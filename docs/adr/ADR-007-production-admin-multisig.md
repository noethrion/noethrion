# ADR-007 — Production admin uses Safe multi-sig with timelock on slash and setThreshold

- **Status:** Accepted
- **Date:** 2026-05-13
- **Deciders:** Founding contributors
- **Related:** ADR-004 (Swiss Stiftung), ADR-006 (m-of-n quorum)
- **Supersedes:** none

## Context

The v0.2 `NoethrionAttester` contract grants `DEFAULT_ADMIN_ROLE`, `ADMIN_ROLE`, and `PAUSER_ROLE` to a single deployer address in the reference `script/Deploy.s.sol`. The local-dev convenience of a single-EOA admin is appropriate for testing and for the integrator examples, but for mainnet it concentrates extraordinary powers in one key:

- **`slash(validator, evidenceHash)`** — revokes a validator's role and writes the evidence reference on-chain. Irreversible (the evidence record is permanent; role can be re-granted, but the on-chain record of the slash event cannot be retracted).
- **`setThreshold(newThreshold)`** — changes the m-of-n quorum value. A hostile admin could set `threshold = 1` to enable single-validator finalization, or set `threshold > validator_count` to freeze all new finalizations indefinitely.
- **`setTokenContract`, `setChallengeWindow`** — protocol-parameter changes with similar attack surface.
- **`pause()` / `unpause()`** — kill switch on every user-facing entry point.

The pre-audit readiness report (`docs/audit/smart-contracts-audit.md`, Open findings · "Admin and pauser are a single EOA in the test setup") flags this as the most material gap between the v0.2 contract surface and a mainnet-ready operational configuration. A decision is required **now**, before the production deploy runbook is written, so that the runbook can be built against a locked admin model and so that the audit engagement starts from the same model the auditor will be asked to attest.

## Decision

> **Reader's note (binding):** the Decision below describes the *target* end-state. The v0.2 reference contract has a single `ADMIN_ROLE` that gates all four admin functions (`slash`, `setThreshold`, `setChallengeWindow`, `setTokenContract`); splitting it as the target table prescribes requires a contract-side change planned for v0.3. The binding v0.2 deploy configuration is the interim described in the "Refinement" section at the bottom of this ADR: the Timelock holds the entire `ADMIN_ROLE`. Production deploy script `contracts/script/DeployProduction.s.sol` implements the interim.

Mainnet deployment binds the protocol's admin powers to a **Safe (formerly Gnosis Safe) 3-of-5 multi-signature wallet**, with an **OpenZeppelin TimelockController** placed in front of the two functions whose effects are hardest to unwind: `slash()` and `setThreshold()`.

Concretely:

| Role | Holder on mainnet | Notes |
|------|-------------------|-------|
| `DEFAULT_ADMIN_ROLE` | Safe 3-of-5 | OpenZeppelin AccessControl super-role; can grant or revoke any other role. |
| `ADMIN_ROLE` for `slash()` and `setThreshold()` | TimelockController (24-hour minimum delay), controlled by the Safe 3-of-5 | Operations on these two surfaces enter a public queue, must wait the timelock, then can be executed by anyone (typically a Safe signer). |
| `ADMIN_ROLE` for `setTokenContract()` and `setChallengeWindow()` | Safe 3-of-5 directly | Same multi-sig, no timelock. These parameters are infrequently changed and a mid-route swap is operationally noisy; the multi-sig itself is the bar. |
| `PAUSER_ROLE` | Safe 3-of-5 directly | No timelock — pausing is the emergency-response surface and must be fast. Pausing is fully reversible (the same 3-of-5 can `unpause()`), so the trade-off is acceptable. |

Initial signer set composition follows ADR-004 (Swiss Stiftung) and the Foundation's documented signing-key custody policy. The signer-set identity and the multi-sig contract address are published with the mainnet deploy announcement; subsequent rotations go through the Safe's own owner-management flow, not by re-deploying the contract.

## Consequences

**Positive**

- **Single-actor capture risk falls sharply.** A successful attack must compromise three out of five distinct signer devices, each with a different operational profile. Compromise of a single signer's machine, recovery phrase, or hardware key cannot move the contract.
- **24-hour public warning before the most damaging actions.** A hostile or mistaken `slash()` or `setThreshold()` queues publicly with a TimelockController event before it can execute. Community monitors can react — pre-emptively `pause()` the contract, broadcast a fork warning, or coordinate a `cancel()` call on the timelock if the action is clearly wrong.
- **Aligns with reviewer / exchange / grant expectations.** Multi-sig + timelock on slashing-class actions is the default expectation in the smart-contract security community as of 2026 and a baseline question on most audit engagement intake forms.
- **Pause stays fast.** Decoupling the pause surface from the timelock keeps the kill switch on its proper timescale. The cost of an over-eager pause is a brief halt of new finalizations; the cost of a slow pause during an incident is unbounded.
- **Foundation governance lives in one place.** The Stiftung's documented signing-key custody policy is enforced by the multi-sig directly; there is no shadow authority outside the Safe.

**Negative**

- **24-hour timelock delays emergency slash response.** A validator caught producing fraudulent batches cannot be slashed for 24 hours after the proof is filed. Acceptable because: (a) slashing is for sustained evidence, not for emergency containment — `pause()` is the emergency lever, and the pause path has no timelock; (b) the 24-hour window is also the window in which on-chain fraud-proof verification (v0.3+) will eventually slash without admin intervention; the timelock-gated admin slash is a fallback, not the primary path.
- **Operational overhead on benign admin actions.** A routine `setChallengeWindow` (multi-sig only, no timelock) requires three signers to coordinate; a routine `slash()` (multi-sig + timelock) requires three signers plus a 24-hour wait. Both costs are accepted because these actions are rare by design.
- **Two coupled contracts to monitor for incidents.** The Safe and the Timelock each have their own event surface and their own attack surface. Mitigated by both being battle-tested, well-audited components used widely; the Noethrion code interacting with them is small.

## Alternatives considered

**Single EOA admin (status quo of `script/Deploy.s.sol`).** Rejected as a launch blocker. Every objection in the Context section applies. Suitable only for local development and for the integrator examples, which is what `Deploy.s.sol` is for.

**Multi-sig without timelock.** Rejected. A 3-of-5 Safe with instant execution is materially better than a single EOA, but a coordinated attack by three signers (compromised, coerced, or bribed) still reaches the contract with no public warning window. The timelock turns *every* sensitive action into a public event before it lands, which is the part that gives the community time to respond.

**Single-account admin with a separate guardian holding pause-only powers.** Considered. Rejected because the guardian-only configuration still concentrates `slash` and `setThreshold` in the single admin. The multi-sig + timelock configuration subsumes the guardian-only proposal's pause-fast property while also fixing the broader admin concentration.

**DAO-governed admin (token-holders vote on every admin action).** Deferred to v1.0+ post-Foundation-handoff. Compelling long-term, but at v0.2 the protocol does not yet have a meaningful token-holder set, governance tooling, or quorum-of-quorums semantics on top of the validator quorum; introducing DAO governance on top of the validator quorum at this stage would create more attack surface than it removes. The Stiftung holds the multi-sig directly for v0.2 → v0.X; the path to broader governance is documented in the Constitution and is a v1.0+ ADR.

**Higher threshold (4-of-7, 5-of-9).** Considered. 3-of-5 chosen as the balance between collusion resistance and operational liveness. At 4-of-7, a single signer being unavailable starts to slow benign operations; at 5-of-9, the operational pain of routine admin actions outweighs the marginal collusion-resistance gain at the Foundation's scale. Re-evaluate at every major version.

**Longer or shorter timelock (12 h, 48 h, 7 d).** 24 h chosen as the smallest window that meaningfully crosses a workday in every timezone in which a Foundation signer or community monitor operates. 12 h is too short for some signers to participate; 48 h+ is too painful for routine threshold tuning. Re-evaluate at every major version.

## Implementation

This ADR locks the *decision*. Implementation lives in two places:

1. **A production deploy runbook** (`docs/runbooks/production-deploy.md`, future) — step-by-step procedure that (a) deploys the Safe, (b) deploys the TimelockController with the Safe as `PROPOSER_ROLE` and the Safe as `EXECUTOR_ROLE`, (c) deploys the Attester + Token with the deployer as initial admin, (d) calls `grantRole` to give the Timelock `ADMIN_ROLE` for `slash` and `setThreshold` (via wrapper or split admin), (e) calls `grantRole` to give the Safe `DEFAULT_ADMIN_ROLE` and the remaining `ADMIN_ROLE` slots and `PAUSER_ROLE`, (f) calls `renounceRole` to remove the deployer EOA from every role. The deployer EOA must end the runbook holding zero roles.
2. **`script/DeployProduction.s.sol`** (future) — an opinionated production variant of the existing dev script that executes the role-handoff atomically and refuses to broadcast unless the Safe and Timelock addresses are pre-set in environment variables (`MAINNET_SAFE`, `MAINNET_TIMELOCK`).

Neither artifact ships in this ADR's commit. This ADR establishes the binding decision so they can be built against a fixed target.

## Cross-references

- `docs/audit/smart-contracts-audit.md` — "Admin and pauser are a single EOA in the test setup" open finding now resolved by reference to this ADR (the gap remains until the runbook + production script ship, but the design is no longer open).
- `docs/adr/ADR-004-swiss-stiftung-foundation.md` — the Stiftung holds the multi-sig.
- `docs/adr/ADR-006-threshold-submitter.md` — the validator quorum that `setThreshold` controls.
- `THREAT_MODEL.md` Section A4 — the validator-collusion threat that `slash` is the response to.
- OpenZeppelin Contracts: `governance/TimelockController.sol`, used as-is, version 5.x.
- Safe (Gnosis Safe): the deployed contract used as-is; production Safe address published with the mainnet announcement.

## Refinement (2026-05-13, same day) — split-role design implication

The Decision table above describes a *target* end-state in which `slash()` + `setThreshold()` sit behind the Timelock while `setTokenContract` / `setChallengeWindow` go through the Safe directly. The v0.2 `NoethrionAttester` contract gates all four functions on a **single `ADMIN_ROLE`** — there is no way to apply a Timelock to two of the four without changing the contract surface to split the role.

This refinement records the consequence honestly and locks the interim model:

**v0.2 mainnet interim (no contract change required).** The Timelock holds the entire `ADMIN_ROLE`. *Every* admin action — including the operationally noisier `setChallengeWindow` and `setTokenContract` — passes through the 24-hour delay. The Safe holds `DEFAULT_ADMIN_ROLE` and `PAUSER_ROLE`. Pause / unpause stays fast as in the original Decision. Trade-off: more friction on parameter tuning, in exchange for shipping without a contract change and without losing any of the safety properties.

**v0.3 enhancement (planned).** A future contract revision splits `ADMIN_ROLE` into two roles — `TIMELOCK_ADMIN_ROLE` (gates `slash` and `setThreshold`) and `IMMEDIATE_ADMIN_ROLE` (gates `setChallengeWindow` and `setTokenContract`) — at which point the original Decision table becomes implementable directly. The split is small, additive, and has no breaking surface for existing integrators.

The original Decision table remains the binding *target*; the interim is the binding *deploy configuration for v0.2*. The production deploy runbook and `DeployProduction.s.sol` will implement the interim. The split-role contract change will be its own ADR-supersede when scoped.
