# `tools/` — Helper scripts for protocol bring-up

Reference utilities (Python CLIs + shell runners) that complement the smart contracts and firmware. They are not part of the on-chain trust boundary — anyone is expected to write their own implementations from the specification — but they let an engineer evaluating the protocol exercise its primitives in minutes rather than days.

## Inventory

| Script | Purpose |
|--------|---------|
| [`provision_atecc.py`](./provision_atecc.py) | Off-chip helpers for ECDSA P-256 key generation, public-key export, and test signatures. Pure-software counterpart to a physical ATECC608B provisioning ceremony. |
| [`verify_attestation.py`](./verify_attestation.py) | Standalone signature and Merkle-inclusion verifier. Reads an attestation token + proof and an endorsed public key, returns pass/fail with reasons. Includes `compute-leaf` for the on-chain claim-record leaf encoding. |
| [`run_lifecycle.sh`](./run_lifecycle.sh) | End-to-end lifecycle smoke test against a freshly started Anvil instance: deploy → propose → vote → finalize → claim → off-chain re-verify. Used by CI on every push. |
| [`genesis.sh`](./genesis.sh) | Testnet sibling of `run_lifecycle.sh` — drives one full attestation lifecycle against a public testnet (e.g. Sepolia), waiting the real challenge window. Testnet-only by design; requires a disposable zero-value key. |
| [`render_social_assets.py`](./render_social_assets.py) | Renders social/announcement image assets from the brand SVG sources (requires Pillow). Not protocol-related. |

`provision_atecc.py` depends only on the [`cryptography`](https://cryptography.io/) library plus Python 3.10+ stdlib. `verify_attestation.py` additionally requires [`pycryptodome`](https://pypi.org/project/pycryptodome/) for EVM `keccak256` — the default pair hash for Merkle verification and `compute-leaf` (Python stdlib's `hashlib.sha3_256` is NIST SHA-3, a different padding). Both dependencies are pinned in [`requirements.txt`](./requirements.txt). The shell runners additionally need Foundry (`anvil`, `cast`, `forge`).

## Install

```bash
cd tools/
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Quick walkthrough

```bash
# 1. Generate a software key pair (for testing — production keys live in
#    the secure element and never leave the silicon).
python3 provision_atecc.py generate-key --out test-device.key

# 2. Print the public key in formats useful for on-chain registration.
python3 provision_atecc.py show-pubkey --key test-device.key

# 3. Sign a sample attestation tuple.
python3 provision_atecc.py sign-test --key test-device.key \
    --wh 1234 --timestamp 1746956400 --device-id 0123456789ABCDEF12 \
    > attestation.json

# 4. Verify the signature in isolation.
python3 verify_attestation.py verify-signature \
    --attestation attestation.json \
    --pubkey test-device.key.pub
```

If the four commands above all succeed, the basic protocol primitives are working end-to-end on your machine.

## What these scripts intentionally do NOT do

- **Drive real hardware.** A production ATECC608B provisioning ceremony requires Microchip's official tooling (`atcacert`, TrustPLATFORM, or equivalent) under chain-of-custody guarantees. These scripts are a software-only stand-in.
- **Talk to a real blockchain (Python CLIs).** On-chain commitment verification (Section 6.3 of the spec) is out of scope for the Python verifiers; a thin Web3 wrapper is planned. The on-chain path is covered by the shell runners — `run_lifecycle.sh` (local Anvil) and `genesis.sh` (public testnet) — via Foundry tooling.
- **Decide endorsement trust.** The endorser registry layer (Section 7 of the spec) is operational policy, not crypto — these scripts only verify signatures against a public key you provide.

## See also

- [`../spec/noethrion-attestation-v0.1.md`](../spec/noethrion-attestation-v0.1.md) — protocol specification (normative).
- [`../firmware/`](../firmware/) — reference device-side implementation.
- [`../contracts/`](../contracts/) — reference on-chain contracts.
