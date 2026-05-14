# License compatibility audit

**Conducted:** 2026-05-13
**Author:** Mel (Claude Code)
**Status:** Initial · pre-launch
**Project license posture:** MIT for code, Apache 2.0 for spec text, MIT for documentation. All artifacts intended to remain license-permissive in perpetuity.

---

## Direct dependencies

### Smart contracts (`contracts/`)

| Dependency | Version | License | Compatible with MIT/Apache 2.0? | Notes |
|------------|---------|---------|--------------------------------|-------|
| `@openzeppelin/contracts` | 5.x | MIT | ✅ Yes | LICENSE file inspected — "The MIT License (MIT) · Copyright (c) 2016-2026 Zeppelin Group Ltd" |
| `forge-std` (Foundry standard library) | main | MIT OR Apache 2.0 (dual) | ✅ Yes | Dual-licensed; either path works for our posture |

### Firmware (`firmware/`)

| Dependency | Version | License | Compatible? | Notes |
|------------|---------|---------|-------------|-------|
| `cryptoauthlib` | v3.7.9 (Microchip) | **Microchip Software License Agreement (MSLA)** | ⚠️ Conditional | Permissive in form (allows redistribution in source/binary), but restricts use **to Microchip products**. Quote: "you may use the Microchip Software and any derivatives exclusively with Microchip products." Acceptable for our firmware because the firmware target is the Microchip ATECC608B. **MUST NOT** be used to claim or imply that the reference firmware works on Infineon / NXP / other vendors via cryptoauthlib. Other-vendor support requires that vendor's own host library. |
| `ArduinoJson` | ^7.1.0 | MIT | ✅ Yes | Permissive |
| Espressif Arduino framework | bundled by PlatformIO | LGPL 2.1 (FreeRTOS components) / Apache 2.0 (ESP-IDF) | ✅ Yes (LGPL is compatible for our use — we link, do not statically embed proprietary code) | Standard for ESP32 development |

### Tools (`tools/`)

| Dependency | Version | License | Compatible? | Notes |
|------------|---------|---------|-------------|-------|
| `cryptography` (Python) | 43..50 | Apache 2.0 OR BSD-3-Clause (dual) | ✅ Yes | PyCA project |
| `pycryptodome` | latest | BSD-2-Clause + Public Domain (mixed per component) | ✅ Yes | The Public Domain portions are former dome-crypto/PyCryptodome legacy; modern parts are BSD |
| `Pillow` (only used by tools/render_social_assets.py) | 12.x | MIT-CMU (HPND derivative) | ✅ Yes | Permissive |

### Integrator templates (`examples/integrators/`)

| Dependency | Version | License | Compatible? | Notes |
|------------|---------|---------|-------------|-------|
| `@noble/curves` | ^1.6.0 | MIT | ✅ Yes | Permissive, audited |
| `@noble/hashes` | ^1.5.0 | MIT | ✅ Yes | Permissive, audited |
| `typescript` (devDep only) | ^5.5.0 | Apache 2.0 | ✅ Yes | Standard permissive license |
| `@types/node` (devDep only) | ^20.14.0 | MIT | ✅ Yes | DefinitelyTyped |

### System fonts referenced in render scripts

The `tools/render_social_assets.py` script uses macOS system fonts (Georgia Italic, Helvetica, Courier New) for SVG-to-PNG rasterisation. These fonts are not redistributed — they are linked at runtime from the operating system. No license obligation attaches to the PNG output.

The landing page (`docs/index.html`) **loads Google Fonts** (Instrument Serif, JetBrains Mono, Inter Tight) at runtime via `fonts.googleapis.com`. These fonts are SIL Open Font License (OFL) 1.1 — permissive, requires only attribution in the font usage (not in the page itself).

---

## Transitive dependencies

### OpenZeppelin Contracts

OZ has its own transitive deps — primarily its `lib/forge-std` (MIT/Apache 2.0) and `lib/erc4626-tests` (none in our consumption path). No incompatibility surfaces transitively.

### `cryptoauthlib` transitive

cryptoauthlib bundles some primitives (e.g., its own BIGINT implementations) under the MSLA. No transitive third-party license conflicts identified.

---

## Findings

### F-1 · cryptoauthlib MSLA restriction · NOTE
The Microchip Software License Agreement permits redistribution but restricts use to Microchip products. This is acceptable for our reference firmware because we target ATECC608B. **Action:** add a clarifying note in `firmware/README.md` so future readers do not assume cryptoauthlib supports any-vendor use.

### F-2 · No copyleft conflicts identified · OK
No dependency under our consumption path is under GPL, AGPL, or Server Side Public License. The strongest copyleft we encounter is LGPL 2.1 (Espressif framework / FreeRTOS components), which is acceptable because we link without static embedding.

### F-3 · Brand fonts not redistributed · OK
Instrument Serif, JetBrains Mono, and Inter Tight are loaded at runtime from Google Fonts (OFL 1.1). The fonts are not embedded in any artifact in this repository, so no font licensing obligation attaches to repository releases.

### F-4 · No proprietary or commercial-only dependencies · OK
Every dependency in the build path is open source under a permissive licence (MIT, BSD, Apache 2.0, OFL, MSLA-conditional). No "commercial use requires license" gates.

---

## Recommended actions

1. **Add MSLA clarifier to `firmware/README.md`** — done as part of this audit's accompanying commit.
2. **Confirm runtime font loading is acceptable to Foundation legal posture** — informally OK; flagged for legal counsel review in the internal legal-checks tracker.
3. **Re-run this audit whenever a `lib_deps` line in `platformio.ini`, a `dependencies` block in `package.json`, or a `requirements.txt` entry changes.** Stale audits are misleading; better to remove than leave outdated.

---

## What this audit is NOT

- A legal opinion. Mel is an LLM-driven assistant, not licensed counsel. For Foundation incorporation (target: Swiss Stiftung per ADR-004), a Swiss IP/software lawyer should re-review the full dependency set.
- A patent freedom-to-operate analysis. Patent risk is orthogonal to copyright/license risk and is captured separately in an internal legal-checks tracker maintained by the team.
- A trademark clearance. Project name "Noethrion" requires a separate trademark search (preliminary) and registration (later) — also tracked in the legal-checks TODO.
