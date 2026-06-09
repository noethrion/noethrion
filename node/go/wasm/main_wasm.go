//go:build js && wasm

// Noethrion in-browser verifier — slim WASM build.
//
// Same verdict logic as ../main.go, but self-contained: NO go-ethereum (it
// bloats / breaks under GOOS=js GOARCH=wasm). We hand-roll the two primitives
// the native node borrows from go-ethereum — keccak256 (via x/crypto/sha3's
// legacy variant) and the trivial fixed-width ABI encode/decode for batches() —
// so the whole thing compiles to a few-MB .wasm with stdlib + x/crypto only.
//
// JS calls globalThis.noethrionVerify(rpcUrl, attester, chainId, epoch,
// batchJSON, attestationJSON, pubKeyPEM) and gets back a Promise that resolves
// to {status, details}. The eth_call RPC goes through the browser's fetch
// (passed in from JS) so CORS is the browser's problem, not Go's.
//
// The last two args (attestationJSON, pubKeyPEM) are OPTIONAL and mirror the
// native node's attestation.json + attester.key.pub files: when present, the
// in-browser verifier runs the SAME ECDSA P-256 (ES256) signature check the Go
// and Python nodes run (crypto/ecdsa + crypto/x509 all compile to js/wasm), so
// the WASM verdict matches the other two implementations byte-for-byte. When
// absent it reports "signature not checked" honestly and never claims "fully
// verified".
//
// Build: GOOS=js GOARCH=wasm go build -o verifier.wasm .
package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"math/big"
	"strings"
	"syscall/js"

	"golang.org/x/crypto/sha3"
)

// ─────────────────────────────────────────────────────────────────────────────
// Primitives (keccak256 + tiny ABI), mirroring main.go exactly.
// ─────────────────────────────────────────────────────────────────────────────

// keccak256 — Ethereum's legacy Keccak (NOT NIST SHA3-256).
func keccak256(parts ...[]byte) []byte {
	h := sha3.NewLegacyKeccak256()
	for _, p := range parts {
		h.Write(p)
	}
	return h.Sum(nil)
}

func hexToBytes(s string) ([]byte, error) {
	s = strings.TrimPrefix(strings.ToLower(strings.TrimSpace(s)), "0x")
	return hex.DecodeString(s)
}

// leftPad32 left-pads b to a 32-byte word (abi fixed-field encoding).
func leftPad32(b []byte) []byte {
	if len(b) >= 32 {
		return b[len(b)-32:]
	}
	out := make([]byte, 32)
	copy(out[32-len(b):], b)
	return out
}

// addrTo20 parses a 0x-prefixed 20-byte address into its raw 20 bytes.
func addrTo20(s string) ([]byte, error) {
	b, err := hexToBytes(s)
	if err != nil {
		return nil, err
	}
	if len(b) != 20 {
		return nil, fmt.Errorf("address must be 20 bytes, got %d", len(b))
	}
	return b, nil
}

// computeLeaf mirrors keccak256(abi.encode(uint256 chainId, address attester,
// address beneficiary, uint128 amount, uint64 epoch)) — each field 32-byte padded.
func computeLeaf(chainID *big.Int, attester20, beneficiary20 []byte, amount *big.Int, epoch uint64) []byte {
	buf := make([]byte, 0, 160)
	buf = append(buf, leftPad32(chainID.Bytes())...)
	buf = append(buf, leftPad32(attester20)...)
	buf = append(buf, leftPad32(beneficiary20)...)
	buf = append(buf, leftPad32(amount.Bytes())...)
	buf = append(buf, leftPad32(new(big.Int).SetUint64(epoch).Bytes())...)
	return keccak256(buf)
}

// verifyMerkle replays a sorted-pair keccak256 proof (OZ MerkleProof semantics).
func verifyMerkle(leaf []byte, proofHex []string, root []byte) (bool, error) {
	h := leaf
	for i, ph := range proofHex {
		p, err := hexToBytes(ph)
		if err != nil {
			return false, fmt.Errorf("proof[%d]: %w", i, err)
		}
		if len(p) != 32 {
			return false, fmt.Errorf("proof[%d]: must be 32 bytes, got %d", i, len(p))
		}
		var lo, hi []byte
		if string(h) < string(p) {
			lo, hi = h, p
		} else {
			lo, hi = p, h
		}
		h = keccak256(lo, hi)
	}
	return string(h) == string(root), nil
}

// ─────────────────────────────────────────────────────────────────────────────
// Hand-rolled batches(uint64) call — selector + 32-byte-word decode.
//
// Solidity: batches(uint64 epoch) returns (
//	bytes32 merkleRoot, uint64 epoch, uint128 totalKwh, uint64 timestamp,
//	address proposer, bool finalized, uint64 thresholdAtPropose,
//	uint64 challengeWindowAtPropose)
// All eight outputs are fixed-size → eight 32-byte words, no offsets/tails.
// ─────────────────────────────────────────────────────────────────────────────

// batchesSelector = first 4 bytes of keccak256("batches(uint64)").
func batchesSelector() []byte { return keccak256([]byte("batches(uint64)"))[:4] }

// encodeBatchesCall builds the eth_call data: selector || uint256(epoch).
func encodeBatchesCall(epoch uint64) []byte {
	data := make([]byte, 0, 36)
	data = append(data, batchesSelector()...)
	data = append(data, leftPad32(new(big.Int).SetUint64(epoch).Bytes())...)
	return data
}

type batchView struct {
	merkleRoot []byte // 32 bytes
	timestamp  uint64
	finalized  bool
}

// decodeBatches reads the first six output words we care about (root, _, _,
// timestamp, _, finalized). The trailing words are ignored.
func decodeBatches(res []byte) (batchView, error) {
	var bv batchView
	// batches() returns an 8-word struct; we read up to word[5]. Require the
	// full 256 bytes (strict parity with the native node's abi.Unpack), so a
	// truncated response is rejected rather than read out of bounds.
	if len(res) < 8*32 {
		return bv, fmt.Errorf("short return: %d bytes (need >= 256)", len(res))
	}
	word := func(i int) []byte { return res[i*32 : (i+1)*32] }
	bv.merkleRoot = append([]byte{}, word(0)...)
	// timestamp is word[3], a uint64 right-aligned in its 32-byte slot.
	bv.timestamp = new(big.Int).SetBytes(word(3)).Uint64()
	// finalized is word[5]: zero = false, non-zero = true.
	bv.finalized = new(big.Int).SetBytes(word(5)).Sign() != 0
	return bv, nil
}

// ─────────────────────────────────────────────────────────────────────────────
// Published batch JSON shape — same as main.go's batchFile/leafRec.
// ─────────────────────────────────────────────────────────────────────────────

type leafRec struct {
	Beneficiary string      `json:"beneficiary"`
	AmountWei   json.Number `json:"amount_wei"`
	Amount      json.Number `json:"amount"`
	Leaf        string      `json:"leaf"`
	Proof       []string    `json:"proof"`
}
type batchFile struct {
	Epoch  uint64    `json:"epoch"`
	Root   string    `json:"root"`
	Leaves []leafRec `json:"leaves"`
}

type verdict struct {
	Status  string   `json:"status"` // "OK" | "ALARM" | "SKIP"
	Details []string `json:"details"`
}

func alarm(format string, a ...any) verdict {
	return verdict{Status: "ALARM", Details: []string{fmt.Sprintf(format, a...)}}
}
func skip(format string, a ...any) verdict {
	return verdict{Status: "SKIP", Details: []string{fmt.Sprintf(format, a...)}}
}

// ─────────────────────────────────────────────────────────────────────────────
// ECDSA P-256 (ES256) signature check — byte-for-byte mirror of native
// main.go's verifySig. Verifies SHA-256(payload_b64_canonical) against the
// PKIX P-256 public key using the r||s (64-byte) signature.
//
// Returns (ok, present, msg):
//   - present=false  → no attestation/pubkey supplied; caller treats as SKIP of
//     the signature check only (chain checks still gate the verdict). The result
//     is then labeled honestly as "leaf+merkle verified, signature not checked".
//   - present=true, ok=false → signature failed / data malformed → ALARM.
//   - present=true, ok=true  → signature verified → eligible for "fully verified".
// ─────────────────────────────────────────────────────────────────────────────
func verifySig(attestationJSON, pubKeyPEM string) (ok bool, present bool, msg string) {
	attestationJSON = strings.TrimSpace(attestationJSON)
	pubKeyPEM = strings.TrimSpace(pubKeyPEM)
	if attestationJSON == "" || pubKeyPEM == "" {
		return true, false, "no attestation/pubkey supplied — signature check skipped"
	}
	var att struct {
		Payload string `json:"payload_b64_canonical"`
		SigHex  string `json:"signature_rs_hex"`
		Alg     string `json:"algorithm"`
	}
	if err := json.Unmarshal([]byte(attestationJSON), &att); err != nil {
		return false, true, "attestation.json malformed"
	}
	block, _ := pem.Decode([]byte(pubKeyPEM))
	if block == nil {
		return false, true, "pubkey PEM malformed"
	}
	pubAny, err := x509.ParsePKIXPublicKey(block.Bytes)
	if err != nil {
		return false, true, "pubkey parse failed"
	}
	pub, ok2 := pubAny.(*ecdsa.PublicKey)
	if !ok2 || pub.Curve != elliptic.P256() {
		return false, true, "pubkey is not P-256"
	}
	sig, err := hexToBytes(att.SigHex)
	if err != nil || len(sig) != 64 {
		return false, true, "signature_rs_hex must be 64 bytes"
	}
	r := new(big.Int).SetBytes(sig[:32])
	s := new(big.Int).SetBytes(sig[32:])
	digest := sha256.Sum256([]byte(att.Payload))
	if ecdsa.Verify(pub, digest[:], r, s) {
		return true, true, "attestation P-256 signature OK"
	}
	return false, true, "attestation P-256 signature did NOT validate"
}

// ─────────────────────────────────────────────────────────────────────────────
// verifyEpoch — same control flow as native main.go verifyEpoch, but the
// on-chain word blob is supplied by JS (it already fetched it) instead of
// go-ethereum's CallContract.
// ─────────────────────────────────────────────────────────────────────────────

func verifyEpoch(rawResult []byte, attesterStr string, chainID *big.Int, epoch uint64, batchJSON, attestationJSON, pubKeyPEM string) verdict {
	attester20, err := addrTo20(attesterStr)
	if err != nil {
		return skip("bad attester address: %v", err)
	}

	bv, err := decodeBatches(rawResult)
	if err != nil {
		return skip("epoch %d: decode error: %v", epoch, err)
	}
	if bv.timestamp == 0 {
		return skip("epoch %d: not proposed yet", epoch)
	}
	if !bv.finalized {
		return skip("epoch %d: not finalized yet", epoch)
	}
	rootOnChain := bv.merkleRoot

	// From here on the epoch is FINALIZED on-chain. Any failure to reconcile the
	// published data is a transparency failure and must ALARM (fail closed), NOT
	// SKIP — matching the native Go/Python nodes. A finalized epoch with missing
	// or garbage published data is exactly the case the watchdog exists to catch.
	var bf batchFile
	if strings.TrimSpace(batchJSON) == "" {
		return alarm("epoch %d: FINALIZED on-chain but no published batch JSON supplied", epoch)
	}
	if err := json.Unmarshal([]byte(batchJSON), &bf); err != nil {
		return alarm("epoch %d: FINALIZED on-chain but published batch JSON is malformed: %v", epoch, err)
	}
	if bf.Epoch != epoch {
		return alarm("epoch %d: FINALIZED on-chain but published batch JSON is for epoch %d, not %d", epoch, bf.Epoch, epoch)
	}

	details := []string{}
	publishedRoot, err := hexToBytes(bf.Root)
	if err != nil || string(publishedRoot) != string(rootOnChain) {
		return alarm("epoch %d: published root %s != on-chain root 0x%x", epoch, bf.Root, rootOnChain)
	}
	details = append(details, fmt.Sprintf("epoch %d: published root matches on-chain root 0x%x", epoch, rootOnChain))

	for i, lf := range bf.Leaves {
		amtStr := string(lf.AmountWei)
		if amtStr == "" {
			amtStr = string(lf.Amount)
		}
		amount, okAmt := new(big.Int).SetString(amtStr, 10)
		if !okAmt {
			return alarm("epoch %d leaf[%d]: bad amount %q", epoch, i, amtStr)
		}
		beneficiary20, err := addrTo20(lf.Beneficiary)
		if err != nil {
			return alarm("epoch %d leaf[%d]: bad beneficiary %q: %v", epoch, i, lf.Beneficiary, err)
		}
		recomputed := computeLeaf(chainID, attester20, beneficiary20, amount, epoch)
		if lf.Leaf != "" {
			claimed, _ := hexToBytes(lf.Leaf)
			if string(claimed) != string(recomputed) {
				return alarm("epoch %d leaf[%d] (%s): recomputed 0x%x != published %s", epoch, i, lf.Beneficiary, recomputed, lf.Leaf)
			}
		}
		ok, err := verifyMerkle(recomputed, lf.Proof, rootOnChain)
		if err != nil || !ok {
			return alarm("epoch %d leaf[%d] (%s): Merkle proof FAILED", epoch, i, lf.Beneficiary)
		}
	}
	details = append(details, fmt.Sprintf("epoch %d: all %d leaf(s) re-derived + Merkle-verified against on-chain root", epoch, len(bf.Leaves)))

	// Signature check — the SAME ECDSA P-256 (ES256) verification the native
	// Go/Python nodes perform. If the attestation + pubkey were supplied and the
	// signature does NOT validate, ALARM (fail closed).
	sigOK, sigPresent, sigMsg := verifySig(attestationJSON, pubKeyPEM)
	if !sigOK {
		return alarm("epoch %d: %s", epoch, sigMsg)
	}
	details = append(details, fmt.Sprintf("epoch %d: %s", epoch, sigMsg))

	// Honest labeling: only claim "fully verified" when the signature was
	// actually checked. Otherwise say plainly that the signature was not checked
	// so the in-browser result never overclaims (M3).
	if sigPresent {
		details = append(details, fmt.Sprintf("epoch %d fully verified", epoch))
	} else {
		details = append(details, fmt.Sprintf("epoch %d: leaf+merkle verified, signature not checked", epoch))
	}
	return verdict{Status: "OK", Details: details}
}

// ─────────────────────────────────────────────────────────────────────────────
// JS bridge.
//
// We export TWO things:
//   - noethrionBatchesCall(epoch): returns "0x"+hex of the eth_call data, so JS
//     can POST the eth_call itself (CORS + fetch live on the JS side, clearer).
//   - noethrionVerify(rpcUrl, attester, chainId, epoch, batchJSON): a Promise.
//     It calls back into JS's fetch to do the eth_call, then runs verifyEpoch.
//
// JS fetch is reached via globalThis.fetch; we drive the Promise from Go with
// Then/Catch so the whole RPC round-trip stays inside one exported call.
// ─────────────────────────────────────────────────────────────────────────────

func verdictToJS(v verdict) js.Value {
	details := make([]any, len(v.Details))
	for i, d := range v.Details {
		details[i] = d
	}
	return js.ValueOf(map[string]any{
		"status":  v.Status,
		"details": details,
	})
}

// jsBatchesCall(epoch) -> "0x..." eth_call data (handy for debugging / manual calls).
func jsBatchesCall(this js.Value, args []js.Value) any {
	if len(args) < 1 {
		return js.ValueOf("error: epoch required")
	}
	epoch := uint64(args[0].Int())
	return js.ValueOf("0x" + hex.EncodeToString(encodeBatchesCall(epoch)))
}

// jsVerify(rpcUrl, attester, chainId, epoch, batchJSON[, attestationJSON, pubKeyPEM])
// -> Promise<{status,details}>. The last two args are optional and enable the
// ECDSA P-256 signature check (mirroring the native node's attestation.json +
// attester.key.pub). Omitted/empty → signature is honestly reported unchecked.
func jsVerify(this js.Value, args []js.Value) any {
	if len(args) < 5 {
		return rejectedPromise("noethrionVerify(rpcUrl, attester, chainId, epoch, batchJSON[, attestationJSON, pubKeyPEM]) — at least 5 args required")
	}
	rpcURL := args[0].String()
	attester := args[1].String()
	chainIDStr := args[2].String()
	epoch := uint64(args[3].Int())
	batchJSON := args[4].String()

	// Optional signature-check inputs.
	optStr := func(i int) string {
		if len(args) > i && !args[i].IsUndefined() && !args[i].IsNull() {
			return args[i].String()
		}
		return ""
	}
	attestationJSON := optStr(5)
	pubKeyPEM := optStr(6)

	chainID, ok := new(big.Int).SetString(strings.TrimSpace(chainIDStr), 10)
	if !ok {
		return rejectedPromise("bad chainId: " + chainIDStr)
	}

	callData := "0x" + hex.EncodeToString(encodeBatchesCall(epoch))

	handler := js.FuncOf(func(_ js.Value, promiseArgs []js.Value) any {
		resolve := promiseArgs[0]
		reject := promiseArgs[1]

		go func() {
			rawResult, err := ethCall(rpcURL, attester, callData)
			if err != nil {
				// RPC failure → SKIP verdict (mirrors native node's rpc error path).
				resolve.Invoke(verdictToJS(skip("epoch %d: rpc error: %v", epoch, err)))
				return
			}
			defer func() {
				if r := recover(); r != nil {
					reject.Invoke(js.ValueOf(fmt.Sprintf("internal error: %v", r)))
				}
			}()
			v := verifyEpoch(rawResult, attester, chainID, epoch, batchJSON, attestationJSON, pubKeyPEM)
			resolve.Invoke(verdictToJS(v))
		}()
		return nil
	})

	promiseCtor := js.Global().Get("Promise")
	return promiseCtor.New(handler)
}

// ethCall POSTs an eth_call to rpcURL via the browser's fetch and returns the
// decoded result bytes. Done synchronously from a goroutine by blocking on a
// channel fed by JS Then/Catch callbacks.
func ethCall(rpcURL, to, data string) ([]byte, error) {
	body := map[string]any{
		"jsonrpc": "2.0",
		"id":      1,
		"method":  "eth_call",
		"params": []any{
			map[string]any{"to": to, "data": data},
			"latest",
		},
	}
	bodyBytes, _ := json.Marshal(body)

	fetch := js.Global().Get("fetch")
	if fetch.IsUndefined() {
		return nil, fmt.Errorf("globalThis.fetch unavailable")
	}

	opts := map[string]any{
		"method":  "POST",
		"headers": map[string]any{"Content-Type": "application/json"},
		"body":    string(bodyBytes),
	}

	type fetchResult struct {
		text string
		err  error
	}
	done := make(chan fetchResult, 1)

	var thenText, onResp, onErr js.Func

	onErr = js.FuncOf(func(_ js.Value, a []js.Value) any {
		msg := "fetch failed"
		if len(a) > 0 {
			msg = a[0].Call("toString").String()
		}
		done <- fetchResult{err: fmt.Errorf("%s", msg)}
		return nil
	})

	thenText = js.FuncOf(func(_ js.Value, a []js.Value) any {
		text := ""
		if len(a) > 0 {
			text = a[0].String()
		}
		done <- fetchResult{text: text}
		return nil
	})

	onResp = js.FuncOf(func(_ js.Value, a []js.Value) any {
		if len(a) == 0 {
			done <- fetchResult{err: fmt.Errorf("empty fetch response")}
			return nil
		}
		resp := a[0]
		// Resolve text() regardless of status; JSON-RPC errors come back 200 anyway.
		resp.Call("text").Call("then", thenText).Call("catch", onErr)
		return nil
	})

	promise := fetch.Invoke(rpcURL, opts)
	promise.Call("then", onResp).Call("catch", onErr)

	res := <-done
	// Release JS callbacks.
	onResp.Release()
	thenText.Release()
	onErr.Release()

	if res.err != nil {
		return nil, res.err
	}

	var rpcResp struct {
		Result string `json:"result"`
		Error  *struct {
			Code    int    `json:"code"`
			Message string `json:"message"`
		} `json:"error"`
	}
	if err := json.Unmarshal([]byte(res.text), &rpcResp); err != nil {
		return nil, fmt.Errorf("bad JSON-RPC response: %v", err)
	}
	if rpcResp.Error != nil {
		return nil, fmt.Errorf("rpc error %d: %s", rpcResp.Error.Code, rpcResp.Error.Message)
	}
	out, err := hexToBytes(rpcResp.Result)
	if err != nil {
		return nil, fmt.Errorf("result not hex: %v", err)
	}
	return out, nil
}

func rejectedPromise(msg string) js.Value {
	handler := js.FuncOf(func(_ js.Value, a []js.Value) any {
		a[1].Invoke(js.ValueOf(msg)) // reject
		return nil
	})
	return js.Global().Get("Promise").New(handler)
}

func main() {
	global := js.Global()
	global.Set("noethrionVerify", js.FuncOf(jsVerify))
	global.Set("noethrionBatchesCall", js.FuncOf(jsBatchesCall))
	// Park forever so the exported functions stay alive.
	select {}
}
