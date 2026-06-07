#!/usr/bin/env bash
#
# Parity gate test — proves the Go and Python verifier nodes return IDENTICAL
# verdicts on the same published batch data. Hermetic: spins up its own Anvil,
# deploys, runs the full lifecycle to finalize a batch, publishes batch.json,
# then runs BOTH nodes against the same data:
#
#   honest batch   -> both must exit 0 (OK)   and agree
#   tampered batch -> both must exit 1 (ALARM) and agree
#
# If the two implementations ever diverge on either case, this fails. This is
# the last open item for the verifier-node track (E) of the launch plan.
#
# Usage:  node/_parity_test.sh        (run from repo root; uses the node venv if present)
# Deps:   foundry (anvil, cast, forge); go; python3 with cryptography + pycryptodome;
#         the node venv (web3 + eth-abi) at /tmp/noethrion_node_venv or web3 on PATH.

set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
cd "$REPO"

# Python that can import web3 (for the Python node). Falls back to system python3.
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

# Build the Go node up front (fail fast if the binary won't compile).
echo "[*] Build Go node"
( cd node/go && go build -o noethrion-verify . )
GO_BIN="$REPO/node/go/noethrion-verify"
[ -x "$GO_BIN" ] || { echo "[FAIL] go build did not produce $GO_BIN"; exit 1; }

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

# --- helpers -------------------------------------------------------------
# Extract the per-epoch verdict from a node's stdout: the last OK/ALARM line.
# Both nodes log "[OK] epoch N fully verified" on success and
# "[ALARM] *** VERIFICATION FAILED ..." on failure — same shape, so we can
# normalize to a single token (OK / ALARM / NONE) and compare across impls.
verdict() {  # $1 = captured stdout
  if echo "$1" | grep -q "^\[ALARM\]"; then echo "ALARM";
  elif echo "$1" | grep -q "^\[OK\]"; then echo "OK";
  else echo "NONE"; fi
}

run_py() {   # $1 = data dir ; prints stdout, sets global PY_EXIT
  set +e
  PY_OUT=$($NODE_PY node/verifier_node.py --rpc "$RPC" --attester "$ATTESTER" --chain-id 31337 --data-dir "$1" --once 2>&1)
  PY_EXIT=$?
  set -e
}
run_go() {   # $1 = data dir ; prints stdout, sets global GO_EXIT
  set +e
  GO_OUT=$("$GO_BIN" --rpc "$RPC" --attester "$ATTESTER" --chain-id 31337 --data-dir "$1" --once 2>&1)
  GO_EXIT=$?
  set -e
}

FAILED=0
check_parity() {  # $1 = label, $2 = expected exit, $3 = expected verdict
  local label="$1" want_exit="$2" want_verdict="$3"
  local pv gv
  pv=$(verdict "$PY_OUT"); gv=$(verdict "$GO_OUT")
  echo "    python: exit=$PY_EXIT verdict=$pv"
  echo "    go:     exit=$GO_EXIT verdict=$gv"
  if [ "$PY_EXIT" -ne "$GO_EXIT" ]; then
    echo "    [FAIL] $label: exit codes differ (py=$PY_EXIT go=$GO_EXIT)"; FAILED=1; return
  fi
  if [ "$pv" != "$gv" ]; then
    echo "    [FAIL] $label: verdicts differ (py=$pv go=$gv)"; FAILED=1; return
  fi
  if [ "$PY_EXIT" -ne "$want_exit" ] || [ "$pv" != "$want_verdict" ]; then
    echo "    [FAIL] $label: agreed but on wrong answer (got exit=$PY_EXIT verdict=$pv, want exit=$want_exit verdict=$want_verdict)"; FAILED=1; return
  fi
  echo "    [PASS] $label: both -> exit=$PY_EXIT verdict=$pv (agree, correct)"
}

# --- CASE 1: honest batch — both must say OK / exit 0 ---------------------
echo ""
echo "[*] CASE 1 (honest): both nodes must agree on OK / exit 0"
run_py "$DATA"; run_go "$DATA"
check_parity "honest" 0 "OK"

# --- CASE 2: tampered batch — both must say ALARM / exit 1 ----------------
echo ""
echo "[*] CASE 2 (tampered leaf amount): both nodes must agree on ALARM / exit 1"
cp "$DATA"/* "$TAMPER/"
$LC_PY -c "import json;p='$TAMPER/batch.json';d=json.load(open(p));d['leaves'][0]['amount_wei']=str(int(d['leaves'][0]['amount_wei'])+1);json.dump(d,open(p,'w'))"
run_py "$TAMPER"; run_go "$TAMPER"
check_parity "tampered" 1 "ALARM"

# --- summary -------------------------------------------------------------
echo ""
if [ "$FAILED" -eq 0 ]; then
  echo "==== PARITY PASS: Go and Python nodes return identical verdicts on honest + tampered data ===="
  exit 0
else
  echo "==== PARITY FAIL: the two implementations diverged (see [FAIL] above) ===="
  exit 1
fi
