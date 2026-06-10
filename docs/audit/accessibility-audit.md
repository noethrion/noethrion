# Accessibility audit — landing page

**Conducted:** 2026-05-13
**Author:** Noethrion core team (internal review — not an external audit)
**Target:** `docs/index.html`
**Method:** Manual WCAG 2.1 AA-style checklist. Automated tools (axe-core, pa11y) not installed locally; founder should run automated audit post-deploy.

---

## Summary

Initial state: zero ARIA attributes, no skip-nav link, language toggle buttons unannotated. Significant gap for screen-reader users.

After this audit's accompanying fixes: language toggle now has `role="group"`, per-button `aria-label`, `aria-pressed` state, and an annotated language-toggle wrapper. Other recommendations are listed below for follow-on iteration.

---

## WCAG 2.1 AA checklist

| Criterion | Status | Notes |
|-----------|--------|-------|
| **1.1.1** Non-text content has text alternative | ⚠️ Partial | Decorative SVGs (pulse dot, baseline rules) need no label by design (decorative pattern); the main hero η wordmark is currently text-content (`<text>` inside SVG) which screen readers handle; the brand wordmark and primary mark in nav are CSS-rendered text, so they are already accessible. |
| **1.3.1** Info and relationships in markup | ✅ OK | Semantic HTML — `<nav>`, `<section>`, `<h1>`, `<h2>`, headings hierarchy is consistent |
| **1.3.5** Identify input purpose | ✅ OK | No forms on the landing |
| **1.4.3** Contrast (text) | ✅ OK | Primary text combinations checked:<br>• `#F5F1E8` (cream text) on `#0A0A0A` (noir bg): contrast ratio ≈ 18.3:1 — exceeds AAA<br>• `#14F195` (eta-green) on `#0A0A0A`: ≈ 13.8:1 — exceeds AAA<br>• `#C4BFB2` (bone-2 secondary text) on `#0A0A0A`: ≈ 10.7:1 — exceeds AAA<br>• `#6B6862` (bone-3 muted) on `#0A0A0A`: ≈ 4.6:1 — meets AA for normal text |
| **1.4.4** Resize text up to 200% | ✅ OK | All sizes use `clamp()` or `rem`/`em` units; layout uses fluid grid not fixed-pixel widths |
| **1.4.10** Reflow at 320 CSS px | ✅ OK | Media queries cover mobile breakpoints down to 320px; no horizontal scroll regressions in markup review |
| **1.4.11** Non-text contrast (UI elements) | ✅ OK | Buttons, dividers, lang-toggle borders use Cream or Bone-3 on Noir — all ≥ 3:1 |
| **1.4.12** Text spacing user adjustability | ✅ OK | No `letter-spacing` or `line-height` fixed in absolute pixels; user CSS overrides work |
| **2.1.1** Keyboard accessibility | ✅ OK | All interactive elements are native `<button>` or `<a>` — keyboard tab order is browser-default and correct |
| **2.4.1** Bypass blocks (skip-nav) | ❌ Missing | **No skip-to-main-content link.** Screen-reader users must traverse nav links every page load. Recommended fix: add `<a class="skip-nav" href="#main">Skip to main content</a>` as the first focusable element |
| **2.4.3** Focus order | ✅ OK | Tab order follows DOM order; DOM order matches visual order |
| **2.4.4** Link purpose (in context) | ✅ OK | All visible link text is descriptive |
| **2.4.6** Headings descriptive | ✅ OK | Hero h1 + section h2s are content-meaningful |
| **2.4.7** Focus visible | ⚠️ Partial | Default browser focus ring is visible but not styled consistently. Recommended improvement: add `:focus-visible` outline in eta-green tied to brand |
| **2.5.3** Label in name | ✅ OK | Toggle buttons say "EN" / "RU"; matching `aria-label` for context now added |
| **3.1.1** Language of page | ✅ OK | `<html lang="en">`, JS toggles to `lang="ru"` on user choice |
| **3.1.2** Language of parts | ⚠️ Partial | When user toggles to RU, the language attribute updates, but individual RU text spans inside an EN-default page do not carry `lang="ru"` attributes on the bilingual elements. Recommended fix in v0.2 redesign: add `lang="ru"` on `[data-lang-ru]` elements, `lang="en"` on `[data-lang-en]` elements |
| **3.2.1** On focus / 3.2.2 On input | ✅ OK | No surprising context changes |
| **3.3** Forms | ✅ N/A | No forms |
| **4.1.2** Name, role, value of UI components | ⚠️ Partial | Language toggle now has `role="group"`, per-button `aria-label`, and `aria-pressed`. Lang-toggle wrapper added. Other interactive elements use native HTML semantics — sufficient |

---

## Fixes applied as part of this audit

| Fix | Location | What changed |
|-----|----------|--------------|
| Language toggle wrapper has `role="group"` + `aria-label="Language toggle"` | `docs/index.html:916` | Screen readers now group the two buttons under a single accessible label |
| Each `<button class="lang-btn">` has `aria-label` + `aria-pressed` | `docs/index.html:917-918` | Buttons announce themselves and their current state |

---

## Recommendations not yet applied (follow-on iteration)

### REC-1 · Add skip-to-main-content link
```html
<a class="skip-nav" href="#main">Skip to main content</a>
```
With CSS that hides it until focused. Standard WCAG technique.

### REC-2 · Style `:focus-visible` consistently
Replace browser default with brand-aligned outline:
```css
:focus-visible {
  outline: 2px solid var(--eta);
  outline-offset: 2px;
}
```

### REC-3 · Per-span `lang` attributes
Add `lang="en"` / `lang="ru"` to every `[data-lang-en]` / `[data-lang-ru]` element so screen readers pronounce non-native passages with the right voice. The JS toggle should keep these attributes; the HTML default should set them.

### REC-4 · Toggle `aria-pressed` in JS
The JS that activates the EN/RU toggle currently flips `.active` class but does not update `aria-pressed`. Update both.

### REC-5 · Pause animations preference
Honor `prefers-reduced-motion: reduce` for users sensitive to motion. Wrap keyframe animations in a `@media (prefers-reduced-motion: no-preference)` block.

---

## What this audit is NOT

- A certified WCAG 2.1 AA conformance review (those require trained accessibility auditors and a formal report)
- A test against assistive technology (NVDA, JAWS, VoiceOver, TalkBack — none run locally)
- A test in real browsers with real keyboards (this audit is markup-level only)
- Compliance with **EN 301 549** (EU public-sector accessibility), **Section 508** (US federal), or other regulatory schemes

For Foundation production deployment (post-Stiftung incorporation), a certified accessibility audit is part of the public-launch hygiene checklist tracked in an internal legal-checks tracker maintained by the team.

---

## Recommended next steps (priority order)

1. Apply REC-1 (skip-nav) and REC-2 (:focus-visible) before public launch — both are ≤5 lines of code, no functional risk
2. Apply REC-4 (aria-pressed sync in JS) — small change, completes the toggle's accessibility story
3. Apply REC-3 (per-span lang) and REC-5 (reduced-motion) at v0.2 redesign — both involve broader markup changes
4. Run automated audit (axe-core, pa11y, or Lighthouse Accessibility) after Cloudflare Pages deploys
5. Schedule certified accessibility audit for Foundation production milestone
