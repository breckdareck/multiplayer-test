---

kanban-plugin: board

---

## TODO

- [ ] Tier 1 — Social Foundation (mostly code, minimal art)
	- [x] Social Hub Towns — Lantern's Rest (spawn town) + Emberwatch: safe hubs with merchant + quest-giver NPCs, players spawn in Lantern's Rest on first login, Hearthstone/Town Scrolls return here (`MapManager.HEARTH_MAPS`)
	- [ ] Friend/Buddy System — Friend list with online status, current map, whisper/PM. Purely UI + networking code
	- [ ] Server-wide Announcements — Chat broadcasts for level milestones, rare drops, boss kills. Infrastructure exists (`_server_announce`) — just need event hooks
	- [ ] Fame/Reputation System — Once per day, +1 or -1 fame to another player. Simple number on character info panel
	- [x] Emotes — `/sit`, `/wave`, `/laugh`, `/cry` chat commands with rate limiting, server-broadcast text bubbles above the character (`show_emote_bubble`), and chat-window entries
- [ ] Tier 2 — Player Economy (all code)
	- [x] Player-to-Player Trading — `TradeManager` runs a proximity-gated, dual-confirmation offer/swap session (server-atomic swap of items + gold). Also supports a no-confirm player↔bot give/take flow
	- [ ] Free Market Zone — A map room where players open personal shops (UI panel listing items + prices). No new art, just a shop UI overlay
	- [ ] Crafting & enchanting — planned roadmap; the slim item-save design already accommodates it
- [ ] Tier 3 — Cooperative Content
	- [x] Party Grind Zones — party members on the same map share EXP with a scaling bonus (+10% per additional member); non-damage-dealing members still get 25% of base; mastery XP is shared too
	- [ ] First Party Quest — ONE simple PQ: 3 stages (kill room, switch puzzle, boss). Reuse existing enemies and tilesets
	- [x] First Boss Encounter — the **Eternal Warlord** (L100, The Sundered Heart): 3 HP phases + enrage, telegraphed `BossAttackData` specials (windup/hold/dash-slam), boss HP bar UI, authored with the `boss_attack_designer` dock (ADR 0005)
	- [x] First mid-band boss — **Thornroot Warchief** (L30 area boss in Thornroot Hollow, 3 phases + enrage + Thorn Rush dash special, Steel-tier drops, capstone quest)
	- [ ] More bosses — L45–70 zones still bossless; reuse the BossAttackData pipeline (add a .tres + optional logic_script, don't subclass)
- [ ] Tier 4 — Progression & Identity
	- [x] Weapon-driven identity — classes & job advancement REMOVED (ADR 0004); identity = 4 weapon disciplines (Sword/Bow/Staff/Dagger) with per-discipline mastery, dual-weapon kits + pair synergies, per-weapon gauges (combo / momentum / stances / shadowmeld)
	- [x] Attribute allocation — 5 free points per character level across STR/DEX/INT/LUCK/CON (ADR 0002), with reconcile guard, respec (cost scales with points refunded), backend `attribute_points` JSONB
	- [x] Ability trees + upgrades — 2-path tree per weapon, ~18 abilities each (≈73 base abilities), 3-tier per-ability upgrade trees (300+ upgrade .tres), purchase/respec API, points-reconcile guard on load
	- [x] Quest System — 31 quests across 8 chains covering L1–95 with no gaps (the Wilds chain bridges L26–40: Thornroot → Dust Warren → boss capstone → Drowned Mines), KILL/COLLECT/REACH_LEVEL objectives, onboarding welcome overlay + auto-accepted starter quest, always-on Quest Tracker HUD
	- [x] NPC quest-givers — `QuestGiverNPC` generalizes right-click NPC dialogs (Village Elder in Lantern's Rest, slime-threat giver in the Near-Wilds); quest IDs baked into NPC `offered_quest_ids`
	- [x] Pets — per-character roster with hunger/feeding, auto-loot magnet, auto-pot, auto-buff command slots (ADR 0001)
	- [ ] Daily Quests — 3 rotating daily objectives (kill X enemies, collect Y items). Rewards: EXP + coins
- [ ] Tier 5 — Guild System (mostly code)
	- [ ] Guild Basics — Create/join guilds, guild chat channel, member list with ranks. Reuse party UI patterns
	- [ ] Guild Perks — Simple passive buffs that scale with member count (bonus EXP %, drop rate %). Pure data, no art
- [ ] Tier 6 — World Expansion (art-heavy, pace yourself)
	- [x] Enemy Types — 33 EnemyData across Slime / Boar / Bunny / Fox / Goblin families with shadow, fire, dust, mithril, ember, runed, astral, and celestial variants spanning level bands 1–100, plus the Eternal Warlord boss
	- [x] Maps — 15 Emberwilds zones L1–100 (Lantern's Rest & Emberwatch towns → Near-Wilds … The Weave's Edge → The Sundered Heart), procedural map builder + portal retopology, minimap + M-key world map (reads `config/world_map_data.json` — regen via `tools/dump_world_map.gd`)
	- [x] Hidden Areas — secret portals leading to small bonus rooms with rare spawns (SecretPortal)
	- [ ] Jump Quest — One platforming challenge map using existing tiles. Reward: unique cosmetic or title
	- [x] Hearthstone + Town Scrolls — Hearthstone teleports to the nearest hearth (BFS), town scrolls are `Effect_TownPotion` consumables
- [ ] Tier 7 — Juice & Feel (incremental, do as you go)
	- [x] Screen Shake — `screen_shake()` on the player controller, triggered by `HealthComponent` on damage with intensity scaled to (damage / max_health)
	- [x] Level-up Effect — `_play_levelup_effect` spawns a GPUParticles2D burst on level-up, broadcast to all peers on the same map
	- [x] Music — title-screen track + per-zone BGM via `MapBase.bgm_path` through `AudioManager`
	- [x] Ability & hit VFX — data-driven `VfxEffectData` cast/hit bursts + tiled ground effects, assigned per ability in the resource_editor; DoT visuals (bleed/poison/burn) via `EnemyBase.play_dot`
	- [x] Enemy overhead HP bars — MapleStory-style, shown only to the hitter, 4s auto-hide
	- [ ] Hitstop on big crits / death feedback — see [DEMO_POLISH.md](DEMO_POLISH.md)
	- [ ] Megaphone Chat — Server-wide chat via consumable item. Reuse chat system
- [ ] Tier 8 — Stretch Goals
	- [ ] Mini-Game — One simple game (dice roll) between two players for coin wagers
	- [ ] Achievement Titles — Track milestones, display title under player name. Purely data + UI
	- [ ] Second Party Quest — Once first PQ is proven fun, build another for a higher level band
	- [x] Skill Trees — shipped as the branching 2-path-per-weapon ability tree (Vanguard/Berserker, Marksman/Skirmisher, Elementalist/Sage, Assassin/Venomancer) + 3-tier per-ability upgrades; v2 layout ideas tracked in memory


## In Progress

- [ ] Demo polish — the near-term path to a showable 15-minute slice lives in [DEMO_POLISH.md](DEMO_POLISH.md) (audio coverage audit, hitstop, death feedback, smoke tests)
- [ ] Combat pacing spectrum follow-ups (ADR 0014) — playtest-gated
	- [x] Four cooldown bands shipped: FILLER 1-2s / SHORT 4-6s / HEAVY 12-14s / ULTIMATE ~30s (one-shots an at-level normal), damage curve-calibrated vs enemy HP; primers 12s, marks 15s; duo ICD untouched
	- [x] Tooling: `tools/damage_matrix.gd` + `tools/damage_matrix_report.py` regenerate `docs/damage_matrix_report.md` with band-calibration checks at every 5 levels — re-run after ANY ability retune
	- [x] `pairtest <primary> <secondary>` console command: legit 100-point L100 pair build (every bar spans filler->ultimate), Astral gear, fresh Warlord per run
	- [ ] Feel-test the six pairs: ult moments, heavy->short->filler weave, 12s primer cross-weapon escalations, 10-15s swap dwell; re-judge the report's DPS-divergence baselines from feel
	- [ ] Held in reserve: Sword O2 AoE cap trims (docs/sword_outlier_review.md); endgame damage-vs-HP curve divergence (player ~L^1.6 vs HP L^2.3)
- [ ] Equipment System
	- [x] EquipmentComponent, slots, stats and bonuses
	- [x] Random affix rolls on equipment drops (rarity-scaled affix count, defining-stat 1.8× roll, dual-discipline stat breadth)
	- [ ] Equipment upgrade/enhancement system (scrolling — ties into the crafting roadmap)
- [ ] Map residency / handoff follow-ups
	- [x] Warm-pool map residency (ADR 0007 revisit) — occupied maps + portal neighbours resident, cold maps evicted, central proximity enemy activation
	- [x] Reparent map handoff for bots + HOST (ADR 0008, ADR 0009 Stage C) — live character node reparents instead of serialize→free→rebuild
	- [x] Persistent local UI layer (ADR 0009 Stages A/B) — HUD lifted out of the player body into a persistent client UI scene
	- [ ] Phase 2: reparent handoff for remote clients (designed, not built)
- [ ] Bot vertical navigation
	- [x] Ladder/rope nav (CLIMB edges, mount/dismount, jump-arc simulation, A* drop penalties, navgraph probe + overlay)
	- [ ] Remaining edge cases as found in playtests


## Complete

- [x] Weapon-Identity Overhaul (Emberwilds)
	- [x] Game named **Emberwilds** + world bible (docs/LORE.md), all maps/items/quests reskinned to theme
	- [x] ClassComponent removed → WeaponMasteryComponent owns identity (ADR 0004); legacy class saves normalize on load
	- [x] ~73 base abilities + 300+ upgrade .tres across 4 disciplines, all formula-driven (no manual level_data)
	- [x] Weapon gauges: sword combo points, bow momentum, staff Fire/Ice/Lightning stances, dagger shadowmeld + pair-synergy widget
	- [x] Attribute allocation (5/level, CON added at StatType 15) + respec economy (cost ∝ points refunded)
	- [x] Unified Game Window (ADR 0003) — Character + Abilities tabs replace the standalone windows
	- [x] HUD: HP/MP → EXP → Mastery bars, hotbar with primary/secondary weapon swap slots, minimap + world map
	- [x] Balance passes: attack curve, boss multipliers, evasion-as-rogue-identity, dual-discipline armour affixes, DoT scaling off ability max hit
	- [x] Headless test harness (`test/`, `run_tests.bat`) — ability/boss/bot/nav suites, exit-code CI-able
	- [x] Editor tooling: resource_editor dock (upgrade trees, VFX picker, validation), balance_simulator, boss_attack_designer
	- [x] Menu polish: juiced login / character-select / character-create screens (parallax, idle bob, dev tools hidden behind F9)
	- [x] Generated pixel-art icons for all abilities and the full weapon/armor tier ladders
- [x] Item System Foundation
	- [x] ItemData resource class, categories (weapon, armor, consumable, material), rarity system, random stats on drops, consumable + equipment effects/modifiers
- [x] Combat System Expansion
	- [x] Attack types beyond basic attacks, skill system, critical hits, miss chance based on level difference
	- [x] Boss encounter system (ADR 0005): is_boss EnemyData, HP phases, enrage, telegraphed BossAttackData specials
- [x] Inventory System
	- [x] InventoryComponent, slots + stacking, drag-and-drop UI, ResourceManager item database, persistence (save/load)
- [x] Player Systems
	- [x] Health component with damage, invulnerability, regen, death/respawn
	- [x] Stats system with level-based growth (now attribute-allocation driven; class system superseded by weapon disciplines)
	- [x] Leveling system with EXP curves (1–100)
	- [x] Combat system with hitboxes, damage calculation, attack timing
	- [x] Character selection and sprite management; creation picks a starting weapon discipline
	- [x] Player persistence (save/load via backend)
- [x] Core Multiplayer Infrastructure
	- [x] ENet networking (host/join, channel switching), server-authoritative RPC system, player management + sync, movement/input, state machine (idle, run, jump, attack, crouch, dash)
- [x] Gameplay Systems
	- [x] Enemy AI state machines, spawner system, drop tables + loot, collectibles, killzones, one-way platforms (tunneling fixed, crates = StaticBody2D), draggable UI windows
- [x] Merchant System
	- [x] Buy/sell logic with support for unique and stackable item buyback
- [x] Social Systems
	- [x] In-game chat system (ChatManager), party system (create, invite, accept, up to 4 players, shared EXP), customizable keybindings
- [x] Backend & Persistence
	- [x] Account system with Flask API and PostgreSQL
	- [x] Per-weapon (front/back) hotbar bars persisted independently; per-ability `upgrades` column on player_abilities; `attribute_points` JSONB
	- [x] Map transitions via MapManager (carried-state on map change, no backend round-trip)
- [x] Progression Journey
	- [x] First-login onboarding: welcome overlay (controls + tips, input-locked) + auto-accepted starter quest
	- [x] 26-quest chain L1–95 incl. 5 endgame zone quests, with prerequisites and quest-giver NPCs
	- [x] Always-on Quest Tracker HUD overlay + quest reward popups
- [x] World Polish
	- [x] Themed zone names + zone-entry banner that fades in on map change
	- [x] Per-zone camera bounds (auto-computed from the Mid tilemap, @tool editor preview outline) + limit_smoothed clamping
	- [x] Parallax background layers with per-map visibility gate


***

## Archive

- [x] Job Advancement (Swordsman→Crusader etc. at level 30) — SUPERSEDED: class advancement was removed entirely by the weapon-identity overhaul (ADR 0004); JobAdvancementManager no longer exists

%% kanban:settings
```
{"kanban-plugin":"board","list-collapse":[false,null,null,null,false,false]}
```
%%
