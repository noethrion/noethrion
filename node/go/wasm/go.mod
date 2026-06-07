// Separate, hermetic module for the in-browser (js/wasm) verifier.
//
// Deliberately NOT part of the parent verifier-node-go module: the parent pulls
// in go-ethereum, which bloats / fails under GOOS=js GOARCH=wasm. This module's
// only non-stdlib dependency is x/crypto/sha3 (keccak256). Everything else —
// big.Int, encoding/json, syscall/js, crypto/* — is the standard library, all
// of which compiles cleanly to wasm.
module github.com/noethrion/verifier-node-go/wasm

go 1.22

require golang.org/x/crypto v0.22.0
