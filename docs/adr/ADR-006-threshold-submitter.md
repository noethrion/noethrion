# ADR-006 — m-of-n validator quorum via on-chain propose + vote

- **Status:** Accepted
- **Date:** 2026-05-13
- **Deciders:** Founding contributors
- **Related:** ADR-002 (hardware root), ADR-003 (EVM L2 settlement)
- **Supersedes:** none

## Context

The v0.1 reference `NoethrionAttester` accepted batch submissions from any single address holding the `VALIDATOR_ROLE`. Threat model A4 ("validator / submitter collusion") flagged this as the **largest residual risk** in the v0.1 protocol — a single malicious validator could submit a batch with arbitrary Merkle roots, and only the challenge-window fraud-proof path (still unbuilt) protected the system.

For v0.2 the protocol needs an m-of-n threshold quorum so that finalization requires concurring votes from `threshold` distinct validators. The design space includes:

1. **Off-chain aggregated signatures, single on-chain transaction.** A coordinator collects m signatures off-chain (BLS, Schnorr threshold, plain ECDSA bundle); a single transaction submits root + aggregated signature; the contract verifies aggregation.
2. **On-chain propose + vote (one transaction per validator).** The first validator calls `proposeBatch(epoch, root, totalKwh)`; subsequent validators call `voteBatch(epoch)`; once `voteCount[epoch] >= threshold`, the batch is eligible for finalization after the challenge window.
3. **Hybrid.** Off-chain signing for cheap chain-storage, on-chain enrolment of votes through a small mediation contract.

## Decision

Choose **Option 2 — on-chain propose + vote**, with the proposer's submission counting as their first vote.

## Consequences

**Positive**

- **No off-chain coordinator role.** Option 1 requires an aggregator who can withhold or reorder signatures; Option 2 lets every validator broadcast independently. Less governance surface to attack.
- **Public audit trail.** Each validator's vote is a distinct on-chain transaction with their address. A slashing event can point to "validator X voted for fraudulent root R at epoch E" — easy evidence.
- **Simpler contract surface.** No threshold-cryptography library dependency, no off-chain signing scheme to specify, no aggregator failure mode to test.
- **Easy to reason about.** A reviewer reading the contract sees `proposeBatch` → `voteBatch` × N → `finalizeBatch`. Each step has a single responsibility.
- **Backward compatible at threshold = 1.** Single-validator local-dev deployments behave identically to v0.1's `submitBatch` — only the function name changed (`submitBatch` → `proposeBatch`). Migration is mechanical.

**Negative**

- **Gas cost is N transactions per batch instead of 1.** At threshold = 5 this is roughly 5× the L2 gas to commit a batch. Per the protocol's commitment cadence (~one batch per 10 minutes) this remains negligible in absolute dollar terms on any reasonable L2; the trade-off is acceptable for v0.2.
- **Time to threshold is bounded by validator responsiveness.** If validator quorum is sluggish to broadcast, the time-to-finalize lengthens. Mitigated by the challenge window already exceeding typical validator response time by orders of magnitude (default 1 hour challenge vs sub-minute validator reaction).
- **No threshold-cryptography learning curve gained.** A future revision that wants the gas savings of Option 1 will have to introduce the aggregation library at that point.

## Alternatives considered

**BLS threshold signatures (Option 1, BLS variant).** Most gas-efficient on-chain (single signature verification regardless of quorum size). Rejected for v0.2 because: (a) BLS precompile availability across EVM L2s is uneven; (b) BLS key generation and rotation introduces operational complexity disproportionate to v0.2 scale; (c) the design would require an aggregator role that we explicitly want to avoid. Reconsider at v0.4+ if gas economics shift materially.

**Schnorr threshold signatures.** Smaller signatures than ECDSA bundle, no precompile dependency (verifier writable in plain Solidity). Rejected for the same off-chain-aggregator reasons as BLS, plus less mature library support than ECDSA.

**Plain ECDSA m-of-n on-chain verification (Option 1, naive variant).** Submit batch with m separate `(v, r, s)` signatures concatenated; contract iterates and verifies each. Mid-gas-cost, no precompile dependency. Rejected because (a) the gas savings vs Option 2 are small at the protocol's batch frequency, (b) it still concentrates the aggregator role, (c) the simplicity benefit of Option 2 is worth the marginal extra gas.

**Hybrid (Option 3).** Considered. Rejected because the hybrid form combines the worst of both — needs an aggregator AND multiple transactions. Optimises for neither end of the trade-off.

## Slashing implementation

Separate but related: the v0.2 `slash(validator, evidenceHash)` function is admin-triggered with off-chain evidence hash recorded on-chain. On-chain fraud-proof verification feeding `slash()` automatically (e.g., observing two conflicting votes from the same validator at the same epoch — already prevented by `voted[epoch][validator]` mapping, but other fraud patterns could be detectable on-chain) is deferred to **v0.3+**.

Admin-triggered slashing is acceptable for v0.2 because:
- The Foundation is still under Initial Development Co. control; admin role security model matches Foundation maturity
- On-chain fraud proofs require careful design work that benefits from real validator misbehaviour evidence to design against — premature without operating experience
- A future revision can add automatic slashing as an additional admin-less path without changing the existing admin-triggered path

## Open questions

- What's the production threshold value? **Defer to v1.0 mainnet configuration.** Typical analogous projects use `threshold = ceil(2n/3)` for Byzantine fault tolerance; with n = 5 → m = 4; with n = 7 → m = 5. The protocol does not require BFT for verification correctness (the challenge window + fraud-proof path provides the safety net), but a strong default makes sense.

- Should `setThreshold` cap at the active-validator count? Currently it does not — admin can set threshold above current `n`, which freezes new finalizations until more validators are enrolled. **Decision: leave as soft cap** — admin's responsibility, prevents the contract from needing an enumerable role registry which adds significant gas.

- Auto-revocation of votes when a validator is slashed mid-epoch? **No** — once a vote is recorded it stays. The challenge-window fraud-proof path is the right place to invalidate fraudulent batches, not vote-level rollback. Future work.
