#!/usr/bin/env python3
"""ADR 0009 Stage B: extract the player body's CanvasLayer subtree into a new
persistent scene (scenes/UI/local_player_ui.tscn) and strip it from player.tscn.

Mechanical .tscn surgery — far less error-prone than hand-retyping. It:
  1. Parses player.tscn into blocks, tracking each block's line range.
  2. Selects the CanvasLayer node + every node parented under it.
  3. Emits a new scene whose root IS the CanvasLayer (renamed LocalPlayerUI),
     stripping the leading "CanvasLayer"/"CanvasLayer/" from child parent paths.
  4. Emits only the transitive ext/sub-resource closure the subtree references
     (+ the controller script).
  5. Rewrites player.tscn by slicing OUT the subtree node ranges and the
     mobile-button [connection] ranges (those get re-wired in code), preserving
     all other formatting exactly.

Run from repo root: python tools/extract_local_ui.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLAYER = ROOT / "scenes/Player/player.tscn"
OUT = ROOT / "scenes/UI/local_player_ui.tscn"
CTRL_SCRIPT_PATH = "res://scripts/UI/local_player_ui.gd"
NEW_SCENE_UID = "uid://blocalplayerui0009"
ROOT_NODE_NAME = "LocalPlayerUI"

lines = PLAYER.read_text(encoding="utf-8").split("\n")

header_re = re.compile(r"^\[(\w+)")
blocks = []  # {kind, start, end(exclusive), header}
cur = None
for i, ln in enumerate(lines):
    if ln.startswith("["):
        if cur:
            cur["end"] = i
        m = header_re.match(ln)
        cur = {"kind": m.group(1) if m else "?", "start": i, "header": ln, "end": None}
        blocks.append(cur)
if cur:
    cur["end"] = len(lines)

def attr(header, name):
    # \b so id= is not captured from inside uid= (e.g. ext_resource has both).
    m = re.search(r'\b' + name + r'="([^"]*)"', header)
    return m.group(1) if m else None

def block_lines(b):
    return lines[b["start"]:b["end"]]

def block_text(b):
    return "\n".join(block_lines(b)).rstrip("\n")

def is_canvas_subtree(b):
    if b["kind"] != "node":
        return False
    name, parent = attr(b["header"], "name"), attr(b["header"], "parent")
    if name == "CanvasLayer" and parent == ".":
        return True
    return parent == "CanvasLayer" or (parent and parent.startswith("CanvasLayer/"))

subtree = [b for b in blocks if is_canvas_subtree(b)]
if not subtree:
    sys.exit("ERROR: no CanvasLayer subtree found")

ext_blocks = {attr(b["header"], "id"): b for b in blocks if b["kind"] == "ext_resource"}
sub_blocks = {}
for b in blocks:
    if b["kind"] == "sub_resource":
        m = re.search(r'id="?([\w]+)"?', b["header"])
        if m:
            sub_blocks[m.group(1)] = b

ref_re = re.compile(r'(?:Ext|Sub)Resource\("?([\w]+)"?\)')
needed_ext, needed_sub = set(), set()
worklist, seen = list(subtree), set()
while worklist:
    b = worklist.pop()
    if id(b) in seen:
        continue
    seen.add(id(b))
    for rid in ref_re.findall(block_text(b)):
        if rid in ext_blocks:
            needed_ext.add(rid)
        elif rid in sub_blocks and rid not in needed_sub:
            needed_sub.add(rid)
            worklist.append(sub_blocks[rid])

def reparent(header):
    parent = attr(header, "parent")
    if parent is None:
        return header
    if parent == "CanvasLayer":
        newp = "."
    elif parent.startswith("CanvasLayer/"):
        newp = parent[len("CanvasLayer/"):]
    else:
        newp = parent
    return header.replace(f'parent="{parent}"', f'parent="{newp}"')

# --- new scene ---
load_steps = len(needed_ext) + 1 + len(needed_sub) + len(subtree)
out = [f'[gd_scene load_steps={load_steps} format=3 uid="{NEW_SCENE_UID}"]', ""]
out.append(f'[ext_resource type="Script" path="{CTRL_SCRIPT_PATH}" id="ctrl_lpui"]')
for b in blocks:
    if b["kind"] == "ext_resource" and attr(b["header"], "id") in needed_ext:
        out.append(b["header"])
out.append("")
for b in blocks:
    if b["kind"] == "sub_resource":
        m = re.search(r'id="?([\w]+)"?', b["header"])
        if m and m.group(1) in needed_sub:
            out.append(block_text(b))
            out.append("")
root_block = next(b for b in subtree if attr(b["header"], "name") == "CanvasLayer")
out.append(f'[node name="{ROOT_NODE_NAME}" type="CanvasLayer"]')
out.append('script = ExtResource("ctrl_lpui")')
out.extend(lines[root_block["start"] + 1:root_block["end"]])  # root props (skip its header)
for b in subtree:
    if b is root_block:
        continue
    out.append(reparent(b["header"]))
    out.extend(lines[b["start"] + 1:b["end"]])
OUT.write_text("\n".join(out).rstrip("\n") + "\n", encoding="utf-8")

# --- rewrite player.tscn by removing subtree + mobile-button connection line ranges ---
def is_mobile_conn(b):
    return b["kind"] == "connection" and "MobileButtons" in b["header"] and 'to="InputSynchronizer"' in b["header"]

remove = set()
for b in subtree + [b for b in blocks if is_mobile_conn(b)]:
    for i in range(b["start"], b["end"]):
        remove.add(i)
kept = [ln for i, ln in enumerate(lines) if i not in remove]
new_player = "\n".join(kept)
new_player = re.sub(r"\n{3,}", "\n\n", new_player)  # collapse runs of blanks left by removals
PLAYER.write_text(new_player.rstrip("\n") + "\n", encoding="utf-8")

print(f"Wrote {OUT.relative_to(ROOT)}: {len(subtree)} nodes, {len(needed_ext)} ext, {len(needed_sub)} sub")
print(f"Stripped {len(subtree)} nodes + {sum(1 for b in blocks if is_mobile_conn(b))} mobile conns from player.tscn")
print("needed_ext ids:", sorted(needed_ext))
