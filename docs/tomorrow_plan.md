# Plan: next features (2026-06-02)

Derived from a comparable-games study (ESO/GW2/Farever/D4/Ragnarok/MapleStory) cross-referenced against the actual overhaul codebase. The weapon-identity overhaul is *systems-complete*; these close documented content/feel gaps (GDD §19–20).

## Shipping now (3 parallel PRs)
1. **Economy respec sink** (this PR) — respec costs monies, server-validated. Closes the GDD §10.5 "coins are sink-less" gap. First sink.
2. **Boss encounter system** — `is_boss` data contract + HP-phase transitions + telegraphed special + boss HP bar; Eternal Warlord becomes a real fight. Closes GDD §20 boss gap; research item #7 (Ragnarok MVP-as-party-anchor).
3. **Active dodge i-frames** — deepen the existing roll (`slide.gd`) into a real defensive verb with server-authoritative invulnerability + cooldown. Research item #8 (GW2 dodge); the "no-tank" survival answer.

## Backlog (ranked, from the research synthesis)
1. **Cards / aspects** (Ragnarok × D4) — droppable, slottable, *skill-transforming* modifiers; common = small stats, rare boss-drops rewrite an ability. Biggest build-identity deepening. **Needs a backend column → requires explicit approval before building.**
2. **Element fields × finisher tags** (GW2 combo) — abilities lay Fire/Ice/Lightning fields; tag weapons with finisher types (sword=Leap, bow=Projectile, staff=Blast, dagger=Whirl); cross-player field+finisher = bonus. Reuses the element + ground-zone infra already built.
3. **Off-weapon "borrow one ability"** (Farever Arsenal) — the inactive weapon slot donates one chosen active/passive to the bar. Near-zero new content on the existing two-slot system; respects the no-random-point invariant (it's a loadout choice).
4. **Party synergy prompt off ground-zones** (ESO) — allies get a one-button bonus off a teammate's ground-zone. Cheap co-op depth.
5. **Basic-attack weave window** (ESO) — short cancel window on CTRL basics for a gauge/resource bonus; raises the skill ceiling.
6. **Tune training maps to weapon AoE shape + high-band maps L33–100** (MapleStory mobbing) — mostly level design; closes the "content lags systems" gap.

## Validation debt (pre-existing, from GDD §19/§20)
- The whole overhaul is compile/unit-validated only — no live host+client+bot end-to-end playtest of spawn→stats→combat→gauge→save. That remains the single highest-priority manual step.
