# AI Agent Instructions for Multiplayer Godot Project

This document guides AI coding agents to be immediately productive in this codebase. It covers architecture, patterns, and development workflows.

## Development Environment Setup

### Backend & Database
```bash
# Start PostgreSQL and Flask API
docker-compose up -d

# Backend runs at http://localhost:5000
# Database: PostgreSQL on localhost:5432 (user: postgres, password: password, db: gamedb)
# Adminer UI for database management: http://localhost:8080
```

### Frontend (Godot)
- **Engine**: Godot 4.5+ (Forward Plus rendering)
- **Entry Point**: `scenes/UI/LoginScreen.tscn`
- **Run in Editor**: Press F5 or use the Play button
- **Launch Multiple Instances** (for local multiplayer testing):
  ```bash
  godot --path . &  # Multiple times in separate terminals
  ```

## Architecture Overview

- **Core Components**: Split into reusable components under `scripts/Components/` (health, stats, combat, etc.)
- **Network Architecture**: Server-authoritative with client-side prediction
  - Managers (`scripts/Managers/`): Handle global systems and multiplayer coordination 
  - Client sends intent via RPCs; server validates and replicates state
  - Use `networked_entities` group for cleanup tracking
- **Backend Integration**: Flask REST API (`backend/app.py`) handles accounts, characters, persistence, and party management
- **UI Flow**: LoginScreen → CharacterCreation/CharacterSelection → Game

## Key Design Patterns

1. **Component-Based Character System**
```gdscript
# Character scene structure:
- Player/  # or Enemy/
  ├── Health/          # health.gd
  ├── Stats/           # stats.gd
  ├── Combat/          # combat.gd
  ├── Ability/         # ability.gd
  ├── Buff/           # buff.gd
  ├── Equipment/      # equipment.gd
  ├── Inventory/      # inventory.gd
  └── Debug/          # debug.gd (dev only)
```

2. **Resource Management**
- Use `ResourceManager` singleton for loading game data
- Resources in `resources/` define game data as Godot resources
- Custom resources under `scripts/Resources/` for systems like abilities, items

3. **State Management**
- Server is authoritative for all state changes
- Components use RPCs for server-client sync
- Persist state in `player_<username>.json` files

## New Game Systems

### Account & Character Management (`scripts/Managers/` + Backend)
- **LoginScreen** (`scripts/UI/LoginScreen.gd`): Account creation and login via Flask API
- **CharacterCreationScreen** (`scripts/UI/CharacterCreationScreen.gd`): Character creation with class selection
- **CharacterSelectScreen** (`scripts/UI/CharacterSelectScreen.gd`): List and select characters from the account
- Backend persists account and character data to PostgreSQL
- Characters are loaded on game start based on selection

### Party System (`scripts/Managers/PartyManager`)
- **Creation & Joining**: Host can create parties; other players can request to join
- **Invitations**: `PartyInvitePopup` handles party invites with accept/decline
- **PartyWindow** (`scripts/UI/party_window.gd`): Display party members and manage party
- **PartyData** (`scripts/Networking/PartyData.gd`): Data structure for party information
- **Server-Authoritative**: All party state changes validated on server
- **API Integration**: Party data persists to backend

### Chat System (`scripts/Managers/ChatManager`)
- **ChatWindow** (`scripts/UI/ChatWindow.gd`): In-game messaging between players
- **ScrollingLog** (`scripts/UI/ScrollingLog.gd`): Message history display
- **LogMessage** (`scripts/UI/LogMessage.gd`): Individual message UI elements
- **Message Types**: Team chat, party chat, system messages
- **RPC-Based**: Messages broadcast via RPC with timestamps

### Map/Level Management (`scripts/Managers/MapManager`, `scripts/Gameplay/map_base.gd`)
- **Multiple Zones**: Supports multiple maps/levels
- **MapBase** (`scripts/Gameplay/map_base.gd`): Base class for maps with spawn points and zones
- **Portals** (`scripts/Gameplay/portal.gd`): Teleportation between maps
- **MapManager**: Handles map transitions and persistence
- **Entry Point**: Maps are loaded by `MultiplayerManager.change_level(scene_name)`

### Input & Configuration
- **InputManager** (`scripts/Managers/InputManager.gd`): Centralized input handling
- **KeybindManager** (`scripts/Managers/keybind_manager.gd`): Custom keybinding storage and retrieval
- **UserConfig** (`scripts/Managers/user_config.gd`): User preferences and settings persistence
- **LogManager** (`scripts/Managers/LogManager.gd`): In-game logging and debug output

## Common Tasks

### Adding New Features
1. Define data in appropriate resource system
2. Create component if needed, following existing patterns
3. Implement server-side logic
4. Add client-side UI/feedback
5. Wire up RPCs for synchronization
6. If persisting to database, add API endpoint in `backend/app.py`

### UI Development
- Use `scripts/UI/` conventions for windows
- Inherit from base window classes
- Connect to components via signals
- For account-related features, integrate with Flask backend

### Testing Changes
1. Run locally with player
2. Test client-server with multiple instances
3. Verify state persistence (both in-game JSON and backend database)
4. Check channel switching behavior
5. Test party and chat functionality with multiple players

## Project Conventions

### GDScript RPC Annotations & Authority Checks
```gdscript
# Host setup (Server/Client combined) always uses "call_local" for visibility
# Server -> Clients (authoritative updates)
@rpc("authority", "call_local", "reliable")
func sync_state(data: Dictionary) -> void:
    if multiplayer.is_server():
        # Server logic
        pass

# Client -> Server (input only, unreliable for performance)
@rpc("any_peer", "call_remote", "unreliable")
func send_input(input_vector: Vector2) -> void:
    if multiplayer.is_server():
        process_input(multiplayer.get_remote_sender_id(), input_vector)

# Always check authority before mutating state
func _physics_process(delta: float) -> void:
    if not is_multiplayer_authority():
        return
    # Server-authoritative logic here
```

### Backend API Integration
The Godot client communicates with the Flask backend (`backend/app.py`) for:
- **Account Management**: Registration, login, authentication
- **Character Management**: Character creation, listing, deletion
- **Player Persistence**: Load/save character data (equipment, inventory, abilities)
- **Party Operations**: Create, join, leave parties (RPC-driven in-game, API-backed persistence)

**Base URL**: `http://localhost:5000` (adjust for deployed backend)

**Key Endpoints**:
- `POST /api/accounts` - Register account
- `POST /api/login` - Authenticate and get session token
- `GET/POST /api/players` - Character CRUD operations
- `POST /api/parties` - Party management
- `PUT /api/players/<player_id>` - Save player state

### Networking
- Server-authoritative actions use RPCs
- Client prediction allowed for smooth movement
- Full state sync on client connect
- Clean up via `networked_entities` group

### Component Integration
```gdscript
# Required node paths:
health_component = $Health
stats_component = $Stats
combat_component = $Combat
ability_component = $Ability
buff_component = $Buff
equipment_component = $Equipment
inventory_component = $Inventory

# Connect required signals:
health_component.connect("health_changed", _on_health_changed)
stats_component.connect("stats_changed", _on_stats_changed)
```

### Scene Requirements
```
Level/
  └── Players/  # Required for spawning
MenuContainer/  # Required in main menu
  ├── selected_character
  ├── get_username()
  └── setup_PID_label()
```

## Common Pitfalls

1. **State Management**
   - Always modify state on server first
   - Use RPCs for client updates
   - Handle disconnects/cleanup properly
   - Persist to backend API when appropriate (accounts, characters, parties)

2. **Resource Loading**
   - Access via `ResourceManager` singleton
   - Cache resources when possible
   - Handle missing resources gracefully

3. **Component Dependencies**
   - Check required component references
   - Maintain proper initialization order
   - Clean up references on scene changes

4. **Backend Integration**
   - Account/character operations must go through Flask API
   - Use proper error handling for network failures
   - Validate all data server-side before persisting
   - Don't expose sensitive operations (passwords, admin actions) to clients

5. **RPC Authority**
   - Ensure proper `@rpc` annotations with correct peer types
   - Always validate sender ID in server-side RPC handlers
   - Use `call_remote` instead of `call_local` for client-only actions to avoid execution on server

## Database Schema (Backend)

The PostgreSQL database includes tables for:
- `accounts`: User accounts with usernames and hashed passwords
- `players`: Character records linked to accounts (level, class, experience, health, inventory)
- `player_items`: Character inventory items
- `player_equipment`: Character equipped items
- `player_abilities`: Character learned abilities and levels
- `parties`: Party groups with creation timestamps
- `party_members`: Players in parties

See `backend/app.py` for SQLAlchemy model definitions.

## Tool & Development Workflow

### Running the Game
- **Development**: Run `scenes/UI/LoginScreen.tscn` as the main scene (already set in project.godot)
- **Testing**: Launch multiple instances from editor or built executables
- **Dedicated Server**: `godot --headless --feature dedicated_server --path . -- --port 8080`
- **Backend**: Ensure `docker-compose up` is running for account/character persistence

### Debugging
- Use Debug component in dev builds (visible in player inspector)
- Check network panel in Godot editor for RPC traffic
- Monitor component signals for state changes
- Backend logs: Check Docker logs with `docker-compose logs api`
- Database: View via Adminer at `http://localhost:8080` (select PostgreSQL)

### Key File Locations

**Entry Points**:
- `scenes/UI/LoginScreen.tscn` - Account login/creation
- `scenes/UI/CharacterSelectScreen.tscn` - Character selection
- `scenes/Levels/game.tscn` - Main gameplay level

**Managers (Autoloads)**:
- `scripts/Managers/multiplayer_manager.gd` - Host/join/channel switching
- `scripts/Managers/resource_manager.gd` - Game data loading
- `scripts/Managers/party_manager.gd` - Party operations
- `scripts/Managers/chat_manager.gd` - Chat messages

**Networking**:
- `scripts/Networking/server_manager.gd` - Server setup
- `scripts/Networking/client_manager.gd` - Client connection
- `scripts/Networking/player_manager.gd` - Player spawning/cleanup
- `scripts/Networking/channel_manager.gd` - Channel switching

**Player Controller**:
- `scripts/Player/multiplayer_controller_v2.gd` - Main player script
- `scripts/Player/multiplayer_input.gd` - Input synchronizer

## Extension Points

### Backend API Development
The Flask backend (`backend/app.py`) handles:
- Account registration and login
- Character CRUD operations
- Party creation and management
- Character data persistence

**To Add New Endpoints**:
1. Define a new SQLAlchemy model (if needed) in `backend/app.py`
2. Create Flask routes following existing patterns
3. Add corresponding Godot client code in appropriate Manager or Component
4. Use `HTTPRequest` nodes or utility functions to call endpoints

**Example API Call Pattern**:
```gdscript
# In a Manager or Component
var http_request = HTTPRequest.new()
add_child(http_request)
http_request.request_completed.connect(_on_http_response)
http_request.request(
    "http://localhost:5000/api/players",
    ["Content-Type: application/json"],
    HTTPClient.METHOD_POST,
    JSON.stringify({"username": "player_name", "level": 1})
)

func _on_http_response(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
    if response_code == 201:  # Created
        var data = JSON.parse_string(body.get_string_from_utf8())
        # Process response
```

### Adding Game Content
1. **New Abilities**:
   - Add resource in `resources/Abilities/`
   - Create logic script in `scripts/AbilityLogic/`
   - Register in `ResourceManager`

2. **New Items**:
   - Define in `resources/Items/`
   - Add to drop tables if needed
   - Update UI as required
   - For unique items, ensure they're generated with randomized stats (see `ItemData` in resources)

3. **New Enemy Types**:
   - Create scene under `scenes/NPC/`
   - Implement AI in `scripts/Enemy/StateMachine/`
   - Configure spawning and drops

4. **New Maps**:
   - Create scene inheriting from `MapBase` (`scripts/Gameplay/map_base.gd`)
   - Define spawn points and portals
   - Add to level transitions via `MapManager.change_level()`

### GDScript-Specific Patterns for This Project

**Singleton Access**:
```gdscript
# All these are autoloaded - accessible globally
ResourceManager.get_item_data("item_id")
PartyManager.create_party(player_ids)
ChatManager.send_message(text, channel)
MultiplayerManager.host_game()
```

**Component Initialization**:
```gdscript
# In a character controller, always wire components after they're created
extends Node

var health_component: HealthComponent
var stats_component: StatsComponent

func _ready() -> void:
    health_component = $Health
    stats_component = $Stats
    # Connect signals
    health_component.health_changed.connect(_on_health_changed)
```

**Signal-Based Communication**:
```gdscript
# Components emit signals for state changes
# Listen for these to update UI without tight coupling
ability_component.ability_used.connect(_on_ability_used)
buff_component.buff_applied.connect(_on_buff_applied)
stats_component.stats_changed.connect(_on_stats_changed)
```