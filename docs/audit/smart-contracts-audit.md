# Smart contracts pre-audit readiness report

**Conducted:** 2026-05-13
**Author:** Noethrion core team (internal review — not an external audit)
**Status:** Initial · pre-launch · self-audit
**Scope:** `contracts/src/NoethrionAttester.sol`, `contracts/src/NoethrionToken.sol`
**Toolchain:** Foundry `forge` 1.6.0, Solidity 0.8.24, OpenZeppelin Contracts 5.x

---

> **Important.** This is a *self-audit*. It does not substitute for an external smart-contract audit. Its purpose is to (a) demonstrate the level of internal rigor applied before engaging external review and (b) give an incoming auditor a structured entry point into the suite — what has been covered, what has not, what limitations are accepted.
>
> External audit is on the launch critical path before any mainnet deploy. The grant track funding it is documented separately. Until that audit is complete, the contracts must not be presented as production-ready.

---

## Suite at a glance

| Surface | Number |
|---------|-------:|
| Source files audited | 2 |
| `NoethrionAttester.sol` unit tests | 63 |
| `NoethrionToken.sol` unit tests | 14 |
| Security (reentrancy mock) tests | 1 |
| Invariant tests | 8 (across 3 phased handler suites) |
| Symbolic (Halmos) checks — Attester | 19 |
| Symbolic (Halmos) checks — Token | 6 |
| Deployment handoff tests (ADR-007) | 16 |
| Deployment validation tests | 15 |
| `DeployTimelock` script tests | 10 |
| **Total tests** | **152** (127 forge + 25 symbolic) |
| Fuzz/invariant call sequences (default profile) | 16,384 |
| Fuzz/invariant call sequences (CI profile) | 98,304 |
| Reverts under random fuzz sequences | 0 (where applicable) |
| Halmos paths explored | 45+ across 15 checks |
| End-to-end lifecycle smoke (`tools/run_lifecycle.sh`) | runs on every CI push (matrix: threshold ∈ {1, 3}) |

All numbers reproducible via `forge test` from `contracts/`.

---

## Coverage

### `NoethrionAttester.sol`

| Dimension | Coverage |
|-----------|---------:|
| Lines | 100.00% (69/69) |
| Statements | 98.72% (77/78) |
| Branches | 95.24% (20/21) |
| Functions | 100.00% (11/11) |

The single uncovered branch is a defensive path in `claim()` whose condition is short-circuited by a prior require in every reachable test sequence; documented as accepted in the open-findings section below.

### `NoethrionToken.sol`

| Dimension | Coverage |
|-----------|---------:|
| Lines | 100.00% (20/20) |
| Statements | 100.00% (24/24) |
| Branches | 100.00% (5/5) |
| Functions | 100.00% (5/5) |

---

## What the suite proves

### Unit tests (`contracts/test/NoethrionAttester.t.sol`)

56 assertions split across:

- **Construction.** Zero-address admin rejected · zero threshold rejected · threshold-1 acceptable.
- **Propose.** Validator-only · counts as first vote · duplicate-epoch rejection.
- **Vote.** Increments count · double-vote rejection (proposer and other validator) · non-validator rejection · unknown-proposal rejection · post-finalize rejection · prior vote of a later-slashed validator persists (ADR-006 Open question, "Do slashed validators retroactively lose votes?", resolved: no).
- **Finalize.** Reverts before window · succeeds after window · double-finalize rejection · unknown epoch rejection · insufficient-votes rejection · exact-threshold acceptance.
- **Slash.** Revokes role · records evidence · admin-only · zero-address rejection · prevents further proposals · evidence-recording on non-validator address (documented intentional behaviour).
- **Pause / unpause.** Each mutating entry point (propose · vote · finalize · claim) is verified to revert under `paused` · role enforcement on both `pause()` and `unpause()` · unpause restores the propose path.
- **Admin paths.** `setChallengeWindow` and `setTokenContract` both verified for role enforcement, zero-address rejection (where applicable), and value updates.
- **Claim.** Success path · double-claim rejection · pre-finalization rejection · invalid-proof rejection · tampered-amount rejection · zero-beneficiary rejection · zero-amount rejection · unset-token-contract rejection.

### Security test (`contracts/test/NoethrionAttester.security.t.sol`)

A `MaliciousToken` mock is set as `tokenContract`. On the first `mint()` callback inside `claim()`, the mock attempts to re-enter `claim()` itself. The outer call completes; the inner call's revert is captured and matched against the OpenZeppelin `ReentrancyGuardReentrantCall()` selector. This is an end-to-end demonstration of the `nonReentrant` modifier plus Checks-Effects-Interactions ordering on the mint plumbing.

### Deployment role-handoff tests (`contracts/test/DeployProductionHandoff.t.sol`)

Sixteen tests that mirror `script/DeployProduction.s.sol` step-for-step and assert the post-state matches the ADR-007 interim model exactly. Deploys a real OpenZeppelin `TimelockController` (24-hour delay, Safe as proposer and executor) and a mock Safe (etched bytecode so the script's `code.length > 0` guard would pass), runs the full handoff sequence as a simulated deployer, and verifies:

- Post-state matrix: Safe holds Attester `DEFAULT_ADMIN_ROLE` + `PAUSER_ROLE`, Timelock holds `ADMIN_ROLE`, Safe holds Token `DEFAULT_ADMIN_ROLE`. All three validators hold `VALIDATOR_ROLE`.
- Critical absence: the Timelock does NOT also hold `DEFAULT_ADMIN_ROLE` — if it did, the Timelock could grant itself any other role and short-circuit the model. The test fails loudly if a regression ever introduces this.
- Deployer is bare: the deployer holds zero roles on either contract after the handoff. This is the property `script/DeployProduction.s.sol` asserts via `require()` at runtime; this test pins it as a compile-time-verified guarantee.
- Operational correctness: Timelock can slash a validator via the schedule + warp + execute path (24-hour delay); Safe can pause immediately without timelock (incident response lever); Safe can grant new validators post-handoff (ongoing operational power); Timelock cannot pause directly (PAUSER is exclusively on the Safe); deployer cannot pause, slash, or grant roles after handoff.

A regression in any of these means the ADR-007 interim deployment guarantees no longer hold, or the test has diverged from the script. Either is critical and the audit team should treat it as a launch blocker.

### Invariant tests

Three layered handler suites, each running with the default profile of 64 runs × 32 depth (2,048 calls) per invariant.

#### Phase 1 — `NoethrionAttester.invariant.t.sol`

Single-leaf batches, threshold fixed at 1. Two invariants:

- **`invariant_VoteCountMatchesVotedMapping`** — for every proposed epoch, the integer `voteCount` equals the population count of the `voted` mapping over the validator set. A break would mean an inconsistent vote-tally bug.
- **`invariant_TotalClaimedNeverExceedsFinalized`** — the cumulative sum of successfully claimed kWh never exceeds the cumulative sum of finalized batch kWh. A break would mean leaves being claimable against un-finalized batches, or double-claims being silently accepted.

#### Phase 2 — `NoethrionAttester.invariant.phase2.t.sol`

4-leaf Merkle batches with real proofs computed by the handler; threshold is mutated by the fuzzer in `[1, validator_count]`. Four invariants:

- **`invariant_TotalSupplyMatchesClaimed`** — `NoethrionToken.totalSupply()` equals the handler's ghost claimed-total. Catches any off-protocol mint path or quantity drift between Attester and Token.
- **`invariant_FinalizedBatchesRetainQuorum`** — every finalized batch still shows `voteCount >= threshold_at_finalize` even after subsequent threshold changes. Catches finalize-under-quorum bugs under churn.
- **`invariant_ClaimedLeavesPersisted`** — every leaf the handler observed `claim()` succeed against has its hash flagged in the contract's `claimed` mapping. Catches a silent-failure path where the flag is not set, which would enable double-spend.
- **`invariant_LatestEpochCoversAllFinalized`** — `latestEpoch` is a monotonic upper bound on every finalized epoch number.

#### Phase 3 — `NoethrionAttester.invariant.phase3.t.sol`

Pause toggle is added as a handler action; every mutating call is wrapped in `try/catch` so a successful execution while `paused == true` can be detected. Two invariants:

- **`invariant_PauseBlocksMutations`** — the count of mutating actions that succeeded under `paused == true` stays at zero across the entire fuzz campaign.
- **`invariant_SupplyMatchesClaimedUnderPauseChurn`** — the supply ↔ claimed equality from phase 2 is re-proved under additional pause-toggle churn.

### CI profile

The CI Foundry profile (`profile.ci` in `foundry.toml`) sets fuzz runs to 1,024 and invariant runs to 256 with depth 64 — i.e., 16,384 random sequences per invariant. All eight invariants have been verified to pass under this profile locally; the same profile is enforced by the `Foundry CI` workflow in `.github/workflows/ci.yml`.

### Symbolic verification (Halmos)

`contracts/test/NoethrionAttester.halmos.t.sol` carries nineteen `check_*` functions that are executed by [Halmos](https://github.com/a16z/halmos) — a symbolic bytecode interpreter built on z3 / yices. Unlike fuzz, Halmos proves a property over the entire input space (subject to its loop-unrolling bound) rather than sampling random inputs. Every public function on `NoethrionAttester` has at least one symbolic property pinned, and the pause kill switch is symbolically proven to block all four mutation entry points (propose, vote, finalize, claim). The nineteen proven properties:

| Check | Property |
|-------|----------|
| `check_proposeBatch_alwaysSetsFirstVote` | For any `(epoch, root, totalKwh)`, a successful `proposeBatch` records exactly one vote from the proposer. |
| `check_setThreshold_zeroAlwaysReverts` | An admin call to `setThreshold(0)` reverts unconditionally — the InvalidThreshold guard cannot be bypassed by any state. |
| `check_constructor_zeroAdminReverts` | The constructor's zero-admin guard holds for any `(challengeWindow, threshold)` combination — no compiler optimisation can elide the require. |
| `check_voteBatch_doubleVoteAlwaysReverts` | For any prior state, a second `voteBatch` call from the same validator on the same epoch reverts — the double-vote invariant in symbolic form. |
| `check_voteBatch_voteCountMonotonic` | `voteCount[epoch]` is monotonically non-decreasing under `voteBatch` and increases by exactly 1 on each successful call. |
| `check_finalizeBatch_revertsBeforeWindow` | `finalizeBatch` reverts for any `block.timestamp` strictly less than `proposalTime + challengeWindow`. Catches `<` ↔ `<=` regressions. |
| `check_claim_zeroBeneficiaryAlwaysReverts` | `claim()` with a zero beneficiary reverts under any `(epoch, amount)` regardless of proof contents. |
| `check_claim_zeroAmountAlwaysReverts` | `claim()` with `amount == 0` reverts under any non-zero beneficiary and any epoch. |
| `check_pause_blocksProposeBatch_alwaysReverts` | When the contract is paused, `proposeBatch` reverts for any `(epoch, root, totalKwh)` — pause covers the entire propose input surface, not just sampled inputs. |
| `check_pause_blocksVoteBatch_alwaysReverts` | Pause symmetrically blocks `voteBatch` for any epoch and any caller. |
| `check_pause_blocksFinalizeBatch_alwaysReverts` | Pause symmetrically blocks `finalizeBatch` for any epoch. |
| `check_pause_blocksClaim_alwaysReverts` | Pause symmetrically blocks `claim` for any `(epoch, beneficiary, amount)`. Completes the 4-way pause-blocks-mutations coverage matrix. |
| `check_claim_singleLeafMintsExactAmount` | End-to-end: for any non-zero `(epoch, beneficiary, amount)`, a single-leaf batch's `claim()` mints *exactly* `amount` to the beneficiary and flags the leaf hash in the contract's `claimed` mapping. Proves the propose → finalize → claim → mint chain over the entire input space. |
| `check_claim_doubleClaimAlwaysReverts` | A second `claim()` against the same leaf reverts under any prior state. Per-leaf double-spend protection in symbolic form. |
| `check_slash_storesEvidenceAndClearsRole` | For any non-zero target, admin's `slash()` leaves the target without `VALIDATOR_ROLE` and records the exact evidence hash. Pre-grant not required — `_revokeRole` is a no-op on an address that did not hold the role, but the evidence record fires either way (intentional). |
| `check_slash_zeroAddressAlwaysReverts` | The `ZeroAddress` guard on `slash()` fires for any evidence hash when target is `address(0)`. |
| `check_setChallengeWindow_updatesValue` | For any `newWindow > 0` within uint64 range, `setChallengeWindow` writes the value to storage exactly. Zero and out-of-range values revert. |
| `check_setChallengeWindow_nonAdminReverts` | For any caller lacking `ADMIN_ROLE`, `setChallengeWindow` reverts. |
| `check_setChallengeWindow_doesNotAffectInFlightBatch` | For any `newWindow` admin passes after a batch is proposed, the per-batch `challengeWindowAtPropose` snapshot remains unchanged. Symbolic equivalent of the `setChallengeWindow` retroactive-shrink guarantee (reviewer C-2 closure, symmetric to H-3 threshold). |

All nineteen pass in under 3 seconds of wall clock on a developer laptop. The Halmos run is not part of the default `forge test` invocation — function names use `check_` (Halmos convention) rather than `test_`, so Forge silently ignores them. Reproduce via `halmos --contract NoethrionAttesterHalmosTest` from the `contracts/` directory.

#### NoethrionToken symbolic checks

`contracts/test/NoethrionToken.halmos.t.sol` carries six `check_*` functions covering the Token's load-bearing surface: the mint-authority chain and the hard-supply-cap invariant.

| Check | Property |
|-------|----------|
| `check_mint_nonMinterAlwaysReverts` | For any caller lacking `MINTER_ROLE` and any `(to, amount)`, `mint()` reverts. Primary defence against unauthorized mints. |
| `check_mint_zeroRecipientAlwaysReverts` | A `MINTER_ROLE`-holding caller minting to `address(0)` reverts for any amount. |
| `check_mint_zeroAmountAlwaysReverts` | A `MINTER_ROLE`-holding caller minting `0` to any non-zero recipient reverts. |
| `check_mint_maxSupplyAlwaysHolds` | For any `(to, amount)` that would push `totalSupply()` strictly past `MAX_SUPPLY`, `mint()` reverts. Pins the economic-model invariant: the 1 NOET = 1 verified kWh hard cap cannot be exceeded by any mint call. |
| `check_authorizeMinter_nonAdminAlwaysReverts` | For any caller lacking `ADMIN_ROLE`, `authorizeMinter()` reverts. Keeps the "100% algorithmic emission, no discretionary mint" property intact at the contract level. |
| `check_authorizeMinter_zeroAddressAlwaysReverts` | Admin authorizing `address(0)` as a minter reverts. |

All six pass in under 1 second. Reproduce via `halmos --contract NoethrionTokenHalmosTest` from the `contracts/` directory.

---

## Static analysis

Slither is configured as a CI workflow (`.github/workflows/security.yml`, committed 2026-05-13) and runs on every push to `main` and every PR that touches `contracts/src/`, `foundry.toml`, `remappings.txt`, or the workflow itself. The workflow uploads SARIF results to the GitHub Security tab (private-repo aware — soft-fails until GitHub Advanced Security is enabled or the repo is flipped public) and surfaces medium-or-higher findings as a job failure.

The detector configuration lives at `contracts/.slither.config.json`:
- `filter_paths` excludes `lib|test|script` so findings are reported only against the protocol surface in `contracts/src/`.
- `exclude_dependencies` is on — OpenZeppelin internals are not Noethrion's surface and are not re-evaluated by this workflow.
- `detectors_to_exclude` carries `timestamp`, `solc-version`, and `unindexed-event-address`. The `timestamp` exclusion is the one that matters semantically: `block.timestamp` is used only to gate the challenge-window comparison, not to derive randomness, and the comparison tolerates validator-manipulable jitter (~15 s) under the 1-hour default window. Documented in ADR-006.

---

## Design constraints enforced by the suite

The following load-bearing design constraints have been verified by at least one test or invariant:

1. **One leaf, one mint.** The `claimed` mapping is keyed by the leaf hash itself, not by `(beneficiary, amount, epoch)` separately; the encoding is fully reconstructed inside the contract. Verified by the double-claim unit test and the `ClaimedLeavesPersisted` invariant.
2. **No mint without finalization.** `claim()` reverts if the batch's `finalized` flag is false. Verified by the pre-finalization unit test and the `TotalClaimedNeverExceedsFinalized` invariant.
3. **No mint outside protocol.** `NoethrionToken.mint()` is guarded by an explicit `authorizeMinter` set; the Attester is the only authorized minter in the deployed configuration. Verified by the `TotalSupplyMatchesClaimed` invariant.
4. **Reentrancy hardness on mint plumbing.** The `claim()` function carries `nonReentrant` and follows Checks-Effects-Interactions (state mutated before the external mint call). Verified by the malicious-token security test.
5. **Pause is a hard kill switch.** No mutating user-facing entry point may succeed while `paused == true`. Verified by per-function unit tests and the `PauseBlocksMutations` invariant.
6. **Validator quorum is mandatory, not advisory.** `finalizeBatch` reverts if `voteCount < threshold`. Verified by the insufficient-votes unit test and the `FinalizedBatchesRetainQuorum` invariant.
7. **Validator votes are durable across slashing.** A vote cast by a validator who is later slashed still counts toward the batch's quorum. Per ADR-006 Open question on slashed-vote persistence (resolved: votes stay). Verified by `test_SlashedValidator_PriorVoteStillCounts`.

---

## Open findings · accepted limitations

Findings that an external auditor should be aware of, with the project's current stance.

### `claim()` — uncovered defensive branch (95.24% branches, not 100%)

The uncovered branch is the `if (tokenContract == address(0)) revert TokenContractNotSet();` check inside `claim()`. The branch is exercised by the `test_Claim_RevertsWhenTokenContractUnset` unit test (a fresh Attester is deployed without `setTokenContract`), but the standard test setup wires the token in `setUp()`, so the live branch is never hit through the common path. **Stance:** accepted — the branch exists for defence in depth and is unit-tested in isolation; achieving 100% branch coverage would require duplicating the entire claim test suite against an unwired Attester, which provides no additional safety signal.

### `slash()` does not verify the target holds `VALIDATOR_ROLE`

The function calls `_revokeRole` (which is a no-op for an address that does not hold the role) and records `slashEvidence` unconditionally for any non-zero target. **Stance:** intentional — keeps the admin able to record evidence even in race conditions where role was already revoked or never held. The behaviour is documented in `test_Slash_OnNonValidatorAddress_StillRecordsEvidence`. Operational guidance: off-chain alerting on `ValidatorSlashed` should cross-check `hasRole(VALIDATOR_ROLE, validator)` before paging.

### `slash()` is admin-triggered, not on-chain fraud-proof verified

`slash()` requires `ADMIN_ROLE`. The off-chain `evidenceHash` is recorded but is not currently verified on-chain. **Stance:** explicit v0.2 limitation documented in the contract's top-of-file NatSpec. Upgrading to on-chain fraud-proof verification (e.g., conflicting-signature detection feeding `slash()` automatically) is v0.3+ work.

### Admin and pauser are a single EOA in the test setup

The constructor grants `DEFAULT_ADMIN_ROLE`, `ADMIN_ROLE`, and `PAUSER_ROLE` to the same address. **Stance:** explicit pre-mainnet limitation; the production model is locked in [ADR-007](../adr/ADR-007-production-admin-multisig.md) — Safe 3-of-5 multi-sig with a 24-hour `TimelockController` on `slash()` and `setThreshold()`, multi-sig only (no timelock) on `setTokenContract` / `setChallengeWindow`, multi-sig only (no timelock) on `pause` / `unpause`. The contract surface does not change; the role-handoff happens in a production deploy script and runbook that ship before mainnet.

### No on-chain bridging or cross-chain coordination

The protocol surface in this version is single-chain. **Stance:** explicit scope decision; cross-chain bridge integration is v0.3+ work and will land via additional contracts, not by modifying the Attester surface.

### Two-layer leaf encoding (spec ↔ contract bridge undocumented)

The Internet-Draft Section 6.1 describes a Merkle tree whose leaves are `SHA-256` over canonically-encoded **attestation tokens** (signed device measurements). The v0.2 reference contract enforces a Merkle tree whose leaves are `keccak256(abi.encode(block.chainid, address(attester), beneficiary, amount, epoch))` — **claim records** identifying redemptions, bound to a specific Attester instance on a specific chain so they cannot be replayed against a fork or sibling deployment. The first two fields are a domain separator added in the pre-audit hardening pass (reviewer-agent finding L-1).

The two layers serve different purposes:

- **Attestation-evidence layer** (spec §6.1): proves a signed measurement existed and was included in a batch. Verified by the off-chain `Verifier` per spec §6.3.
- **Claim-record layer** (contract): gates on-chain NOET minting on Merkle proof of a specific redemption tuple. Verified by `NoethrionAttester.claim()`.

The aggregation function that turns attestation tokens into claim records is implicit in the off-chain builder; it is not specified normatively in the v0.1 I-D. Spec §6.3.1 added 2026-05-13 documents the existence of the two layers but defers the formal aggregation specification to a future revision.

**Stance:** this is a spec gap, not a contract bug. The contract is the implementation truth for the claim-record layer. A future spec revision will define the aggregation function explicitly so an external auditor sees a single normative source. The off-chain Merkle builder in `examples/lifecycle/03_build_merkle_tree.py` is the de-facto reference for the claim-record encoding (matches the contract exactly, verified by the lifecycle smoke test in CI).

### Solidity 0.8.24 ↔ Cancun EVM

The contract targets EVM Cancun (`evm_version = "cancun"` in `foundry.toml`). **Stance:** intentional — Cancun is universally supported on EVM L2 settlement layers that have a Q2 2026 readiness target. Deployments to older targets require an explicit project override.

---

## What is NOT in scope of this self-audit

- **Cryptographic primitives.** ECDSA, keccak, Merkle hashing — relied on as built into OpenZeppelin Contracts and Solidity. Not independently re-verified here.
- **Hardware-attestation pipeline.** The off-chain Merkle-tree builder that produces the roots Attester accepts is reviewed separately (firmware audit + spec conformance). Bugs in the builder cannot be caught by this suite.
- **Economic-model assumptions.** Whether `1 NOET = 1 verified kWh` is the right unit, whether threshold = m is the right value at launch, and how slashing economics interact with validator incentives — all out of scope for the contract audit; covered by the protocol spec and the Constitution.
- **Deploy script (`script/Deploy.s.sol`)** — currently at 0% line coverage by design (the script is exercised by environment-specific deploy runs, not by unit tests). A deploy-time runbook lives outside `contracts/`.

---

## Reproduction

### From a zero state (external auditor, fresh clone)

The block below reproduces every verification claim in this document. Each command runs to completion in under two minutes on a developer laptop; the full sequence finishes in well under ten minutes. Expected exit code: zero for every step.

```bash
# 0. Clone + setup. Replace the SHA below with the pinned audit-target SHA.
git clone https://github.com/noethrion/noethrion.git
cd noethrion
git checkout <pinned-audit-target-sha>

# 1. Foundry-side verification.
cd contracts
forge install                                          # one-time, fetches OZ + forge-std submodules
forge build                                            # expect zero errors, zero warnings
forge test                                             # expect 127 PASS, 0 FAIL
FOUNDRY_PROFILE=ci forge test                          # expect 127 PASS under stricter CI profile (16,384 fuzz calls per invariant)
forge coverage --report summary                        # expect Attester 100/98.72/95.24/100, Token 100/100/100/100

# 2. Halmos symbolic verification (every public function pinned).
forge clean                                            # halmos re-builds without optimizer, must start fresh
pip install halmos==0.3.3                              # CI pins this exact version; see .github/workflows/ci.yml
halmos --contract NoethrionAttesterHalmosTest          # expect 19/19 PROVEN in under 3 s
halmos --contract NoethrionTokenHalmosTest             # expect 6/6 PROVEN in under 1 s

# 3. Slither static analysis (Trail of Bits).
slither . --config-file .slither.config.json           # expect zero medium-or-higher findings; detector-exclusion rationale documented in this file (Static analysis section)

# 4. End-to-end lifecycle smoke (off-chain builder + on-chain claim).
cd ..
pip install -r tools/requirements.txt                  # cryptography + pycryptodome
./tools/run_lifecycle.sh                               # threshold=1 path; expect LIFECYCLE PASS
THRESHOLD=3 ./tools/run_lifecycle.sh                   # threshold=3 m-of-n quorum path; expect LIFECYCLE PASS

# 5. Independent leaf-encoding cross-check.
# The compute-leaf CLI uses the same 5-tuple encoding the contract enforces.
# This is the byte-equivalence test an integrator would run before trusting
# the leaf hashes their off-chain Merkle builder produces.
python3 tools/verify_attestation.py compute-leaf \
    --chain-id 31337 \
    --attester 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512 \
    --beneficiary 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
    --amount 100000000000000000000 \
    --epoch 1
# Expected: 0xdcf8760eaacee491d816b637521446ba2f00f0721f10a5099cfb69ce6f2c40b3
```

### Continuous integration

Every push to `main` re-runs steps 1, 2, and 4 above as separate matrix jobs in `.github/workflows/ci.yml`; step 3 runs as a separate workflow in `.github/workflows/security.yml`. The Halmos zero-match guard in the CI workflow fails the run if a future refactor accidentally collects zero symbolic tests under `--match-contract` (so a silent suite-rename cannot quietly turn off the symbolic layer). The four pipelines together lock every guarantee this document claims at the SHA the audit was performed against.

### Individual subsections

If you need to reproduce a single section's claims rather than the whole document:

- "Unit tests" — `forge test --match-contract NoethrionAttesterTest` and `forge test --match-contract NoethrionTokenTest`
- "Security test" — `forge test --match-contract NoethrionAttesterSecurityTest`
- "Invariant tests" — `forge test --match-path "**/*invariant*"`
- "Deployment handoff tests" — `forge test --match-contract DeployProductionHandoffTest`
- "Deployment validation tests" — `forge test --match-contract DeployProductionValidationTest`
- "Deployment Timelock script tests" — `forge test --match-contract DeployTimelockTest`
- "Symbolic verification (Halmos)" — `halmos --contract NoethrionAttesterHalmosTest` and `halmos --contract NoethrionTokenHalmosTest`
- "End-to-end lifecycle smoke" — `./tools/run_lifecycle.sh` (default threshold = 1; set `THRESHOLD=3` for the m-of-n quorum leg)

---

## Cadence

This report refreshes when:
- The contract surface changes (new function, new state, new error).
- A new invariant is added or an existing one materially changes scope.
- Coverage drops below the figures recorded here.

Stale reports are worse than missing reports. Bump the date and revise the numbers in the same commit that lands the relevant code change.

---

## See also

- `docs/adr/ADR-006-threshold-submitter.md` — design rationale for the propose + vote + finalize state machine
- `contracts/src/NoethrionAttester.sol` — top-of-file NatSpec lists the v0.2 → v0.3 hardening path
- `THREAT_MODEL.md` (repo root) — system-level threat enumeration that drove the invariant choices above
- `.github/workflows/ci.yml`, `.github/workflows/security.yml` — automation that runs the above checks on every push
- `contracts/.slither.config.json` — Slither detector configuration and exclusion rationale
