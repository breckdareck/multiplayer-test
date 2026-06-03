#!/usr/bin/env python3
"""Repoint each weapon/armor .tres `icon` to its generated SVG.

Adds a Texture2D ext_resource (id 99_svgicon) pointing at the matching
generated_svg/<rel>.svg (uid from .svg.import), and rewrites the `icon = ...`
assignment to ExtResource("99_svgicon"). Bumps load_steps by 1. Idempotent.
Old AtlasTexture sub-resources are left in place (harmless, unreferenced).
"""
import os, re, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ITEMS = os.path.join(ROOT, "resources", "Items")
SVG = os.path.join(ROOT, "assets", "sprites", "Items", "generated_svg")
SRC_DIRS = ["Weapons", "Armor", "Unique"]
ICON_ID = "99_svgicon"

def svg_uid_path(rel_noext):
    imp = os.path.join(SVG, rel_noext + ".svg.import")
    if not os.path.exists(imp):
        return None, None
    txt = open(imp, encoding="utf-8").read()
    uid = re.search(r'uid="([^"]+)"', txt).group(1)
    src = re.search(r'source_file="([^"]+)"', txt).group(1)
    return uid, src

def main():
    wired, skipped = 0, []
    for sd in SRC_DIRS:
        for tres in sorted(glob.glob(os.path.join(ITEMS, sd, "**", "*.tres"), recursive=True)):
            rel_noext = os.path.splitext(os.path.relpath(tres, ITEMS))[0]
            uid, path = svg_uid_path(rel_noext)
            if not uid:
                continue
            txt = open(tres, encoding="utf-8").read()
            if 'script_class="WeaponData"' not in txt and 'script_class="ArmorData"' not in txt:
                continue
            already = f'path="{path}"' in txt
            # 1) inject ext_resource after the gd_resource header line (once)
            if not already:
                hdr = re.search(r'^\[gd_resource [^\]]*\]\n', txt, re.M)
                ext_line = (f'[ext_resource type="Texture2D" uid="{uid}" '
                            f'path="{path}" id="{ICON_ID}"]\n')
                txt = txt[:hdr.end()] + "\n" + ext_line + txt[hdr.end():].lstrip("\n")
                # bump load_steps
                txt = re.sub(r'(\[gd_resource [^\]]*?load_steps=)(\d+)',
                             lambda mm: mm.group(1) + str(int(mm.group(2)) + 1), txt, count=1)
            # 2) repoint icon assignment
            new_txt, n = re.subn(r'^icon\s*=\s*(SubResource|ExtResource)\("[^"]+"\)',
                                 f'icon = ExtResource("{ICON_ID}")', txt, count=1, flags=re.M)
            if n == 0:
                skipped.append(f"{rel_noext} (no icon assignment)")
                continue
            open(tres, "w", encoding="utf-8").write(new_txt)
            wired += 1
    print(f"Wired {wired} item icons.")
    for s in skipped:
        print("  skip:", s)

if __name__ == "__main__":
    main()
