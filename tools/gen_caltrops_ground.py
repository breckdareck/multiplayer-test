#!/usr/bin/env python3
"""Generate the Caltrops ground-VFX sprite sheet (zero-dependency, via
tools/pixelart.py — same pipeline as gen_ability_icons_px.py).

A low strip of scattered steel caltrops (the classic jack: two splayed legs
on the ground + one spike pointing up) with a glint that wanders between
frames so the looping strip subtly shimmers instead of sitting dead-still.

Output: assets/sprites/VFX/generated_px/caltrops_ground-Sheet.png
4 frames of 48x24, laid out horizontally. Referenced by
resources/VFX/caltrops_ground.tres (frame_width 48, frame_height 24, loop).

Run from project root:  python tools/gen_caltrops_ground.py
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pixelart import Canvas, hexc

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "VFX", "generated_px")
OUT = os.path.join(OUT_DIR, "caltrops_ground-Sheet.png")

FRAMES = 4
FW, FH = 48, 24

STEEL = hexc("#aeb8c6")
STEEL_DARK = hexc("#5a626c")
STEEL_DEEP = hexc("#363c44")
GLINT = hexc("#f2f6fb")
RUST = hexc("#8a6a4a")

# (x, y of the ground point, flip, rusty) — a hand-scattered strip. y is the
# caltrop's BASE on the ground (bottom of the frame band, leaving headroom for
# the up-spike). Layout chosen so tiling the 48px frame side-by-side doesn't
# create an obvious seam (no caltrop touches the frame edge).
CALTROPS = [
    (7, 20, False, False),
    (16, 22, True, True),
    (25, 19, False, False),
    (33, 22, False, False),
    (41, 20, True, True),
]

# Which caltrop (index) carries the glint per frame — the shimmer wanders.
GLINT_AT = [0, 2, 4, 1]


def draw_caltrop(cv: Canvas, x: int, y: int, flip: bool, rusty: bool) -> None:
    """One jack: two splayed ground legs + a center spike pointing up.
    ~7px wide, ~7px tall. `flip` mirrors the leg spread; `rusty` darkens
    one leg for variety."""
    body = STEEL_DARK if rusty else STEEL
    d = -1 if flip else 1
    # splayed legs (ground contact)
    cv.line(x, y - 2, x - 3 * d, y, RUST if rusty else STEEL_DARK)
    cv.line(x, y - 2, x + 3 * d, y, body)
    # center joint
    cv.px(x, y - 2, STEEL)
    cv.px(x + d, y - 2, STEEL_DEEP)
    # up-spike
    cv.vline(x, y - 6, y - 3, body)
    cv.px(x, y - 7, STEEL_DEEP)
    # rear leg hint (depth)
    cv.px(x - 1 * d, y - 1, STEEL_DEEP)


def draw_frame(cv: Canvas, ox: int, glint_idx: int) -> None:
    for i, (x, y, flip, rusty) in enumerate(CALTROPS):
        draw_caltrop(cv, ox + x, y, flip, rusty)
        if i == glint_idx:
            # the wandering glint: spike tip + a sparkle pixel beside it
            cv.px(ox + x, y - 6, GLINT)
            cv.px(ox + x + 1, y - 7, GLINT)


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    sheet = Canvas(FW * FRAMES, FH)
    for f in range(FRAMES):
        draw_frame(sheet, f * FW, GLINT_AT[f])
    sheet.to_png(OUT)
    print("wrote", OUT, f"({FW * FRAMES}x{FH}, {FRAMES} frames of {FW}x{FH})")


if __name__ == "__main__":
    main()
