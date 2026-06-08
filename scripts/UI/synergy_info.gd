extends RefCounted

## Single source of truth for the player-facing names + explanations of every
## weapon-pair synergy. The HUD's synergy_widget reads this to (a) name the pair
## you have equipped and (b) build the hover tooltip that teaches what the synergy
## does. Every synergy is TWO-WAY: each weapon does something for the other, so the
## tooltip lists both directions, labeled by which weapon you're currently wielding.
## Keep this in lockstep with scripts/Components/weapon_pair_synergy.gd — if a
## direction, multiplier, or effect changes there, update the wording here.
##
## Keyed by the normalized "min_max" discipline pair (SWORD=0, BOW=1, STAFF=2,
## DAGGER=3), matching weapon_pair_synergy / synergy_widget. Each entry is:
##   name  — the loud HUD name (matches synergy_widget's PAIR label)
##   pair  — the two weapons in plain words ("Sword + Staff")
##   tag   — one-line hook describing the loop the two weapons form
##   dirs  — ordered [weapon, effect] pairs: what each weapon does for the other.

const HEADER_COLOR := "#8fd0ff"   # cyan — synergy name
const PAIR_COLOR := "#c9b88a"     # muted gold — weapon pair line
const TAG_COLOR := "#9aa6b8"      # grey — the loop hook
const DIR_COLOR := "#ffd479"      # warm gold — "Wielding the X" label
const BODY_COLOR := "#d6dae3"     # off-white — effect text

const DATA := {
	# Sword + Staff
	"0_2": {
		"name": "SPELLBLADE",
		"pair": "Sword + Staff",
		"tag": "The staff's element rides your blade; your sword combo fuels your spells.",
		"dirs": [
			["Sword", "Your sword ability hits carry the staff's active stance element (burn / slow / chain)."],
			["Staff", "Your spells spend banked Sword Combo for a bonus magic burst (~50% per point)."],
		],
	},
	# Bow + Staff
	"1_2": {
		"name": "ELEMENTAL SHOT",
		"pair": "Bow + Staff",
		"tag": "Arrows deliver the staff's element; your bow momentum empowers your spells.",
		"dirs": [
			["Bow", "Your arrows carry the staff's active stance element (burn / slow / chain)."],
			["Staff", "Your spells ride your Bow Momentum ramp for bonus damage (it persists across the swap)."],
		],
	},
	# Staff + Dagger
	"2_3": {
		"name": "HEXBLADE",
		"pair": "Staff + Dagger",
		"tag": "Ambushes deliver the staff's element; your spells spread the dagger's poison.",
		"dirs": [
			["Staff", "Your spells apply the dagger's poison DoT (stacking, scales with the hit)."],
			["Dagger", "Your ambush carries the staff's active stance element (burn / slow / chain)."],
		],
	},
	# Sword + Bow
	"0_1": {
		"name": "SKIRMISHER",
		"pair": "Sword + Bow",
		"tag": "Build Sword Combo at range with the bow, then cash it in up close.",
		"dirs": [
			["Bow", "Your bow hits bank Sword Combo points, which persist across the weapon swap."],
			["Sword", "Swap in with a full stockpile and unload it on a heavy combo finisher."],
		],
	},
	# Sword + Dagger
	"0_3": {
		"name": "ASSASSIN",
		"pair": "Sword + Dagger",
		"tag": "Build Combo on the sword, cloak, and detonate it in one poisoned strike.",
		"dirs": [
			["Sword", "Your sword ability hits apply the dagger's poison DoT."],
			["Dagger", "Your ambush spends banked Sword Combo for a damage spike (~50% per point)."],
		],
	},
	# Bow + Dagger
	"1_3": {
		"name": "AMBUSHER",
		"pair": "Bow + Dagger",
		"tag": "Soften from range to charge the buffer, then close and detonate it.",
		"dirs": [
			["Bow", "Your bow hits charge an ambush buffer (up to 10) and apply poison."],
			["Dagger", "Your next ambush spends the stored charge for a burst of bonus damage."],
		],
	},
}


## Returns the synergy record for a pair key, or null if not a recognized pair.
static func get_for_key(pair_key: String):
	return DATA.get(pair_key, null)


## Builds the BBCode tooltip body for a pair key: name, weapons, the loop hook, and
## both directions (what each weapon does for the other). "" if not a real synergy.
static func tooltip_bbcode(pair_key: String) -> String:
	var rec = DATA.get(pair_key, null)
	if rec == null:
		return ""
	var out := "[color=%s][b]%s[/b][/color]\n[color=%s]%s[/color]\n[color=%s]%s[/color]" % [
		HEADER_COLOR, rec["name"],
		PAIR_COLOR, rec["pair"],
		TAG_COLOR, rec["tag"],
	]
	for d in rec["dirs"]:
		out += "\n\n[color=%s][b]Wielding the %s:[/b][/color]\n[color=%s]%s[/color]" % [
			DIR_COLOR, d[0], BODY_COLOR, d[1],
		]
	return out
