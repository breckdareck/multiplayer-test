# Sword outlier review — dual-lens verdict and options

**Date:** 2026-06-11 · **Follow-up to:** `docs/dagger_tuning_options.md` ·
**Data:** `docs/damage_matrix_report.md` (now carries the dual-lens table permanently).

## The correction first

The earlier "+99% sword outlier" framing was incomplete. Under the **single-target
(boss) lens** the four disciplines are already balanced:

| Discipline | full-AoE rotation-core | single-target rotation-core |
|---|---|---|
| Sword | 105.6 | 29.7 |
| Staff | 53.1 | 28.7 |
| Bow | 53.0 | 26.8 |
| Dagger (post-scenario-D) | 38.6 | 24.5 (≈34.9 with the 1-in-4 ambush cadence — top of the pack, as its identity should be) |

Single-target spread is a tight ±10%. **Sword's base damage is not overtuned.**
The outlier decomposes into two specific things:

1. **Generous AoE caps on its spammables** — Steel Flurry: 3 targets × 2 hits at a
   1 s cooldown (150.5 full-AoE dps); Crescent Cleave: 6 targets on 4 s (116.4).
2. **The combo finisher multiplying the whole AoE cast** — the ×4 amp (Power Strike
   ×7) applies to *every* roll of the finisher, so a 3-combo Crescent Cleave on a
   pack is a **466 dps-equivalent** burst. This is the real spike; the AoE caps just
   set its size.

## Options (projected)

| # | Change | Effect |
|---|---|---|
| **O1 (recommended)** | **Finisher amp applies at full value to the PRIMARY target only** (other targets hit at base) | 3-combo Cleave burst 466 → **175** dps-equiv. Single-target finishers completely untouched (×4 vs a boss stays). One code change in the pending-multiplier application; the "finisher must beat spam" philosophy still holds — on the target. |
| O2 | AoE cap trims: Steel Flurry 3→2 targets, Crescent Cleave 6→4 | Full-AoE core 105.6 → 75.9 (still +43% vs the 53 cluster). Content-only change, but erodes the "sword = crowd king" identity without fixing the finisher spike. |
| O3 | Accept as identity | Defensible: single-target parity is real; sword being the premier crowd-clearer may be intended. Document it and watch playtests/server kill-feeds. |

O1+O2 together would land full-AoE near ~76 with the spike gone — likely overkill in
one step. Recommendation: **O1 now, re-measure, hold O2 in reserve.**

## Status

Awaiting design call.
