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

## Bot population

**Bot speech**:
A server-initiated chat line attributed to a bot, entered through a
server-side `ChatManager` call (a bot can never be an RPC's remote sender)
and broadcast like any player message — feed line + overhead bubble on every
peer's copy of the bot's character node. Event-keyed and always true to what
the bot actually did. See
[docs/adr/0011-bot-ambient-population.md](docs/adr/0011-bot-ambient-population.md).
_Avoid_: Bot chat AI, bot dialogue.

**Speech budget**:
The ChatManager-owned rate limit on bot speech: a server-wide minimum gap
between any two bot lines plus a per-bot cooldown, scaled by the bot's
chattiness. Exists so 20 bots build the busy-server illusion instead of
spamming it away.

**Personality archetype**:
A data-defined behavioral flavor for a bot — line-pool key, chattiness, zone
preference. Authored in `bot_config.json` for named bots; rolled once for
`/bot spawn random` bots and persisted in the bot roster.
_Avoid_: Personality type, role, profile.

**Bot roster**:
The server-side file (written by `BotManager`) persisting per-bot *identity*
(name, archetype, rolled traits). Distinct from the bot's **Player save**
(level/gear/build, which goes through `SaveManager` to the backend).
Deliberately NOT a Postgres column — see ADR 0011.
_Avoid_: Bot save, bot database.

**Companion command**:
A party-leader-issued `/bot` order (`follow`, `stay`, `free`) that sets a
mode flag on the bot's brain. Distinct from a **Pet command** (a taught pet
capability) and from trinity roles, which the party model deliberately lacks.
_Avoid_: Pet command, bot order, role assignment.

**Seeded spawn**:
A bot's first-ever spawn (no save row) at a level inside its home map's
`map_difficulty` band — granted through the `set_level` path (EXP + mastery
together) so the point-reconcile invariant holds — plus band-appropriate
gold. Existing bots load their save; seeding never re-applies.
_Avoid_: Level boost, starter level.

## Combat statuses

**Status tag**:
A canonical queryable category of enemy status — `bleed`, `poison`, `burn`,
`chill`, `mark` — aggregated across all per-source applications. Per-ability
meta keys (`hemorrhage_bleed`, `envenom_poison`, …) remain the unit of
stacking and tick math; the tag is the unit of *querying* (`is bleeding?`,
`total bleed stacks?` = sum across sources). Implemented as a registry index
on the enemy, maintained at apply time (`EnemyStatus` helper, BleedDot-style).
Consumers and escalation rules key off tags, never off per-ability keys.
Tag state is **enemy-global**: consumers read and spend the whole tag
regardless of which participant (player or bot) applied it; per-key tick/kill
credit keeps its existing last-refresher behavior.
_Avoid_: Status channel ("channel" is reserved for cast-over-time channeled
abilities and port-switched server instances), status effect, DoT type.

**Channeled ability**:
An active with a cast-time wind-up that roots the caster before its release
(Vanguard's Onslaught, Spellweave, Sky Volley, Stormcall, Charge!). Modified
by `channel_time_reduction` / `channel_time_extension` upgrade keys.
_Avoid_: Channel (bare — collides with server-instance channels), cast bar.

**Escalation rule**:
An authored cross-status combat rule fired at status-apply time — e.g. chill
applied to a burning enemy triggers a Thermal Shock burst. Lives in a small
static code table at the `EnemyStatus` registration chokepoint (deliberately
NOT `.tres`-driven: ~3 cross-cutting rules with bespoke effects, GW2-style
legibility). Reaction bursts scale off the *triggering* application's ability
max hit × stacks consumed, crediting the participant who completed the combo.
_Avoid_: Combo rule, element reaction (when meaning this system), proc.

**Duo node**:
The named synergy effect for a specific weapon-discipline pair (6 pairs
total): one on-swap trigger + one standing pair rule, authored in
`weapon_pair_synergy.gd`. NOT a purchasable upgrade — a stateless *derived*
unlock, active while both equipped disciplines have at least the threshold
points spent in them. Never persisted (recomputed from synced state), costs
no ability points, deactivates automatically on respec below threshold, and
works for bots with no extra wiring. Swap-trigger internal cooldowns are
transient server-side state, also never persisted.
_Avoid_: Duo boon, pair upgrade, synergy perk.

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

## Map residency & simulation

**Warm pool**:
The set of map scene instances the server keeps resident even when they hold
no occupants. A vacated map is not freed immediately; it enters a deferred-
unload grace period (TTL) and is only torn down if still empty when the timer
fires, or when an LRU cap forces eviction of the least-recently-vacated empty
map. Maps with any occupant — human **or bot** — are pinned and never evicted.
Exists to eliminate the cold-`instantiate()` hiccup on re-entry to a recently-
left map.
_Avoid_: Map cache, preload pool, pinned set.

**Enemy activation (awake / asleep)**:
A per-enemy simulation state. An **awake** enemy runs its full state-machine
tick; an **asleep** enemy has `_process`/`_physics_process` disabled and costs
≈0. State is driven externally by a per-map **proximity scanner**, not by the
enemy itself (an asleep enemy cannot self-detect). Wake when within
`detection_radius + margin` of any agent; sleep past a larger radius
(hysteresis). A map with zero agents runs no scanner, so all its enemies are
asleep — this is the only "paused map" state; there is no separate per-map
slow-tick.
_Avoid_: Map attention level, HOT/WARM/IDLE, slow-tick, tick-divisor.

**Reparent handoff**:
The bot-only map-change path that moves the *live* character node from the old
map's `Players` container to the new map's (across per-map SubViewport
World2Ds) instead of freeing it and re-instantiating `player.tscn` +
re-running `JoinHandshake`. Preserves all live component state; reuses the
recreate path's client-facing RPCs (`client_despawn_player` /
`client_spawn_player` / visibility / appearance). Gated on `is_bot` + already-
on-a-map, with a recreate fallback; a bot's first spawn still rebuilds. See
[docs/adr/0008-bot-map-change-reparent.md](docs/adr/0008-bot-map-change-reparent.md).
_Avoid_: Warm-body pool, fast-spawn, node recycling.

**Arrival reset**:
The small set of transient state the reparent handoff must explicitly clear
because the live node carries it across a hop (which free+recreate discarded):
zero `velocity`, reposition to the spawn point, reset the state machine to
neutral, reset per-weapon gauges (combo / charge / stealth). Persistent buffs
survive. Bots only hop while travelling, so there is no combat target to clear.

**Local player UI layer**:
(Proposed — ADR 0009.) A single persistent client-side `CanvasLayer` scene that
holds the local player's presentation — HUD (bars/hotbar/buffbar/widgets),
`MoveableWindows` (GameWindow, QuestWindow), keybinds/game menus — instantiated
once per client and **rebound** to the local character body on each spawn/map
change via a `MapManager.local_player_changed` signal. Distinct from the
**character body** (the in-map avatar: sprite/collision/components/camera/overhead
`PlayerWorldHUD`). Lifting the UI off the body is what lets the body reparent
(ADR 0008) without the UI's tree-notification cleanup breaking it.
_Avoid_: HUD node (when it lived under the player), player UI subtree.

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

## Enemy combat behaviour

**Attack pattern**:
An enemy's combat-behaviour identity — *how* it attacks — chosen so it pressures
some weapon disciplines and rewards others (a ranged plinker punishes slow melee,
a charger punishes kiting). The lever that makes the weapon-discipline choice felt
moment-to-moment rather than only on the character sheet. See
[docs/adr/0016-enemy-attack-patterns-ranged-delivery.md](docs/adr/0016-enemy-attack-patterns-ranged-delivery.md).
_Avoid_: AI type, behaviour profile, archetype (reserved for the defensive
stat-multiplier `MonsterArchetype`).

**Attack delivery**:
*How* an enemy attacks — expressed by **which attack STATE node it authors** under its
`StateMachine`, NOT by a data field (the old `EnemyData.attack_type` enum was removed).
The node types: `melee_attack` (frame-windowed hitbox swing), `ranged_attack` /
`secondary_attack` (`EnemyProjectileAttack` — homing projectile, the same one the
player uses), and a breath (`EnemyHitboxAttack` — a plume sprite + a cone hitbox).
`chase` polls each attack node's `can_start()` in child order and enters the first
ready one (presence-based dispatch; child order = priority). Each node owns its own
projectile/anim/cooldown/reach (`EnemyData` keeps only enemy-wide defaults —
`attack_range`, `attack_cooldown`, `ranged_projectile_scene/speed`). Orthogonal to
`is_magic_attacker`, the *damage axis* (physical vs magic).
_Avoid_: attack type (the removed enum), attack mode.

**Ranged caster**:
An enemy whose `attack_type` is `RANGED`/`MAGIC`: from `chase` it stops at its
`attack_range` and fires a homing projectile (the same one the player uses) at its
target instead of contact-swinging. Only engages targets within the **attack
box** (see below), and has no kiting AI — enemies have no pathfinding — so it
keeps casting at point-blank once meleed and dies fast (squishy by design; that
gap is the melee answer). `RabbitWizard` / `DeerDruid` are the first conversions.
_Avoid_: mage enemy, shooter, archer (an archer is the physical-projectile variant).

**Attack box**:
The region an enemy will attack into: within `attack_range` *horizontally* AND
within ±1 tile (~16px + slack) *vertically* (`EnemyBase.target_in_attack_zone`).
The vertical clamp is deliberate — it keeps a ranged enemy from firing across
several platforms; it engages only the same platform or one tile up/down.
_Avoid_: attack radius, aggro range (that's `detection_radius`), reach.

**Leaper**:
An enemy (`is_leaper`) that **runs at its target and hops a wall/step in its path**
to climb one tile up without breaking its charge — following the player onto a
platform one up. It doesn't bounce everywhere or stop short; it keeps coming and
rams on contact. The only enemy type that changes platforms (everyone else stays
on its own). The "charger" of the attack-pattern set: the counter to ranged/kiting,
denying the vertical escape a ranged caster's ±1-tile band leaves open. Boar is the first.
See [docs/adr/0017-leaper-enemy-hopping-locomotion.md](docs/adr/0017-leaper-enemy-hopping-locomotion.md).
_Avoid_: jumper, charger (the role), dasher (a dash is the rejected boss-style variant).

**Blocker**:
An enemy (`is_blocker`) that periodically raises a **frontal guard** (`enemy_block`
state, plays its `block` clip) while chasing: for the guard window, damage from the
front is heavily reduced and its flinch is suppressed, but a hit from **behind**
ignores the guard. The defensive member of the attack-pattern set — punishes
hold-to-attack spam, rewards timing (strike on the drop) and flanking (dagger
backstab). The SW Knight (ARMORED) is the first. See
[docs/adr/0018-blocker-enemy-frontal-guard.md](docs/adr/0018-blocker-enemy-frontal-guard.md).
_Avoid_: tank (that's the ARMORED archetype / a stat profile), parry (reactive, not built).

**Splitter**:
An enemy (`is_splitter`) that, on death, spawns `split_count` smaller, weaker
copies of its own scene, bounded by `split_generations` so the cascade can't
runaway. Fills the AoE-vs-single-target axis of the attack-pattern set — single-
target chip just makes more bodies, AoE clears the cluster. The base Slime is the
first. See [docs/adr/0019-splitter-exploder-swarm-enemies.md](docs/adr/0019-splitter-exploder-swarm-enemies.md).
_Avoid_: spawner (that's `EnemySpawner`/the pooling system), summoner.

**Exploder**:
An enemy (`is_exploder`) that bursts a circular AoE (`explode_radius`,
`explode_damage_mult`) around itself when it dies — punishes meleeing it / being
adjacent, rewards killing it from range. Usually `is_aggressive` so it rushes in.
The FireSlime is the first. See [docs/adr/0019-splitter-exploder-swarm-enemies.md](docs/adr/0019-splitter-exploder-swarm-enemies.md).
_Avoid_: bomber, kamikaze (informal), boss special (that's the telegraphed system).

**Swarm**:
Not a per-enemy mechanic but an encounter shape: a fast, low-HP `GLASS` mob (with
`attack_mult` toned down so the threat is *numbers*, not per-hit) placed in a
cluster — rewards AoE / punishes single-target. The **Feral Hare** (aggressive
Bunny-sprite variant) is the first. See [docs/adr/0019-splitter-exploder-swarm-enemies.md](docs/adr/0019-splitter-exploder-swarm-enemies.md).
_Avoid_: horde, pack (informal); not the same as a **Splitter** (which makes its
bodies on death).

**Telegraph (telegraphed zone)**:
A previewed AoE shape shown for a windup dodge-window before its damage resolves,
server-authoritative (`BossAttackData` + `broadcast_attack_telegraph` /
`deal_boss_special_damage`). Currently a **boss-only** mechanic — the ranged
caster fires a projectile, not a zone — but it remains the path if a zone-style
regular-enemy attack is wanted later.
_Avoid_: AoE marker, warning indicator, danger zone.

## Combat pacing

**Cooldown band**:
One of four pacing tiers every weapon kit's actives are authored into
(ADR 0014): FILLER (1-2s spam/builders), SHORT (4-6s), HEAVY (12-14s,
~0.45-0.75x of an at-level normal enemy's HP per target), ULTIMATE (~30s,
~one-shots an at-level normal, never a boss). Cooldowns are flat across
ability levels; damage curves are calibrated against the enemy HP curve by
`tools/damage_matrix.gd`.
_Avoid_: tier (collides with gear/upgrade tiers), rank.
