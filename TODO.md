---

kanban-plugin: board

---

## TODO

- [ ] Tier 1 — Social Foundation (mostly code, minimal art)
	- [ ] Social Hub Town — Reuse existing tileset for a safe zone with NPC shops and a bulletin board. Players spawn here and return via town scrolls
	- [ ] Friend/Buddy System — Friend list with online status, current map, whisper/PM. Purely UI + networking code
	- [ ] Server-wide Announcements — Chat broadcasts for level milestones, rare drops, boss kills. Just formatted chat messages, no art needed
	- [ ] Fame/Reputation System — Once per day, +1 or -1 fame to another player. Simple number on character info panel
	- [ ] Emotes — Chat commands (/sit, /wave) that play existing sprite frames or simple text bubbles. Keep it simple
- [ ] Tier 2 — Player Economy (all code)
	- [ ] Player-to-Player Trading — Proximity-based trade window with dual confirmation. Reuse inventory UI patterns
	- [ ] Free Market Zone — A map room where players open personal shops (UI panel listing items + prices). No new art, just a shop UI overlay
- [ ] Tier 3 — Cooperative Content
	- [ ] Party Grind Zones — Bonus EXP multiplier when in a party. Pure code change to existing EXP system, zero art
	- [ ] First Party Quest — Start with ONE simple PQ: 3 stages (kill room, switch puzzle, boss). Reuse existing enemies and tilesets. Level 15-30
	- [ ] First Boss Encounter — One boss with 2 phases. Reskin/recolor an existing enemy sprite as a larger variant. Unique drops
- [ ] Tier 4 — Progression & Identity
	- [ ] Job Advancement — Class evolution at level 30 (e.g., Swordsman → Crusader). Server announcement. 2-3 new abilities per advanced class. No new sprites needed if abilities are projectile/hitbox based
	- [ ] Simple Quest System — NPC interaction + kill/collect objectives. Quest log UI. Start with 5-10 quests to guide early leveling
	- [ ] Daily Quests — 3 rotating daily objectives (kill X enemies, collect Y items, complete a PQ). Rewards: EXP + coins
- [ ] Tier 5 — Guild System (mostly code)
	- [ ] Guild Basics — Create/join guilds, guild chat channel, member list with ranks. Reuse party UI patterns
	- [ ] Guild Perks — Simple passive buffs that scale with member count (bonus EXP %, drop rate %). Pure data, no art
- [ ] Tier 6 — World Expansion (art-heavy, pace yourself)
	- [ ] 2-3 New Enemy Types — Recolor/variant sprites of existing enemies with different stats and AI behaviors
	- [ ] 2-3 New Maps — Level-banded zones (30-50, 50-70). Reuse tilesets with different layouts and color palettes
	- [x] Hidden Areas — 1-2 secret portals in existing maps leading to small bonus rooms with rare spawns (SecretPortal implemented)
	- [ ] Jump Quest — One platforming challenge map using existing tiles. Reward: unique cosmetic or title
	- [x] Town Scrolls — Consumable item to teleport back to hub town. Just an item effect, no art (Effect_TownPotion implemented)
- [ ] Tier 7 — Juice & Feel (incremental, do as you go)
	- [ ] Screen Shake — Simple camera shake on big hits. A few lines of code
	- [ ] Level-up Effect — Simple particle burst or flash on level up. Use Godot's built-in GPUParticles2D
	- [x] Per-map BGM — Add royalty-free music tracks per zone. Just AudioStreamPlayer setup (MapBase.bgm_path implemented)
	- [ ] Megaphone Chat — Server-wide chat via consumable item. Reuse chat system
- [ ] Tier 8 — Stretch Goals
	- [ ] Mini-Game — One simple game (dice roll) between two players for coin wagers
	- [ ] Achievement Titles — Track milestones, display title under player name. Purely data + UI
	- [ ] Second Party Quest — Once first PQ is proven fun, build another for a higher level band
	- [ ] Skill Trees — Branching ability choices per class. Complex but all code/data, no art


## In Progress

- [ ] Item System Foundation
	- [x] Create ItemData resource class
	- [x] Implement item categories (weapon, armor, consumable, material)
	- [x] Create item effects and modifiers (for equipment)
	- [x] Add item rarity system (common, uncommon, rare, epic, legendary)
	- [x] Add random stats to equipment drops
	- [x] Create item effects and modifiers (for consumables)
- [ ] Equipment System
	- [x] Create EquipmentComponent class
	- [x] Define equipment slots (weapon, armor, accessories)
	- [x] Implement equipment stats and bonuses
	- [ ] Create equipment upgrade/enhancement system
- [ ] Combat System Expansion
	- [x] Expand attack types beyond basic attacks
	- [x] Add skill system implementation
	- [x] Add critical hit mechanics
	- [x] Add miss chance based on level difference


## Complete

- [x] Inventory System
	- [x] Create InventoryComponent class
	- [x] Implement inventory slots and item stacking
	- [x] Add drag-and-drop inventory UI
	- [x] Create item database and item types / ResourceManager
	- [x] Implement inventory persistence (save/load)
- [x] Swapping out Monster Health and EXP given for the Curves Created
- [x] Player Systems
	- [x] Health component with damage, invulnerability, regen, death/respawn
	- [x] Stats system (STR, DEX, INT, VIT) with level-based growth
	- [x] Class system (Beginner, Swordsman, Archer, Mage, Rogue) with stat bonuses
	- [x] Leveling system with EXP curves and level-up mechanics (1-100)
	- [x] Combat system with hitboxes, damage calculation, and attack timing
	- [x] Character selection and sprite management
	- [x] Player persistence (save/load to JSON files)
- [x] Core Multiplayer Infrastructure
	- [x] Multiplayer networking with ENet (host/join, channel switching)
	- [x] Server-authoritative architecture with RPC system
	- [x] Player management and synchronization
	- [x] Basic player movement and input handling
	- [x] State machine for player actions (idle, run, jump, attack, crouch, dash)
- [x] Gameplay Systems
	- [x] Basic enemy AI with state machines (Slime, Goblin, Template)
	- [x] Enemy spawner system
	- [x] Drop tables and loot system
	- [x] Collectibles (coins) with pickup mechanics
	- [x] Killzones for player death
	- [x] Platform mechanics (drop-through, mobile HUD support)
	- [x] Draggable UI windows
- [x] Merchant System
	- [x] Implemented buy/sell logic with support for unique and stackable item buyback
- [x] Social Systems
	- [x] In-game chat system (ChatManager)
	- [x] Party system (create, invite, accept, up to 4 players, shared EXP)
	- [x] Customizable keybindings
- [x] Abilities & Buffs
	- [x] 11 abilities with leveling, cooldowns, passives, proc effects
	- [x] Buff/debuff system with stacking and custom logic
	- [x] Ability logic scripts (SlashBlast, PowerGuard, MapleWarrior, EnhancedBasics)
- [x] Backend & Persistence
	- [x] Account system with Flask API and PostgreSQL
	- [x] 3 maps with portal system (game, game2, game3)
	- [x] Map transitions via MapManager


***

## Archive

- [ ]

%% kanban:settings
```
{"kanban-plugin":"board","list-collapse":[false,null,null,null,false,false]}
```
%%
