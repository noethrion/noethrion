# Noethrion threat model

Standalone, expanded threat model for the Noethrion attestation protocol. This document is **informative**; the normative reference is Section 8 of the [Internet-Draft](spec/noethrion-attestation-v0.1.md). When the two diverge, the spec is canonical.

The threat model is written from the perspective of a relying party — an entity that consumes attestations as evidence of clean-energy generation. The question being answered throughout is: **under what conditions can a relying party trust an attestation, and what are the residual risks even when those conditions hold?**

---

## 1. System under analysis

The system consists of five interacting components:

1. **Meter** — measures electricity production at a generation source. Produces measurement tuples `(kWh, timestamp, deviceID)`.
2. **Secure element** — Common Criteria EAL5+ certified chip adjacent to the meter. Generates an ECDSA P-256 keypair on-die; signs every measurement tuple with the on-die private key. Private key cannot be exported.
3. **Host MCU** — microcontroller that orchestrates measurement, signing, and transmission. Untrusted in the protocol's threat model.
4. **Aggregator + Validator Quorum** — off-chain process that batches attestations into Merkle trees; one validator proposes the root on-chain via `NoethrionAttester.proposeBatch()` and the remaining quorum members confirm via `voteBatch()`.
5. **On-chain commitment contract** — stores Merkle roots, enforces a challenge window, and exposes the `claim()` function downstream consumers use to verify individual leaves.

A sixth component — the **Endorser** — sits outside the runtime path and provides the public-key-to-device binding that relying parties consult during verification. Endorser trust is **policy**, not protocol — described in Section 7 of the I-D.

---

## 2. Adversary catalogue

We enumerate ten adversary classes. Some compose (a corrupt manufacturer is also a side-channel attacker with hardware access); we treat each in isolation for clarity.

### A1. Device operator with economic incentive to over-report

**Capability.** Owns or operates the meter; can physically access the device and its surroundings; financially rewarded for each kWh attested.

**Attack.** Reports more kWh than the meter actually produced.

**Mitigations.**
- The meter signs the measurement inside the secure element, which cannot independently verify the meter's physical sensor reading. The operator could thus, in principle, inject a false sensor reading upstream of the secure element. This **is** an attack the protocol does not by itself prevent.
- Detection relies on (a) revenue-grade physical sealing of the meter housing (an existing industry practice predating the protocol), (b) periodic audits comparing aggregated Noethrion attestations to grid-level dispatch records published by independent system operators (ERCOT, MISO, PJM, ENTSO-E equivalents), and (c) statistical anomaly detection on per-device generation patterns.

**Residual risk.** Sophisticated tampering with the physical sensor pathway between the kWh-counting element and the secure element's input is not detectable by the protocol alone. We accept this risk because the alternative — building tamper-detection into every component — is impractical at the protocol level. Endorsers are expected to require revenue-grade sealing as a precondition for endorsement.

### A2. Compromised host MCU

**Capability.** Full software control over the microcontroller that interfaces with the secure element.

**Attack.** Feeds false `(kWh, timestamp, deviceID)` tuples to the secure element for signing. The secure element signs whatever the host presents because the host is the only path through which signing requests arrive.

**Mitigations.**
- Reference Values (firmware hash, configuration hash) included as optional claims in the attestation token. A relying party that knows the expected Reference Values for a deployed device can detect firmware-level tampering.
- Per-device hash chain (`prev` claim) prevents replay of historical attestations as new ones.
- Anomaly detection on per-device patterns flags devices producing implausible values.

**Residual risk.** A relying party that does not check Reference Values is exposed to MCU compromise. The protocol enables this check; whether it is performed is operational policy.

### A3. Hardware manufacturer (supply chain)

**Capability.** Influences the secure-element provisioning process before parts ship.

**Attack.** Generates known weak keys; back-doors the random-number generator; pre-records key material before the on-die generation runs; ships parts with the manufacturer's signature on attestations the manufacturer itself constructs.

**Mitigations.**
- Common Criteria EAL5+ certification regime imposes review of the manufacturer's processes by an independent evaluation lab. This is significant but not absolute protection.
- Endorser federation — different Endorsers can endorse different manufacturer batches. A relying party that does not trust manufacturer X's process can choose to only accept devices endorsed by Endorser Y, whose policy excludes batches from X.
- Multi-vendor diversification — the protocol's Reference Values list approves multiple manufacturer families (see `docs/hardware-vendor-matrix.md`), so no single supply chain failure compromises the entire protocol.

**Residual risk.** A successful supply-chain attack at a major Endorser's certification process compromises every device that Endorser endorsed. Limiting blast radius requires the Endorser federation to be **actually federated** in practice, not just in principle.

### A4. Validator collusion

**Capability.** Holds (or coordinates the holding of) the `VALIDATOR_ROLE` on the Attester contract. In the v0.2 reference implementation, finalization requires `threshold` distinct validators voting independently — a single party no longer suffices.

**Attack.** Submits a Merkle root that does not correspond to actual attestation leaves; withholds attestations from the batch; reorders or censors specific devices.

**Mitigations (v0.2 — implemented in the current reference contract).**
- **m-of-n threshold quorum** — `proposeBatch` + `voteBatch` + `finalizeBatch` requires `threshold` distinct validator votes before a batch becomes finalizable. See ADR-006 for the design rationale.
- **Per-epoch double-vote prevention** — `voted[epoch][validator]` mapping prevents a single validator from inflating the vote count.
- **Admin-triggered slashing** — `slash(validator, evidenceHash)` revokes the validator's role and records the off-chain evidence hash on-chain. A future revision will add automatic slashing fed by on-chain fraud proofs (v0.3+ work).
- **Challenge window** — independent of the threshold mechanism. No batch can be finalized before the window elapses, giving any independent observer time to detect a fraudulent root. In v0.2 the response path is operational: detected fraud escalates to `pause()` plus `slash()` before finalization. An on-chain challenge entry point is v0.3+ work.
- All attestation leaves are also published off-chain on IPFS / equivalent so any independent observer can reconstruct the Merkle tree from the leaves and verify the submitted root.

**Residual risk (v0.2).** A coalition of `threshold` validators colluding can still finalize a fraudulent batch within the challenge window. The risk surface shrinks from "any single malicious validator" to "a Byzantine coalition", but does not disappear. Production-grade relying parties should require a threshold high enough that coalition cost exceeds expected fraud value (typical analogues use `threshold = ceil(2n/3)`), and should rely on independent re-verification during the challenge window — escalating to `pause()` + `slash()` — as the second line of defence.

### A5. Endorser issuing bad endorsements

**Capability.** Signs endorsements binding device public keys to identity metadata.

**Attack.** Issues endorsements for keys the Endorser does not actually control or has not verified; endorses keys controlled by colluding adversaries.

**Mitigations.**
- Endorser's own public key must be verifiable through a higher-trust mechanism (X.509 chain, well-known DNS record, on-chain registry with role-based access).
- Endorser revocation procedure (Section 7.2 of the I-D).
- Relying parties choose which Endorsers to trust; there is no protocol-mandated single root of endorsement trust.

**Residual risk.** An Endorser that endorses widely without rigorous process can flood the network with low-quality attestations. Reputation systems for Endorsers will need to emerge. The protocol does not prescribe one.

### A6. Side-channel attacker (key extraction)

**Capability.** Has physical access to a secure element and the resources to perform power analysis, electromagnetic emission analysis, or fault injection on it.

**Attack.** Extracts the private signing key from the secure element. Resigns arbitrary attestations against the device's public key.

**Mitigations.**
- Common Criteria EAL5+ certification includes side-channel resistance evaluation against state-of-the-art lab attacks.
- Estimated cost of successful extraction against modern parts is **disproportionate to the value of falsifying generation reports** for any reasonable economic actor.
- Per-device hash chain (`prev`) limits the value of an extracted key — historical attestations are already anchored on-chain and cannot be retroactively replaced.

**Residual risk.** A nation-state actor with billion-dollar resources is in principle capable of extraction against any specific part. The protocol does not defend against such actors and does not claim to. For attestations whose economic value approaches that threshold, additional defenses (per-claim ZK proofs of liveness, etc.) would be needed.

### A7. Replay / freshness attacker

**Capability.** Has captured one or more historical valid attestations.

**Attack.** Replays an old attestation as new generation; replays an attestation from device A as if device B had produced it.

**Mitigations.**
- Per-device monotonic `seq` claim — Verifiers MUST reject any attestation whose `seq` is not strictly greater than the highest previously observed `seq` for the same device.
- Previous-attestation hash chain (`prev` claim) makes any out-of-order replay detectable: the `prev` value in a replayed attestation will not match the actual chain head for that device at the receiving Verifier.
- Timestamp range checks at the relying party — attestations whose `iat` is far in the past should be rejected.

**Residual risk.** Negligible if Verifiers implement the spec's MUST-level replay protections. Becomes material if a Verifier silently accepts non-monotonic `seq` values.

### A8. Privacy adversary

**Capability.** Has read access to the public attestation record.

**Attack.** Correlates per-device timestamps and `kWh` values with external data sources (occupancy patterns, utility billing leaks, weather data) to infer the behavior of small-scale producers — particularly residential solar.

**Mitigations.**
- Timestamp rounding to coarse buckets (e.g., 10-minute resolution) at producer option, with corresponding loss of verification granularity.
- Batch padding with dummy leaves so the small-scale producer's contribution count is not distinguishable from a larger batch.
- Planned zero-knowledge variant of the attestation token (Section 9.2 of the I-D) that replaces the per-device identifier with a commitment plus selective-disclosure proofs.
- Voluntary participation — small-scale producers who do not need the protocol's benefits are not required to publish attestations.

**Residual risk.** Substantial for residential producers who participate without applying mitigations. The protocol documents this directly and does not coerce disclosure.

### A9. Regulator / state-level adversary

**Capability.** Issues subpoenas, sanctions specific addresses, compels the Foundation to act against its stated principles, or attempts to seize the on-chain commitment infrastructure.

**Attack.** Forces the Foundation to censor specific attestations; demands the protocol revoke a device whose owner is politically disfavored.

**Mitigations.**
- The protocol's open-source license and the Foundation's Stiftung structure together make protocol-level censorship technically infeasible: the spec is published, the smart contract is immutable, the Endorser federation is voluntary.
- The Foundation cannot revoke attestations the protocol's deterministic emission rule has already minted. The Foundation has no `mint`/`burn` discretion.
- The Foundation can be compelled to update its own published statements; it cannot be compelled to mint new attestations contrary to the protocol.

**Residual risk.** A specific Endorser can be compelled to revoke endorsements under its jurisdiction. Relying parties depending exclusively on that Endorser would lose verification capability for affected devices. The Endorser federation is the structural answer; in practice it must be maintained as actually federated.

### A10. Network adversary on validator transactions

**Capability.** Intercepts traffic between a validator and the RPC endpoint used to call `proposeBatch()` / `voteBatch()` / `finalizeBatch()`.

**Attack.** Replays or modifies the on-chain transaction.

**Mitigations.**
- Each validator's transaction is signed by their own Ethereum private key. A network adversary cannot alter the transaction content without invalidating the signature.
- Each validator is responsible for their own transaction nonce management; replays are blocked by the EVM's built-in nonce check.

**Residual risk.** Negligible. This adversary class is largely already handled by Ethereum's transaction format.

---

## 3. Mitigations matrix

The following table summarises which protocol-level control addresses which attack. "Protocol" = the spec defines a normative MUST. "Operational" = the Endorser, the Foundation, or the relying party must implement.

| Attack | Protocol mitigation | Operational mitigation |
|--------|---------------------|------------------------|
| A1. Operator over-reports | (none — boundary issue) | Revenue-grade sealing, grid-level audit, anomaly detection |
| A2. Compromised host MCU | Reference Values in claim; prev hash chain | RV check at Verifier; firmware integrity programs |
| A3. Manufacturer supply chain | CC EAL5+ requirement; multi-vendor list | Endorser federation; supply-chain audit |
| A4. Validator collusion | m-of-n threshold quorum + challenge window + admin slashing (v0.2 shipped) | Production deployments choose threshold ≥ ceil(2n/3); v0.3+ automatic fraud-proof-fed slashing |
| A5. Bad endorsements | Endorser revocation procedure | Endorser reputation; relying-party diligence |
| A6. Side-channel key extraction | CC EAL5+; per-device hash chain limits damage | Tamper-evident physical deployment |
| A7. Replay / freshness | Monotonic `seq` MUST-reject; `prev` chain | Verifier correctly implements MUST-rejects |
| A8. Privacy correlation | Timestamp rounding option; ZK variant (v0.2) | Producer opts into mitigations; voluntary participation |
| A9. Regulator censorship | Immutable contract; deterministic emission; license | Endorser federation; jurisdictional diversity |
| A10. Network adversary | Each validator signs their own tx; EVM nonce protection | Standard transport security |

### 3.1 Implementation-level cross-reference

Each protocol-level mitigation in the table above has at least one corresponding test or fuzz invariant in the contract suite. Notable contract-implementation hardening that is *not* itself a Section-2 adversary but does materially affect whether the Section-3 mitigations hold in practice:

| Implementation property | Verified by |
|------------------------|-------------|
| Reentrancy on the mint plumbing (an attacker-controlled token cannot re-enter `claim()`) | `nonReentrant` + CEI ordering; end-to-end malicious-token security test in the contract suite |
| Pause is a hard kill switch (no mutation while paused) | Unit tests on every mutation entry point plus a fuzz invariant that pins the success-under-pause count at zero |
| Threshold churn cannot retroactively unfinalize a batch | Multi-leaf phased invariant under fuzzed threshold mutation |
| Token supply matches the sum of claimed leaves at every step | Cross-contract supply ↔ claimed-ghost invariant |

The end-to-end testing posture — coverage figures, the full invariant catalogue, the Slither configuration, accepted findings, and known limitations — is documented in [`docs/audit/smart-contracts-audit.md`](docs/audit/smart-contracts-audit.md). When that document and this one disagree about what the implementation does, the implementation's actual source is canonical and both documents should be updated in the same commit that lands the change.

---

## 4. Out-of-scope threats

The following classes of attack are explicitly **not** addressed by Noethrion v0.1. Relying parties needing protection against them must layer additional controls on top of the protocol.

- **Physical tampering of upstream sensors.** The protocol assumes revenue-grade meter integrity exists upstream of the secure element. Sensor-level tampering is a metering-industry problem, not a Noethrion problem.
- **Grid-level fraud about generation source.** The protocol does not, and cannot, verify the *source* of the electricity (solar vs nuclear vs natural gas) from the meter alone. Source attribution is an Endorser-policy question — the Endorser certifies the device's installation context.
- **Compromise of large-scale relying-party infrastructure** (the sustainability-reporting database, the carbon-accounting service). Out of scope.
- **Quantum cryptanalysis** against historical attestations. Post-quantum migration is documented (ADR-001, I-D Section 5.2) but the v0.1 spec does not provide quantum resistance.

---

## 5. Residual risk acknowledgement

The Foundation explicitly acknowledges that the protocol does not provide:

- Trust-free guarantees against operator collusion with physical sensor tampering.
- Protection against state-level adversaries with billion-dollar resources targeting specific devices.
- Privacy guarantees for residential producers who do not actively apply the documented mitigations.
- Censorship resistance for relying parties depending on a single Endorser whose jurisdiction can compel revocation.
- Automatic on-chain fraud-proof verification feeding slashing — v0.2 ships admin-triggered slashing; v0.3+ work adds the automatic path.

These are real residual risks. We document them rather than minimize them. The protocol is **infrastructure**, not magic; it shifts the cost of fraud from "trivial" to "expensive enough to be detectable and prosecutable", which is the bar that historically distinguishes working infrastructure from working theatre.

---

## 6. Reporting

Security disclosures: `security@noethrion.com` (PGP key in [SECURITY.md](SECURITY.md)).

Threat-model improvements via Pull Request against this file or against Section 8 of the [Internet-Draft](spec/noethrion-attestation-v0.1.md).

*η = E_useful / E_total*
