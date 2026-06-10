# Noethrion Attestation Protocol — Internet-Draft v0.1

```
Internet Engineering Task Force                              A. Chursin
Internet-Draft                                     Noethrion Foundation
Intended status: Standards Track                             May 2026
Expires: 12 November 2026
```

## Hardware-Rooted Attestation Tokens for Electricity Generation

> **Status of This Memo**
>
> This Internet-Draft is submitted in full conformance with the provisions of BCP 78 and BCP 79.
>
> Internet-Drafts are working documents of the Internet Engineering Task Force (IETF). Note that other groups may also distribute working documents as Internet-Drafts.
>
> The list of current Internet-Drafts is at <https://datatracker.ietf.org/drafts/current/>. Internet-Drafts are draft documents valid for a maximum of six months and may be updated, replaced, or obsoleted by other documents at any time. It is inappropriate to use Internet-Drafts as reference material or to cite them other than as "work in progress."
>
> Copyright Notice — Copyright (c) 2026 IETF Trust and the persons identified as the document authors. All rights reserved.

---

## Abstract

This document specifies an attestation token format and verification protocol for hardware-rooted measurements of electricity generation. The protocol enables a tamper-evident chain of custody from a metering device to a publicly verifiable settlement layer, using ECDSA P-256 signatures generated inside a Common Criteria EAL5+ certified secure element. It defines: (a) the CBOR-encoded attestation token, aligned with the Entity Attestation Token format of [RFC9711] and the RATS architecture of [RFC9334]; (b) a Merkle-aggregation and on-chain commitment scheme for scalable verification; and (c) a registry mechanism for endorsing device public keys. The token is intended for use by relying parties — energy producers, consumers, regulators, and standards bodies — that require cryptographic provenance for clean-energy claims.

## Table of Contents

1. Introduction
2. Conventions and Terminology
3. Architecture and Roles
4. Attestation Token Format
5. Signature Scheme
6. Merkle Aggregation and Settlement
7. Endorsement and Verification
8. Threat Model
9. Privacy Considerations
10. Security Considerations
11. IANA Considerations
12. References

---

## 1. Introduction

Clean-energy claims today rest on accounting infrastructure — Renewable Energy Certificates (RECs) in the United States, Guarantees of Origin (GoOs) in the European Union, International RECs (I-RECs) elsewhere. These instruments are issued annually, traded through brokered email confirmations, and reconciled against grid-level dispatch records that the issuance system does not cryptographically verify. Analyses of major markets have identified discrepancies of up to 18 percent between dispatched generation and registered certificate issuance.

Two regulatory and industrial trends, both effective in 2026, make this verification gap acute:

1. **Twenty-four-hour, hourly carbon-free energy matching** has become a procurement requirement at multiple large compute-infrastructure operators, with multi-gigawatt power purchase agreements signed for dedicated nuclear capacity over 2024–2026. Hourly matching cannot be evidenced by annual certificate aggregation.

2. **The European Union's Carbon Border Adjustment Mechanism (CBAM)**, effective 1 January 2026, requires importers of cement, iron, steel, aluminum, fertilizer, electricity, and hydrogen to demonstrate embedded carbon content at the source. There is no globally interoperable system for verifiable energy provenance that can satisfy this requirement.

This document specifies an open standard intended to close that gap. The protocol places a hardware secure element adjacent to a kilowatt-hour meter; the secure element signs the tuple `(kWh_delta, timestamp, deviceID)` with a private key that is generated on-chip and cannot be extracted; the resulting attestation tokens are aggregated into Merkle trees and committed to a public settlement layer; any relying party with the device's endorsed public key can independently verify any single attestation.

The protocol is deliberately narrow in scope. It defines verification, not trading. It does not specify payment rails, market-clearing mechanisms, or currency-like token economics. The unit of accounting in the protocol (NOET) represents one verified kilowatt-hour and is intended as a verifiable attestation token used internally by the protocol — not as a payment instrument or store-of-value asset.

This document is intended for review by the Remote ATtestation procedureS Working Group (RATS WG) and other interested IETF participants. Comments are welcome at the address given in the Authors' Addresses section.

## 2. Conventions and Terminology

The key words **MUST**, **MUST NOT**, **REQUIRED**, **SHALL**, **SHALL NOT**, **SHOULD**, **SHOULD NOT**, **RECOMMENDED**, **NOT RECOMMENDED**, **MAY**, and **OPTIONAL** in this document are to be interpreted as described in BCP 14 [RFC2119] [RFC8174] when, and only when, they appear in all capitals, as shown here.

### 2.1 Terms

| Term | Definition |
|------|------------|
| **Attester** | A metering device, paired with a secure element, that produces attestation tokens. Aligns with the Attester role in the RATS architecture [RFC9334]. |
| **Verifier** | Any party that reconstructs and validates an attestation, including its Merkle inclusion proof and on-chain commitment. |
| **Relying Party (RP)** | An economic actor consuming an attestation as evidence of clean-energy generation (a producer, consumer, regulator, or integrator). |
| **Endorser** | An entity that issues an endorsement linking a device's public key to a real-world identity (manufacturer, certification authority, or self-attested operator). |
| **Reference Values** | The expected device configuration, firmware hash, and certification status against which Verifiers may assess an Attester. |
| **Attestation Token** | A CBOR-encoded object carrying the signed measurement and ancillary claims. |
| **Settlement Layer** | A publicly accessible verifiable data structure on which Merkle roots of attestation batches are committed. In this version, the Settlement Layer is an EVM-compatible Layer 2 rollup; future revisions MAY broaden this. |
| **Batch** | An ordered collection of attestation tokens whose hashes form the leaves of a single Merkle tree. |
| **Epoch** | The sequence number identifying a batch in time. Epochs increase monotonically. |
| **Challenge Window** | A configurable period following batch submission during which the batch can be challenged before finalization. |
| **NOET** | The unit of accounting in the protocol. One NOET represents one verified kilowatt-hour. |

## 3. Architecture and Roles

This document follows the role decomposition of the RATS architecture [RFC9334]. Each role has a specific scope of responsibility and security boundary.

### 3.1 Attester

The Attester is composed of two physical components: a kilowatt-hour meter (the measurer) and a secure element (the signer). The Attester:

- **MUST** generate the device's signing key inside the secure element using on-chip entropy.
- **MUST NOT** expose the signing key outside the secure element under any operational condition.
- **MUST** sign each attestation tuple with the device's private key before transmission.
- **SHOULD** include in each attestation a hash of the previous attestation produced by the same device, forming a per-device hash chain.
- **MAY** include firmware version, model identifier, and configuration claims in the attestation token.

### 3.2 Verifier

The Verifier is software, executed by any interested party, that:

- **MUST** validate the ECDSA signature over the canonical CBOR serialization of the attestation claims using the Attester's endorsed public key.
- **MUST** verify the Merkle inclusion proof against the on-chain committed root for the corresponding epoch.
- **SHOULD** check the endorsement chain of the Attester's public key against a trusted Endorser registry.
- **MAY** apply additional Reference Values checks (firmware version, model, certification status) where required.

### 3.3 Relying Party

The Relying Party consumes attestations and acts on them. A Relying Party:

- **MUST** independently invoke a Verifier (either as a library or as a service); it **MUST NOT** rely on an Attester's self-report alone.
- **SHOULD** apply use-case-specific validity criteria beyond signature verification (e.g., timestamp freshness, jurisdiction).

### 3.4 Endorser

An Endorser issues an endorsement binding a device public key to identity metadata (manufacturer, model, certification batch). Endorsers:

- **MUST** publish their own public key in a manner that is itself verifiable (X.509 certificate, well-known DNS record, or on-chain registry).
- **SHOULD** specify the procedure by which they obtain assurance that a given public key originates from a tamper-evident secure element.

This document does not mandate a single Endorser hierarchy. A federation of Endorsers is expected to emerge in practice; relying parties choose which Endorsers to trust.

### 3.5 Validator

The Validator is an on-chain role responsible for confirming Merkle root submissions before they are finalized for claim. Validators extend the RATS architecture; they exist because the on-chain commitment layer requires a defined set of accountable parties whose signed actions are the basis of finalization. A Validator:

- **MUST** hold the `VALIDATOR_ROLE` granted by the holder of the contract's `DEFAULT_ADMIN_ROLE` (production deployments place that role in a multi-signature wallet; see the deploy runbook).
- **MUST** independently verify the Merkle root it is voting on against its own reconstruction of the underlying leaf set before broadcasting `proposeBatch` or `voteBatch`. A Validator that votes without independent verification is a single point of trust and defeats the m-of-n property the quorum is designed to provide.
- **SHOULD** publish its identity — operator, jurisdiction, contact — so that fraud-proof challengers and relying parties can attribute votes.
- **MAY** be operated by the Foundation, by a delegated operator, or by an independent third party. The m-of-n design treats Validators as Byzantine-tolerant peers, not as trusted authorities.

Validator accountability is enforced through two mechanisms whose details appear in Section 8.4:

1. **Quorum.** No single Validator can cause finalization on its own; the m-of-n threshold ensures that a minimum of `threshold` distinct Validators must independently agree. The `threshold` value is a deployment parameter; production deployments SHOULD select `threshold >= ceil(2n/3)` for Byzantine fault tolerance, where `n` is the size of the active Validator set.

2. **Slashing.** A Validator proven to have voted for a fraudulent batch loses `VALIDATOR_ROLE` and has the off-chain evidence hash recorded on-chain. A Validator that has been slashed for a prior epoch retains the vote it cast before the slash — historical votes are durable to preserve the audit trail.

The Validator role is distinct from the Attester (the on-device measurer + signer) and from the Verifier (the relying-party-side software): the Attester proves a measurement was taken on certified hardware; the Validator proves a quorum of independent parties agree the measurement appeared in a legitimate batch; the Verifier checks both layers when consuming an attestation.

## 4. Attestation Token Format

Attestation tokens are encoded in CBOR [RFC8949]. The token is a CBOR map with the claim set defined below. The serialization MUST use Canonical CBOR rules (deterministic encoding) so that signature inputs are unambiguous.

### 4.1 Claim set

| Label | Claim | Type | Required | Description |
|-------|-------|------|----------|-------------|
| 1 | `iss` | bstr | MUST | Device identifier — the 9-byte serial number of the secure element. |
| 2 | `iat` | uint | MUST | Issued-at timestamp — Unix seconds, UTC. |
| 3 | `wh` | uint | MUST | Energy delta in watt-hours since the previous attestation from the same device. |
| 4 | `seq` | uint | MUST | Per-device monotonic sequence number, starting at 1 and incremented for each emitted attestation. |
| 5 | `prev` | bstr / nil | MUST | Hash of the previous attestation token from the same device. SHALL be CBOR `nil` for the first attestation (`seq == 1`). |
| 6 | `fwv` | tstr | SHOULD | Firmware version string, e.g., `"noethrion-0.1.0"`. |
| 7 | `mdl` | tstr | SHOULD | Device model identifier. |
| 8 | `cfg` | bstr | MAY | Hash of the device configuration relevant to measurement integrity. |
| 9 | `sig` | bstr | MUST | ECDSA P-256 signature; see Section 5. |

Labels 1–8 correspond to a sub-map; the signature in label 9 is computed over the canonical CBOR encoding of that sub-map.

### 4.2 Mapping to EAT

The claim set above is intentionally compatible with the Entity Attestation Token (EAT) format defined in [RFC9711]. Implementations MAY choose to additionally emit a fully EAT-conformant variant by mapping `iss`, `iat`, `seq` to their CWT-registered claim numbers. A formal EAT profile for energy attestation will be specified in a follow-up document.

## 5. Signature Scheme

This document specifies a single signature algorithm for v0.1: ECDSA over the NIST P-256 curve (secp256r1) with SHA-256, denoted `ES256` in [RFC8152].

### 5.1 Rationale

P-256 is selected because:

1. It is the curve natively supported by widely available secure elements suitable for low-cost meter integration, including parts certified to Common Criteria EAL5+ (an example part family is documented in the reference firmware that accompanies this document).
2. It is broadly understood, has mature implementations, and is acceptable to relying parties whose internal cryptographic policies typically permit NIST curves.
3. Performance on constrained microcontrollers is sufficient for the protocol's per-minute signing cadence.

### 5.2 Post-quantum migration

It is acknowledged that P-256 is not post-quantum secure. A migration path to a post-quantum signature scheme — anticipated to be ML-DSA (CRYSTALS-Dilithium) once finalized in [FIPS204] — is part of the protocol's long-term plan. The token format reserves room for an `alg` claim and a versioned key identifier to enable in-place algorithm rotation without breaking historical verifiability.

A future revision of this document SHALL specify the migration procedure, including dual-signing transitions and the policy under which historical P-256 attestations remain verifiable.

## 6. Merkle Aggregation and Settlement

### 6.1 Off-chain aggregation

Attestation tokens are aggregated off-chain into Merkle trees. Each tree contains up to 2^16 (65,536) leaves, where each leaf is the SHA-256 hash of one canonically-encoded attestation token.

Interior nodes are computed with a commutative sorted-pair construction:

```text
parent = keccak256(min(a, b) || max(a, b))
```

where `a` and `b` are the two 32-byte child hashes and `min`/`max` denote lexicographic byte-wise ordering. Sorting each pair before hashing makes the construction order-independent: an inclusion proof carries only the sibling hashes, with no left/right position flags. This is exactly the construction implemented by the OpenZeppelin `MerkleProof` library used by the on-chain reference contract and by the reference off-chain Verifier tooling. Off-chain builders MUST use this pair hash for any tree whose root is committed on-chain.

**Note on leaf domain separation.** This construction deliberately omits the per-level domain-separation prefixes (`0x00` for leaves, `0x01` for interior nodes) defined by [RFC6962]. The second-preimage class those prefixes guard against — reinterpreting an interior node as a leaf, or vice versa — is structurally closed here by preimage length: an interior-node preimage is exactly 64 bytes (two concatenated 32-byte hashes), whereas leaf preimages are never 64 bytes. The on-chain claim-record leaf (Section 6.3.1) hashes a 160-byte `abi.encode` payload, and the attestation-evidence leaf hashes a canonical CBOR token, which is substantially longer than 64 bytes for any token carrying the required claims of Section 4.1 (and additionally uses a different hash function, SHA-256, than the keccak256 node hash). [RFC6962] informed the design of this layer and is listed as an Informative reference.

A batch is identified by a monotonically increasing epoch number. The aggregator MAY be operated by the device owner, by a service provider, or by the Noethrion Foundation reference implementation; the choice does not affect verifiability.

### 6.2 On-chain commitment

For each batch, the Merkle root is committed to a public EVM-compatible Layer 2 settlement network through a reference smart contract (the "Attester" contract — note: name reuses the RATS term for unrelated reasons; see implementation guide for disambiguation). The on-chain commitment record SHALL include, at minimum:

- The epoch number;
- The Merkle root (32 bytes);
- The total watt-hour sum claimed in the batch (for cross-check against grid-level dispatch records);
- The proposing validator's address (and, via separate `BatchVoted` events, the addresses of all validators who voted to reach quorum);
- The block timestamp at submission;
- The quorum threshold value active at the moment of submission (`thresholdAtPropose`). Snapshotting this at submission rather than reading the live storage at finalization ensures a subsequent admin change to the global `threshold` cannot retroactively pass or block this specific batch;
- The challenge-window value active at the moment of submission (`challengeWindowAtPropose`). Snapshotting prevents retroactive shrink (which would let an admin finalize batches early) and retroactive extension (which would freeze finalization of legitimately-voted batches).

The two snapshot fields close the symmetric retroactive-shift class of admin abuses; in the v0.2 reference contract both values fit in `uint64` (lossless under admin parameter validation).

A challenge window (configurable; default one hour) follows submission. In the v0.2 reference contract the fraud-proof path during this window is off-chain: any party MAY report evidence of a fraudulent batch to the contract operators and validators, who can respond through the on-chain `pause` mechanism (blocking finalization) and admin-triggered slashing (Section 8.4). A dedicated on-chain challenge entry point — allowing any party to publish a fraud proof directly on-chain — is deferred to the v0.3 protocol extension, together with fraud-proof-verified slashing. After the challenge window expires without the batch being rejected, the batch is finalized; finalization is irreversible.

### 6.3 Verification path

A Verifier resolves a single attestation as follows:

1. Receive the candidate attestation token and a Merkle inclusion proof (siblings along the tree path).
2. Compute the SHA-256 leaf hash from the canonical CBOR encoding.
3. Apply the inclusion proof to derive the candidate Merkle root.
4. Look up the on-chain commitment for the corresponding epoch.
5. Confirm the candidate root equals the committed root.
6. Confirm the batch is finalized (i.e., the challenge window has elapsed without successful challenge).
7. Validate the ECDSA signature against the **device Attester's** endorsed public key — the secure-element-bound key from Section 3.1, not the on-chain Attester contract from Section 6.2.

All seven steps MUST succeed for the attestation to be accepted.

#### 6.3.1 Note on the two-layer leaf encoding

The Merkle tree described in Section 6.1 — leaves = SHA-256 of canonically-encoded attestation tokens — is the **attestation-evidence layer**. It proves that a particular signed measurement was included in a committed batch.

The on-chain `claim()` function in the v0.2 reference contract enforces a **claim-record layer**: each on-chain leaf is `keccak256(abi.encode(block.chainid, address(attester), beneficiary, amount, epoch))`, identifying a specific redemption (which address gets how many NOET against which epoch) bound to a specific Attester instance on a specific chain. The first two fields act as a domain separator so a Merkle tree built for one Attester cannot be replayed against a fork or sibling deployment. The two layers are related but not identical: each claim record aggregates one or more attestation tokens whose summed kWh underwrites the redemption amount.

A future spec revision will document the aggregation function from attestation-tokens to claim-records explicitly. For v0.2, off-chain builders MUST produce claim-record trees whose leaves match the contract's encoding exactly — including the chain-id and attester-address domain separator; the attestation-evidence tree is verified separately by the off-chain Verifier path above and is not yet referenced on-chain.

## 7. Endorsement and Verification

### 7.1 Public key registry

Endorsed device public keys are recorded in a registry. The registry MAY be:

- **On-chain**, as a smart-contract mapping from device serial number to public key and endorsement metadata, with role-based mutation rights (Endorsers only). This is the reference deployment.
- **Off-chain**, distributed via signed JSON files at well-known URLs maintained by Endorsers.
- **Hybrid**, with on-chain anchors and off-chain bulk distribution.

The choice is operational and does not affect the verification semantics: a Verifier MUST be able to obtain a device's endorsed public key, traceable to an Endorser whose own key is verifiable.

### 7.2 Endorser revocation

An Endorser MAY revoke an endorsement (e.g., on discovery of a compromised provisioning batch). Revocations SHALL be timestamped; a Verifier evaluating an attestation MUST consider revocations issued before the attestation's `iat` timestamp.

### 7.3 Device-level revocation

A device's endorsement MAY be revoked individually (e.g., on suspicion of physical tampering reported through the protocol's challenge mechanism). Attestations from a revoked device with `iat` after the revocation timestamp MUST be rejected.

## 8. Threat Model

The following adversaries are explicitly considered.

### 8.1 Compromised host MCU

The host microcontroller adjacent to the secure element may be compromised. Because the signing key is generated on-chip and never leaves the secure element, a compromised host can lie about *what* to sign but cannot forge signatures from the device's public key.

The protocol mitigates this through Reference Values (firmware hash, configuration hash) included in the attestation claims. A Relying Party that knows the expected Reference Values can detect a tampered host.

### 8.2 Physical tampering

The meter or its sealing may be physically tampered with to inject false readings. The protocol does not by itself detect physical tampering of the upstream meter; detection relies on the existing physical-seal and audit procedures of revenue-grade metering, which predate this protocol and are out of scope.

The protocol DOES detect substitution of one secure element for another (the device serial number changes, and the new public key has no endorsement chain).

### 8.3 Secure-element key extraction

Extraction of the signing key from a Common Criteria EAL5+ secure element is currently considered infeasible against the design assumptions of state-of-the-art parts. If such an extraction becomes feasible, the affected device family's endorsements SHALL be revoked. The protocol's per-device hash chain (claim `prev`) limits the value of an extracted key for back-dating, because all historical attestations are anchored on-chain.

### 8.4 Validator collusion

A validator could withhold attestations or propose a batch with a Merkle root not corresponding to the claimed leaves. Three mechanisms address this in combination:

1. **m-of-n threshold quorum.** Finalization requires `threshold` distinct validator votes through the `proposeBatch` + `voteBatch` + `finalizeBatch` sequence. A single party can no longer cause a batch to be finalized; `threshold` MUST be selected such that coalition cost exceeds expected fraud value (typical analogous systems use `threshold = ceil(2n/3)` for Byzantine fault tolerance).
2. **Challenge window.** Independent of the threshold mechanism: between submission and earliest finalization, any party MAY report evidence of fraud. In v0.2 this path is off-chain — evidence is reported to operators and validators, who block finalization via `pause` and apply slashing; an on-chain challenge entry point is deferred to v0.3 (Section 6.2). A batch successfully challenged within the window is never finalized.
3. **Slashing.** Validators proven to have voted for fraudulent batches MAY be slashed — `VALIDATOR_ROLE` revoked, off-chain evidence hash recorded on-chain. v0.2 reference contract implements admin-triggered slashing; on-chain fraud-proof verification feeding slashing automatically is deferred to a future revision.

A coalition of `threshold` validators colluding within the challenge window can still finalize a fraudulent batch. This is the residual risk; it shrinks but does not disappear with the threshold mechanism. Production deployments SHOULD treat the challenge-window fraud-proof path as load-bearing.

### 8.5 Replay attacks

The combination of the per-device monotonic `seq` claim and the previous-attestation hash chain (`prev`) prevents replay of an old attestation as a new one. A Verifier that observes a `seq` value not strictly greater than the highest previously observed for the same device MUST reject the attestation.

### 8.6 Side-channel observation

Side-channel attacks against the secure element (power analysis, electromagnetic, fault injection) are mitigated by the Common Criteria certification regime governing the part. Operators SHOULD follow vendor guidance on physical deployment to reduce exposure.

## 9. Privacy Considerations

The protocol produces a public, durable record of per-device energy generation. This has direct privacy implications, particularly for small-scale producers (e.g., residential rooftop solar).

### 9.1 Inferences from attestations

A continuous record of per-device generation timestamps can be correlated with consumption patterns to infer the occupancy and behavior of a household. Aggregation and timestamp rounding mitigate but do not eliminate this risk.

### 9.2 Mitigations

- **Timestamp rounding.** Producers MAY round `iat` to a coarser resolution (e.g., 10-minute buckets) at the cost of reduced verification granularity.
- **Batch padding.** Aggregators SHOULD pad batches with dummy leaves so that small-scale producers' contribution count is not distinguishable.
- **Optional zero-knowledge extensions.** A future revision will specify an optional zk-friendly attestation variant in which the per-device identifier is replaced by a commitment, with selective-disclosure proofs available to authorized auditors.

### 9.3 Right to opt out

Participation in the protocol is, by design, voluntary. Operators are not required to publish attestations; the protocol's value derives from voluntary adoption by parties that wish to be cryptographically credible.

## 10. Security Considerations

In addition to the threat model in Section 8, implementers are advised of the following.

- **Time source integrity.** The `iat` timestamp depends on the device's local clock. Implementations MUST authenticate the time source (e.g., NTP with cryptographic verification, or GNSS-based time) to prevent clock-manipulation attacks.
- **Key provisioning.** Endorsement integrity depends on a trustworthy provisioning ceremony, in which the device's public key is read from the secure element under chain-of-custody guarantees. Implementations SHOULD use vendor-provided pre-provisioning programs where available.
- **Smart-contract risk.** The on-chain commitment contract is a security-critical component. Implementations SHOULD subject it to independent audit prior to production deployment and SHOULD support upgradability only via a transparent governance process.
- **Settlement-layer reliance.** The protocol depends on the liveness and integrity of the chosen settlement layer. Operators SHOULD evaluate the settlement layer's security model, including its consensus assumptions and its fault-recovery procedures.

## 11. IANA Considerations

This document requests the registration of the following media type:

- **Type name:** application
- **Subtype name:** noethrion+cbor
- **Required parameters:** none
- **Optional parameters:** profile (a URI identifying the attestation profile in use)
- **Encoding considerations:** binary
- **Security considerations:** see Section 10 of this document.
- **Interoperability considerations:** see Section 4.
- **Published specification:** this document.
- **Applications that use this media type:** Noethrion attestation token producers and consumers.
- **Author/Change controller:** IETF (with the Noethrion Foundation as designated expert through the document lifecycle).

Future revisions of this document may request additional CBOR tag allocations and CoAP profile registrations.

## 12. References

### 12.1 Normative

- **[RFC2119]** Bradner, S., "Key words for use in RFCs to Indicate Requirement Levels," BCP 14, RFC 2119, DOI 10.17487/RFC2119, March 1997.
- **[RFC8152]** Schaad, J., "CBOR Object Signing and Encryption (COSE)," RFC 8152, DOI 10.17487/RFC8152, July 2017.
- **[RFC8174]** Leiba, B., "Ambiguity of Uppercase vs Lowercase in RFC 2119 Key Words," BCP 14, RFC 8174, DOI 10.17487/RFC8174, May 2017.
- **[RFC8949]** Bormann, C. and P. Hoffman, "Concise Binary Object Representation (CBOR)," STD 94, RFC 8949, DOI 10.17487/RFC8949, December 2020.
- **[RFC9334]** Birkholz, H., Thaler, D., Richardson, M., Smith, N., and W. Pan, "Remote ATtestation procedureS (RATS) Architecture," RFC 9334, DOI 10.17487/RFC9334, January 2023.
- **[RFC9711]** Lundblade, L., Mandyam, G., O'Donoghue, J., and C. Wallace, "The Entity Attestation Token (EAT)," RFC 9711, DOI 10.17487/RFC9711, December 2024.

### 12.2 Informative

- **[FIPS204]** National Institute of Standards and Technology, "Module-Lattice-Based Digital Signature Standard," FIPS 204, August 2024.
- **[CBAM]** European Commission, "Carbon Border Adjustment Mechanism," Regulation (EU) 2023/956, May 2023.
- **[RFC6962]** Laurie, B., Langley, A., and E. Kasper, "Certificate Transparency," RFC 6962, DOI 10.17487/RFC6962, June 2013. *Design inspiration for the Merkle aggregation layer; the construction actually used differs — see Section 6.1.*

### 12.3 Reference implementation

A reference implementation of the Attester (firmware) and Verifier (smart contract + off-chain library) is available at the Noethrion project repository.

## Authors' Addresses

```
Aleksey Chursin (editor)
Noethrion Foundation
Email: team@noethrion.com
URI:   https://noethrion.com
```

---

*This document is a working draft and is not, at the time of publication, a formal Internet-Draft on the IETF datatracker. Submission to the RATS Working Group is intended after one further iteration based on public review.*
