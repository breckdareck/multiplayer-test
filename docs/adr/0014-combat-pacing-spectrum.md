# Combat pacing spectrum: four cooldown bands and curve-calibrated weight

Playtesting the pair builds showed the kit had no rhythm: ~half the damage
actives sat at ≤5s cooldowns, so cycling a 5-slot hotbar brought the first
ability back before the last fired — no downtime, no weight, and no reason to
Tab-swap despite the duo/synergy layer. We decided to give every weapon kit an
explicit **four-band cooldown spectrum** with damage **calibrated against the
enemy HP curve** (`0.7·L^2.3`), validated at every 5 character levels by
`tools/damage_matrix.gd`, instead of scaling damage proportionally to cooldown.

## The decisions

1. **Four bands per weapon kit.** FILLER (1–2s, builders/farm spam, slight
   damage bump), SHORT (4–6s), HEAVY (12–14s, ~0.45–0.75× of an at-level
   normal enemy's HP per target), ULTIMATE (~30s, ~0.9–1.05× — the
   MapleStory-style big hitter that one-shots an at-level normal, never a
   boss). One ultimate per weapon: Earthsplitter, Snipe, Stormcall,
   Eviscerate.
2. **Damage is authored against the enemy HP curve, not derived from old
   values.** Pure proportional scaling (damage × new_cd/old_cd) one-shots the
   L5–L20 band (up to 1.67× of at-level HP) because per-cast damage there is
   already a third to half of enemy HP. Each heavy/ult's `damage_percent`
   formula is solved from a target HP-fraction anchored at the acquisition
   band (ability max ≈ char L10) on canonical builds.
3. **Cooldowns are flat across ability levels and never increase on
   level-up.** A level-ramped cooldown (8s→14s as the ability grows) was
   considered and rejected: a stat that worsens on level-up reads as
   punishment regardless of compensation. Instead the ability grows INTO its
   weight: damage starts at ~55% of the anchored target at L1 and reaches it
   at max, so every level-up strictly increases damage.
4. **Both playstyles are first-class.** Solo single-weapon throughput stays
   ≈today's (filler bump backfills heavy downtime); the rhythm-swapper's
   ceiling is +10–15%, funded entirely by the existing synergy layer (duo
   arrival beats, banked gauges, cross-weapon escalations) — never by taxing
   non-swappers. Dwell target is an unhurried 10–15s per side; the 8s
   duo-swap ICD is deliberately untouched (always ready on arrival — a reward
   collected, not a timer watched).
5. **Primers outlive the swap loop.** DoT primer durations rise to 12s
   (bleeds, burns, poisons) and marks to 15s so prime-on-A / consume-on-B is
   possible calmly — previously burn (4s), poison (4s), and chill (2.5s)
   expired inside one 8s swap round-trip, making cross-weapon escalations
   mathematically unplayable. Chill/slow durations stay short: they are CC,
   not DoT bookkeeping.

## Considered options

- **Proportional damage-with-cooldown scaling** — rejected: one-shots the
  early game (measured, not estimated; see the L5–20 rows of the sweep).
- **A ×2.5 damage-multiplier cap** — rejected as a derivation shortcut; curve
  calibration produces the safe ceiling at every level instead of one knob.
- **Cooldown ramping up with ability level** — rejected on feel (see 3).
- **Taxing solo play to motivate swapping** — rejected: player choice is the
  point; the swap is an optimization, not an obligation.

## Consequences

- The damage matrix is the calibrator, not just the auditor: any retune
  re-runs `tools/damage_matrix.gd` + `tools/damage_matrix_report.py` and the
  band/weight checks confirm the contract at every 5 levels.
- The at-level HP fraction drifts down toward endgame (player damage grows
  ~L^1.6 vs HP L^2.3); crits, finisher amp, upgrades, and duo layers carry
  late-game weight. That divergence is pre-existing and tracked as a separate
  curve-tuning item — this change does not silently re-tune it.
- `cooldown_flat_reduction` upgrades are relatively weaker on 30s ultimates
  (-1s of 30 vs -1s of 6); acceptable, revisit per-upgrade if playtests care.
- Bots need no changes: they cast off cooldown and inherit the spectrum.
