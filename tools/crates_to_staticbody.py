#!/usr/bin/env python3
"""Convert the static crate platforms from AnimatableBody2D to StaticBody2D.

The crate one-way platforms in the level scenes are AnimatableBody2D but never
move (no anim_player wired, no AnimationPlayer). AnimatableBody2D is for MOVING
platforms: it's a kinematic body processed every physics frame with
`sync_to_physics`, and its one-way collision path is less reliable for fast
fallers than a StaticBody2D (the canonical one-way platform). Under heavy load
(many falling bots) this let bodies tunnel even with a generous
one_way_collision_margin. StaticBody2D lives in the static broadphase, is cheaper,
and gives the most robust one-way collision.

For each scene: AnimatableBody2D -> StaticBody2D, and drop the (now type-mismatched)
platform.gd script line from those nodes. The one-way CollisionShape2D + margin are
untouched. Idempotent. Run: python tools/crates_to_staticbody.py
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# scene -> ext_resource id of res://scripts/Gameplay/platform.gd in that scene
TARGETS = {
    "scenes/Levels/game.tscn": "11_kgokg",
    "scenes/Levels/game4.tscn": "8_u8wq7",
}

for rel, script_id in TARGETS.items():
    path = ROOT / rel
    text = path.read_text(encoding="utf-8")
    bodies = text.count('type="AnimatableBody2D"')
    text = text.replace('type="AnimatableBody2D"', 'type="StaticBody2D"')
    script_line = 'script = ExtResource("%s")' % script_id
    kept = [ln for ln in text.split("\n") if ln.strip() != script_line]
    removed = text.count("\n") + 1 - len(kept)
    path.write_text("\n".join(kept), encoding="utf-8")
    print("%s: converted %d AnimatableBody2D -> StaticBody2D, removed %d platform-script line(s)" % (
        rel, bodies, removed))
print("Done.")
