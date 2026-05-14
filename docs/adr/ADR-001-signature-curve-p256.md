# ADR-001 — Use ECDSA P-256 as the device signature scheme

- **Status:** Accepted
- **Date:** 2026-05-13
- **Deciders:** Founding contributors

## Context

The Noethrion protocol requires devices to produce cryptographic signatures over measurement tuples. The signature scheme choice affects: (a) which secure elements can produce signatures at the meter, (b) the on-chain verification gas cost when a downstream contract checks a signature directly, (c) interoperability with enterprise cryptographic policies of likely relying parties (utilities, regulators, large compute operators), and (d) the post-quantum migration trajectory.

The decision sits between three primary candidates with established secure-element support and verifier ecosystems.

## Decision

The v0.1 protocol uses **ECDSA over the NIST P-256 curve (secp256r1) with SHA-256**, denoted `ES256` in COSE / RFC 8152.

## Consequences

**Positive**
- P-256 is supported by the widest set of low-cost CC EAL5+ secure elements suitable for meter integration. The reference firmware target (Microchip ATECC608B) and equivalents from Infineon, NXP, and others all support it natively. This keeps the hardware BOM under approximately one dollar at volume.
- Enterprise relying parties (utilities, compliance offices, hyperscaler sustainability teams) typically have internal cryptographic policies that explicitly approve NIST curves. P-256 attestations clear those policies without amendment.
- Signing performance inside a microcontroller-bound secure element is sufficient for the protocol's per-minute cadence.
- ECDSA P-256 on-chain verification is a built-in EVM precompile (`ecrecover` is secp256k1; P-256 needs a contract or a different precompile path). The protocol's normal verification path is **Merkle inclusion against a root**, not direct ECDSA on every leaf, so the gas hit is bounded.

**Negative**
- P-256 is not post-quantum secure. The protocol must include a migration path to a post-quantum scheme; ADR-001 acknowledges this debt explicitly.
- Some open-source cryptographic communities prefer Ed25519 for its simpler implementation surface. The protocol cannot use Ed25519 in the meter today because secure-element coverage is uneven, but a future profile could allow operators to choose.
- P-256 is more vulnerable to nonce-reuse failures than deterministic-nonce schemes (Ed25519, RFC 6979 ECDSA). Implementations MUST use deterministic-nonce ECDSA per RFC 6979 to mitigate.

## Alternatives considered

**Ed25519 (RFC 8032 EdDSA)** — Smaller code, deterministic nonces by construction, fashionable in newer cryptographic protocols. Rejected for v0.1 because secure-element coverage at meter price points is materially weaker. Will be reconsidered in v0.2 as a parallel-allowed profile if the supply situation changes.

**secp256k1** — Native to Ethereum's `ecrecover` precompile, so on-chain verification is cheaper than P-256. Rejected because secure-element support at the relevant price point is dominated by cryptocurrency wallet products rather than industrial measurement parts, and the price/availability profile at the meter is worse than P-256.

**ML-DSA (CRYSTALS-Dilithium)** — Post-quantum secure, finalised in FIPS 204. Rejected for v0.1 because secure-element support does not yet exist at the meter price point and key/signature sizes (1300 / 2400 bytes) are inconvenient for the per-batch storage budget. Recorded as the **migration target** in Section 5.2 of the protocol specification.

## Open questions

- The exact deterministic-nonce mandate language for the v0.2 specification text.
- Whether to ship an Ed25519 profile in parallel once secure-element coverage warrants.
- When to set the migration trigger to ML-DSA (calendar date, secure-element availability threshold, NIST guidance update, or all three).
