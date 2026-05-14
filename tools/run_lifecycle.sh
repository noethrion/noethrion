#!/usr/bin/env bash
#
# Drive the lifecycle examples end-to-end against a freshly-started Anvil
# instance. On success: NOET is minted for the leaf claimed in step 06, the
# on-chain balance matches the leaf amount exactly, and the off-chain verifier
# in step 07 prints PASS.
#
# This is the "convenience runner" that the lifecycle README has been pointing
# at as a roadmap item. It does NOT replace the manual walkthrough — the goal
# is a single command that smoke-tests the full path, useful for CI and for
# quickly proving that a code change did not break the end-to-end behaviour.
#
# Run from the repository root (or any directory — the script chdirs):
#   ./tools/run_lifecycle.sh
#
# Tears down Anvil on exit (clean exit or error).
#
# Dependencies: foundry (anvil, cast, forge), python3 with cryptography and
# pycryptodome, openssl, jq is NOT required (we use python3 -c for JSON).

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
cd "$REPO"

# Threshold can be overridden — set THRESHOLD=N (1..5) to exercise the m-of-n
# quorum path. With THRESHOLD=1 the proposer's call alone satisfies the quorum
# (default). With THRESHOLD>1 the runner grants VALIDATOR_ROLE to additional
# Anvil accounts and calls voteBatch from each until quorum is reached.
THRESHOLD="${THRESHOLD:-1}"
if ! [[ "$THRESHOLD" =~ ^[1-5]$ ]]; then
  echo "[!] THRESHOLD must be an integer in [1, 5] (got '$THRESHOLD')" >&2
  exit 2
fi

# ─── SECURITY STANCE ─────────────────────────────────────────────────────────
# THIS RUNNER IS LOCAL-DEV-ONLY. It is hard-coded to use Anvil's documented
# deterministic test mnemonic ("test test ... junk", well-known public, see
# Foundry book), and assumes every key it touches is throwaway. It MUST NEVER
# be pointed at a real RPC endpoint with real funds, because:
#
#   - Keys are derived in this shell and passed to `cast send` via the
#     `--private-key` flag, which puts the key string in process argv.
#     On a multi-tenant host that argv is readable through /proc/<pid>/cmdline
#     by other processes — fine for public test keys, catastrophic for real
#     keys. Real-network deployment uses contracts/script/DeployProduction.s.sol
#     plus a hardware wallet / Safe signer pipeline, NOT this runner.
#   - The secrets-guard pre-commit hook flags 0x+64hex literals to prevent
#     real keys from being committed by mistake. We derive the test keys at
#     runtime from a mnemonic string (not 0x+hex) so the hook stays clean and
#     this file does not look like a real-key dump.
#   - The challenge window is shrunk via `evm_increaseTime` (an Anvil cheat).
#     That cheat does not exist on a real chain.
ANVIL_MNEMONIC="test test test test test test test test test test test junk"
derive_pk() {
  # derive_pk <index>
  cast wallet private-key --mnemonic "$ANVIL_MNEMONIC" --mnemonic-index "$1"
}
derive_addr() {
  # derive_addr <index>
  cast wallet address --mnemonic "$ANVIL_MNEMONIC" --mnemonic-index "$1"
}

DEPLOYER_PK="$(derive_pk 0)"

# Pin Anvil to a random ephemeral port (not the default 8545) so the runner
# cannot accidentally talk to a separate Anvil / geth / hardhat node a
# developer left running on the default port — which would otherwise see
# the deployer private key in cast's --private-key argv. Re-resolved on
# every run; collisions inside [30000, 40000] retried up to 10 times.
pick_port() {
  for _ in {1..10}; do
    local p=$((30000 + RANDOM % 10000))
    if ! lsof -nP -iTCP:"$p" -sTCP:LISTEN 2>/dev/null | grep -q LISTEN; then
      echo "$p"; return 0
    fi
  done
  echo "[!] could not find a free port in [30000, 40000] after 10 tries" >&2
  return 1
}
ANVIL_PORT="$(pick_port)"
RPC_URL="http://localhost:$ANVIL_PORT"

ANVIL_PID=""
ANVIL_LOG="$(mktemp -t noethrion-anvil.XXXXXX)"

cleanup() {
  local exit_code=$?
  if [[ -n "$ANVIL_PID" ]] && kill -0 "$ANVIL_PID" 2>/dev/null; then
    kill "$ANVIL_PID" 2>/dev/null || true
    wait "$ANVIL_PID" 2>/dev/null || true
  fi
  rm -f "$ANVIL_LOG"
  # Sweep local lifecycle artifacts so a developer's working tree stays clean
  # after the runner exits. These are all gitignored, but leaving them around
  # creates optics issues (PEM private key in the tree even though synthetic).
  rm -f examples/lifecycle/attester.key \
        examples/lifecycle/attester.key.pub \
        examples/lifecycle/attestation.json \
        examples/lifecycle/batch.json
  # Also sweep forge broadcast artifacts from the Anvil chain id (31337) so
  # `git status` stays clean. These are gitignored too; the sweep just keeps
  # the working tree tidy.
  rm -rf contracts/broadcast/Deploy.s.sol/31337 \
         contracts/broadcast/DeployProduction.s.sol/31337 \
         contracts/broadcast/DeployTimelock.s.sol/31337 2>/dev/null || true
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

bjson() {
  # JSON field reader: bjson <path> <python-expression-on-loaded-dict>
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$1" "$2"
}

# ─── Start Anvil ─────────────────────────────────────────────────────────────

echo "[*] Starting Anvil on port $ANVIL_PORT (silent)..."
anvil --silent --port "$ANVIL_PORT" >"$ANVIL_LOG" 2>&1 &
ANVIL_PID=$!

for i in {1..30}; do
  if cast block latest --rpc-url "$RPC_URL" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done
if ! cast block latest --rpc-url "$RPC_URL" >/dev/null 2>&1; then
  echo "[!] Anvil failed to start. Log:" >&2
  cat "$ANVIL_LOG" >&2
  exit 1
fi
echo "[*] Anvil up (PID $ANVIL_PID, port $ANVIL_PORT)"

# ─── Deploy ──────────────────────────────────────────────────────────────────

echo "[*] Deploying Attester + Token (threshold=$THRESHOLD)..."
DEPLOY_OUTPUT=$(
  PRIVATE_KEY="$DEPLOYER_PK" THRESHOLD="$THRESHOLD" \
    forge script contracts/script/Deploy.s.sol \
    --root contracts \
    --rpc-url "$RPC_URL" --broadcast 2>&1
)

ATTESTER=$(echo "$DEPLOY_OUTPUT" | grep -E "^\s*ATTESTER:" | tail -1 | awk '{print $NF}')
TOKEN=$(echo "$DEPLOY_OUTPUT" | grep -E "^\s*TOKEN" | tail -1 | awk '{print $NF}')

if [[ -z "$ATTESTER" || -z "$TOKEN" ]]; then
  echo "[!] Could not parse deployed addresses. Deploy output:" >&2
  echo "$DEPLOY_OUTPUT" >&2
  exit 1
fi
echo "[*] ATTESTER : $ATTESTER"
echo "[*] TOKEN    : $TOKEN"

# ─── Extra validator setup (only when THRESHOLD > 1) ─────────────────────────
# Deploy.s.sol grants VALIDATOR_ROLE to a single VALIDATOR (defaults to the
# deployer). For threshold > 1 we need (threshold - 1) additional validators
# with the role. Grant them from the deployer (who holds DEFAULT_ADMIN_ROLE).

EXTRA_VALIDATOR_ADDRS=()
EXTRA_VALIDATOR_PKS=()
if [[ "$THRESHOLD" -gt 1 ]]; then
  VALIDATOR_ROLE=$(cast call "$ATTESTER" "VALIDATOR_ROLE()(bytes32)" \
    --rpc-url "$RPC_URL")
  for i in $(seq 1 $((THRESHOLD - 1))); do
    EXTRA_PK="$(derive_pk "$i")"
    EXTRA_ADDR="$(derive_addr "$i")"
    EXTRA_VALIDATOR_ADDRS+=("$EXTRA_ADDR")
    EXTRA_VALIDATOR_PKS+=("$EXTRA_PK")
    cast send "$ATTESTER" "grantRole(bytes32,address)" \
      "$VALIDATOR_ROLE" "$EXTRA_ADDR" \
      --private-key "$DEPLOYER_PK" \
      --rpc-url "$RPC_URL" >/dev/null
    echo "[*] granted VALIDATOR_ROLE to extra validator $i : $EXTRA_ADDR"
  done
fi

# ─── 01 Generate device key ──────────────────────────────────────────────────

# Clean any artifacts from a previous run so a re-run is idempotent. These
# files are in .gitignore at the repo root.
rm -f examples/lifecycle/attester.key \
      examples/lifecycle/attester.key.pub \
      examples/lifecycle/attestation.json \
      examples/lifecycle/batch.json

echo "[01] Generating device key..."
python3 tools/provision_atecc.py generate-key \
  --out examples/lifecycle/attester.key >/dev/null

# ─── 02 Sign attestation ─────────────────────────────────────────────────────

echo "[02] Signing sample attestation..."
bash examples/lifecycle/02_sign_attestation.sh >/dev/null

# ─── 03 Build Merkle tree ────────────────────────────────────────────────────

echo "[03] Building Merkle tree (with chain+attester domain separator)..."
# Anvil's default chainId is 31337. The builder folds chain_id + attester_addr
# into each leaf so the resulting Merkle root binds to exactly this Attester
# instance on this chain — replay against a different deployment fails the
# InvalidMerkleProof check inside claim().
ATTESTER="$ATTESTER" CHAIN_ID="${CHAIN_ID:-31337}" \
  python3 examples/lifecycle/03_build_merkle_tree.py >/dev/null

BATCH_JSON="examples/lifecycle/batch.json"
EPOCH=$(bjson "$BATCH_JSON" "d['epoch']")
ROOT=$(bjson "$BATCH_JSON" "d['root']")
TOTAL_WH=$(bjson "$BATCH_JSON" "d['totalKwh']")
echo "[03] epoch=$EPOCH root=$ROOT totalKwh=$TOTAL_WH"

# ─── 04 Propose batch ────────────────────────────────────────────────────────
#
# The Solidity example scripts at examples/lifecycle/04..06 are documentation
# (they show the exact env-var and forge-script invocation a developer would
# use). This runner takes the faster + foundry-config-independent path of
# calling the contract via `cast send` directly. Both produce identical
# on-chain effects; the example scripts remain the readable reference.

echo "[04] Proposing batch..."
cast send "$ATTESTER" "proposeBatch(uint64,bytes32,uint128)" \
  "$EPOCH" "$ROOT" "$TOTAL_WH" \
  --private-key "$DEPLOYER_PK" \
  --rpc-url "$RPC_URL" >/dev/null

# The proposer's submission counts as their first vote. For THRESHOLD > 1 we
# loop through the extra validators granted above, voting until quorum is met.
# Each extra validator must be DISTINCT from the proposer (the contract
# reverts with AlreadyVoted otherwise) — guaranteed here because validator i
# is derived from mnemonic index i and the deployer is index 0.
if [[ "$THRESHOLD" -gt 1 ]]; then
  echo "[04b] Voting from $((THRESHOLD - 1)) additional validator(s) to reach quorum..."
  for i in "${!EXTRA_VALIDATOR_PKS[@]}"; do
    EXTRA_PK="${EXTRA_VALIDATOR_PKS[$i]}"
    EXTRA_ADDR="${EXTRA_VALIDATOR_ADDRS[$i]}"
    cast send "$ATTESTER" "voteBatch(uint64)" "$EPOCH" \
      --private-key "$EXTRA_PK" \
      --rpc-url "$RPC_URL" >/dev/null
    VOTES_NOW=$(cast call "$ATTESTER" "voteCount(uint64)(uint256)" "$EPOCH" \
      --rpc-url "$RPC_URL")
    echo "[04b]   vote $((i + 2)) from $EXTRA_ADDR -> voteCount = ${VOTES_NOW%% *}"
  done
fi

# Sanity-check the on-chain voteCount matches the threshold exactly before
# attempting finalization. A mismatch here would mean either the role grant
# failed silently or a vote was rejected; either way, finalize would revert.
VOTES_FINAL=$(cast call "$ATTESTER" "voteCount(uint64)(uint256)" "$EPOCH" \
  --rpc-url "$RPC_URL" | awk '{print $1}')
if [[ "$VOTES_FINAL" -lt "$THRESHOLD" ]]; then
  echo "[!] voteCount=$VOTES_FINAL below THRESHOLD=$THRESHOLD; cannot finalize" >&2
  exit 1
fi

# ─── 05 Finalize (warp time + finalize) ──────────────────────────────────────

echo "[05] Warping past challenge window and finalizing..."
cast rpc evm_increaseTime 3700 --rpc-url "$RPC_URL" >/dev/null
cast rpc evm_mine --rpc-url "$RPC_URL" >/dev/null
cast send "$ATTESTER" "finalizeBatch(uint64)" "$EPOCH" \
  --private-key "$DEPLOYER_PK" \
  --rpc-url "$RPC_URL" >/dev/null

# ─── 06 Claim leaf 0 (alice, 100 NOET) ───────────────────────────────────────

BENEFICIARY=$(bjson "$BATCH_JSON" "d['leaves'][0]['beneficiary']")
AMOUNT=$(bjson "$BATCH_JSON" "d['leaves'][0]['amount_wei']")
PROOF_BRACKETED=$(bjson "$BATCH_JSON" "'[' + ','.join(d['leaves'][0]['proof']) + ']'")

echo "[06] Claiming leaf 0 -> $BENEFICIARY ($AMOUNT wei)..."
cast send "$ATTESTER" "claim(uint64,bytes32[],address,uint128)" \
  "$EPOCH" "$PROOF_BRACKETED" "$BENEFICIARY" "$AMOUNT" \
  --private-key "$DEPLOYER_PK" \
  --rpc-url "$RPC_URL" >/dev/null

# Sanity-check the on-chain balance matches the claimed amount exactly.
BAL_RAW=$(cast call "$TOKEN" "balanceOf(address)(uint256)" "$BENEFICIARY" \
  --rpc-url "$RPC_URL")
BAL=$(echo "$BAL_RAW" | awk '{print $1}')
if [[ "$BAL" != "$AMOUNT" ]]; then
  echo "[!] balance mismatch: got '$BAL', expected '$AMOUNT'" >&2
  exit 1
fi
echo "[06] on-chain balance = $BAL wei (matches expected)"

# ─── 07 Off-chain verifier ───────────────────────────────────────────────────

echo "[07] Off-chain verifying attestation signature..."
bash examples/lifecycle/07_verify_offchain.sh >/dev/null

echo ""
echo "==== LIFECYCLE PASS ===="
echo "  ATTESTER : $ATTESTER"
echo "  TOKEN    : $TOKEN"
echo "  Epoch    : $EPOCH"
echo "  Claimed  : $AMOUNT wei to $BENEFICIARY"
