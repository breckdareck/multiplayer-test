extends RefCounted

## Pure, dependency-free boss phase/enrage crossing math. Kept in its own script
## (no class_name, no preloads, RefCounted base) so it can be unit-tested in
## isolation without dragging in the whole EnemyBase compile graph — and so the
## server-authoritative threshold logic has one canonical home. EnemyBase calls
## these statics; the test suite preloads this file directly.

## Given the previous highest-passed phase index, the current HP fraction, and the
## threshold list, returns the NEW highest phase index that should be active.
## Thresholds are HP fractions the boss crosses DOWNWARD (e.g. [0.66, 0.33]); a
## fraction of 0.5 has passed index 0 (0.66) but not index 1 (0.33), so it returns
## 0. Monotonic: never goes below `prev_idx`, so a heal that lifts HP back above a
## threshold does NOT un-fire a phase. Returns -1 when nothing has been crossed.
static func compute_phase_index(prev_idx: int, hp_fraction: float, thresholds: Array) -> int:
	var idx: int = prev_idx
	for i in range(thresholds.size()):
		if i <= idx:
			continue  # already entered this (or an earlier-index) phase
		if hp_fraction <= float(thresholds[i]):
			idx = i
		else:
			break  # thresholds are descending — once one isn't met, none past it are
	return idx


## True once HP has dropped to/below the enrage fraction.
## `enrage_fraction <= 0.0` disables enrage entirely.
static func should_enrage(hp_fraction: float, enrage_fraction: float) -> bool:
	if enrage_fraction <= 0.0:
		return false
	return hp_fraction <= enrage_fraction
