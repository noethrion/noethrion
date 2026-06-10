/**
 * Noethrion attestation verifier — Node-only TypeScript reference.
 *
 * Single exported function `verifyAttestation()` returns
 * `{ ok: true } | { ok: false, reason: string }`.
 *
 * Dependencies (in package.json):
 *   - @noble/curves   ECDSA P-256
 *   - @noble/hashes   keccak256
 *
 * No DOM, no fetch, no browser globals. Runs in Node 18+, Cloudflare Workers,
 * Vercel Edge, AWS Lambda, Deno (with --allow-import).
 *
 * Example:
 *
 *     import { verifyAttestation } from "./javascript_verifier";
 *     import { readFileSync } from "node:fs";
 *
 *     const attestation = JSON.parse(readFileSync("attestation.json", "utf-8"));
 *     const publicKeyPem = readFileSync("attester.key.pub", "utf-8");
 *
 *     const result = verifyAttestation({
 *       attestation,
 *       publicKeyPem,
 *       merkleRoot: "0xabc...",
 *       merkleProof: ["0xdef...", "0x123..."],
 *       chainId: 1n,                                              // the chain the Attester is deployed on
 *       attesterAddress: "0x...",                                 // the deployed NoethrionAttester contract address
 *       beneficiary: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
 *       amountWei: BigInt("100000000000000000000"),
 *       epoch: 1n,
 *     });
 *
 *     if (result.ok) {
 *       console.log("attestation verified");
 *     } else {
 *       console.warn("verification failed:", result.reason);
 *     }
 */

import { p256 } from "@noble/curves/p256";
import { sha256 } from "@noble/hashes/sha2";
import { keccak_256 } from "@noble/hashes/sha3";

export type VerificationResult =
  | { ok: true }
  | { ok: false; reason: string };

export interface Attestation {
  // Contains raw canonical JSON, not base64 — naming kept for v0.1
  // wire-format compatibility.
  payload_b64_canonical: string;
  signature_rs_hex: string;
  algorithm: string;
}

export interface VerifyArgs {
  attestation: Attestation;
  publicKeyPem: string;
  merkleRoot: string;            // hex, 0x-prefixed or bare
  merkleProof: readonly string[]; // each hex, 32 bytes
  chainId: bigint;               // the chain id the Attester is deployed on
  attesterAddress: string;       // 0x-prefixed 20-byte address of the deployed NoethrionAttester
  beneficiary: string;           // 0x-prefixed 20-byte address
  amountWei: bigint;
  epoch: bigint;
}

export function verifyAttestation(args: VerifyArgs): VerificationResult {
  const sigResult = verifySignature(args.attestation, args.publicKeyPem);
  if (!sigResult.ok) return sigResult;
  return verifyMerkle(
    args.chainId,
    args.attesterAddress,
    args.beneficiary,
    args.amountWei,
    args.epoch,
    args.merkleProof,
    args.merkleRoot,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Signature
// ─────────────────────────────────────────────────────────────────────────────

export function verifySignature(
  attestation: Attestation,
  publicKeyPem: string,
): VerificationResult {
  if (attestation.algorithm !== "ES256") {
    return { ok: false, reason: `unsupported algorithm ${attestation.algorithm} (only ES256)` };
  }
  let sigBytes: Uint8Array;
  try {
    sigBytes = hexToBytes(attestation.signature_rs_hex);
  } catch (e) {
    return { ok: false, reason: `signature_rs_hex not valid hex: ${(e as Error).message}` };
  }
  if (sigBytes.length !== 64) {
    return { ok: false, reason: `signature must be 64 raw bytes, got ${sigBytes.length}` };
  }

  const pubKeyXy = parseP256PublicKeyPem(publicKeyPem);
  const payload = new TextEncoder().encode(attestation.payload_b64_canonical);
  const msgHash = sha256(payload);

  // fromCompact validates the (r, s) ranges; verify takes the compact bytes.
  const sig = p256.Signature.fromCompact(sigBytes);
  const ok = p256.verify(sig.toCompactRawBytes(), msgHash, pubKeyXy);
  if (!ok) return { ok: false, reason: "ECDSA P-256 signature did not validate" };
  return { ok: true };
}

// ─────────────────────────────────────────────────────────────────────────────
// Merkle inclusion (sorted-pair keccak256 — matches OpenZeppelin MerkleProof)
// ─────────────────────────────────────────────────────────────────────────────

export function verifyMerkle(
  chainId: bigint,
  attesterAddress: string,
  beneficiary: string,
  amountWei: bigint,
  epoch: bigint,
  proofHex: readonly string[],
  rootHex: string,
): VerificationResult {
  const root = hexToBytes(rootHex);
  if (root.length !== 32) {
    return { ok: false, reason: `root must be 32 bytes, got ${root.length}` };
  }

  const leaf = computeLeaf(chainId, attesterAddress, beneficiary, amountWei, epoch);
  let computed = leaf;
  for (let i = 0; i < proofHex.length; i++) {
    const sibling = hexToBytes(proofHex[i]);
    if (sibling.length !== 32) {
      return { ok: false, reason: `proof[${i}] not 32 bytes` };
    }
    computed = hashPair(computed, sibling);
  }
  if (!bytesEqual(computed, root)) {
    return {
      ok: false,
      reason: `merkle mismatch — derived ${bytesToHex(computed)}, expected ${bytesToHex(root)}`,
    };
  }
  return { ok: true };
}

function computeLeaf(
  chainId: bigint,
  attesterAddress: string,
  beneficiary: string,
  amountWei: bigint,
  epoch: bigint,
): Uint8Array {
  // Mirror Solidity abi.encode(uint256, address, address, uint128, uint64):
  //   uint256 chainId           → 32 bytes big-endian
  //   address attester contract → 32 bytes (12 zero + 20 address)
  //   address beneficiary       → 32 bytes (12 zero + 20 address)
  //   uint128 amountWei         → 32 bytes big-endian
  //   uint64  epoch             → 32 bytes big-endian
  // The first two fields are the domain separator binding each leaf to a
  // specific Attester instance on a specific chain — a Merkle tree built
  // for one deployment is byte-different from a leaf with identical
  // (beneficiary, amount, epoch) on any sibling deployment.
  const attesterBytes = hexToBytes(attesterAddress);
  if (attesterBytes.length !== 20) throw new Error(`attesterAddress must be 20 bytes`);
  const beneficiaryBytes = hexToBytes(beneficiary);
  if (beneficiaryBytes.length !== 20) throw new Error(`beneficiary must be 20 bytes`);

  const buf = new Uint8Array(160);
  bigIntToBytes32(chainId, buf, 0);
  buf.set(attesterBytes, 32 + 12);          // address slot 1, right-aligned
  buf.set(beneficiaryBytes, 64 + 12);       // address slot 2, right-aligned
  bigIntToBytes32(amountWei, buf, 96);
  bigIntToBytes32(epoch, buf, 128);
  return keccak_256(buf);
}

function hashPair(a: Uint8Array, b: Uint8Array): Uint8Array {
  const [lo, hi] = compareBytes(a, b) < 0 ? [a, b] : [b, a];
  const merged = new Uint8Array(64);
  merged.set(lo, 0);
  merged.set(hi, 32);
  return keccak_256(merged);
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

function hexToBytes(hex: string): Uint8Array {
  const clean = hex.toLowerCase().startsWith("0x") ? hex.slice(2) : hex;
  if (clean.length % 2 !== 0) throw new Error(`odd hex length: ${hex}`);
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) {
    const byte = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
    if (Number.isNaN(byte)) throw new Error(`invalid hex char near offset ${i * 2}`);
    out[i] = byte;
  }
  return out;
}

function bytesToHex(b: Uint8Array): string {
  return "0x" + Array.from(b, x => x.toString(16).padStart(2, "0")).join("");
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

function compareBytes(a: Uint8Array, b: Uint8Array): number {
  const len = Math.min(a.length, b.length);
  for (let i = 0; i < len; i++) {
    if (a[i] !== b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}

function bigIntToBytes32(n: bigint, out: Uint8Array, offset: number): void {
  // Right-aligned big-endian into 32 bytes.
  let v = n;
  for (let i = 31; i >= 0; i--) {
    out[offset + i] = Number(v & 0xffn);
    v >>= 8n;
  }
  if (v !== 0n) throw new Error("uint overflow: value > 2^256");
}

function parseP256PublicKeyPem(pem: string): Uint8Array {
  // Decode PEM SubjectPublicKeyInfo and pull out the uncompressed
  // 65-byte point (0x04 || x[32] || y[32]). The DER preamble for a
  // P-256 SPKI is fixed-length; we scan for the BIT STRING content tag.
  const b64 = pem.replace(/-----BEGIN [^-]+-----|-----END [^-]+-----|\s+/g, "");
  const der = base64Decode(b64);
  // For prime256v1 SPKI the DER ends with "03 42 00 04 <x> <y>" (66 bytes from 0x03).
  // Find the last "00 04" before exactly 64 more bytes follow.
  for (let i = der.length - 65; i >= 0; i--) {
    if (der[i] === 0x00 && der[i + 1] === 0x04 && der.length - (i + 1) === 65) {
      return der.subarray(i + 1); // full 65-byte uncompressed point (0x04 || x || y)
    }
  }
  throw new Error("could not locate uncompressed P-256 point in SPKI");
}

function base64Decode(s: string): Uint8Array {
  // Node-safe base64 decode (no `atob` in older Node versions guaranteed).
  const buf = Buffer.from(s, "base64");
  return new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength);
}
