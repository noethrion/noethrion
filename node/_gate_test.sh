#!/usr/bin/env bash
#
# Launch-gate test for the verifier node.
#
# Proves the node does its one job: it says OK when the published batch data
# reconciles with the on-chain Merkle root, and it ALARMS when the data is
# tampered. Hermetic — spins up its own Anvil, deploys, runs the full lifecycle
# to finalize a batch, then:
#   1. runs the node against the deployment   -> expects exit 0 (OK)
#   2. tampers a leaf amount and re-runs       -> expects exit 1 (ALARM)
#
# This is the gate the node must pass to be launch-includable.
#
# Usage:  node/_gate_test.sh        (run from repo root; uses the node venv if present)
# Deps:   foundry (anvil, cast, forge); python3 with cryptography + pycryptodome;
#         the node venv (web3 + eth-abi) at /tmp/noethrion_node_venv or web3 on PATH.

set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
cd "$REPO"

# Python that can import web3 (for the node). Falls back to system python3.
NODE_PY="/tmp/noethrion_node_venv/bin/python"
[ -x "$NODE_PY" ] || NODE_PY="python3"
# Python for the crypto lifecycle steps (needs cryptography + pycryptodome).
LC_PY="python3"

ANVIL_MNEMONIC="test test test test test test test test test test test junk"
DEPLOYER_PK="$(cast wallet private-key --mnemonic "$ANVIL_MNEMONIC" --mnemonic-index 0)"

pick_port() { for _ in {1..10}; do local p=$((34000 + RANDOM % 4000)); lsof -nP -iTCP:"$p" -sTCP:LISTEN 2>/dev/null | grep -q LISTEN || { echo "$p"; return; }; done; echo 34999; }
PORT="$(pick_port)"; RPC="http://localhost:$PORT"
DATA="$(mktemp -d)"; TAMPER="$(mktemp -d)"
ANVIL_PID=""
cleanup() {
  [ -n "$ANVIL_PID" ] && kill "$ANVIL_PID" 2>/dev/null || true
  rm -rf "$DATA" "$TAMPER" examples/lifecycle/attester.key examples/lifecycle/attester.key.pub \
         examples/lifecycle/attestation.json examples/lifecycle/batch.json \
         contracts/broadcast/Deploy.s.sol/31337 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "[*] Anvil on $PORT"
anvil --silent --port "$PORT" & ANVIL_PID=$!
for _ in {1..30}; do cast block latest --rpc-url "$RPC" >/dev/null 2>&1 && break; sleep 0.2; done

echo "[*] Deploy"
OUT=$(PRIVATE_KEY="$DEPLOYER_PK" THRESHOLD=1 forge script contracts/script/Deploy.s.sol --root contracts --rpc-url "$RPC" --broadcast 2>&1)
ATTESTER=$(echo "$OUT" | grep -E "^\s*ATTESTER:" | tail -1 | awk '{print $NF}')
echo "[*] ATTESTER=$ATTESTER"

# lifecycle: key -> sign -> merkle -> propose -> warp -> finalize (batch.json kept)
$LC_PY tools/provision_atecc.py generate-key --out examples/lifecycle/attester.key >/dev/null
bash examples/lifecycle/02_sign_attestation.sh >/dev/null
ATTESTER="$ATTESTER" CHAIN_ID=31337 $LC_PY examples/lifecycle/03_build_merkle_tree.py >/dev/null
EPOCH=$($LC_PY -c "import json;print(json.load(open('examples/lifecycle/batch.json'))['epoch'])")
ROOT=$($LC_PY -c "import json;print(json.load(open('examples/lifecycle/batch.json'))['root'])")
TOTAL=$($LC_PY -c "import json;print(json.load(open('examples/lifecycle/batch.json'))['totalKwh'])")
cast send "$ATTESTER" "proposeBatch(uint64,bytes32,uint128)" "$EPOCH" "$ROOT" "$TOTAL" --private-key "$DEPLOYER_PK" --rpc-url "$RPC" >/dev/null
cast rpc evm_increaseTime 3700 --rpc-url "$RPC" >/dev/null; cast rpc evm_mine --rpc-url "$RPC" >/dev/null
cast send "$ATTESTER" "finalizeBatch(uint64)" "$EPOCH" --private-key "$DEPLOYER_PK" --rpc-url "$RPC" >/dev/null
echo "[*] batch $EPOCH finalized"

cp examples/lifecycle/batch.json examples/lifecycle/attestation.json examples/lifecycle/attester.key.pub "$DATA/"

echo ""
echo "[*] TEST 1 (positive): node must print OK and exit 0"
set +e
$NODE_PY node/verifier_node.py --rpc "$RPC" --attester "$ATTESTER" --chain-id 31337 --data-dir "$DATA" --once
POS=$?
set -e
[ "$POS" -eq 0 ] || { echo "[FAIL] node did not return OK on valid data (exit $POS)"; exit 1; }
echo "[PASS] valid batch -> OK"

echo ""
echo "[*] TEST 2 (negative): tamper a leaf amount, node must ALARM and exit 1"
cp "$DATA"/* "$TAMPER/"
$LC_PY -c "import json;p='$TAMPER/batch.json';d=json.load(open(p));d['leaves'][0]['amount_wei']=str(int(d['leaves'][0]['amount_wei'])+1);json.dump(d,open(p,'w'))"
set +e
$NODE_PY node/verifier_node.py --rpc "$RPC" --attester "$ATTESTER" --chain-id 31337 --data-dir "$TAMPER" --once
NEG=$?
set -e
[ "$NEG" -eq 1 ] || { echo "[FAIL] node did NOT alarm on tampered data (exit $NEG)"; exit 1; }
echo "[PASS] tampered batch -> ALARM"

echo ""
echo "==== GATE TEST PASSED: node verifies honest data and catches tampering ===="
