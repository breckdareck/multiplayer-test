#!/usr/bin/env python3
"""Standardize one_way_collision_margin across map scenes.

One-way platform tunneling: a body at terminal velocity falls MAX_FALL_SPEED/
physics_ticks = 1200/60 = 20px per physics tick. Godot only registers a one-way
collision while the body is within `one_way_collision_margin` of the shape, so a
margin BELOW the per-tick travel lets fast fallers pass straight through. Many
inline level shapes were at 16px (or the 1px default when no margin line existed),
so bots/players tunnelled — worse with many bots simply because more are falling.

Set every one_way shape to MARGIN (> per-tick travel, with headroom). Idempotent.
Run: python tools/fix_oneway_margins.py
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MARGIN = "32.0"
SCENES = sorted((ROOT / "scenes").rglob("*.tscn"))

total_files = 0
total_set = 0
total_inserted = 0
for scene in SCENES:
    text = scene.read_text(encoding="utf-8")
    if "one_way_collision = true" not in text and "one_way_collision_margin" not in text:
        continue
    lines = text.split("\n")
    out = []
    set_count = 0
    ins_count = 0
    for i, ln in enumerate(lines):
        stripped = ln.strip()
        if stripped.startswith("one_way_collision_margin"):
            # Normalize any existing margin to MARGIN.
            if ln != "one_way_collision_margin = " + MARGIN:
                set_count += 1
            out.append("one_way_collision_margin = " + MARGIN)
            continue
        out.append(ln)
        if stripped == "one_way_collision = true":
            # Insert a margin line right after, unless the next line already is one
            # (that case is handled by the branch above on the next iteration).
            nxt = lines[i + 1].strip() if i + 1 < len(lines) else ""
            if not nxt.startswith("one_way_collision_margin"):
                out.append("one_way_collision_margin = " + MARGIN)
                ins_count += 1
    new_text = "\n".join(out)
    if new_text != text:
        scene.write_text(new_text, encoding="utf-8")
        total_files += 1
        total_set += set_count
        total_inserted += ins_count
        print("%s: normalized %d, inserted %d" % (scene.relative_to(ROOT), set_count, ins_count))

print("Done. %d files changed, %d margins normalized, %d inserted (all -> %s)." % (
    total_files, total_set, total_inserted, MARGIN))
