# Changelog

All notable changes to this repository.

The format is loosely [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning is informal
pre-launch — the project pre-dates an `npm version`-style semver line. Once the protocol v1.0 mainnet ships,
this changelog will adopt strict semver.

---

## Unreleased

Pre-launch work. The verifier node has its own tag line — `node-v0.1.1` is published with platform binaries
and `SHA256SUMS` (see the GitHub Releases page). Everything else below is in main but not yet behind a tag;
the protocol/spec itself remains untagged pending `v0.1.0-spec`.

### Added

- `ROADMAP.md` — multi-year roadmap with explicit phases and "not on roadmap" exclusions
- `CHANGELOG.md` — this file
- `FAQ.md` — 30 anticipated launch-day questions across positioning / technical / market / concerns / engagement
- `THREAT_MODEL.md` — standalone expanded threat model with ten adversary classes and mitigations matrix
- `EXAMPLES.md` — top-level walkthrough of the example directory
- `QUICKSTART.md` — five-minute on-ramp for engineers
- `docs/adr/` — five Architecture Decision Records (signature curve, hardware root of trust, EVM L2 settlement,
  Swiss Stiftung Foundation structure, no-token-sale posture) + index
- `docs/hardware-vendor-matrix.md` — secure-element comparison across four families
- `docs/audit/` — license / performance / accessibility / i18n self-audit reports
- `docs/og-image.png` — Open Graph / Twitter card hero (1200×630, brand-compliant)
- `docs/index.html` — landing page (~45 KB single-file bilingual HTML)
- `spec/noethrion-attestation-v0.1.md` — IETF-style Internet-Draft v0.1
- `examples/lifecycle/` — seven-step end-to-end protocol walkthrough (key generation → signing → Merkle tree →
  on-chain submit → finalize → claim → off-chain verify)
- `examples/integrators/` — drop-in starter code in three languages (Python library, Node TypeScript,
  Solidity consumer)
- `contracts/script/Deploy.s.sol` — Foundry deployment script for a local Anvil chain
- `assets/og-image.svg`, `assets/social/twitter_avatar_400.{svg,png}`,
  `assets/social/farcaster_avatar_400.{svg,png}` — brand-compliant social assets
- `firmware/` — ESP32 + ATECC608B reference firmware (probe-only skeleton, PlatformIO, cryptoauthlib v3.7.9)
- `tools/provision_atecc.py` — software ECDSA P-256 key-generation + signing helper
- `tools/verify_attestation.py` — standalone signature + Merkle inclusion verifier
- `tools/render_social_assets.py` — Pillow-based renderer for OG image + avatar PNGs
- `.github/workflows/deploy-pages.yml` — Cloudflare Pages deploy on `docs/**` changes
- Bilingual EN + RU content across README, QUICKSTART, EXAMPLES, FAQ, landing page

### Smart contracts

- `NoethrionAttester` — `claim()` implementation with on-chain Merkle proof verification
  (`@openzeppelin/contracts/utils/cryptography/MerkleProof`), `ReentrancyGuard`-wrapped external mint call,
  double-spend prevention via the per-leaf `claimed` mapping, double-finalization revert via the new
  `BatchAlreadyFinalized` error
- `NoethrionToken` — ERC-20 + ERC20Permit + AccessControl, MINTER_ROLE-gated `mint()`, hard cap
- Test coverage 27 tests across two suites including fuzz on the mint path

### Changed

- Editorial pass across all public documents: settlement-layer references abstracted to
  "EVM-compatible Layer 2" pending spec lock; positioning language aligned with the project's
  open-standard framing; all `noethrion.org` references updated to `noethrion.com`
- Brand book v0.3 logo previews and three F-series SVG taglines updated to the current positioning
  ("open standard for verifiable energy")
- `foundry.toml` RPC endpoint slots reduced to mainnet + sepolia only (specific L2 selection deferred to
  spec v0.2)
- **BREAKING (v0.2 contract):** `NoethrionAttester.submitBatch(epoch, root, totalKwh)` renamed to
  `proposeBatch(...)` with identical signature. The proposer's call counts as their first vote in the new
  m-of-n quorum. Constructor now takes a third argument — `initialThreshold` — required to be ≥ 1. Event
  `BatchSubmitted` renamed to `BatchProposed`; error `EpochAlreadySubmitted` renamed to
  `EpochAlreadyProposed`; struct field `submitter` renamed to `proposer`. Acceptable because contracts are
  pre-flip private and unaudited; no production callers exist.

### Added (v0.2 contract)

- `voteBatch(uint64 epoch)` — additional validator votes after the proposer
- `finalizeBatch()` — now requires `voteCount[epoch] >= threshold` in addition to the challenge-window check
- `setThreshold(uint256)` — admin can raise or lower `m`
- `slash(address validator, bytes32 evidenceHash)` — admin revokes `VALIDATOR_ROLE` and records off-chain
  evidence hash
- New errors: `InsufficientVotes`, `AlreadyVoted`, `InvalidThreshold`
- New events: `BatchVoted`, `ThresholdUpdated`, `ValidatorSlashed`
- New storage: `threshold`, `voted`, `voteCount`, `slashEvidence`
- Test suite expanded from 27 to 45 passing tests covering propose / vote / threshold / slash paths
- ADR-006 documents the design choice (on-chain propose+vote vs off-chain aggregated signatures)

### Added (v0.2 verification + deploy posture, 2026-05-13)

- **Test suite extended from 45 → 73** Forge tests: +5 token coverage (commit `b4a5710`), +8 attester
  admin-path units, +1 reentrancy security test, +8 fuzz invariants across three phased handler suites
  (single-leaf, multi-leaf Merkle with mutated threshold, pause-aware try/catch)
- **Halmos symbolic verification suite** (`contracts/test/NoethrionAttester.halmos.t.sol`) — 9 properties
  proven over the entire input space: first-vote on propose, zero-threshold revert, zero-admin revert,
  double-vote revert, voteCount monotonicity, finalize-before-window revert, claim zero-beneficiary /
  zero-amount reverts, pause-blocks-propose. All pass in under 1s of wall clock
- **Reentrancy hardening verified end-to-end** — `MaliciousToken` mock attempts re-entry from inside
  `mint()`; the inner call is captured to revert with `ReentrancyGuardReentrantCall()`, validating the
  `nonReentrant` modifier and Checks-Effects-Interactions ordering
- **Pause is a hard kill switch** — per-mutation-function unit tests plus a fuzz invariant that pins
  success-under-pause count at 0 across 2048 random sequences
- **Coverage** — `NoethrionAttester` 100% lines / 98.72% statements / 95.24% branches / 100% functions;
  `NoethrionToken` 100% across the board
- `docs/audit/smart-contracts-audit.md` — pre-audit readiness report (entry document for the incoming
  external auditor); covers coverage, invariant catalogue, Halmos checks, Slither configuration, open
  findings, accepted limitations, reproduction commands
- `THREAT_MODEL.md` Section 3.1 — implementation-level cross-reference linking each adversary mitigation to
  its corresponding test or invariant
- ADR-007 — production admin uses Safe 3-of-5 multi-sig with TimelockController (24h delay) on slash +
  setThreshold; refinement section locks the v0.2 interim model (Timelock holds the entire ADMIN_ROLE) until
  a future contract-side role-split lands
- `contracts/script/DeployProduction.s.sol` — opinionated production deploy script that implements the
  ADR-007 interim role-handoff with full post-deploy verification (deployer ends holding zero roles)

### Added (v0.2 hardening pass — spec/whitepaper/security alignment, 2026-05-13)

- **Spec §3.5 Validator** — first-class on-chain role definition added (was implicit). Cross-refs §8.4 for
  quorum + slashing accountability mechanisms; differentiates the on-chain Validator from the RATS
  device-side Attester and the relying-party-side Verifier
- **Spec §6.3.1 two-layer leaf-encoding bridge** — documents the relationship between the
  attestation-evidence Merkle layer (spec §6.1) and the claim-record Merkle layer enforced by the on-chain
  `claim()`; both legitimate, both verified, formal aggregation function deferred to a v0.3 revision
- **`tools/run_lifecycle.sh`** — convenience runner that smoke-tests the full lifecycle end-to-end against a
  fresh Anvil. CI matrix `lifecycle-smoke` runs `threshold=1` + `threshold=3` on every push. No hex-key
  literals — keys derived at runtime from Anvil's documented test mnemonic via `cast wallet private-key`.
  Explicit SECURITY STANCE comment block documents why the runner is local-dev-only
- **Halmos symbolic suite extended 9 → 11** — adds `check_claim_singleLeafMintsExactAmount` (end-to-end
  propose → finalize → claim → mint chain proven exactly-equal-to-amount for any non-zero
  `(epoch, beneficiary, amount)`) and `check_claim_doubleClaimAlwaysReverts` (per-leaf double-spend
  protection in symbolic form)
- **Whitepaper v0.2 alignment** — stake-gated submitter paragraph rewritten to separate v0.3+ vision from
  v0.2 current state; architecture-diagram settlement layer relabelled to the abstract `LAYER 2 (EVM)`
  pending spec lock
- **SECURITY.md editorial pass** — settlement-layer wording generalised to "EVM-compatible Layer 2",
  consistent with the whitepaper alignment above
- **ROADMAP.md Q4 2026** — verification suite + production deploy model + spec aggregation-function
  carry-over recorded as public momentum signals for grant reviewers and the broader community

### Added (v0.2 pre-audit reviewer pass — independent review hardening, 2026-05-13)

- **`thresholdAtPropose` snapshot** — `AttestationBatch` struct now stores the threshold value at propose
  time as a `uint64`; `finalizeBatch` checks the per-batch snapshot, not the live `threshold` storage.
  Closes the loophole where `setThreshold` could retroactively pass or block an in-flight batch's quorum.
  `setThreshold` itself reverts on values > `type(uint64).max` so the snapshot is always lossless. Pinned by
  3 new unit tests (reviewer H-3)
- **Constructor rejects `challengeWindow = 0`** — new `InvalidChallengeWindow` error. Closes the path where
  a `threshold=1` deploy with zero window could collapse propose + finalize into a single block
  (reviewer L-3)
- **`script/DeployProduction.s.sol` Timelock pre-flight verification** — requires the configured Timelock to
  hold Safe as `PROPOSER_ROLE` + `EXECUTOR_ROLE` and `getMinDelay() >= 24 hours` before broadcast. Without
  this the handoff could succeed cleanly against a mis-configured Timelock and the "ROLE HANDOFF VERIFIED"
  log would give false assurance (reviewer H-1)
- **`contracts/test/DeployProductionHandoff.t.sol`** — 14 tests pinning the ADR-007 interim post-state and
  operational gates (Safe holds DEFAULT_ADMIN + PAUSER, Timelock holds ADMIN, deployer ends bare, Timelock
  does NOT also hold DEFAULT_ADMIN, Safe pauses fast, Timelock slashes via 24h schedule+execute path,
  deployer cannot pause/slash/grant after handoff)
- **`contracts/test/DeployProductionValidation.t.sol`** — `DeployValidator` contract mirrors the script's
  pre-flight validation as a pure function plus 15 negative-path unit tests across every revert reason (zero
  addresses, safe==timelock, missing bytecode, wrong Timelock proposer/executor, sub-24h delay, threshold<3,
  validators<threshold, zero/duplicate validator) (reviewer M-4)
- **Inverse role assertions in handoff tests** — `Safe_doesNotHoldAttesterAdmin`,
  `Deployer_doesNotHoldValidatorRole`, `Safe_doesNotHoldAdmin` in the `_verifyHandoff` require block. The
  original positive-only assertions all passed `assertTrue`; the inverses catch any future refactor that
  accidentally over-grants (reviewer M-3)
- **Leaf encoding now domain-separated** —
  `keccak256(abi.encode(block.chainid, address(this), beneficiary, amount, epoch))`. A Merkle tree built for
  one Attester on one chain is byte-different from a leaf with the same `(beneficiary, amount, epoch)` on
  any sibling deployment. Coordinated change across the contract, six test files, the off-chain Python
  builder (`CHAIN_ID` + `ATTESTER` env vars), the Solidity consumer interface, the lifecycle runner, spec
  §6.3.1, the audit doc, and two example READMEs (reviewer L-1)
- **Final reviewer verdict (second pass)** — "Repo is in audit-ready shape. Ship." 11 of 15 reviewer
  findings closed in code (3H + 4M + 2L + 2 second-pass cleanup); 4 explicitly accepted or deferred and
  documented inline

### Added (v0.2 post-third-pass hardening — second + third reviewer iteration, 2026-05-13)

- **Halmos symbolic suite extended to 15** — added 4 admin-path proofs:
  `check_slash_storesEvidenceAndClearsRole`, `check_slash_zeroAddressAlwaysReverts`,
  `check_setChallengeWindow_updatesValue`, `check_setChallengeWindow_nonAdminReverts`. Every public function
  on the Attester now has at least one symbolic property pinned
- **`tools/run_lifecycle.sh` random ephemeral Anvil port** — closes the wrong-RPC foot-gun (reviewer M-5).
  Picks an unused port from [30000, 40000] via `lsof` retry loop; threads `RPC_URL` through every `cast` /
  `forge` invocation; cleanup trap now also sweeps lifecycle artifacts (`attester.key`, `attestation.json`,
  `batch.json`) and `contracts/broadcast/*/31337` on every exit
- **`NoethrionToken.MAX_SUPPLY` doc lock** — removed "TBD / placeholder / skeleton" wording; documented the
  100B NOET cap rationale and the revisable-before-mainnet language (reviewer L-2)
- **`DeployProduction.s.sol` enumerates each validator address in pre-flight log** — operator can
  glance-verify the parsed `VALIDATORS` env var matches their intent before broadcast (reviewer L-4)
- **`contracts/script/DeployTimelock.s.sol`** — deploys an OZ TimelockController configured per ADR-007 (24h
  min delay, Safe as PROPOSER + EXECUTOR, admin = address(0) for self-administering). Asserts post-deploy
  state matches what `DeployProduction.s.sol` expects, so a misconfigured Timelock cannot end up on chain
  and silently pass the later handoff
- **`docs/runbooks/production-deploy.md`** — canonical v0.2 mainnet deploy procedure (Safe → Timelock →
  Attester + Token + handoff → independent verification grid → announcement → first-batch smoke test →
  operating cadence → sign-offs)
- **`docs/runbooks/incident-response.md`** — pause / slash / re-deploy decision tree; Safe operations for
  emergency pause and 24h-scheduled slash; drill cadence
- **`contracts/test/DeployTimelock.t.sol`** — 10 tests for the Timelock deploy script (5 pre-flight
  rejects + 5 configuration mirrors including the critical "Safe does NOT hold DEFAULT_ADMIN on Timelock"
  absence)
- **Third-pass reviewer findings closed** — CRITICAL C-1 (Python + JS integrator templates were on the OLD
  3-tuple leaf encoding while contract is on the post-L-1 5-tuple; coordinated update of both libraries +
  their docstring examples — caught BEFORE public flip), H-1 (production-deploy.md step 5.1 cast call
  corrected from non-existent `authorizedMinters(...)` to `hasRole(MINTER_ROLE, attester)`), M-1 through M-4
  (audit doc test counts + Halmos table refreshed; ADR-008 forward-reference dropped; ADR-006 Q3 label
  rephrased to cite the actual open-question bullet), L-1 / L-3 (Slither config detector-exclusion rationale
  documented inline; lifecycle runner cleanup trap extended)
- **`BatchProposed` event extended with `thresholdAtPropose`** — off-chain monitors no longer need a
  per-epoch `batches(epoch)` view call to learn the quorum bar that was snapshotted at propose time; pinned
  by `test_ProposeBatch_EmitsThresholdAtProposeInEvent`

### Added (v0.2 fresh-sweep audit closure — challenge-window snapshot + bytecode check, 2026-05-13)

- **CRITICAL C-2 closed — `challengeWindow` snapshotted at propose time.** Symmetric to the
  previously-fixed H-3 threshold snapshot. `AttestationBatch` struct gains an 8th field
  `uint64 challengeWindowAtPropose`; `finalizeBatch` reads the per-batch snapshot, not the live
  `challengeWindow` storage. `setChallengeWindow` now reverts on `newWindow == 0` and on
  `newWindow > type(uint64).max` so the snapshot is always lossless and the zero-bypass is closed. Before
  this fix, an admin (even a 24h-Timelocked admin) calling `setChallengeWindow(0)` could retroactively
  eliminate the unlock delay for every in-flight batch and finalize them in the same block as their
  propose — the third-pass Explore audit caught it; the Halmos check `check_setChallengeWindow_updatesValue`
  had accepted any uint256 with an "operator responsibility" comment, which the security implication did not
  defend
- **MEDIUM M-6 closed — `setTokenContract` bytecode check.** Added
  `if (newToken.code.length == 0) revert NotAContract();`. Closes the silent-broken-state path where admin
  pointed `tokenContract` at an EOA and every `claim()` would call `.mint` against zero bytecode without
  reverting
- **Six new unit tests + one new Halmos check** mirror the threshold-snapshot pattern:
  `test_ProposeBatch_StoresChallengeWindowAtPropose`,
  `test_FinalizeBatch_UsesProposeTimeChallengeWindow_{LowerLater,HigherLater}`,
  `test_SetChallengeWindow_RevertsOnZero`, `test_SetChallengeWindow_RevertsAboveUint64Max`,
  `test_SetTokenContract_RevertsOnNonContract`, plus `check_setChallengeWindow_doesNotAffectInFlightBatch`
  (symbolic equivalent — pins the no-retroactive-shrink guarantee over the entire input space)
- **Eight struct destructure call sites updated** across 6 test files + the lifecycle example + the Solidity
  consumer interface (the `batches(epoch)` getter return tuple grew from 7 to 8 slots)
- **README Russian section line 206 sync** — stale `27/27 тестов` replaced with full match to English
  `127 forge + 16 Halmos`
- **Audit doc + production-deploy runbook totals refreshed** to 127 forge / 16 Halmos / 143 verification
  artifacts
- **New `NotAContract` error** added to `NoethrionAttester` error set (sits alongside `ZeroAddress`,
  `InvalidChallengeWindow`, etc.)

### Added (v0.2 symmetric-coverage closure — Halmos parity + tool self-containment, 2026-05-13)

- **Symmetric pause Halmos coverage** — three new symbolic checks (`check_pause_blocksVoteBatch_alwaysReverts`,
  `check_pause_blocksFinalizeBatch_alwaysReverts`, `check_pause_blocksClaim_alwaysReverts`) complete the
  4-way pause-blocks-mutations matrix at the symbolic layer (commit `89d1376`). The propose-side check was
  already pinned in an earlier round; now every mutation entry point on the contract carries the same
  property symbolically. Attester Halmos suite grew 16 → 19
- **`tools/verify_attestation.py` gains `compute-leaf` subcommand** — closes the integrator foot-gun where
  `verify-merkle --leaf` required a pre-computed hash with no recipe in the script for how to compute it.
  The new subcommand takes the 5-tuple `(chain-id, attester-address, beneficiary, amount, epoch)` and emits
  the leaf hash on stdout; encoding mirrors `examples/lifecycle/03_build_merkle_tree.py` byte-for-byte
  (commit `eaebf55`). The CLI is now self-contained — an integrator can generate leaves, verify Merkle
  proofs, and verify device signatures without needing to also read the contract source
- **NoethrionToken Halmos symbolic suite (6 checks)** — closes the asymmetric coverage gap where Attester
  had 19 Halmos checks and Token had 0 despite being the contract that performs the mint and enforces the
  hard-supply cap. New file `contracts/test/NoethrionToken.halmos.t.sol` pins: mint role gate,
  zero-recipient guard, zero-amount guard, MAX_SUPPLY cap invariant, authorizeMinter role gate,
  authorizeMinter zero-address guard (commit `cc668f5`). Combined Halmos total 19 + 6 = 25 symbolic proofs
  across both contracts; 152 verification artifacts total (127 forge + 25 symbolic)
- **`BatchProposed` event extended with `thresholdAtPropose`** — surfaces the quorum snapshot directly in
  event payload so off-chain monitors no longer need a per-epoch `batches(epoch)` view call (commit
  `4f8d91c`). Pinned by `test_ProposeBatch_EmitsThresholdAtProposeInEvent`
- **Spec §6.2 commitment-record requirements extended** — now lists `thresholdAtPropose` and
  `challengeWindowAtPropose` as required fields of the on-chain commitment record; documents the symmetric
  retroactive-shift closure rationale. Spec §3.5 (Validator role definition) added earlier in the sprint.
  Spec/README change-history updated with both Section-6.2 extensions

### Added (genesis attestation + independent verification network, 2026-06)

- **First on-chain attestation cycle on a public testnet (Sepolia)** — the full protocol lifecycle executed
  against live deployed contracts: device-signed attestation → Merkle batch → propose → finalize → claim →
  mint
- **`docs/proof/` genesis attestation proof page** — public walkthrough of the genesis attestation with
  links to the on-chain transactions, so anyone can inspect the cycle end-to-end
- **`node/` independent verifier node** — a "verify it yourself" watchdog anyone can run; re-derives every
  leaf, replays Merkle proofs against the on-chain committed root, and re-verifies ECDSA P-256 attestation
  signatures. Reference implementations in Python and Go plus a Go→WASM build, all fail-closed; a three-way
  parity test pins identical verdicts across implementations
- **One-line installer scripts** (`node/install.sh`, mirrored at `docs/install.sh`) — curl-pipe-sh setup
  for the verifier node
- **`docs/network/` in-browser self-verification page** — runs the WASM verifier directly in the visitor's
  browser and re-verifies the genesis batch against the on-chain commitment, no installation required

### Security

- Editorial-consistency grep passes on every tracked file
- Leak grep passes — no vault / handoff / internal markers in public files
- All commits signed by YubiKey GPG and Verified on GitHub
- Pre-commit hook scans for secrets (Ethereum private keys, API tokens, credentials)

### Documentation

- All public-facing user documents (README, QUICKSTART, EXAMPLES, FAQ) shipped bilingually (EN + RU)
- Technical specifications (Spec, ADRs, threat model, hardware matrix, audit reports) shipped in English per
  project convention
- Professional Russian-language review of technical documents scheduled post-launch

---

## How this changelog is maintained

Each substantive commit to `main` adds a bullet to the appropriate section of "Unreleased". The verifier
node already ships tagged releases on its own line (`node-v0.1.x`, currently `node-v0.1.1`, each with
platform binaries and `SHA256SUMS`). When the first protocol/spec tagged release ships (anticipated as
`v0.1.0-spec` after the IETF Internet-Draft submission completes one review cycle), the "Unreleased"
section becomes the body of that release; a new empty "Unreleased" section starts immediately above.

Roadmap items that move from planned to shipped graduate from `ROADMAP.md` into this changelog. The two
files together describe "what is done" (changelog) and "what is next" (roadmap).
