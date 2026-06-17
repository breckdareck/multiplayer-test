extends SceneTree
## Rebuild mines.tscn ropes as SHORT climbs: each platform/perch gets one rope hanging from it
## down to ~2 tiles above the surface directly below (a jump-and-grab gap, never touching down).
## One way up per platform, no long ropes threading multiple tiers. Rope = Area2D +
## RectangleShape2D (climb zone) + NinePatchRect (visual) + ladder.gd (ext "9_rrhmt"), reusing
## AtlasTexture_p47w5. Each entry is [col, top_row, bottom_row] (bottom hangs above the lower level).
const MAP := "res://scenes/Levels/mines.tscn"
const ROPES := [
	# floor (row 26) -> row-22 tier: hang to row 24 (2-tile jump gap)
	[33, 22, 24], [73, 22, 24], [113, 22, 24],
	# row-22 -> row-17 tier: hang to row 20. Right one at col 120 (off perchC, which is 121-124).
	[27, 17, 20], [65, 17, 20], [120, 17, 20],
	# P17c has no row-22 platform under it -> reaches down toward the floor (row 24)
	[93, 17, 24],
	# row-17 -> row-12 tier: hang to row 15. Right one at col 120 so it doesn't cross perchC.
	[27, 12, 15], [65, 12, 15], [120, 12, 15],
	# row-17 -> row-14 rest perches: hang to row 15 (2-tile gap, was touching at 16). Right perch
	# rope at col 124 so the right perch's access is clear of the col-120 tier climb.
	[21, 14, 15], [90, 14, 15], [131, 14, 15],
]

func _init() -> void:
	var f := FileAccess.open(MAP, FileAccess.READ); var text := f.get_as_text(); f.close()

	# Fresh collision-shape sub_resources, one per distinct rope height.
	text = _strip_subs(text, "RopeShape")
	var heights := {}
	for r in ROPES: heights[(r[2] - r[1]) * 16] = true
	var subs := ""
	for h in heights: subs += '[sub_resource type="RectangleShape2D" id="RopeShape%d"]\nsize = Vector2(4, %d)\n\n' % [h, h]
	var fn := text.find("\n[node ") + 1
	text = text.substr(0, fn) + subs + text.substr(fn)

	var body := ""; var n := 0
	for r in ROPES:
		var col: int = r[0]; var tr: int = r[1]; var br: int = r[2]
		var x: int = col * 16 - 111
		var ytop: int = tr * 16 - 269; var ybot: int = br * 16 - 269
		var h: int = ybot - ytop; var yc: int = (ytop + ybot) / 2
		var nm := "R%d" % n
		body += '\n[node name="%s" type="Area2D" parent="Ropes"]\n' % nm
		body += 'position = Vector2(%d, %d)\n' % [x, yc]
		body += 'collision_layer = 0\ncollision_mask = 2\nscript = ExtResource("9_rrhmt")\n\n'
		body += '[node name="CollisionShape2D" type="CollisionShape2D" parent="Ropes/%s"]\n' % nm
		body += 'shape = SubResource("RopeShape%d")\n\n' % h
		body += '[node name="NinePatchRect" type="NinePatchRect" parent="Ropes/%s"]\n' % nm
		body += 'offset_left = -2.0\noffset_top = %d.0\noffset_right = 2.0\noffset_bottom = %d.0\n' % [-h / 2, h / 2]
		body += 'texture = SubResource("AtlasTexture_p47w5")\npatch_margin_top = 2\npatch_margin_bottom = 2\naxis_stretch_vertical = 1\n'
		n += 1

	var rs := text.find('[node name="Ropes" type="Node2D" parent="."]')
	var hdr_end := text.find("\n", rs) + 1
	var scan := hdr_end; var next_top := -1
	while true:
		var ni := text.find("\n[node ", scan)
		if ni == -1: break
		var le := text.find("]", ni)
		if 'parent="."]' in text.substr(ni + 1, le - ni):
			next_top = ni + 1; break
		scan = ni + 1
	if next_top == -1: print("NO NEXT TOP NODE"); quit(); return
	text = text.substr(0, hdr_end) + body + "\n" + text.substr(next_top)

	var w := FileAccess.open(MAP, FileAccess.WRITE); w.store_string(text); w.close()
	print("OK wrote ", n, " short ropes")
	quit()

# Remove every RectangleShape2D sub_resource whose id starts with `prefix`.
func _strip_subs(text: String, prefix: String) -> String:
	while true:
		var i := text.find('[sub_resource type="RectangleShape2D" id="' + prefix)
		if i == -1: break
		var endb := text.find("\n\n", i)
		endb = text.length() if endb == -1 else endb + 2
		text = text.substr(0, i) + text.substr(endb)
	return text
