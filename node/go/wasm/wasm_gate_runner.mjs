// wasm_gate_runner.mjs — headless Node.js driver for the in-browser WASM verifier.
//
// Loads wasm_exec.js + verifier.wasm exactly as a browser would, installs the
// globals the WASM expects (globalThis.fetch, Promise), invokes the exported
// noethrionVerify(...) with the published batch JSON, and exits by verdict:
//
//   verdict OK    -> exit 0
//   verdict ALARM -> exit 1
//   verdict SKIP  -> exit 3   (distinct, so the gate can tell "skipped" from "ok")
//   crash/usage   -> exit 2
//
// This is the THIRD leg of the 3-way parity gate: it runs the SAME .wasm the
// browser ships against the SAME on-chain root + published batch the Go and
// Python nodes verify, and must reach the SAME verdict. The WASM does its
// eth_call via globalThis.fetch, so we either proxy that fetch to a live RPC
// (the hermetic Anvil from _parity_test.sh) or answer it from a fixed result
// blob — both modes are supported below.
//
// Usage:
//   node wasm_gate_runner.mjs \
//     --rpc        http://localhost:PORT      (or --root 0x<64hex> to stub the call) \
//     --attester   0x...                      \
//     --chain-id   31337                      \
//     --epoch      N                          \
//     --batch      /path/to/batch.json        (use "-" or omit to send empty string) \
//     [--attestation /path/to/attestation.json] \
//     [--pubkey      /path/to/attester.key.pub] \
//     [--raw-result  0x<hex>]   force the eth_call to return this exact blob \
//     [--rpc-error]             force the eth_call to return a JSON-RPC error
//
// Notes on fail-closed testing: --batch may point at deliberately garbage /
// truncated / wrong-epoch JSON; the WASM must ALARM (exit 1), never crash.

import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { webcrypto } from "node:crypto";

const HERE = dirname(fileURLToPath(import.meta.url));

// ---- arg parsing -----------------------------------------------------------
function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith("--")) continue;
    const key = a.slice(2);
    // boolean flags
    if (key === "rpc-error") {
      out[key] = true;
      continue;
    }
    out[key] = argv[++i];
  }
  return out;
}
const args = parseArgs(process.argv.slice(2));

function need(name) {
  const v = args[name];
  if (v === undefined) {
    console.error(`[wasm-runner] missing required --${name}`);
    process.exit(2);
  }
  return v;
}

const attester = need("attester");
const chainId = need("chain-id");
const epoch = parseInt(need("epoch"), 10);
const rpcUrl = args["rpc"] || "http://stub.local"; // unused when --raw-result/--root given

// Read a file arg; "-" or missing -> empty string (lets us test the
// "finalized but no published JSON" fail-closed path).
async function readArgFile(name) {
  const p = args[name];
  if (p === undefined || p === "-") return "";
  return await readFile(p, "utf8");
}
const batchJSON = await readArgFile("batch");
const attestationJSON = await readArgFile("attestation");
const pubKeyPEM = await readArgFile("pubkey");

// ---- fetch shim ------------------------------------------------------------
// The WASM POSTs a JSON-RPC eth_call. We answer it. Two stub modes plus a live
// proxy mode:
//   --raw-result 0x..  -> return that blob as the eth_call result
//   --root 0x<64hex>   -> synthesize an 8-word batches() return committing that
//                         root, timestamp=1, finalized=true (enough for verify)
//   --rpc-error        -> return a JSON-RPC error object
//   otherwise          -> proxy to the real --rpc (live Anvil) via Node fetch
function synthBatchesReturn(rootHex) {
  const root = rootHex.replace(/^0x/, "").padStart(64, "0");
  const word = (hex) => hex.padStart(64, "0");
  const w0 = root; // merkleRoot
  const w1 = word((epoch >>> 0).toString(16)); // epoch
  const w2 = word("0"); // totalKwh
  const w3 = word("1"); // timestamp (nonzero => proposed)
  const w4 = word("0"); // proposer
  const w5 = word("1"); // finalized = true
  const w6 = word("0"); // thresholdAtPropose
  const w7 = word("0"); // challengeWindowAtPropose
  return "0x" + w0 + w1 + w2 + w3 + w4 + w5 + w6 + w7;
}

const nodeFetch = globalThis.fetch; // Node 18+ has a global fetch we proxy through

globalThis.fetch = async (url, opts) => {
  let id = 1;
  try {
    id = JSON.parse(opts?.body || "{}").id ?? 1;
  } catch {
    /* ignore */
  }
  const reply = (obj) => ({
    ok: true,
    status: 200,
    async text() {
      return JSON.stringify({ jsonrpc: "2.0", id, ...obj });
    },
    async json() {
      return { jsonrpc: "2.0", id, ...obj };
    },
  });

  if (args["rpc-error"]) {
    return reply({ error: { code: -32000, message: "forced rpc error" } });
  }
  if (args["raw-result"] !== undefined) {
    return reply({ result: args["raw-result"] });
  }
  if (args["root"] !== undefined) {
    return reply({ result: synthBatchesReturn(args["root"]) });
  }
  // Live proxy: forward to the real RPC (hermetic Anvil).
  if (!nodeFetch) {
    return reply({ error: { code: -32601, message: "no proxy fetch available" } });
  }
  const real = await nodeFetch(url, opts);
  const txt = await real.text();
  return {
    ok: real.ok,
    status: real.status,
    async text() {
      return txt;
    },
    async json() {
      return JSON.parse(txt);
    },
  };
};

// crypto/sha256 + ecdsa under js/wasm uses globalThis.crypto.getRandomValues.
if (!globalThis.crypto) globalThis.crypto = webcrypto;

// ---- load + run the WASM ---------------------------------------------------
// wasm_exec.js is a classic (non-module) script that defines global Go. We load
// it by evaluating its source with the Node global object as `this`.
const wasmExecSrc = await readFile(join(HERE, "wasm_exec.js"), "utf8");
// eslint-disable-next-line no-new-func
new Function(wasmExecSrc).call(globalThis);

const go = new globalThis.Go();
const wasmBytes = await readFile(join(HERE, "verifier.wasm"));
const { instance } = await WebAssembly.instantiate(wasmBytes, go.importObject);

// go.run() never resolves (the Go main parks on select{}), so we kick it off
// and then poll for the exported function to appear.
go.run(instance); // fire-and-forget

async function waitForExport(name, timeoutMs = 5000) {
  const start = Date.now();
  while (typeof globalThis[name] !== "function") {
    if (Date.now() - start > timeoutMs) {
      throw new Error(`export ${name} never appeared`);
    }
    await new Promise((r) => setTimeout(r, 10));
  }
  return globalThis[name];
}

try {
  const verify = await waitForExport("noethrionVerify");
  const result = await verify(
    rpcUrl,
    attester,
    String(chainId),
    epoch,
    batchJSON,
    attestationJSON,
    pubKeyPEM,
  );
  const status = result?.status ?? "NONE";
  const details = Array.isArray(result?.details) ? result.details : [];
  // Mirror the native nodes' log shape so the parity gate can grep [OK]/[ALARM].
  for (const d of details) console.log(`[INFO] ${d}`);
  if (status === "OK") {
    console.log(`[OK] epoch ${epoch} fully verified (wasm)`);
    process.exit(0);
  } else if (status === "ALARM") {
    console.log(`[ALARM] *** VERIFICATION FAILED at epoch ${epoch} (wasm) ***`);
    process.exit(1);
  } else {
    // SKIP or unknown.
    console.log(`[SKIP] epoch ${epoch}: ${status} (wasm)`);
    process.exit(3);
  }
} catch (e) {
  // The WASM must never crash the gate: a thrown/rejected promise is itself a
  // failure, but we report it as a runner error (exit 2) so the gate can
  // distinguish "verifier said ALARM" from "harness blew up".
  console.error(`[wasm-runner] error: ${e?.stack || e}`);
  process.exit(2);
}
