# `docs/audit/` — Quality & compliance audit reports

Pre-launch self-audit reports covering license compatibility, performance, accessibility, and i18n coverage. Each audit is **Mel-conducted, founder-reviewed** — none of them are substitutes for the formal legal / security / accessibility reviews that gate mainnet and post-Foundation operation.

A separate tracker for items requiring external (legal / regulatory / certified accessibility) review lives in an internal legal-checks tracker maintained by the team (internal, not in this repo).

## Reports

| Report | Coverage | Result summary |
|--------|----------|----------------|
| [`license-audit.md`](./license-audit.md) | Compatibility of every direct and transitive dependency license against the project's MIT + Apache 2.0 posture | All compatible except **one note**: cryptoauthlib carries the Microchip Software License Agreement (MSLA), which restricts use to Microchip products. Documented; not a blocker for ATECC608B-targeted firmware. |
| [`performance-audit.md`](./performance-audit.md) | Manual checklist for `docs/index.html` landing page (file size, render-blocking resources, animations, mobile responsiveness) | Single-file 45 KB landing, no JS-blocking, mobile-responsive. One privacy-adjacent improvement available (self-host Google Fonts) — recorded but not blocking. |
| [`accessibility-audit.md`](./accessibility-audit.md) | Manual WCAG 2.1 AA checklist for `docs/index.html`, brand book HTML, and other public docs | Found 0 ARIA attributes on landing — added minimal `role="img"` + `aria-label` on the η mark, skip-nav link, and document language attribute. Contrast ratios verified for primary colour combinations. |
| [`i18n-coverage.md`](./i18n-coverage.md) | EN/RU coverage matrix per the `bilingual-output` skill rule | README + landing + whitepaper + constitution + brand book bilingual. QUICKSTART, EXAMPLES, FAQ are EN-only (public-facing user docs — should be bilingual). Technical specs (Spec, ADRs, threat model, hardware vendor matrix) appropriately EN-only per skill rule. |
| [`smart-contracts-audit.md`](./smart-contracts-audit.md) | Pre-audit readiness report for `NoethrionAttester.sol` + `NoethrionToken.sol`: 73 tests (50 unit + 1 reentrancy + 8 invariants × up to 16,384 fuzz sequences). Coverage, invariants, Slither posture, open findings, accepted limitations. | 100% lines / 98.72% statements / 95.24% branches / 100% functions on the Attester · 100% across the board on the Token · 8 fuzz invariants pass under both default and CI profiles with 0 reverts · reentrancy guard verified end-to-end with a malicious-token mock. The single uncovered branch is a defensive `tokenContract == 0` check tested in isolation; accepted. **External audit still required** before any mainnet deploy. |

## What's NOT in this directory

- Formal legal opinions (securities, AML, trademark, patent FTO) — these require external counsel; gap tracker is an internal legal-checks tracker maintained by the team
- Third-party smart-contract audit — the `smart-contracts-audit.md` report above is a **self-audit**, not a substitute. External audit is funded via the EF ESP grant track and is on the launch critical path before any mainnet deploy
- Certified accessibility audit (Section 508, EN 301 549) — not pre-launch blocker; revisit after public launch and first wave of feedback
- Formal Russian translation review — current bilingual content is Mel-authored, not professionally translated; tracked in the internal legal-checks tracker

## Cadence

These reports get refreshed when:
- Dependencies change (license audit)
- Landing page redesigns (performance + accessibility)
- New public-facing doc added (i18n coverage)
- Contract surface changes, an invariant is added, or coverage drops (smart-contracts audit)

Stale reports are worse than missing reports. If the project state moves past a report, mark it stale at the top before adding new findings.
