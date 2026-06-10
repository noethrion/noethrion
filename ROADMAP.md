# Roadmap

Multi-year plan for the Noethrion protocol and the Foundation that administers it. **Slow by design** — energy infrastructure outlives software fashion, so the roadmap is measured in years, not weeks. Aggressive timelines tend to create the failure modes the project is built to avoid.

This document is a **direction**, not a contract. Specific dates shift; the ordering of work does not.

---

## Where we are (2026 Q2)

| Pillar | State |
|--------|-------|
| Protocol specification | **v0.1 draft published** — IETF Internet-Draft format, RATS WG submission pending one further public-review pass |
| Smart contracts | **Beta** — `NoethrionAttester` + `NoethrionToken`, 127/127 forge tests + 25/25 Halmos symbolic proofs passing, `claim()` implemented with MerkleProof + ReentrancyGuard. Third-party audit funded via grant, pending engagement |
| Reference firmware | **Skeleton** — ESP32 + ATECC608B probe-only stub. Hardware bring-up bench pending |
| Reference tooling | **Published** — Python CLI (provision, verify, render assets) + integrator templates (Python library, Node TypeScript, Solidity consumer) |
| Foundation | **Initial Development Co. (Delaware C-Corp interim)** — transition to Swiss Stiftung targeted for 2028+ after treasury maturity threshold |
| Documentation | **Complete for v0.1** — whitepaper, constitution, brand book, spec, threat model, ADRs, hardware vendor matrix, FAQ |
| Bilingual coverage | **Complete** — EN + RU for all public-facing user documents |
| First social posts | **Drafted, ready to publish** — Twitter thread + Mirror long-form, both editorially reviewed |

---

## Phase 1 — Foundation phase (now → 2027)

**Goal:** Ship a credible v0.1, attract critical reviewers, secure first hardware vendor + first energy producer commitment to pilot.

### Q2 2026 (current)
- [ ] Public flip the repository to public (gated on founder decision)
- [ ] Cloudflare Pages secrets configured; `noethrion.com` serving the landing
- [ ] First social media posts published (Twitter thread + Mirror long-form + Day-2 Mirror RU)
- [ ] First 5–10 cold-outreach contacts sent per the templates in operational docs
- [ ] First external GitHub Discussions and issue volume

### Q3 2026
- [ ] Hardware POC bring-up bench complete — real ATECC608B signing real attestations to a local testnet
- [ ] Internet-Draft submitted to IETF RATS WG datatracker
- [ ] First external reviewer cohort engaged (≥3 substantive technical reviewers)
- [ ] First conference talk or workshop slot booked
- [ ] First grant approval (target: Gitcoin QF or EF ESP)

### Q4 2026
- [ ] Smart-contract third-party audit engaged (firm shortlist locked, kickoff scheduled)
- [ ] Multi-vendor hardware evaluation expanded to second secure-element family
- [ ] First small-scale energy producer committed to pilot (signed letter of intent or equivalent)
- [x] v0.2 reference contract — m-of-n threshold validator quorum + admin slashing (commit `0ef551f`, 2026-05-13)
- [x] v0.2 verification suite — 73 forge tests (50 unit + 1 reentrancy + 8 fuzz invariants × up to 16k sequences each) + 11 Halmos symbolic proofs + end-to-end lifecycle smoke test on CI; Attester coverage 100% lines / 98.72% statements / 95.24% branches / 100% functions; pre-audit readiness report at `docs/audit/smart-contracts-audit.md` (2026-05-13)
- [x] v0.2 production deploy model — ADR-007 (Safe 3-of-5 multi-sig + TimelockController 24h on slash + setThreshold) and `contracts/script/DeployProduction.s.sol` implementing the v0.2 interim handoff (2026-05-13)
- [ ] v0.2 specification work continues — Endorser registry governance, optional ZK privacy variant, on-chain fraud-proof verification feeding slash() automatically, formal attestation->claim-record aggregation function (the two-layer leaf-encoding bridge documented in spec §6.3.1)

### Q1–Q2 2027
- [ ] Smart-contract audit findings addressed; v1.0 contract candidate frozen
- [ ] Internet-Draft v0.2 with audit-informed changes
- [ ] First Endorser federation participant onboarded
- [ ] Foundation legal-entity transition timeline locked

---

## Phase 2 — Validation phase (2027 → 2028)

**Goal:** Reach mainnet readiness through structured pilots, certification authority onboarding, and the first wave of certified hardware.

- [ ] Mainnet v1.0 deployment on the chosen EVM-compatible Layer 2 (selection per a v0.2 criteria-based evaluation)
- [ ] 5–10 partner integrations on testnet, progressively migrating to mainnet
- [ ] First B2B partnerships through certified third-party integrators (the Foundation does not sell to enterprise directly — that is a deliberate choice, not a temporary tactic)
- [ ] Second + third smart-contract audit pass (post-deployment) on protocol governance and v1.0 changes
- [ ] First academic citations in peer-reviewed venues
- [ ] First IETF Internet-Draft revisions accepted by RATS WG
- [ ] First independent reference implementation of the verifier in a language outside our three (Python / TypeScript / Solidity)

---

## Phase 3 — Scale phase (2028 → 2031)

**Goal:** Foundation incorporation, multi-client ecosystem, founder transition out, protocol independence.

- [ ] Swiss Stiftung Foundation incorporated; Initial Development Co. self-dissolves and transfers assets to the Foundation per its charter
- [ ] First major hardware vendor integration at scale (across the smart-meter and energy-monitoring ecosystem)
- [ ] First hyperscaler-scale partnership for compute energy attestation disclosure
- [ ] 3+ independent reference clients of the protocol — the multi-client implementation goal: no single codebase should be a point of capture (see the [Constitution](docs/constitution.html))
- [ ] First post-quantum signature variant shipped (ML-DSA dual-signing on the wire, single-signature on chain — per spec Section 5.2)
- [ ] Founder transitions to advisory; protocol authority held by the Foundation
- [ ] Endorser federation diversified across ≥3 jurisdictions
- [ ] First sovereign integration (regulatory body using Noethrion attestations for CBAM / equivalent compliance verification)

---

## Phase 4 — Founder exit (2031+)

**Goal:** Operational founder departure. Protocol must be unkillable without us.

- [ ] Founder out of day-to-day governance; advisory-only role
- [ ] Foundation operates entirely on grant + treasury + member-dues income
- [ ] No single point of failure — every protocol-critical role has at least one trained backup
- [ ] First decade-anniversary review: what worked, what changed, what to write into the second decade's specifications

The shape of this phase is intentionally underspecified. We do not pretend to know how energy markets, hardware certification, or post-quantum cryptography will look in 2031.

---

## What is NOT on the roadmap

- **A Layer 1 chain.** ADR-003 records the decision permanently. We do not build, we anchor.
- **Token economic engineering** for price targeting, market-making, or insider allocation. ADR-005 records the no-token-sale posture as permanent.
- **Enterprise direct sales** by the Foundation. The [Constitution](docs/constitution.html) records that distribution is through certified third-party integrators, not Foundation-as-vendor.
- **An ICO, presale, allocation round, or airdrop** — see ADR-005.
- **A founder-led perpetuity.** Section 4 above is explicit about the founder leaving.

---

## How this document evolves

This roadmap is updated when:
- Quarter-end retros surface a meaningful shift in ordering
- A milestone is achieved (mark it `✅`, leave it in place for one cycle, then graduate it to the "where we are" section)
- A milestone is dropped (mark it `❌` with a one-line note pointing to a separate decision document or ADR)
- A new initiative meets the bar of being "in the project's plan", not just "in someone's head"

Roadmap items are aspirational and may slip. The principles in the [Constitution](docs/constitution.html) and the decisions in `docs/adr/` are not — they are the part of the project that doesn't move.

---

*η = E_useful / E_total*
