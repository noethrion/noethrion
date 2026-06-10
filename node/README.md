# Noethrion verifier node (v0.1)

An independent watchdog anyone can run to verify the Noethrion protocol **without
trusting the operator**. This is the "don't trust us, verify it yourself"
component — the trust-minimizing core of the network.

## What it does

For every **finalized** batch on a deployed Attester, the node independently:

1. reads the on-chain committed `merkleRoot` from `batches(epoch)`,
2. loads the operator-published batch data for that epoch,
3. confirms the published root equals the on-chain root,
4. re-derives every leaf as `keccak256(abi.encode(chainId, attesterAddr, beneficiary, amount, epoch))`
   — the exact encoding the contract enforces in `claim()` — and replays the
   Merkle proof against the on-chain root,
5. cross-checks that the batch is non-empty and that the published leaf
   amounts sum exactly to the on-chain `totalKwh` commitment,
6. re-verifies the ECDSA P-256 attestation signature (when published).

Any mismatch → **ALARM**. So is a **finalized** epoch whose published batch data
is absent, malformed, or missing required fields (`leaf` is mandatory on every
leaf record): fail closed — an operator must not be able to dodge verification
by not publishing. The node never trusts the operator's word; it recomputes
everything from the on-chain commitment. When no attestation/pubkey is
published, the chain checks still gate the verdict, but the node reports
honestly: "chain checks OK, signature not checked" — never "fully verified".

**Scope v0.1:** chain + signatures. Consumption-matching (generation↔spend) is a
later version and intentionally not here.

## Reuse, not reinvention

The cryptographic engine is **imported** from [`../tools/verify_attestation.py`](../tools/verify_attestation.py)
(P-256 signature + sorted-pair keccak256 Merkle verification) — a single source
of truth, already covered by the lifecycle tests. The node adds only the
chain-watching + leaf-domain-encoding layer.

## Run

```bash
pip install -r node/requirements.txt        # + tools/requirements.txt engine deps

python3 node/verifier_node.py \
    --rpc        https://sepolia.infura.io/v3/<key> \
    --attester   0xATTESTER... \
    --chain-id   11155111 \
    --data-dir   ./published \
    --once          # single pass; omit for a continuous daemon (polls --interval seconds)
```

`--data-dir` holds the operator-published files per epoch:

| File | Required | Purpose |
|------|----------|---------|
| `batch.json` (or `batch-<epoch>.json`) | yes | Merkle root + per-leaf proofs (same shape as the lifecycle tooling emits) |
| `attestation.json` | optional | enables the ECDSA P-256 signature check |
| `attester.key.pub` | optional | device public key for the signature check |

Exit codes (`--once`): `0` all verified · `1` ALARM (mismatch) · `2` usage or
connectivity error (e.g. unreachable RPC / undecodable response — never silently
reported as success). Same contract in both the Python and Go implementations.

## Deploy as a daemon (any Linux host)

Run one or more independent verifier nodes — ideally operated by distinct parties
across different regions — so no single operator's word has to be trusted. Drop a
`systemd` unit (omit `--once`, add `Restart=always`) pointing at the deployed
Attester + a `--data-dir` the operator keeps current. The node logs `OK epoch N`
per verified batch and `ALARM` on any reconciliation failure.
