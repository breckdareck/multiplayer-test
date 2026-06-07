@tool
class_name WeaponToolingPanel
extends Control

## Single bottom-panel home for the cross-cutting weapon-content tools, replacing
## the three separate popup Windows + their dock buttons. Tabs: Tree Board,
## Problems, Batch. "Jump to resource" opens the target in the native Inspector
## via EditorInterface (no dependency on the legacy dock).

var _tabs: TabContainer
var _board: DisciplineBoard
var _problems: ValidationDashboard
var _batch: BatchEditWindow


func _init() -> void:
	custom_minimum_size = Vector2(0, 380)
	_tabs = TabContainer.new()
	_tabs.anchor_right = 1.0
	_tabs.anchor_bottom = 1.0
	add_child(_tabs)

	_board = DisciplineBoard.new()
	_board.name = "Tree Board"
	_tabs.add_child(_board)

	_problems = ValidationDashboard.new()
	_problems.name = "Problems"
	_problems.jump_requested.connect(_on_jump)
	_tabs.add_child(_problems)

	_batch = BatchEditWindow.new()
	_batch.name = "Batch"
	_tabs.add_child(_batch)

	_tabs.tab_changed.connect(func(_i): _refresh_active())
	visibility_changed.connect(func(): if visible: _refresh_active())


func _ready() -> void:
	_batch.setup()


func _refresh_active() -> void:
	var cur := _tabs.get_current_tab_control()
	if cur and cur.has_method("refresh"):
		cur.refresh()


func _on_jump(path: String) -> void:
	if path.is_empty():
		return
	var res = load(path)
	if res == null:
		return
	EditorInterface.edit_resource(res)
	var fsd = EditorInterface.get_file_system_dock()
	if fsd and fsd.has_method("navigate_to_path"):
		fsd.navigate_to_path(path)
