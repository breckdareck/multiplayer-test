# Ability Synergy & Upgrade-Juice Research (2026-06-10)

Research pass for the "abilities don't mesh between disciplines + upgrades are plain"
complaint. Two inputs: a code-level map of the current ability/status/upgrade landscape
(this repo), and a survey of synergy mechanics in GW2, D4, Last Epoch, PoE, New World,
ESO, MapleStory, Hades, RoR2, Outriders, Magicka.

---

## 1. Diagnosis — why it doesn't mesh today

The synergy *plumbing* already exists (`scripts/Components/weapon_pair_synergy.gd`
covers all 6 weapon pairs; passives stack from both slots; combo/momentum/stance
persist off-hand). What's missing is the *payoff economy*:

**Statuses are applied and never consumed.** The apply-vs-consume matrix is almost
empty on the consume side:

| Status | Appliers | Consumers |
|---|---|---|
| Bleed (4 separate meta keys) | Hemorrhage, Barbed Shot, Death Mark T3, MotH T3 | **none** |
| Burn (3 separate meta keys) | Immolate, Pyre Burst, fire-stance rider | **none** |
| Slow/chill (5 separate meta keys) | staff chill, Frost Patch, Caltrops, Backstab, slow-on-hit upgrades | **none** |
| Poison | Envenom, Caltrops T3, pair-synergy imbue | Toxicology + Vendetta — but **only** `envenom_poison` |
| Marks (4) | Sentinel's/Hunter's/Death Mark, Mana Resonance | each consumed only by its **own** discipline |

Poison is the only status with a real apply→consume loop, and it's the proof the
shape works — Envenom → Toxicology (+30% vs poisoned) → Vendetta (spend stacks for
burst) is exactly the loop the whole game needs more of.

**Per-ability meta keys structurally block cross-ability synergy.** Every DoT uses
its own hardcoded string (`hemorrhage_bleed`, `barbed_shot_bleed`, …). There is no
shared "is_bleeding" query, so a "bonus vs bleeding" passive can't exist cleanly.
This was a deliberate per-ability-stacking convention, but it's now the main
infrastructure obstacle.

**Upgrades are numerically dominated.** Of ~280 upgrade .tres: `bonus_damage_mult`
×48, `passive_stat_flat_bonus` ×33, `cooldown_flat_reduction` ×27, `mana_flat_reduction`
×8. Nearly every T1 is one of these four inert number bumps. The upgrades that feel
good are the minority that reference a status, a gauge, or a shape
(`reaction_any_stance`, `bonus_mark_spread`, `combo_coefficient_override`).

**Bugs found during the audit (real today, pre-rework):**
1. `AL_Toxicology.gd` and `AL_Vendetta.gd` hardcode `envenom_poison` — poison from
   Caltrops T3 (`caltrops_poison`) and the dagger pair-synergy imbue (`synergy_poison`)
   is cosmetically visible but feeds neither the passive nor the spender. The
   sword/dagger + bow/dagger pairings' headline synergy is mechanically inert.
2. `enemy_base.gd` mark-indicator colors omit `mana_resonance_remaining` — Mana
   Surge's mark is invisible.

---

## 2. External patterns worth stealing (ranked for this game)

Full per-game breakdown + sources in the research agent transcript; distilled here.

### Tier A — directly address the complaint

**A1. Universal exploit-status, appliers/consumers split across kits**
(D4 Vulnerable, New World Rend, PoE exposure). One status whose whole purpose is
"the OTHER skill hits harder." New World is the closest topology (two 3-active
weapon kits) and its entire pairing meta is built on Rend/slow/Empower being applied
by one weapon and cashed by the other.
→ Unify bleed/poison/burn/chill into canonical stacking channels on the enemy, then
author consumers in *other* disciplines: "+X% vs bleeding" (staff passive), "Snipe
consumes burn for a detonation" (bow T3), etc.

**A2. Status escalation chains** (Outriders burn→ash→vulnerable; Magicka wet+cold=
frozen). Authored rules: status A + element B = effect C. Cheap to implement as
checks in a unified status-apply path, and they make a weapon *pairing* read as a
combined element. Examples: chill+burn = Thermal Shock burst (consumes both);
poison on bleeding = Septic (faster ticks); burn on chilled = extended slow.

**A3. Duo nodes — one authored upgrade per weapon pair** (Hades duo boons). 6 pairs
= 6 bespoke, named, VFX'd nodes that unlock with investment in both equipped trees
and braid the two kits' statuses/gauges. Hades shows these are the screenshot-able,
memorable answer to "my two kits don't talk." Highest legibility per content-dollar.

**A4. Weapon swap as a first-class trigger** (GW2 sigils w/ internal cooldown, ESO
bar-swap rotations). "On swap to sword: gain 2 combo points (9s ICD)", "on swap to
staff: next cast free", "swap converts unspent momentum → combo points". Turns the
swap button into a rotation beat. Currently the swap *event* triggers nothing.

### Tier B — strong supporting structure

**B5. Field + finisher matrix** (GW2 combos). Ground zones (Frost Patch, Caltrops,
fire pools, Banner, Smoke Bomb — already on GroundZone infra) become *typed fields*;
tag leaps/projectiles/dashes as finishers; small deterministic table (arrow through
fire pool = burn shots; Shadowstep through frost = AoE chill). Works cross-player
in parties for free — fits the soft-roles party model.

**B6. Scheduled procs over random procs** (D4 Overpower loops, MapleStory
Counterattack "every 20th hit"). Upgrades that make a payoff deterministic on a
countable condition — "every 3rd combo spender overpowers", "every 5th hit vs
marked is a guaranteed crit". Legible in a damage-number 2D game; no aim required.

**B7. Different-source multiplication** (RoR2 stacking math). Make cross-discipline
damage contributions separate multiplicative buckets (mark ×1.15, matched-status
×1.10) while same-discipline bonuses stay additive — then the optimizer math itself
tells players to diversify across both weapons.

**B8. Back-bar persistence** (ESO back-bar DoTs / front-bar spam). Each discipline
needs 2–3 abilities that keep working while stowed (banners, caltrops, pools,
familiar already qualify) with durations that comfortably outlast a swap cycle —
and upgrade text that advertises it ("persists while stowed").

### Tier C — later / optional

**C9. X-casts-Y trigger upgrades** (Last Epoch nodes, PoE supports) — T3 variants
that bolt a mini-cast of another ability onto hits, with ICDs. Powerful but needs
careful server-side bounding.
**C10. Stack-cap raised by second status** (Hades Low Tolerance: Hangover cap 5→8
while Weak) — only meaningful after statuses have visible stack counts.
**C11. Link-skill breadth rewards** (MapleStory) — mastery milestones in discipline
A emit a small class-neutral passive; fits the existing class-neutral-passives rule.

### The D4 cautionary tale (why "more numeric tiers" won't fix it)
D4's own 2026 Lord of Hatred skill-tree rework — per-skill numeric modifier ranks —
got divided reception for exactly this failure: exciting while novel, then
"monotonous… collapses into a single correct option once the math is solved." The
memorable D4 power is in aspects: effects that *change the verb* (spreads, triggers,
detonates, converts). Principle for every tier: **change the verb, not the number**,
and give every verb-change a visible tell (the existing `play_dot` convention is
the right instinct).

---

## 3. LOCKED plan (grilled 2026-06-10 — supersedes the proposal below)

Decisions from the grilling session. Glossary terms in CONTEXT.md: **status
tag**, **escalation rule**, **duo node**, **channeled ability**.

1. **Status layer = query layer over existing per-source keys (Q1).** Per-ability
   meta keys keep their independent stacking/tick math; a BleedDot-style static
   `EnemyStatus` helper maintains a per-enemy tag index (`bleed`/`poison`/`burn`/
   `chill`/`mark`) registered at apply time, lazily pruned. `stack_count` =
   **sum across sources**. ("Status tag", NOT "channel" — that word is taken
   twice over.)
2. **Tag state is enemy-global (Q2).** Reads AND spends ignore applier identity
   (FFA party philosophy; GW2 cross-player combos as a feature). Per-key
   tick/kill credit keeps last-refresher behavior — accepted quirk.
3. **Escalation rules = authored static code table (Q3),** 3 rules at launch
   (Thermal Shock / Septic / Brittle), hooked at the EnemyStatus chokepoint.
   Bursts scale off the *triggering* application's ability max hit × stacks
   consumed. Nothing consumes poison (Vendetta owns that channel of play).
4. **Duo nodes = stateless derived unlocks (Q4),** active while both equipped
   disciplines have ≥N points spent (N tunable, ~30). No purchase, no
   persistence, no reconcile-guard interaction, bots qualify automatically.
5. **Swap triggers live exclusively on duo nodes in v1 (Q5)** — one swap trigger
   + one standing pair rule per duo, authored in `weapon_pair_synergy.gd`
   (which already receives `on_weapon_state_changed`). ICD ~8s, transient
   server-side, never persisted. No in-combat gating. (A per-discipline swap
   passive would violate the passives-are-class-neutral rule.)
6. **Upgrade re-author is retroactive with stable structure (Q6):** upgrade_ids,
   point costs, tree shape never change — only effect_key + magnitude. Owned
   upgrades morph in place; no save migration; reconcile untouched. T3
   "pairing" variants reference **status tags and gauges, not the other weapon
   slot** (slot can be empty or same-discipline → dead purchase). Slot-pair
   flavor belongs to duo nodes only.
7. **Channeled-ability wind-up is broken and gets a standalone fix-PR first
   (Q7/Q8).** Root cause: `ability.gd` `_trigger_ability_state_change` calls
   `logic_script.execute()` same-frame; `cast_time` is only the post-hoc
   hitbox-window duration. Fix: opt-in wind-up on ActiveBehaviorData that
   defers execute + hitbox-on, driven in the attack state's `_process` (boss
   windup pattern, not SceneTreeTimers); uninterruptible except death/forced
   state change, no resource refund on cancel; peer-local wind-up clocks
   (server release stays the only authoritative one).
8. **Multiplicative cross-discipline bucket: PARKED (Q9).** Three new pairing
   rewards ship at once; adding a fourth inside the benchmarked `_execute_hit`
   makes balance unattributable. Revisit only if the post-v1 balance report
   shows optimal builds still ignore the off-weapon's statuses. Field/finisher
   table (old Phase 4) stays parked behind the same gate.
9. **Bots:** consumers/escalations/duo standing rules work for bots with zero
   bot work. Bots never swap weapons, so duo swap-triggers won't fire for them
   — accepted for v1; "bot swap cadence" is a future bot_brain item.

**PR sequence:**
- **PR A** — channeled-ability wind-up fix (blocks playtesting everything else).
- **PR B** — `EnemyStatus` tag registry + re-target Toxicology/Vendetta to the
  poison tag (fixes the caltrops/synergy_poison dead-end) + mana-resonance mark
  indicator + per-tag stack-count visuals. No balance change beyond the bugfixes.
- **PR C** — consumer economy: per discipline, 1 passive + 1–2 upgrades reacting
  to a tag the discipline doesn't apply well itself; the 3 escalation rules.
- **PR D** — duo nodes ×6 in weapon_pair_synergy + threshold UI surfacing.
- **PR E–H** — per-discipline T1/T2/T3 re-author passes (stable ids), one
  weapon per PR, regenerating the ability reference report each time.

---

## (superseded) Proposed shape for the rework (pre-grilling)

### Phase 0 — unify the status layer (enabling infrastructure)
Canonical per-enemy status channels (bleed/poison/burn/chill + marks) with stack
counts, replacing per-ability meta keys as the *query* surface (per-ability appliers
can keep independent DoT math underneath, but registration goes through one helper,
e.g. `EnemyStatus.apply(enemy, "bleed", stacks, source)` / `EnemyStatus.has(enemy,
"bleed")` / `count(enemy, "bleed")`). Fixes the Toxicology/Vendetta poison bug as a
side effect. Add stack-count to the DoT visuals. **Everything else keys off this.**

### Phase 1 — consumer economy
- Per discipline, add 1 passive + 1–2 ability upgrades that consume/react to a
  status the discipline does NOT apply well itself (A1).
- 3–4 authored escalation rules in the unified apply path (A2).
- Make marks cross-consumable: any discipline's spender gets a T-upgrade keying
  off "marked" generically.

### Phase 2 — pairing identity
- 6 duo nodes, one per weapon pair, gated on investment in both equipped trees (A3).
- On-swap triggers: 1 passive or T2 upgrade per discipline keyed to the swap event
  with an ICD (A4).
- Multiplicative bucket for cross-discipline statuses in `_execute_hit` (B7).

### Phase 3 — upgrade-tier re-author pass (the "plain upgrades" fix)
Tier templates applied across all ~80 trees:
- **T1**: conditional numeric or gauge-economy only — "+15% vs bleeding", "+1 max
  momentum", "combo decays 4s slower". Ban bare `bonus_damage_mult` /
  `cooldown_flat_reduction` at T1 (or demote them to ability *levels*, which already
  carry the raw numbers).
- **T2**: one of (a) on-swap / while-stowed clause, (b) field/finisher tag, (c)
  scheduled proc ("every Nth …").
- **T3 (1-of-3)**: variant 1 = solo transform (current style), variant 2 = status/
  element transform, **variant 3 = pairing transform that references "your other
  equipped weapon"** — guarantees every tree contains a reason to think about the
  pair, and reads differently with each partner.

### Phase 4 — field/finisher table (B5) once Phases 0–3 are proven.

Open questions to grill before building:
- Does Phase 0 keep per-ability DoT stacking (project convention: burn pools
  per-ability) under a unified query layer, or collapse to shared channels with
  caps? (Recommend: keep per-source math, unify the query + visuals.)
- Duo-node point cost & where it lives in the UI (per-ability tree vs a new
  pair panel on the ability window).
- Server-side bounding rules for any X-casts-Y upgrades (ICD storage per enemy or
  per player?).
- Balance: B7's multiplicative buckets are power creep — pair with a glance at the
  attack curve.
