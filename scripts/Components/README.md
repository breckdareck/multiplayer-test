# Component System Documentation

This document explains how the various components in the multiplayer game work together to create a cohesive character system.

## Component Overview

### 1. ClassComponent (`class.gd`)
- **Purpose**: Manages character class selection and provides class-specific bonuses and skills
- **Key Features**:
  - Three classes: SWORDSMAN, ARCHER, MAGE
  - Class bonuses for stats (strength, dexterity, intelligence, vitality)
  - Class-specific skill lists
  - Signals when class changes to trigger stat recalculation

### 2. StatsComponent (`stats.gd`)
- **Purpose**: Manages character statistics and applies class bonuses
- **Key Features**:
  - Base stats with level-based growth
  - Integrates with ClassComponent to apply bonuses
  - Provides derived stats (attack power, magic power, defense, critical chance)
  - Automatically recalculates when level or class changes

### 3. LevelingComponent (`level.gd`)
- **Purpose**: Handles character progression and experience
- **Key Features**:
  - Experience tracking and level progression
  - Configurable growth rates
  - Signals when leveling up to trigger stat and health recalculation

### 4. HealthComponent (`health.gd`)
- **Purpose**: Manages character health, damage, and death
- **Key Features**:
  - Health tracking with max health based on vitality
  - Invulnerability frames after taking damage
  - Health regeneration over time
  - Integrates with StatsComponent for health calculations

### 5. CombatComponent (`combat.gd`)
- **Purpose**: Handles combat mechanics and damage calculations
- **Key Features**:
  - Attack system with hitboxes and timers
  - Class-based damage bonuses using stats
  - Hit detection and damage application

## How Components Work Together

### Initialization Flow
1. **ClassComponent** initializes with default class (SWORDSMAN)
2. **StatsComponent** finds ClassComponent and connects to its signals
3. **StatsComponent** calculates initial stats and applies class bonuses
4. **HealthComponent** uses vitality from StatsComponent for max health
5. **CombatComponent** uses stats for damage calculations

### Class Change Flow
1. **ClassComponent.change_class()** is called
2. **ClassComponent** emits `class_changed` signal
3. **StatsComponent** receives signal and calls `_recalculate_stats()`
4. **StatsComponent** applies new class bonuses to stats
5. **HealthComponent** may update max health if vitality changed
6. **CombatComponent** automatically uses new stats for damage

### Level Up Flow
1. **LevelingComponent.add_exp()** is called
2. **LevelingComponent** emits `leveled_up` signal
3. **StatsComponent** receives signal and recalculates stats
4. **HealthComponent** receives signal and updates max health
5. All derived stats (attack power, magic power, etc.) are updated

### Damage Calculation Flow
1. **CombatComponent.perform_attack()** is called
2. **CombatComponent** calculates base damage from attack data
3. **CombatComponent** gets character stats and class from components
4. **CombatComponent** applies class-specific damage bonuses
5. **CombatComponent** calls **HealthComponent.take_damage()**
6. **HealthComponent** applies damage and handles invulnerability

## Class Bonuses

### SWORDSMAN
- Strength: +5
- Vitality: +3
- Damage bonus: +20% of strength

### ARCHER
- Dexterity: +8
- Strength: +2
- Damage bonus: +15% of dexterity

### MAGE
- Intelligence: +10
- Vitality: +1
- Damage bonus: +25% of intelligence

## Testing

Use the `ComponentTest` script to verify component integration:
1. Attach it to a node with all components
2. Run the scene to see debug output
3. Call `test_class_change()` to test class switching
4. Call `test_level_up()` to test level progression

## Debug Output

The components provide extensive debug output to help troubleshoot issues:
- Class changes and bonuses applied
- Stat recalculations and final values
- Damage calculations with breakdowns
- Health updates and level progression

## Common Issues and Solutions

### Class Bonuses Not Applied
- Ensure ClassComponent is properly connected to StatsComponent
- Check that `_recalculate_stats()` is called when class changes
- Verify class bonus values are correctly defined

### Stats Not Updating on Level Up
- Ensure LevelingComponent is connected to StatsComponent
- Check that `leveled_up` signal is properly emitted
- Verify `_recalculate_stats()` is called

### Health Not Updating with Stats
- Ensure HealthComponent is connected to LevelingComponent
- Check that `leveled_up` signal is properly connected
- Verify vitality calculation in `_on_player_leveled()`

### Combat Damage Not Using Stats
- Ensure CombatComponent has references to both Stats and Class components
- Check that damage calculation uses the correct stat getters
- Verify class-specific damage multipliers
