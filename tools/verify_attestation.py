#!/usr/bin/env python3
"""Standalone Noethrion attestation verifier.

Verifies an attestation token against an endorsed device public key. Optionally
verifies a Merkle inclusion proof against a committed root. On-chain commitment
verification is a future addition (will require a Web3 dependency).

Subcommands:
  verify-signature   Validate the ECDSA P-256 signature on an attestation.
  verify-merkle      Validate a Merkle inclusion proof against a known root.
  verify-full        Both of the above in one call.
  compute-leaf       Compute the on-chain claim-record leaf hash from
                     (chain-id, attester-address, beneficiary, amount, epoch).
                     Output is suitable to pass as --leaf to verify-merkle.

Exit codes:
  0  all checks passed
  1  cryptographic verification failed
  2  malformed input or usage error
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature


# ─────────────────────────────────────────────────────────────────────────────
# Loaders
# ─────────────────────────────────────────────────────────────────────────────

def _load_attestation(path: Path) -> dict:
    try:
        with path.open("r", encoding="utf-8") as fh:
            obj = json.load(fh)
    except json.JSONDecodeError as e:
        raise SystemExit(f"error: {path} is not valid JSON: {e}")
    required = {"payload_b64_canonical", "signature_rs_hex", "algorithm"}
    missing = required - obj.keys()
    if missing:
        raise SystemExit(f"error: attestation missing required fields: {sorted(missing)}")
    if obj["algorithm"] != "ES256":
        raise SystemExit(
            f"error: unsupported algorithm {obj['algorithm']!r}; only ES256 is implemented in v0.1"
        )
    return obj


def _load_pubkey(path: Path) -> ec.EllipticCurvePublicKey:
    with path.open("rb") as fh:
        data = fh.read()
    try:
        pub_key = serialization.load_pem_public_key(data)
    except ValueError:
        raise SystemExit(f"error: could not parse public key from {path}")
    if not isinstance(pub_key, ec.EllipticCurvePublicKey):
        raise SystemExit(f"error: {path} is not an EC public key")
    if not isinstance(pub_key.curve, ec.SECP256R1):
        raise SystemExit(
            f"error: {path} is on curve {pub_key.curve.name}, expected secp256r1 (P-256)"
        )
    return pub_key


# ─────────────────────────────────────────────────────────────────────────────
# Verifications
# ─────────────────────────────────────────────────────────────────────────────

def _verify_signature(att: dict, pub_key: ec.EllipticCurvePublicKey) -> tuple[bool, str]:
    payload = att["payload_b64_canonical"].encode("utf-8")
    sig_hex = att["signature_rs_hex"]
    try:
        sig_bytes = bytes.fromhex(sig_hex)
    except ValueError:
        return False, "signature_rs_hex is not valid hex"
    if len(sig_bytes) != 64:
        return False, f"signature_rs_hex must be 64 bytes (got {len(sig_bytes)})"
    r = int.from_bytes(sig_bytes[:32], "big")
    s = int.from_bytes(sig_bytes[32:], "big")
    der = encode_dss_signature(r, s)
    try:
        pub_key.verify(der, payload, ec.ECDSA(hashes.SHA256()))
    except InvalidSignature:
        return False, "ECDSA signature did NOT validate against the supplied public key"
    return True, "ECDSA P-256 signature OK"


def _verify_merkle_proof_impl(
    leaf_hex: str,
    proof_hex: list[str],
    root_hex: str,
    hash_alg: str,
) -> tuple[bool, str]:
    def _to_bytes(label: str, h: str) -> bytes:
        h = h.lower().removeprefix("0x")
        try:
            b = bytes.fromhex(h)
        except ValueError:
            raise SystemExit(f"error: {label} is not valid hex: {h!r}")
        if len(b) != 32:
            raise SystemExit(f"error: {label} must be 32 bytes (got {len(b)})")
        return b

    leaf = _to_bytes("leaf", leaf_hex)
    root = _to_bytes("root", root_hex)
    proof = [_to_bytes(f"proof[{i}]", p) for i, p in enumerate(proof_hex)]

    if hash_alg == "sha256":
        H = lambda b: hashlib.sha256(b).digest()
    elif hash_alg == "keccak256":
        try:
            from Crypto.Hash import keccak  # type: ignore
            def H(b: bytes) -> bytes:
                k = keccak.new(digest_bits=256)
                k.update(b)
                return k.digest()
        except ImportError:
            # Fallback for environments without pycryptodome — try hashlib's
            # SHA-3 (NOT identical to Ethereum keccak256, hence error if used).
            raise SystemExit(
                "error: --hash keccak256 requires pycryptodome (pip install pycryptodome).\n"
                "       Note: hashlib.sha3_256 is NIST SHA-3, NOT Ethereum keccak256."
            )
    else:
        raise SystemExit(f"error: unknown --hash {hash_alg!r}; use sha256 or keccak256")

    computed = leaf
    for sibling in proof:
        # OpenZeppelin's commutative pair-hash: sort the pair first.
        a, b = (computed, sibling) if computed < sibling else (sibling, computed)
        computed = H(a + b)
    return (computed == root,
            "Merkle proof OK"
            if computed == root
            else f"Merkle root mismatch: computed {computed.hex()} != expected {root.hex()}")


# ─────────────────────────────────────────────────────────────────────────────
# Leaf encoding — the v0.2 contract's claim-record domain-separated leaf.
#
# leaf = keccak256(abi.encode(
#     uint256 chain_id,
#     address attester_contract,
#     address beneficiary,
#     uint128 amount,
#     uint64  epoch
# ))
#
# The first two fields are the domain separator binding each leaf to a
# specific Attester instance on a specific chain — a Merkle tree built for
# one Attester is byte-different from a leaf with the same
# (beneficiary, amount, epoch) on any sibling deployment.
# ─────────────────────────────────────────────────────────────────────────────

def _addr_to_32(addr_hex: str, label: str) -> bytes:
    raw = addr_hex.removeprefix("0x")
    if len(raw) != 40:
        raise SystemExit(f"error: {label} must be 20 bytes / 40 hex chars: {addr_hex!r}")
    # A typo in a mixed-case (EIP-55 checksum) address silently produces a
    # wrong-but-well-formed leaf. Warn — don't fail — when the caller passed
    # a mixed-case address whose checksum does not validate. All-lowercase
    # and all-uppercase inputs skip the check (they're conventionally
    # treated as "explicitly opting out of checksum validation").
    has_upper = any(c.isupper() for c in raw)
    has_lower = any(c.islower() for c in raw)
    if has_upper and has_lower:
        try:
            from Crypto.Hash import keccak as _keccak  # type: ignore
            kh = _keccak.new(digest_bits=256)
            kh.update(raw.lower().encode("ascii"))
            digest = kh.hexdigest()
            expected = "".join(
                ch.upper() if int(digest[i], 16) >= 8 else ch.lower()
                for i, ch in enumerate(raw.lower())
            )
            if expected != raw:
                print(
                    f"warning: {label} {addr_hex!r} has a mixed-case form whose EIP-55 "
                    f"checksum does not validate; expected {('0x' + expected)!r}. "
                    "Continuing with the address as supplied — if the leaf-hash mismatch "
                    "downstream, retype the address.",
                    file=sys.stderr,
                )
        except ImportError:
            pass
    addr_clean = raw.lower()
    try:
        return b"\x00" * 12 + bytes.fromhex(addr_clean)
    except ValueError as e:
        raise SystemExit(f"error: {label} is not valid hex: {e}")


def _compute_leaf_impl(
    chain_id: int, attester_address: str, beneficiary: str, amount_wei: int, epoch: int
) -> bytes:
    if chain_id < 0 or chain_id >= 1 << 256:
        raise SystemExit(f"error: chain_id out of uint256 range: {chain_id}")
    if amount_wei < 0 or amount_wei >= 1 << 128:
        raise SystemExit(f"error: amount_wei out of uint128 range: {amount_wei}")
    if epoch < 0 or epoch >= 1 << 64:
        raise SystemExit(f"error: epoch out of uint64 range: {epoch}")
    try:
        from Crypto.Hash import keccak  # type: ignore
    except ImportError:
        raise SystemExit(
            "error: compute-leaf requires pycryptodome (pip install pycryptodome).\n"
            "       Note: hashlib.sha3_256 is NIST SHA-3, NOT Ethereum keccak256."
        )
    encoded = chain_id.to_bytes(32, "big")
    encoded += _addr_to_32(attester_address, "attester_address")
    encoded += _addr_to_32(beneficiary, "beneficiary")
    encoded += amount_wei.to_bytes(32, "big")
    encoded += epoch.to_bytes(32, "big")
    k = keccak.new(digest_bits=256)
    k.update(encoded)
    return k.digest()


# ─────────────────────────────────────────────────────────────────────────────
# Subcommands
# ─────────────────────────────────────────────────────────────────────────────

def cmd_verify_signature(args: argparse.Namespace) -> int:
    att = _load_attestation(Path(args.attestation))
    pub_key = _load_pubkey(Path(args.pubkey))
    ok, msg = _verify_signature(att, pub_key)
    print(("PASS  " if ok else "FAIL  ") + msg)
    return 0 if ok else 1


def cmd_verify_merkle(args: argparse.Namespace) -> int:
    proof = []
    if args.proof:
        if args.proof.endswith(".json"):
            with open(args.proof, "r", encoding="utf-8") as fh:
                data = json.load(fh)
            if not isinstance(data, list):
                raise SystemExit(f"error: {args.proof} must contain a JSON array of hex strings")
            proof = data
        else:
            proof = [p.strip() for p in args.proof.split(",") if p.strip()]
    ok, msg = _verify_merkle_proof_impl(args.leaf, proof, args.root, args.hash)
    print(("PASS  " if ok else "FAIL  ") + msg)
    return 0 if ok else 1


def cmd_verify_full(args: argparse.Namespace) -> int:
    sig_rc = cmd_verify_signature(args)
    if sig_rc != 0:
        return sig_rc
    return cmd_verify_merkle(args)


def cmd_compute_leaf(args: argparse.Namespace) -> int:
    leaf = _compute_leaf_impl(
        args.chain_id, args.attester, args.beneficiary, args.amount, args.epoch
    )
    print("0x" + leaf.hex())
    return 0


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="verify_attestation.py",
        description="Verify a Noethrion attestation token (signature and/or Merkle proof).",
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("verify-signature", help="Verify ECDSA P-256 signature only")
    s.add_argument("--attestation", required=True, help="Path to attestation JSON")
    s.add_argument("--pubkey", required=True, help="Path to device public key PEM")
    s.set_defaults(func=cmd_verify_signature)

    m = sub.add_parser("verify-merkle", help="Verify Merkle inclusion proof only")
    m.add_argument("--leaf", required=True, help="32-byte hex leaf hash (0x-prefix optional)")
    m.add_argument("--root", required=True, help="32-byte hex Merkle root")
    m.add_argument("--proof", default="", help="Comma-separated hex siblings OR path to JSON array file")
    m.add_argument(
        "--hash",
        default="keccak256",
        choices=["keccak256", "sha256"],
        help="Pair hash algorithm (default: keccak256 — matches on-chain Solidity)",
    )
    m.set_defaults(func=cmd_verify_merkle)

    f = sub.add_parser("verify-full", help="Verify signature AND Merkle inclusion")
    f.add_argument("--attestation", required=True)
    f.add_argument("--pubkey", required=True)
    f.add_argument("--leaf", required=True)
    f.add_argument("--root", required=True)
    f.add_argument("--proof", default="")
    f.add_argument("--hash", default="keccak256", choices=["keccak256", "sha256"])
    f.set_defaults(func=cmd_verify_full)

    cl = sub.add_parser(
        "compute-leaf",
        help="Compute the on-chain claim-record leaf hash for a (chain, attester, beneficiary, amount, epoch) tuple",
    )
    cl.add_argument("--chain-id", type=int, required=True, dest="chain_id",
                    help="Chain ID the Attester is deployed on (e.g., 1 for Ethereum mainnet, 31337 for Anvil)")
    cl.add_argument("--attester", required=True,
                    help="Deployed NoethrionAttester contract address (0x-prefixed, 20 bytes)")
    cl.add_argument("--beneficiary", required=True,
                    help="Beneficiary address from the leaf (0x-prefixed, 20 bytes)")
    cl.add_argument("--amount", type=int, required=True,
                    help="Amount in wei (uint128, fits in 128 bits)")
    cl.add_argument("--epoch", type=int, required=True, help="Batch epoch (uint64)")
    cl.set_defaults(func=cmd_compute_leaf)

    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
