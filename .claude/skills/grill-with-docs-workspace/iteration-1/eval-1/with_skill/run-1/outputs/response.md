Before we grill the numbers, I want to flag the load-bearing issue, because it changes what kind of feature this even is.

**Movement speed is not a stat in this codebase.** `Constants.StatType` (`scripts/Core/Enums/constants.gd`) lists STRENGTH, INT, DEX, LUCK, HEALTH, MANA, regen, defenses, crit, attack, knockback resist — and nothing for movement speed. The player's actual speed is a hard-coded `const SPEED: float = 130.0` on `scripts/Player/multiplayer_controller_v2.gd`, consumed by `move.gd` / `slide.gd` directly as `player.SPEED`. There is no Stats-component pipe, no equipment hook, no buff hook going into movement.

That matters because the obvious-looking implementation — a passive `.tres` with a `StatBonusFormula` like Nimble Step's — won't work. `StatBonusFormula.stat_type` is a `StatType`, and there's no member to point at. So you have three real paths, not one, and they aren't equivalent:

1. **Add `MOVEMENT_SPEED` to `StatType`.** Cleanest long-term: equipment, buffs, future passives all get it for free. But it touches every Stats block, every save file's stat dictionary, the equipment bonus pipeline, and any UI that lists stats. That's a save-format change.
2. **Custom `AL_FleetFoot.gd` passive** that reaches into the controller and applies a multiplier to a new `speed_multiplier` field, refreshed on level-up. Localised, but it's a one-off mechanism that the next "+X% speed" effect (boots? Haste rework? a buff?) will want too, and now you have two speed systems.
3. **Make `SPEED` itself derived** from a Stats-component value (even if there's only one consumer today), then choose path 1 or 2 against that. Decouples the controller from the constant either way.

Haste (`A_Haste.tres` + `AL_Haste.gd` + `B_Haste.tres`) is already the Rogue's "go faster" active — and it currently buffs DEX/LUCK, not literal move speed. So you also haven't told me how Fleet Foot relates to it: stacks multiplicatively, mutually exclusive, or Fleet Foot is the *passive* layer that Haste-the-active sits on top of?

**My recommended first question to lock down, with my proposed answer:**

> Should Fleet Foot's +5%/level apply to the player's *actual locomotion speed* (the `SPEED` constant on the controller), or to a stat-derived quantity? If it's locomotion speed, we need to commit to one of the three paths above before any `.tres` work — and my recommendation is **path 3 + path 1**: refactor `SPEED` to read from a new `MOVEMENT_SPEED` `StatData` on the Stats component (base 130, percent_bonus_value drives the multiplier), then add `MOVEMENT_SPEED` to `StatType`. That makes Fleet Foot a one-line `StatBonusFormula` just like Nimble Step, opens the door for speed boots / speed buffs / the Haste rework cleanly, and keeps the server-authoritative story honest (the Stats component is already server-owned and broadcast).
>
> The cost you're accepting: a save-format bump (existing player saves won't have `MOVEMENT_SPEED` in their stat dict — `SaveManager` needs a default-on-load), and any UI that enumerates stats picks up a new row. This is ADR-worthy on both counts.

Does that match your intent, or were you imagining Fleet Foot as a localised effect that doesn't open the speed-as-a-stat door?
