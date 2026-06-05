extends SceneTree
## Headless nav-graph probe. Loads a real level, builds the bot nav graph with the
## real jump profile, and dumps edge counts + sample pathfinding between the
## lowest and highest surfaces — so we can see whether the graph actually has the
## up/down routes the bots need, without the live game.
##
## Run: godot --headless --path . --script res://test/nav/probe_navgraph.gd -- <level>
##   <level> defaults to game4.

const BotNavGraph = preload("res://scripts/Bot/bot_nav_graph.gd")

var _frames := 0
var _level: Node = null
var _level_path := "res://scenes/Levels/game4.tscn"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.ends_with(".tscn"):
			_level_path = a
		elif not a.is_empty():
			_level_path = "res://scenes/Levels/%s.tscn" % a


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		print("[probe] loading ", _level_path)
		var packed = load(_level_path)
		if packed == null:
			print("[probe] FAILED to load level")
			quit(1)
			return true
		_level = packed.instantiate()
		get_root().add_child(_level)
		return false
	# Give physics a few frames to register collision shapes in the space.
	if _frames < 6:
		return false
	_run()
	quit(0)
	return true


func _run() -> void:
	print("[probe] runtime gravity = ", ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
	# Count ladder/rope Area2Ds in the level (the intended vertical traversal).
	var ladders := _find_ladders(_level)
	print("[probe] ladders/ropes in level: ", ladders.size())
	for L in ladders:
		print("          ladder at %s" % str(L.global_position))
	# Sweep max_jump to see how connectivity responds — finds the calibration that
	# connects the playable platforms without me touching production code.
	print("[probe] --- max_jump sweep (reach=47) ---")
	for mj in [27.0, 32.0, 38.0, 45.0, 55.0]:
		var gg = BotNavGraph.new()
		gg.build(_level, mj, 47.0)
		var s2 = gg.get_stats()
		var comps = _component_sizes(gg)
		var bottom_i := 0
		for i in gg.points.size():
			if gg.points[i].y > gg.points[bottom_i].y:
				bottom_i = i
		var fwd := {}
		for key in gg.edges:
			if not fwd.has(key.x): fwd[key.x] = []
			fwd[key.x].append(key.y)
		var reach = _bfs(fwd, bottom_i).size()
		print("[probe]   max_jump=%.0f : jump=%d drop=%d  components=%s  bottom-reaches=%d/%d" % [
			mj, s2.jump, s2.drop, str(comps.slice(0, 5)), reach, gg.points.size()])

	var g = BotNavGraph.new()
	# Real player jump profile (jump_velocity -230, move_speed 100, grav 980).
	var ok = g.build(_level, 27.0, 47.0)
	print("[probe] built=", ok, " (max_jump=27, reach=47)")
	if not ok:
		print("[probe] graph build failed — no live physics world?")
		return
	var s = g.get_stats()
	print("[probe] surfaces=%d points=%d  edges=%d  walk=%d jump=%d drop=%d gap=%d" % [
		s.segments, s.points, s.edges, s.walk, s.jump, s.drop, s.gap])
	print("[probe] bounds=", s.bounds)

	if g.points.size() == 0:
		print("[probe] no points — nothing to path on")
		return

	# Find the lowest and highest graph points (y grows downward).
	var lowest_i := 0    # largest y = bottom of the map
	var highest_i := 0   # smallest y = top of the map
	for i in g.points.size():
		if g.points[i].y > g.points[lowest_i].y:
			lowest_i = i
		if g.points[i].y < g.points[highest_i].y:
			highest_i = i
	var low: Vector2 = g.points[lowest_i]
	var high: Vector2 = g.points[highest_i]
	print("[probe] lowest point=%s  highest point=%s  (dy=%.0f)" % [low, high, low.y - high.y])

	var up_path: PackedInt64Array = g.find_id_path(low, high)
	var down_path: PackedInt64Array = g.find_id_path(high, low)
	print("[probe] path LOW->HIGH (ascend): %d waypoints" % up_path.size())
	print("[probe] path HIGH->LOW (descend): %d waypoints" % down_path.size())

	_report_components(g)
	_report_directed(g, lowest_i, "BOTTOM")
	_dump_surfaces(g)


## Lists every surface (y, x-extent, solid/one-way) sorted top-to-bottom so the
## vertical structure is visible — to see where drops/jumps SHOULD connect.
func _dump_surfaces(g) -> void:
	var segs: Array = g.segments.duplicate()
	segs.sort_custom(func(a, b): return a.y < b.y)
	print("[probe] surfaces (top->bottom):")
	for seg in segs:
		print("          y=%5.0f  x=[%5.0f..%5.0f] w=%4.0f  %s" % [
			seg.y, seg.x_min, seg.x_max, seg.x_max - seg.x_min,
			"ONE-WAY" if seg.one_way else "solid"])


## All ladder/rope Area2Ds in the level (the `Ladder`-scripted Area2Ds).
func _find_ladders(node: Node, out: Array = []) -> Array:
	if node is Area2D and node.get_script() != null:
		var p: String = node.get_script().resource_path
		if p.ends_with("ladder.gd"):
			out.append(node)
	for c in node.get_children():
		_find_ladders(c, out)
	return out


## Sorted (desc) sizes of the weakly-connected components.
func _component_sizes(g) -> Array:
	var parent := {}
	for i in g.points.size():
		parent[i] = i
	var find := func(x):
		var root = x
		while parent[root] != root:
			root = parent[root]
		return root
	for key in g.edges:
		var ra = find.call(key.x)
		var rb = find.call(key.y)
		if ra != rb:
			parent[ra] = rb
	var sizes := {}
	for i in g.points.size():
		var r = find.call(i)
		sizes[r] = int(sizes.get(r, 0)) + 1
	var out: Array = sizes.values()
	out.sort()
	out.reverse()
	return out


## Weakly-connected components (treat every edge as undirected) — shows how many
## disconnected islands the graph shattered into and how big each is.
func _report_components(g) -> void:
	var parent := {}
	for i in g.points.size():
		parent[i] = i
	var find := func(x):
		var root = x
		while parent[root] != root:
			root = parent[root]
		return root
	for key in g.edges:
		var ra = find.call(key.x)
		var rb = find.call(key.y)
		if ra != rb:
			parent[ra] = rb
	var sizes := {}
	for i in g.points.size():
		var r = find.call(i)
		sizes[r] = int(sizes.get(r, 0)) + 1
	var comp_sizes := sizes.values()
	comp_sizes.sort()
	comp_sizes.reverse()
	print("[probe] weakly-connected components: %d (sizes: %s)" % [comp_sizes.size(), str(comp_sizes.slice(0, 10))])

	# For the two LARGEST components, find the closest pair of points across them —
	# the smallest gap a bridging edge (jump up / drop down / ladder) would span.
	var roots_by_size := {}
	for i in g.points.size():
		var r = find.call(i)
		if not roots_by_size.has(r): roots_by_size[r] = []
		roots_by_size[r].append(i)
	var ordered := roots_by_size.keys()
	ordered.sort_custom(func(a, b): return roots_by_size[a].size() > roots_by_size[b].size())
	if ordered.size() < 2:
		return
	var a_pts: Array = roots_by_size[ordered[0]]
	var b_pts: Array = roots_by_size[ordered[1]]
	var best := INF
	var best_a := Vector2.ZERO
	var best_b := Vector2.ZERO
	for ia in a_pts:
		var pa: Vector2 = g.points[ia]
		for ib in b_pts:
			var pb: Vector2 = g.points[ib]
			var d := pa.distance_to(pb)
			if d < best:
				best = d
				best_a = pa
				best_b = pb
	print("[probe] closest gap between the 2 biggest islands: %.0f px  (dx=%.0f dy=%.0f)  %s <-> %s" % [
		best, absf(best_a.x - best_b.x), absf(best_a.y - best_b.y), best_a, best_b])


## Directed reachability (respecting JUMP=up / DROP=down direction) from a start
## point: how many points can the bot actually travel to, and back.
func _report_directed(g, start_i: int, label: String) -> void:
	var fwd := {}    # from -> [to,...]
	var rev := {}
	for key in g.edges:
		if not fwd.has(key.x): fwd[key.x] = []
		fwd[key.x].append(key.y)
	var reach_fwd := _bfs(fwd, start_i)
	print("[probe] from %s point: can REACH %d / %d points (directed)" % [label, reach_fwd.size(), g.points.size()])


func _bfs(adj: Dictionary, start: int) -> Dictionary:
	var seen := {start: true}
	var queue := [start]
	while not queue.is_empty():
		var n = queue.pop_back()
		for m in adj.get(n, []):
			if not seen.has(m):
				seen[m] = true
				queue.append(m)
	return seen


## For each surface, is it reachable from the bottom-most point via A*? Lists the
## unreachable ones (these are the platforms bots can never get to).
func _report_reachability(g, from_i: int) -> void:
	var from_pos: Vector2 = g.points[from_i]
	var unreachable_surfaces := {}
	var checked_segments := {}
	for i in g.points.size():
		var seg: int = g.point_segment[i]
		if checked_segments.has(seg):
			continue
		checked_segments[seg] = true
		var path: PackedInt64Array = g.find_id_path(from_pos, g.points[i])
		if path.size() == 0 and g.points[i] != from_pos:
			unreachable_surfaces[seg] = g.points[i]
	if unreachable_surfaces.is_empty():
		print("[probe] reachability: ALL surfaces reachable from the bottom ✓")
	else:
		print("[probe] reachability: %d surface(s) UNREACHABLE from the bottom:" % unreachable_surfaces.size())
		for seg in unreachable_surfaces:
			print("          seg %d near %s" % [seg, unreachable_surfaces[seg]])
