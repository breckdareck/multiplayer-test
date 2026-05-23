Happy to grill this. I read through the ability/passive plumbing and the player movement code before writing — the pitch sounds simple, but it sits right on a seam in this codebase where several things don't line up. Let me walk it from "won't compile as designed" to "design smells."

## Hard blockers (the design as written can't be built without new code)

**1. There is no `MOVEMENT_SPEED` stat. Passives can only emit `StatType` bonuses.**

`scripts/Core/Enums/constants.gd` defines `StatType` as: STRENGTH, INTELLIGENCE, DEXTERITY, LUCK, HEALTH, MANA, HPREGEN, MPREGEN, DEFENSE, MAGICDEFENSE, CRITCHANCE, CRITDAMAGE, WEAPONATTACK, MAGICATTACK, KNOCKBACKRESIST. No movement.

Every existing passive — `A_DEX_Passive`, `A_Nimble_Step`, `A_STR_Passive`, `A_INT_Passive` — works by declaring a `StatBonusFormula` with a `stat_type` enum value, and `AbilityComponent.get_passive_effect_modifiers()` rolls those into `StatsComponent`. There is literally no channel through which a passive's bonus can reach movement today. So before Fleet Foot exists, *something* has to be decided:

- Add `MOVEMENT_SPEED` to `StatType` and have `StatsComponent` aggregate it? Then who reads it?
- Or skip the stat system entirely and write a custom `AL_FleetFoot.gd` logic script (the pattern `A_Haste` uses for its buff) that mutates movement directly?

These are very different architectural choices. Which one are you picturing?

**2. Movement speed is not read from `StatsComponent` at all today.**

Two parallel numbers drive the player's velocity, and *neither* is a stat:

- `MultiplayerPlayerV2.SPEED = 130.0` (a `const` on the controller) — used as a *clamp ceiling* in `move.gd` line 25.
- `State.move_speed = 130` (an `@export` on each state node, set in the scene) — the actual value `velocity.x` chases in `move.gd` line 30.

A 5%-per-level passive needs *somewhere* to apply that multiplier. None of the obvious somewheres exist yet:

- `MultiplayerPlayerV2` has no `get_move_speed()` accessor.
- `State` reads its own `@export var move_speed`, so even if you added a getter on the player, every move/jump/fall/slide/crouch state has its own copy.
- The clamp at `move.gd:25` is a `const`, so a buffed player who exceeds `SPEED` would be *slowed back down* to 130 by the very next frame.

So "increases movement speed by 5% per level" implicitly demands a refactor: a single source of truth for move speed on the player, queried each frame by the active state, that aggregates base + passive + buff. That's the real ticket. Has that work been scoped?

**3. `AbilityData` has no `required_level` field. "Unlocks at character level 5" isn't expressible.**

I grepped — `required_level` exists on `QuestData`, not `AbilityData`. The only gating on abilities today is `prerequisite_abilities` (a Dictionary of `AbilityData -> int_level`). So "unlocks at character level 5" needs one of:

- Add an `@export var required_character_level: int` to `AbilityData` and gate it in `AbilityComponent.learn_ability` / the ability window UI.
- Or model the prereq as "must have learned X first" where X is something Rogues only get at level 5.

Pick one — they have different cascading consequences (the first is a global mechanism that every future ability can use; the second is one-off).

## Design smells worth pressure-testing

**4. Rogues already have `A_Haste`. What's the relationship?**

`resources/Abilities/Rogue/A_Haste.tres` exists. In its current implementation it grants a party-wide DEX/LUCK buff via `B_Haste.tres` — the *name* suggests speed but the *mechanic* is stats. Two possible reads:

- (a) The repo's Haste is misnamed and was always meant to be the speed buff; Fleet Foot duplicates it.
- (b) Haste is intentionally a stat buff and Fleet Foot is its passive movement-speed sibling.

If (b), is Fleet Foot meant to stack with Haste? With movement buffs from items? With a sprint/dash? Without a stacking rule, +50% Fleet Foot + future +X% boots + future Haste-real becomes a balance landmine. **What's the design intent for movement-speed sources stacking?**

**5. +50% movement is a *lot* and it's permanent.**

`Move.gd` line 25 caps "input-driven" speed at `SPEED` (130). A 50% boost takes the Rogue's walk speed to 195 — well above the clamp, which means either (a) the clamp gets removed/scaled (then knockback recovery behavior changes, see lines 25–27) or (b) the boost silently gets clipped and players feel cheated past level ~6. Have you thought about:

- Server-authority feel: in this codebase the server validates all critical state. Movement is currently driven by client input via `InputSynchronizer`. Does a 50% faster Rogue desync more visibly? Worth a quick test.
- Knockback recovery: the clamp at `move.gd:25` is specifically the "you got knocked back, ease down to SPEED" logic. A higher cap changes how knockback feels.
- Jump distance: jumps use horizontal velocity at takeoff. A 50% faster Rogue jumps 50% farther. Map design (esp. anything you've made for the level-1–30 quest journey from your roadmap) assumes a fixed jump arc.
- Enemy chase: `scripts/Enemy/StateMachine/enemy_chase.gd` uses `SPEED` too. If Rogues outpace every enemy from level 14 onward, kiting trivializes content. Intended?

**6. Class-exclusive *and* tied to character level. Why both?**

Rogue class restriction is easy (`required_class = [3]`, same as other Rogue passives). But you also want a level-5 character gate. That's redundant unless the level-5 number is meaningful — and the obvious question is: when do other classes get their level-1-locked passives? Currently the existing passives (`A_DEX_Passive`, `A_STR_Passive`, etc.) have *no* level gate at all. So Fleet Foot would be the first ability in the game with a "character level 5 to learn" gate. Is that genuinely the desired carve-out, or is "level 5" a placeholder?

**7. Per-level granularity: 10 levels of +5% — is that really how Rogue progression should feel?**

Look at `A_Nimble_Step.tres`: `max_level = 20`, +2% DEX per level. `A_Haste.tres`: `max_level = 30`. Most passives go to 20 or 30 and use fine-grained bumps. Fleet Foot at `max_level = 10` is unusually coarse for this codebase — players will be done leveling it by ~mid-game and then it's dead SP. Is the cap-at-10 intentional pacing, or just where +50% felt round?

**8. Persistence: passives survive logout. Is that vetted?**

Per the root `CLAUDE.md`, "in-game character state… abilities, buffs" persists through `SaveManager`. `_active_passive_abilities` is rebuilt from `_ability_levels` on load (`ability.gd:798–799`). That's fine for a stat passive — but if Fleet Foot routes through a custom `AL_FleetFoot.gd` that mutates `State.move_speed` at apply-time, you have to handle the load path explicitly (`set_loading_mode(true)` window), or the buff "re-applies" on load and stacks with a stale carry-over.

## My summary to react to

The proposal as written assumes three things that aren't true in this codebase:

1. Movement speed is a stat. *(It isn't — it's two raw constants split across two files.)*
2. Passives can grant non-stat effects. *(They can't via the standard pipe — you'd need custom logic, like `A_Haste`'s `AL_Haste.gd`.)*
3. Abilities can require a character level. *(They can't today — only prerequisite abilities.)*

So before this is buildable, three architectural decisions need to land:

- **A. Movement-speed source of truth** — new `StatType` entry + Stats aggregation, *or* a `get_move_speed()` method on `MultiplayerPlayerV2` that all states read?
- **B. How Fleet Foot reads that source** — declarative stat bonus, or custom `AL_FleetFoot.gd` logic script?
- **C. Character-level gating mechanism** — add `required_character_level` to `AbilityData` (reusable), or fake it with a hidden prerequisite ability (one-off)?

And before you commit to the *numbers*: please reconcile +50% with the existing `move.gd:25` clamp, the jump-distance side effect, and the enemy chase speed in `enemy_chase.gd`.

Where would you like to start — the architecture decisions (A/B/C), or the balance numbers?
