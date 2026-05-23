class_name QuestRewardPopup
extends Control

## Showcase popup that fires when a quest completes. Replaces the 3-5 chat
## lines (+50 EXP, +10 Coins, +Item ...) with a single centered card the
## player can't miss. The chat still gets one concise scroll-back summary
## line — this is the visual celebration on top of that.
##
## Non-modal (mouse_filter = IGNORE everywhere) and self-frees when the
## tween completes. Positioned ~25% from the top so it doesn't overlap the
## player or the quest tracker (which lives in the top-right).

const THEME_PATH: String = "res://assets/themes/UI_Theme.tres"

const FADE_IN: float = 0.35
const HOLD: float = 2.2
const FADE_OUT: float = 0.55

const COLOR_GOLD: Color = Color(1.0, 0.85, 0.35)
const COLOR_EXP: Color = Color(0.55, 0.95, 0.55)
const COLOR_ITEM: Color = Color(0.7, 0.85, 1.0)

var _quest_name: String = ""
var _reward_exp: int = 0
var _reward_coins: int = 0
var _reward_items: Array = []


## Call before add_child().
func setup(quest_name: String, exp_amount: int, coins_amount: int, items: Array) -> void:
	_quest_name = quest_name
	_reward_exp = exp_amount
	_reward_coins = coins_amount
	_reward_items = items.duplicate() if items else []


func _ready() -> void:
	# Full-HUD root, click-through.
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS

	_build_and_play()


func _build_and_play() -> void:
	# Card anchored top-center: anchors fix x to the parent's horizontal
	# midpoint, top is at 22% from the top of the HUD. grow_vertical = END
	# lets the PanelContainer auto-extend downward for content.
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(360, 0)
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.22
	card.anchor_bottom = 0.22
	card.offset_left = -180.0
	card.offset_right = 180.0
	card.offset_top = 0.0
	card.offset_bottom = 0.0
	card.grow_vertical = Control.GROW_DIRECTION_END
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var ui_theme: Theme = load(THEME_PATH)
	if ui_theme:
		card.theme = ui_theme

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.09, 0.12, 0.95)
	bg.border_color = COLOR_GOLD
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(4)
	bg.content_margin_left = 18.0
	bg.content_margin_right = 18.0
	bg.content_margin_top = 14.0
	bg.content_margin_bottom = 14.0
	card.add_theme_stylebox_override("panel", bg)

	add_child(card)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 6)
	card.add_child(vbox)

	var header := Label.new()
	header.text = "Quest Complete!"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_color_override("font_color", COLOR_GOLD)
	header.add_theme_font_size_override("font_size", 18)
	vbox.add_child(header)

	var name_label := Label.new()
	name_label.text = _quest_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92))
	name_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(name_label)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	if _reward_exp > 0:
		_add_reward_row(vbox, "+ %d EXP" % _reward_exp, COLOR_EXP)
	if _reward_coins > 0:
		_add_reward_row(vbox, "+ %d Coins" % _reward_coins, COLOR_GOLD)
	for item_name in _reward_items:
		_add_reward_row(vbox, "+ %s" % str(item_name), COLOR_ITEM)

	# Fade in / hold / fade out.
	modulate.a = 0.0
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, FADE_IN)
	tween.tween_interval(HOLD)
	tween.tween_property(self, "modulate:a", 0.0, FADE_OUT)
	tween.tween_callback(queue_free)


func _add_reward_row(parent: VBoxContainer, text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 14)
	parent.add_child(label)
