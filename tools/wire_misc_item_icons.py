#!/usr/bin/env python3
"""Repoint consumable / pet-item / Coin `icon` to the generated SVG.

Same approach as wire_item_icons.py but for ConsumableData / PetFoodData /
PetSkillBookData / ItemData under Consumables/, PetItems/, and Coin.tres.
Idempotent; old AtlasTexture sub-resources are left in place (harmless).
"""
import os, re, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ITEMS = os.path.join(ROOT, "resources", "Items")
SVG = os.path.join(ROOT, "assets", "sprites", "Items", "generated_svg")
ICON_ID = "99_svgicon"
CLASSES = ("ConsumableData", "PetFoodData", "PetSkillBookData", "ItemData")

def svg_uid_path(rel_noext):
    imp = os.path.join(SVG, rel_noext + ".svg.import")
    if not os.path.exists(imp):
        return None, None
    txt = open(imp, encoding="utf-8").read()
    return (re.search(r'uid="([^"]+)"', txt).group(1),
            re.search(r'source_file="([^"]+)"', txt).group(1))

def main():
    targets = (glob.glob(os.path.join(ITEMS, "Consumables", "**", "*.tres"), recursive=True) +
               glob.glob(os.path.join(ITEMS, "PetItems", "**", "*.tres"), recursive=True) +
               [os.path.join(ITEMS, "Coin.tres")])
    wired, skipped = 0, []
    for tres in sorted(targets):
        if not os.path.exists(tres):
            continue
        rel_noext = os.path.splitext(os.path.relpath(tres, ITEMS))[0]
        uid, path = svg_uid_path(rel_noext)
        if not uid:
            skipped.append(f"{rel_noext} (no svg import)")
            continue
        txt = open(tres, encoding="utf-8").read()
        if not any(f'script_class="{c}"' in txt for c in CLASSES):
            skipped.append(f"{rel_noext} (unhandled class)")
            continue
        already = f'path="{path}"' in txt
        if not already:
            hdr = re.search(r'^\[gd_resource [^\]]*\]\n', txt, re.M)
            ext_line = (f'[ext_resource type="Texture2D" uid="{uid}" '
                        f'path="{path}" id="{ICON_ID}"]\n')
            txt = txt[:hdr.end()] + "\n" + ext_line + txt[hdr.end():].lstrip("\n")
            txt = re.sub(r'(\[gd_resource [^\]]*?load_steps=)(\d+)',
                         lambda mm: mm.group(1) + str(int(mm.group(2)) + 1), txt, count=1)
        new_txt, n = re.subn(r'^icon\s*=\s*(SubResource|ExtResource)\("[^"]+"\)',
                             f'icon = ExtResource("{ICON_ID}")', txt, count=1, flags=re.M)
        if n == 0:
            skipped.append(f"{rel_noext} (no icon assignment)")
            continue
        open(tres, "w", encoding="utf-8").write(new_txt)
        wired += 1
    print(f"Wired {wired} misc item icons.")
    for s in skipped:
        print("  skip:", s)

if __name__ == "__main__":
    main()
