# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running the Game

- **Engine**: Godot 4.5+ (Forward Plus rendering)
- **Main scene**: `scenes/UI/LoginScreen.tscn` (set in project.godot)
- **Run in editor**: Press F5
- **Multiple instances for local multiplayer testing**: Launch additional instances from the editor's Debug menu or run the exported binary
- **Dedicated server** (headless):
  ```
  godot --headless --feature dedicated_server --path . -- --port 8080
  ```

## Backend (Required for account/character persistence)

```bash
docker-compose up -d
# Flask API: http://localhost:5000
# PostgreSQL: localhost:5432 (user: postgres, password: password, db: gamedb)
# Adminer DB UI: http://localhost:8080
```

Backend logs: `docker-compose logs api`

## Architecture Overview

This is a **server-authoritative multiplayer RPG** in Godot 4. All critical state mutations happen on the server; clients send intent via RPCs and receive authoritative state back.

### Autoload Singletons (globally accessible)

| Singleton | Script | Purpose |
|---|---|---|
| `MultiplayerManager` | `scripts/Managers/multiplayer_manager.gd` | Host/join, channel switching, level loading |
| `ServerManager` | `scripts/Networking/server_manager.gd` | ENet server lifecycle |
| `ClientManager` | `scripts/Networking/client_manager.gd` | ENet client connection |
| `PlayerManager` | `scripts/Networking/player_manager.gd` | Player spawn/cleanup |
| `ChannelManager` | `scripts/Networking/channel_manager.gd` | Port switching without restart |
| `NetworkUtils` | `scripts/Networking/network_utils.gd` | IP/port validation, scene helpers |
| `ResourceManager` | `scripts/Managers/resource_manager.gd` | Load/cache all `.tres` game data |
| `MapManager` | `scripts/Managers/map_manager.gd` | Map/zone transitions |
| `PartyManager` | `scripts/Managers/party_manager.gd` | Party creation/joining |
| `ChatManager` | `scripts/Managers/ChatManager.gd` | In-game messaging |
| `KeybindManager` | `scripts/Managers/keybind_manager.gd` | Custom keybindings |
| `UserConfig` | `scripts/Managers/user_config.gd` | User preferences persistence |
| `AudioManager` | `scripts/Managers/audio_manager.gd` | Music and SFX |
| `LogManager` | `scripts/Managers/LogManager.gd` | In-game debug logging |

### Component-Based Character System

Player and enemy characters are composed of child Node components under a root character node:

```
Player/
├── Health/       # health.gd — damage, invuln frames, regen, death/respawn
├── Stats/        # stats.gd — STR/DEX/INT/LUCK/etc., aggregates all bonuses
├── Combat/       # combat.gd — hitboxes, damage calc, crit hits
├── Ability/      # ability.gd — learn/level/use abilities, cooldowns, passives
├── Buff/         # buff.gd — timed buffs/debuffs with stacking and custom logic
├── Equipment/    # equipment.gd — 5 slots (head/chest/legs/feet/weapon)
├── Inventory/    # inventory.gd — item slots, stacking, drag-and-drop
└── Debug/        # debug.gd — dev-only heal/damage/exp buttons
```

Set exported references in `multiplayer_controller_v2.gd` to wire these together.

### Data-Driven Resources

Game data lives in `resources/` as Godot `.tres` files:
- `resources/Abilities/` — `AbilityData`, `AbilityLevelData`, `AbilityScalingData`, `ProcEffectData`
- `resources/Buffs/` — `BuffData`
- `resources/Items/` — `ItemData`, `EquipmentData`, `ArmorData`, `WeaponData`
- `resources/Player/Classes/` — `ClassData` (Swordsman, Archer, Mage)
- `resources/DropTables/` — enemy drop configuration

Access all resources via `ResourceManager` (never load directly at runtime).

### Custom Logic Scripts

- `scripts/AbilityLogic/` — `AL_*.gd` scripts executed by AbilityComponent for complex active abilities
- `scripts/BuffLogic/` — `BL_*.gd` scripts executed by BuffComponent for reactive buff effects

### Scene Requirements

- Gameplay scenes need `Level/Players` node path for player spawning
- Main menu needs `%MenuContainer` with `selected_character`, `get_username()`, and `setup_PID_label()`

### UI Flow

`LoginScreen` → `CharacterSelectScreen` / `CharacterCreationScreen` → `game.tscn`

All UI windows are draggable and toggled by input actions (Tab, I, E, C, P, etc.).

## RPC Conventions

```gdscript
# Server → Clients (authoritative updates) — "call_local" because host is also a client
@rpc("authority", "call_local", "reliable")

# Client → Server (input only)
@rpc("any_peer", "call_remote", "unreliable")

# Always guard server-only logic:
func _physics_process(delta: float) -> void:
    if not is_multiplayer_authority():
        return
```

Add all networked entities to the `networked_entities` group for consistent cleanup on disconnect/channel switch.

## Persistence

- In-game state: saved to `player_<username>.json` on server (health, level, exp, abilities, buffs, equipment, inventory, monies)
- Account/character records: persisted to PostgreSQL via Flask API
- Delete `player_<username>.json` to reset a character's in-game progress

## Adding New Content

**New ability**: Add `.tres` in `resources/Abilities/`, create `AL_*.gd` in `scripts/AbilityLogic/` if it needs custom active behavior, register in `ResourceManager`.

**New item**: Add `.tres` in `resources/Items/`, add to drop tables if needed.

**New enemy**: Create scene under `scenes/NPC/`, extend `enemy_base.gd`, add states in `scripts/Enemy/StateMachine/`.

**New map**: Create scene inheriting `MapBase` (`scripts/Gameplay/map_base.gd`), define spawn points and portals, register with `MapManager`.

**New backend endpoint**: Add SQLAlchemy model + Flask route in `backend/app.py`, call from Godot using `HTTPRequest`.

## Global Groups

- `networked_entities` — all network-spawned nodes; cleared on cleanup
- `Players` — player character nodes
- `Enemies` — enemy nodes