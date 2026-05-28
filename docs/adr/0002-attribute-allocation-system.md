# Attribute allocation system — manual AP (convert level-scaling), 5 dual-role attributes, new CON stat, mastery stays auto

**Status:** Accepted (2026-05-28) — design locked; the build is **PR 7**, bundled with the **full removal of Job Advancement** (user-confirmed: classes don't exist, only weapons). The `attribute_points` backend column still requires explicit sign-off before the `backend/app.py` change — build the client/server/UI + class removal first, apply the backend column last after approval.

## Context

Today a character's STR/DEX/INT/LUCK are 100% auto-derived — the player makes **no** allocation choice. `StatsComponent` applies two automatic sources on top of the StatData base floor:

1. **Character-level scaling:** `stats[stat].base_value += class_disc.stat_bonuses[stat] * (level - 1)`. Every discipline's `stat_bonuses` sums to **5/level** (Sword 3 STR + 2 DEX; Bow 2 STR + 3 DEX; Mage 3 INT + 2 LUCK; Rogue 2 DEX + 3 LUCK).
2. **Mastery scaling:** the same `stat_bonuses` applied per *weapon-mastery* level of the wielded discipline.

This gives no room for player identity: a sword main can't choose to be a CON tank, a sword/staff hybrid can't dip INT, and there's no "constitution" lever for survivability. The project's differentiation north star is New World's weapon-driven identity + freely-allocated attributes with breakpoint utilities (see `memory/project_differentiation_direction.md`). This ADR converts the **character-level** stat budget into a manually-allocated attribute pool, adds a fifth attribute (CON), and gives every attribute a **secondary utility** so off-weapon investment is meaningful.

The damage formula already supports hybrids: `_calculate_max_range()` reads `(primary_stat × 4 + secondary_stat) × WeaponAttack / 100` using the *current weapon's* primary/secondary, so attribute points sunk into a non-scaling attribute simply don't help that weapon — the hybrid tradeoff is automatic.

## Decision

### 1. Five attributes, each with a damage role AND a secondary utility

| Attribute | Weapon damage role | Secondary utility (feeds existing stat) |
|---|---|---|
| **STR** | Sword **primary** (×4); Bow secondary | **+Physical Defense** (`DEFENSE`) |
| **DEX** | Bow & Dagger **primary**; Sword secondary | **+Accuracy / hit chance** |
| **INT** | Staff **primary** | **+Max Mana + MP Regen** (`MANA` / `MPREGEN`) |
| **LUCK** | Dagger **primary**; Mage secondary | **+Base Crit %** (`CRITCHANCE`) — crit *damage* lives on gear |
| **CON** *(new)* | none | **+Max HP + HP Regen** (`HEALTH` / `HPREGEN`) |

Each of the four damage attributes is the primary of exactly one weapon, so they stay distinct. **Resource-stat symmetry:** the two resource attributes (CON, INT) each give **pool + regen**; the three others give a single utility. The secondary utilities make every attribute worth a partial investment to *someone*: a mana-hungry sword user dips INT, a low-crit build dips LUCK, a front-liner stacks CON + STR. STR→Defense and CON→HP form a clean two-axis tank model (mitigation vs. effective-HP pool); DEX→Accuracy gives sword mains genuine tension (pure STR = max hit damage but more whiffs vs. tough mobs; a DEX splash = fewer misses + a little secondary damage).

**Crit split:** LUCK drives crit *rate* (frequency — the dagger fantasy, and a universally useful dip), while crit *damage* (the multiplicative partner) scales from **gear**. Rationale: crit rate is valuable to any damage build (good dip value); crit damage is conditional (worthless without rate), so it would be dead weight on an attribute meant for partial investment. At a modest ~0.1%/LUCK the contribution only nears the 100% cap at the top of the 495-AP pool, so points rarely fully waste.

**Considered alternatives:**
- *Damage-only attributes (no utility):* rejected — makes every non-primary point dead weight, kills the hybrid/tank fantasy the user asked for.
- *A separate "Accuracy"/"Vitality" stat instead of folding into DEX/CON:* rejected — more attributes to balance and allocate; folding utility onto the five keeps the UI and the math compact.

### 2. Allocation model — convert character-level scaling into a manual AP pool; mastery stays auto

- **Grant 5 attribute points per level-up**, pool size `= 5 × (level − 1)` = **495 at the level-100 cap** (identical to the budget the weapon discipline auto-assigned before, so total stat budget is unchanged). **This overhaul has no classes — only weapons** (level 30 unlocks more weapons; it does NOT advance a class), so the per-level rate is a uniform **5/level** across all four weapon disciplines. (An earlier draft cited "7/level advanced classes → 693 AP" — that came from reading the legacy class-advancement code, `JobAdvancementManager` + the `ASSASSIN`/`CRUSADER`/etc. scaling in `stats.gd`. That system contradicts the weapon-only direction and the overhaul should neutralize it; `current_class` stays the fixed STARTING weapon discipline.)
- The player allocates freely across STR / DEX / INT / LUCK / CON.
- **Mastery scaling stays automatic and unchanged** — wielding a sword still auto-grants that discipline's `stat_bonuses` (+3 STR / +2 DEX) per mastery level. This keeps weapon identity reinforced by what you actually *use*, so even a CON-heavy sword main still accrues some STR from mastery.
- **Base floor unchanged** (StatData base value per attribute).
- Weapon damage scaling math (`_calculate_max_range`) is **untouched** — it still reads the current weapon's primary/secondary, so allocation choice flows through it automatically.

**Considered alternatives:**
- *Additive small pool on top of full auto-scaling:* rejected by the user — the auto-scaling still rails you toward the class default, so hybrids/tanks only get a light nudge.
- *Auto primary/secondary + manual only for CON/off-stats:* rejected by the user in favor of full New-World freedom.

### 3. CON is a NEW StatType, appended at the end of the enum

`Constants.StatType` currently ends at `KNOCKBACKRESIST = 14`. **CONSTITUTION must be appended (index 15)**, never inserted — every persisted `stat_type` int in save data and `.tres` resources (e.g. passive `stat_bonus_formulas`, buff `stat_modifiers`) is positional, so renumbering would silently corrupt them. CON is an *attribute* that contributes to the existing `HEALTH` derived stat; it is not itself a derived stat.

### 4. Secondary-utility wiring (in `StatsComponent` aggregation)

Each attribute adds a contribution to its utility stat during aggregation (alongside the existing base/class/equipment/buff/passive sources). Proposed starting rates — **all tunable, to be verified against the live crit/defense/hit formulas at implementation**:

| Source | Contribution (starting proposal) |
|---|---|
| STR → DEFENSE | +1 Defense per STR |
| DEX → Accuracy | +hit-chance term per DEX (calibrate to the existing level-diff hit formula) |
| INT → MANA + MPREGEN | +5 Max Mana per INT + small MP regen per INT |
| LUCK → CRITCHANCE | +0.1% crit per LUCK (100 LUCK ⇒ +10%); crit *damage* comes from gear |
| CON → HEALTH + HPREGEN | +8 Max HP per CON (additive on the class HP curve) + small HP regen per CON |

The class HP curve (`CLASS_BASE_MAX_HEALTH + CLASS_HEALTH_SCALING × (level-1)`) stays as the baseline; CON is purely additive on top, so it is the deliberate tank lever without removing the class's innate bulk.

### 5. Respec + a reconcile invariant (parallel to ability points)

- A respec returns all allocated AP to the unused pool (free for v1; a gold cost is an open question). Server-authoritative via a `respec_attributes_request` RPC, mirroring the ability-respec pattern.
- **Invariant (mirrors the ability-point rule):** `granted (5 × (level−1)) == spent + unused`. A `reconcile_attribute_points()` runs on load and corrects drift either way — and makes the 5-AP/level grant retroactive for existing characters exactly like `reconcile_ability_points()` did for the grant change. Reuse that proven shape.

### 6. Persistence — NEW backend column (REQUIRES APPROVAL)

Proposed: a `attribute_points` JSONB column on `Player` storing the *spent* allocation `{str, dex, int, luck, con}` (unused is derived = granted − spent). Mirrors `ability_points_per_discipline` exactly: save handler destructures it, load response returns it, idempotent `ALTER TABLE` in `_run_migrations`, container restart to apply. **No backend edit will be made until this column is explicitly approved** (per `feedback_backend_changes_require_explicit_approval`).

### 7. UI — allocation lives in the Stats window

The existing Stats window gains a per-attribute row with +/− allocation buttons, an "unused AP" counter, and a Respec button — same affordance language as the Ability Window's point spend. No new window.

### 8. Migration — default-allocate to the old split, so nothing changes until the player respecs

On first load after the feature ships, an existing character's pool (`5 × (level−1)`) is **default-allocated to their class's historical ratio** (Sword → 3:2 STR:DEX, etc.), reproducing their current stats exactly. They lose nothing; they opt into customization by respeccing. CON starts at 0 for everyone (it's new budget-neutral headroom they can respec into).

## Consequences

- **Specialization is stronger than the old forced split.** Verified on a L100 dagger wielder (2026-05-28, no class advancement): pure-primary (all 5/level into LUCK = 495) vs. the forced dagger split (297 LUCK + 198 DEX) is **+43%** on the discipline contribution to the `(primary×4 + secondary)` multiplier. Intended (New World rewards specialization) but it raises the ceiling — likely needs the primary multiplier cut (×4 → ×3), a **soft cap / diminishing returns**, or enemy scaling. **Central balance decision** (Open Questions #1).
- **WEAPONATTACK (from gear) dwarfs attributes at endgame.** It has base 0 and is a flat linear multiplier, so it's entirely gear-driven; the verified Eternal Dirk roll alone (WEAPONATTACK 99→197) *doubles* the max basic hit (2,767→5,506). Attribute reallocation moves damage far less than a weapon upgrade — so the attribute system is more about *identity/utility* (CON tank, hybrid, crit) than raw DPS, which lowers the urgency of the specialization spike above but doesn't remove it.
- **Crit is a dead stat without a CRITDAMAGE source.** Live `CRITDAMAGE` base is 0 with nothing feeding it, so crits are only ×1.2–1.5 — making crit *chance* low-value. LUCK→crit-rate only pays off if crit *damage* gets a real source (the ADR's "crit damage on gear" — this must actually ship, or crit stays a trap).
- **Large endgame pool (495 AP at L100)** means breakpoints/soft-caps matter more than at L30 (145 AP). Linear utilities are simplest but a single attribute stacked to ~495 could trivialize its utility stat (e.g., crit cap, defense cap) — utility stats that can break the game (crit %, defense) need their own caps.
- **CON is budget-neutral but additive to survivability**, so the realistic concern is the *opposite* of a nerf: every build can now buy raw EHP it couldn't before. HP-per-CON must be tuned so a dedicated tank is durable without being unkillable, and a 0-CON glass cannon is appropriately fragile.
- **Append-only enum** constraint is permanent: CON at index 15, and any future attribute also appends.
- **Two parallel point economies** now exist (ability points per discipline; attribute points per character). Both follow the same granted == spent + unused reconcile invariant — consistent mental model, but two reconcile passes on load.
- **Backend approval gate** blocks the persistence slice; the client/server attribute logic + UI can be prototyped first behind that gate if desired.
- **Mastery still auto-grants stats**, so a weapon you actually wield always contributes some of its scaling attribute regardless of allocation — a CON-stacked sword main is never at literally 0 STR-from-progression.

## Resolved decisions (2026-05-28)

1. **Damage ceiling** — **Launch with the current ×4 primary multiplier, NO preemptive nerf.** Gear WEAPONATTACK dominates damage anyway, so the +43% pure-primary spike is secondary; rather than nerf existing feel up front, add a **soft diminishing-returns curve as a fast-follow tuning knob** only if playtest shows runaway. Reversible, low-risk.
2. **Linear vs. breakpoint utilities** — **Linear per-point for v1** (simplest, predictable). New-World breakpoints are a possible later polish, not a launch requirement.
3. **Per-point rates** — calibrate at implementation against the live combat/crit/defense formulas (starting proposals in §4 stand as defaults).
4. **Respec cost** — **Free for v1** (mirrors the current free ability respec); add a cost later if attribute-swapping proves too frictionless.
5. **HP source** — **Keep the discipline HP curve as the baseline; CON is additive on top** (this ADR's choice — fuller "CON is the only HP source" model is out of scope).
6. **Caps** — crit% self-limits at the proposed ~0.1%/LUCK rate; add an explicit crit-chance cap (and defense soft-cap) only if the 495-AP pool proves to trivialize them. Defer.
7. **CRITDAMAGE source (REQUIRED fast-follow)** — crit is currently a dead stat (CRITDAMAGE base 0, no source → crits only ×1.2–1.5). For LUCK→crit-rate to be worth anything, **add CRITDAMAGE as a roll-able stat on high-tier gear.** This is a small separate item-content task that must ship alongside PR 7, or LUCK's crit utility is a trap.
8. **Job Advancement — FULLY REMOVED in PR 7** (user-confirmed 2026-05-28). Delete `JobAdvancementManager` + the advanced-class match arms/constants (`CRUSADER`/`RANGER`/`ARCHMAGE`/`ASSASSIN`) in `stats.gd`; `current_class` stays the fixed starting weapon discipline. Existing advanced-class characters need a one-time migration back to their tier-1 discipline (with HP-curve + stat recompute; the reconcile guards absorb the point math).
