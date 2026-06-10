# AI bots

Server-side AI players. A bot drives the *same* `MultiplayerPlayerV2` character a
human would — it just supplies input flags instead of a keyboard.

## Files

`bot_brain.gd` is the orchestrator — it owns the think loop and delegates
combat / navigation / economy / equipment decisions to sibling modules so
each piece stays small.

| File | Role |
|---|---|
| `bot_manager.gd` | Autoload. Spawns/despawns bots, owns `/bot` chat commands, loads `config/bot_config.json`, caches per-map nav graphs |
| `bot_brain.gd` | Per-bot think-loop FSM (idle / wander / fight / retreat / loot / travel); routes the decision through priority "considerations" and writes input flags onto the character |
| `bot_combat.gd` | Combat sub-module: target selection, attack timing, ability use; also spends ability + attribute points (see [Progression](#progression--spending-points-under-the-weapon-system)) |
| `bot_navigator.gd` | Per-bot navigation: queries `bot_nav_graph` for waypoint paths and steers the bot via input flags (incl. `_ride_ladder` for CLIMB edges), with a periodic repath. `compute_jump_profile` SIMULATES the real jump arc (jump.gd skips gravity one frame) — don't use the textbook v²/2g |
| `bot_nav_graph.gd` | Runtime-built nav graph from the map's tilemap (WALK / JUMP / DROP / GAP / **CLIMB** edges across `TileMapLayer.get_used_rect()`); CLIMB edges model ladders/ropes (the maps' vertical traversal — platforms are spaced beyond the ~29px jump); built incrementally a few columns per frame; cached per `map_id` on `BotManager`. **Build with `BotManager._bot_jump_params()` so every caller uses the same profile (the graph is cached by whoever builds first).** Inspect headlessly with `test/nav/probe_navgraph.gd` (edge counts, connected components, ladder spans) |
| `bot_economy.gd` | Inventory pickup, gold management, sell decisions |
| `bot_equipment_logic.gd` | Scores gear and decides equip/sell swaps |
| `bot_debug_draw.gd` | Debug-overlay rendering for `/bot watch` and the backtick `DebugPanel` bot view (targets, HP bars, nav-graph sub-layers) |

## Key facts

- **Bots have negative peer IDs.** `BotManager.is_bot(id)` is exactly `id < 0`.
- **A bot has no client.** On spawn it frees its whole `CanvasLayer` UI subtree.
  Never send a bot a node-addressed RPC; never assume a bot has buff/hotbar UI.
- **The brain outlives the body.** `BotBrain` is parented to `BotManager`, not the
  character. As of ADR 0008 a bot map change **reparents the SAME live body** between
  maps (no free/recreate); `MapManager` then calls `BotManager.handle_bot_reparented()`
  → `attach_to_player()` to reset the brain's transient targets/nav for the new map
  while preserving travel timers, patrol progress, and cooldowns. (A bot's *first*
  spawn — and the recreate fallback — still build a fresh body.)
- **Bots are server-only.** All bot logic is gated behind `multiplayer.is_server()`.

## The think loop

`bot_brain._process()` ticks several timers and, every `think_interval` (~0.3s),
runs `_think()`, which sets `current_action`. `_apply_current_action()` then
translates that action into input flags on the character (`player.direction`,
`player.do_attack`, `player.do_jump`, `player.do_pickup`, …). The server's normal
character `_physics_process` consumes those flags — the bot never moves the body
directly. Add new behaviour by extending the `_think()` decision tree and the
`_apply_current_action()` match.

## Progression — spending points under the weapon system

A bot spends its own points to build toward its weapon identity; both spends run
in `bot_combat.build_ability_lists()`, ticked on the brain's ability timer
(~5s). They call the **server-side** component methods directly (bots have no
client to RPC).

- **Ability points** (`_auto_spend_ability_points`) — a purposeful value-weighted
  greedy, not random: each point goes to the highest *value/point* ability
  (role weight × `1/(level+1)` marginal gain), so early points spread into a
  usable kit and later points deepen the signature attack skills; once an ability
  maxes, leftover points reinvest into its upgrades (`purchase_upgrade`, lower
  tiers first). `AbilityComponent`'s per-discipline pool gating means a
  discipline's points only ever buy that discipline's content.
- **Attribute points** (`_auto_spend_attribute_points`) — allocates on the
  discipline's `stat_bonuses` ratio plus a CONSTITUTION survival bias, topping up
  only the shortfall vs. what's already spent (never unallocates, never fights the
  migration default-allocation).

**Where the points come from:** attribute points are granted by **character
level**; ability points are granted only by **weapon-mastery** level-ups
(`mastery_level_changed` → `AbilityComponent._add_ability_points`). Mastery XP is
earned **on kill** (`CombatComponent.grant_mastery_xp_server`), which fires for
bots since they deal real damage — so a grinding bot accrues both naturally.

## Ambient population (ADR 0011)

Bots fake a busy server for a small co-op session (the Erenshor "SimPlayer"
pattern). See [docs/adr/0011-bot-ambient-population.md](../../docs/adr/0011-bot-ambient-population.md).

- **Speech** — `ChatManager.bot_say(bot_id, text)` is the ONLY way a bot
  speaks (a bot can never be an RPC's remote sender). It is map-scoped like
  player chat and applies a server-wide budget (`BOT_SPEECH_GLOBAL_GAP`); the
  brain's `try_speak(event, ctx, force)` adds a per-bot cooldown + chattiness
  roll on top. Events: `greet` (LOD far→near transition), `level_up`, `death`,
  `rare_loot` (rarity ≥ RARE), `boss_kill`, `party_join`, `command_*`,
  `decline_trade`. Lines are data in `config/bot_personalities.json`
  (templates: `{player}` `{map}` `{item}` `{enemy}` `{level}`).
- **Personality** — an archetype key per bot: authored `"personality"` in the
  bot's config entry wins; otherwise a one-time roll persisted in
  `saves/bot_roster.json` (server-side identity roster — deliberately NOT a
  backend column) so random bots stay recognizable across sessions.
- **Cold-start seeding** — a bot whose spawn found NO save row
  (`PlayerManager.add_bot` → `mark_bot_fresh`) gets a one-time seed in
  `_on_bot_spawned`: level into a difficulty band (spawn map's band, else a
  random banded patrol map; per-bot `"seed_level"` overrides; global
  `"seed_max_level"` caps) via `pump_bot_to_level` — the same EXP+mastery path
  as `/bot set_level`, so the point-reconcile invariant holds — plus
  `level × 40` gold. Seeding runs BEFORE the brain attaches so the level-up
  pump can't trigger speech.
- **Companion commands** — `/bot follow|stay|free <name|id|all>`,
  party-leader-only. A mode flag on the brain (no trinity roles): `follow`
  sticks to the leader (same-map and into town, unlike ambient regrouping);
  `stay` anchors at the commanded position (fights only within `STAY_RADIUS`);
  commands suppress restock errands and lapse when the bot leaves the party.
- **Trade consent** — non-party players can only TAKE sell-fodder from a bot;
  consumables and would-equip gear are declined (scored by
  `BotEquipmentLogic`). Party members keep the free give/take window.

### Texture layer (ADR 0012)

- **Churn** — `BotManager._step_churn` logs identities in/out over a session
  (`bot_config.json "churn"` block); pool = config bots ∪ roster; global
  "<name> has logged in/off" feed lines. Never churns out a player's
  groupmate, a commanded companion, or a stress bot. Roster entries carry
  `class` + `last_seen`.
- **Replies** — `ChatManager._broadcast_message` scans player messages for
  same-map bot names → delayed forced `try_speak("reply")`, staggered past
  the speech gap.
- **Image emotes** — `tools/gen_emote_icons_px.py` renders sit/wave/laugh/cry
  to `assets/sprites/Emotes/generated_px/`; `EMOTES` maps command →
  `{text, icon}`; `ChatManager.bot_emote()` is the visual-only twin of
  `bot_say` (own 3s gap). Bots wave on greet, cry on death, sit on idle.
- **Reputation** — `BotManager.add_reputation/get_reputation`, per-player
  scores in the roster (party +3/member, trade +1/item). Greet pools tier:
  `greet` → `greet_familiar` (3+) → `greet_friend` (10+).
- **Player invites** — a solo bot with no bot partner may invite a solo
  level-adjacent player (normal invite UI); 5-min cooldown, 30s unanswered
  → the solo party is abandoned. Party tracking watches real-player
  MEMBERSHIP, not party id (creating the invite party is silent).
- **Banter** — `BotManager._step_banter` scripts one overheard
  open+reply exchange (60–140s cadence) between two bots within 350px on a
  map with a real-player audience.
- **Offline catch-up** — a returning identity gains levels for downtime
  since roster `last_seen` (`bot_config.json "offline_progression"`), via
  `pump_bot_to_level` (now level-cap-safe).
- **World-map presence** — `MapManager.request_population_counts` /
  `receive_population_counts` RPC pair; the world map shows an "N" badge on
  revealed maps (players + bots counted indistinguishably). The minimap
  already draws bots.

## Configuration — `config/bot_config.json`

```jsonc
{
  "auto_spawn": true,            // spawn bots when the server starts
  "default_map": "near_wilds",
  "bots": [                      // one entry per bot; name "random" auto-generates
    { "name": "Bob", "class": "SWORDSMAN", "map": "lanterns_rest",
      "patrol_route": ["near_wilds", "ember_meadows", "deep_woods"] }
  ],
  "behavior": { },               // think_interval, ranges, durations - copied into each brain
  "map_difficulty": {            // per-map level band; bots travel to stay in-band
    "near_wilds": { "min_level": 1, "max_level": 20 }
  }
}
```

Reload at runtime with `/bot reload_config` — it only affects bots spawned
afterward.

A bot spawned via `/bot spawn` has no `bots[]` entry, so no configured
`patrol_route`. `BotManager._default_patrol_route()` substitutes every map in
`map_difficulty`, sorted by `min_level`, so a manually-spawned bot still has a
way to leave town after its first restock trip (without this fallback,
`_should_change_map` returns false on town and the bot wedges there).

## `/bot` commands

`spawn`, `despawn`, `despawn_all`, `list`, `roster [forget <name>]`,
`teleport`, `set_level`, `personality <bot> [archetype]`,
`say <bot> <event|text>`, `emote <bot> <sit|wave|laugh|cry>`,
`rep <bot> [player [delta]]`, `party`, `follow|stay|free <bot|all>`,
`churn <status|on|off|now>`, `banter`, `travel info`, `inspect`, `trade`,
`reload_config` — dispatched by `BotManager.handle_command()`. The debug
console (`` ` ``) passes through with Tab-completion for every subcommand;
`botdock` opens the live roster table, `/bot inspect` the single-bot
deep-dive (identity, brain state, mastery, lifetime metrics, reputation).

`set_level` pumps character EXP **and** raises the bot's primary-discipline
mastery to match (one mastery level per character level, capped at
`MASTERY_CAP`) — without that, a force-levelled test bot would have attribute
points but no ability points (which are mastery-gated), leaving it skill-less.
