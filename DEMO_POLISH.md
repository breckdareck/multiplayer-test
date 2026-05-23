# Demo polish checklist

**Goal:** a stranger boots the game, plays a 15-minute slice solo (or 20 with a
friend), and comes away feeling it's a real product — not a tech demo with
placeholder art. The systems are mostly done; what's left is the connective
tissue that makes the loop *feel* finished.

This is a near-term focused list. The long-term roadmap lives in
[TODO.md](TODO.md).

---

## The showcase path

The intended demo flow — every step should land cleanly:

1. **Title / Login** — register an account, log in.
2. **Character Select** — create a Swordsman.
3. **Spawn into Maple Town** — zone banner fades in, welcome chat lines appear,
   the starter quest `First Blood` auto-accepts. Quest tracker is visible
   top-right.
4. **Walk right, take the portal** — enter Slime Meadow, banner fades in,
   parallax visible behind the trees.
5. **Kill 3 slimes** — quest progresses live in the tracker, completes, "New
   quest available" hint fires, EXP and level-up burst trigger.
6. **Loot something, equip it** — inventory + equipment windows showcase.
7. **Travel through Goblin Hollow into Shadowfell** — show portal navigation
   and the three distinct hunting zones.
8. **(With a friend)** — second player joins via host IP, parties up, fights
   together with the party EXP bonus.
9. **Return to town, talk to the Job Master** — right-click dialog explains
   the level requirement; (use `/bot set_level` to skip the grind for the
   demo) advance to Crusader and see the chat broadcast + class change.
10. **Trade an item with your friend.**
11. **Emote (`/wave`) and wrap.**

Anything that breaks or feels rough on this path is in scope below.

---

## Must-fix before demo

The blocking issues. If you only have time for a few, do these.

### Visuals

- [ ] **Item icons** — `resources/Items/Weapons/`, `resources/Items/Armor/`,
  `resources/Items/Consumables/` reference character-spritesheet crops as
  icons for most of the 240+ items. Only 3 real equipment icons exist
  (`assets/sprites/Items/Equipment/Eqp_*.png`). At minimum, paint or source
  ~20 icons covering: wooden / iron / steel weapon tier, beginner armor set,
  3 potion tiers. Items the demo will actually surface need to look like
  items, not pixel scraps.
- [ ] **Shadowfell visual differentiation** — `game3` (Shadowfell) currently
  reuses the same Country-village parallax + tileset as `game` and `game2`.
  The "shadow" theme isn't sold. Easiest fix: duplicate
  `scenes/Levels/village_background.tscn` → `village_background_dark.tscn`,
  put `modulate = Color(0.45, 0.45, 0.6)` on every inner `Sprite2D`, and swap
  the ext_resource in `game3.tscn`. Bonus: also tint the tilemap layers with a
  CanvasModulate.
- [ ] **Onboarding overlay** — the welcome chat lines are easy to miss. Add a
  one-time dismissable overlay in `scripts/UI/` (instantiated by the player
  controller when the QuestManager onboarding fires) that lists the
  control mappings + "press Q for quest log" prominently. Replace the static
  `Tutorial` Label in `game.tscn` with this.

### Audio coverage

`AudioManager` and a dozen SFX files (`assets/sounds/`) already exist. What's
missing is them being **called** consistently. Quick audit:

- [ ] **Attack sound** — verify every base-attack swing plays `hurt.wav` or a
  weapon-specific SFX. Search `scripts/Components/combat.gd`.
- [ ] **Ability cast SFX** — many ability `.tres` have `sfx_path` fields; some
  may be empty. Pick the 5-6 abilities the demo class actually uses and
  ensure they have sounds.
- [ ] **UI feedback** — `tap.wav` on every button press (LoginScreen,
  inventory drag-drop, ability hotbar). Currently silent in many places.
- [ ] **Footsteps / jump landing** — `jump.wav` exists; verify it fires
  on jump start, and add a quiet landing thud.
- [ ] **Item pickup** — `pickup.mp3` should play on every coin/item pickup
  (`DroppedItem.gd`).

### Game feel

- [ ] **Hitstop on big crits** — 60–100 ms freeze when a crit lands. One
  `await get_tree().create_timer(0.08).timeout` inside `Engine.time_scale = 0`
  in `combat.gd`. Massive impact for tiny work.
- [ ] **Death feedback** — currently a death animation and respawn timer.
  Add a dark vignette + slow-motion ramp on death, and a "You Died" overlay
  on the local player.

---

## Should-fix polish

Real quality bumps, but the demo can ship without them.

- [ ] **Per-zone tilesets** — game / game2 / game3 all use the Country-village
  tileset. Pull in 1–2 new tilesets (or recolor existing) so each themed zone
  reads visually different.
- [ ] **Wire up orphaned enemy art** — `assets/sprites/Mushroom/`,
  `assets/sprites/Flying eye/`, `assets/sprites/Skeleton/` are fully
  animated and sitting unused. Each could be a new enemy via the `add-enemy`
  skill in ~30 min. Adds visual variety to existing maps.
- [ ] **Splash / title screen art** — the login screen is functional but
  plain. Even a tinted logo at the top makes the first impression land.
- [ ] **Job advancement transition VFX** — when the player advances, the
  class change is a sprite swap with the existing level-up particle burst.
  Add a brief screen flash + class name banner fly-in. Showcase moment.
- [ ] **Quest reward popups** — completing a quest currently spams 3-5 chat
  lines (`+50 EXP`, `+10 Coins`, etc.). Replace with a single centered
  reward popup that animates in/out.
- [ ] **Mob health bars in world** — the bot debug overlay already draws
  enemy HP bars. Make it a player-facing toggle (default on) and style it
  with the UI theme.
- [ ] **Persistent quest tracker tab order** — `QuestTracker` already supports
  pinning via the journal (`tracked` field exists in `quest_window.gd`).
  Verify the pin UI is obvious and that pinned quests stay across logout.
- [ ] **NPC quest-givers** — generalize the Job Master pattern
  (`scripts/NPC/job_advancement_npc.gd`) into a `QuestGiverNPC` that lists
  available/turn-in quests via the same dialog window. Replaces the
  self-service "press Q to accept" feel with NPC interaction.

---

## Stretch additions (if time)

- [ ] **One boss encounter** — pick the goblin/flying-eye/skeleton sprite
  pack, scale up the sprite, give it 2 phases (low HP triggers a new attack
  pattern). Place behind a portal off Goblin Hollow at level 25. Drops a
  unique item.
- [ ] **Daily quests** — 2-3 rotating objectives bound to a real-clock day.
  Gives the demo something to come back to.
- [ ] **Achievement titles** — a string under the player name when milestones
  hit (First Kill, Level 30, etc.). Pure data + a small label.
- [ ] **Demo GIF for README** — record 10–15s of gameplay and convert to GIF.
  Drop it under `README/` and link in the README hero section.

---

## Pre-demo verification

Run these before recording / showing:

- [ ] **Two-player smoke test** — host + 1 client. Walk together through the
  showcase path. Things to specifically watch:
  - Quest tracker on the client (not just host) shows progress.
  - Other player's name + HP bar shows above their character.
  - Trade window opens and completes both directions.
  - Party EXP bonus actually applies (kill a slime in a 2-person party,
    verify both get EXP).
  - Map transitions don't leave ghost players in the old map.
- [ ] **Fresh-character flow** — delete your save, create a brand-new
  character, confirm:
  - Spawns in Maple Town (not game).
  - Onboarding chat lines fire.
  - `q_first_blood` is auto-accepted and visible in the tracker.
  - Starter weapon + clothing equipped.
- [ ] **Level-30 advancement** — `/bot set_level 30` on yourself, talk to the
  Job Master, advance. Then log out and back in. Confirm:
  - Class is still the advanced class.
  - Existing abilities are still at their previous levels.
  - HP/MP scaling is higher than as a base class.
- [ ] **Camera bounds** — walk to every map edge in every zone. Verify the
  camera clamps cleanly without showing void or causing the player to walk
  off-screen.
- [ ] **Save round-trip under load** — kill 30 mobs back-to-back, then log
  out. Log back in. Quest progress, inventory, EXP all match.
- [ ] **Backend restart** — `docker-compose restart api` mid-session. Confirm
  the next save retries cleanly instead of dropping state silently.

---

## Out of scope for this checklist

Things that would also be great but explicitly aren't required for a demo:

- HTTPS / production hardening — see [DEPLOYMENT.md](DEPLOYMENT.md).
- Friend/Buddy system, Guild system, Free Market — see [TODO.md](TODO.md)
  tiers 1, 2, 5.
- Skill trees, mini-games, more party quests — stretch goals in
  [TODO.md](TODO.md) tier 8.
