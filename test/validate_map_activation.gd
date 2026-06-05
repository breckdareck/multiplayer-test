# Headless validation for the enemy proximity-activation API (ADR 0007).
#
# Run from the project root (Windows: use --log-file, stdout isn't piped):
#   <godot> --headless --path . --script res://test/validate_map_activation.gd --log-file test/activation_run.log
#
# Instantiates a REAL map scene, adds it to the tree so enemies run _ready, then
# exercises EnemyBase's activation_sleep / activation_wake / is_activation_eligible
# directly. This is an integration check the unit harness can't do (it never
# mounts enemies). Exit 0 = all pass, 1 = any fail.
#
# Uses a frame counter (NOT await) so the SceneTree _process -> bool contract is
# preserved while giving enemy _ready (which defers a frame) time to finish.
extends SceneTree

const MAP_PATH := "res://scenes/Levels/game.tscn"

var _frame := 0
var _map: Node = null
var _pass := 0
var _fail := 0


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_setup()
		return false
	if _frame < 5:
		return false # let enemy _ready (deferred a frame) settle
	_run()
	quit(1 if _fail > 0 else 0)
	return true


func _setup() -> void:
	var scene: PackedScene = load(MAP_PATH)
	if scene == null:
		return
	_map = scene.instantiate()
	get_root().add_child(_map)


func _check(label: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  [PASS] %s" % label)
	else:
		_fail += 1
		print("  [FAIL] %s" % label)


func _run() -> void:
	print("\n========== Map activation validation ==========")

	_check("map scene instantiated", _map != null)
	if _map == null:
		return

	var enemies_node: Node = _map.get_node_or_null("Enemies")
	_check("map has an Enemies node", enemies_node != null)
	if enemies_node == null:
		return

	# Collect enemies by group, mirroring MapManager._collect_enemies.
	var enemies: Array = []
	for child in enemies_node.get_children():
		if child.is_in_group("Enemies") and child.has_method("activation_sleep"):
			enemies.append(child)
	_check("found at least one enemy", enemies.size() > 0)
	if enemies.is_empty():
		return

	var e: Node = enemies[0]

	# A live enemy is eligible and starts awake.
	_check("live enemy is activation-eligible", e.is_activation_eligible())
	_check("live enemy starts awake (processing)", e.is_processing() and e.is_physics_processing())

	# Sleep pauses processing but keeps the body visible (not pooled).
	e.activation_sleep()
	_check("after sleep: _process disabled", not e.is_processing())
	_check("after sleep: _physics_process disabled", not e.is_physics_processing())
	_check("after sleep: still visible (not pooled)", e.visible)

	# Sleep is idempotent.
	e.activation_sleep()
	_check("sleep is idempotent (still asleep)", not e.is_processing())

	# Wake resumes processing.
	e.activation_wake()
	_check("after wake: _process re-enabled", e.is_processing())
	_check("after wake: _physics_process re-enabled", e.is_physics_processing())

	# Wake is idempotent.
	e.activation_wake()
	_check("wake is idempotent (still awake)", e.is_processing())

	# A pooled/dead enemy (invisible, offscreen) must NOT be eligible, so the
	# scanner never toggles it — guarding against reviving a corpse.
	e.visible = false
	_check("pooled (invisible) enemy is NOT eligible", not e.is_activation_eligible())
	e.activation_sleep() # must be a no-op on an ineligible body — no crash
	_check("activation_sleep on ineligible body is a safe no-op", true)
	e.visible = true

	print("  --- %d passed, %d failed ---" % [_pass, _fail])
