#!/usr/bin/env python3
"""Off-chip helpers for Noethrion device provisioning.

These commands operate on **software keys** generated and stored in regular
files. They exist to let an engineer evaluate the protocol primitives without
real hardware. A production deployment binds the signing key to a Common
Criteria EAL5+ secure element (Microchip ATECC608B or equivalent); the key
material never appears outside the silicon. Use Microchip's official tooling
(TrustPLATFORM, atcacert) for real device provisioning under chain of custody.

Subcommands:
  generate-key   Create an ECDSA P-256 private key, save to a PEM file.
  show-pubkey    Print the public key in raw, DER, and hex formats.
  sign-test      Sign a (deviceId, timestamp, wh) tuple to confirm the
                 key + signing path work end-to-end. Outputs JSON.
  export-onchain Emit the uncompressed 64-byte public key (x || y) in hex,
                 the format expected by an on-chain key registry.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import (
    decode_dss_signature,
    encode_dss_signature,
)


# ─────────────────────────────────────────────────────────────────────────────
# I/O helpers
# ─────────────────────────────────────────────────────────────────────────────

def _load_private_key(path: Path) -> ec.EllipticCurvePrivateKey:
    with path.open("rb") as fh:
        key = serialization.load_pem_private_key(fh.read(), password=None)
    if not isinstance(key, ec.EllipticCurvePrivateKey):
        raise SystemExit(f"error: {path} is not an EC private key")
    if not isinstance(key.curve, ec.SECP256R1):
        raise SystemExit(
            f"error: {path} is on curve {key.curve.name}, expected secp256r1 (P-256)"
        )
    return key


def _write_public_key(pub_key: ec.EllipticCurvePublicKey, path: Path) -> None:
    pem = pub_key.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    path.write_bytes(pem)


def _uncompressed_xy_hex(pub_key: ec.EllipticCurvePublicKey) -> str:
    raw = pub_key.public_bytes(
        encoding=serialization.Encoding.X962,
        format=serialization.PublicFormat.UncompressedPoint,
    )
    # X9.62 uncompressed format = 0x04 || x (32B) || y (32B). Drop the 0x04 byte
    # for the on-chain registry, which conventionally stores x || y.
    assert len(raw) == 65 and raw[0] == 0x04
    return raw[1:].hex()


# ─────────────────────────────────────────────────────────────────────────────
# Subcommands
# ─────────────────────────────────────────────────────────────────────────────

def cmd_generate_key(args: argparse.Namespace) -> int:
    out = Path(args.out)
    if out.exists() and not args.force:
        print(
            f"error: {out} already exists. Use --force to overwrite "
            f"(refusing for safety).",
            file=sys.stderr,
        )
        return 1

    private_key = ec.generate_private_key(ec.SECP256R1())

    pem_private = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    out.write_bytes(pem_private)
    # 0600 to discourage casual sharing.
    os.chmod(out, 0o600)

    pub_path = out.with_suffix(out.suffix + ".pub") if out.suffix else out.with_name(out.name + ".pub")
    _write_public_key(private_key.public_key(), pub_path)

    print(f"private key written to {out}    (chmod 600)")
    print(f"public  key written to {pub_path}")
    return 0


def cmd_show_pubkey(args: argparse.Namespace) -> int:
    key_path = Path(args.key)
    if key_path.suffix == ".pub" or args.key.endswith(".pub"):
        with key_path.open("rb") as fh:
            pub_key = serialization.load_pem_public_key(fh.read())
    else:
        pub_key = _load_private_key(key_path).public_key()
    if not isinstance(pub_key, ec.EllipticCurvePublicKey):
        raise SystemExit("error: not an EC public key")

    numbers = pub_key.public_numbers()
    raw_xy = _uncompressed_xy_hex(pub_key)
    der = pub_key.public_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    ).hex()

    print(f"curve     : secp256r1 (P-256)")
    print(f"x         : 0x{numbers.x:064x}")
    print(f"y         : 0x{numbers.y:064x}")
    print(f"raw  (xy) : 0x{raw_xy}")
    print(f"der hex   : {der}")
    return 0


def cmd_sign_test(args: argparse.Namespace) -> int:
    key_path = Path(args.key)
    private_key = _load_private_key(key_path)

    device_id_bytes = bytes.fromhex(args.device_id)
    if len(device_id_bytes) != 9:
        raise SystemExit(
            f"error: --device-id must be 18 hex chars (9 bytes), got {len(device_id_bytes)} bytes"
        )

    # Canonical signing input — keep simple for the test path; the production
    # format is the CBOR-canonical encoding defined in spec/v0.1 Section 4.
    payload = json.dumps(
        {
            "device_id": args.device_id.lower(),
            "timestamp": int(args.timestamp),
            "wh": int(args.wh),
        },
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")

    signature_der = private_key.sign(payload, ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(signature_der)

    # Emit r||s concatenated (64 bytes) — the format on-chain verification
    # libraries typically expect after stripping DER wrapping.
    sig_rs_hex = r.to_bytes(32, "big").hex() + s.to_bytes(32, "big").hex()

    out = {
        "device_id": args.device_id.lower(),
        "timestamp": int(args.timestamp),
        "wh": int(args.wh),
        "payload_b64_canonical": payload.decode("ascii"),
        "signature_rs_hex": sig_rs_hex,
        "signature_der_hex": signature_der.hex(),
        "algorithm": "ES256",
    }
    json.dump(out, sys.stdout, indent=2)
    sys.stdout.write("\n")
    return 0


def cmd_export_onchain(args: argparse.Namespace) -> int:
    key_path = Path(args.key)
    if key_path.suffix == ".pub" or args.key.endswith(".pub"):
        with key_path.open("rb") as fh:
            pub_key = serialization.load_pem_public_key(fh.read())
    else:
        pub_key = _load_private_key(key_path).public_key()
    if not isinstance(pub_key, ec.EllipticCurvePublicKey):
        raise SystemExit("error: not an EC public key")

    raw_xy = _uncompressed_xy_hex(pub_key)
    print(f"0x{raw_xy}")
    return 0


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="provision_atecc.py",
        description="Off-chip key generation and signing helpers (software-only).",
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    g = sub.add_parser("generate-key", help="Generate an ECDSA P-256 private key")
    g.add_argument("--out", required=True, help="Output PEM file path")
    g.add_argument("--force", action="store_true", help="Overwrite existing file")
    g.set_defaults(func=cmd_generate_key)

    s = sub.add_parser("show-pubkey", help="Print the public key in multiple formats")
    s.add_argument("--key", required=True, help="Private (.pem) or public (.pem.pub) key path")
    s.set_defaults(func=cmd_show_pubkey)

    t = sub.add_parser("sign-test", help="Produce a test attestation signature")
    t.add_argument("--key", required=True, help="Private key path")
    t.add_argument("--device-id", required=True, help="9-byte device serial number, hex (18 chars)")
    t.add_argument("--timestamp", required=True, help="Unix seconds")
    t.add_argument("--wh", required=True, help="Energy delta in watt-hours")
    t.set_defaults(func=cmd_sign_test)

    e = sub.add_parser("export-onchain", help="Print the uncompressed (x||y) hex public key")
    e.add_argument("--key", required=True, help="Private or public key path")
    e.set_defaults(func=cmd_export_onchain)

    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
