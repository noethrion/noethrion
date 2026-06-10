#!/usr/bin/env bash
#
# Parity gate test — proves the Go, Python, AND in-browser WASM verifiers return
# IDENTICAL verdicts on the same published batch data. Hermetic: spins up its own
# Anvil, deploys, runs the full lifecycle to finalize a batch, publishes
# batch.json (+ attestation.json + attester.key.pub for the signature check),
# then runs ALL THREE implementations against the same on-chain root:
#
#   honest batch          -> all three must exit 0 (OK)    and agree
#   tampered batch        -> all three must exit 1 (ALARM) and agree
#   malformed batch       -> all three must ALARM (exit 1), never crash, never OK
#   missing batch (FINAL) -> all three must ALARM (finalized + absent data)
#   negative amount / missing leaf field / string epoch / empty leaves
#                         -> all three must ALARM (fail-closed field validation)
#
# The WASM leg loads verifier.wasm in headless Node (wasm_gate_runner.mjs),
# proxies its eth_call fetch to the same live Anvil RPC, and reaches its verdict
# from the SAME on-chain commitment — true 3-way parity, not a re-run of Go.
#
# If the implementations ever diverge on any case, this fails. This is the last
# open item for the verifier-node track (E) of the launch plan.
#
# Usage:  node/_parity_test.sh        (run from repo root; uses the node venv if present)
# Deps:   foundry (anvil, cast, forge); go (for the Go node + the WASM build);
#         node (>=18, for the WASM runner); python3 with cryptography + pycryptodome;
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

WASM_DIR="$REPO/node/go/wasm"
WASM_RUNNER="$WASM_DIR/wasm_gate_runner.mjs"

pick_port() { for _ in {1..10}; do local p=$((34000 + RANDOM % 4000)); lsof -nP -iTCP:"$p" -sTCP:LISTEN 2>/dev/null | grep -q LISTEN || { echo "$p"; return; }; done; echo 34999; }
PORT="$(pick_port)"; RPC="http://localhost:$PORT"
DATA="$(mktemp -d)"; TAMPER="$(mktemp -d)"; GARBAGE="$(mktemp -d)"
ANVIL_PID=""
cleanup() {
  [ -n "$ANVIL_PID" ] && kill "$ANVIL_PID" 2>/dev/null || true
  rm -rf "$DATA" "$TAMPER" "$GARBAGE" examples/lifecycle/attester.key examples/lifecycle/attester.key.pub \
         examples/lifecycle/attestation.json examples/lifecycle/batch.json \
         contracts/broadcast/Deploy.s.sol/31337 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Build the Go node up front (fail fast if the binary won't compile).
echo "[*] Build Go node"
( cd node/go && go build -o noethrion-verify . )
GO_BIN="$REPO/node/go/noethrion-verify"
[ -x "$GO_BIN" ] || { echo "[FAIL] go build did not produce $GO_BIN"; exit 1; }

# Build the WASM verifier up front too (the third parity leg).
echo "[*] Build WASM verifier (GOOS=js GOARCH=wasm)"
( cd "$WASM_DIR" && GOOS=js GOARCH=wasm go build -trimpath -o verifier.wasm . )
[ -f "$WASM_DIR/verifier.wasm" ] || { echo "[FAIL] wasm build did not produce verifier.wasm"; exit 1; }
# wasm_exec.js ships with the Go toolchain (lib/wasm since Go 1.24, misc/wasm before).
if [ ! -f "$WASM_DIR/wasm_exec.js" ]; then
  GOROOT_DIR="$(go env GOROOT)"
  for CAND in "$GOROOT_DIR/lib/wasm/wasm_exec.js" "$GOROOT_DIR/misc/wasm/wasm_exec.js"; do
    [ -f "$CAND" ] && cp "$CAND" "$WASM_DIR/wasm_exec.js" && break
  done
fi
[ -f "$WASM_DIR/wasm_exec.js" ] || { echo "[FAIL] missing $WASM_DIR/wasm_exec.js (not found in Go toolchain either)"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "[FAIL] node not on PATH (needed for WASM leg)"; exit 1; }
echo "    node $(node --version) · verifier.wasm $(du -h "$WASM_DIR/verifier.wasm" | cut -f1)"

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
# All three impls log "[OK] epoch N ..." on success and "[ALARM] ..." on failure
# (the WASM runner is shaped to match), so we normalize to a single token
# (OK / ALARM / NONE) and compare across implementations.
verdict() {  # $1 = captured stdout
  if echo "$1" | grep -q "^\[ALARM\]"; then echo "ALARM";
  elif echo "$1" | grep -q "^\[OK\]"; then echo "OK";
  else echo "NONE"; fi
}

run_py() {   # $1 = data dir ; sets PY_OUT, PY_EXIT
  set +e
  PY_OUT=$($NODE_PY node/verifier_node.py --rpc "$RPC" --attester "$ATTESTER" --chain-id 31337 --data-dir "$1" --once 2>&1)
  PY_EXIT=$?
  set -e
}
run_go() {   # $1 = data dir ; sets GO_OUT, GO_EXIT
  set +e
  GO_OUT=$("$GO_BIN" --rpc "$RPC" --attester "$ATTESTER" --chain-id 31337 --data-dir "$1" --once 2>&1)
  GO_EXIT=$?
  set -e
}
run_wasm() { # $1 = data dir ; sets WASM_OUT, WASM_EXIT
  # The WASM verifier takes the published artifacts as explicit args and does its
  # own eth_call against the live Anvil (proxied through the runner's fetch shim).
  # A missing batch file -> pass "-" so the WASM hits its "no published JSON"
  # fail-closed path, exactly as the file-based nodes hit "no batch data".
  local dir="$1" batch_arg
  if [ -f "$dir/batch.json" ]; then batch_arg="$dir/batch.json"; else batch_arg="-"; fi
  set +e
  WASM_OUT=$(node "$WASM_RUNNER" \
    --rpc "$RPC" --attester "$ATTESTER" --chain-id 31337 --epoch "$EPOCH" \
    --batch "$batch_arg" \
    --attestation "$dir/attestation.json" \
    --pubkey "$dir/attester.key.pub" 2>&1)
  WASM_EXIT=$?
  set -e
  # The runner uses exit 3 for SKIP; the file nodes use exit 0 with no [OK] for
  # SKIP. For parity comparison we only care OK(0) vs ALARM(1); a crash is exit 2.
  if [ "$WASM_EXIT" -eq 3 ]; then WASM_EXIT=0; fi   # normalize SKIP -> 0 like the others
}

FAILED=0
# 3-way parity check: all three impls must agree with each other AND be correct.
check_parity3() {  # $1 = label, $2 = expected exit, $3 = expected verdict
  local label="$1" want_exit="$2" want_verdict="$3"
  local pv gv wv
  pv=$(verdict "$PY_OUT"); gv=$(verdict "$GO_OUT"); wv=$(verdict "$WASM_OUT")
  echo "    python: exit=$PY_EXIT   verdict=$pv"
  echo "    go:     exit=$GO_EXIT   verdict=$gv"
  echo "    wasm:   exit=$WASM_EXIT   verdict=$wv"
  if [ "$WASM_EXIT" -eq 2 ]; then
    echo "    [FAIL] $label: WASM verifier CRASHED (exit 2) — must never crash"; FAILED=1; return
  fi
  if [ "$PY_EXIT" -ne "$GO_EXIT" ] || [ "$PY_EXIT" -ne "$WASM_EXIT" ]; then
    echo "    [FAIL] $label: exit codes differ (py=$PY_EXIT go=$GO_EXIT wasm=$WASM_EXIT)"; FAILED=1; return
  fi
  if [ "$pv" != "$gv" ] || [ "$pv" != "$wv" ]; then
    echo "    [FAIL] $label: verdicts differ (py=$pv go=$gv wasm=$wv)"; FAILED=1; return
  fi
  if [ "$PY_EXIT" -ne "$want_exit" ] || [ "$pv" != "$want_verdict" ]; then
    echo "    [FAIL] $label: agreed but on wrong answer (got exit=$PY_EXIT verdict=$pv, want exit=$want_exit verdict=$want_verdict)"; FAILED=1; return
  fi
  echo "    [PASS] $label: all three -> exit=$PY_EXIT verdict=$pv (agree, correct)"
}

# --- CASE 1: honest batch — all three must say OK / exit 0 ----------------
echo ""
echo "[*] CASE 1 (honest): Python + Go + WASM must agree on OK / exit 0"
run_py "$DATA"; run_go "$DATA"; run_wasm "$DATA"
check_parity3 "honest" 0 "OK"

# --- CASE 2: tampered batch — all three must say ALARM / exit 1 -----------
echo ""
echo "[*] CASE 2 (tampered leaf amount): all three must agree on ALARM / exit 1"
cp "$DATA"/* "$TAMPER/"
$LC_PY -c "import json;p='$TAMPER/batch.json';d=json.load(open(p));d['leaves'][0]['amount_wei']=str(int(d['leaves'][0]['amount_wei'])+1);json.dump(d,open(p,'w'))"
run_py "$TAMPER"; run_go "$TAMPER"; run_wasm "$TAMPER"
check_parity3 "tampered" 1 "ALARM"

# --- CASE 3: malformed published batch.json — fail closed ----------------
# A FINALIZED epoch whose published batch.json is garbage / truncated / wrong
# is a transparency failure: every impl must ALARM (exit 1), never crash, never
# OK.
run_malformed_case() {  # $1 = label, $2 = how to corrupt batch.json (python snippet writing to $p)
  local label="$1" corrupt="$2"
  rm -rf "$GARBAGE"; mkdir -p "$GARBAGE"
  cp "$DATA"/* "$GARBAGE/"
  $LC_PY -c "p='$GARBAGE/batch.json'; $corrupt"
  echo ""
  echo "[*] CASE ($label) (corrupted published batch): all three must ALARM, never crash, never OK"
  run_py "$GARBAGE"; run_go "$GARBAGE"; run_wasm "$GARBAGE"
  check_parity3 "$label" 1 "ALARM"
}

# 3a — not valid JSON at all
run_malformed_case "malformed:raw-garbage" "open(p,'w').write('}{ not json at all {{{')"
# 3b — valid JSON but truncated structure (missing leaves / root)
run_malformed_case "malformed:missing-fields" "import json;json.dump({'epoch': $EPOCH}, open(p,'w'))"
# 3c — wrong-field types (leaves is a string, amount non-numeric)
run_malformed_case "malformed:wrong-types" "import json;json.dump({'epoch': $EPOCH, 'root': '0x00', 'leaves': 'not-a-list'}, open(p,'w'))"

# --- CASE 4: FINALIZED epoch with NO published batch file — fail closed ----
# Finalized + absent data = ALARM in all three implementations: an operator
# must not be able to dodge verification by simply not publishing.
echo ""
echo "[*] CASE 4 (missing-batch-finalized): all three must ALARM / exit 1"
rm -rf "$GARBAGE"; mkdir -p "$GARBAGE"
cp "$DATA/attestation.json" "$DATA/attester.key.pub" "$GARBAGE/"
run_py "$GARBAGE"; run_go "$GARBAGE"; run_wasm "$GARBAGE"
check_parity3 "missing-batch-finalized" 1 "ALARM"

# --- CASE 5: per-field fail-closed validation ------------------------------
# 5a — negative leaf amount (root untouched; the amount itself must trip it)
run_malformed_case "negative-amount" \
  "import json;d=json.load(open(p));d['leaves'][0]['amount_wei']=-abs(int(d['leaves'][0]['amount_wei']));json.dump(d,open(p,'w'))"
# 5b — missing required `leaf` field on a leaf record
run_malformed_case "missing-leaf-field" \
  "import json;d=json.load(open(p));d['leaves'][0].pop('leaf');json.dump(d,open(p,'w'))"
# 5c — string epoch (strict parsing: `epoch` must be a JSON integer everywhere)
run_malformed_case "string-epoch" \
  "import json;d=json.load(open(p));d['epoch']=str(d['epoch']);json.dump(d,open(p,'w'))"
# 5d — empty leaves array on a FINALIZED epoch (also breaks the totalKwh sum)
run_malformed_case "empty-leaves" \
  "import json;d=json.load(open(p));d['leaves']=[];json.dump(d,open(p,'w'))"

# --- summary -------------------------------------------------------------
echo ""
if [ "$FAILED" -eq 0 ]; then
  echo "==== PARITY PASS (3-way): Python + Go + WASM return identical, correct verdicts on honest, tampered, malformed, missing, and field-invalid data ===="
  exit 0
else
  echo "==== PARITY FAIL: the implementations diverged or one crashed (see [FAIL] above) ===="
  exit 1
fi
