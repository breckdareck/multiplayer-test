# Ability & Upgrade Design Review — weapon-identity overhaul

**Date:** 2026-06-10
**Scope:** `feat/weapon-identity-overhaul` — `resources/Abilities/**` (80 abilities, 347 upgrades),
`scripts/Resources/AbilitySystem/`, `scripts/Components/ability.gd`
**Prompted by:** [How To Design Abilities For Your Game](https://www.youtube.com/watch?v=mTaPBEfM524)
(YouTube, June 2026) — a video on structuring ability systems in game development.
The video itself is not fetchable from this environment, so the design yardstick below is
assembled from established written sources on the same topic (cited at the bottom); the
verdicts come from auditing the actual `.tres` data and its code consumers.

## The yardstick

The recurring principles in ability-system design literature:

1. **Data-driven, composition-based structure** — abilities as data assets with pluggable
   behavior, because you can't predict the final ability list up front.
2. **Clear levers** — cooldown, cost, and targeting as explicit, balanceable knobs.
3. **Upgrades should change decisions, not just numbers** — pure stat bumps feel hollow;
   the memorable upgrades alter *how* an ability plays (Hades boons, TF2 sidegrades).
4. **Mutually exclusive choices create builds** — "pick 1 of N" forces identity; stacking
   everything creates none.
5. **No dominant option** — if one choice is strictly best, the others are noise.

## How the overhaul measures up

### Architecture: strong, fully aligned with principle 1–2

`AbilityData` (.tres) + `ActiveBehaviorData` + per-stat `AbilityScalingFormula` +
`AL_*.gd` logic scripts + string `effect_key` dispatch is exactly the composition shape
the literature prescribes. Upgrade purchase is server-authoritative with tier gating and
variant mutex enforced in `ability.gd` (`can_purchase_upgrade`), and tooltips resolve
`$[placeholder]` tokens per level — the clarity lever is built in.

### Structural audit: clean

Mechanical cross-check of all 347 upgrade `.tres` files against the 80 ability files and
every `scripts/**/*.gd` consumer:

| Invariant | Result |
|---|---|
| Orphan upgrade files (referenced by no ability) | **0** |
| Upgrades referenced by more than one ability | **0** |
| Broken/missing upgrade references | **0** |
| Distinct `effect_key`s with no consumer in code | **0 of 87** |
| Upgrades missing `effect_key` or with magnitude 0 | **0** |
| Tier-vs-magnitude inversions (higher tier weaker) | **0** |
| Description numbers contradicting magnitudes | **0** (delta-vs-total phrasing accounted for) |

The tier scheme is uniform: actives carry **T1 (1 pt broad modifier) → T2 (1 pt mechanical
augment) → T3 (2 pt, pick-1-of-3 mutex variants)**; regular passives carry a 3-step
T1/T2/T3 chain. Each weapon additionally has exactly **one signature passive with a full
5-upgrade tree** tied to its identity mechanic — Vanguard's Resolve (Sword/combo),
Wind Rider (Bow/Momentum), Predator's Patience (Dagger/Patience stacks), Elemental
Affinity (Staff/element cycle). That symmetry is deliberate and good.

Per-weapon totals: 13 tree actives × 5 + 1 signature passive × 5 + 6 passives × 3 = **88**
for Sword, Staff, Dagger — **83 for Bow** (see finding 1).

### Things that look like issues but are not

- **Shared `(tree_path, tree_depth)` rows** (16 across all weapons) are by design:
  `tree_depth` is only a sort key in `skill_tree_canvas.gd`, and the climb-gate is
  disabled (free-pick, 2026-05-30). Not collisions.
- **Snap Shot (Bow) having 0 upgrades / max_level 1** is intentional: it is the bow's
  basic auto-attack, routed via `attack.gd` — the ranged counterpart of root `A_FMA.tres`.
- **Missing `tier`/`point_cost` lines in many `.tres` files** mean the script defaults
  (1 and 1) — Godot's re-save strips default-valued properties. The data matches the
  documented scheme exactly.
- **`U_SW_Inexhaustible` (Second Wind T3) having no `variant_group`** matches every other
  single-T3 passive; mutex is only needed where 3 variants exist.

## Findings (ranked)

### 1. Bow has one fewer real ability than every other discipline

Bow fields **12 tree actives** vs 13 for Sword/Staff/Dagger (Dagger's 13th is the off-tree
Shadow Partner; Bow's 20th file slot is consumed by the Snap Shot basic attack). Net
effect: bow players get **83 upgrade points of customization vs 88** and one fewer button.
If intentional (Momentum compensates), record it; otherwise Bow is owed a 13th active.

### 2. 15 of 55 T3 variant trios offer no behavior-changing option

The video's central thesis area. 40 of 55 trios include at least one genuinely
transformative pick (Shadowstep: i-frames vs backstab-window vs stealth; Frost Patch:
slow vs duration vs freeze-on-enter; Spellweave: zone vs double-release vs MP refund).
The other 15 are three flavors of "+number":

- **Identical `{+damage, +hits, +targets}` trio (12):** Snipe, Split Shot, Skyfall,
  Hailstorm (Bow); Eviscerate, Twin Fang, Fan of Knives (Dagger); Arcane Bolt,
  Arcane Lance, Glacial Spike, Pyre Burst (Staff); Vault Strike (Sword).
- **`{+damage, +targets, −cooldown}` (2):** Disengage (Bow), Cripple (Dagger).
- **All-QoL (1):** Bulwark Stance (Sword) — see finding 3.

Partial defense: `bonus_hits` feeds Momentum/combo generation, so the trio does encode a
bossing / mobbing / resource-feeding choice. But twelve abilities sharing the exact same
trio reads as generator output, not design. These are the deepening candidates — each
ability ideally gets at least one variant that changes *how it plays*, in the vein of the
40 good ones.

### 3. Bulwark Stance's tree is the flattest in the game

T1 = +10s duration, T2 = −4 mana, T3 = pick of {+20s duration, −8 mana, −5s cooldown}.
Every node is QoL; two T3 variants duplicate the effects of the lower tiers of the *same
ability* (duration-on-duration, mana-on-mana). With a 30s cooldown, the +20s duration
variant likely approaches permanent uptime — a dominant pick (violates principle 5).
A defensive-identity T3 trio (e.g. reflect / damage-reduction-while-active / ally aura)
would fix both problems at once.

### 4. Filename-prefix drift on ~20 upgrade files (maintenance hazard, not a bug)

The contents are coherent — names, descriptions, and effects all correctly reference
their owning ability — but the file prefixes lie about ownership:

| Files | Prefix suggests | Actually owned by |
|---|---|---|
| `Bow/U_IH_Ironclad/Calloused/Thick` | "Iron Hide"? | Marksman's Focus |
| `Bow/U_DR_Boundless/Wellspring/Capacity` | "Deep Reserves"? | Tailwind |
| `Bow/U_FF_Nimble/Quick/LightningReflexes` | "Fleet Foot"? | Execution |
| `Dagger/U_SST_DoubleCut/Ambush/Whirl/Cutpurse` | old Shadowstep names | Shadowstep (renamed effects) |
| `Dagger/U_VIG_Stalwart/Robust/Hardy` | "Vigor"? | Cutthroat |
| `Dagger/U_LUK_Fortunate/Lucky/Blessed` | "Luck"? | Composure |
| `Dagger/U_DPK_Deep/Bottomless` | "Deep Pockets"? | Opportunist |

Leftovers from earlier ability designs that were repurposed in place. Worth a rename pass
(filenames only — uids keep references intact) before the content set grows further.

### 5. Display-name collisions (cosmetic)

- Upgrade **"Assassinate"** exists on both Eviscerate (T3) and Opportunist (T2).
- Opportunist's T1 upgrade is named **"Backstab"** — also the name of a full ability.
- Arcane Lance's T3 **"Overload"** shares its name with the Staff passive ability.

Confusing in tooltips, chat links, and search. Cheap to rename.

### 6. One-off effect-key naming inconsistency

`U_MNS_heavy_surge.tres` uses `effect_key = "bonus_damage_bonus"` — the only upgrade in
the dataset not using `bonus_damage_mult` for a damage multiplier. It *is* consumed in
code (zero dead keys), but the near-identical name invites a future copy-paste bug.

### 7. Latent: `on_damaged` proc has no dispatch site

Carried over from `tools/upgrade_audit_report.py`'s own notes: any future passive using
`on_damaged_proc` will silently never fire. Add the dispatch or a loud assert before
authoring content against it.

## Status update (2026-06-10, later the same day)

All findings below were addressed on `feat/weapon-identity-overhaul`
(commits `18964d55`, `d7479337`, `5f03bd47`, `860509f1`):

1. **Fixed** — Bow gained Gale Pierce (path B depth 5), the Momentum-builder
   counterpart to Sundering Arrow; Bow now matches the other disciplines'
   13 actives / 88 upgrade points.
2. **Fixed** — each of the 15 numeric-only T3 trios now has at least one
   behavior-changing variant wired to its weapon's identity system.
3. **Fixed** — Bulwark Stance's T3s are now Counter Stance (reflect) /
   Immovable (damage reduction) / Unyielding Vigil (no MP drain).
4. **Fixed** — 62 drifted upgrade files renamed to their owners' prefixes.
5. **Fixed** — "Assassinate"/"Backstab"/"Overload" upgrade-name collisions
   renamed away.
6. **Fixed** — `bonus_damage_bonus` → `bonus_mark_damage`.
7. **Fixed** (`cb59fdd9`) — `on_damaged` procs now dispatch via the Health
   component's `damaged` signal in `AbilityComponent`. Verified headless with
   Godot 4.5: 119/119 unit tests pass; all 81 ability `.tres` load cleanly.

## Suggested order of attack

1. Decide Bow's 13th active (or document the 12+Momentum tradeoff). — finding 1
2. Redesign Bulwark Stance's T3 trio. — finding 3
3. Sweep the 12 identical `{dmg,hits,targets}` trios, one behavioral variant each. — finding 2
4. Filename + display-name rename pass. — findings 4, 5
5. Normalize `bonus_damage_bonus` → distinct or documented. — finding 6

## Sources

- [How To Design Abilities For Your Game](https://www.youtube.com/watch?v=mTaPBEfM524) — the prompting video (title/topic verified via search; content not directly accessible from this environment)
- [How to Power up Players with Upgrades — Game Developer](https://www.gamedeveloper.com/design/how-to-power-up-players-with-upgrades)
- [The Impurities of Pure Upgrades in Game Design — Game Wisdom](https://game-wisdom.com/critical/impurities-upgrades-game-design)
- [Building Counterplay — CritPoints](https://critpoints.net/2025/05/06/building-counterplay-for-pvp-games/)
- [Designing a Flexible Ability System for Games — Medium](https://medium.com/@galiullinnikolai/designing-a-flexible-ability-system-for-games-1e2ba31beee1)
- [Gameplay Ability System — Unreal Engine docs](https://dev.epicgames.com/documentation/en-us/unreal-engine/gameplay-ability-system-for-unreal-engine) (the GAS shape our AbilityData/effect_key system mirrors)
