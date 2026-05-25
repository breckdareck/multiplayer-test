# Pet system — implementation phasing

The full pet design is large enough that a single PR would be unreviewable. This document slices it into nine phases that each ship independently, each unlocks the next, and each is testable in isolation. Architecture decisions are in [docs/adr/0001-pet-system-architecture.md](adr/0001-pet-system-architecture.md). Vocabulary is in [CONTEXT.md](../CONTEXT.md).

## Slicing principle

Each phase ships **the smallest end-to-end vertical slice that produces a felt change in-game** — not a horizontal layer (data → server → UI). A phase that adds backend without something visible to a player is the wrong shape, because it cannot be reviewed by play-testing.

---

## Phase 1 — Foundation (no player-visible change)

**Goal**: scaffold the new types so subsequent phases plug into something that exists.

- `PetManager` autoload registered in `project.godot`.
- `PetData extends Resource` class in `scripts/Resources/PetSystem/PetData.gd` — fields: `pet_id`, `display_name`, `sprite_frames`, `walk_speed`, `leash_radius`, `autoloot_radius`, `hunger_decay_per_sec`, `max_hunger`.
- `PetFoodData extends ConsumableData` and `PetSkillBookData extends ConsumableData` subclasses (each with the one new field they need).
- `pets: []` and `summoned_pet_ids: []` added to the save format. Loaders default missing keys to `[]`. No write path yet.
- The `add-item` skill receives a small note about the new subclasses.

**Visible change**: none. **Ships when**: the project compiles, save loads cleanly with empty pet arrays, autoload list is clean.

---

## Phase 2 — Egg + hatch + follow (the cute slice)

**Goal**: a player can use an egg, name their pet, see it appear, and have it follow.

- One `PetData` `.tres` instance authored (e.g., "Basic Hound").
- One Pet Egg consumable authored via `add-item`.
- Hatch flow: server-side handler consumes egg, opens name-input dialog on owner client, creates pet record in save, auto-summons.
- Spawn pathway: `PetManager.spawn_pet_server(owner_id, pet_id)` adds pet node under `map_root`, sets multiplayer authority to owner, adds to `networked_entities`.
- Follow logic on owner client: simple lerp toward owner with a small offset, capped at leash radius (teleport to owner if exceeded).
- Despawn on disconnect / channel / map change; re-spawn from `summoned_pet_ids` on the new context.

**Visible change**: you can hatch a pet and it follows you across maps. No auto-actions, no hunger, no UI window yet.

---

## Phase 3 — Pet management tab in Equipment panel

**Goal**: the player has a real UI to inspect and manage pets.

- New tab in the Equipment panel.
- Left list of owned pets (portrait + name + summoned indicator).
- Right detail: portrait, name (editable inline), [Summon/Unsummon] button, [Release] button with confirmation.
- Inventory slots: 5 visual slots (2 autopot + 3 storage), all empty / nonfunctional for now — UI scaffolding only.
- Locks input via `InputManager.set_input_locked(true/false)` on open/close.

**Visible change**: full pet management UI exists, even though most slots/buttons don't do anything yet.

---

## Phase 4 — Hunger + feeding + Hungry state

**Goal**: pets now have needs and the player must care for them.

- `PetManager._process` ticks hunger for each summoned pet whose owner is online.
- Server save throttling via `SaveManager`.
- Floating `!` bubble above pet at <25% hunger.
- Hungry state at 0: pet sprite swaps to sleeping animation, pet stops following, persistent "Feed me!" bubble.
- 5-minute auto-unsummon if owner leaves leash range while pet is Hungry.
- `PetFoodData` instance(s) authored via `add-item`.
- Pet management tab: "Feed" button → inventory picker filtered to `PetFoodData` → `PetManager.feed_pet_server(pet_id, slot_index)`.
- Re-summon a starved pet boots its hunger to 1 (small feed window).

**Visible change**: pets have a hunger bar, can be fed, get sad when starved.

---

## Phase 5 — Auto-loot (Item Pouch + Meso Magnet)

**Goal**: the headline pet QoL feature. Pet picks up loot.

- `PetSkillBookData` instances authored: "Pet Item Pouch Command", "Pet Meso Magnet Command".
- "Use" book on a summoned pet → server adds to `learned_commands`.
- Owner client adds 0.1s timer iterating `Players` group + dropped items on its map; for each in range of *pet position* and eligible for owner, sends `PetManager.request_autoloot_server(pet_id, drop_id)`.
- Server validation: caller owns pet, pet is summoned + not Hungry, pet position (server-synced) within `autoloot_radius + 16` of drop after leash clamp, owner eligible via existing `_can_player_pickup`, owner has inventory room, rate-limit 1 / 0.2s per pet.
- Pet sprite client-side: interrupt follow → walk toward drop → on RPC success, resume follow.
- Calls existing `_pickup_item(owner_node)` pathway.

**Visible change**: pet vacuums loot. The single biggest "wow" moment. Ship this before autopot/autobuff so the win lands clean.

---

## Phase 6 — Auto-pot (HP + MP) + pet inventory slots

**Goal**: the second-biggest QoL win. Pet keeps you alive.

- "Pet Auto Pot Command" book authored — unlocks both HP and MP autopot.
- Pet inventory tab: 2 dedicated autopot slots become functional (drag-drop from main inventory and back). Generic storage slots remain UI-only.
- Per-pet `autopot_config: { hp_item_id, hp_threshold, mp_item_id, mp_threshold }` — defaults blank, thresholds default 0.5.
- Pet management tab: HP/MP threshold sliders + (optionally) an "item picker" view for slot contents.
- Owner client 0.2s timer compares server-authoritative HP/MP to thresholds → `PetManager.request_autopot_server(pet_id, slot_type)`.
- Server validation: caller owns summoned non-Hungry pet, command learned, pet slot has matching item, threshold crossed, 1.0s cooldown per slot type independent.
- Consume happens from the pet slot, not main inventory.

**Visible change**: pet auto-uses HP/MP potions from its own slots. Configurable thresholds.

---

## Phase 7 — Auto-buff (slot + ability drag-in)

**Goal**: round out the trio of MapleStory pet actions.

- "Pet Buff Command" book authored — unlocks the buff slot.
- Pet management tab: buff slot dropdown lists owner's known abilities filtered to buff-type/self-target; player picks one → stored as `active_buff_ability_id`.
- Server-side timer in `PetManager._process` for each summoned pet with an active buff: when ability cooldown clears and owner doesn't have the buff (or remaining < 5s), apply the ability's `BuffData` to owner's `BuffComponent`. No MP cost, no `AbilityComponent` call.
- Hungry pets do not autobuff.

**Visible change**: pet keeps the owner buffed without intervention.

---

## Phase 8 — Generic storage slots

**Goal**: finish the pet inventory.

- The 3 generic storage slots in pet inventory become functional (drag-drop any item type to/from main inventory).
- On Release: storage slot contents return to main inventory; if full, drop on the floor at the pet's last position.

**Visible change**: pet is a small extra bag the player can carry.

---

## Phase 9 — Juice pass

**Goal**: make every pet interaction feel good. The original "fun and juice" ask.

- Hatch VFX (egg crack particles + chime).
- Pet summon "poof" particle + sound.
- Auto-loot: sparkle arc from drop to pet, then pet→owner.
- Auto-pot: brief tint flash on owner (red for HP, blue for MP).
- Auto-buff: cast bubble on pet ("Haste!"), icon flies to owner buff bar.
- Feed: "om nom" particle + chew sound.
- Idle: pet bounces / wags tail.
- Hunger warning sound when crossing 25%.

**Visible change**: every pet event has feedback. Game feels alive.

---

## What's NOT in this phasing (deferred to v2)

- Pet closeness / pet leveling / pet exp.
- Pet equipment items (collar, mask, name tag) and the corresponding equipped-on-pet slot system.
- Cash-shop-style premium pets and pet expiration timers.
- Party AoE for autobuff.
- Paid rename items.
- Pet "magnet" enchant items that boost autoloot radius beyond `PetData` defaults.
- Multiple simultaneously-summoned pets (the save format supports it; v1 caps at 1 active).
- Offline hunger ticking.
- Hunger affecting pet performance below the 0-threshold (we deliberately picked binary on/off).

---

## Phase dependency graph

```
1 Foundation
 └─ 2 Hatch + follow
     ├─ 3 Pet UI tab
     │   └─ 4 Hunger + feed
     │       ├─ 5 Auto-loot
     │       ├─ 6 Auto-pot
     │       ├─ 7 Auto-buff
     │       └─ 8 Storage slots
     │           └─ 9 Juice pass
```

Phases 5/6/7/8 are independent of each other once Phase 4 is in. Ship them in
the order above for the cleanest player narrative ("the pet follows me →
needs care → starts being useful → grows more useful → world feels alive"),
but any of them can slip without blocking the others.
