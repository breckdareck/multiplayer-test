# Ability Roster Audit — top-down (2026-06-10)

Per-discipline review of all 52 actives: what each does, duplicate clusters,
numeric sanity (dmg% × hits × targets vs CD/mana), and a KEEP / TUNE /
REWORK / REPLACE verdict for every flagged ability. Numbers are max-level,
from `docs/ability_data_dump.json`; mechanics verified against the AL scripts.
"Output/s" = dmg% × hits × targets ÷ CD (theoretical max; ST = single-target).

Recommendation: do NOT slim the rosters below 13 — the problems are
2 near-duplicates, 2 dead niches, and ~8 numeric outliers, not count.

---

## SWORD

| Ability | Shape | Max #s (mana/CD/dmg%/tgt/hit) | Output/s | Verdict |
|---|---|---|---|---|
| Crescent Cleave | AoE spender | 5 / 4s / 294 / 6 / 1 | 1764 (3-combo, 6t) | **TUNE** — mana 5 → 14 (cheapest spender, biggest output) |
| Sundering Blow | ST spender | 11 / 3s / 222 / 1 / 1 | 518 (3-combo) | KEEP |
| Earthsplitter | zone spender | 14 / 8s / 116 / 8 / 1 | high w/ ticks | KEEP |
| Steel Flurry | builder | 10 / 1s / 134 / 3 / 2 | 804 (3t) / 268 ST | **TUNE** — dmg% 134 → ~95. The 1s-CD builder shouldn't also be the kit's top damage; it makes Vault Strike/Charge! irrelevant as builders |
| Vault Strike | line dash builder | 13 / 3s / 210 / 2 / 1 | 140 | **REWORK** — the "2 Charges" problem. Restore its original design: a VERTICAL leap-arc with a small AoE landing slam (MapleStory vertical mobility — distinct from Charge!'s horizontal line in both movement axis and payoff) |
| Charge! | line dash builder | 8 / 4s / 136 / 3 / 1 | 102 | KEEP (the horizontal crowd-rush) |
| Vanguard's Onslaught | channel pierce | 11 / 8s / 252 / 6 / 1 | 189 | KEEP (now has a real wind-up) |
| Hemorrhage | DoT setter | 9 / 2s / 220 / 1 / 1 | 110 + bleed | **TUNE** — CD 2s → 3s (it's the top non-spender ST throughput *and* a DoT setter *and* cheap; 3s matches Barbed Shot) |
| Sentinel's Mark | mark | 5 / 6s / 78 / 1 / 1 | n/a | KEEP |
| Bulwark Stance | self buff (DEF) | 15 / 30s | n/a | KEEP |
| Iron Riposte | self buff (reflect) | 36 / 25s / 48% reflect | n/a | **REPLACE** — dead niche: reflect needs "stand there and get hit," which the no-dodge potion-survival model never rewards; worst mana efficiency in the kit; zero gauge/tag interaction. Proposal: **Challenging Shout** — AoE shout, small damage, struck enemies deal −15% damage for 6s (defense via debuffing the pack; scales where reflect didn't, party-relevant, fits the vanguard fantasy) |
| Vow of the Vanguard | party buff (spends combo) | 64 / 40s | n/a | KEEP |
| Banner of the Vanguard | zone party buff | 20 / 20s | n/a | KEEP |

Passives: fine as a spread (defense/offense/conditional). No action.

## BOW

| Ability | Shape | Max #s | Output/s | Verdict |
|---|---|---|---|---|
| Snipe | ST spender | 17 / 6s / 380 / 1 / 1 | 63 + momentum | **TUNE** — 380 → 420 so the signature payoff clearly beats Hailstorm ST after its fix |
| Sundering Arrow | pierce spender | 14 / 7s / 242 / 6 / 1 | 207 | KEEP |
| Gale Pierce | pierce builder | 12 / 5s / 174 / 4 / 1 | 139 | KEEP (clean builder/spender pair with Sundering) |
| Split Shot | multi-hit ST | 7 / 1.5s / 131 / 1 / 2 | 175 | KEEP (the filler) |
| Hailstorm | multi-hit AoE | 28 / 4s / 76 / 3 / 10 | 570 (3t) / 190 ST | **TUNE** — the bow's biggest outlier: beats Snipe at its own ST job. hits 10 → 6 and dmg% 76 → 66 (≈ 297/s at 3t, 99/s ST) |
| Skyfall | AoE burst | 38 / 5s / 114 / 6 / 1 | 137 | **TUNE** — mana 38 → 20 (2.3× Hailstorm's cost for less output) |
| Sky Volley | channel zone | 17 / 8s / ticks / 6 | 284 (6t full) | KEEP (now actually roots) |
| Caltrops | zone + slow | 8 / 10s / ticks / 6 | 204 (6t full) | KEEP (chill-tag enabler) |
| Barbed Shot | DoT setter | 10 / 3s / 182 / 1 / 1 | 61 + bleed | KEEP |
| Mark of the Hunt | mark | 6 / 12s | n/a | **TUNE** — mark duration 8s → 12s (the build-momentum-then-spend window is too tight against its own 12s CD) |
| Disengage | mobility | 11 / 6s / 200 / 1 / 1 | 33 | KEEP |
| Steady Aim | self buff | 16 / 30s | n/a | KEEP |
| Eagle Eye | party buff | 14 / 45s | n/a | KEEP (crit-stacking with Steady Aim noted; revisit at balance pass) |

Passives: Surefoot (knockback resist) is the dead slot — candidate to swap for
a Momentum-engaging passive in the T2/T3 phase. Only 2 of 8 passives touch the
gauge that defines the weapon.

## STAFF

| Ability | Shape | Max #s | Output/s | Verdict |
|---|---|---|---|---|
| Arcane Bolt | ST filler | 7 / 1.2s / 190 / 1 / 1 | 158 | KEEP |
| Arcane Lance | multi-hit beam | 28 / 4s / 86 / 3 / 10 | **645** (3t) / 215 ST | **TUNE — worst outlier in the game.** 10×+ over siblings. hits 10 → 6, dmg% 86 → 60 (≈ 270/s at 3t, 90/s ST — still the multi-hit king, no longer the whole kit) |
| Glacial Spike | ST nuke + freeze | 26 / 6s / 180 / 1 / 1 | 30 | **TUNE** — CD 6s → 4s (45/s; lowest damage of all staff actives even WITH the CC priced in) |
| Pyre Burst | AoE + burn/pool | 32 / 5s / 114 / 6 / 1 | 137 | KEEP |
| Immolate | DoT setter | 13 / 3s / 172 / 1 / 1 | 57 + burn | KEEP |
| Frost Patch | zone + chill | 13 / 8s / ticks / 6 | ~15 | **TUNE** — tick 8% → 12% of dot base. Its role got better (it's now the chill-tag/Thermal-Shock enabler) but the damage is symbolic |
| Stormcall | channel zone | 22 / 12s / ticks / 5 | 22 (5t!) | **TUNE** — CD 12s → 9s and tick 11% → 14%. A 3s self-root needs to pay much better than this |
| Spellweave | channel, per-stance | 24 / 10s / anchor 155 | 46-56 | **REWORK (design, with T2/T3 phase)** — its FIRE release is a third fire-pool (after Pyre Burst's pool and Immolate's splash). Change FIRE release to an instant cone wave that applies 2 burn stacks (burst shape, no third zone). ICE/LIGHTNING releases keep their shapes |
| Mana Surge | mark (MP economy) | 10 / 12s | n/a | KEEP |
| Arcane Familiar | summon | 27 / 20s | ~14 | KEEP (verify stance riders don't fire on familiar bolts — known gotcha, fine for v1) |
| Aether Ward | self buff (mana shield) | 15 / 30s | n/a | KEEP |
| Phase Step | blink | 20 / 8s | n/a | KEEP |
| Communion | party buff | 15 / 40s | n/a | KEEP |

Fire-zone triplication (Pyre pool / Spellweave FIRE / Immolate splash) is the
staff's "2 Charges" — resolved by the Spellweave FIRE rework above.

## DAGGER

| Ability | Shape | Max #s | Output/s | Verdict |
|---|---|---|---|---|
| Twin Fang | multi-hit ST filler | 4 / 1s / 127 / 1 / 2 | **254 ST** | **TUNE — the dagger's Arcane Lance.** 4-11× every sibling; the whole kit collapses into "spam Twin Fang." dmg% 127 → 90 (180/s — still the best filler, no longer the only button) |
| Eviscerate | ST execute | 17 / 6s / 370 / 1 / 1 | 62 (way more in execute window) | KEEP |
| Vendetta | poison spender | 11 / 6s / 174 / 1 / 1 | 55 w/ stacks | KEEP (now spends any poison) |
| Backstab | positional ST | 5 / 5s / 116 / 1 / 1 | 23 front / 41 behind | **TUNE** — dead outside the Shadowstep combo. CD 5s → 3s, dmg% 116 → 150 (front 50/s, behind 87/s, stealth+behind ~175/s — a real payoff button) |
| Fan of Knives | multi-hit AoE | 17 / 3s / 42 / 3 / 7 | 294 (3t) | KEEP (the AoE tool; fine once Twin Fang is tuned) |
| Envenom | DoT setter | 11 / 4s / 162 / 1 / 1 | 41 + poison | KEEP |
| Cripple | debuff strike | 19 / 10s / 124 / 1 / 1 | 12 | **REWORK (small)** — damage is a rounding error and the Disorder debuff is opaque. Make Cripple also apply the **chill tag** (hamstring = slow): it becomes the dagger's chill enabler (feeds Dead Aim partners + Thermal Shock pairings) and its setup role becomes legible. Verify/raise Disorder magnitude while in there |
| Death Mark | mark (+crit vs target) | 7 / 10s | n/a | KEEP (mark-tag economy anchor) |
| Shadowstep | blink + backstab window | 15 / 2s | n/a | KEEP |
| Smoke Bomb | defensive zone | 13 / 15s | n/a | KEEP |
| Shadow Partner | summon | 20 / 120s | ~58 passive | KEEP |
| Killing Edge | self crit buff | 22 / 45s / 14s dur | n/a | **TUNE** — 31% uptime is the worst buff economy in the game. CD 45s → 30s (47% uptime) |
| Bloodlust | party crit buff | 21 / 40s | n/a | KEEP |

Watch item (defer): the crit-investment cluster (Killing Edge + Death Mark +
Bloodlust + Killer Instinct + Cutthroat) — an optimizing dagger hits ~70% crit
from abilities alone. Revisit after the Twin Fang/Backstab retune changes what
crit multiplies.

Stealth gap (for the T2/T3 phase): only 3 of 13 actives are stealth-modified.
Twin Fang / Fan of Knives / Smoke Bomb are the natural candidates for
stealth-modified T2 clauses — that's exactly the upgrade-authoring work queued
behind this audit.

---

## Summary of proposed changes

**Reworks (3):** Vault Strike → vertical leap-slam (kills the "2 Charges"
duplicate); Iron Riposte → Challenging Shout (kills the dead reflect niche);
Spellweave FIRE release → cone burn wave (kills the third fire-pool).

**Numeric retunes (11):** Arcane Lance ↓↓, Twin Fang ↓, Hailstorm ↓, Steel
Flurry ↓, Hemorrhage CD ↑, Crescent Cleave mana ↑, Skyfall mana ↓, Snipe ↑,
Glacial Spike CD ↓, Stormcall ↑, Frost Patch ↑, Backstab ↑, Killing Edge CD ↓,
Mark of the Hunt duration ↑.

**Deliberately untouched:** all spender/builder pairs (they're clean), all
marks, all zones except numbers, both summons, all party buffs.

After these land: regenerate `ability_balance_report.html` + re-run the test
harness, THEN start the T2/T3 upgrade authoring (stealth clauses, scheduled
procs, pairing T3s) against the corrected baseline.
