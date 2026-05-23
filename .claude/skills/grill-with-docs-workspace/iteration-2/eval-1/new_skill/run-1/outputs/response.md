Happy to grill this. Before we get into balance and edge cases, two things to surface up front, because they change what we're actually designing.

**1. There's already a skill for this — use it.** "Fleet Foot" is an `AbilityData` `.tres` with `ability_type = PASSIVE` and a `stat_bonus_formulas` entry. That's exactly the recipe the `add-ability` skill walks through (step 7 covers passives specifically). When we're done grilling, that's the skill to load — don't hand-roll it. Also note the project convention from your memory file: there is **one** progression system. The user-facing word "skill" maps to **Ability** in this codebase; we're not building a parallel skill tree.

**2. Your plan trips a hard invariant: `StatType` has no movement-speed entry.** I checked `scripts/Core/Enums/constants.gd` — the stat enum is `STRENGTH, INTELLIGENCE, DEXTERITY, LUCK, HEALTH, MANA, HPREGEN, MPREGEN, DEFENSE, MAGICDEFENSE, CRITCHANCE, CRITDAMAGE, WEAPONATTACK, MAGICATTACK, KNOCKBACKRESIST`. No `MOVEMENT_SPEED`. Movement speed today lives as a `SPEED` constant on the player and a `move_speed` local in `scripts/Player/StateMachine/move.gd` — it is **not** flowing through the `Stats` component. So a passive that writes to `stat_bonus_formulas[MOVEMENT_SPEED]` has nowhere to land. This is the real design decision, and it's ADR-shaped if we go the "promote movement speed to a real stat" route.

There's also a smaller wrinkle worth flagging now: **Rogue already has `A_Haste.tres`** (`resources/Abilities/Rogue/A_Haste.tres`, with `AL_Haste.gd` logic). Whatever Haste does presumably overlaps with Fleet Foot. We need to decide if Fleet Foot is additive, replaces Haste, or is the passive baseline that Haste's active buff stacks on top of.

---

So the first real grilling question, which everything else depends on:

**How should movement speed become moddable?** The three options I see, with my recommendation:

- **(a) Promote `MOVEMENT_SPEED` to a real `StatType` enum entry**, and refactor `move.gd` to read `move_speed` from the `Stats` component instead of a hardcoded value. Fleet Foot then becomes a vanilla passive with `stat_bonus_formulas[MOVEMENT_SPEED]` (percent), exactly like every other stat-bonus passive. Server-authoritative for free because `Stats` is already on the server side.
- **(b) Skip the stat system entirely** and write a custom `AL_FleetFoot.gd` passive that pokes the player's `SPEED` directly on level-up / login. Faster to ship, but it means movement speed lives in two places, future passives/buffs that touch speed all need bespoke code, and you have to handle the level-down / respec / disconnect cases by hand.
- **(c) Express it as a permanent self-buff** the passive grants on learn/level (re-use the buff system, like Haste does at runtime). Buys you stacking semantics for free but introduces "is this buff actually a passive?" confusion in saves and UI.

**My recommendation is (a).** Movement speed is going to come up again (boots, run-speed quests, slow debuffs, mounts down the road). Building it as a first-class stat once is cheaper than patching every future system that wants to touch it. It's also the only option where the server-authority story is trivial: the existing `Stats` component is already the source of truth, and the existing buff/equipment/ability machinery already broadcasts it.

Which path do you want to go down — (a), (b), (c), or something else? If (a), the next thing I want to grill is the client–server split for movement: even after we promote the stat, the client predicts its own position locally, so we have to be deliberate about how the new `move_speed` value reaches `move.gd` on every peer without letting a tampered client pretend it has +500%.
