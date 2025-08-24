extends PanelContainer
class_name Slot

@onready var texture_rect: TextureRect = $TextureRect
@onready var label: Label = $Label

@export var item: Item = null:
	set(value):
		item = value
		
		if value != null:
			texture_rect.texture = value.icon
		else:
			texture_rect.texture = null


func get_preview():
	var preview_texture = TextureRect.new()
	preview_texture.texture = texture_rect.texture
	preview_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_texture.custom_minimum_size = Vector2(55,55)
	
	var preview = Control.new()
	preview.add_child(preview_texture)
	preview_texture.position = -.5 * Vector2(55,55)
	
	return preview


func _get_drag_data(_at_position):
	if item == null:
		return
	set_drag_preview(get_preview())
	return self

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return data is Slot
	
func _drop_data(at_position: Vector2, data: Variant) -> void:
	var temp = item
	item = data.item
	data.item = temp
