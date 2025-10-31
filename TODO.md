---

kanban-plugin: board

---

## TODO

- [ ] User Experience
	- [ ]  Add tutorials and help system
	- [ ]  Implement accessibility features
	- [ ]  Create localization system
	- [ ]  Add customizable controls and keybindings
- [ ] Visual & Audio
	- [ ]  Add particle effects for combat and skills
	- [ ]  Implement screen shake and visual feedback
	- [ ]  Add ambient sounds and music transitions
	- [ ]  Create visual effects for status conditions
- [ ] Trading & Economy
	- [ ]  Implement player-to-player trading
	- [ ]  Create auction house system
	- [ ]  Add currency system (gold, premium currency)
	- [ ]  Implement item pricing and market dynamics
- [ ] World & Exploration
	- [ ]  Implement multiple zones and areas
	- [ ]  Add teleportation and fast travel
	- [ ]  Create exploration rewards and discoveries
	- [ ]  Implement weather and time systems
- [ ] Guild & Social Features
	- [ ]  Create guild system with ranks and permissions
	- [ ]  Implement guild chat and announcements
	- [ ]  Add guild activities and events
	- [ ]  Create friend system and private messaging
- [ ] Combat & Skills
	- [ ]  Implement skill trees for each class
	- [ ]  Add active and passive skills
	- [ ]  Create skill cooldown system
	- [ ]  Implement skill effects and animations
	- [ ]  Add combo system with skill chains
- [ ] Enemy & Boss System
	- [ ]  Create boss encounters with multiple phases
	- [ ]  Implement enemy AI patterns and behaviors
	- [ ]  Add enemy loot tables and drop rates
	- [ ]  Create mini-boss and world boss systems
	- [ ]  Implement enemy scaling with player level
- [ ] Quest & Progression
	- [ ]  Create quest system with objectives
	- [ ]  Implement quest rewards and progression
	- [ ]  Add daily/weekly quests
	- [ ]  Create achievement system
	- [ ]  Implement reputation system
- [ ] Enemy AI Enhancement
	- [ ]  Expand enemy state machines (currently basic)
	- [ ]  Add more enemy types beyond basic goblin/slime
	- [ ]  Implement enemy pathfinding and behavior patterns
	- [ ]  Add enemy loot drops



## In Progess

- [ ] Item System Foundation (High Priority)
	- [x]  Create ItemData resource class
	- [x]  Implement item categories (weapon, armor, consumable, material)
	- [x]  Create item effects and modifiers (for equipment)
	- [x]  Add item rarity system (common, uncommon, rare, epic, legendary)
	- [x]  Add random stats to equipment drops
	- [ ]  Create item effects and modifiers (for consumables)
- [ ] Equipment System (High Priority)
	- [x]  Create EquipmentComponent class
	- [x]  Define equipment slots (weapon, armor, accessories)
	- [x]  Implement equipment stats and bonuses
	- [ ]  Create equipment upgrade/enhancement system
- [ ] Combat System Expansion
	- [x]  Expand attack types beyond basic attacks
	- [x]  Add skill system implementation
	- [x]  Add critical hit mechanics
	- [x]  Add miss chance based on level difference


## Complete

- [x] Inventory System (High Priority)
	- [x]  Create InventoryComponent class
	- [x]  Implement inventory slots and item stacking
	- [x]  Add drag-and-drop inventory UI
	- [x]  Create item database and item types/ AKA ResourceManager to get itemData by UUID
	- [x]  Implement inventory persistence (save/load)
- [x] Swapping out Monster Health and EXP given for the Curves Created
- [ ] Player Systems
	- [x]  Health component with damage, invulnerability, regen, death/respawn
	- [x]  Stats system (STR, DEX, INT, VIT) with level-based growth
	- [x]  Class system (Swordsman, Archer, Mage) with stat bonuses
	- [x]  Leveling system with EXP curves and level-up mechanics
	- [x]  Combat system with hitboxes, damage calculation, and attack timing
	- [x]  Character selection and sprite management
	- [x]  Player persistence (save/load to JSON files)
- [ ] Core Multiplayer Infrastructure
	- [x]  Multiplayer networking with ENet (host/join, channel switching)
	- [x]  Server-authoritative architecture with RPC system
	- [x]  Player management and synchronization
	- [x]  Basic player movement and input handling
	- [x]  State machine for player actions (idle, run, jump, attack, crouch, dash)
- [ ] Gameplay Systems
	- [x]  Basic enemy AI with state machines
	- [x]  Enemy spawner system
	- [x]  Collectibles (coins) with pickup mechanics
	- [x]  Killzones for player death
	- [x]  Platform mechanics (drop-through, mobile HUD support)
	- [x]  Basic UI with moveable windows
- [x] Merchant System
	- [x] Implemented buy/sell logic with support for unique and stackable item buyback.


***

## Archive

- [ ] 

%% kanban:settings
```
{"kanban-plugin":"board","list-collapse":[false,null,null,null,false,false]}
```
%%
