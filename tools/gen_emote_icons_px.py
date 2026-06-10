#!/usr/bin/env python3
"""Render the chat emote set as 32x32 pixel-art PNGs for overhead bubbles.

Same zero-dependency pipeline as gen_item_icons_px.py (tools/pixelart.py
canvas, hard edges, 1px outline, transparent background). The chat feed keeps
the text form ("*waves*"); these icons replace TEXT in the overhead bubble
only (see ChatManager.EMOTES + MultiplayerPlayerV2.show_emote_bubble).

Output: assets/sprites/Emotes/generated_px/<name>.png
Run from project root:  python tools/gen_emote_icons_px.py
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pixelart import Canvas, hexc

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sprites", "Emotes", "generated_px")

OL = hexc("#1a1f27")
SKIN = hexc("#ffd9a0"); SKINH = hexc("#ffefd0"); SKIND = hexc("#c9974f")
MOUTH = hexc("#7a2e1e"); BLUSH = hexc("#ff9d7a")
TEAR = hexc("#6fc3ff"); TEARH = hexc("#cdeaff")
ZF = hexc("#cdd6e2")
SEAT = hexc("#6e4a28"); SEATH = hexc("#9c6b3f")


def face(c, cx=16, cy=15, r=10):
    """Round face base with a simple top-light."""
    c.disc(cx, cy, r, SKIN)
    c.disc(cx - 2, cy - 3, r - 4, SKINH)
    c.disc(cx, cy, r, None)  # no-op keeps signature obvious
    # bottom shade arc
    for y in range(cy + r - 3, cy + r + 1):
        for x in range(cx - r, cx + r + 1):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                c.px(x, y, SKIND)


def eyes(c, cx=16, cy=14, open_=True):
    if open_:
        c.rect(cx - 5, cy - 1, cx - 3, cy + 1, OL, fill=OL)
        c.rect(cx + 3, cy - 1, cx + 5, cy + 1, OL, fill=OL)
    else:
        c.hline(cx - 6, cx - 3, cy, OL)
        c.hline(cx + 3, cx + 6, cy, OL)


def gen_laugh():
    c = Canvas(32, 32)
    face(c)
    # squeezed-happy eyes (^ ^)
    c.line(10, 14, 12, 12, OL); c.line(12, 12, 14, 14, OL)
    c.line(18, 14, 20, 12, OL); c.line(20, 12, 22, 14, OL)
    # big open laughing mouth
    c.ellipse(16, 20, 5, 3, MOUTH)
    c.hline(12, 20, 18, hexc("#ffffff"))
    # blush
    c.rect(8, 17, 10, 18, BLUSH, fill=BLUSH)
    c.rect(22, 17, 24, 18, BLUSH, fill=BLUSH)
    c.outline(OL)
    return c


def gen_cry():
    c = Canvas(32, 32)
    face(c)
    eyes(c, open_=False)
    # downturned mouth
    c.line(13, 22, 16, 20, OL); c.line(16, 20, 19, 22, OL)
    # twin tears running from the eyes
    c.rect(11, 16, 12, 21, TEAR, fill=TEAR)
    c.px(11, 22, TEAR); c.px(12, 23, TEARH)
    c.rect(20, 16, 21, 19, TEAR, fill=TEAR)
    c.px(20, 20, TEARH)
    c.outline(OL)
    return c


def gen_wave():
    c = Canvas(32, 32)
    # smaller face, lower-left, leaving room for the raised hand
    face(c, cx=13, cy=18, r=8)
    eyes(c, cx=13, cy=17)
    c.hline(11, 15, 21, OL)  # smile
    # raised arm + open hand, upper-right
    c.line(20, 18, 24, 12, SKIND)
    c.line(21, 18, 25, 12, SKIN)
    c.disc(25, 9, 3, SKIN)
    c.disc(24, 8, 2, SKINH)
    # fingers
    for i, (fx, fy) in enumerate([(22, 6), (24, 5), (26, 5), (28, 7)]):
        c.line(fx, fy, 25, 9, SKIN)
    # motion ticks
    c.px(18, 6, ZF); c.px(17, 8, ZF)
    c.outline(OL)
    return c


def gen_sit():
    c = Canvas(32, 32)
    # seated figure in profile: head, torso leaning back, legs folded forward
    c.disc(13, 9, 5, SKIN)
    c.disc(12, 8, 3, SKINH)
    c.px(15, 9, OL)  # eye (profile, facing right)
    # torso
    c.poly([(9, 14), (16, 14), (17, 22), (8, 22)], hexc("#5a7c9c"))
    c.rect(9, 14, 16, 16, hexc("#7aa2c4"), fill=hexc("#7aa2c4"))
    # folded legs forward
    c.rect(14, 20, 22, 23, hexc("#4a6582"), fill=hexc("#4a6582"))
    c.rect(21, 20, 23, 26, hexc("#4a6582"), fill=hexc("#4a6582"))
    c.rect(20, 25, 25, 26, SEATH, fill=SEATH)  # foot
    # log seat
    c.rect(5, 23, 18, 27, SEAT, fill=SEAT)
    c.hline(6, 17, 24, SEATH)
    c.outline(OL)
    return c


EMOTES = {
    "sit": gen_sit,
    "wave": gen_wave,
    "laugh": gen_laugh,
    "cry": gen_cry,
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in EMOTES.items():
        path = os.path.join(OUT, name + ".png")
        fn().to_png(path)
        print("wrote", os.path.relpath(path, ROOT))


if __name__ == "__main__":
    main()
