extends Node

## Buff logic for Rogue's Shadow Partner.
## Spawns a dark copy of the player that follows behind them and mirrors attacks.

var source_ability_level: int = 1
var damage_percent: float = 50.0
var _shadow: Node2D = null
var _owner_ref: Node = null
var _combat_component: CombatComponent = null
var _shadow_offset := Vector2(-20, 0)

func on_apply(owner_node: Node, _active_buff) -> void:
	_owner_ref = owner_node
	_combat_component = owner_node.get_node_or_null("Components/Combat")

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
		shadow_sprite.z_index = -1
		_shadow.add_child(shadow_sprite)

	owner_node.add_child(_shadow)
	_shadow.position = _shadow_offset

	if _combat_component:
		var hitbox_area: Area2D = _combat_component.attack_hitbox.get_parent()
		if not hitbox_area.area_entered.is_connected(_on_owner_hit):
			hitbox_area.area_entered.connect(_on_owner_hit)

	if owner_node.has_method("sync_shadow_partner"):
		owner_node.sync_shadow_partner.rpc(true)

	print("Shadow Partner spawned for %s (Level %d, %.0f%% damage)" % [
		owner_node.name, source_ability_level, damage_percent])


func on_remove(owner_node: Node, _active_buff) -> void:
	if _combat_component:
		var hitbox_area: Area2D = _combat_component.attack_hitbox.get_parent()
		if hitbox_area.area_entered.is_connected(_on_owner_hit):
			hitbox_area.area_entered.disconnect(_on_owner_hit)

	if is_instance_valid(_shadow):
		_shadow.queue_free()
		_shadow = null

	if owner_node.has_method("sync_shadow_partner"):
		owner_node.sync_shadow_partner.rpc(false)

	print("Shadow Partner expired on %s" % owner_node.name)


func on_tick(owner_node: Node, _active_buff, _delta: float) -> void:
	if not is_instance_valid(_shadow):
		return

	var dir: int = owner_node.facing_direction
	_shadow.position = Vector2(-20 * dir, 0)

	var shadow_sprite = _shadow.get_node_or_null("ShadowSprite")
	var owner_sprite: AnimatedSprite2D = owner_node.get_node_or_null("AnimatedSprite2D")
	if shadow_sprite and owner_sprite:
		shadow_sprite.flip_h = owner_sprite.flip_h
		if owner_sprite.is_playing():
			shadow_sprite.play(owner_sprite.animation)


func _on_owner_hit(area: Area2D) -> void:
	if not is_instance_valid(_owner_ref) or not _owner_ref.multiplayer.is_server():
		return
	if not area.owner is EnemyBase:
		return
	var enemy: EnemyBase = area.owner
	var health_comp = enemy.get("health_component")
	if not health_comp or health_comp.is_dead:
		return

	var shadow_damage := roundi(_combat_component.calculate_attack_damage() * (damage_percent / 100.0))
	shadow_damage = maxi(1, shadow_damage)
	health_comp.take_damage(shadow_damage, _combat_component, true, false, false)
	print("Shadow Partner hit %s for %d damage" % [enemy.name, shadow_damage])
