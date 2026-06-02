class_name WeaponSignatureComponent
extends Node

## Shared interface for the four weapon-discipline SIGNATURE systems — the sword
## combo, bow momentum, staff element stance, and dagger shadowmeld. A signature
## is the per-discipline combat mechanic that makes a weapon FEEL like itself.
##
## Why this base exists (candidate-2 deepening): the rule "reset a signature when
## its discipline goes inactive (weapon swap / re-equip) or its owner dies" used
## to be hand-coded per signature across three different handlers on the player
## root, plus a fourth in EquipmentComponent — with inconsistent method names
## (`reset` / `reset_combo` / `cancel_stealth`) and two of the four not wired at
## all. This base lets the player root notify EVERY signature through ONE
## interface; each signature owns its OWN activation rule. Adding a fifth
## signature needs zero player-root edits — it just extends this base and
## implements the hooks it cares about.
##
## Server-authoritative: the player root (MultiplayerPlayerV2) only calls these
## hooks on the server, matching where every per-signature reset already ran.
## Each hook defaults to a no-op, so a signature with no reset rule (staff
## element persists across swaps and death) overrides nothing.

## The weapon discipline (a `Constants.ClassType` int) this signature belongs to.
## Override in every concrete signature. Returned to the player root so it can
## be matched against the currently-wielded discipline.
func signature_discipline() -> int:
	return -1


## Called (server-side) whenever the wielded-weapon state changes — a Tab-swap or
## an equipment edit. `active_discipline` is the discipline currently wielded;
## `equipped_disciplines` are the disciplines present in EITHER weapon slot. Each
## signature decides whether its volatile state should reset. Default: no-op.
func on_weapon_state_changed(_active_discipline: int, _equipped_disciplines: Array) -> void:
	pass


## Called (server-side) when the owner dies. Clear any volatile signature state
## that should not survive death. Default: no-op.
func on_owner_died() -> void:
	pass
