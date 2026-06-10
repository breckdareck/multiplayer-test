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
##   duo   — the pair's DUO NODE (ADR 0013): a derived unlock (30+ ability
##           points spent in BOTH equipped disciplines) that adds an on-swap
##           trigger (8s internal cooldown) + a standing amplification. Keep in
##           lockstep with weapon_pair_synergy.gd's _fire_duo_swap_trigger /
##           duo standing constants.
##     name      — the duo's name
##     swap      — what firing the swap trigger does
##     standing  — the always-on amplification while the duo is unlocked

const HEADER_COLOR := "#8fd0ff"   # cyan — synergy name
const PAIR_COLOR := "#c9b88a"     # muted gold — weapon pair line
const TAG_COLOR := "#9aa6b8"      # grey — the loop hook
const DIR_COLOR := "#ffd479"      # warm gold — "Wielding the X" label
const BODY_COLOR := "#d6dae3"     # off-white — effect text
const DUO_COLOR := "#ff9d5c"      # ember orange — duo node name
const DUO_LOCKED_COLOR := "#7d8694"  # dim grey — locked duo state

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
		"duo": {
			"name": "EMBERBLADE",
			"swap": "Your next stance imbue strikes twice.",
			"standing": "Your BASIC sword hits also carry the stance element (not just abilities).",
		},
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
		"duo": {
			"name": "GALECALLER",
			"swap": "Gain 4 Momentum stacks on the spot.",
			"standing": "Spells riding your Momentum pay 1.5× the usual bonus.",
		},
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
		"duo": {
			"name": "VENOMWEAVE",
			"swap": "Your next poison imbue applies DOUBLE stacks.",
			"standing": "The pair's poison imbue stacks to 8 (up from 5).",
		},
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
		"duo": {
			"name": "SKIRMISHER'S RHYTHM",
			"swap": "Bank 2 Sword Combo points instantly.",
			"standing": "Every 3rd bow hit banks an EXTRA Combo point.",
		},
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
		"duo": {
			"name": "BLADE DANCER'S OATH",
			"swap": "Swap to the dagger: meld into shadow. Swap to the sword: bank 2 Combo points.",
			"standing": "Ambush combo-spend pays 75% per point (up from 50%).",
		},
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
		"duo": {
			"name": "VEILED QUARRY",
			"swap": "The ambush buffer charges +4 from the swap itself.",
			"standing": "Buffer cap raised to 15 (up from 10).",
		},
	},
}


## Returns the synergy record for a pair key, or null if not a recognized pair.
static func get_for_key(pair_key: String):
	return DATA.get(pair_key, null)


## Builds the BBCode tooltip body for a pair key: name, weapons, the loop hook, and
## both directions (what each weapon does for the other). "" if not a real synergy.
##
## The optional duo args render the pair's DUO NODE section with live state:
## `duo_unlocked` paints it active; `duo_progress` is a short pre-formatted
## points line (e.g. "Sword 12/30 · Staff 30/30") shown while locked. Pass
## neither to render the duo as plain reference text.
static func tooltip_bbcode(pair_key: String, duo_unlocked: bool = false, duo_progress: String = "") -> String:
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

	var duo = rec.get("duo", null)
	if duo != null:
		var name_color: String = DUO_COLOR if duo_unlocked else DUO_LOCKED_COLOR
		var state: String = "UNLOCKED" if duo_unlocked else "LOCKED"
		out += "\n\n[color=%s][b]★ DUO — %s[/b]  (%s)[/color]" % [name_color, duo["name"], state]
		out += "\n[color=%s][b]On weapon swap[/b] (8s cooldown): %s[/color]" % [BODY_COLOR if duo_unlocked else DUO_LOCKED_COLOR, duo["swap"]]
		out += "\n[color=%s][b]Always:[/b] %s[/color]" % [BODY_COLOR if duo_unlocked else DUO_LOCKED_COLOR, duo["standing"]]
		if not duo_unlocked:
			out += "\n[color=%s]Unlocks with 30+ ability points spent in BOTH equipped weapons." % TAG_COLOR
			if duo_progress != "":
				out += "  (%s)" % duo_progress
			out += "[/color]"
	return out
