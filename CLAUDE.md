# CLAUDE.md

Guidance for Claude Code in this repository. This is the **lean root** — it holds
only repo-wide truths. Each major subsystem carries its own `CLAUDE.md` that loads
additively when you work in that directory; see [Subsystem guides](#subsystem-guides).

## What this is

**Emberwilds** — a **server-authoritative multiplayer RPG** built in Godot 4,
with a Flask + PostgreSQL backend for account and character persistence. Cozy
co-op weapon-identity action on a rebuilt frontier of a world the **Emberfall**
shattered; world bible in [docs/LORE.md](docs/LORE.md).

**The rule that governs everything:** the server owns all critical state. Clients
send *intent* via RPCs; the server validates it, mutates state, and broadcasts the
authoritative result back. Never mutate health, stats, inventory, drops, abilities,
or progression on a client and assume it sticks — it will be overwritten.

## Running the game

- **Engine**: Godot 4.5+ (Forward Plus rendering)
- **Main scene**: `scenes/UI/LoginScreen.tscn`
- **Run in editor**: F5
- **Local multiplayer testing**: launch extra instances from the editor's Debug
  menu, or run the exported binary
- **Dedicated server** (headless):
  `godot --headless --feature dedicated_server --path . -- --port 8080`
- **Windows helpers**: `start_server.bat` / `stop_server.bat`

## Backend (required for account/character persistence)

```
docker-compose up -d
```

| Service | URL / port | Credentials |
|---|---|---|
| Flask API | http://localhost:5000 | — |
| PostgreSQL | localhost:5432 | `postgres` / `password` / db `gamedb` |
| Adminer (DB UI) | http://localhost:8080 | — |

Logs: `docker-compose logs api`. Schema and endpoint conventions live in
[backend/CLAUDE.md](backend/CLAUDE.md).

## Autoload singletons

Registered in `project.godot`; globally accessible by name from any script.

| Singleton | Script | Purpose |
|---|---|---|
| `MultiplayerManager` | `scripts/Managers/multiplayer_manager.gd` | Host/join, channel switching, level loading; emits `server_has_started` |
| `ServerManager` | `scripts/Networking/server_manager.gd` | ENet server lifecycle |
| `ClientManager` | `scripts/Networking/client_manager.gd` | ENet client connection |
| `PlayerManager` | `scripts/Networking/player_manager.gd` | Player/bot spawn & cleanup, player-node lookup |
| `ChannelManager` | `scripts/Networking/channel_manager.gd` | Port switching without a restart |
| `NetworkUtils` | `scripts/Networking/network_utils.gd` | IP/port validation, scene helpers |
| `NetworkManager` | `scripts/Networking/network_manager.gd` | Backend HTTP API (login, characters, save/load) |
| `ResourceManager` | `scripts/Managers/resource_manager.gd` | Loads & caches ability/item/buff/class `.tres` |
| `SaveManager` | `scripts/Managers/save_manager.gd` | Debounced player-data persistence |
| `MapManager` | `scripts/Managers/map_manager.gd` | Map registry (15 Emberwilds zones, L1–100; `HEARTH_MAPS` = the safe towns), transitions, visibility, spawning; map residency = **bounded warm pool** (occupied maps + their portal neighbours stay resident, cold empty maps are evicted) + central proximity enemy activation — see [docs/adr/0007-map-residency-and-enemy-activation.md](docs/adr/0007-map-residency-and-enemy-activation.md) (original v1 decision kept for history + dated warm-pool revision) |
| `PartyManager` | `scripts/Managers/party_manager.gd` | Party creation/joining |
| `BotManager` | `scripts/Bot/bot_manager.gd` | Server-side AI bot lifecycle, `/bot` commands |
| `TradeManager` | `scripts/Trading/trade_manager.gd` | Player-to-player trading |
| `QuestManager` | `scripts/Managers/quest_manager.gd` | Quest tracking and objectives |
| `PetManager` | `scripts/Managers/pet_manager.gd` | Per-character pet roster, hunger tick, auto-buff timer, auto-loot / auto-pot validation — see [docs/adr/0001-pet-system-architecture.md](docs/adr/0001-pet-system-architecture.md) |
| `ChatManager` | `scripts/Managers/ChatManager.gd` | In-game messaging and slash commands |
| `KeybindManager` | `scripts/Managers/keybind_manager.gd` | Custom keybindings |
| `UserConfig` | `scripts/Managers/user_config.gd` | User-preference persistence |
| `InputManager` | `scripts/Managers/InputManager.gd` | Global input lock/unlock |
| `AudioManager` | `scripts/Managers/audio_manager.gd` | Music and SFX |
| `LogManager` | `scripts/Managers/LogManager.gd` | In-game debug logging |
| `DebugPanel` | `scripts/UI/debug_panel.gd` | Backtick-toggled developer console (typed commands w/ Tab autocomplete + history, quick-action buttons; routes `bot`/`quest` through their managers) |

## RPC conventions

```gdscript
# Server -> all peers (authoritative state). call_local: the host is also a
# client, so it must run the update too.
@rpc("authority", "call_local", "reliable")

# Client -> server (intent request). Always guard the body:
@rpc("any_peer", "call_local", "reliable")
func do_something_server(arg) -> void:
    if not multiplayer.is_server():
        return
    ...

# Server -> clients only (the server must NOT run it itself):
@rpc("authority", "call_remote", "reliable")
```

- The **server is always peer ID 1**. Clients reach it with `rpc_id(1, ...)`.
- Guard server-only logic with `if not multiplayer.is_server(): return` (or
  `is_multiplayer_authority()` for per-entity authority).
- **Bots have negative peer IDs** and no client. Never send a node-addressed RPC
  to a bot — route bot-related visuals through an autoload (e.g. `MapManager`),
  which resolves on every peer. See [scripts/Bot/CLAUDE.md](scripts/Bot/CLAUDE.md).

Full networking detail: [scripts/Networking/CLAUDE.md](scripts/Networking/CLAUDE.md).

## Global groups

- `networked_entities` — every network-spawned node; cleared on disconnect /
  channel switch. Add new networked entities to this group.
- `Players` — player (and bot) character nodes.
- `Enemies` — enemy nodes. This group is **global across all maps**; filter by map
  when iterating (see how `bot_brain.gd` does it).

## Persistence

Two layers:

- **Account / character records** → PostgreSQL via the Flask API. `username` is
  the unique **character name**. See [backend/CLAUDE.md](backend/CLAUDE.md).
- **In-game character state** (health, level, exp, abilities, buffs, equipment,
  inventory, monies) → persisted through `SaveManager` to the backend.

## Component-based characters

Player and enemy characters are composed of `Node` components under a root
character node (`Player/Components/Health`, `.../Stats`, …). The root player
script is `scripts/Player/multiplayer_controller_v2.gd` (`MultiplayerPlayerV2`).
See [scripts/Components/CLAUDE.md](scripts/Components/CLAUDE.md).

## Weapon-driven identity (no classes)

There are no character classes or job advancement. Identity comes from the four
**weapon disciplines** — Sword, Bow, Staff, Dagger (`Constants.ClassType`).
`WeaponMasteryComponent` is the single owner of identity: per-discipline mastery
levels plus the `primary_discipline` pointer (legacy class saves normalize on
load). Players carry a **two-weapon kit** (primary + secondary hotbar slots);
the pairing names a synergy via `WeaponPairSynergyComponent` (e.g. Sword+Staff =
Spellblade). Each discipline has a gauge mechanic (sword combo points, bow
momentum, staff Fire/Ice/Lightning stances, dagger shadowmeld stealth) and a
2-path ability tree with 3-tier per-ability upgrades. Character level grants
**5 freely-allocated attribute points per level** (STR/DEX/INT/LUCK/CON, managed
by `StatsComponent`). See
[docs/adr/0004-classcomponent-removal-weapon-discipline.md](docs/adr/0004-classcomponent-removal-weapon-discipline.md)
and [docs/adr/0002-attribute-allocation-system.md](docs/adr/0002-attribute-allocation-system.md).

## Testing

Zero-dependency headless harness in `test/` (no GUT/gdUnit4). Run with
`run_tests.bat`, or directly:

```
godot --headless --path . --script res://test/run_tests.gd --log-file test/last_run.log
```

Exit 0 = all pass, 1 = any failure (the GUI `Godot.exe` won't pipe stdout on
Windows — use the log file). Suites live under `test/ability/`, `test/boss/`,
`test/bot/`, and `test/nav/`, covering ability scaling formulas, every
ability×level + upgrade (content validation), live `AbilityComponent` behavior,
respec economy, boss phases/attack data, and bot point-spending.

## Editor tooling (`addons/`)

- `resource_editor` — custom dock (left, "Resources" tab) for authoring
  abilities / items / buffs / upgrade trees: formula tree + curve chart, hitbox
  visualizer, VFX picker, upgrade-tree cards, plus popup windows for the
  discipline placement board, validation dashboard, and batch edit.
- `balance_simulator` — read-only dock that runs each ability's scaling
  formulas per level and mirrors `CombatComponent`'s hit math in a combat
  simulator.
- `boss_attack_designer` — visual preview/scrub of `BossAttackData`
  (shape, dash, windup/hit timing) at true runtime geometry.

Gotcha: running `godot --editor --quit` headless disables plugins in
`project.godot` and re-serializes touched `.tres` — verify with `--script`
smokes instead, and `git checkout -- project.godot resources/` after any
`--editor` run.

## Data-driven content

Game content is Godot `.tres` resources under `resources/`, defined by classes in
`scripts/Resources/`. `ResourceManager` auto-loads abilities, items, buffs, and
classes recursively — no manual registration. See
[scripts/Resources/CLAUDE.md](scripts/Resources/CLAUDE.md).

## Subsystem guides

| Area | Guide |
|---|---|
| Networking, RPCs, ENet, channels | [scripts/Networking/CLAUDE.md](scripts/Networking/CLAUDE.md) |
| Character components | [scripts/Components/CLAUDE.md](scripts/Components/CLAUDE.md) |
| Data resource classes | [scripts/Resources/CLAUDE.md](scripts/Resources/CLAUDE.md) |
| AI bots | [scripts/Bot/CLAUDE.md](scripts/Bot/CLAUDE.md) |
| Backend (Flask / Postgres) | [backend/CLAUDE.md](backend/CLAUDE.md) |

## Skills — workflow recipes

Repeatable workflows packaged as Claude Code skills under `.claude/skills/`.
The `add-*` skills are path-scoped and load automatically when you work in
the matching files. `create-gdd` is intent-triggered.

The grilling / architecture skills form a **composable graph** (ported from
[mattpocock/skills](https://github.com/mattpocock/skills)): three model-invocable
**engines** — `grilling`, `domain-modeling`, `codebase-design` — and three
user-invoked **orchestrators** (`disable-model-invocation`) that compose them:
`grill-me`, `grill-with-docs`, `improve-codebase-architecture`. The engines
auto-trigger on intent; run an orchestrator with `/` when you want its specific
combination (e.g. grilling *with* doc side-effects).

| Skill | Use when |
|---|---|
| `add-ability` | Creating/editing an ability (`resources/Abilities/`, `scripts/Abilities/`) |
| `add-buff` | Creating/editing a buff or debuff (`resources/Buffs/`, `scripts/Buffs/`) |
| `add-item` | Creating a weapon, armor, or consumable (`resources/Items/`) |
| `add-enemy` | Creating an enemy (`resources/Enemies/`, `scenes/NPC/`) |
| `add-map` | Creating a map/level (`scenes/Levels/`) |
| `add-backend-endpoint` | Adding a Flask route or model (`backend/`) |
| `grilling` *(engine)* | The reusable interview loop. Stress-tests a plan one question at a time (each with a recommended answer) against the repo's server-authoritative invariants (`grilling/INVARIANTS.md`). Auto-triggers on grill/pressure-test/"poke holes" intent. |
| `domain-modeling` *(engine)* | Builds and sharpens the domain model: challenges fuzzy terms, maintains the `CONTEXT.md` glossary and `docs/adr/` decision records inline. Owns `CONTEXT-FORMAT.md` / `ADR-FORMAT.md`. |
| `codebase-design` *(engine)* | The deep-module vocabulary (module / interface / depth / seam / adapter / leverage / locality) + principles, the `DEEPENING.md` dependency-category guide, and the `DESIGN-IT-TWICE.md` parallel-sub-agent interface exploration. |
| `grill-me` *(orchestrator)* | `/grill-me` — runs a grilling session with no doc side-effects. |
| `grill-with-docs` *(orchestrator)* | `/grill-with-docs` — grilling **plus** `domain-modeling`, so `CONTEXT.md` and ADRs stay current as terms and decisions crystallise. |
| `improve-codebase-architecture` *(orchestrator)* | `/improve-codebase-architecture` — scans for **deepening opportunities** (shallow → deep refactors), renders an HTML report of candidates (`HTML-REPORT.md`), then grills through the chosen one. Composes all three engines. |
| `create-gdd` | Authoring or refreshing the Game Design Document (`docs/GDD.md`). Pulls from CLAUDE.md, CONTEXT.md, ADRs, and memory pointers (verifying claims against source before citing), fills a 20-section template, and renders a styled standalone HTML preview via the bundled Python script. No path scope — invoke by intent. |

### More ported mattpocock/skills

The rest of the [mattpocock/skills](https://github.com/mattpocock/skills) set,
ported (faithfully; lightly adapted where this repo's tooling differs). The
**idea → ship flow** chains several of these — run `/ask-matt` if you're unsure
which fits.

| Skill | Use when |
|---|---|
| `ask-matt` *(router)* | `/ask-matt` — names the user-invoked skills and which flow each fits. Start here when you don't remember what exists. |
| `tdd` *(model-invoked)* | Test-first red-green-refactor against the `test/` harness; "build this test-first", "red-green-refactor". |
| `diagnosing-bugs` *(model-invoked)* | Hard bug / perf regression — builds a tight feedback loop first. "diagnose", "debug this", something broken/slow. |
| `prototype` *(orchestrator)* | `/prototype` — throwaway code to answer a design question (logic TUI, or UI variants). |
| `handoff` *(orchestrator)* | `/handoff` — compact the conversation into a markdown handoff doc for a fresh session. |
| `to-prd` *(orchestrator)* | `/to-prd` — synthesize the current thread into a PRD on the issue tracker (no interview). |
| `to-issues` *(orchestrator)* | `/to-issues` — split a plan/PRD into independently-grabbable tracer-bullet issues. |
| `triage` *(orchestrator)* | `/triage` — move incoming issues/PRs through triage roles, write agent-ready briefs. |
| `setup-matt-pocock-skills` *(orchestrator)* | `/setup-matt-pocock-skills` — one-time config (issue tracker, triage labels, domain docs) the triage/PRD/issues skills assume. |
| `teach` *(orchestrator)* | `/teach` — learn a concept over multiple sessions in a stateful workspace. |
| `writing-great-skills` *(orchestrator)* | `/writing-great-skills` — reference + glossary for authoring skills well. |
| `git-guardrails-claude-code` *(model-invoked)* | Install a PreToolUse hook that blocks dangerous git commands. |
| `setup-pre-commit` *(model-invoked)* | Set up Husky + lint-staged + Prettier pre-commit hooks (JS/TS subtrees only). |
| `migrate-to-shoehorn` *(model-invoked)* | TS-only: replace `as` assertions in tests with shoehorn. Applies only to TS tooling, not the game. |
| `scaffold-exercises` *(model-invoked)* | ai-hero-cli course-authoring layout; not specific to the game. |

## The AI Layer

This repo's Claude Code configuration — the CLAUDE.md hierarchy, the skills above,
the read-only `explorer` subagent, and the `SessionStart` orientation hook — is
catalogued in [AI-LAYER.md](AI-LAYER.md).
