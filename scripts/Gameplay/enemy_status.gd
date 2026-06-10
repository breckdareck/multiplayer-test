class_name EnemyStatus
extends RefCounted

## Status-tag query layer + escalation rules (ADR 0013).
##
## A "status tag" is the canonical queryable category of enemy status —
## bleed / poison / burn / chill / mark — aggregated across every per-source
## application. Per-ability meta keys (hemorrhage_bleed, envenom_poison, …)
## REMAIN the unit of stacking and tick math (the bleed_dot.gd convention);
## this class is the unit of QUERYING. Consumers and escalation rules key off
## tags, never off per-ability keys.
##
## Tag state is enemy-global: queries and consumes ignore who applied the
## stacks (any participant — player or bot — can read/spend any
## participant's stacks; FFA party philosophy). Per-key tick/kill credit
## keeps its existing last-refresher behavior.
##
## All methods are static and server-side; callers are responsible for the
## multiplayer.is_server() guard (every applier already guards at its entry).
##
## Meta value shapes this layer understands:
##   - Dictionary with "stacks"  → DoT (BleedDot / burn machinery). Live while
##     the meta exists; the tick machinery removes it at expiry.
##   - int/float on a "*_remaining" key → mark expiry timestamp (ms, server
##     clock). Live while now < value (lazy expiry, same as the mark code).
##   - other scalar (slow keys hold the pre-slow movement_speed) → live while
##     the meta exists; stack count 1.

const TAG_BLEED := "bleed"
const TAG_POISON := "poison"
const TAG_BURN := "burn"
const TAG_CHILL := "chill"
const TAG_MARK := "mark"

## Index of dynamically-registered keys, stored as enemy meta: {tag: {key: true}}.
const INDEX_META := "_status_tag_index"

## Every key the CURRENT content can apply, so queries work even for statuses
## applied by code that predates (or forgot) register(). New appliers should
## still call register() — this table is the safety net, not the contract.
## Freeze metas (glacial_freeze etc.) are deliberately NOT chill: freeze is a
## hard CC with its own machinery, and consuming it would strand restore state.
const KNOWN_KEYS := {
	TAG_BLEED: ["hemorrhage_bleed", "barbed_shot_bleed", "death_mark_bleed", "hunters_mark_bleed"],
	TAG_POISON: ["envenom_poison", "caltrops_poison", "synergy_poison"],
	TAG_BURN: ["immolate_burn", "pyre_burst_burn", "staff_element_burn"],
	TAG_CHILL: ["staff_element_chill", "frost_patch_chill", "caltrops_slow", "backstab_slow", "upgrade_slow_on_hit"],
	TAG_MARK: ["sentinels_mark_remaining", "hunters_mark_remaining", "death_mark_remaining", "mana_resonance_remaining"],
}

# --- Escalation rules (authored code table — deliberately NOT .tres-driven;
# --- three cross-cutting rules with bespoke effects, GW2-style legibility) ---

## Thermal Shock: chill applied to a burning enemy (or burn onto a chilled
## one) detonates the burn — the burn's next THERMAL_SHOCK_TICKS ticks are
## paid instantly as one burst — and consumes BOTH tags. Because per_tick is
## derived from the applying ability's max hit (dot_scaling_base), the burst
## scales with the trigger's power, per the grilled rule.
const THERMAL_SHOCK_TICKS := 4

## Septic: poison applied to a bleeding enemy ticks harder for that
## application's lifetime.
const SEPTIC_MULT := 1.5

## Brittle: when a MARKED enemy reaches 5+ total bleed stacks, the mark is
## consumed and the next hit against it is a guaranteed crit (combat.gd reads
## and clears BRITTLE_META in its crit roll).
const BRITTLE_BLEED_STACKS := 5
const BRITTLE_META := "brittle_crit"


## Record a status application under its tag and run the escalation rules.
## Call from every applier, right after the meta is written (both fresh-apply
## and refresh — escalations trigger per application event, not per fresh
## stack). `applier` is credited for escalation-burst damage and kills.
static func register(target: Node, tag: String, meta_key: String, applier: Node = null) -> void:
	if target == null or not is_instance_valid(target):
		return
	var index: Dictionary = target.get_meta(INDEX_META) if target.has_meta(INDEX_META) else {}
	var keys: Dictionary = index.get(tag, {})
	keys[meta_key] = true
	index[tag] = keys
	target.set_meta(INDEX_META, index)
	_check_escalations(target, tag, meta_key, applier)


## True when the enemy carries any live application of the tag.
static func has_tag(target: Node, tag: String) -> bool:
	return stack_count(target, tag) > 0


## Total stacks across every live application of the tag (SUM across sources —
## two appliers' bleeds add up; rewards stacking the pair).
static func stack_count(target: Node, tag: String) -> int:
	if target == null or not is_instance_valid(target):
		return 0
	var total: int = 0
	for key in _keys_for(target, tag):
		total += _live_stacks(target, key)
	return total


## Remove every live application of the tag; returns the total stacks removed.
## DoT/mark metas are simply removed (their tick machinery tolerates a missing
## meta). Chill keys hold the pre-slow movement_speed, so consuming restores
## the speed first — otherwise the pending restore timer would no-op and leave
## the enemy slowed forever.
static func consume_tag(target: Node, tag: String) -> int:
	if target == null or not is_instance_valid(target):
		return 0
	var removed: int = 0
	for key in _keys_for(target, tag):
		var stacks: int = _live_stacks(target, key)
		if stacks <= 0:
			continue
		removed += stacks
		if tag == TAG_CHILL:
			_restore_chill(target, key)
		target.remove_meta(key)
	return removed


# --- internals ---

static func _keys_for(target: Node, tag: String) -> Array:
	var keys: Dictionary = {}
	for k in KNOWN_KEYS.get(tag, []):
		keys[k] = true
	if target.has_meta(INDEX_META):
		var index: Dictionary = target.get_meta(INDEX_META)
		for k in index.get(tag, {}):
			keys[k] = true
	return keys.keys()


## Stacks in one live application; 0 when the meta is missing or expired.
static func _live_stacks(target: Node, key: String) -> int:
	if not target.has_meta(key):
		return 0
	var value = target.get_meta(key)
	if value is Dictionary:
		return maxi(1, int(value.get("stacks", 1)))
	if key.ends_with("_remaining"):
		# Mark expiry timestamp — lazily prune when stale.
		if Time.get_ticks_msec() < int(value):
			return 1
		target.remove_meta(key)
		return 0
	return 1


static func _restore_chill(target: Node, key: String) -> void:
	var value = target.get_meta(key)
	if value is float or value is int:
		if "movement_speed" in target:
			target.movement_speed = float(value)
	var sprite = target.get("animated_sprite")
	if sprite != null and is_instance_valid(sprite):
		sprite.modulate = Color.WHITE


static func _check_escalations(target: Node, tag: String, meta_key: String, applier: Node) -> void:
	match tag:
		TAG_CHILL:
			if has_tag(target, TAG_BURN):
				_thermal_shock(target, applier)
		TAG_BURN:
			if has_tag(target, TAG_CHILL):
				_thermal_shock(target, applier)
		TAG_POISON:
			if has_tag(target, TAG_BLEED):
				_septic(target, meta_key)
		TAG_BLEED:
			if has_tag(target, TAG_MARK) and stack_count(target, TAG_BLEED) >= BRITTLE_BLEED_STACKS:
				_brittle(target)


## Detonate: pay the burn's next THERMAL_SHOCK_TICKS ticks instantly, consume
## burn + chill. Damage bypasses i-frames like every DoT tick and credits the
## participant who completed the combo (enemy-global spending, per ADR 0013).
static func _thermal_shock(target: Node, applier: Node) -> void:
	var burst: int = 0
	for key in _keys_for(target, TAG_BURN):
		if not target.has_meta(key):
			continue
		var state = target.get_meta(key)
		if state is Dictionary:
			burst += int(state.get("per_tick", 1)) * maxi(1, int(state.get("stacks", 1))) * THERMAL_SHOCK_TICKS
			# Applier-less triggers (e.g. the staff chill rider) credit the
			# consumed burn's own applier.
			if applier == null:
				applier = state.get("applier", null)
	consume_tag(target, TAG_BURN)
	consume_tag(target, TAG_CHILL)
	if burst <= 0:
		return
	var health_comp = target.get("health_component")
	if health_comp == null or not is_instance_valid(health_comp) or health_comp.is_dead:
		return
	if applier != null and not is_instance_valid(applier):
		applier = null
	var was_alive: bool = not health_comp.is_dead
	health_comp.take_damage(burst, applier, true, false, true)
	if target.has_method("play_dot"):
		target.play_dot("burn")
	if was_alive and health_comp.is_dead:
		BleedDot._credit_kill(applier, target)


## The just-applied poison ticks SEPTIC_MULT harder while the enemy bleeds.
## Applied to this application only (refreshes re-evaluate naturally).
static func _septic(target: Node, poison_key: String) -> void:
	if not target.has_meta(poison_key):
		return
	var state = target.get_meta(poison_key)
	if state is Dictionary and not state.get("septic", false):
		state["per_tick"] = maxi(1, roundi(float(int(state.get("per_tick", 1))) * SEPTIC_MULT))
		state["septic"] = true
		target.set_meta(poison_key, state)


## Consume the mark; the next hit against this enemy is a guaranteed crit.
static func _brittle(target: Node) -> void:
	if consume_tag(target, TAG_MARK) > 0:
		target.set_meta(BRITTLE_META, true)
