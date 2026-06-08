# Emberwilds

> *Rekindle the wilds.*

A **server-authoritative 2D co-op RPG** built with Godot 4.5+, where **your weapon
is your class**. There are no job classes to pick — you wield a **Sword, Bow,
Staff, or Dagger**, master it, dual-wield a second, and rebuild it through
branching upgrade trees. Modeled on MapleStory's chunky 2D hunting, crossed with
New World's weapon-driven identity and Diablo-style ability upgrades. Host a
lobby, bring your friends, and push the frontier back.

Generations ago the **Weave** that held all magic shattered in the **Emberfall**,
raining elemental **embers** across the land and warping the wild into monsters.
An ember can't be wielded barehanded — but *bound into a weapon, it can be
channelled*. You're a **Wilder**: take up your steel, walk past the lantern-light,
and rekindle the wilds. Full world bible in [docs/LORE.md](docs/LORE.md).

![Emberwilds title screen](README/Login.png)

## Screenshots

| Forge your legend | Choose your Wilder |
|---|---|
| ![Character creation](README/Character_Create.png) | ![Character select](README/Character_Select.png) |

| Lantern's Rest — the Hearth hub | Hunting the Near-Wilds |
|---|---|
| ![Lantern's Rest](README/Lanterns_Rest.png) | ![Gameplay](README/Gameplay.png) |

Dual-wield: two weapons equipped at once light up two signature gauges (here Sword
**Combo** + Bow **Momentum**) and a **Synergy** between the disciplines —

![Weapon gauges and synergy](README/Weapon_Widget.png)

| Weapon mastery & ability trees | The unified character hub |
|---|---|
| ![Abilities](README/Abilities.png) | ![Character window](README/Game_Window.png) |

## Features

### The weapon is the class
- **Four weapon disciplines** — Sword, Bow, Staff, Dagger — each with its own
  **signature gauge** (sword **Combo**, bow **Momentum**, staff **Element Stance**,
  dagger **Shadowmeld**), stat axis (Defense / Accuracy / Magic Attack / Evasion),
  and a different *mechanical shape*, not a reskin
- **Two weapon slots** equipped at once — your kit is the **union of two ability
  trees**, and passives stack from both slots
- **Per-discipline weapon mastery** (cap 100) earned by fighting with that weapon;
  the active weapon drives your damage scaling — *"I am my weapon"*
- **Spellblade hybrid:** wield a Staff with high STR/DEX and your magic damage
  folds in a slice of your melee stat

### Build it yourself
- **Freely-allocated attributes** — 5 points per level (495 at the cap). Five
  dual-role attributes, each a weapon stat **and** a utility: **STR** (+Defense),
  **DEX** (+Accuracy), **INT** (+Mana/MP regen), **LUCK** (+Crit rate), **CON**
  (+Max HP/HP regen — the tank lever)
- **Per-ability 3-tier upgrade trees** (Diablo-4 shape): a broad modifier → a
  mechanical augment → pick **one of three** mutually-exclusive Tier-3 variants
  that *change how the ability plays* — never just "+30% damage." **80 abilities
  with 343 upgrade variants** in the build
- **Free respec** at every granularity (one ability, a tree, a discipline, or
  everything) — rebuild around a new weapon without re-grinding
- Two divergent **paths per weapon** (Vanguard/Berserker, Marksman/Skirmisher,
  Elementalist/Sage, Assassin/Venomancer)

### Multiplayer & persistence
- **Server-authoritative** architecture — the server validates all state; clients
  send *intent* via RPCs, the server mutates and broadcasts the truth
- **Host / join** on a listen server, with in-game **channel** (port) switching
- Account & character system persisted to **PostgreSQL via a Flask REST API**
- Dedicated **headless server** support

### Combat
- **Basic attack** (always rolls off your active weapon), **abilities** on an
  8-slot hotbar, and a **signature gauge** you build and spend for a payoff cast
- **Mastery damage floor** (min roll = 20% of max) so even low rolls feel like
  progress; floating crit numbers; **CRITDAMAGE** as a chase gear stat
- A **second damage axis** — staff spells mitigate against Magic Defense
- Status effects: **bleed / poison / burn DoTs**, slow, knockback, stealth, marks
- **No dodge i-frames** — most enemies deal contact damage, so survival is HP, the
  potion loop, positioning, and per-weapon defensive abilities (MapleStory's model)

### World & enemies
- A **Hearth hub** (Lantern's Rest) ringed by **portal-connected wild maps** that
  climb from the Near-Wilds to the Sundered Heart and its keeper, the **Eternal
  Warlord** (level 100)
- **Per-map isolation** — each map runs in its own `SubViewport` with a fresh
  `World2D` (independent physics / nav / audio); maps stay warm in a residency pool
- **Parallax background layers** and **per-map camera bounds** auto-computed from
  the tilemap
- A **24-enemy ladder** (level 1 → 100) with state-machine AI (idle → patrol →
  chase → attack → leash) and both contact-damage and telegraphed-slash models
- **Server-side AI bots** that join parties, fight, loot, and focus your target —
  Erenshor-style population and party-fill
- **Pets** — owner-bound companions that auto-pot, auto-loot, and auto-buff

### Progression, quests & onboarding
- **Level cap 100**; character level and weapon mastery are decoupled but
  calibrated so mastery ~100 lands around level ~70 (then refine attributes & gear)
- **`.tres`-driven quests** — a guided **level 1 → 30 journey** across six chains,
  with first-login onboarding (auto-granted first kill + welcome overlay)
- An **always-on Quest Tracker** HUD; KILL / COLLECT / REACH_LEVEL objectives with
  prerequisites and chained unlocks

### Items & economy
- **Weapons** (two slots) and **armor** (head / chest / legs / feet) with rolled
  stats; **rarity** from Common to Legendary; ~281 item resources
- **Consumables** (HP/MP potions, pet food, pet skill books), merchant buy/sell,
  and dual-confirmation **player-to-player trading**

### Interface
- A **unified game window** — equipment, stats, the five attributes, inventory,
  and pet on a Character tab; the branching skill tree on an Abilities tab
- 8-slot hotbar with cooldowns, the four **screen-edge weapon-gauge widgets**, buff
  bar, target frame, party frames, and a mobile touch HUD
- In-game chat with slash commands (`/quest`, `/bot`, `/trade`, emotes, …) and a
  backtick-toggled developer console

## Getting Started

### Prerequisites
- **Godot Engine** 4.5+ (Forward Plus rendering)
- **Docker & Docker Compose** (for the backend/database)

### Setup

1. Clone the repository and open it in Godot:
   ```bash
   git clone <repository-url>
   cd emberwilds
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

> **Just want to see combat?** In a debug build, the login screen's dev panel
> (toggle with **F9**) has skip-to-combat buttons that host an offline max-level
> Wilder of each discipline straight into the field — no backend required.

To let friends outside your network play with persistent characters, see
[DEPLOYMENT.md](DEPLOYMENT.md) for the VPS recipe and the in-game Backend
Settings flow.

## How to Play

1. Create an account and log in on the Login screen.
2. **Forge your legend** — create a character and pick your **starting weapon**
   (Sword / Bow / Staff / Dagger). Characters persist across sessions.
3. **Host** a game (listen server) or **Join** one by entering the host's IP and port.
4. New Wilders start in the **Hearth**. Talk to the quest-giver Hearthfolk, step
   into a glowing **portal**, and head into the wilds. Build your weapon's gauge,
   spend it on a payoff, and pour your attribute and ability points into the build
   you want — respec is free if you change your mind.

### Controls (default — customizable in Options)

| Action | Input |
|---|---|
| Move left / right | A / D (or ← / →) |
| Move up / down | W / S (or ↑ / ↓) |
| Jump | Space |
| Basic attack | Left Ctrl |
| Weapon signature (spend gauge) | R |
| Swap weapon loadout | Tab |
| Ability hotkeys | 1 – 8 |
| Pick up item | Z |
| Character window (stats / equipment / inventory) | C / E / I |
| Abilities (skill tree) | K |
| Party window | P |
| Quest log | Q |
| Interact with NPC / chest | Right-click |
| Toggle in-game debug panel | ` (backtick) |

Drop through one-way platforms: hold **Move Down** and press **Jump**.

## Project Layout

```
addons/      Godot editor plugins (resource editor, balance/boss-attack designers)
assets/      Sprites, audio, fonts, shaders, themes, curves
backend/     Flask REST API + Dockerfile
docs/        GDD, world lore, ADRs, design references
resources/   Data-driven content (.tres): abilities, upgrades, buffs, items,
             enemies, disciplines, quests, VFX
scenes/      Levels, UI, player, NPC, and gameplay scenes
scripts/     Game logic (GDScript)
tools/       Content generators and screenshot/render scripts
```

## Architecture & Contributing

This repo uses a layered `CLAUDE.md` documentation hierarchy. Start with the root
[CLAUDE.md](CLAUDE.md), skim the [Game Design Document](docs/GDD.md) for the full
picture, then read the subsystem guide for the area you're touching:

| Area | Guide |
|---|---|
| Networking, RPCs, channels | [scripts/Networking/CLAUDE.md](scripts/Networking/CLAUDE.md) |
| Character components | [scripts/Components/CLAUDE.md](scripts/Components/CLAUDE.md) |
| Data resource classes | [scripts/Resources/CLAUDE.md](scripts/Resources/CLAUDE.md) |
| AI bots | [scripts/Bot/CLAUDE.md](scripts/Bot/CLAUDE.md) |
| Backend (Flask / Postgres) | [backend/CLAUDE.md](backend/CLAUDE.md) |

Key architectural decisions are recorded as ADRs in [docs/adr/](docs/adr/) (class
removal, the attribute system, the unified window, map residency, bots, pets, …).
Adding content (abilities, buffs, items, enemies, maps, backend endpoints) follows
packaged, repeatable workflows — see [AI-LAYER.md](AI-LAYER.md).

## Roadmap

The **weapon-identity overhaul is systems-complete in code**; the next milestones
are live multiplayer validation, balance tuning, and content depth (high-level
maps, authored boss mechanics, economy sinks). The full picture lives in the
[GDD §19 production roadmap](docs/GDD.md), with the tiered task board in
[TODO.md](TODO.md) and the showable-demo checklist in [DEMO_POLISH.md](DEMO_POLISH.md).

## Credits

- Built with [Godot Engine](https://godotengine.org/)
- Art assets from open-source pixel-art packs (Minifolks character & creature
  sprites, Country-village tileset & parallax pack, plus various creature
  spritesheets); UI font: PixelOperator. See individual asset folders for
  per-pack licensing.

## License

This project is for educational and demonstration purposes. See individual asset
folders for specific licenses.
