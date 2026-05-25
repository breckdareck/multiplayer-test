# multiplayer-test — domain glossary

The shared language of this Godot multiplayer RPG. Keep each entry tight:
define what the term IS, not what it does. Implementation lives in the code
and in the [CLAUDE.md](CLAUDE.md) hierarchy.

## Non-player entities

The repo has three distinct non-player entity types. They are NOT
interchangeable, despite all being "things that aren't you."

**Pet**:
An owner-bound companion entity spawned by `PetManager`. Has no peer id, no
`Health` / `Stats` / `Combat` components, and no AI brain — the owner's
client drives auto-loot and auto-pot loops, and the server runs the
auto-buff timer. Survives map and channel changes (re-spawned from the
owner's `summoned_pet_ids`). 1 pet active per owner in v1; save format
supports N.
_Avoid_: Companion, familiar, summon, minion.

**Bot**:
A server-side AI participant with a negative peer id and no networked
client. Drives the same `MultiplayerPlayerV2` character a human would,
supplying input flags via `bot_brain.gd`. Joins parties, fights enemies,
casts abilities. Cannot own a pet.
_Avoid_: AI player, NPC.

**Enemy**:
A hostile non-player monster, defined as `EnemyData` (`.tres`, NOT
auto-loaded — referenced directly from the enemy scene) and spawned via
`enemy_spawner`. Lives in the global `Enemies` group; filter by map when
iterating.
_Avoid_: NPC, mob, creature, monster (when used loosely).

## Pet vocabulary

**Pet skill book**:
A consumable (`PetSkillBookData extends ConsumableData`) that, when used on
a summoned pet, teaches it one command. Examples: "Pet Auto Pot Command",
"Pet Item Pouch Command", "Pet Meso Magnet Command", "Pet Buff Command".
Recorded per-pet as `learned_commands: []`. One-time consumption.
_Avoid_: Pet scroll, pet skill scroll.

**Pet command**:
A capability the pet can perform once taught — auto-pot, item pickup, coin
pickup, auto-buff. Distinct from a player **Ability**: commands are not
castable manually. Most cost nothing; auto-buff is the exception — it routes
through the owner's `AbilityComponent.use_ability`, so the owner's MP is
deducted exactly as if they had cast the buff themselves.
_Avoid_: Pet skill, pet ability.

**Pet inventory**:
A 5-slot per-pet storage attached to the pet record: 2 dedicated autopot
slots (HP and MP) + 3 generic storage slots. The autopot slots are the
sole source for auto-consumed potions; main inventory is not searched.

**Pet food**:
A consumable (`PetFoodData extends ConsumableData`) that restores pet
hunger when fed to a summoned pet. Distinct from a player HP/MP potion —
player potions cannot feed pets and pet food cannot heal players.

**Hungry state**:
A pet at 0 hunger. Stays summoned but stops following, stops all auto
actions, plays a sleeping sprite, and shows a persistent "Feed me!"
bubble. Feeding pet food exits the state. Auto-unsummons after 5 minutes
if the owner has moved beyond leash range.

**Pet leash**:
The maximum distance a pet may be from its owner. Used both for "teleport
pet to owner if it falls behind" and as the server-side clamp on
owner-client-reported pet position (defeats spoofing for distant auto-loot).

## Content & progression

**Ability**:
A castable or passive effect owned by a `Player` or `Bot`, defined as
`AbilityData` (`.tres`) under `resources/Abilities/<Class>/` and resolved
server-side. Single progression system — there is no separate "Skill".
_Avoid_: Skill, spell, technique, power.

**Component**:
A `Node` child of the character root that owns a single concern: `Health`,
`Stats`, `Combat`, `Ability`, `Buff`, `Equipment`, `Inventory`, `Debug`.
New character behavior slots into one of these. **Pets do NOT use this
pattern** — they have no components and cannot take damage.
_Avoid_: System, module, subsystem.

## World & networking

**Channel**:
A port-switched server instance, managed by `ChannelManager`. Players move
between channels to balance load or instance content.
_Avoid_: World, shard, server (when used loosely), realm.

**Map**:
A scene loaded within a channel, managed by `MapManager`. Has spawn
points, enemies, transitions to other maps.
_Avoid_: Level (unless naming the scene file), zone, area.

**Networked entity**:
Any node spawned through `PlayerManager`, `MapManager`, or `PetManager`
that must be cleaned up on disconnect or channel switch. Added to the
global `networked_entities` group.
_Avoid_: Actor, networked actor, replicated node.

## Persistence

**Player save**:
The per-character in-game state (health, level, exp, abilities, buffs,
equipment, inventory, monies, **pets**). JSON, written to the backend by
`SaveManager`, debounced.
_Avoid_: Save file, character data, profile.

**Character record**:
The per-character account-layer row in Postgres (login, character list,
owned characters, the unique `username`). Lives behind the Flask API.
_Avoid_: Account, profile, user record.
