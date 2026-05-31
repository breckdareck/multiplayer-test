extends Node

## Buff logic for Rogue's Shadow Partner.
## Spawns a dark copy of the player that follows behind them and mirrors attacks.

var source_ability_level: int = 1
var damage_percent: float = 50.0
var _shadow: Node2D = null
var _owner_ref: Node = null
var _combat_component: CombatComponent = null

func on_apply(owner_node: Node, _active_buff) -> void:
	_owner_ref = owner_node
	_combat_component = owner_node.get_node_or_null("Components/Combat")

	_create_shadow_visual(owner_node)
	_connect_combat_signal()

	if owner_node.has_method("sync_shadow_partner"):
		owner_node.sync_shadow_partner.rpc(true)

	#print("Shadow Partner spawned for %s (%.0f%% damage)" % [owner_node.name, damage_percent])


func on_remove(owner_node: Node, _active_buff) -> void:
	_disconnect_combat_signal()

	if is_instance_valid(_shadow):
		_shadow.queue_free()
		_shadow = null

	if owner_node.has_method("sync_shadow_partner"):
		owner_node.sync_shadow_partner.rpc(false)



func on_tick(owner_node: Node, _active_buff, _delta: float) -> void:
	if not is_instance_valid(_shadow):
		_owner_ref = owner_node
		_combat_component = owner_node.get_node_or_null("Components/Combat")
		_create_shadow_visual(owner_node)
		_connect_combat_signal()
		if owner_node.has_method("sync_shadow_partner"):
			owner_node.sync_shadow_partner.rpc(true)

	if not _combat_component:
		_combat_component = owner_node.get_node_or_null("Components/Combat")
		_connect_combat_signal()

	var dir: int = owner_node.facing_direction
	_shadow.position = Vector2(-10 * dir, 0)

	var shadow_sprite = _shadow.get_node_or_null("ShadowSprite")
	var owner_sprite: AnimatedSprite2D = owner_node.get_node_or_null("AnimatedSprite2D")
	if shadow_sprite and owner_sprite:
		shadow_sprite.flip_h = owner_sprite.flip_h
		if owner_sprite.is_playing():
			shadow_sprite.play(owner_sprite.animation)


func _create_shadow_visual(owner_node: Node) -> void:
	# Free any stale "ShadowPartner" child left behind by a previous BL_ShadowPartner
	# instance whose owner the buff outlived (e.g. load_buffs frees the old logic
	# node but the _shadow child it parented on the player stays — without this
	# cleanup, the next on_tick adds a second Node2D that Godot auto-renames).
	var stale := owner_node.get_node_or_null("ShadowPartner")
	if stale:
		stale.queue_free()

	_shadow = Node2D.new()
	_shadow.name = "ShadowPartner"

	var owner_sprite: AnimatedSprite2D = owner_node.get_node_or_null("AnimatedSprite2D")
	if owner_sprite and owner_sprite.sprite_frames:
		var shadow_sprite := AnimatedSprite2D.new()
		shadow_sprite.name = "ShadowSprite"
		shadow_sprite.sprite_frames = owner_sprite.sprite_frames
		shadow_sprite.modulate = Color(0.15, 0.05, 0.25, 0.6)
		shadow_sprite.offset = owner_sprite.offset
		shadow_sprite.scale = owner_sprite.scale
		shadow_sprite.position = owner_sprite.position
		shadow_sprite.z_index = 0
		_shadow.add_child(shadow_sprite)

	owner_node.add_child(_shadow)
	_shadow.position = Vector2(-10 * owner_node.facing_direction, 0)


func _connect_combat_signal() -> void:
	if not _combat_component:
		return
	if not _combat_component.dealt_damage.is_connected(_on_owner_dealt_damage):
		_combat_component.dealt_damage.connect(_on_owner_dealt_damage)


func _disconnect_combat_signal() -> void:
	if is_instance_valid(_combat_component) and _combat_component.dealt_damage.is_connected(_on_owner_dealt_damage):
		_combat_component.dealt_damage.disconnect(_on_owner_dealt_damage)


func _on_owner_dealt_damage(target: Node, damage_values: Array, crit_values: Array) -> void:
	if not is_instance_valid(_owner_ref) or not _owner_ref.multiplayer.is_server():
		return
	if not target is EnemyBase:
		return
	var health_comp = target.get("health_component")
	if not health_comp:
		return

	var stats_comp: StatsComponent = _owner_ref.get_node_or_null("Components/Stats")
	if not stats_comp:
		return

	var hit_count: int = damage_values.size()
	var attacker_level: int = _owner_ref.level_component.level
	var target_level: int = target.monster_level
	var level_diff: int = attacker_level - target_level
	# PR 13: mirror combat.gd hit-chance — level scalar 3, DEX accuracy +
	# ACCURACY stat + target EVASIONCHANCE subtractor. Without this, Shadow
	# Partner's phantom hits would have higher hit% than the player's own
	# strikes against high-evasion targets, and lower hit% than the player's
	# strikes when the player has accuracy investment.
	var dex_acc: float = 0.0
	var stat_acc: float = 0.0
	if stats_comp.stats.has(Constants.StatType.DEXTERITY):
		dex_acc = stats_comp.stats[Constants.StatType.DEXTERITY].total_value * StatsComponent.DEX_TO_ACCURACY
	if stats_comp.stats.has(Constants.StatType.ACCURACY):
		stat_acc = float(stats_comp.stats[Constants.StatType.ACCURACY].total_value)
	var tgt_evasion: float = 0.0
	var tgt_stats = target.get("stats_component")
	if tgt_stats != null and is_instance_valid(tgt_stats) and tgt_stats.stats.has(Constants.StatType.EVASIONCHANCE):
		tgt_evasion = float(tgt_stats.stats[Constants.StatType.EVASIONCHANCE].total_value)
	var hit_chance: float = clampf(95.0 + (level_diff * 3.0) + dex_acc + stat_acc - tgt_evasion, 5.0, 100.0)

	var shadow_damages: Array = []
	var shadow_crits: Array = []

	for i in range(hit_count):
		if randf() * 100.0 > hit_chance:
			shadow_damages.append(-1)
			shadow_crits.append(false)
			continue

		var base_damage := float(_combat_component.calculate_attack_damage()) * (damage_percent / 100.0)

		if target.has_node("Stats"):
			var target_stats = target.get_node("Stats")
			var target_defense: int = target_stats.stats.get(Constants.StatType.DEFENSE).total_value
			var level_modifier: float = clampf(1.0 + (level_diff * 0.05), 0.5, 1.5)
			var defense_multiplier: float = 1.0 - (float(target_defense) / (target_defense + 500.0))
			base_damage *= level_modifier * defense_multiplier

		var crit_chance: float = stats_comp.stats.get(Constants.StatType.CRITCHANCE).total_value
		var is_crit: bool = (randf() * 100.0) < crit_chance

		if is_crit:
			var crit_damage_bonus: float = stats_comp.stats.get(Constants.StatType.CRITDAMAGE).total_value
			var crit_multiplier: float = randf_range(1.2, 1.5) + (crit_damage_bonus / 100.0)
			base_damage *= crit_multiplier
		else:
			base_damage *= randf_range(0.8, 1.2)

		var final_damage := maxi(1, roundi(base_damage))
		shadow_damages.append(final_damage)
		shadow_crits.append(is_crit)
		health_comp.take_damage(final_damage, _combat_component, true, is_crit, false)

	# Interleave: insert each shadow hit after its corresponding player hit
	for i in range(shadow_damages.size()):
		var insert_idx: int = (i * 2) + 1
		damage_values.insert(insert_idx, shadow_damages[i])
		crit_values.insert(insert_idx, shadow_crits[i])
