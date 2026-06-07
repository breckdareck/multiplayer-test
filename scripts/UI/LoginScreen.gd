extends Control

@onready var username_input = $Panel/VBoxContainer/UsernameInput
@onready var password_input = $Panel/VBoxContainer/PasswordInput
@onready var login_button = $Panel/VBoxContainer/LoginButton
@onready var register_button = $Panel/VBoxContainer/RegisterButton
@onready var dev_login_button = $Panel/VBoxContainer/DevLoginButton
@onready var local_save_checkbox = $Panel/VBoxContainer/LocalSaveCheckbox
@onready var status_label = $Panel/VBoxContainer/StatusLabel

# Backend settings (from scene)
@onready var backend_settings_button = $Panel/VBoxContainer/BackendSettingsButton
@onready var preset_label = $Panel/VBoxContainer/PresetLabel
@onready var preset_button_box = $Panel/VBoxContainer/PresetButtonBox
@onready var local_button = $Panel/VBoxContainer/PresetButtonBox/LocalButton
@onready var cloud_button = $Panel/VBoxContainer/PresetButtonBox/CloudButton
@onready var api_url_input = $Panel/VBoxContainer/APIUrlInput
@onready var apply_button = $Panel/VBoxContainer/ApplyButton
@onready var api_status_label = $Panel/VBoxContainer/APIStatusLabel

# Dev fast-path UI (authored in the scene; debug-only — hidden in release).
@onready var _dev_nodes := [
	$Panel/VBoxContainer/DevSeparator,
	$Panel/VBoxContainer/DevLabel,
	$Panel/VBoxContainer/DevRow,
]
@onready var dev_sword_button = $Panel/VBoxContainer/DevRow/DevSwordButton
@onready var dev_bow_button = $Panel/VBoxContainer/DevRow/DevBowButton
@onready var dev_staff_button = $Panel/VBoxContainer/DevRow/DevStaffButton
@onready var dev_dagger_button = $Panel/VBoxContainer/DevRow/DevDaggerButton

var settings_expanded: bool = false

# Presets for quick switching
var api_presets = {
	"Local": "http://127.0.0.1:5000/api",
	"Cloud": "http://72.84.198.233:5000/api",
}

func _ready():
	login_button.pressed.connect(_on_login_pressed)
	register_button.pressed.connect(_on_register_pressed)
	dev_login_button.pressed.connect(_on_dev_login_pressed)
	local_save_checkbox.toggled.connect(_on_local_save_toggled)
	
	backend_settings_button.pressed.connect(_toggle_backend_settings)
	local_button.pressed.connect(_on_preset_selected.bind("Local"))
	cloud_button.pressed.connect(_on_preset_selected.bind("Cloud"))
	apply_button.pressed.connect(_on_apply_api_url)
	
	NetworkManager.login_success.connect(_on_login_success)
	NetworkManager.login_failed.connect(_on_login_failed)
	NetworkManager.registration_success.connect(_on_registration_success)
	NetworkManager.registration_failed.connect(_on_registration_failed)
	
	_setup_backend_display()
	_setup_dev_ui()
	_play_intro()

	if MultiplayerManager.disconnect_reason != "":
		status_label.text = MultiplayerManager.disconnect_reason
		status_label.add_theme_color_override("font_color", Color.RED)
		MultiplayerManager.disconnect_reason = ""


var _health_request: HTTPRequest = null

func _setup_backend_display():
	api_url_input.text = UserConfig.get_backend_api_url()
	api_status_label.text = "API URL: %s (checking...)" % UserConfig.get_backend_api_url()
	_health_request = HTTPRequest.new()
	_health_request.request_completed.connect(_on_health_check_completed)
	add_child(_health_request)
	_check_backend_health()

func _check_backend_health():
	var base_url = UserConfig.get_backend_api_url().replace("/api", "")
	var error = _health_request.request(base_url + "/health")
	if error != OK:
		_update_backend_status(false)

func _on_health_check_completed(_result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray):
	_update_backend_status(response_code == 200)

func _update_backend_status(online: bool):
	var url = UserConfig.get_backend_api_url()
	if online:
		api_status_label.text = "API URL: %s (Online)" % url
		api_status_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		api_status_label.text = "API URL: %s (Offline)" % url
		api_status_label.add_theme_color_override("font_color", Color.RED)


func _toggle_backend_settings():
	settings_expanded = !settings_expanded
	preset_label.visible = settings_expanded
	preset_button_box.visible = settings_expanded
	api_url_input.visible = settings_expanded
	apply_button.visible = settings_expanded
	backend_settings_button.text = "Backend Settings ▼" if settings_expanded else "Backend Settings ▶"


func _on_preset_selected(preset_name: String):
	var preset_url = api_presets[preset_name]
	
	if preset_url.is_empty():
		status_label.text = "Please configure Cloud URL first"
		status_label.add_theme_color_override("font_color", Color.YELLOW)
		return
	
	# Apply the preset. NetworkManager.api_url is a computed getter that reads
	# from UserConfig, so updating UserConfig is what makes the change take effect.
	UserConfig.set_backend_api_url(preset_url)
	api_url_input.text = preset_url
	_check_backend_health()

	status_label.text = "Switched to %s backend" % preset_name
	status_label.add_theme_color_override("font_color", Color.GREEN)
	_toggle_backend_settings()  # Collapse the settings


func _on_apply_api_url():
	var new_url = api_url_input.text.strip_edges()
	if new_url.is_empty():
		status_label.text = "API URL cannot be empty"
		status_label.add_theme_color_override("font_color", Color.RED)
		return
	
	# Basic validation
	if not new_url.begins_with("http://") and not new_url.begins_with("https://"):
		status_label.text = "API URL must start with http:// or https://"
		status_label.add_theme_color_override("font_color", Color.RED)
		return
	
	# NetworkManager.api_url is a computed getter that reads from UserConfig,
	# so updating UserConfig is what makes the change take effect.
	UserConfig.set_backend_api_url(new_url)
	api_presets["Cloud"] = new_url  # Save as Cloud preset
	_check_backend_health()

	status_label.text = "Backend API URL updated!"
	status_label.add_theme_color_override("font_color", Color.GREEN)
	_toggle_backend_settings()  # Collapse the settings


func _on_login_pressed():
	var user = username_input.text
	var passw = password_input.text
	if user == "" or passw == "":
		status_label.text = "Please enter username and password."
		return
		
	status_label.text = "Logging in..."
	status_label.add_theme_color_override("font_color", Color.WHITE)
	NetworkManager.login(user, passw)

func _on_register_pressed():
	var user = username_input.text
	var passw = password_input.text
	if user == "" or passw == "":
		status_label.text = "Please enter username and password."
		return
		
	status_label.text = "Registering..."
	status_label.add_theme_color_override("font_color", Color.WHITE)
	NetworkManager.register(user, passw)

func _on_dev_login_pressed():
	status_label.text = "Logging in as Dev..."
	status_label.add_theme_color_override("font_color", Color.WHITE)
	NetworkManager.dev_login()

func _on_local_save_toggled(toggled_on: bool):
	NetworkManager.use_local_save = toggled_on
	if toggled_on:
		status_label.text = "Local Save Enabled"
		status_label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		status_label.text = "Local Save Disabled"
		status_label.add_theme_color_override("font_color", Color.WHITE)

func _on_login_success(_account_id, _username):
	status_label.text = "Login Successful!"
	status_label.add_theme_color_override("font_color", Color.GREEN)
	# Transition to Character Select
	get_tree().change_scene_to_file("res://scenes/UI/CharacterSelectScreen.tscn")

func _on_login_failed(error):
	status_label.text = "Login Failed: " + error
	status_label.add_theme_color_override("font_color", Color.RED)

func _on_registration_success(_account_id):
	status_label.text = "Registration Successful! Please Login."
	status_label.add_theme_color_override("font_color", Color.GREEN)

func _on_registration_failed(error):
	status_label.text = "Registration Failed: " + error
	status_label.add_theme_color_override("font_color", Color.RED)


# ============================================================================
# DEV FAST-PATH — skip login + character select, host offline with a max-level
# character straight into the combat map. Debug builds only.
# ============================================================================

const _DEV_USERNAME := "DevMax"
const _DEV_DISCIPLINES := [
	[Constants.ClassType.SWORD, "Sword"],
	[Constants.ClassType.BOW, "Bow"],
	[Constants.ClassType.STAFF, "Staff"],
	[Constants.ClassType.DAGGER, "Dagger"],
]

## Wires the scene-authored dev "skip to combat" buttons and hides the whole
## section in non-debug builds so it never ships in a release.
func _setup_dev_ui() -> void:
	var dbg := OS.is_debug_build()
	for n in _dev_nodes:
		if is_instance_valid(n):
			n.visible = dbg
	if not dbg:
		return
	dev_sword_button.pressed.connect(_on_dev_skip_pressed.bind(Constants.ClassType.SWORD))
	dev_bow_button.pressed.connect(_on_dev_skip_pressed.bind(Constants.ClassType.BOW))
	dev_staff_button.pressed.connect(_on_dev_skip_pressed.bind(Constants.ClassType.STAFF))
	dev_dagger_button.pressed.connect(_on_dev_skip_pressed.bind(Constants.ClassType.DAGGER))


## Light entrance polish: fade the screen in, slide/settle the title + panel, and
## drift the clouds. Purely cosmetic — no gameplay effect.
func _play_intro() -> void:
	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.4)

	var title_box := get_node_or_null("TitleBox")
	if title_box:
		title_box.position.y -= 14
		var t2 := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		t2.tween_property(title_box, "position:y", title_box.position.y + 14, 0.6)

	_drift_cloud($Cloud1 if has_node("Cloud1") else null, 26.0)
	_drift_cloud($Cloud2 if has_node("Cloud2") else null, -34.0)


## Slowly slides a cloud back and forth forever.
func _drift_cloud(cloud: Control, dist: float) -> void:
	if not is_instance_valid(cloud):
		return
	var x0: float = cloud.position.x
	var tw := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(cloud, "position:x", x0 + dist, 9.0)
	tw.tween_property(cloud, "position:x", x0, 9.0)


## Fabricates + writes a max-level save for `disc`, then hosts straight into the
## combat map (reusing the normal dev-login offline flow).
func _on_dev_skip_pressed(disc: int) -> void:
	status_label.text = "Dev: launching max %s…" % _DEV_DISCIPLINES[disc][1]
	status_label.add_theme_color_override("font_color", Color.YELLOW)

	NetworkManager.is_dev_mode = true
	NetworkManager.use_local_save = true  # offline: load/save from res://saves/
	NetworkManager.account_id = 9999
	NetworkManager.account_username = _DEV_USERNAME

	_write_dev_save(_DEV_USERNAME, _build_dev_max_save(_DEV_USERNAME, disc))

	# These metas are what PlayerManager._client_send_initial_info reads to pick
	# the character (normally set by the character-select screen).
	NetworkManager.set_meta("selected_character_name", _DEV_USERNAME)
	NetworkManager.set_meta("selected_character_class", disc)

	# Tear down the login screen once the server is up — same gate the
	# character-select screen uses.
	if not MultiplayerManager.server_has_started.is_connected(_on_dev_server_started):
		MultiplayerManager.server_has_started.connect(_on_dev_server_started)
	MultiplayerManager.host_game()


func _on_dev_server_started() -> void:
	queue_free()


## Builds a max-level save dict (level 100, all four masteries capped, every active
## ability of `disc` learned at level 1 with the first 8 bound to the primary
## hotbar). Empty inventory → JoinHandshake grants the starter weapon/armor.
## Spawns in "game" (the combat map) so there are enemies to hit immediately.
func _build_dev_max_save(username: String, disc: int) -> Dictionary:
	var weapon_type: int = disc  # ClassType 0-3 aligns 1:1 with WeaponType 0-3
	var ability_levels: Dictionary = {}
	var primary: Dictionary = {}
	var secondary: Dictionary = {}
	for i in range(8):
		primary[str(i)] = ""
		secondary[str(i)] = ""

	var slot: int = 0
	for ab in ResourceManager.ability_data.values():
		if ab.ability_type != Constants.AbilityType.ACTIVE:
			continue
		if not ab.required_weapon_types.has(weapon_type):
			continue
		ability_levels[ab.ability_id] = 1
		if slot < 8:
			primary[str(slot)] = ab.ability_id
			slot += 1

	var mastery: Dictionary = {}
	for k in ["sword", "bow", "staff", "dagger"]:
		mastery[k] = {"level": WeaponMasteryComponent.MASTERY_CAP, "xp": 0}

	return {
		"username": username,
		"level": 100,
		"experience": 0,
		"character_type": disc,
		"current_health": 999999, "max_health": 999999,
		"current_mana": 999999, "max_mana": 999999,
		"monies": 999999,
		"inventory": {},  # empty → starter kit (weapon + armor) granted on spawn
		"equipment": {},
		"weapon_mastery": mastery,
		"abilities": {
			"ability_levels": ability_levels,
			# reconcile_ability_points() recomputes these from mastery vs spent.
			"available_points_per_discipline": {"sword": 0, "bow": 0, "staff": 0, "dagger": 0},
			"learned_ability_upgrades": {},
			"primary_hotbar_bindings": primary,
			"secondary_hotbar_bindings": secondary,
		},
		"buffs": {},
		"quests": {},
		"attribute_points": {},
		"last_map": "game",
		"party_id": -1,
		"pets": [],
		"summoned_pet_ids": [],
	}


func _write_dev_save(username: String, data: Dictionary) -> void:
	var dir_abs := ProjectSettings.globalize_path("res://saves")
	if not DirAccess.dir_exists_absolute(dir_abs):
		DirAccess.make_dir_recursive_absolute(dir_abs)
	var f := FileAccess.open("res://saves/player_%s.json" % username, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
		f.close()
