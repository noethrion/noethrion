# Hardware vendor evaluation matrix

Comparison of the four secure-element families called out across the Noethrion codebase. Doubles as a procurement reference for first reference clients and as the candidate list for the v0.2 "approved hardware" specification work.

The protocol is **vendor-neutral by design**. This document evaluates candidates against a uniform criteria set so a relying party — or the Foundation's eventual certification authority — can make an informed choice. No single part is required by the spec.

---

## Comparison table

| Criterion | Microchip ATECC608B | Infineon OPTIGA Trust M (SLS32AIA) | NXP EdgeLock SE050 | NXP A71CH |
|-----------|---------------------|------------------------------------|--------------------|-----------|
| Certification | CC EAL5+ (variant-dependent) | CC EAL6+ | CC EAL6+ | CC EAL6+ |
| Curves supported | NIST P-256 only | NIST P-256, P-384, RSA-2048, RSA-3072, RSA-4096 | NIST P-256, P-384, P-521, secp256k1, Ed25519, RSA up to 4096, ECDH | NIST P-256 only |
| Symmetric primitives | AES-128, AES-256, SHA-256, HMAC, KDF | AES-128, AES-256, SHA-256/384, HMAC | AES, DES, SHA-1/256/512, HMAC | AES-128, SHA-256 |
| On-die key generation | Yes (per slot) | Yes (per slot) | Yes (per slot) | Yes (limited slots) |
| Key extraction | Infeasible by design | Infeasible by design | Infeasible by design | Infeasible by design |
| Default I²C address | `0x60` (fresh) / `0x6A` (Trust&Go pre-provisioned) | `0x30` | `0x48` | `0x48` |
| Supply interface | I²C, SWI (single-wire) | I²C | I²C, SPI | I²C |
| Supply voltage | 2.0–5.5 V | 1.62–5.5 V | 1.62–5.5 V | 2.5–5.5 V |
| MOQ (Mouser / DigiKey direct) | 1 unit (sample), 1k reel | 1 unit, 3k reel | 1 unit, 4.5k reel | 1 unit, 4.5k reel |
| Approximate price at 1 | $1.50–2.50 | $3.00–5.00 | $3.50–6.00 | $2.00–4.00 |
| Approximate price at 1,000 | $0.85–1.10 | $2.00–3.00 | $2.50–4.00 | $1.20–1.80 |
| Approximate price at 10,000 | $0.55–0.85 | $1.50–2.50 | $1.80–3.00 | $0.90–1.40 |
| Package availability | SOIC-8, UDFN-8, contact-mounting | TSSOP-16, USON-10, DSC-1 | HVQFN-32, HWQFN-20 | HVSON-8, HVQFN-32 |
| Pre-provisioning programs | Trust&Go, TrustFLEX, TrustCUSTOM | Trust X commercial provisioning | EdgeLock 2GO IoT provisioning | (limited; SE050 is the successor) |
| Library / SDK | `cryptoauthlib` (C, open-source, multi-platform) | `OPTIGA Trust M Host Library` (C, open-source) | `Plug & Trust Middleware` (C/C++, open-source) | `A71CH Host Library` (legacy) |
| Arduino / ESP32 ecosystem | Excellent (`cryptoauthlib` + community wrappers) | Good (vendor port for ESP32) | Reasonable (vendor port, more complex stack) | Acceptable (legacy support) |
| Datasheet (public) | `microchip.com/en-us/product/ATECC608B` | `infineon.com/optiga-trust-m` | `nxp.com/products/SE050` | `nxp.com/products/A71CH` |
| Lifecycle status | Active production | Active production | Active production | Mature; SE050 is the recommended successor for new designs |

---

## Recommendation by use case

### For the v0.1 reference firmware (ESP32 + low-cost meter)

**Microchip ATECC608B** is the right default. The criteria that push it ahead at this stage:
- Lowest BOM at the price points (~$0.55 at 10k vs >$1 for OPTIGA Trust M).
- Best community + ESP32 + Arduino ecosystem maturity.
- Provisioning programs (Trust&Go / TrustFLEX) are mature, well-documented, and reduce factory-floor friction.
- Single-curve support (P-256 only) matches the v0.1 protocol — no unused crypto surface area.

The reference firmware in `firmware/` targets this family.

### For higher-assurance certification customers

**Infineon OPTIGA Trust M** when the relying-party context demands CC EAL6+ assurance and the BOM uplift (≈$1 per device) is acceptable. The wider crypto suite is mostly unused by the protocol but signals headroom for future post-quantum profile work.

### For multi-curve / Ed25519 / secp256k1 integrators

**NXP EdgeLock SE050** is the only candidate that supports the full curve spread today. Relevant only if a downstream relying party needs to multi-sign attestations with non-P-256 keys for a parallel system. Not the default; cost and stack complexity push it back unless that specific need exists.

### Not recommended for new designs

**NXP A71CH** — included for historical reference; new designs should use SE050. The A71CH remains in field deployments and existing customer integrations.

---

## Known gotchas

### Microchip ATECC608B
- **Config zone lock is irreversible.** A misconfigured part is a brick. Use Microchip's official provisioning scripts and verify against a test board before locking a production batch.
- **Two address variants in shipping** — the fresh-from-fab default is `0x60`, but `ATECC608B-MAHDA-T` (Trust&Go pre-provisioned) ships at `0x6A`. Code must probe both.
- **Three-counter limit per slot** for monotonic counter usage; do not confuse with key-use counters.

### Infineon OPTIGA Trust M
- **More complex application protocol** (APDU-based, command-and-response framing) than the ATECC. The vendor library handles it, but custom integrations need more glue code.
- **TSSOP-16 / USON-10 packages** require slightly more PCB area than ATECC's SOIC-8.

### NXP EdgeLock SE050
- **`Plug & Trust Middleware` stack is significant** (~150 KB code on a microcontroller). Constrained environments need careful selection of the feature subset.
- **HVQFN-32 footprint** is denser than the others; QFN soldering at hobbyist scale is harder.
- **EdgeLock 2GO IoT provisioning** is cloud-tied — air-gapped factory provisioning needs careful setup.

### NXP A71CH
- **Lifecycle status** — Active production but SE050 is the supported successor. New designs should default to SE050 to avoid a forced migration later.

---

## Procurement notes

### Sample quantities (1–10)
Direct from **Mouser, DigiKey, Arrow, Avnet, Farnell**. Expect 2–5 business day delivery in US/EU; emerging-market delivery may need re-routing.

### Pilot quantities (100–1,000)
Most reliably through **authorized distributors** (above) under standard commercial terms. Manufacturer-direct (Microchip Direct, Infineon Direct, NXP Direct) becomes available around 1k.

### Production quantities (10k+)
**Direct from manufacturer**, with custom pre-provisioning programs typically integrated at this scale. Provisioning takes 2–4 weeks beyond standard lead times.

### Avoid
- Greymarket / consolidator sources for any quantity. Secure-element parts that have transited unknown supply chains have an elevated risk of pre-configuration with attacker-controlled keys. This is the single highest-leverage attack on the protocol and the easiest to defend against by **buying through authorized channels only**.

---

## How this list evolves

The matrix above is **informational for v0.1**. For v0.2, the Foundation's certification authority work will produce a formal "approved hardware" list, which will be a subset of the candidates here plus any additions the federation accepts. Inclusion in the v0.2 list will require:

- Independent verification of CC EAL certification
- Per-batch endorsement procedure documented and replicable
- Vendor commitment to a multi-year supply horizon
- Public, auditable provisioning programs

Vendor additions can be proposed by anyone via Pull Request against this file. Removals require evidence (vendor end-of-life notification, security advisory, or formal certification revocation).

---

## Cross-references

- [`firmware/README.md`](../firmware/README.md) — reference firmware targeting ATECC608B
- [`spec/noethrion-attestation-v0.1.md`](../spec/noethrion-attestation-v0.1.md) Section 7 — Endorsement and Verification (registry layer)
- [`docs/adr/ADR-001-signature-curve-p256.md`](adr/ADR-001-signature-curve-p256.md) — why P-256 (affects which secure elements qualify)
- [`docs/adr/ADR-002-hardware-root-of-trust.md`](adr/ADR-002-hardware-root-of-trust.md) — why hardware (frames the requirement)
- [`THREAT_MODEL.md`](../THREAT_MODEL.md) Sections A3, A6 — supply-chain and side-channel adversaries
