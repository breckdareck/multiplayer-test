# Demo polish checklist

**Goal:** a stranger boots the game, plays a 15-minute slice solo (or 20 with a
friend), and comes away feeling it's a real product — not a tech demo with
placeholder art. The systems are mostly done; what's left is the connective
tissue that makes the loop *feel* finished.

This is a near-term focused list. The long-term roadmap lives in
[TODO.md](TODO.md). Last refreshed 2026-06-09 against
`feat/weapon-identity-overhaul`.

---

## The showcase path

The intended demo flow — every step should land cleanly:

1. **Title / Login** — title music, parallax background, juiced panel.
   Register an account, log in. (Dev tools are hidden behind F9 — keep them
   hidden on camera.)
2. **Character Create** — pick a starting weapon discipline (Sword for the
   demo). Show the idle-bob portrait and discipline descriptions.
3. **Spawn into Lantern's Rest** — zone banner fades in, the welcome overlay
   explains controls (dismiss it on camera — it sells onboarding), starter
   quest `First Blood` auto-accepts, quest tracker visible top-right, minimap
   top-left.
4. **Talk to the Village Elder** — right-click NPC quest dialog, accept a
   second quest.
5. **Portal out to the Near-Wilds** — banner + BGM change, parallax behind
   the terrain.
6. **Kill slimes** — overhead enemy HP bar (only you see it), quest progresses
   live in the tracker, completes with the reward popup, EXP and level-up
   burst trigger. Show a DoT (bleed/burn) ticking with its visual.
7. **Loot affix gear, equip it** — generated pixel icons, rarity-colored affix
   rolls. Open the Game Window: equip on the Character tab, allocate attribute
   points (the + buttons), then the Abilities tab to spend ability points on
   the tree.
8. **Weapon identity beat** — swap to the secondary weapon (hotbar swap
   slots): gauge widget changes (combo pips ↔ the other weapon's gauge),
   synergy widget names the pairing. Cast 2–3 abilities with VFX.
9. **World map (M)** — show the zone graph L1–100, hover a far zone's tooltip.
   Hearthstone back to town.
10. **(With a friend)** — second player joins via host IP, parties up, fights
    together with the party EXP bonus; trade an item.
11. **Emote (`/wave`) and wrap.**
12. **(Stretch closer)** — Eternal Warlord showcase: use the dev fast-path /
    `/bot set_level` to reach The Sundered Heart, show the boss HP bar, the
    telegraphed dash-slam, and a phase transition.

Anything that breaks or feels rough on this path is in scope below.

---

## Must-fix before demo

The blocking issues. If you only have time for a few, do these.

### Audio coverage

`AudioManager` and the SFX pipeline exist (per-map BGM, title music, ability
`sfx_path` broadcast to the map). What's left is **coverage and quality**:

- [ ] **Placeholder ability SFX** — many ability `.tres` set
  `sfx_path = "res://assets/sounds/tap.wav"` (a UI click) as a stand-in.
  Audit the 6–8 abilities the demo discipline actually uses and give them
  real cast sounds.
- [ ] **Attack sound** — verify every base-attack swing plays a swing/hit SFX
  per weapon (`scripts/Components/combat.gd`).
- [ ] **UI feedback** — `tap.wav` on every button press (login, Game Window
  tabs, inventory drag-drop, hotbar). Currently silent in places.
- [ ] **Footsteps / jump landing** — verify `jump.wav` fires on jump start;
  add a quiet landing thud.
- [ ] **Item pickup** — `pickup.mp3` on every coin/item pickup (incl. pet
  magnet loot).

### Game feel

- [ ] **Hitstop on big crits** — 60–100 ms freeze when a crit lands. One
  `await get_tree().create_timer(0.08).timeout` with `Engine.time_scale = 0`
  in `combat.gd`. Massive impact for tiny work.
- [ ] **Death feedback** — currently a death animation and respawn timer.
  Add a dark vignette + slow-motion ramp on death, and a "You Died" overlay
  on the local player.

---

## Should-fix polish

Real quality bumps, but the demo can ship without them.

- [ ] **Mid-band boss** — the only boss is the L100 Eternal Warlord, which a
  fresh demo character can't reach honestly. A reskinned L25–30 boss behind a
  portal (new `BossAttackData` .tres + the boss_attack_designer dock, no new
  code) would let the boss beat happen *inside* the honest demo arc.
- [ ] **Quest variety on the demo path** — all 26 quests are KILL objectives
  today (COLLECT/REACH_LEVEL types exist in code but are unused). One COLLECT
  quest on the starter path would show the system's breadth.
- [ ] **Quest tracker pinning** — verify the pin UI is obvious and pinned
  quests survive logout (`tracked` field in `quest_window.gd`).
- [ ] **Demo GIF for README** — record 10–15s of gameplay and convert to GIF;
  link in the README hero section.

### Done (kept for the record)

- [x] **Item + ability icons** — generated pixel-art icons cover all abilities
  and the full weapon/armor tier ladders (`assets/sprites/**/generated_px/`);
  the old character-spritesheet crops are gone from the demo surface.
- [x] **Splash / title screen** — login, character-select, and
  character-create screens all juiced (parallax, idle bob, title music);
  dev tools moved behind F9.
- [x] **Per-zone visual identity** — the 4-zone Country-village clone problem
  is gone: 15 themed Emberwilds zones via the procedural map builder +
  portal retopology.
- [x] **Onboarding overlay** — `WelcomeOverlay` full-screen card (controls
  grid, tips, input-locked until dismissed), fired once per character from
  `QuestManager.start_onboarding`.
- [x] **Mob health bars in world** — MapleStory-style overhead enemy HP bar,
  shown only to the hitter, 4s auto-hide.
- [x] **Boss encounter** — Eternal Warlord (3 phases, enrage, telegraphed
  specials, boss HP bar) — see "mid-band boss" above for the demo-arc gap.
- [x] **NPC quest-givers** — `QuestGiverNPC` + dialog (Village Elder in
  Lantern's Rest, slime-threat giver in the Near-Wilds).
- [x] **Quest reward popups** — top-center card + one concise chat line.

---

## Pre-demo verification

Run these before recording / showing:

- [ ] **Headless test suite green** — `run_tests.bat` exits 0 (ability /
  boss / bot / nav suites).
- [ ] **Two-player smoke test** — host + 1 client. Walk together through the
  showcase path. Things to specifically watch:
  - Quest tracker on the client (not just host) shows progress.
  - Other player's name + HP bar shows above their character.
  - Weapon-swap sprite updates on the *other* peer's screen.
  - Trade window opens and completes both directions.
  - Party EXP bonus actually applies (kill a slime in a 2-person party,
    verify both get EXP).
  - Map transitions don't leave ghost players in the old map (warm-pool
    eviction + reparent handoff are newer — watch this closely).
  - Client inventory/equipment drags act on the client's own items and
    persist across relog.
- [ ] **Fresh-character flow** — delete your save, create a brand-new
  character, confirm:
  - Spawns in Lantern's Rest.
  - Welcome overlay fires once, then never again.
  - `q_first_blood` is auto-accepted and visible in the tracker.
  - Starter weapon equipped; first ability point spendable.
- [ ] **Point-economy round-trip** — spend attribute + ability points, buy an
  upgrade, respec one ability (confirm the cost dialog shows first), log out
  and back in. Confirm granted == spent + unused for both pools (the
  reconcile guards should make this a no-op).
- [ ] **Gauge persistence sanity** — swap weapons mid-fight; the right gauge
  widget shows, synergy name is correct, stale gauges reset on un-equip.
- [ ] **Boss smoke** — enter The Sundered Heart, verify the boss HP bar
  binds, phases trigger at 66%/33%, the dash-slam telegraph is readable and
  jumpable.
- [ ] **Camera bounds** — walk to every map edge in the demo zones. Verify the
  camera clamps cleanly without showing void.
- [ ] **Save round-trip under load** — kill 30 mobs back-to-back, then log
  out. Log back in. Quest progress, inventory, EXP, mastery all match.
- [ ] **Backend restart** — `docker-compose restart api` mid-session. Confirm
  the next save retries cleanly instead of dropping state silently.

---

## Out of scope for this checklist

Things that would also be great but explicitly aren't required for a demo:

- HTTPS / production hardening — see [DEPLOYMENT.md](DEPLOYMENT.md).
- Friend/Buddy system, Guild system, Free Market — see [TODO.md](TODO.md)
  tiers 1, 2, 5.
- Party quests, daily quests, mini-games, achievement titles — [TODO.md](TODO.md)
  tiers 3, 4, 8.
- Steam-lobby topology migration — ENet + the Postgres backend stay as the
  dev/test stack until the game is playable.
