# AI Agent Instructions for Multiplayer Godot Project

This document guides AI coding agents to be immediately productive in this codebase. It covers architecture, patterns, and development workflows.

## Architecture Overview

- **Core Components**: Split into reusable components under `scripts/Components/` (health, stats, combat, etc.)
- **Network Architecture**: Server-authoritative with client-side prediction
  - Managers (`scripts/Managers/`): Handle global systems and multiplayer coordination 
  - Client sends intent via RPCs; server validates and replicates state
  - Use `networked_entities` group for cleanup tracking

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

## Common Tasks

### Adding New Features
1. Define data in appropriate resource system
2. Create component if needed, following existing patterns
3. Implement server-side logic
4. Add client-side UI/feedback
5. Wire up RPCs for synchronization

### UI Development
- Use `scripts/UI/` conventions for windows
- Inherit from base window classes
- Connect to components via signals

### Testing Changes
1. Run locally with player
2. Test client-server with multiple instances
3. Verify state persistence
4. Check channel switching behavior

## Project Conventions

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

2. **Resource Loading**
   - Access via `ResourceManager` singleton
   - Cache resources when possible
   - Handle missing resources gracefully

3. **Component Dependencies**
   - Check required component references
   - Maintain proper initialization order
   - Clean up references on scene changes

## Tool & Development Workflow

### Running the Game
- Development: Run `main_menu.tscn`
- Testing: Launch multiple instances
- Dedicated Server: `godot --headless --feature dedicated_server --path . -- --port 8080`

### Debugging
- Use Debug component in dev builds
- Check network panel for RPC traffic
- Monitor component signals for state changes

## Extension Points

### Adding Game Content
1. **New Abilities**:
   - Add resource in `resources/Abilities/`
   - Create logic script in `scripts/AbilityLogic/`
   - Register in `ResourceManager`

2. **New Items**:
   - Define in `resources/Items/`
   - Add to drop tables if needed
   - Update UI as required

3. **New Enemy Types**:
   - Create scene under `scenes/NPC/`
   - Implement AI in `scripts/Enemy/StateMachine/`
   - Configure spawning and drops