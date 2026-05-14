#!/usr/bin/env python3
"""Render Noethrion social-card and avatar PNGs.

The SVGs in `assets/og-image.svg`, `assets/social/twitter_avatar_400.svg`,
and `assets/social/farcaster_avatar_400.svg` are the source of truth. Because
cairosvg requires a system libcairo install that is not universally available,
this script reproduces the same composition directly with Pillow primitives,
which only needs the wheel-bundled native bits.

Output PNGs are written next to the SVGs and committed alongside them; the
landing page references the PNGs via the OG / Twitter meta tags.

Run:
    python3 tools/render_social_assets.py [--out-dir <REPO_ROOT>]

Output files (all 24-bit RGB PNG, no transparency, sRGB):
    docs/og-image.png                      1200 × 630   (served by Cloudflare Pages)
    assets/social/twitter_avatar_400.png    400 × 400   (founder uploads manually)
    assets/social/farcaster_avatar_400.png  400 × 400   (founder uploads manually)
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("error: Pillow required. Install with: pip install pillow")


# ─────────────────────────────────────────────────────────────────────────────
# Brand constants
# ─────────────────────────────────────────────────────────────────────────────

NOIR = (10, 10, 10)
ETA_GREEN = (20, 241, 149)
CREAM = (245, 241, 232)
CREAM_DIM = (196, 191, 178)
NEUTRAL_DIM = (107, 104, 98)

# macOS-standard fonts used as Instrument-Serif / Inter-Tight / JetBrains-Mono
# fallbacks. The brand fonts are not freely redistributable into the repo, so
# we approximate them at render time.
FONT_SERIF_ITALIC = "/System/Library/Fonts/Supplemental/Georgia Italic.ttf"
FONT_SANS = "/System/Library/Fonts/Helvetica.ttc"
FONT_MONO = "/System/Library/Fonts/Supplemental/Courier New.ttf"


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _load(path: str, size: int) -> ImageFont.FreeTypeFont:
    try:
        return ImageFont.truetype(path, size=size)
    except OSError as e:
        sys.exit(f"error: font not found: {path} ({e}). This script targets macOS system fonts.")


def _text(draw: ImageDraw.ImageDraw, xy, text, font, fill, anchor="la"):
    draw.text(xy, text, font=font, fill=fill, anchor=anchor)


# ─────────────────────────────────────────────────────────────────────────────
# Renderers
# ─────────────────────────────────────────────────────────────────────────────

def render_og_image(out: Path) -> None:
    """1200×630 social card — link-preview hero used on Twitter, FB, Mastodon, etc."""
    W, H = 1200, 630
    img = Image.new("RGB", (W, H), color=NOIR)
    draw = ImageDraw.Draw(img)

    # Pulse dot top-left
    draw.ellipse((74, 74, 86, 86), fill=ETA_GREEN)

    # Mono caption
    f_mono14 = _load(FONT_MONO, 14)
    _text(draw, (100, 78), "// PROTOCOL · v0.1 · MAY 2026", f_mono14, NEUTRAL_DIM)

    # Large italic eta — left third
    f_eta = _load(FONT_SERIF_ITALIC, 380)
    _text(draw, (240, 450), "η", f_eta, ETA_GREEN, anchor="mb")

    # Baseline rule under eta (55% of glyph width, centered)
    draw.line([(135, 480), (345, 480)], fill=CREAM, width=2)

    # Wordmark
    f_word = _load(FONT_SANS, 78)
    _text(draw, (470, 290), "noethrion", f_word, CREAM, anchor="ls")

    # Tagline
    f_tag = _load(FONT_SANS, 26)
    _text(draw, (470, 350), "Open standard for verifiable energy.", f_tag, CREAM_DIM, anchor="ls")

    # Equation in eta-green mono
    f_eq = _load(FONT_MONO, 18)
    _text(draw, (470, 420), "1 NOET = 1 kWh · cryptographically signed", f_eq, ETA_GREEN, anchor="ls")

    # Footer formula
    _text(draw, (100, 595), "η = E_useful / E_total", f_mono14, NEUTRAL_DIM, anchor="ls")

    # Footer URL right-aligned
    _text(draw, (1100, 595), "noethrion.com", f_mono14, NEUTRAL_DIM, anchor="rs")

    img.save(out, format="PNG", optimize=True)
    print(f"wrote {out} ({W}×{H})")


def render_avatar(out: Path, label: str) -> None:
    """400×400 square avatar — Twitter / X, Farcaster, anywhere a square mark is needed."""
    W, H = 400, 400
    img = Image.new("RGB", (W, H), color=NOIR)
    draw = ImageDraw.Draw(img)

    # Large italic eta, centered
    f_eta = _load(FONT_SERIF_ITALIC, 280)
    _text(draw, (W // 2, 280), "η", f_eta, ETA_GREEN, anchor="mb")

    # Baseline rule under eta
    draw.line([(125, 300), (275, 300)], fill=CREAM, width=3)

    img.save(out, format="PNG", optimize=True)
    print(f"wrote {out} ({W}×{H}, {label})")


# ─────────────────────────────────────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────────────────────────────────────

def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    p.add_argument(
        "--out-dir",
        default=str(Path(__file__).resolve().parent.parent),
        help="Repository root (default: parent of tools/)",
    )
    args = p.parse_args(argv)

    root = Path(args.out_dir)
    (root / "docs").mkdir(parents=True, exist_ok=True)
    (root / "assets" / "social").mkdir(parents=True, exist_ok=True)

    # og-image lives in docs/ so Cloudflare Pages serves it at noethrion.com/og-image.png
    render_og_image(root / "docs" / "og-image.png")
    # Avatars stay in assets/social/ — uploaded manually to Twitter/X + Farcaster
    render_avatar(root / "assets" / "social" / "twitter_avatar_400.png", "twitter/X")
    render_avatar(root / "assets" / "social" / "farcaster_avatar_400.png", "farcaster")
    return 0


if __name__ == "__main__":
    sys.exit(main())
