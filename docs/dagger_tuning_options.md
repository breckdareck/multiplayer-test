# Dagger tuning options — closing the L10 throughput gap

**Date:** 2026-06-11 · **Data source:** `docs/damage_matrix_report.md` (rotation-core =
mean of a weapon's top-3 ability DPS at character/ability level 10, zone-corrected).
All projections recomputed from `docs/damage_matrix_dump.json` with the same model.

## The problem, restated with the final numbers

| Discipline | Rotation-core (L10) | vs Bow/Staff cluster |
|---|---|---|
| Sword | 105.6 | **+99%** (its own outlier — see note below) |
| Bow | 53.0 | baseline cluster |
| Staff | 53.1 | baseline cluster |
| **Dagger** | **27.9** | **−47%** |

Dagger's compensators do not close this: its crit edge is only ×1.038 vs ~×1.02 for
the others (LUCK→crit has a knee at 100), and the ambush opener (×2 + forced crit
≈ **×2.70** per opener) is a *once-per-stealth-window* event, not a cycle.

**Parity target:** the Bow/Staff cluster (~53), *not* Sword. Sword's 105.6 — before
its ×4/×7 finisher amplification — is its own outlier and arguably needs a separate
downward look; pulling Dagger up to Sword would just move the imbalance.

## Scenarios (projected with the matrix model)

| # | Lever | Change | Projected rotation-core | vs cluster |
|---|---|---|---|---|
| A | Gear | Dirk weapon-attack 16 → 22 at the L10 tier (daggers run ~60% of sword attack across all generated tiers) | 38.3 | **−28%** |
| B | Cadence | Make restealth support one ambush per ~4 hits (shorter shadowmeld cooldown, or "Killing Edge / Shadowstep resets shadowmeld") | 27.9 × 1.425 = 39.7 | **−25%** |
| C | Content | Multiply dagger damage abilities' `damage_percent` curves ×1.35 | 37.6 | **−29%** |
| **D** | **Hybrid (recommended)** | **Dirk 16 → 22 AND ambush cadence ~1 per 4 hits** | 38.3 × 1.425 = **54.6** | **+3%** |

Why no single lever suffices: the gap is multiplicative — Dagger is behind on *both*
the stat base (max_range 26 vs 39–47) *and* the identity-cycle factor (no repeatable
finisher analog). Each lever alone lands at roughly −25–29%.

### Scenario D details (what would actually change)

1. **Generated dagger gear curve**: regenerate `resources/Items/Weapons/Generated/*_Dirk.tres`
   with weapon-attack ≈ 80% of the sword tier (16 → 22 at Bronze; same ratio up the
   table). One generator-input change + regen; keeps daggers below swords (they keep
   crit/LUCK as the differentiator) but not 40% below.
2. **Ambush cadence**: today the stealth window's re-entry cost makes the ×2.70
   opener roughly once-per-engagement. The lever is shadowmeld's re-entry rules
   (cooldown / combat-restealth), or cheaper: an upgrade/duo path that refunds
   shadowmeld on kill — making "stealth → opener → 3 hits → restealth" the dagger's
   finisher loop, mirroring sword's build-3-spend-1 rhythm. Tuning knob ends up
   cadence (1-in-N hits ambushed): N=4 → ×1.425 sustained, N=5 → ×1.34, N=6 → ×1.28.
3. Leave the per-ability `damage_percent` curves alone (option C's lever) so the
   change surface stays small and reversible.

### Sanity checks on D

- PvP/bosses: the opener multiplier itself is unchanged (×2.70) — burst ceiling does
  not grow, only its availability. The 8s duo-swap ICD and stealth-break rules still
  bound chaining.
- Fan of Knives (already ×7.3 its weapon median) scales with both levers like
  everything else; after D it sits near Hailstorm/Arcane Lance territory — watch it
  in the next matrix run.
- DoT anchors (`dot_scaling_base`) scale with max_range, so dagger bleeds/poisons
  rise proportionally — intended, since those are also "behind" today.

## Status: Scenario D implemented (2026-06-11)

- All 14 `*_Dirk.tres` tiers rescaled to 80% of the matching Longsword's
  weapon attack (Worn 5->7 ... Bronze 16->22 ... Eternal 99->126); the
  generator's dirk slope updated to match (4.0+0.95/lv -> 5.6+1.2/lv).
- `shadowmeld.gd ENTER_COOLDOWN_SEC` 6.0 -> 4.0: the restealth loop now
  supports roughly one ambush opener per 4 hits - dagger's finisher cycle.
- Post-change matrix: dagger rotation-core 38.3 base, ~54.6 with the
  1-in-4 ambush cadence folded in (+3% vs the Bow/Staff cluster); it no
  longer trips the rotation-core divergence check. Sword's own +99%
  outlier remains the open follow-up.

## Decision needed (resolved: D)

Pick a scenario (or none). D is recommended; A alone is the cheapest if a partial
close (−28%) is acceptable for now. Whichever lands, re-run
`tools/damage_matrix.gd` + `tools/damage_matrix_report.py` to confirm projections,
and give Sword's finisher ceiling its own follow-up review.
