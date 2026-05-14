# Production deploy runbook — Noethrion v0.2

> **Audience.** A Foundation operator (or auditor verifying the deploy plan) walking through the full path from an empty mainnet account to a live, role-handed-off Noethrion deployment with the Safe + Timelock + Attester + Token wired per ADR-007.
>
> **Scope.** This runbook is the canonical procedure for v0.2. Any deviation must be approved by the Council and recorded as a deployment-incident note. v0.3 will revise this runbook when the split-role contract change lands.
>
> **Status.** Pre-mainnet. Walk-through verified on a local Anvil; no real-network deploy has happened yet.

---

## 0 · Why this runbook exists

ADR-007 locks the production admin model: a Safe 3-of-5 multi-sig holds `DEFAULT_ADMIN_ROLE` + `PAUSER_ROLE`, an OpenZeppelin `TimelockController` (24-hour delay) holds `ADMIN_ROLE`, and the deployer ends with zero roles on either contract.

The contracts (`contracts/src/NoethrionAttester.sol`, `contracts/src/NoethrionToken.sol`) and the deploy scripts (`contracts/script/DeployProduction.s.sol`, `contracts/script/DeployTimelock.s.sol`) together implement the model. This runbook is the operational glue: which steps in what order, what to verify at each step, who reviews what, and what to do when something fails.

The runbook is conservative on purpose. The cost of slowing down a one-time mainnet deploy by a day is small; the cost of a misconfigured admin model that has to be re-deployed with the existing token holders re-migrated is enormous.

---

## 1 · Prerequisites

### 1.1 People

- **Deployer.** Holds the EOA that pays gas for steps 4–6 and renounces every role at the end. Must NOT be a Foundation signer. Throwaway-style key acceptable.
- **Safe signers (5).** Each holds one of the 5 hardware-wallet-backed keys that compose the 3-of-5 multi-sig. Identity, jurisdiction, and contact for each signer published with the deploy announcement (per ADR-007).
- **Second-pair-of-eyes reviewer (1).** Reads every console output in steps 3–6, cross-checks every address on the block explorer, signs off in writing (Telegram / email / PR comment) before the next step.

### 1.2 Tooling

- Foundry (`forge`, `cast`, `anvil`) — pinned to the version recorded in `contracts/foundry.toml`.
- A funded EOA on the target L2 (deployer's address).
- Block-explorer access on the target L2 (e.g., the chain's Etherscan-equivalent).
- A Safe transaction-builder front end OR an ABI-aware Safe client able to construct and sign role-management calls.

### 1.3 Decisions to lock BEFORE step 1.4

| Parameter | v0.2 minimum | Locked value | Decided by |
|-----------|--------------|--------------|------------|
| `CHALLENGE_WINDOW` (seconds) | > 0 | *TBD per Foundation Council vote* | Council |
| `THRESHOLD` (m in m-of-n) | ≥ 3 | *TBD per validator set finalization* | Foundation operations |
| `VALIDATORS` (list of addresses) | ≥ `THRESHOLD` distinct | *TBD per Foundation operations* | Foundation operations |
| Settlement layer | EVM-compatible Layer 2 | *TBD per spec lock* | Spec working group |
| Timelock `MIN_DELAY` | ≥ 86400 (24h) | 86400 | ADR-007 |

Fill these in below before the deploy session begins. Do not start step 2 with a single TBD remaining.

### 1.4 Pre-deploy security checklist

Read top-to-bottom before any tx is broadcast.

- [ ] Latest `main` commit on `noethrion/noethrion` matches the SHA you intend to deploy. Cross-check against the audit report's pinned SHA in `docs/audit/smart-contracts-audit.md`.
- [ ] `forge test` passes locally on that SHA (127/127 — re-confirm count against the audit report's pinned SHA).
- [ ] `halmos` passes locally on that SHA — 19/19 on `NoethrionAttesterHalmosTest` + 6/6 on `NoethrionTokenHalmosTest` = 25/25 symbolic proofs across both contracts.
- [ ] `./tools/run_lifecycle.sh` and `THRESHOLD=3 ./tools/run_lifecycle.sh` both print `LIFECYCLE PASS` locally.
- [ ] External smart-contract audit complete. Findings either closed in code (commit hashes recorded) or accepted in writing by the Council.
- [ ] Deployer's machine has hardware-wallet signing OR an isolated air-gapped key bundle. Deployer's private key MUST NOT live on a shared host.
- [ ] Second-pair-of-eyes reviewer is reachable in real time for the duration of the deploy.

If any box above is unchecked, abort the session. There is no schedule pressure that justifies a half-checked deploy.

---

## 2 · Deploy the Safe multi-sig

Use the Safe's official front end (the `Create Safe` flow), NOT a custom script. Reasons: the Safe deployment contract is well-known; the front end handles signer order and threshold without hand-rolled tx construction; the resulting address ends up cross-indexed on Safe's own infrastructure (proxy lookup, transaction batching UI).

### 2.1 Parameters

- Network: the locked settlement L2.
- Owners: the 5 signer addresses (hardware-wallet-backed; identities published).
- Threshold: 3 of 5.
- Payment options: skip (deployer pays gas).

### 2.2 Verification

After the Safe is deployed, cross-check on the explorer:

- The Safe is a `GnosisSafeProxy` pointing at the chain's canonical singleton.
- The owner list matches the intended 5 addresses (no extras, no zeroes).
- The threshold is 3.

Record the Safe address. This is `MAINNET_SAFE` for the next steps.

---

## 3 · Deploy the TimelockController

```bash
# Replace each <…> placeholder before running. Do NOT paste private keys
# into your shell history — use `read -rs PRIVATE_KEY` or pipe from a
# hardware-wallet signer.
read -rs -p "PRIVATE_KEY: " PRIVATE_KEY; echo
export PRIVATE_KEY
export MAINNET_SAFE=<safe-address-from-step-2.2>
export MIN_DELAY=86400
forge script contracts/script/DeployTimelock.s.sol \
    --rpc-url "$MAINNET_RPC_URL" --broadcast --verify
```

The script asserts post-deploy that:

- The Safe holds `PROPOSER_ROLE` on the Timelock.
- The Safe holds `EXECUTOR_ROLE` on the Timelock.
- `getMinDelay() == MIN_DELAY` (≥ 24h).
- Neither the deployer nor the Safe holds `DEFAULT_ADMIN_ROLE` on the Timelock — the Timelock self-administers.

If any assertion fails, the broadcast reverts and no Timelock address ends up on chain. Re-run after fixing the root cause; do NOT proceed with a partial deploy.

Record the Timelock address. This is `MAINNET_TIMELOCK` for step 4.

---

## 4 · Deploy + hand off Attester + Token

```bash
# Same PRIVATE_KEY as step 3; read it interactively, do not echo to history.
read -rs -p "PRIVATE_KEY: " PRIVATE_KEY; echo
export PRIVATE_KEY
export MAINNET_SAFE=<safe-address>
export MAINNET_TIMELOCK=<timelock-address-from-step-3>
export CHALLENGE_WINDOW=<locked-value>
export THRESHOLD=<locked-value>
export VALIDATORS=<v1>,<v2>,<v3>,<v4>,<v5>   # locked validator set
forge script contracts/script/DeployProduction.s.sol \
    --rpc-url "$MAINNET_RPC_URL" --broadcast --verify
```

The script's pre-flight `require()` block enforces:

- Every address non-zero, non-deployer, distinct from each other.
- Safe and Timelock both have bytecode (catches typo'd addresses).
- Timelock has Safe as `PROPOSER_ROLE` and `EXECUTOR_ROLE`, `getMinDelay() >= 24h`.
- Threshold ≥ 3.
- Validators array length ≥ threshold; no duplicates; no zero addresses.
- Each validator address echoed on its own line for glance-verification.

Then it broadcasts in this order:

1. Deploy `NoethrionToken` (deployer = admin).
2. Deploy `NoethrionAttester` (deployer = admin).
3. Wire: `attester.setTokenContract(token)` + `token.authorizeMinter(attester)`.
4. For each validator: `grantRole(VALIDATOR_ROLE, validator)`.
5. Grant Safe `DEFAULT_ADMIN_ROLE` + `PAUSER_ROLE` on Attester.
6. Grant Timelock `ADMIN_ROLE` on Attester.
7. Grant Safe `DEFAULT_ADMIN_ROLE` on Token.
8. Deployer renounces every role on both contracts.

Then it asserts via `require()` that:

- Each post-handoff role is held by the expected contract.
- The deployer holds zero roles.
- The Timelock does NOT also hold `DEFAULT_ADMIN_ROLE` (would short-circuit ADR-007).
- The Safe does NOT also hold `ADMIN_ROLE` (would bypass the 24h timelock).
- Every configured validator holds `VALIDATOR_ROLE`.

If any assertion fails, the broadcast reverts. Investigate, re-deploy from scratch.

Record `ATTESTER` and `TOKEN`. These plus the Safe and Timelock are the four canonical addresses for the announcement.

---

## 5 · Independent post-deploy verification

Done by the second-pair-of-eyes reviewer using `cast`, NOT trust in the script's own `require()`s.

```bash
# Replace addresses with the deployed values.
ATTESTER=<attester-address>
TOKEN=<token-address>
SAFE=<safe-address>
TIMELOCK=<timelock-address>
DEPLOYER=<deployer-address>
RPC="$MAINNET_RPC_URL"

# 5.1 Confirm the wiring.
cast call "$ATTESTER" "tokenContract()(address)" --rpc-url "$RPC"
# Token uses AccessControl's MINTER_ROLE, not a separate `authorizedMinters` mapping.
MINTER_ROLE=$(cast call "$TOKEN" "MINTER_ROLE()(bytes32)" --rpc-url "$RPC")
cast call "$TOKEN" "hasRole(bytes32,address)(bool)" "$MINTER_ROLE" "$ATTESTER" --rpc-url "$RPC"
cast call "$ATTESTER" "threshold()(uint256)" --rpc-url "$RPC"
cast call "$ATTESTER" "challengeWindow()(uint256)" --rpc-url "$RPC"

# 5.2 Confirm role matrix.
DEFAULT_ADMIN=0x0000000000000000000000000000000000000000000000000000000000000000
ADMIN_ROLE=$(cast call "$ATTESTER" "ADMIN_ROLE()(bytes32)" --rpc-url "$RPC")
PAUSER_ROLE=$(cast call "$ATTESTER" "PAUSER_ROLE()(bytes32)" --rpc-url "$RPC")
VALIDATOR_ROLE=$(cast call "$ATTESTER" "VALIDATOR_ROLE()(bytes32)" --rpc-url "$RPC")

# Safe should have DEFAULT_ADMIN_ROLE + PAUSER_ROLE.
cast call "$ATTESTER" "hasRole(bytes32,address)(bool)" "$DEFAULT_ADMIN" "$SAFE" --rpc-url "$RPC"
cast call "$ATTESTER" "hasRole(bytes32,address)(bool)" "$PAUSER_ROLE" "$SAFE" --rpc-url "$RPC"
# Safe should NOT have ADMIN_ROLE.
cast call "$ATTESTER" "hasRole(bytes32,address)(bool)" "$ADMIN_ROLE" "$SAFE" --rpc-url "$RPC"

# Timelock should have ADMIN_ROLE only.
cast call "$ATTESTER" "hasRole(bytes32,address)(bool)" "$ADMIN_ROLE" "$TIMELOCK" --rpc-url "$RPC"
# Timelock should NOT have DEFAULT_ADMIN_ROLE.
cast call "$ATTESTER" "hasRole(bytes32,address)(bool)" "$DEFAULT_ADMIN" "$TIMELOCK" --rpc-url "$RPC"

# Each validator should have VALIDATOR_ROLE — loop over each address from VALIDATORS list.

# Deployer must have zero roles.
cast call "$ATTESTER" "hasRole(bytes32,address)(bool)" "$DEFAULT_ADMIN" "$DEPLOYER" --rpc-url "$RPC"
cast call "$ATTESTER" "hasRole(bytes32,address)(bool)" "$ADMIN_ROLE" "$DEPLOYER" --rpc-url "$RPC"
cast call "$ATTESTER" "hasRole(bytes32,address)(bool)" "$PAUSER_ROLE" "$DEPLOYER" --rpc-url "$RPC"

# Token: Safe should have DEFAULT_ADMIN_ROLE; deployer should not.
cast call "$TOKEN" "hasRole(bytes32,address)(bool)" "$DEFAULT_ADMIN" "$SAFE" --rpc-url "$RPC"
cast call "$TOKEN" "hasRole(bytes32,address)(bool)" "$DEFAULT_ADMIN" "$DEPLOYER" --rpc-url "$RPC"
```

Every check that prints `true` must be a check expected to be `true`. Every check that prints `false` must be a check expected to be `false`. The reviewer signs off in writing only after the entire grid is verified.

---

## 6 · Announcement

Do NOT announce before step 5 is signed off.

### 6.1 Canonical addresses

Publish exactly four addresses, in this order, in every channel:

```
Attester:  <attester-address>
Token:     <token-address>
Safe:      <safe-address>
Timelock:  <timelock-address>
```

Plus the deployed source SHA from `noethrion/noethrion` and a link to the audit report.

### 6.2 Channels

- GitHub release on `noethrion/noethrion` with the canonical addresses, the SHA, and links to ADR-007 + the audit report.
- Mirror.xyz / Paragraph post.
- Twitter thread (already drafted).
- Farcaster cast.

### 6.3 Validator-set publication

Each validator's identity, jurisdiction, and contact published alongside the contract addresses. This is operational transparency, not legal disclosure — it lets relying parties attribute on-chain votes.

---

## 7 · First-batch smoke test

Before any production attestation hits the deployed Attester, run a manual smoke test with a synthetic batch:

1. Off-chain: build a 3-leaf Merkle tree using `examples/lifecycle/03_build_merkle_tree.py` with the production `CHAIN_ID` + the deployed Attester address. Use a Foundation-controlled beneficiary address (NOT a real third party).
2. On-chain: `THRESHOLD - 1` validators (other than the proposer) call `voteBatch` until quorum.
3. Wait the full `CHALLENGE_WINDOW` (do NOT use any time-warp — there is no `evm_increaseTime` on a real chain).
4. Anyone calls `finalizeBatch(epoch)`.
5. Anyone calls `claim(epoch, proof, beneficiary, amount)` with the leaf from step 1.
6. Verify the Foundation-controlled beneficiary received exactly `amount` NOET.

If step 6 produces the wrong amount or reverts, **PAUSE** the contract from the Safe (see `incident-response.md`) and investigate before another batch lands.

---

## 8 · Operating cadence after launch

| Action | Path | Cadence |
|--------|------|---------|
| Real-batch propose + finalize | Validator quorum + `claim` redemptions | Per protocol attestation rate |
| `setChallengeWindow` tuning | Safe schedules via Timelock (24h delay) | Rare; documented in a future ADR before mainnet |
| `setThreshold` tuning | Safe schedules via Timelock (24h delay) | Rare |
| `slash` a validator | Safe schedules via Timelock (24h delay) | Per fraud-proof evidence |
| `pause` / `unpause` | Safe directly (no delay) | Incident only |
| Adding a new validator | Safe directly via `grantRole(VALIDATOR_ROLE, addr)` | Per validator-set update |
| Revoking a validator (non-slash) | Safe directly via `revokeRole(VALIDATOR_ROLE, addr)` | Per validator-set update |

The `Safe schedules via Timelock` rows correspond to: signer A in the Safe builds a `schedule(target, value, data, predecessor, salt, delay)` call to the Timelock; 3 of 5 signers approve; 24 hours later, signer B in the Safe builds the matching `execute(...)` call; 3 of 5 signers approve. Off-chain monitors observe the `schedule` event during the 24h window and surface it for review.

---

## 9 · Incident response

See `docs/runbooks/incident-response.md` for the full procedure. Brief:

- **Pause** is the first lever for ANY non-trivial incident. The Safe pauses; investigation follows; un-pause only after the root cause is documented.
- **Slash** is the second lever, used for sustained validator misbehaviour with evidence.
- **Re-deploy** is the last lever, used only if the contract itself is found vulnerable post-audit. There is no contract upgrade path — re-deploy means a new Attester address and a migration ceremony with existing holders.

---

## 10 · Sign-offs

Recorded as PR comments on a `deploy-2026-XX-XX.md` artifact in the same PR, OR via a separate signing ceremony (Foundation Council vote record).

- [ ] Deployer
- [ ] Second-pair-of-eyes reviewer
- [ ] All 5 Safe signers acknowledge the Safe address and threshold
- [ ] Council approves the locked parameters (challenge window, threshold, validator set)
- [ ] External auditor cross-references the deployed SHA against the audit report

---

## Cross-references

- ADR-004 (Swiss Stiftung) — the Foundation holds the multi-sig.
- ADR-006 (m-of-n quorum) — the validator role definitions this runbook configures.
- ADR-007 (production admin model) — the binding design this runbook implements.
- `docs/audit/smart-contracts-audit.md` — the pre-audit posture report; SHA cross-reference.
- `docs/runbooks/incident-response.md` — when something goes wrong post-launch.
- `contracts/script/DeployTimelock.s.sol` — step 3.
- `contracts/script/DeployProduction.s.sol` — step 4.
- `contracts/test/DeployProductionHandoff.t.sol` + `DeployProductionValidation.t.sol` — pre-flight test coverage for the script paths above.
