# Noethrion in-browser verifier — WASM (v0.1)

The "don't trust us, verify it yourself" tool, with **zero install**. This is the
same verification logic as the command-line [`../`](../) Go node, compiled to
WebAssembly and driven from a one-file static page. Open the page, paste the
operator's published batch JSON, hit **Verify** — your browser re-derives every
leaf, replays the sorted-pair keccak256 Merkle proof, and checks it against the
on-chain `batches(uint64)` root via your chosen RPC endpoint. Green = OK,
red = ALARM.

## Why a separate, slim build

go-ethereum's `ethclient` / `accounts/abi` drag in packages that bloat or fail
under `GOOS=js GOARCH=wasm`. So this module re-implements, by hand, the only two
primitives the native node borrowed from go-ethereum:

- **keccak256** via `golang.org/x/crypto/sha3` (`NewLegacyKeccak256` — Ethereum's
  legacy Keccak, *not* NIST SHA3-256).
- the trivial **fixed-width ABI** for `batches(uint64)` — selector =
  `0x8232e389` (first 4 bytes of `keccak256("batches(uint64)")`), arguments and
  return values are all fixed 32-byte words, decoded by offset.

Everything else (`math/big`, `encoding/json`, `syscall/js`, `crypto/*`) is the
standard library, all of which compiles cleanly to wasm. Result: a ~3.3 MB
`verifier.wasm`, not the tens-of-MB a go-ethereum wasm build would produce.

The leaf hash this produces is byte-identical to both `../main.go` (go-ethereum
path) and `../../../tools/verify_attestation.py compute-leaf` — verified.

This directory is its **own Go module** (`go.mod`), deliberately decoupled from
the parent `verifier-node-go` module so the wasm build never has to resolve
go-ethereum.

## Build

From this directory (`node/go/wasm`):

```bash
GOOS=js GOARCH=wasm go build -o verifier.wasm .
```

Then copy the matching JS support shim that ships with your Go toolchain. The
path moved in recent Go releases:

```bash
# Go 1.24+ (incl. 1.26, used here):
cp "$(go env GOROOT)/lib/wasm/wasm_exec.js" .

# Go 1.23 and earlier:
# cp "$(go env GOROOT)/misc/wasm/wasm_exec.js" .
```

Both `verifier.wasm` and the copied `wasm_exec.js` are build artifacts and are
gitignored — only the source (`main_wasm.go`, `index.html`, `go.mod`, `go.sum`,
this README) is committed. Rebuild both before serving.

## Serve

WASM must be served over HTTP (not `file://`). Any static server works:

```bash
python3 -m http.server 8080
# then open http://localhost:8080/node/go/wasm/  (or cd here first and use /)
```

## Use

1. **RPC URL** — prefilled with `https://ethereum-sepolia-rpc.publicnode.com`.
2. **Attester contract address** — the deployed `NoethrionAttester`.
3. **Chain ID** — `11155111` for Sepolia.
4. **Epoch** — the batch epoch to check.
5. **Published batch JSON** — paste the operator's `batch-<epoch>.json`
   (`{epoch, root, leaves:[{beneficiary, amount_wei, leaf, proof[]}]}`), the same
   shape the lifecycle tooling emits and the native node reads from `--data-dir`.

Verdicts:

- **OK** (green) — finalized on-chain, published root matches, every leaf
  re-derived and Merkle-verified against the on-chain root.
- **ALARM** (red) — a mismatch: published root ≠ on-chain root, a leaf doesn't
  re-derive, or a Merkle proof fails.
- **SKIP** — epoch not proposed / not finalized yet, RPC error, or malformed
  input. Nothing to verify.

## JS API (exported by the wasm to `globalThis`)

```js
// Returns a Promise<{ status: "OK"|"ALARM"|"SKIP", details: string[] }>.
await noethrionVerify(rpcUrl, attester, chainId, epoch, batchJSON);

// Helper: returns the eth_call data ("0x8232e389" + uint256(epoch)) if you want
// to make the batches(uint64) call yourself.
noethrionBatchesCall(epoch);
```

## Scope / caveats

- **v0.1 covers chain + Merkle.** The optional ECDSA P-256 attestation signature
  check from the native node is **not yet wired** in-browser (stdlib
  `crypto/ecdsa` compiles to wasm fine — it's a nice-to-have follow-up). The
  load-bearing leaf + Merkle + on-chain-root check is fully present.
- **CORS:** the in-browser `eth_call` is a cross-origin `fetch` to the RPC
  endpoint. The prefilled `https://ethereum-sepolia-rpc.publicnode.com` returns
  permissive CORS headers and works from a browser today — but public RPC CORS
  policies can change without notice. If a future endpoint blocks browser
  `fetch`, the verdict comes back **SKIP** ("rpc error"); point the URL at a
  CORS-enabled RPC (publicnode, most paid providers, or your own node) and retry.

## Roadmap

- [ ] Wire the P-256 signature check (stdlib `crypto/ecdsa` + `crypto/x509`).
- [ ] Prefill a known-good Sepolia genesis batch as a one-click demo.
- [ ] Host at `verify.noethrion.com` (static, CDN-served).
