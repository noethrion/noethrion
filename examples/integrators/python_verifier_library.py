"""Noethrion attestation verifier — Python library shape.

A minimal, dependency-light wrapper around the primitives in
`tools/verify_attestation.py`. Designed to be imported into a Python service
(Django, FastAPI, Flask, Celery, plain script) without bringing along any CLI.

Usage:

    from noethrion_verifier import NoethrionVerifier, VerificationResult

    verifier = NoethrionVerifier(public_key_pem=open("attester.key.pub", "rb").read())
    result = verifier.verify(
        attestation=json.load(open("attestation.json")),
        merkle_root=bytes.fromhex("abc..."),
        merkle_proof=[bytes.fromhex("def..."), bytes.fromhex("123...")],
        chain_id=1,                                                 # the chain the Attester is deployed on
        attester_address="0x...",                                   # the deployed NoethrionAttester contract address
        beneficiary="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
        amount_wei=100 * 10**18,
        epoch=1,
    )
    if result.ok:
        print("attestation verified — beneficiary may receive credit")
    else:
        log.warning("verification failed: %s", result.reason)

The class is stateless after construction; thread-safe; re-entrant. No I/O
beyond what the caller provides.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature

try:
    from Crypto.Hash import keccak  # type: ignore
except ImportError as e:
    raise ImportError(
        "pycryptodome is required for keccak256. Install with: pip install pycryptodome"
    ) from e


# ─────────────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class VerificationResult:
    ok: bool
    reason: str

    def __bool__(self) -> bool:
        return self.ok


class NoethrionVerifier:
    """Stateless verifier bound to a single device public key.

    Construct one instance per device key you care about. Re-use across requests.
    """

    __slots__ = ("_pub_key",)

    def __init__(self, public_key_pem: bytes) -> None:
        pub = serialization.load_pem_public_key(public_key_pem)
        if not isinstance(pub, ec.EllipticCurvePublicKey):
            raise ValueError("public key is not an EC key")
        if not isinstance(pub.curve, ec.SECP256R1):
            raise ValueError("public key is not on secp256r1 (P-256)")
        self._pub_key = pub

    # ── Signature only ──────────────────────────────────────────────────────

    def verify_signature(self, attestation: dict) -> VerificationResult:
        try:
            # Field contains raw canonical JSON, not base64 — naming kept for
            # v0.1 wire-format compatibility.
            payload = attestation["payload_b64_canonical"].encode("utf-8")
            sig_bytes = bytes.fromhex(attestation["signature_rs_hex"])
        except (KeyError, ValueError) as e:
            return VerificationResult(False, f"malformed attestation: {e}")
        if len(sig_bytes) != 64:
            return VerificationResult(False, "signature must be 64 raw bytes (r||s)")
        r = int.from_bytes(sig_bytes[:32], "big")
        s = int.from_bytes(sig_bytes[32:], "big")
        try:
            self._pub_key.verify(
                encode_dss_signature(r, s),
                payload,
                ec.ECDSA(hashes.SHA256()),
            )
        except InvalidSignature:
            return VerificationResult(False, "ECDSA P-256 signature did not validate")
        return VerificationResult(True, "signature OK")

    # ── Merkle inclusion only ───────────────────────────────────────────────

    @staticmethod
    def verify_merkle(
        chain_id: int,
        attester_address: str,
        beneficiary: str,
        amount_wei: int,
        epoch: int,
        proof: Iterable[bytes],
        expected_root: bytes,
    ) -> VerificationResult:
        if len(expected_root) != 32:
            return VerificationResult(False, "expected_root must be 32 bytes")
        leaf = _compute_leaf(chain_id, attester_address, beneficiary, amount_wei, epoch)
        computed = leaf
        for sibling in proof:
            if len(sibling) != 32:
                return VerificationResult(False, "proof sibling not 32 bytes")
            computed = _hash_pair(computed, sibling)
        if computed != expected_root:
            return VerificationResult(
                False,
                f"merkle root mismatch: derived {computed.hex()} expected {expected_root.hex()}",
            )
        return VerificationResult(True, "merkle inclusion OK")

    # ── Full check (signature + merkle) ─────────────────────────────────────

    def verify(
        self,
        attestation: dict,
        merkle_root: bytes,
        merkle_proof: Iterable[bytes],
        chain_id: int,
        attester_address: str,
        beneficiary: str,
        amount_wei: int,
        epoch: int,
    ) -> VerificationResult:
        sig = self.verify_signature(attestation)
        if not sig.ok:
            return sig
        return self.verify_merkle(
            chain_id, attester_address, beneficiary, amount_wei, epoch, merkle_proof, merkle_root
        )


# ─────────────────────────────────────────────────────────────────────────────
# Internals
# ─────────────────────────────────────────────────────────────────────────────

def _keccak256(data: bytes) -> bytes:
    h = keccak.new(digest_bits=256)
    h.update(data)
    return h.digest()


def _hash_pair(a: bytes, b: bytes) -> bytes:
    return _keccak256(a + b) if a < b else _keccak256(b + a)


def _addr_to_32(addr_hex: str, label: str = "address") -> bytes:
    addr_clean = addr_hex.lower().removeprefix("0x")
    if len(addr_clean) != 40:
        raise ValueError(f"{label} must be 20 bytes / 40 hex chars: {addr_hex!r}")
    return b"\x00" * 12 + bytes.fromhex(addr_clean)


def _compute_leaf(
    chain_id: int,
    attester_address: str,
    beneficiary: str,
    amount_wei: int,
    epoch: int,
) -> bytes:
    # Mirror Solidity abi.encode(uint256, address, address, uint128, uint64):
    #   uint256 chain_id          → 32 bytes big-endian
    #   address attester contract → 32 bytes (12 zero bytes + 20 address bytes)
    #   address beneficiary       → 32 bytes (12 zero bytes + 20 address bytes)
    #   uint128 amount_wei        → 32 bytes big-endian
    #   uint64  epoch             → 32 bytes big-endian
    # The first two fields are the domain separator binding each leaf to a
    # specific Attester instance on a specific chain — a Merkle tree built
    # for one deployment is byte-different from a leaf with identical
    # (beneficiary, amount, epoch) on any sibling deployment.
    encoded = chain_id.to_bytes(32, "big")
    encoded += _addr_to_32(attester_address, "attester_address")
    encoded += _addr_to_32(beneficiary, "beneficiary")
    encoded += amount_wei.to_bytes(32, "big")
    encoded += epoch.to_bytes(32, "big")
    return _keccak256(encoded)
