# Research: Cross-Discipline Synergy & Upgrade Juice

**Date:** 2026-06-10 · **Scope:** `feat/weapon-identity-overhaul` ability kits, the
weapon-pair synergy layer, and the upgrade system · **Prompt:** "abilities don't mesh
enough between disciplines, and the upgrades are still very plain — research how to
add juice."

---

## 1. What actually exists today (inventory before design)

### 1a. The pair-synergy layer is real — and nobody can see it

`scripts/Components/weapon_pair_synergy.gd` already implements an automatic effect for
**all six weapon pairs** (several bidirectional — ~10 directional effects):

| Pair | Active weapon | Effect | Magnitude |
|---|---|---|---|
| Sword+Staff | Sword | Sword *abilities* carry the staff stance's element rider | rider's own numbers |
| Sword+Staff | Staff | Spell spends banked Combo for a magic burst | hit × combo(0–3) × 0.5 |
| Sword+Bow | Bow | Bow hits **bank** a Combo point (Combo persists across swap) | +1/hit, cap 3 |
| Sword+Dagger | Sword | Sword abilities apply Poison DoT | 6%/tick, 5 stacks, 4 s |
| Sword+Dagger | Dagger | Ambush spends banked Combo for bonus damage | hit × combo × 0.5 |
| Bow+Staff | Bow | Arrows carry the stance rider | rider's numbers |
| Bow+Staff | Staff | Spell rides the Momentum ramp (persists across swap) | hit × stacks × 3.5% |
| Bow+Dagger | Bow | Hits charge a swap-buffer **and** apply Poison | +1/hit, cap 10 |
| Bow+Dagger | Dagger | Ambush spends the buffer | hit × charge × 0.15 |
| Staff+Dagger | Dagger | Ambush carries the stance element | rider's numbers |
| Staff+Dagger | Staff | Spells apply Poison ("venom mage") | 6%/tick DoT |

It is server-authoritative, swap-aware, and even emits a `synergy_proc(pair_key)`
signal to the owning client for a widget flash.

**So why does it not *feel* synergistic?** Three reasons, and they frame everything
below:

1. **It is invisible and unbuildable.** No ability description, no upgrade, no
   tooltip references any pair effect. Zero of the 352 upgrades touch the pair layer
   — you cannot invest in a synergy, deepen it, or build around it. It's ambient
   flavor, not a build axis. (Hades' lesson: the *named, gated* duo boon is what
   makes players plan around two gods.)
2. **Ability states are weapon-siloed.** The content layer is full of states —
   bleeds (`hemorrhage_bleed`, Barbed Shot's, `synergy_poison`), burns
   (`immolate_burn`, `pyre_burst_burn`, stance burn), chill/freeze, shock, four mark
   types, the weaken channel, the DR channel — but every consumer only reacts to its
   *own weapon's* states. A staff burn means nothing to a sword swing; a sword bleed
   means nothing to Glacial Spike. There are primers everywhere and no detonators.
3. **The upgrades read as plumbing.** Even after the T3 behavioral pass, T1/T2 are
   flat numbers, payoffs are silent (a lifesteal or a slow with no sting, no flash,
   no sound), and no upgrade changes what an ability *looks or sounds* like. Juice
   research is blunt about this: power you can't perceive doesn't register as power.

### 1b. The raw material for synergy glue (already in the codebase)

- **Gauges:** Sword Combo (build/spend, cap 3, persistent), Bow Momentum (10 stacks
  × 3.5%, persists sheathed, Snipe spends), Dagger Shadowmeld/ambush + Patience
  stacks, Staff element stance (fire/ice/lightning, never clears).
- **Target-stamped states (metas):** 3 bleed channels, 2 burn channels + stance
  burn, chill + hard freeze, shock, poison, 4 marks (Sentinel/Death/Hunt/Resonance),
  weaken (choke), each with documented apply sites.
- **Delivery channels:** `try_trigger_procs` event bus, the post-hit rider section in
  `combat.gd`, `VfxCatalog` + `broadcast_vfx_everywhere`, `DmgNumberSpawner` combo
  display, `AudioManager.play_sfx_for_map`, and the already-wired `synergy_proc`
  client signal.

This matters because **every proposal below is a recombination of existing parts** —
no new architecture is required.

---

## 2. External patterns worth stealing

| Source | Pattern | Transferable lesson |
|---|---|---|
| [Hades duo boons](https://hades.fandom.com/wiki/Duo_Boons) | Every god *pair* shares one named boon, gated on owning prerequisites from both | A synergy must be **named, visible, and gated on commitment to both sides** to drive builds; 28 duos for 8 gods ≈ our 6 pairs need ~6 marquee effects |
| [Genshin elemental reactions](https://genshin-impact.fandom.com/wiki/Elemental_Reaction) | Element B applied onto element A's aura triggers a *rule* (melt, freeze, overload) | **Primer + trigger as modular rules**, not bespoke ability pairs — N states × M triggers scales content for free |
| [Outriders primer/detonator](https://outriders.wiki.fextralife.com/Detonator), [Divinity surfaces](https://fextralife.com/divinity-original-sin-2-party-combinations-guide-magic-physical-and-mixed/) | Statuses are split into "set up" and "pay off" classes | Make the payoff a **visible burst** (detonation), not a passive multiplier — detonation is legible and juicy |
| [Diablo 4 aspects](https://maxroll.gg/d4/wiki/legendary-aspects) | The best-loved powers "add new interactions between skills" | Upgrades should create **cross-ability sentences** ("X now feeds Y"), not adjectives ("X bigger") |
| [PoE support gems](https://www.poewiki.net/wiki/Support_gem) | Generic modifiers attach to many skills | Our generic `effect_key`s (`bonus_momentum_per_hit`, `bonus_slow_on_hit`, `bonus_mp_on_hit`) are proto-supports — lean into reusable keys over bespoke ones |
| [Juice it or Lose it / Vlambeer school](https://www.cobble.games/wise-inspiring-smart/game-design/juice-it-or-lose-it), [GameAnalytics on juice](https://www.gameanalytics.com/blog/squeezing-more-juice-out-of-your-game-design) | Amplify feedback on every meaningful event | Every owned upgrade and every synergy proc needs a **tell**: distinct color, number style, sound, or shake |

---

## 3. Proposal A — Reactions: cross-weapon primers & detonators

The Genshin/Outriders shape, built on the metas we already stamp. One server-side
rule table in the `combat.gd` post-hit rider section (right beside the existing
staff-element and momentum riders) that checks the *target's* states against the
*hit's* discipline:

| # | Reaction (name shown on proc) | Primer (any source) | Trigger | Payoff |
|---|---|---|---|---|
| R1 | **Scald** | Burn (any burn channel) | Ice/chill application | Consume burn → burst = remaining burn ticks × 1.5, AoE steam puff |
| R2 | **Rupture** | Bleed ≥ 2 stacks | A combo-spending sword finisher | Consume bleed → instant remaining-bleed damage + brief stagger |
| R3 | **Toxic Shock** | Poison | Lightning shock rider | Poison ticks twice as fast for 3 s (purple spark tell) |
| R4 | **Shatter** | Hard freeze (`glacial_freeze`) | Any physical *ability* hit (sword/bow/dagger) | Consume freeze → +50% on that hit, ice-break VFX |
| R5 | **Exposed Quarry** | Any mark | Hit from the *other* equipped weapon | +15% damage vs marked for that hit (mark glint) |
| R6 | **Smothered** | Weaken (choke channel) | Smoke/ambush source | Extends weaken 2 s on dagger hits |

Why this works here specifically: primers are already stamped as target metas with
expiry — each rule is a ~15-line read-consume-burst block, exactly the
`spread_on_death` / choke-channel idiom that already ships. Reactions also make the
*pair layer* legible retroactively: Sword+Staff stops being "ambient rider" and
becomes "I freeze with my off-hand stance, then **Shatter** with Earthsplitter."

**Gating (the duo-boon lesson):** don't give reactions away free. Two options —
(a) each reaction unlocks via a 2-pt upgrade on the relevant signature passive
(Wind Rider, Vanguard's Resolve, Predator's Patience, Elemental Affinity get a 6th
"reaction" node), or (b) reactions are innate but weak, and upgrades amplify them.
Option (a) is recommended: it makes the signature passives the home of
cross-discipline identity, which they already thematically are.

## 4. Proposal B — Duo upgrades: make ~12 upgrades pair-aware

Pick one existing T2 or T3 slot on 2–3 abilities per weapon and rewrite it as a
**pair-aware sentence** (these replace the plainest remaining numeric nodes):

- *Snipe — "Stancebreaker Shot":* Snipe also consumes your staff stance's element,
  detonating any matching DoT on the target (requires staff equipped).
- *Crescent Cleave — "Bloodwind Cleave":* enemies bled by **any** source take +20%
  from Cleave (sword detonating bow/dagger bleeds).
- *Glacial Spike — "Deep Shatter":* your Shatter reactions (R4) deal +40%.
- *Fan of Knives — "Venom Carrier":* blades refresh the synergy poison's duration.
- *Charge! — "Bannerman's Rush":* piercing a marked enemy spreads the mark.

Mechanically these are ordinary `effect_key`s read at the reaction/rider sites — the
same pattern as `reaction_any_stance`. Budget: ~12 upgrades touched, no new systems.

## 5. Proposal C — the juice pass (cheap, high leverage)

Everything here uses delivery channels that already exist:

1. **Synergy procs get a face.** `synergy_proc` already reaches the client; add a
   per-pair VFX key in `VfxCatalog` (6 colorways), a short SFX stinger per pair
   (`tools/gen_ability_sfx.py` can synthesize them), and render synergy/reaction
   bonus damage through `DmgNumberSpawner` in a distinct color + the reaction's name
   ("SCALD 142"). Named floating text is the single biggest legibility win.
2. **Owned upgrades change the ability's look.** Precedent already in-repo: Glacial
   Spike's freeze tints the enemy. Extend the idiom — Permafrost = deeper blue trail,
   Fang and Vein = red lifesteal wisp, Hurricane Draw = green wind streaks on the
   arrow. One `hit_vfx`/tint override per owned T3 (the `ActiveBehaviorData`
   override field already exists).
3. **Gauge moments.** Momentum cap reached / 3-combo banked while the *other* weapon
   is active = tiny screen pulse + click sound, teaching the swap rhythm without a
   tutorial.
4. **Tooltip surfacing.** Add a "Synergy:" line to ability tooltips when the
   relevant pair is equipped (the tooltip pipeline already resolves per-level
   placeholders; this is one more conditional line).

## 6. Recommended sequence

1. **C1 + C4 first** (procs get names/colors/sounds; tooltips surface the pair
   layer). Zero balance risk, makes the *existing* synergy layer feel new.
2. **A (reactions)**, gated via the signature passives — the build-defining core.
3. **B (duo upgrades)** to deepen whichever reactions playtests show are popular.
4. Re-run the balance report after A: reactions add burst, so DoT-heavy pairs
   (anything + Dagger) need watching for double-dipping.

## Sources

- [Hades Duo Boons — wiki](https://hades.fandom.com/wiki/Duo_Boons) · [duo-boon build analysis](https://gamerant.com/hades-best-duo-boons-guide/)
- [Genshin Impact Elemental Reactions — wiki](https://genshin-impact.fandom.com/wiki/Elemental_Reaction)
- [Outriders Detonator/primer system](https://outriders.wiki.fextralife.com/Detonator)
- [Divinity: Original Sin 2 — party/element combination guide](https://fextralife.com/divinity-original-sin-2-party-combinations-guide-magic-physical-and-mixed/)
- [Diablo 4 Legendary Aspects — Maxroll](https://maxroll.gg/d4/wiki/legendary-aspects)
- [Path of Exile support gems — PoE wiki](https://www.poewiki.net/wiki/Support_gem)
- [Juice it or Lose it (Jonasson & Purho) — summary](https://www.cobble.games/wise-inspiring-smart/game-design/juice-it-or-lose-it) · [GameAnalytics: Squeezing more juice out of your game design](https://www.gameanalytics.com/blog/squeezing-more-juice-out-of-your-game-design)
