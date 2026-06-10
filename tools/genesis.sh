#!/usr/bin/env bash
#
# genesis.sh — drive ONE full attestation lifecycle against a PUBLIC TESTNET
# (e.g. Sepolia) to produce a "genesis" on-chain attestation: deploy
# Attester + Token, propose a batch, wait the REAL challenge window, finalize,
# and claim — minting NOET for the first time on a public network. Prints the
# block-explorer links for the launch announcement.
#
# This is the testnet sibling of tools/run_lifecycle.sh. The crucial
# differences:
#   - run_lifecycle.sh is Anvil-ONLY: it uses the evm_increaseTime cheat to skip
#     the challenge window and Anvil's deterministic test mnemonic. Neither
#     exists on a real chain.
#   - genesis.sh talks to a REAL testnet RPC and WAITS the real challenge window
#     (default 60s) with a genuine `sleep` + on-chain timestamp check.
#
# ─── SECURITY STANCE — READ THIS ─────────────────────────────────────────────
# TESTNET ONLY. The PRIVATE_KEY you pass MUST be a disposable, ZERO-VALUE key
# used for nothing else. The key is passed to `forge`/`cast` via env + the
# --private-key flag (process argv / environ), which is readable by other
# processes on a multi-tenant host. That is fine for a throwaway testnet key and
# CATASTROPHIC for a real one. Mainnet / real value uses
# contracts/script/DeployProduction.s.sol + a hardware-wallet / Safe pipeline,
# NOT this script. genesis.sh refuses to run against mainnet chain ids and
# requires an explicit CONFIRM_TESTNET=yes acknowledgement.
#
# ─── USAGE ───────────────────────────────────────────────────────────────────
#   # 1. A disposable testnet key with some faucet ETH on Sepolia.
#   export PRIVATE_KEY=<0x... disposable testnet key>
#   export RPC_URL="https://sepolia.infura.io/v3/<your-key>"   # or Alchemy/public
#   export CHAIN_ID=11155111            # Sepolia
#   export CONFIRM_TESTNET=yes          # required safety acknowledgement
#   export CHALLENGE_WINDOW=60          # optional, seconds (default 60)
#   ./tools/genesis.sh
#
# On success prints ATTESTER, TOKEN, the claimed amount, and explorer links.
#
# Dependencies: foundry (forge, cast), python3 with cryptography + pycryptodome.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
cd "$REPO"

# ─── Required configuration ──────────────────────────────────────────────────
# The disposable key may be supplied directly (PRIVATE_KEY) or via a JSON
# keystore file path (KEYFILE) — the latter keeps the secret out of shell
# history / process argv at the call site. KEYFILE accepts the `cast wallet new
# --json` shape ({"address","private_key"} or a list thereof).
if [[ -z "${PRIVATE_KEY:-}" && -n "${KEYFILE:-}" ]]; then
  PRIVATE_KEY="$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); w=d[0] if isinstance(d,list) else d; print(w.get('private_key') or w.get('privateKey'))" "$KEYFILE")"
  export PRIVATE_KEY
fi
: "${PRIVATE_KEY:?set PRIVATE_KEY (or KEYFILE) to a DISPOSABLE testnet key (zero value)}"
: "${RPC_URL:?set RPC_URL to a testnet RPC endpoint}"
CHAIN_ID="${CHAIN_ID:?set CHAIN_ID (e.g. 11155111 for Sepolia)}"
CHALLENGE_WINDOW="${CHALLENGE_WINDOW:-60}"

# ─── Safety gates ─────────────────────────────────────────────────────────────
if [[ "${CONFIRM_TESTNET:-}" != "yes" ]]; then
  echo "[!] Refusing to run without CONFIRM_TESTNET=yes." >&2
  echo "    genesis.sh is TESTNET-ONLY and expects a disposable, zero-value key." >&2
  exit 2
fi
# Hard-block known mainnet chain ids (1 = Ethereum, 8453 = a popular L2 mainnet,
# 10 = another L2 mainnet, 137 = a sidechain mainnet). Testnets are allowed.
case "$CHAIN_ID" in
  1|10|137|8453|42161|43114)
    echo "[!] CHAIN_ID=$CHAIN_ID looks like a MAINNET. genesis.sh is testnet-only." >&2
    echo "    Mainnet deployment uses DeployProduction.s.sol + a hardware signer." >&2
    exit 2 ;;
esac
if [[ "$RPC_URL" == *"localhost"* || "$RPC_URL" == *"127.0.0.1"* ]]; then
  echo "[!] RPC_URL points at localhost — use tools/run_lifecycle.sh for Anvil." >&2
  exit 2
fi
if ! [[ "$CHALLENGE_WINDOW" =~ ^[0-9]+$ ]] || [[ "$CHALLENGE_WINDOW" -lt 1 ]]; then
  echo "[!] CHALLENGE_WINDOW must be a positive integer (seconds)." >&2
  exit 2
fi

# ─── Artifact cleanup (idempotent re-runs; never leave a key file behind) ─────
cleanup() {
  local code=$?
  rm -f examples/lifecycle/attester.key \
        examples/lifecycle/attester.key.pub \
        examples/lifecycle/attestation.json \
        examples/lifecycle/batch.json
  exit "$code"
}
trap cleanup EXIT INT TERM

bjson() {
  python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$1" "$2"
}

# Explorer base for the links we print at the end.
explorer_base() {
  case "$CHAIN_ID" in
    11155111) echo "https://sepolia.etherscan.io" ;;
    17000)    echo "https://holesky.etherscan.io" ;;
    *)        echo "" ;;
  esac
}
EXPLORER="$(explorer_base)"

DEPLOYER="$(cast wallet address --private-key "$PRIVATE_KEY")"
echo "[*] Network        : chainId=$CHAIN_ID  rpc=$RPC_URL"
echo "[*] Deployer       : $DEPLOYER"
echo "[*] Challenge window: ${CHALLENGE_WINDOW}s (REAL wait — no time-warp on a live chain)"
echo "[*] Threshold      : 1 (single-validator genesis)"

# Confirm the deployer actually has gas before we start broadcasting.
BAL_WEI="$(cast balance "$DEPLOYER" --rpc-url "$RPC_URL")"
if [[ "$BAL_WEI" == "0" ]]; then
  echo "[!] Deployer balance is 0 — fund $DEPLOYER from a testnet faucet first." >&2
  exit 1
fi
echo "[*] Deployer balance: $(cast from-wei "$BAL_WEI") ETH"

# ─── Deploy ───────────────────────────────────────────────────────────────────
echo "[*] Deploying Attester + Token (challengeWindow=$CHALLENGE_WINDOW, threshold=1)..."
DEPLOY_OUTPUT=$(
  PRIVATE_KEY="$PRIVATE_KEY" CHALLENGE_WINDOW="$CHALLENGE_WINDOW" THRESHOLD=1 \
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

# ─── 01 device key · 02 sign · 03 merkle ──────────────────────────────────────
rm -f examples/lifecycle/attester.key examples/lifecycle/attester.key.pub \
      examples/lifecycle/attestation.json examples/lifecycle/batch.json

echo "[01] Generating device key (P-256, software stand-in for the secure element)..."
python3 tools/provision_atecc.py generate-key \
  --out examples/lifecycle/attester.key >/dev/null

echo "[02] Signing sample attestation..."
bash examples/lifecycle/02_sign_attestation.sh >/dev/null

echo "[03] Building Merkle tree (domain-separated by chainId=$CHAIN_ID + attester)..."
ATTESTER="$ATTESTER" CHAIN_ID="$CHAIN_ID" \
  python3 examples/lifecycle/03_build_merkle_tree.py >/dev/null

BATCH_JSON="examples/lifecycle/batch.json"
EPOCH=$(bjson "$BATCH_JSON" "d['epoch']")
ROOT=$(bjson "$BATCH_JSON" "d['root']")
TOTAL_WH=$(bjson "$BATCH_JSON" "d['totalKwh']")
echo "[03] epoch=$EPOCH root=$ROOT totalKwh=$TOTAL_WH"

# ─── 04 propose (proposer's call is also their first vote; threshold=1) ───────
echo "[04] Proposing batch on-chain..."
PROPOSE_HASH=$(cast send "$ATTESTER" "proposeBatch(uint64,bytes32,uint128)" \
  "$EPOCH" "$ROOT" "$TOTAL_WH" \
  --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL" --json | python3 -c \
  "import json,sys;print(json.load(sys.stdin)['transactionHash'])")
echo "[04] proposeBatch tx: $PROPOSE_HASH"

# ─── 05 wait the REAL challenge window, then finalize ─────────────────────────
echo "[05] Waiting the real challenge window (${CHALLENGE_WINDOW}s + 10s buffer)..."
# The public `batches` getter returns the full AttestationBatch struct in
# declaration order: merkleRoot(bytes32), epoch(uint64), totalKwh(uint128),
# timestamp(uint64), proposer(address), finalized(bool),
# thresholdAtPropose(uint64), challengeWindowAtPropose(uint64). cast prints one
# field per line, so timestamp is line 4.
BATCH_TS=$(cast call "$ATTESTER" \
  "batches(uint64)(bytes32,uint64,uint128,uint64,address,bool,uint64,uint64)" \
  "$EPOCH" --rpc-url "$RPC_URL" | sed -n '4p' | awk '{print $1}')
sleep $((CHALLENGE_WINDOW + 10))
# Confirm the chain clock has actually passed batch.timestamp + window.
NOW_TS=$(cast block latest --rpc-url "$RPC_URL" --field timestamp)
echo "[05] chain time=$NOW_TS  batch time=$BATCH_TS  window=$CHALLENGE_WINDOW"
if [[ -n "$BATCH_TS" && "$NOW_TS" -lt $((BATCH_TS + CHALLENGE_WINDOW)) ]]; then
  echo "[05] chain clock not yet past window; waiting for next block..."
  sleep 15
fi
echo "[05] Finalizing batch..."
FINALIZE_HASH=$(cast send "$ATTESTER" "finalizeBatch(uint64)" "$EPOCH" \
  --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL" --json | python3 -c \
  "import json,sys;print(json.load(sys.stdin)['transactionHash'])")
echo "[05] finalizeBatch tx: $FINALIZE_HASH"

# ─── 06 claim leaf 0 (first beneficiary) ──────────────────────────────────────
BENEFICIARY=$(bjson "$BATCH_JSON" "d['leaves'][0]['beneficiary']")
AMOUNT=$(bjson "$BATCH_JSON" "d['leaves'][0]['amount_wei']")
PROOF_BRACKETED=$(bjson "$BATCH_JSON" "'[' + ','.join(d['leaves'][0]['proof']) + ']'")

echo "[06] Claiming leaf 0 -> $BENEFICIARY ($AMOUNT wei)..."
CLAIM_HASH=$(cast send "$ATTESTER" "claim(uint64,bytes32[],address,uint128)" \
  "$EPOCH" "$PROOF_BRACKETED" "$BENEFICIARY" "$AMOUNT" \
  --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL" --json | python3 -c \
  "import json,sys;print(json.load(sys.stdin)['transactionHash'])")
echo "[06] claim tx: $CLAIM_HASH"

BAL_RAW=$(cast call "$TOKEN" "balanceOf(address)(uint256)" "$BENEFICIARY" \
  --rpc-url "$RPC_URL")
BAL=$(echo "$BAL_RAW" | awk '{print $1}')
if [[ "$BAL" != "$AMOUNT" ]]; then
  echo "[!] balance mismatch: got '$BAL', expected '$AMOUNT'" >&2
  exit 1
fi
echo "[06] on-chain NOET balance = $BAL wei (matches expected)"

# ─── 07 off-chain verify ──────────────────────────────────────────────────────
echo "[07] Off-chain verifying the attestation signature..."
bash examples/lifecycle/07_verify_offchain.sh >/dev/null

# ─── Summary + explorer links for the launch post ────────────────────────────
echo ""
echo "==== GENESIS ATTESTATION COMPLETE ===="
echo "  chainId  : $CHAIN_ID"
echo "  ATTESTER : $ATTESTER"
echo "  TOKEN    : $TOKEN"
echo "  Epoch    : $EPOCH"
echo "  Claimed  : $AMOUNT wei NOET -> $BENEFICIARY"
if [[ -n "$EXPLORER" ]]; then
  echo ""
  echo "  Explorer links (for the launch announcement):"
  echo "    Attester  : $EXPLORER/address/$ATTESTER"
  echo "    Token     : $EXPLORER/address/$TOKEN"
  echo "    proposeBatch tx : $EXPLORER/tx/$PROPOSE_HASH"
  echo "    finalizeBatch tx: $EXPLORER/tx/$FINALIZE_HASH"
  echo "    claim tx        : $EXPLORER/tx/$CLAIM_HASH"
fi
echo ""
echo "  NOTE for the announcement copy: this is the protocol's first on-chain"
echo "  attestation CYCLE on a public network. The kWh figure is reference data"
echo "  (the hardware meter integration is still a stub), so describe it as"
echo "  'first on-chain attestation', NOT 'first verified real green kWh'."
