# `docs/runbooks/` — Operational runbooks

Procedural documents for operating a live Noethrion deployment. Distinct from `docs/adr/` (design decisions) and `docs/audit/` (assessment reports): runbooks are step-by-step procedures intended to be read mid-action by a Foundation operator.

| Runbook | When to read |
|---------|--------------|
| [`production-deploy.md`](./production-deploy.md) | Walking through the canonical v0.2 mainnet deploy: Safe creation, Timelock deployment, Attester + Token deployment + role handoff, post-deploy verification, announcement template, first-batch smoke test, operating cadence. |
| [`incident-response.md`](./incident-response.md) | Being paged because something has gone wrong on a live deployment. Pause / slash / re-deploy decision tree; how to use the Safe to pause; how to schedule + execute a slash through the Timelock; drill cadence. |

## Status

Both runbooks are pre-mainnet. They have been walked through against a local Anvil but not yet against a real network. They will be revised after the first real-network deploy and after the first real incident (if any). Stale runbooks are worse than missing ones; if you walk through one and find a gap, file a PR before another operator hits the same gap.

## Cross-references

- [`../adr/ADR-007-production-admin-multisig.md`](../adr/ADR-007-production-admin-multisig.md) — the binding design these runbooks implement.
- [`../audit/smart-contracts-audit.md`](../audit/smart-contracts-audit.md) — the pre-audit posture report; the SHA both runbooks reference for the deployed source.
- [`../../contracts/script/DeployTimelock.s.sol`](../../contracts/script/DeployTimelock.s.sol), [`../../contracts/script/DeployProduction.s.sol`](../../contracts/script/DeployProduction.s.sol) — the deploy scripts the production-deploy runbook drives.
