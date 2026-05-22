# Multiplayer Godot RPG

A **server-authoritative multiplayer RPG** built with Godot 4.5+, featuring
component-based characters, data-driven content, and a Flask + PostgreSQL backend
for account and character persistence. Play with friends in a persistent world
with leveling, equipment, abilities, parties, trading, and AI companions.

## Features

### Multiplayer & Persistence
- Server-authoritative architecture — the server validates all state, clients send intent via RPCs
- Host/join networking on a listen server, with in-game channel (port) switching
- Account & character system persisted to PostgreSQL
- Dedicated headless server support

### Characters & Progression
- Three classes — Swordsman, Archer, Mage — with class abilities and stat growth
- Job advancement into advanced classes at level 30
- Component-based characters: Health, Stats, Combat, Leveling, Class, Ability, Buff, Equipment, Inventory
- Ability system with cooldowns, skill points, prerequisites, stat scaling, and proc effects
- Buff/debuff system with stacking, durations, and custom logic hooks

### RPG Systems
- Inventory with stacking, drag-and-drop, and server validation
- Equipment slots (head, chest, legs, feet, weapon) with stat bonuses and visual changes
- Consumables — heal, restore mana, grant experience, town teleport
- Merchant buy/sell and player-to-player trading
- Quest system with NPC objectives
- Party system — create, invite, join, leave

### World & Combat
- Multiple zones with portal-based fast travel (town, game, game2, game3)
- Enemy AI state machines with aggro, chase, patrol, and attack behaviors
- Server-side AI bots that explore, fight, and trade
- Critical hits, floating damage numbers, invulnerability frames, death/respawn, killzones

### Interface
- Draggable windows for abilities, equipment, stats, inventory, party, and chat
- Hotbar with cooldown visualization, buff bar, and a mobile touch HUD
- In-game chat with slash commands

## Screenshots

| Main Menu | In-Game |
|---|---|
| ![Main Menu](README/main_menu_view.png) | ![In-Game](README/In_game_view.png) |

| Stats & Inventory | Ability Window |
|---|---|
| ![Stats and Inventory](README/stats_inventory_windows.png) | ![Ability Window](README/ability_window.png) |

## Getting Started

### Prerequisites
- **Godot Engine** 4.5+ (Forward Plus rendering)
- **Docker & Docker Compose** (for the backend/database)

### Setup

1. Clone the repository and open it in Godot:
   ```bash
   git clone <repository-url>
   cd multiplayer-test
   ```
2. Start the backend (required for account/character persistence):
   ```bash
   docker-compose up -d
   ```
   | Service | URL / Port |
   |---|---|
   | Flask API | http://localhost:5000 |
   | PostgreSQL | localhost:5432 |
   | Adminer (DB UI) | http://localhost:8080 |
3. Run the game — press **F5** in Godot. The main scene is `scenes/UI/LoginScreen.tscn`.

Dedicated headless server:
```bash
godot --headless --feature dedicated_server --path . -- --port 8080
```
Windows helpers: `start_server.bat` / `stop_server.bat`.

To let friends outside your network connect, see [DEPLOYMENT.md](DEPLOYMENT.md)
and [QUICK_START.md](QUICK_START.md).

## How to Play

1. Create an account and log in on the Login screen.
2. Create or select a character — characters persist across sessions.
3. **Host** a game (listen server) or **Join** one by entering the host's IP and port.

### Controls (default — customizable in Options)

| Action | Input |
|---|---|
| Move left / right | A / D |
| Move down | S |
| Jump | Space |
| Attack | Left Click |
| Ability hotkeys | 1–5 |
| Open windows | Tab (abilities), I (inventory), E (equipment), C (stats), P (party) |

Drop through platforms: hold **Move Down** and press **Jump**.

## Project Layout

```
addons/      Godot editor plugins
assets/      Sprites, audio, fonts, shaders, themes
backend/     Flask REST API + Dockerfile
resources/   Data-driven content (.tres): abilities, buffs, items, enemies, classes
scenes/      Levels, UI, player, NPC, and gameplay scenes
scripts/     Game logic (GDScript)
```

## Architecture & Contributing

This repo uses a layered `CLAUDE.md` documentation hierarchy. Start with the root
[CLAUDE.md](CLAUDE.md), then read the subsystem guide for the area you're touching:

| Area | Guide |
|---|---|
| Networking, RPCs, channels | [scripts/Networking/CLAUDE.md](scripts/Networking/CLAUDE.md) |
| Character components | [scripts/Components/CLAUDE.md](scripts/Components/CLAUDE.md) |
| Data resource classes | [scripts/Resources/CLAUDE.md](scripts/Resources/CLAUDE.md) |
| AI bots | [scripts/Bot/CLAUDE.md](scripts/Bot/CLAUDE.md) |
| Backend (Flask / Postgres) | [backend/CLAUDE.md](backend/CLAUDE.md) |

Adding content (abilities, buffs, items, enemies, maps, backend endpoints) follows
packaged, repeatable workflows — see [AI-LAYER.md](AI-LAYER.md).

## Roadmap

Planned work is tracked in [TODO.md](TODO.md) — a tiered board covering social
systems, the player economy, cooperative content (party quests, bosses), guilds,
and world expansion.

## Credits

- Built with [Godot Engine](https://godotengine.org/)
- Art and sound assets from [Kenney.nl](https://kenney.nl/) and other open sources

## License

This project is for educational and demonstration purposes. See individual asset
folders for specific licenses.
