# Lifecycle examples — full attestation flow end-to-end

Seven numbered files walk the protocol from "device with no key" all the way to "verified attestation, NOET minted, off-chain verifier returns PASS." Run them in order on a local development environment.

## Prerequisites

- Foundry (`forge`, `anvil`, `cast`) installed
- Python 3.10+ with `cryptography` and `pycryptodome` available
  (`pip install -r ../../tools/requirements.txt && pip install pycryptodome`)
- The Noethrion repository checked out (you're already here)

For the on-chain steps (04 / 05 / 06), start a local Anvil node in a separate terminal:

```bash
anvil   # listens on 127.0.0.1:8545, mines on demand, free ETH for default accounts
```

## Run order

| # | File | What it does | Expected output |
|---|------|--------------|-----------------|
| 01 | `01_generate_key.md` | Creates an ECDSA P-256 keypair (software stand-in for the secure element) | `attester.key` + `attester.key.pub` |
| 02 | `02_sign_attestation.sh` | Signs a sample `(deviceId, timestamp, kWh)` tuple | `attestation.json` |
| 03 | `03_build_merkle_tree.py` | Builds a sorted-pair keccak256 Merkle tree over a synthetic batch | `batch.json` with `root` + per-leaf `proof` |
| 04 | `04_propose_batch.s.sol` | Calls `NoethrionAttester.proposeBatch(epoch, root, totalKwh)` — proposer's call also counts as their first vote | Tx hash; batch stored on-chain with `voteCount = 1` |
| 04b | `04b_vote_batch.s.sol` | Required only when `threshold > 1` — additional validator(s) call `voteBatch(epoch)` until `voteCount[epoch] >= threshold` | Tx hash per vote; logs current quorum state |
| 05 | `05_finalize_batch.s.sol` | Warps Anvil's clock past the challenge window, calls `finalizeBatch(epoch)`. Requires `voteCount >= threshold` and `block.timestamp >= batch.timestamp + challengeWindow` | `batches(epoch).finalized == true` |
| 06 | `06_claim.s.sol` | Calls `claim(epoch, proof, beneficiary, amount)` | NOET balance of beneficiary increases |
| 07 | `07_verify_offchain.sh` | Off-chain verification of the same attestation against the device public key | `PASS  ECDSA P-256 signature OK` |

**Threshold = 1 (local-dev default):** the proposer's call in step 04 already counts as the only required vote. Skip step 04b entirely and proceed to step 05.

**Threshold > 1 (production):** after step 04, run step 04b from `(threshold - 1)` distinct validator keys before step 05 will succeed.

If any step fails, see the troubleshooting section at the bottom.

## Run all in one shot

```bash
./tools/run_lifecycle.sh                  # threshold=1 (default)
THRESHOLD=3 ./tools/run_lifecycle.sh      # exercises the m-of-n quorum path
```

The runner starts a fresh Anvil instance, deploys Attester + Token from `contracts/script/Deploy.s.sol`, walks every numbered step in order, and exits with `LIFECYCLE PASS` after the off-chain verifier confirms the signed attestation. Anvil is torn down on exit (clean exit or error). The runner uses `cast send` for the on-chain calls (faster and Foundry-root-config-independent); the Solidity example scripts at `04..06` remain the readable reference for what each call does.

`THRESHOLD` is bounded to `[1, 5]`. With `THRESHOLD > 1` the runner grants `VALIDATOR_ROLE` to `THRESHOLD - 1` additional Anvil accounts (derived from the deterministic test mnemonic), then loops `voteBatch` from each until `voteCount[epoch] >= threshold` before finalizing. CI exercises both `threshold=1` and `threshold=3` on every push so the quorum path stays verified.

Re-running is idempotent — the previous run's local artifacts (`attester.key`, `attestation.json`, `batch.json`) are deleted at the start of each run.

**Security stance.** The runner is hard-coded to Anvil's documented test mnemonic and derives every key at runtime, so no hex-key literals live in the repo. It MUST NOT be pointed at a real RPC. Real-network deployment uses [`contracts/script/DeployProduction.s.sol`](../../contracts/script/DeployProduction.s.sol) and a hardware-wallet / Safe signer pipeline. See the top of `tools/run_lifecycle.sh` for the full security stance comment block.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `forge: command not found` | Foundry not installed | <https://book.getfoundry.sh/getting-started/installation> |
| `address is not a contract` on step 04 | NoethrionAttester not yet deployed to local Anvil | Run `forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast` from `contracts/` first. The script prints the deployed `ATTESTER` and `TOKEN` addresses — export both before running 04-06. |
| `RPC unreachable` | Anvil not running | Start `anvil` in another terminal |
| `InvalidMerkleProof` on step 06 | Leaf encoding mismatch between off-chain builder and contract | Confirm the leaf hash uses `keccak256(abi.encode(block.chainid, address(this), beneficiary, amount, epoch))` exactly — the first two fields are the domain separator binding the leaf to this specific Attester on this specific chain. Builders MUST pass both via `CHAIN_ID` and `ATTESTER` env vars. |
| Python `ModuleNotFoundError: pycryptodome` | dep missing | `pip install pycryptodome` |

## What this covers — and does not

These scripts demonstrate the **happy path** of the protocol. They do not exercise:

- Challenge-and-revert flow (challenge mechanism is a planned v0.2 spec addition)
- Higher-threshold production deployments — the examples here default to `threshold = 1` for local Anvil; production setups grant `VALIDATOR_ROLE` to multiple addresses and set `threshold >= 3`
- Endorser registry lookup (the Verifier is given a public key directly)
- Post-quantum signature variant

The protocol specification — [`../../spec/noethrion-attestation-v0.1.md`](../../spec/noethrion-attestation-v0.1.md) — is normative; these examples are illustrative.
