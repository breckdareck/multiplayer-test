# Pet system architecture — owner-driven intent + server authorization, per-character JSON persistence, book-gated capabilities

## Context

MapleStory-style pets are a new entity type — neither a Player (owner-bound, has a client) nor a Bot (server-side AI with a negative peer ID, no client). They follow an owner and trigger five capabilities: item pickup, coin pickup, HP consume, MP consume, buff cast. Each capability already has a server-validated RPC pathway used by the owning player; the architectural question was how a pet hooks into those pathways without growing a parallel server AI subsystem.

## Decision

### 1. Entity model — owner client drives intent; server authorizes via existing RPCs

The pet is a synced cosmetic puppet under `map_root`, spawned by a new `PetManager` autoload. The pet node's multiplayer authority is set to the owner's peer id via `set_multiplayer_authority(owner_peer_id)`, so its `MultiplayerSynchronizer`-driven position is owner-client-authoritative. The owner's client runs the auto-loot and auto-pot trigger loops and sends the existing player-action RPCs (or thin wrappers like `PetManager.request_autoloot_server`). The server validates everything just as it does for a manual player action — including a leash clamp on reported pet position to defeat client position-spoofing.

**Considered alternatives:**
- *Server-side pet brain (BotManager-shaped):* duplicates the validation that already exists for player-triggered consume/pickup/cast. Rejected — duplicate code paths, more server CPU for no authority gain.
- *Pure client cosmetic with all state local:* violates server authority on hunger (clients could refuse to tick); breaks "reload from another device" because hunger and inventory live nowhere durable.

### 2. Persistence — per-character via SaveManager → Postgres `Player.pets` JSONB

The save payload carries two top-level keys (`pets`, `summoned_pet_ids`), the
same shape `multiplayer_controller_v2.get_save_data` emits and `PetManager.load_pets`
consumes. The backend bundles them into a single `pets` JSONB column on the
`players` row: `{roster: [...], summoned: [...]}`. Same wholesale read/write
pattern as `Player.quests`. Acquisition is via a "Pet Egg" consumable that
hatches into a pet record carrying `learned_commands`, `pet_inventory` (2
autopot reference slots + 3 command slots), `autopot_config`,
`active_buff_ability_id`, `hunger`, and `name`. The format reserves an
unlimited `roster` and `summoned` so raising the v1 cap of 1 active pet to N
later requires no schema migration.

When the backend is offline (`NetworkManager.use_local_save = true`) SaveManager
falls through to its existing per-character JSON file fallback, which carries
the same flat keys — no separate code path for pets.

**Considered alternatives:**
- *Account-level Postgres table:* heavyweight — new table, new endpoints, new
  sync on character switch. Trade-off accepted: pets do not follow across alts
  on the same account.
- *Pet as inventory item with metadata:* couples pet evolution to the item
  save format; conceptually fuzzy ("is a pet a thing you own or a thing you
  carry?"); fights against a Pet management UI separate from inventory.

### 3. Capability gating — every pet command requires a skill book

A freshly-hatched pet does nothing automatically. The owner must obtain and consume "Pet * Command" books (Auto Pot, Item Pouch, Meso Magnet, Buff) to teach the pet each capability. The buff book unlocks an empty slot that accepts *any* of the player's owned buff-type abilities — not one book per buff.

**Considered alternative:**
- *Built-in capabilities (e.g., auto-loot ON by default):* less MapleStory-authentic; pets become an instant superpower instead of a progression curve. Explicitly rejected mid-grill in favor of parity.

### 4. Auto-buff is the only deliberate deviation from "owner drives intent"

Auto-loot and auto-pot are driven by the owner client because their triggers are client-observable (drop appears in range; HP crosses a threshold). Auto-buff's trigger is purely time-based, which is server-observable. Running the autobuff timer on the server avoids a pointless RPC round-trip for a server-knowable event. The cooldown source is the ability's own cooldown (not a pet-specific cadence), under the design assumption that no buff has both a short duration and a short cooldown.

## Consequences

- **Bots cannot own pets** in this design (no client to run the trigger loops for auto-loot / auto-pot). Acceptable — bots are dev/QA tooling, not players. If pet ownership for bots becomes a requirement later, autoloot/autopot trigger loops would need a server-side analog gated on `BotManager.is_bot(owner_id)`.
- **The pet entity carries no `Health`, `Stats`, `Combat`, `Ability`, or `Buff` component.** Pets cannot take damage, cast through `AbilityComponent`, or hold buffs of their own. This breaks the convention from `scripts/Components/CLAUDE.md` that character behavior slots into existing components — pets are deliberately not characters.
- **Auto-buff routes through the owner's `AbilityComponent.use_ability`** — same code path a player-driven cast hits. This deducts the owner's MP, enforces the ability's cooldown, applies the buff via `BuffComponent`, and triggers the ability's normal client visuals. Pets do not bypass MP; if the owner is out of MP the pet's cast silently fails until MP regenerates. (Earlier design considered bypassing AbilityComponent for MapleStory parity, but routing through the canonical pathway means every cooldown/visual/balance change to a buff ability automatically applies to pet casts too.)
- **Two new resource subclasses** must be authored before any pet content can be created via the `add-item` skill: `PetFoodData extends ConsumableData` and `PetSkillBookData extends ConsumableData`. The skill will need a minor update to recognize them.
- **Save migration risk: low.** The new `players.pets` JSONB column is added by an idempotent `_run_migrations()` entry in `backend/app.py`; rows without the key default to `NULL`, which the load path treats as an empty roster.
- **Pet position spoofing** is defended by a server-side leash-radius clamp before any pet-position range check. The pet can never validly be farther from the owner than `pet_leash_radius`.

Decided in the grill session of 2026-05-24.
