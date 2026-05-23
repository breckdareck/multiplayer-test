Happy to grill this. Before I start poking the design as a whole, I need to surface something I found while skimming the relevant code, because it changes what "Fleet Foot" can even mean in this codebase.

**The contradiction**

`scripts/Core/Enums/constants.gd` defines `StatType` as:

```
STRENGTH, INTELLIGENCE, DEXTERITY, LUCK, HEALTH, MANA, HPREGEN, MPREGEN,
DEFENSE, MAGICDEFENSE, CRITCHANCE, CRITDAMAGE, WEAPONATTACK, MAGICATTACK,
KNOCKBACKRESIST
```

There is no `MOVEMENT_SPEED` (or anything equivalent) in `StatType`. Every existing passive ability I checked — e.g. `resources/Abilities/Rogue/A_Nimble_Step.tres` — grants its bonus through `AbilityScalingData.stat_bonus_formulas`, which writes into a `StatType` slot on the player's `Stats` component. Movement speed currently *isn't* one of those slots. It lives on the character's movement code (e.g. `EnemyData.movement_speed` for enemies), not in the stat system.

So "passive that increases movement speed by 5% per level" doesn't slot into the existing `.tres`-only passive recipe (`add-ability`) the way Nimble Step does. You'd be picking one of:

1. **Add `MOVEMENT_SPEED` to the `StatType` enum** and teach the player's movement code to read its `total_value` / `percent_bonus_value`. After that, Fleet Foot is a pure `.tres` — same shape as Nimble Step, just a different stat. Costs: enum changes ripple (saves, equipment, buffs, UI), and you have to decide what "+50% movement speed" actually multiplies (base walk speed? jump? dash?).
2. **Make it a buff with custom application logic** — a permanently-applied `BuffData` that nudges movement speed via a custom buff effect script, since the passive's data layer can't express it. Cheaper to ship, but it's now code-as-content (you said "passive ability," not "buff"), and you give up the `add-ability` skill recipe.
3. **Custom `AL_` ability logic script**, the documented exception path for abilities whose effect can't be expressed in pure data. Most flexible, least uniform with the other Rogue passives.

I'd pick **(1)** — Fleet Foot is the canary for a stat slot that's going to come up again the moment you add boots-with-+movement, a Haste-style buff that actually affects movement, a slow debuff, etc. Doing it once, properly, in the stat system is the server-authoritative move; the alternatives push movement-speed math out into a hundred little places.

But option 1 is also the most expensive, and it's the kind of decision that's hard to reverse later (every save and every equip path is downstream of `StatType`). So before we go any further down the Fleet Foot design tree:

**Which path do you want to take for "movement speed as a thing the stat system knows about" — extend `StatType`, or one of the workarounds?**
