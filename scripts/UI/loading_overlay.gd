extends CanvasLayer

@onready var label: Label = %LoadingLabel
var _safety_timer: Timer

func _ready():
	visible = false
	_safety_timer = Timer.new()
	_safety_timer.one_shot = true
	_safety_timer.wait_time = 15.0
	_safety_timer.timeout.connect(_on_safety_timeout)
	add_child(_safety_timer)

func show_loading(map_name: String = ""):
	if map_name.is_empty():
		label.text = "Loading..."
	else:
		label.text = "Loading %s..." % map_name
	visible = true
	_safety_timer.start()

func hide_loading():
	visible = false
	_safety_timer.stop()

func _on_safety_timeout():
	push_warning("LoadingOverlay: Safety timeout — hiding stuck overlay")
	hide_loading()
