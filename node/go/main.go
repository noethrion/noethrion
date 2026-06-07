// Noethrion independent verifier node — Go implementation (v0.1).
//
// Same job as ../verifier_node.py, but compiles to a single static binary for
// any OS (and, later, to WASM for an in-browser verifier). For every finalized
// batch it re-derives each leaf as
//
//	keccak256(abi.encode(chainId, attester, beneficiary, amount, epoch))
//
// — exactly as NoethrionAttester.claim() does — replays the sorted-pair
// keccak256 Merkle proof against the on-chain root, optionally re-checks the
// ECDSA P-256 attestation signature, and ALARMs on any mismatch. Never trusts
// the operator; recomputes everything from the on-chain commitment.
//
// Scope v0.1: chain + signatures. (Consumption-matching is a later version.)
//
// Build:  cd node/go && go build -o noethrion-verify .
// Run:    ./noethrion-verify --rpc <url> --attester 0x... --chain-id 11155111 --data-dir ./published --once
package main

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/sha256"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"flag"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"strings"
	"time"

	ethereum "github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

const attesterABI = `[{"type":"function","name":"batches","stateMutability":"view","inputs":[{"name":"epoch","type":"uint64"}],"outputs":[{"name":"merkleRoot","type":"bytes32"},{"name":"epoch","type":"uint64"},{"name":"totalKwh","type":"uint128"},{"name":"timestamp","type":"uint64"},{"name":"proposer","type":"address"},{"name":"finalized","type":"bool"},{"name":"thresholdAtPropose","type":"uint64"},{"name":"challengeWindowAtPropose","type":"uint64"}]}]`

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

func logf(level, format string, a ...any) { fmt.Printf("["+level+"] "+format+"\n", a...) }

func hexToBytes(s string) ([]byte, error) {
	s = strings.TrimPrefix(strings.ToLower(strings.TrimSpace(s)), "0x")
	return hex.DecodeString(s)
}

// computeLeaf mirrors keccak256(abi.encode(uint256 chainId, address attester,
// address beneficiary, uint128 amount, uint64 epoch)) — each field 32-byte padded.
func computeLeaf(chainID *big.Int, attester, beneficiary common.Address, amount *big.Int, epoch uint64) []byte {
	buf := make([]byte, 0, 160)
	buf = append(buf, common.LeftPadBytes(chainID.Bytes(), 32)...)
	buf = append(buf, common.LeftPadBytes(attester.Bytes(), 32)...)
	buf = append(buf, common.LeftPadBytes(beneficiary.Bytes(), 32)...)
	buf = append(buf, common.LeftPadBytes(amount.Bytes(), 32)...)
	buf = append(buf, common.LeftPadBytes(new(big.Int).SetUint64(epoch).Bytes(), 32)...)
	return crypto.Keccak256(buf)
}

// verifyMerkle replays a sorted-pair keccak256 proof (OZ MerkleProof semantics).
func verifyMerkle(leaf []byte, proofHex []string, root []byte) (bool, error) {
	h := leaf
	for i, ph := range proofHex {
		p, err := hexToBytes(ph)
		if err != nil {
			return false, fmt.Errorf("proof[%d]: %w", i, err)
		}
		var lo, hi []byte
		if string(h) < string(p) {
			lo, hi = h, p
		} else {
			lo, hi = p, h
		}
		h = crypto.Keccak256(append(append([]byte{}, lo...), hi...))
	}
	return string(h) == string(root), nil
}

// verifySig re-checks the ECDSA P-256 attestation signature, if published.
func verifySig(dir string) (ok bool, present bool, msg string) {
	attBytes, err1 := os.ReadFile(filepath.Join(dir, "attestation.json"))
	pubBytes, err2 := os.ReadFile(filepath.Join(dir, "attester.key.pub"))
	if err1 != nil || err2 != nil {
		return true, false, "no attestation/pubkey published — signature check skipped"
	}
	var att struct {
		Payload string `json:"payload_b64_canonical"`
		SigHex  string `json:"signature_rs_hex"`
		Alg     string `json:"algorithm"`
	}
	if err := json.Unmarshal(attBytes, &att); err != nil {
		return false, true, "attestation.json malformed"
	}
	block, _ := pem.Decode(pubBytes)
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

func loadBatch(dir string, epoch uint64) (*batchFile, bool) {
	for _, name := range []string{fmt.Sprintf("batch-%d.json", epoch), "batch.json"} {
		b, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			continue
		}
		var bf batchFile
		if json.Unmarshal(b, &bf) == nil && bf.Epoch == epoch {
			return &bf, true
		}
	}
	return nil, false
}

// verifyEpoch returns status: "OK", "ALARM", or "SKIP".
func verifyEpoch(ctx context.Context, client *ethclient.Client, parsed abi.ABI, attester common.Address, chainID *big.Int, epoch uint64, dir string) (string, []string) {
	calldata, _ := parsed.Pack("batches", epoch)
	res, err := client.CallContract(ctx, ethereum.CallMsg{To: &attester, Data: calldata}, nil)
	if err != nil {
		return "SKIP", []string{fmt.Sprintf("epoch %d: rpc error: %v", epoch, err)}
	}
	out, err := parsed.Unpack("batches", res)
	if err != nil || len(out) < 6 {
		return "SKIP", []string{fmt.Sprintf("epoch %d: decode error", epoch)}
	}
	merkleRoot := out[0].([32]byte)
	timestamp := out[3].(uint64)
	finalized := out[5].(bool)
	if timestamp == 0 {
		return "SKIP", []string{fmt.Sprintf("epoch %d: not proposed yet", epoch)}
	}
	if !finalized {
		return "SKIP", []string{fmt.Sprintf("epoch %d: not finalized yet", epoch)}
	}
	rootOnChain := merkleRoot[:]

	bf, found := loadBatch(dir, epoch)
	if !found {
		return "ALARM", []string{fmt.Sprintf("epoch %d: FINALIZED on-chain but no published batch data in %s", epoch, dir)}
	}
	details := []string{}
	publishedRoot, err := hexToBytes(bf.Root)
	if err != nil || string(publishedRoot) != string(rootOnChain) {
		return "ALARM", []string{fmt.Sprintf("epoch %d: published root %s != on-chain root 0x%x", epoch, bf.Root, rootOnChain)}
	}
	details = append(details, fmt.Sprintf("epoch %d: published root matches on-chain root 0x%x", epoch, rootOnChain))

	for i, lf := range bf.Leaves {
		amtStr := string(lf.AmountWei)
		if amtStr == "" {
			amtStr = string(lf.Amount)
		}
		amount, okAmt := new(big.Int).SetString(amtStr, 10)
		if !okAmt {
			return "ALARM", []string{fmt.Sprintf("epoch %d leaf[%d]: bad amount %q", epoch, i, amtStr)}
		}
		recomputed := computeLeaf(chainID, attester, common.HexToAddress(lf.Beneficiary), amount, epoch)
		if lf.Leaf != "" {
			claimed, _ := hexToBytes(lf.Leaf)
			if string(claimed) != string(recomputed) {
				return "ALARM", []string{fmt.Sprintf("epoch %d leaf[%d] (%s): recomputed 0x%x != published %s", epoch, i, lf.Beneficiary, recomputed, lf.Leaf)}
			}
		}
		ok, err := verifyMerkle(recomputed, lf.Proof, rootOnChain)
		if err != nil || !ok {
			return "ALARM", []string{fmt.Sprintf("epoch %d leaf[%d] (%s): Merkle proof FAILED", epoch, i, lf.Beneficiary)}
		}
	}
	details = append(details, fmt.Sprintf("epoch %d: all %d leaf(s) re-derived + Merkle-verified against on-chain root", epoch, len(bf.Leaves)))

	sigOK, _, sigMsg := verifySig(dir)
	if !sigOK {
		return "ALARM", []string{fmt.Sprintf("epoch %d: %s", epoch, sigMsg)}
	}
	details = append(details, fmt.Sprintf("epoch %d: %s", epoch, sigMsg))
	return "OK", details
}

func main() {
	rpc := flag.String("rpc", "", "EVM RPC URL")
	attesterStr := flag.String("attester", "", "deployed NoethrionAttester address")
	chainIDInt := flag.Int64("chain-id", 0, "chain id (leaf domain separator)")
	dataDir := flag.String("data-dir", "./published", "dir with operator-published batch data")
	startEpoch := flag.Uint64("start-epoch", 1, "first epoch to verify")
	interval := flag.Int("interval", 30, "daemon poll interval seconds")
	once := flag.Bool("once", false, "single pass then exit")
	flag.Parse()
	if *rpc == "" || *attesterStr == "" || *chainIDInt == 0 {
		fmt.Fprintln(os.Stderr, "usage: --rpc <url> --attester 0x... --chain-id <n> [--data-dir d] [--once]")
		os.Exit(2)
	}

	ctx := context.Background()
	client, err := ethclient.DialContext(ctx, *rpc)
	if err != nil {
		logf("ERROR", "cannot connect to RPC %s: %v", *rpc, err)
		os.Exit(2)
	}
	parsed, err := abi.JSON(strings.NewReader(attesterABI))
	if err != nil {
		logf("ERROR", "bad ABI: %v", err)
		os.Exit(2)
	}
	attester := common.HexToAddress(*attesterStr)
	chainID := big.NewInt(*chainIDInt)
	logf("INFO", "connected: chainId=%d attester=%s data-dir=%s", *chainIDInt, attester.Hex(), *dataDir)

	epoch := *startEpoch
	alarms := 0
	for {
		status, details := verifyEpoch(ctx, client, parsed, attester, chainID, epoch, *dataDir)
		lvl := "INFO"
		if status == "ALARM" {
			lvl = "ALARM"
		}
		for _, d := range details {
			logf(lvl, "%s", d)
		}
		switch status {
		case "OK":
			logf("OK", "epoch %d fully verified", epoch)
			epoch++
			continue
		case "ALARM":
			alarms++
			logf("ALARM", "*** VERIFICATION FAILED at epoch %d · total_alarms=%d ***", epoch, alarms)
			if *once {
				os.Exit(1)
			}
		}
		// SKIP or post-ALARM: nothing new this tick.
		if *once {
			if alarms > 0 {
				os.Exit(1)
			}
			os.Exit(0)
		}
		time.Sleep(time.Duration(*interval) * time.Second)
	}
}
