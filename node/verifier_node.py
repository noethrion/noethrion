#!/usr/bin/env python3
"""Noethrion independent verifier node (v0.1).

A standalone watchdog that anyone can run to verify the Noethrion protocol
WITHOUT trusting the operator. It watches a deployed Attester, and for every
*finalized* batch it independently:

  1. reads the on-chain committed `merkleRoot` from `batches(epoch)`,
  2. loads the operator-published batch data (the same `batch.json` the lifecycle
     tooling produces) for that epoch,
  3. confirms the published root matches the on-chain root,
  4. re-derives every leaf as
        keccak256(abi.encode(chainId, attesterAddr, beneficiary, amount, epoch))
     — the exact encoding the contract enforces in claim() — and replays the
     Merkle proof against the on-chain root,
  5. (when the attestation + device public key are published) re-verifies the
     ECDSA P-256 signature on the underlying attestation.

If anything does not reconcile, the node raises an ALARM (non-zero exit in
--once mode; logged + alarm counter in daemon mode). This is the "don't trust
us, verify it yourself" component — the trust-minimizing core of the network.

Scope v0.1: chain + signatures. Consumption-matching (generation↔spend) is a
future version and intentionally NOT here.

Reuses the verification engine in ../tools/verify_attestation.py (single source
of truth) rather than reimplementing crypto.

Usage:
    pip install -r node/requirements.txt
    python3 node/verifier_node.py \
        --rpc        https://sepolia.infura.io/v3/<key> \
        --attester   0xATTESTER... \
        --chain-id   11155111 \
        --data-dir   ./published \
        --once                      # single pass; omit for a continuous daemon

The --data-dir holds, per epoch, the operator-published files:
    <data-dir>/batch.json            (or batch-<epoch>.json)   — required
    <data-dir>/attestation.json      (optional — enables signature check)
    <data-dir>/attester.key.pub      (optional — device public key for sig check)

Exit codes (in --once mode): 0 all verified, 1 ALARM (mismatch), 2 usage error.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from json import JSONDecodeError
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
# Reuse the audited verification engine rather than reimplementing crypto.
sys.path.insert(0, str(REPO / "tools"))
import verify_attestation as va  # noqa: E402

try:
    from web3 import Web3
    from eth_abi import encode as abi_encode
except ImportError:  # pragma: no cover
    sys.stderr.write(
        "error: web3 not installed. Run: pip install -r node/requirements.txt\n"
    )
    raise SystemExit(2)


# Minimal ABI: the public `batches(uint64)` getter returns the full
# AttestationBatch struct in declaration order, plus the BatchFinalized event.
ATTESTER_ABI = [
    {
        "type": "function",
        "name": "batches",
        "stateMutability": "view",
        "inputs": [{"name": "epoch", "type": "uint64"}],
        "outputs": [
            {"name": "merkleRoot", "type": "bytes32"},
            {"name": "epoch", "type": "uint64"},
            {"name": "totalKwh", "type": "uint128"},
            {"name": "timestamp", "type": "uint64"},
            {"name": "proposer", "type": "address"},
            {"name": "finalized", "type": "bool"},
            {"name": "thresholdAtPropose", "type": "uint64"},
            {"name": "challengeWindowAtPropose", "type": "uint64"},
        ],
    },
]


def log(level: str, msg: str) -> None:
    print(f"[{level}] {msg}", flush=True)


def compute_leaf(chain_id: int, attester: str, beneficiary: str, amount: int, epoch: int) -> str:
    """Re-derive the on-chain leaf exactly as NoethrionAttester.claim() does:
    keccak256(abi.encode(uint256 chainId, address attester, address beneficiary,
                         uint128 amount, uint64 epoch)).
    """
    enc = abi_encode(
        ["uint256", "address", "address", "uint128", "uint64"],
        [
            int(chain_id),
            Web3.to_checksum_address(attester),
            Web3.to_checksum_address(beneficiary),
            int(amount),
            int(epoch),
        ],
    )
    h = Web3.keccak(enc).hex()
    return h if h.startswith("0x") else "0x" + h


class MalformedBatch(Exception):
    """A published batch file exists for this epoch but is unparseable/garbage.

    Distinct from 'no file at all'. On a FINALIZED epoch this is fail-closed:
    the operator published *something* for this epoch but it cannot be verified,
    which is indistinguishable from tampering — caller must ALARM, never SKIP.
    """


def _load_batch_file(data_dir: Path, epoch: int) -> dict | None:
    """Published merkle data for an epoch. Accepts batch-<epoch>.json or batch.json.

    Returns the parsed dict, or None if no batch file is present for this epoch.
    Raises MalformedBatch if a candidate file exists but is not valid JSON, is
    not an object, or its `epoch` field is non-numeric — these are NOT the same
    as 'absent', and on a finalized epoch must be alarmed on, not silently
    skipped.
    """
    for name in (f"batch-{epoch}.json", "batch.json"):
        p = data_dir / name
        if not p.exists():
            continue
        try:
            with p.open("r", encoding="utf-8") as fh:
                obj = json.load(fh)
        except (JSONDecodeError, OSError, UnicodeDecodeError) as e:
            raise MalformedBatch(f"{p.name} is present but not readable/valid JSON: {e}")
        if not isinstance(obj, dict):
            raise MalformedBatch(f"{p.name} is present but is not a JSON object")
        # batch.json is single-epoch; only accept it if its epoch matches.
        try:
            file_epoch = int(obj.get("epoch", -1))
        except (TypeError, ValueError):
            raise MalformedBatch(f"{p.name} has a non-numeric `epoch` field")
        if file_epoch == epoch:
            return obj
        # A batch-<epoch>.json whose internal epoch disagrees with its filename
        # is corrupt/mislabeled; for the generic batch.json a mismatch just
        # means "this single-epoch file is for a different epoch" → keep looking.
        if name == f"batch-{epoch}.json":
            raise MalformedBatch(
                f"{p.name} is named for epoch {epoch} but its `epoch` field is {file_epoch}"
            )
    return None


def verify_epoch(w3, attester_addr: str, chain_id: int, epoch: int, data_dir: Path) -> tuple[str, list[str]]:
    """Verify one finalized epoch. Returns (status, details) where status is one
    of 'OK', 'ALARM', 'SKIP' (not finalized / no published data yet).

    FAIL-CLOSED contract: once an epoch is FINALIZED on-chain, *any* problem
    reconciling the operator-published data against the on-chain commitment —
    a mismatch, a forgery, OR merely garbage/malformed/missing-field data we
    cannot parse — yields ALARM, never a silent OK and never a SKIP. Garbage
    on a finalized epoch is treated as adversarial (an operator could hide
    tampering behind 'unparseable' data). Only genuinely-absent published data
    on a not-yet-finalized epoch is a SKIP.
    """
    contract = w3.eth.contract(
        address=Web3.to_checksum_address(attester_addr), abi=ATTESTER_ABI
    )
    # On-chain read: connectivity / RPC errors are NOT forgery; let them
    # propagate to the daemon loop, which treats them as transient (logs +
    # retries), rather than mislabeling a flaky RPC as a protocol violation.
    b = contract.functions.batches(epoch).call()
    merkle_root_onchain = "0x" + b[0].hex() if isinstance(b[0], (bytes, bytearray)) else b[0]
    timestamp = b[3]
    finalized = b[5]

    if timestamp == 0:
        return "SKIP", [f"epoch {epoch}: not proposed yet"]
    if not finalized:
        return "SKIP", [f"epoch {epoch}: proposed but not finalized yet"]

    # From here the epoch is FINALIZED — fail closed on ANY data problem.
    try:
        return _verify_finalized_epoch(
            attester_addr, chain_id, epoch, data_dir, merkle_root_onchain
        )
    except _AbsentData as e:
        # The one not-adversarial case: the operator has not yet published the
        # batch data for a freshly-finalized epoch. Surfaced as SKIP so the
        # daemon retries; in --once mode this is a clean "nothing to verify".
        return "SKIP", [f"epoch {epoch}: {e}"]
    except MalformedBatch as e:
        return "ALARM", [
            f"epoch {epoch}: FINALIZED on-chain but published batch data is malformed — {e}"
        ]
    except SystemExit as e:
        # The reused crypto engine (tools/verify_attestation.py) signals
        # malformed input by raising SystemExit. On a finalized epoch that is
        # attacker-controlled garbage, not a reason to terminate the watchdog:
        # convert it to an ALARM and keep running.
        return "ALARM", [
            f"epoch {epoch}: FINALIZED on-chain but verification engine rejected the "
            f"published data as malformed — {e}"
        ]
    except (KeyError, TypeError, ValueError, JSONDecodeError, AttributeError) as e:
        # Missing fields, wrong types, bad hex, non-numeric amounts, etc. on a
        # finalized epoch are all fail-closed ALARMs, not crashes.
        return "ALARM", [
            f"epoch {epoch}: FINALIZED on-chain but published data could not be parsed "
            f"({type(e).__name__}: {e}) — treating as a verification failure"
        ]


class _AbsentData(Exception):
    """No operator-published data exists yet for a finalized epoch (benign-ish:
    the publisher may simply be lagging the chain). Surfaced as SKIP."""


def _verify_finalized_epoch(
    attester_addr: str, chain_id: int, epoch: int, data_dir: Path, merkle_root_onchain: str
) -> tuple[str, list[str]]:
    """The data-reconciliation core for an already-finalized epoch. Raises on
    any malformed/missing data; the caller maps those to ALARM/SKIP."""
    details: list[str] = []
    batch = _load_batch_file(data_dir, epoch)
    if batch is None:
        # On-chain says finalized but the operator published no data at all.
        # We deliberately treat this as ABSENT (SKIP/retry) rather than ALARM:
        # the publisher legitimately lags finalization. A persistent absence
        # will keep re-SKIPping every tick, which is visible without crying
        # forgery on a timing gap.
        raise _AbsentData(
            f"FINALIZED on-chain but no published batch data in {data_dir} yet — "
            "cannot verify (publisher may be lagging; will retry)"
        )

    # 1. Published root must equal the on-chain committed root.
    raw_root = batch.get("root")
    if not isinstance(raw_root, str) or not raw_root.strip():
        raise MalformedBatch("batch is missing a usable `root` field")
    published_root = raw_root.strip().lower()
    if not published_root.startswith("0x"):
        published_root = "0x" + published_root
    if published_root != merkle_root_onchain.lower():
        return "ALARM", [
            f"epoch {epoch}: published root {published_root} != on-chain root {merkle_root_onchain}"
        ]
    details.append(f"epoch {epoch}: published root matches on-chain root {merkle_root_onchain}")

    # 2. Every leaf re-derives correctly and its Merkle proof replays to the root.
    leaves = batch.get("leaves", [])
    if not isinstance(leaves, list):
        raise MalformedBatch("`leaves` is present but is not a JSON array")
    for i, lf in enumerate(leaves):
        if not isinstance(lf, dict):
            raise MalformedBatch(f"leaf[{i}] is not a JSON object")
        if "beneficiary" not in lf:
            raise MalformedBatch(f"leaf[{i}] is missing `beneficiary`")
        beneficiary = lf["beneficiary"]
        raw_amount = lf.get("amount_wei", lf.get("amount"))
        if raw_amount is None:
            raise MalformedBatch(f"leaf[{i}] is missing both `amount_wei` and `amount`")
        # int() of a garbage string / wrong type raises ValueError/TypeError,
        # which the caller maps to ALARM (fail closed on non-numeric amounts).
        amount = int(raw_amount)
        # compute_leaf checksums the addresses; a malformed beneficiary raises
        # (ValueError) and is mapped to ALARM by the caller.
        recomputed = compute_leaf(chain_id, attester_addr, beneficiary, amount, epoch)
        claimed_raw = lf.get("leaf")
        if not isinstance(claimed_raw, str) or not claimed_raw.strip():
            raise MalformedBatch(f"leaf[{i}] ({beneficiary}) is missing a usable `leaf` hash")
        claimed_leaf = claimed_raw.strip().lower()
        if not claimed_leaf.startswith("0x"):
            claimed_leaf = "0x" + claimed_leaf
        if recomputed.lower() != claimed_leaf:
            return "ALARM", [
                f"epoch {epoch} leaf[{i}] ({beneficiary}): recomputed {recomputed} != published {claimed_leaf}"
            ]
        proof = lf.get("proof", [])
        if not isinstance(proof, list):
            raise MalformedBatch(f"leaf[{i}] ({beneficiary}) has a `proof` that is not a JSON array")
        ok, m = va._verify_merkle_proof_impl(recomputed, proof, merkle_root_onchain, "keccak256")
        if not ok:
            return "ALARM", [f"epoch {epoch} leaf[{i}] ({beneficiary}): Merkle proof FAILED — {m}"]
    details.append(f"epoch {epoch}: all {len(leaves)} leaf(s) re-derived + Merkle-verified against on-chain root")

    # 3. Signature check. If the operator publishes BOTH attestation + pubkey,
    #    the signature MUST validate (fail closed — a present-but-invalid sig is
    #    an ALARM). Only the genuine absence of either file is a clean skip.
    att_path = data_dir / "attestation.json"
    pub_path = data_dir / "attester.key.pub"
    att_present = att_path.exists()
    pub_present = pub_path.exists()
    if att_present and pub_present:
        # _load_attestation / _load_pubkey raise SystemExit on malformed
        # material; the caller maps that to ALARM rather than letting it kill
        # the watchdog.
        att = va._load_attestation(att_path)
        pub = va._load_pubkey(pub_path)
        ok, m = va._verify_signature(att, pub)
        if not ok:
            return "ALARM", [f"epoch {epoch}: attestation signature FAILED — {m}"]
        details.append(f"epoch {epoch}: attestation P-256 signature OK")
    elif att_present or pub_present:
        # Exactly one of the two present: fail closed (mirrors the Go node). An
        # operator must not be able to publish an attestation while withholding
        # the pubkey (or vice versa) to dodge the signature check.
        missing = "attester.key.pub" if att_present else "attestation.json"
        return "ALARM", [
            f"epoch {epoch}: signature material is half-published ({missing} missing) — refusing to skip"
        ]
    else:
        details.append(f"epoch {epoch}: no attestation/pubkey published — signature check skipped (chain checks still passed)")

    return "OK", details


def run(args: argparse.Namespace) -> int:
    w3 = Web3(Web3.HTTPProvider(args.rpc))
    if not w3.is_connected():
        log("ERROR", f"cannot connect to RPC {args.rpc}")
        return 2
    log("INFO", f"connected: chainId={args.chain_id} attester={args.attester} data-dir={args.data_dir}")

    data_dir = Path(args.data_dir)
    epoch = args.start_epoch
    last_verified = None
    alarms = 0

    while True:
        try:
            status, details = verify_epoch(w3, args.attester, args.chain_id, epoch, data_dir)
        except SystemExit:
            # Defensive: any SystemExit that somehow escapes verify_epoch must
            # NOT take the watchdog down. (verify_epoch already converts engine
            # SystemExit on finalized epochs to ALARM; this catches the rest.)
            log("ALARM", f"epoch {epoch}: verification raised SystemExit — treated as failure, continuing")
            status, details = "ALARM", [f"epoch {epoch}: SystemExit during verification"]
        except KeyboardInterrupt:
            raise
        except Exception as e:  # noqa: BLE001 — watchdog must never die on a tick
            # RPC/connectivity/decoding errors on the on-chain read are
            # transient, not forgery. Log and retry (in --once mode, report a
            # usage/connectivity skip without claiming verification success).
            log("ERROR", f"epoch {epoch}: transient error during verification ({type(e).__name__}: {e})")
            if args.once:
                log("INFO", f"--once: could not complete verification at epoch {epoch}; last_verified_epoch={last_verified}")
                return 1 if alarms else 2
            time.sleep(args.interval)
            continue
        for d in details:
            log("INFO" if status != "ALARM" else "ALARM", d)
        if status == "OK":
            last_verified = epoch
            log("OK", f"epoch {epoch} fully verified · last_verified_epoch={last_verified}")
            epoch += 1
            continue
        if status == "ALARM":
            alarms += 1
            log("ALARM", f"*** VERIFICATION FAILED at epoch {epoch} · total_alarms={alarms} ***")
            if args.once:
                return 1
            # In daemon mode: do not advance past a bad epoch; re-check next tick.
        # SKIP: no new finalized epoch yet.
        if args.once:
            log("INFO", f"--once: nothing new to verify at epoch {epoch}; last_verified_epoch={last_verified}")
            return 1 if alarms else 0
        time.sleep(args.interval)


def main() -> int:
    p = argparse.ArgumentParser(description="Noethrion independent verifier node (v0.1)")
    p.add_argument("--rpc", required=True, help="EVM RPC URL of the chain the Attester is deployed on")
    p.add_argument("--attester", required=True, help="deployed NoethrionAttester address")
    p.add_argument("--chain-id", type=int, required=True, help="chain id (domain separator for leaves)")
    p.add_argument("--data-dir", default="./published", help="dir with operator-published batch data")
    p.add_argument("--start-epoch", type=int, default=1, help="first epoch to verify (default 1)")
    p.add_argument("--interval", type=int, default=30, help="daemon poll interval seconds (default 30)")
    p.add_argument("--once", action="store_true", help="single pass then exit (for tests/CI)")
    args = p.parse_args()
    try:
        return run(args)
    except KeyboardInterrupt:
        log("INFO", "interrupted — exiting")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
