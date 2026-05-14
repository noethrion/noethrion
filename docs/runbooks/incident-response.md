# Incident response runbook — Noethrion v0.2

> **Audience.** A Foundation signer who is being paged at 03:00 UTC because something has gone wrong on a live deployment. Read top-to-bottom, do not skip.
>
> **Scope.** v0.2 mainnet deployments only. Local-dev (Anvil) and testnet incidents are not in scope — those are dev hygiene, not response.
>
> **Status.** Pre-mainnet. Document is canonical for the moment mainnet goes live; revise immediately after the first real incident.

---

## 0 · Decision tree

| Symptom | First action | Section |
|---------|--------------|---------|
| Validator suspected of voting on fraudulent root | **Pause** + investigate | 2 |
| `claim()` minting wrong amount or to wrong address | **Pause** immediately | 2 |
| Contract appears stuck (finalize reverts when it shouldn't) | Cross-check threshold + window first; pause if root cause not obvious in 10 minutes | 2 |
| Block-explorer shows roles granted to unexpected address | **Pause** + check `_verifyHandoff` log on the deploy block | 2 |
| External auditor surfaces a critical post-launch finding | **Pause** + coordinate with Council | 4 |
| Tooling outage (Safe UI down, explorer down) | Use `cast` against the RPC directly; document the workaround | — |
| Off-chain validator outage (one validator unreachable) | If `voteCount >= threshold` can still be reached with remaining validators, no action. If not, document the gap; do not panic-call. | — |

**The default lever is `pause`. Use it first, investigate second.** Pause is reversible. Slash is not. Re-deploy is catastrophic.

---

## 1 · Roles for incident response

- **Incident commander.** Foundation operations lead. Makes the call to pause / un-pause / slash. Single point of decision authority during an active incident.
- **Safe signers (3 of 5 required).** Sign the `pause` / `unpause` / `schedule slash` / `execute slash` transactions per the commander's direction.
- **Investigator.** Reads on-chain events, validator off-chain signing logs, anything else relevant. Produces a written timeline within 24 hours of the incident.
- **External comms.** Drafts the public statement once root cause is confirmed. Does NOT speak until the commander signs off.

If you cannot reach the incident commander within 10 minutes, the on-call Safe signer with the highest seniority becomes acting commander and pauses. Pausing on suspicion is correct; not pausing when there is real evidence is not.

---

## 2 · Pause — the first lever

`pause()` is held by the Safe directly, no timelock. 3 of 5 signatures land it on chain within minutes.

### 2.1 How to pause

Via the Safe transaction-builder:

- Target: the deployed `NoethrionAttester` address.
- ABI: `pause()` (no arguments).
- Value: 0.
- Have 3 signers approve. Execute.

Confirm on the explorer that `Paused` event was emitted and `attester.paused()` reads `true`.

After pause, the following user-facing entry points revert:

- `proposeBatch` — no new batches.
- `voteBatch` — no new votes on existing batches.
- `finalizeBatch` — pending batches stay pending until un-paused.
- `claim` — no new mints.

The following admin functions stay live (deliberate — admin needs to fix the contract during pause):

- `slash`, `setThreshold`, `setChallengeWindow`, `setTokenContract` (each through the 24h Timelock).
- `unpause` (direct from Safe).
- Role-management via `grantRole` / `revokeRole` (direct from Safe via `DEFAULT_ADMIN_ROLE`).

### 2.2 Investigate

While paused:

- Investigator pulls every `BatchProposed`, `BatchVoted`, `BatchFinalized`, `AttestationClaimed`, `ValidatorSlashed` event since the last known-good state.
- Cross-check on-chain state against off-chain validator logs (each validator must publish their own signing log for incident traceability).
- Identify which (if any) validator(s) acted incorrectly.
- Identify whether the contract itself is at fault — if so, escalate to section 4 (re-deploy).

Document everything. The 24-hour-timeline writeup is non-negotiable and the public statement depends on it.

### 2.3 Un-pause

Only after:

- Root cause confirmed in writing.
- Mitigation in place (validator slashed, threshold adjusted, token contract re-pointed — whichever applies).
- Council signs off on the un-pause decision.

Via the Safe transaction-builder:

- Target: the deployed `NoethrionAttester` address.
- ABI: `unpause()` (no arguments).
- Have 3 signers approve. Execute.

Confirm on the explorer that `Unpaused` event was emitted and `attester.paused()` reads `false`.

---

## 3 · Slash — the validator-accountability lever

`slash(address validator, bytes32 evidenceHash)` is gated by `ADMIN_ROLE`, which the Timelock holds. Calling it requires a 24-hour schedule + execute via the Safe.

### 3.1 When to slash

Slash a validator when **all** of the following are true:

- They voted for a batch that is provably fraudulent (Merkle root does not correspond to the claimed leaves; or the underlying attestations are not from endorsed devices; or a sustained pattern of off-policy votes).
- The off-chain evidence (signing logs, conflicting signatures, telemetry mismatch) is reviewable by an independent party.
- The Council has voted to slash, OR the incident commander has paused and is acting under emergency authority pending Council review.

Do NOT slash a validator who is merely unreachable for an extended period. Use `revokeRole(VALIDATOR_ROLE, addr)` from the Safe directly for a no-fault validator-set update.

### 3.2 How to slash

Two transactions, separated by 24 hours.

**Transaction A — schedule (now):**

Via the Safe transaction-builder, call `schedule(...)` on the Timelock:

- `target`: the deployed `NoethrionAttester` address.
- `value`: 0.
- `data`: the ABI-encoded call to `slash(address,bytes32)` with the validator address and the evidence hash. Use a tool that shows you the decoded call before you sign.
- `predecessor`: `bytes32(0)` (no dependency).
- `salt`: a random `bytes32`. Record it.
- `delay`: 86400 (24 hours) — must equal `Timelock.getMinDelay()`.

Have 3 of 5 signers approve. Execute the schedule call.

Confirm the explorer logged `CallScheduled` on the Timelock with the matching `target` / `data` / `salt`.

Publish a brief public note: validator X has been scheduled for slash; evidence hash Y; execution window opens at timestamp Z. This is the 24-hour public-warning property of the Timelock — it lets the community react if the scheduled action is wrong.

**Transaction B — execute (24h+ later):**

Via the Safe transaction-builder, call `execute(...)` on the Timelock with the same arguments as the schedule call (same `target`, `value`, `data`, `predecessor`, `salt`).

Have 3 of 5 signers approve. Execute the execute call.

Confirm:

- The Timelock logged `CallExecuted` with the matching arguments.
- The Attester logged `ValidatorSlashed(validator, evidenceHash, timestamp)`.
- `attester.hasRole(VALIDATOR_ROLE, validator)` now returns `false`.
- `attester.slashEvidence(validator)` returns the evidence hash.

The slashed validator's prior votes on un-finalized batches remain counted (per ADR-006 Q3) — this is intentional, the audit trail is preserved. Their future proposals and votes revert under `onlyRole(VALIDATOR_ROLE)`.

### 3.3 Cancel a scheduled slash

If during the 24-hour window the evidence is found to be wrong (validator was framed, evidence hash was incorrect), cancel the schedule:

- Via the Safe transaction-builder, call `cancel(bytes32 id)` on the Timelock.
- `id` is the Timelock operation ID, derivable from `(target, value, data, predecessor, salt)` or readable from the `CallScheduled` event.
- 3 of 5 signers approve.

Confirm the Timelock logged `Cancelled` for the matching ID. The schedule is gone; if you still want to slash later, schedule a new one with a different salt.

---

## 4 · Re-deploy — the last lever

Use re-deploy only when:

- The contract itself is found vulnerable (post-launch finding from external audit or community researcher) AND
- The vulnerability cannot be patched via admin functions alone AND
- Pausing is not a viable long-term answer (the contract is permanently broken).

This is a Council-level decision and is out of scope for emergency response. Document the procedure in a separate runbook when it ever becomes relevant. Key constraints to remember:

- There is no upgrade path. A new deploy means a new Attester address and a new Token address.
- Token holders must be migrated. The new Token can read the old Token's balances and mint equivalents — but this migration itself is a contract change that must be audited.
- The validator set, the Safe, the Timelock can be carried forward if they themselves are not compromised.

Pause the old contract. Announce the re-deploy timeline. Coordinate with relying parties.

---

## 5 · Post-incident artifact

Within 7 days of any pause event (even a precautionary one):

- Public timeline note in `docs/incidents/YYYY-MM-DD-summary.md`. Includes: trigger, response timeline, root cause, mitigation, follow-ups.
- Updates to this runbook reflecting any procedural gap surfaced.
- Updates to `docs/audit/smart-contracts-audit.md` Open Findings if the incident exposed a new finding.

Stale incident notes are worse than missing ones. If the project state moves past a note, mark it stale at the top before adding new content.

---

## 6 · Drill cadence

Before mainnet:

- Pause / un-pause drill on the staging testnet, 3 of 5 signers exercising the Safe flow. Record timings.
- Slash schedule / cancel drill on staging, full 24-hour cycle.

Post-mainnet:

- Quarterly pause / un-pause drill on the production contract (yes, on mainnet — confirms the Safe signing path works in practice).
- Annual full slash schedule / execute drill against a Foundation-controlled retired validator address.

Drills surface signer-key custody issues, multi-sig UI changes, and policy gaps long before a real incident does.

---

## Cross-references

- `docs/runbooks/production-deploy.md` — pre-launch deploy procedure.
- ADR-007 — the binding admin model that gates the Pause / Slash levers above.
- ADR-006 — validator-quorum semantics, including the "slashed validator's prior votes still count" decision in Q3.
- `THREAT_MODEL.md` §A4 — the validator-collusion threat that Slash is designed to address.
- `contracts/src/NoethrionAttester.sol` — the contract whose live state these procedures operate on.
