#!/usr/bin/env python3
"""Repoint each ability .tres's icon to its generated SVG.

For every resources/Abilities/<Weapon>/A_*.tres, find the Texture2D ext_resource
referenced by `ability_icon = ExtResource("id")` and rewrite its uid + path to the
matching generated_svg/<Weapon>/<base>.svg (uid read from the .svg.import).
Idempotent. Run after importing the SVGs in Godot.
"""
import os, re, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ABIL = os.path.join(ROOT, "resources", "Abilities")
SVG = os.path.join(ROOT, "assets", "sprites", "Abilities", "generated_svg")
WEAPONS = ["Sword", "Bow", "Staff", "Dagger"]

def svg_uid_and_path(weapon, base):
    imp = os.path.join(SVG, weapon, base + ".svg.import")
    if not os.path.exists(imp):
        return None, None
    txt = open(imp, encoding="utf-8").read()
    uid = re.search(r'uid="([^"]+)"', txt).group(1)
    src = re.search(r'source_file="([^"]+)"', txt).group(1)
    return uid, src

def main():
    wired, skipped = 0, []
    for w in WEAPONS:
        for tres in sorted(glob.glob(os.path.join(ABIL, w, "*.tres"))):
            base = os.path.splitext(os.path.basename(tres))[0]
            uid, path = svg_uid_and_path(w, base)
            if not uid:
                skipped.append(f"{w}/{base} (no svg import)")
                continue
            txt = open(tres, encoding="utf-8").read()
            m = re.search(r'ability_icon\s*=\s*ExtResource\("([^"]+)"\)', txt)
            if not m:
                skipped.append(f"{w}/{base} (no ability_icon)")
                continue
            icon_id = m.group(1)
            # rewrite the Texture2D ext_resource line carrying this id
            pat = re.compile(
                r'\[ext_resource type="Texture2D"[^\]]*?\bid="' + re.escape(icon_id) + r'"\]')
            new_line = (f'[ext_resource type="Texture2D" uid="{uid}" '
                        f'path="{path}" id="{icon_id}"]')
            new_txt, n = pat.subn(new_line, txt, count=1)
            if n == 0:
                skipped.append(f"{w}/{base} (ext_resource id {icon_id} not found)")
                continue
            if new_txt != txt:
                open(tres, "w", encoding="utf-8").write(new_txt)
            wired += 1
    print(f"Wired {wired} ability icons.")
    if skipped:
        print("Skipped:")
        for s in skipped:
            print("  -", s)

if __name__ == "__main__":
    main()
