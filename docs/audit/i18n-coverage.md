# i18n coverage audit

**Conducted:** 2026-05-13
**Author:** Mel (Claude Code)
**Method:** Per-file scan for Cyrillic content; cross-reference with the `bilingual-output` skill rule that distinguishes public-facing user docs (should be bilingual EN+RU) from technical specs (EN-only OK).
**Scope:** All Markdown and HTML files in the public repository.

---

## Bilingual coverage matrix

| File | EN | RU | Required bilingual? | Status |
|------|----|----|---------------------|--------|
| `README.md` | ✅ | ✅ | Yes — first page visitors see | OK |
| `docs/index.html` (landing) | ✅ | ✅ | Yes — public-facing | OK |
| `docs/whitepaper.html` | ✅ | ✅ | Yes — public document | OK |
| `docs/constitution.html` | ✅ | ✅ | Yes — public document | OK |
| `docs/brand-book-v0.3.html` | ✅ | ✅ | Yes — public document | OK (per memory; double-checked sample sections) |
| `QUICKSTART.md` | ✅ | ✅ | **Yes — public-facing user doc** | OK (RU section added 2026-05-13 in commit 33bab61) |
| `EXAMPLES.md` | ✅ | ✅ | **Yes — public-facing user doc** | OK (RU section added 2026-05-13 in commit 33bab61) |
| `FAQ.md` | ✅ | ✅ | **Yes — public-facing user doc** | OK (RU section added 2026-05-13 in commit 33bab61) |
| `CONTRIBUTING.md` | ✅ | ✅ | Yes | OK (per existing structure) |
| `SECURITY.md` | ✅ | ✅ (light) | Yes | OK (per existing structure) |
| `THREAT_MODEL.md` | ✅ | ❌ | Technical doc — EN OK per skill | OK (defensible) |
| `spec/noethrion-attestation-v0.1.md` | ✅ | ❌ | IETF I-D — EN only per convention | OK (RFC convention) |
| `spec/README.md` | ✅ | ❌ | Technical index — EN OK | OK |
| `docs/adr/*.md` (5 files + README) | ✅ | ❌ | Technical decisions — EN OK | OK |
| `docs/hardware-vendor-matrix.md` | ✅ | ❌ | Technical reference — EN OK | OK |
| `docs/audit/*.md` (this audit set) | ✅ | ❌ | Internal audit — EN OK | OK |
| `examples/lifecycle/*` | ✅ | ❌ | Code-adjacent docs — EN per convention | OK |
| `examples/integrators/*` | ✅ | ❌ | Code-adjacent docs — EN per convention | OK |
| `firmware/README.md` | ✅ | ❌ | Code-adjacent — EN OK | OK |
| `tools/README.md` | ✅ | ❌ | Code-adjacent — EN OK | OK |

---

## Identified gaps (require RU translation)

### GAP-1 · `QUICKSTART.md` is EN-only — ✅ CLOSED 2026-05-13
RU section added in commit `33bab61`. ~700 RU words mirroring the EN structure. Professional review pass remains tracked in an internal legal-checks tracker maintained by the team P2-3.

### GAP-2 · `EXAMPLES.md` is EN-only — ✅ CLOSED 2026-05-13
RU section added in commit `33bab61`. ~400 RU words covering the lifecycle directory overview, integrator templates, and the shared 4-step verification pattern.

### GAP-3 · `FAQ.md` is EN-only — ✅ CLOSED 2026-05-13
RU section added in commit `33bab61`. All 30 Q&A pairs translated; ~2000 RU words. Same 5 categories. Answers paraphrased for idiomatic Russian rather than mechanically translated.

---

## Decision points

### Q1 · Translate now or punt to launch + 1 week?
Trade-offs:
- **Translate now (Mel-authored):** repo is fully bilingual at launch; risk = imperfect Russian phrasing in a few places
- **Punt to launch + 1 week (professional):** higher RU quality; risk = bilingual gap visible at launch; Russian-speaking initial visitors see partial translation
- **Hybrid (Mel writes v0.1 RU now; founder commits to professional review by launch + 2 weeks):** ships at launch with full bilingual coverage; quality refined later

Recommendation: **Hybrid**. Mel ships RU sections for QUICKSTART, EXAMPLES, FAQ in the current sprint window. Professional review goes in the LEGAL_CHECKS_TODO tracker.

### Q2 · Scope creep for technical docs?
The `bilingual-output` skill explicitly carves out technical specs as EN-only. We've followed that for spec, ADRs, threat model, hardware vendor matrix. Re-reading them, this still seems right — these are reference materials for engineers and standards-body reviewers, not first-touch user docs.

Recommendation: **No scope expansion**. Technical docs stay EN-only.

---

## What is NOT measured

- **Russian phrasing quality** of existing bilingual content (README, landing, whitepaper, constitution, brand book). Current RU was Mel-authored, sufficient for v0.1 but not professionally reviewed. Tracked in the internal legal-checks tracker.
- **Other languages (Spanish, Mandarin)** mentioned in v0.2 plans across constitution and whitepaper. Not in v0.1 scope.
- **Per-string locale correctness** (date formats, number formats, RTL handling). Not relevant given Russian + English are both LTR with similar conventions.

---

## Recommended next steps

1. **Decide on Q1** (translate now / punt / hybrid) — defaults to hybrid above
2. If hybrid chosen, Mel ships RU sections for QUICKSTART / EXAMPLES / FAQ in this sprint window (next 1–2 hours)
3. Add an entry to the internal legal-checks tracker for the professional Russian review pass before public launch + 2 weeks
4. At v0.2, evaluate whether Spanish + Mandarin scope additions become realistic
