extends Control

@onready var label: Label = $Label

var is_fading_out = false

func set_text(text: String, color: Color) -> void:
	label.text = text
	label.modulate = color

func fade_in():
	modulate.a = 0.0
	var tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.3)

func fade_out():
	if is_fading_out:
		return
	is_fading_out = true
	var tween = create_tween().set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	await tween.finished
	queue_free()
