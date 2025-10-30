extends PanelContainer
class_name OptionsMenu

signal back_pressed

@onready var master_slider: HSlider = %MasterSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sfx_slider: HSlider = %SfxSlider
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


	# Connect slider signals
	master_slider.value_changed.connect(_on_master_slider_value_changed)
	music_slider.value_changed.connect(_on_music_slider_value_changed)
	sfx_slider.value_changed.connect(_on_sfx_slider_value_changed)

func show_menu():
	visible = true

func hide_menu():
	visible = false

func _on_master_slider_value_changed(value: float):
	UserConfig.set_master_volume(linear_to_db(value))

func _on_music_slider_value_changed(value: float):
	UserConfig.set_music_volume(linear_to_db(value))

func _on_sfx_slider_value_changed(value: float):
	UserConfig.set_sfx_volume(linear_to_db(value))
