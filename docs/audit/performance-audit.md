# Performance audit — landing page

**Conducted:** 2026-05-13
**Author:** Mel (Claude Code)
**Target:** `docs/index.html` (the page served at `noethrion.com` after Cloudflare Pages deploy)
**Method:** Manual review — Lighthouse / WebPageTest / PageSpeed Insights not installed locally; founder is expected to run an automated audit post-deploy.

---

## File-size budget

| Asset | Size | Notes |
|-------|------|-------|
| `docs/index.html` | ~45 KB raw markup + CSS + inline SVGs | Single file, no JS modules, no external CSS |
| `docs/og-image.png` | 27 KB | 1200×630 PNG for OG / Twitter cards |
| Inline noise SVG (data URI) | ~1 KB | Used for body texture |
| All fonts | externally loaded from Google Fonts CDN | Three font families (Instrument Serif, JetBrains Mono, Inter Tight) |
| **Total above-the-fold byte cost** | **~46 KB** + font fetches | |

**Verdict:** Well under any conventional landing-page budget. A 90+ Lighthouse Performance score is plausible once Cloudflare Pages serves the page over HTTP/2 with Brotli compression.

---

## Render-blocking resources

| Resource | Blocking? | Mitigation in place |
|----------|-----------|---------------------|
| `<link rel="preconnect" href="fonts.googleapis.com">` | No | Preconnect speeds up font fetch without blocking |
| `<link href="fonts.googleapis.com/css2?...">` (the font stylesheet) | Yes (CSS is render-blocking by default) | Included `&display=swap` query — fonts will not block paint; fallback font shows immediately and swaps when web font loads |
| Inline `<style>` block | Yes (parsed inline, but no extra network round-trip) | Fine — all critical CSS is inline |
| Synchronous head-script (FOUC fix) | Yes by design | ~10 lines of localStorage check; runs in <1 ms; required to prevent EN-to-RU language flash for returning RU users |

---

## Animations and reflow

- All animations use CSS `@keyframes` driven by `transform` or `opacity`. These properties **do not trigger layout reflow**, only compositor work, so animation cost on mobile is minimal.
- No `position: sticky` cascades, no `box-shadow` on animated elements, no large blurred backdrop filters except the nav backdrop-filter (cheap because it animates only `top/scroll`).

---

## Mobile responsiveness

- `<meta name="viewport" content="width=device-width, initial-scale=1.0">` present
- `@media (max-width: 768px)` rules cover the hero, nav, hero-eyebrow, abstract, and lang-toggle elements
- Hero font sizes use `clamp()` for fluid typography
- No horizontal-scroll regressions observed in markup review

---

## Privacy considerations affecting performance

- **Google Fonts external load** is documented as a P2 privacy issue in the reviewer-agent findings (Phase 5+6 sprint). Visitors' IPs are logged by Google. For an "open standard, sovereignty" landing, this is a minor ideological mismatch. **Mitigation available:** self-host the three font families via `@fontsource/*` npm packages bundled into `docs/`. **Cost:** +~150 KB initial bundle, removes external DNS lookup. **Decision:** keep external for v0.1; revisit in v0.2 if privacy framing becomes an active criticism.

---

## What is NOT measured

- **Lighthouse Performance / Accessibility / Best Practices / SEO scores** — requires Chromium + Lighthouse, neither installed locally. Founder is expected to run `npx lighthouse https://noethrion.com --view` after Cloudflare Pages secret configuration completes.
- **Core Web Vitals** — Largest Contentful Paint, Cumulative Layout Shift, Interaction to Next Paint require real-user-monitoring or synthetic browser. Run via Chrome DevTools after deploy.
- **Real-world TTFB and edge-cache hit rates** — Cloudflare Pages publishes these in its analytics tab once secrets and project are linked.

---

## Recommendations

1. **Run Lighthouse after Cloudflare Pages deploy completes.** Target: ≥90 Performance, ≥95 Accessibility, ≥95 Best Practices, ≥95 SEO. Report findings; address regressions before public launch.
2. **Consider self-hosting fonts** in v0.2 if privacy criticism arises. Currently deferred.
3. **Add a tiny inline favicon** — already done (Phase D `60297d1` inlined an SVG favicon as a data URI).
4. **Test on a real low-end Android device + Safari iOS** before broad public launch — no automation substitutes for this.

---

## Compared to typical project landings

- The page ships **45 KB** versus typical SaaS landings at 1.5-3 MB. The size advantage is intentional and serves the project's "boring infrastructure" tone.
- **One HTTP request** for HTML, three for fonts, one for og-image (only fetched by social scrapers, not by visitors). This is approximately one-tenth the resource count of a typical landing.

This page is structurally fast. The remaining performance work is mostly **measurement and confirmation**, not optimisation.
