# -*- coding: utf-8 -*-
"""Generate the 5 new Emberwilds zone scenes by cloning map_template.tscn,
swapping in the right enemies, and wiring the portal chain
game4 -> mines -> keep -> emberscar -> weave -> warlord.

Geometry (tilemap/platforms) is the template's placeholder — art-pass in-editor.
Enemies/portals are placed at sensible positions on the template's ground (y=16).
"""
import io, re, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATE = os.path.join(ROOT, "scenes/Levels/map_template.tscn")

ENEMY = {
    "wolf_pathfinder":  "res://scenes/NPC/Beastmen/wolf_pathfinder.tscn",
    "mithril_hare":     "res://scenes/NPC/Minifolks/mithril_hare.tscn",
    "deer_druid":       "res://scenes/NPC/Beastmen/deer_druid.tscn",
    "rabbit_wizard":    "res://scenes/NPC/Beastmen/rabbit_wizard.tscn",
    "war_goblin":       "res://scenes/NPC/war_goblin.tscn",
    "bear_warrior":     "res://scenes/NPC/Beastmen/bear_warrior.tscn",
    "dark_bunny":       "res://scenes/NPC/Minifolks/dark_bunny.tscn",
    "lion_knight":      "res://scenes/NPC/Beastmen/lion_knight.tscn",
    "adamant_crawler":  "res://scenes/NPC/adamant_crawler.tscn",
    "panda_warrior":    "res://scenes/NPC/Beastmen/panda_warrior.tscn",
    "shadow_fox":       "res://scenes/NPC/Minifolks/shadow_fox.tscn",
    "runed_boar":       "res://scenes/NPC/Minifolks/runed_boar.tscn",
    "fire_slime":       "res://scenes/NPC/fire_slime.tscn",
    "ember_fox":        "res://scenes/NPC/Minifolks/ember_fox.tscn",
    "wild_boar":        "res://scenes/NPC/Minifolks/wild_boar.tscn",
    "celestial_hare":   "res://scenes/NPC/Minifolks/celestial_hare.tscn",
    "astral_slime":     "res://scenes/NPC/astral_slime.tscn",
    "eternal_warlord":  "res://scenes/NPC/eternal_warlord.tscn",
}

def pcs(s):  # snake -> PascalCase node name
    return "".join(p.capitalize() for p in s.split("_"))

MAPS = [
    dict(id="mines", root="Mines", name="The Drowned Mines",
         prev="game4", prevpc="Game4", nxt="keep", nxtpc="Keep",
         enemies=[("wolf_pathfinder",4),("mithril_hare",3),("deer_druid",3),("rabbit_wizard",3),("war_goblin",3)]),
    dict(id="keep", root="Keep", name="The Warded Keep",
         prev="mines", prevpc="Mines", nxt="emberscar", nxtpc="Emberscar",
         enemies=[("bear_warrior",3),("dark_bunny",3),("lion_knight",3),("adamant_crawler",3),("panda_warrior",2),("shadow_fox",3)]),
    dict(id="emberscar", root="Emberscar", name="The Ember-Scar",
         prev="keep", prevpc="Keep", nxt="weave", nxtpc="Weave",
         enemies=[("runed_boar",4),("fire_slime",4),("ember_fox",4),("wild_boar",3)]),
    dict(id="weave", root="Weave", name="The Weave's Edge",
         prev="emberscar", prevpc="Emberscar", nxt="warlord", nxtpc="Warlord",
         enemies=[("celestial_hare",5),("astral_slime",5)]),
    dict(id="warlord", root="Warlord", name="The Sundered Heart",
         prev="weave", prevpc="Weave", nxt=None, nxtpc=None,
         enemies=[("eternal_warlord",1)]),
]

PORTAL_BLOCK = (
    '[ext_resource type="PackedScene" path="res://scenes/Gameplay/portal.tscn" id="4_q3nul"]'
)

def portal_nodes(m):
    """Return the replacement text for the template's single portal+marker block."""
    out = []
    # Back portal -> prev
    out.append('[node name="PortalTo%s" parent="." instance=ExtResource("4_q3nul")]' % m["prevpc"])
    out.append('position = Vector2(-520, 16)')
    out.append('target_map_id = "%s"' % m["prev"])
    out.append('target_spawn_point_name = "%s_%s_Portal_Spawn"' % (m["prevpc"], m["root"]))
    out.append('')
    out.append('[node name="%s_%s_Portal_Spawn" type="Marker2D" parent="."]' % (m["root"], m["prevpc"]))
    out.append('position = Vector2(-450, 16)')
    out.append('')
    if m["nxt"]:
        out.append('[node name="PortalTo%s" parent="." instance=ExtResource("4_q3nul")]' % m["nxtpc"])
        out.append('position = Vector2(520, 16)')
        out.append('target_map_id = "%s"' % m["nxt"])
        out.append('target_spawn_point_name = "%s_%s_Portal_Spawn"' % (m["nxtpc"], m["root"]))
        out.append('')
        out.append('[node name="%s_%s_Portal_Spawn" type="Marker2D" parent="."]' % (m["root"], m["nxtpc"]))
        out.append('position = Vector2(450, 16)')
    return "\n".join(out)

def enemy_extres(m):
    keys = [k for k, _ in m["enemies"]]
    return "\n".join('[ext_resource type="PackedScene" path="%s" id="e_%s"]' % (ENEMY[k], k) for k in keys)

def enemy_nodes(m):
    out = []
    # spread enemies across x in [-360, 360] on the ground
    total = sum(c for _, c in m["enemies"])
    if total == 1:
        positions = [0]
    else:
        step = 720.0 / (total - 1)
        positions = [int(-360 + step * i) for i in range(total)]
    idx = 0
    n = 0
    for key, count in m["enemies"]:
        for c in range(count):
            n += 1
            name = pcs(key) + ("" if n == 1 else str(n))
            out.append('[node name="%s" parent="Enemies" instance=ExtResource("e_%s")]' % (name, key))
            out.append('position = Vector2(%d, 16)' % positions[idx])
            out.append('respawnable = true')
            out.append('')
            idx += 1
    return "\n".join(out)

template = io.open(TEMPLATE, encoding="utf-8").read()

# the template's portal+marker block we replace (exact text)
OLD_PORTAL = (
    '[node name="PortalToTargetMap" parent="." instance=ExtResource("4_q3nul")]\n'
    'target_map_id = "game2"\n'
    'target_spawn_point_name = "Game2_Game_Portal_Spawn"\n'
    '\n'
    '[node name="CurrentMap_TargetMap_Portal_Spawn" type="Marker2D" parent="."]'
)
assert OLD_PORTAL in template, "template portal block not found — template changed?"

for m in MAPS:
    t = template
    # 1) display name
    t = t.replace('display_name = "New Wild"', 'display_name = "%s"' % m["name"])
    # 2) portals/markers
    t = t.replace(OLD_PORTAL, portal_nodes(m))
    # 3) enemy ext_resources — insert right after the global_drop_handler ext_resource
    anchor = '[ext_resource type="Script" uid="uid://igk1rxt26f2i" path="res://scripts/UI/global_drop_handler.gd" id="15_2xd81"]'
    assert anchor in t
    t = t.replace(anchor, anchor + "\n" + enemy_extres(m))
    # 4) enemy nodes — append at end (parent="Enemies" already declared)
    t = t.rstrip() + "\n\n" + enemy_nodes(m) + "\n"
    # 5) recompute load_steps = #ext_resource + #sub_resource + 1
    n_ext = len(re.findall(r'^\[ext_resource ', t, re.M))
    n_sub = len(re.findall(r'^\[sub_resource ', t, re.M))
    t = re.sub(r'load_steps=\d+', 'load_steps=%d' % (n_ext + n_sub + 1), t, count=1)
    # remove the template's uid so each new scene gets a fresh one assigned by Godot
    t = re.sub(r'\s+uid="uid://[a-z0-9]+"', '', t, count=1)
    out_path = os.path.join(ROOT, "scenes/Levels/%s.tscn" % m["id"])
    io.open(out_path, "w", encoding="utf-8", newline="\n").write(t)
    print("wrote", out_path, "(%d enemies)" % sum(c for _, c in m["enemies"]))

print("done")
