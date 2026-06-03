#!/usr/bin/env python3
"""Repoint every ability/item .tres icon from its generated_svg SVG to the
matching generated_px PNG (pixel-art). Reads the PNG's uid from its .png.import.
Idempotent. Run after importing the PNGs in Godot.
"""
import os, re, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOTS = [os.path.join(ROOT, "resources", "Abilities"),
         os.path.join(ROOT, "resources", "Items")]

EXT_RE = re.compile(
    r'\[ext_resource type="Texture2D" uid="[^"]*" '
    r'path="(res://[^"]*generated_svg/[^"]*\.svg)" id="([^"]*)"\]')

def png_uid(res_png_path):
    abs_imp = os.path.join(ROOT, res_png_path[len("res://"):] + ".import")
    if not os.path.exists(abs_imp):
        return None
    txt = open(abs_imp, encoding="utf-8").read()
    return re.search(r'uid="([^"]+)"', txt).group(1)

def main():
    wired, skipped = 0, []
    for base in ROOTS:
        for tres in glob.glob(os.path.join(base, "**", "*.tres"), recursive=True):
            txt = open(tres, encoding="utf-8").read()
            m = EXT_RE.search(txt)
            if not m:
                continue
            svg_path, icon_id = m.group(1), m.group(2)
            png_path = svg_path.replace("generated_svg", "generated_px").replace(".svg", ".png")
            uid = png_uid(png_path)
            if not uid:
                skipped.append(f"{os.path.relpath(tres, ROOT)} (no png import for {png_path})")
                continue
            new_line = (f'[ext_resource type="Texture2D" uid="{uid}" '
                        f'path="{png_path}" id="{icon_id}"]')
            new_txt = EXT_RE.sub(new_line, txt, count=1)
            open(tres, "w", encoding="utf-8").write(new_txt)
            wired += 1
    print(f"Wired {wired} icons svg -> png.")
    for s in skipped:
        print("  skip:", s)

if __name__ == "__main__":
    main()
