# Noethrion verifier node — Go (v0.1)

A single-binary, zero-dependency-at-runtime version of the independent verifier
([`../verifier_node.py`](../verifier_node.py) is the reference). Anyone, anywhere,
downloads one file and runs it — the gravitational "don't trust us, verify it
yourself" tool. The same source is intended to also compile to **WASM** for an
in-browser verifier (next step).

Does the same checks as the Python reference: for every finalized batch it
re-derives each leaf as `keccak256(abi.encode(chainId, attester, beneficiary,
amount, epoch))`, replays the sorted-pair keccak256 Merkle proof against the
on-chain root, re-checks the ECDSA P-256 attestation signature (when published),
and ALARMs on any mismatch.

## Build & run

```bash
cd node/go
go build -o noethrion-verify .

./noethrion-verify \
  --rpc       https://sepolia.infura.io/v3/<key> \
  --attester  0x... \
  --chain-id  11155111 \
  --data-dir  ./published \
  --once          # single pass; omit for a continuous daemon
```

`--data-dir` holds the operator-published `batch.json` (+ optional
`attestation.json` and `attester.key.pub` for the signature check) — the same
shape the lifecycle tooling emits.

Exit codes (`--once`): `0` all verified · `1` ALARM (mismatch) · `2` usage error.

## Cross-compile (any OS, one command each)

```bash
GOOS=linux   GOARCH=amd64 go build -o noethrion-verify-linux   .
GOOS=darwin  GOARCH=arm64 go build -o noethrion-verify-macos   .
GOOS=windows GOARCH=amd64 go build -o noethrion-verify.exe     .
```

## Roadmap
- [ ] WASM build + a tiny static page so anyone verifies in the browser, zero install.
- [ ] Parity gate test against the Python reference on the same batch.
