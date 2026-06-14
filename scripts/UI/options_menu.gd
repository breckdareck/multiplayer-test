extends PanelContainer
class_name OptionsMenu

signal back_pressed

@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SfxSlider
@onready var screen_shake_checkbox: CheckBox = %ScreenShakeCheckBox
@onready var chat_text_size_slider: HSlider = %ChatTextSizeSlider
@onready var chat_text_size_value: Label = %ChatTextSizeValue
@onready var back_button: Button = %BackButton

var master_bus_idx: int
var music_bus_idx: int
var sfx_bus_idx: int

func _ready():
	back_button.pressed.connect(func(): back_pressed.emit())
	visible = false # Start hidden

	master_bus_idx = AudioServer.get_bus_index("Master")
	music_bus_idx = AudioServer.get_bus_index("Music")
	sfx_bus_idx = AudioServer.get_bus_index("SFX")

	# Initialize slider values
	master_slider.value = db_to_linear(UserConfig.master_volume_db)
	music_slider.value = db_to_linear(UserConfig.music_volume_db)
	sfx_slider.value = db_to_linear(UserConfig.sfx_volume_db)
	screen_shake_checkbox.button_pressed = UserConfig.screen_shake_enabled
	chat_text_size_slider.value = UserConfig.chat_text_size
	chat_text_size_value.text = str(UserConfig.chat_text_size)


	# Connect slider signals
	master_slider.value_changed.connect(_on_master_slider_value_changed)
	music_slider.value_changed.connect(_on_music_slider_value_changed)
	sfx_slider.value_changed.connect(_on_sfx_slider_value_changed)
	screen_shake_checkbox.toggled.connect(_on_screen_shake_toggled)
	chat_text_size_slider.value_changed.connect(_on_chat_text_size_changed)

func show_menu():
	visible = true

func hide_menu():
	visible = false

func _on_master_slider_value_changed(value: float):
	UserConfig.set_master_volume(_slider_to_db(value))

func _on_music_slider_value_changed(value: float):
	UserConfig.set_music_volume(_slider_to_db(value))

func _on_sfx_slider_value_changed(value: float):
	UserConfig.set_sfx_volume(_slider_to_db(value))


## Convert a 0..1 slider position to dB WITHOUT ever producing linear_to_db(0) == -INF
## (which silences the bus unrecoverably). Full-left lands on the silence floor — a
## finite, audibly-silent value the slider can still climb back out of.
func _slider_to_db(value: float) -> float:
	if value <= 0.0:
		return UserConfig.MIN_VOLUME_DB
	return maxf(UserConfig.MIN_VOLUME_DB, linear_to_db(value))

func _on_screen_shake_toggled(button_pressed: bool):
	UserConfig.set_screen_shake_enabled(button_pressed)

func _on_chat_text_size_changed(value: float):
	UserConfig.set_chat_text_size(int(value))
	chat_text_size_value.text = str(int(value))
