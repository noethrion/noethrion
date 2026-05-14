# ADR-002 — Hardware-rooted attestation as the trust foundation

- **Status:** Accepted
- **Date:** 2026-05-13
- **Deciders:** Founding contributors
- **Related:** ADR-001

## Context

Verifying that a kilowatt-hour was generated where and when it is claimed reduces to verifying a measurement. Where the verification root sits — in software, in a multi-party consensus, in zero-knowledge proofs, or in a tamper-resistant hardware component at the source — determines the protocol's threat model, its attack surface, and its legal weight.

For attestations to be useful to compliance frameworks (CBAM, 24/7 hourly matching procurement, sustainability reporting standards), they must withstand adversarial pressure from operators with strong economic incentives to misreport. Software-based and trust-based approaches have repeatedly fallen short under such pressure in adjacent industries.

## Decision

Noethrion attestations are **rooted in a hardware secure element adjacent to the meter**. The signing key is generated on-die and cannot be exported. Every attestation tuple `(kWh, timestamp, deviceID)` is signed inside the secure element before transmission. Software components — host MCU firmware, aggregators, on-chain commitment contracts — are trust-minimised but cannot compromise the signature.

## Consequences

**Positive**
- Converts the verification problem from a **trust problem** into a **physics problem**. To forge an attestation, an adversary must either physically tamper with the meter (detectable through revenue-grade sealing) or extract a private key from a Common Criteria EAL5+ secure element (currently infeasible against state-of-the-art parts and would require disproportionate resources).
- Defeating the protocol leaves **physical evidence** — either a tampered meter or an extracted chip. Software-only schemes can be defeated invisibly.
- The model is familiar from adjacent domains: EMV payment chips secure tens of trillions of dollars in card transactions; TPM modules underpin verified boot in modern laptops; DNSSEC anchors integrity to physical key ceremonies. Each runs on physics rather than trust.

**Negative**
- Requires physical hardware at every measurement point. This is the largest deployment friction in the protocol. Mitigated by the low cost of secure elements at volume (approximately one dollar) and by the fact that revenue-grade meters already have a hardware presence the secure element can sit alongside.
- A physical-tampering threat is out of scope for the protocol itself; detection relies on existing sealing and audit procedures from the metering industry. The protocol assumes those procedures function as designed.
- Forecloses some elegant fully-on-chain designs (zero-knowledge proofs of generation, oracle-quorum schemes) that work without device hardware. We accept this trade-off.

## Alternatives considered

**Software-only oracle attestation.** A trusted operator signs measurements in software. Rejected because the trust boundary collapses to the operator — the original problem the protocol exists to solve.

**Multi-party oracle quorum.** N independent operators co-sign each measurement; the protocol accepts the result if M of N agree. Rejected because (a) collusion among M operators is plausible at scale, (b) the legal weight of a quorum signature is weaker than that of a hardware signature traceable to a serialised part, and (c) operator selection becomes a governance bottleneck.

**Zero-knowledge proofs of generation.** A prover demonstrates knowledge of a witness consistent with generation without revealing the witness. Rejected for v0.1 because no working zk circuit currently exists for the relevant physical sensing primitives. May become viable in a later spec version as a complementary privacy-preserving layer; see Section 9.2 of the specification.

**Trusted execution environments (Intel SGX, AMD SEV-SNP) on commodity servers.** Rejected because TEE primitives sit too high in the stack — a compromised server-class host could still feed false measurements to the TEE. Hardware roots of trust belong at the measurement source, not the back-end.

## Open questions

- Which secure-element families are admitted into the protocol's first certified hardware list (planned for v0.2 spec) — see `docs/hardware-vendor-matrix.md`.
- How to handle secure-element revocation events (compromised batch, manufacturing recall) without invalidating valid historical attestations from non-affected devices.
- Long-term: how to add a privacy-preserving zero-knowledge variant **on top of** hardware attestation, rather than as a replacement.
