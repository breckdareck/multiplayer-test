#!/usr/bin/env python3
"""Strip orphaned Items.png references from item .tres whose icon is already
migrated to generated_px.

Handles BOTH atlas-holder forms found in the generated content:
  A) [ext_resource ... path="res://assets/sprites/Items/Items.png" id="X"]
     + [sub_resource type="AtlasTexture"] atlas = ExtResource("X")
  B) [sub_resource type="CompressedTexture2D"] load_path=".../Items.png-*.ctex"
     + [sub_resource type="AtlasTexture"] atlas = SubResource("<that comp>")

SAFE BY DESIGN: a file is modified only when EVERY removal-target id is
unreferenced by the rest of the file (icon/fields point elsewhere). If anything
still uses the atlas, the file is reported and SKIPPED — never broken. Line
endings are preserved.

Usage:
  python tools/strip_items_png_refs.py          # dry-run report
  python tools/strip_items_png_refs.py --apply  # write changes
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
ITEMS_DIR = ROOT / "resources" / "Items"
ITEMS_PNG_PATH = 'path="res://assets/sprites/Items/Items.png"'  # exact bare atlas
APPLY = "--apply" in sys.argv

ext_re = re.compile(r'^\[ext_resource\s+.*\bid="([^"]+)"\s*\]\s*$')
sub_open_re = re.compile(r'^\[sub_resource\s+type="([^"]+)"\s+id="([^"]+)"\s*\]\s*$')
block_re = re.compile(r'^\[')

modified, skipped, untouched = [], [], 0

def block_body(lines, i):
    """Return (body_lines, next_index) for the block opened at line i."""
    j = i + 1
    body = []
    while j < len(lines) and not block_re.match(lines[j]):
        body.append(lines[j]); j += 1
    return body, j

for tres in sorted(ITEMS_DIR.rglob("*.tres")):
    text = tres.read_text(encoding="utf-8")
    if "Items.png" not in text:
        untouched += 1
        continue
    lines = text.splitlines(keepends=False)

    ext_ids = set()    # E: bare Items.png ext_resource ids
    comp_ids = set()   # C: CompressedTexture2D sub-resources pointing at Items.png ctex
    atlas_ids = set()  # A: AtlasTexture sub-resources referencing E or C

    # pass 1: collect E and C
    i = 0
    while i < len(lines):
        ln = lines[i]
        if ext_re.match(ln) and ITEMS_PNG_PATH in ln:
            ext_ids.add(ext_re.match(ln).group(1)); i += 1; continue
        m = sub_open_re.match(ln)
        if m and m.group(1) == "CompressedTexture2D":
            body, nxt = block_body(lines, i)
            if any("Items.png" in b for b in body):
                comp_ids.add(m.group(2))
            i = nxt; continue
        i += 1

    # pass 2: AtlasTextures whose atlas points at any E (ExtResource) or C (SubResource)
    i = 0
    while i < len(lines):
        m = sub_open_re.match(lines[i])
        if m and m.group(1) == "AtlasTexture":
            body, nxt = block_body(lines, i)
            joined = "\n".join(body)
            if any(f'ExtResource("{x}")' in joined for x in ext_ids) or \
               any(f'SubResource("{x}")' in joined for x in comp_ids):
                atlas_ids.add(m.group(2))
            i = nxt; continue
        i += 1

    remove = ext_ids | comp_ids | atlas_ids
    if not remove:
        skipped.append((tres, "mentions Items.png but no removable atlas ref found"))
        continue

    # build the set of line indices to drop (declarations + sub-resource bodies)
    drop_idx = set()
    i = 0
    while i < len(lines):
        ln = lines[i]
        em = ext_re.match(ln)
        if em and em.group(1) in remove:
            drop_idx.add(i); i += 1; continue
        sm = sub_open_re.match(ln)
        if sm and sm.group(2) in remove:
            drop_idx.add(i)
            _, nxt = block_body(lines, i)
            for k in range(i + 1, nxt):
                drop_idx.add(k)
            # also drop a single trailing blank separator if present
            if nxt < len(lines) and lines[nxt].strip() == "":
                drop_idx.add(nxt); nxt += 1
            i = nxt; continue
        i += 1

    # safety: is any removal-target id still referenced OUTSIDE the dropped lines?
    refs = [re.compile(r'(?:Ext|Sub)Resource\("%s"\)' % re.escape(x)) for x in remove]
    still_used = any(
        any(r.search(ln) for r in refs)
        for idx, ln in enumerate(lines) if idx not in drop_idx
    )
    if still_used:
        skipped.append((tres, "icon/field still references the Items.png atlas — NOT migrated"))
        continue

    new_lines = [ln for idx, ln in enumerate(lines) if idx not in drop_idx]
    removed_steps = len(remove)
    for idx, ln in enumerate(new_lines):
        sm = re.match(r'^(\[gd_resource\b.*?\bload_steps=)(\d+)(.*\]\s*)$', ln)
        if sm:
            new_lines[idx] = sm.group(1) + str(int(sm.group(2)) - removed_steps) + sm.group(3)
            break

    nl = "\r\n" if "\r\n" in text else "\n"
    new_text = nl.join(new_lines) + (nl if text.endswith("\n") else "")
    modified.append((tres, len(ext_ids), len(comp_ids), len(atlas_ids)))
    if APPLY:
        tres.write_text(new_text, encoding="utf-8", newline="")

print(f"{'APPLIED' if APPLY else 'DRY-RUN'}  modified={len(modified)}  skipped={len(skipped)}  untouched(no Items.png)={untouched}")
for t, ne, nc, na in modified:
    print(f"  {t.relative_to(ROOT)}  (-{ne} ext, -{nc} comp, -{na} atlas)")
if skipped:
    print("--- SKIPPED (left alone) ---")
    for t, why in skipped:
        print(f"  {t.relative_to(ROOT)}  :: {why}")
