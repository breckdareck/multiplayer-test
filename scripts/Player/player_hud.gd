extends Node

var player: MultiplayerPlayer

@onready var health_bar: TextureProgressBar = $BottomStatsContainer/HealthBar
@onready var hp_value_label: Label = $BottomStatsContainer/HealthBar/HPValueLabel

@onready var mana_bar: TextureProgressBar = $BottomStatsContainer/ManaBar
@onready var mp_value_label: Label = $BottomStatsContainer/ManaBar/MPValueLabel

@onready var experience_bar: TextureProgressBar = $BottomStatsContainer/ExperienceBar
@onready var exp_percent_label: RichTextLabel = $BottomStatsContainer/ExperienceBar/EXPPercentLabel

@onready var level_label: RichTextLabel = $BottomStatsContainer/ExperienceBar/LevelPanel/LevelLabel


func _ready() -> void:
	player = self.owner as MultiplayerPlayer
	health_bar.max_value = player.health_component.max_health
	health_bar.value = player.health_component.current_health
	hp_value_label.text = str(player.health_component.current_health) + "/" + str(player.health_component.max_health)
	
	experience_bar.value = player.level_component.experience
	experience_bar.max_value = player.level_component.get_exp_to_next_level()
	exp_percent_label.text = "%0.2f" % (float(player.level_component.experience)/player.level_component.get_exp_to_next_level()*100) + "%"
	
	player.health_component.health_changed.connect(_on_health_changed)
	player.level_component.experience_changed.connect(_on_experience_changed)
	player.level_component.leveled_up.connect(_on_level_changed)


func _on_health_changed(new_health: int, _max_health: int) -> void:
	"""Updates the ProgressBar value when health changes."""
	health_bar.max_value = _max_health
	health_bar.value = new_health
	hp_value_label.text = str(player.health_component.current_health) + "/" + str(player.health_component.max_health)


func _on_experience_changed(new_value: int, _exp_to_level: int) -> void:
	experience_bar.max_value = _exp_to_level
	experience_bar.value = new_value
	exp_percent_label.text = "%0.2f" % (float(player.level_component.experience)/player.level_component.get_exp_to_next_level()*100) + "%"


func _on_level_changed(new_value: int) -> void:
	level_label.text = "LV.[color=yellow]%s[/color]" % str(new_value)
