extends RefCounted

## Single source of truth for the player-facing explanations of the four weapon
## signature gauges (Sword Combo, Bow Momentum, Staff Element stance, Dagger
## Shadowmeld). Each gauge widget reads the matching builder here for its hover
## tooltip, so the "what is this gauge?" copy lives in one place beside SynergyInfo.
## Keep these in lockstep with the components in scripts/Components/* — if a cap,
## effect, or cooldown changes there, update the wording here.

const TITLE_COLOR := "#8fd0ff"   # cyan — gauge name
const BODY_COLOR := "#d6dae3"    # off-white — explanation
const KEY_COLOR := "#ffd479"     # warm gold — key hint
const FIRE_COLOR := "#ff6b4d"
const ICE_COLOR := "#66bfff"
const LIGHTNING_COLOR := "#ffd940"


## Sword — combo points built by hits, spent by finishers.
static func sword_combo() -> String:
	return _title("COMBO POINTS") + ("[color=%s]Every sword hit banks a Combo Point (max 3). "
		+ "Your finisher abilities spend ALL banked points at once — the more you've stacked, "
		+ "the harder the finisher lands. Points persist when you swap weapons, but decay after "
		+ "5s with no attacks.[/color]") % BODY_COLOR


## Bow — momentum stacks that ramp damage and attack speed.
static func bow_momentum() -> String:
	return _title("MOMENTUM") + ("[color=%s]The bow is a rhythm weapon. Every landed shot adds a "
		+ "stack of Momentum (max 10), ramping BOTH your bow damage and your attack speed. Keep "
		+ "firing to climb the gauge; pause for ~2s and it bleeds back down. Momentum persists "
		+ "across weapon swaps, so a mage can build it on the bow and unload empowered spells.[/color]") % BODY_COLOR


## Staff — the element stance cycled with the signature key.
static func staff_element() -> String:
	var key := signature_key_label()
	return _title("ELEMENT STANCE") + (
		"[color=%s]Press [color=%s][b]%s[/b][/color] to cycle your staff's element. "
		+ "The active element rides every staff spell hit:[/color]\n"
		+ "[color=%s]●[/color] [color=%s][b]Fire[/b] — a stacking burn that ticks damage over time.[/color]\n"
		+ "[color=%s]●[/color] [color=%s][b]Ice[/b] — slows the enemy's movement.[/color]\n"
		+ "[color=%s]●[/color] [color=%s][b]Lightning[/b] — bonus shock that chains to nearby enemies.[/color]"
	) % [
		BODY_COLOR, KEY_COLOR, key,
		FIRE_COLOR, BODY_COLOR,
		ICE_COLOR, BODY_COLOR,
		LIGHTNING_COLOR, BODY_COLOR,
	]


## Dagger — the stealth toggle and its ambush payoff.
static func shadowmeld() -> String:
	var key := signature_key_label()
	return _title("SHADOWMELD") + (
		"[color=%s]Press [color=%s][b]%s[/b][/color] to cloak — you vanish from enemy sight. "
		+ "Your next strike from stealth is an [b]Ambush[/b] that deals double damage, then stealth "
		+ "breaks. After cloaking there's a 6s cooldown, and you auto-uncloak after 8s if you never "
		+ "attack. The widget reads STEALTHED, READY, or a recharge countdown.[/color]"
	) % [BODY_COLOR, KEY_COLOR, key]


## Resolves the current key bound to the WeaponSignature action (defaults to "R").
## Read straight from the InputMap — this action isn't in UserConfig's managed set.
static func signature_key_label() -> String:
	for ev in InputMap.action_get_events("WeaponSignature"):
		if ev is InputEventKey:
			var kc: int = ev.physical_keycode
			if kc != KEY_NONE:
				return OS.get_keycode_string(kc)
	return "R"


static func _title(t: String) -> String:
	return "[color=%s][b]%s[/b][/color]\n\n" % [TITLE_COLOR, t]
