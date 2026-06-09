# Backend (Flask + PostgreSQL)

The persistence layer for accounts and characters. Godot talks to it over HTTP
through `scripts/Networking/network_manager.gd`.

## Files

- `app.py` — **the entire backend**: the Flask app, every SQLAlchemy model, every
  route, and the migration runner. One file, by design.
- `requirements.txt`, `Dockerfile`, `.env.example`
- Runs via `docker-compose up -d` (see the root `CLAUDE.md`).

## Models

`Account`, `Player`, `PlayerItem`, `PlayerEquipment`, `PlayerAbility`,
`PlayerHotbar`, `PlayerBuff`, `PlayerQuest`.

- **`Player.username` is the character name**, and is globally unique. The child
  tables foreign-key to it by `player_username` (not the integer `id`), now with
  `ON DELETE CASCADE` so deleting a player row cleans up its children at the DB
  level instead of erroring. `Player.account_id` is indexed
  (`idx_players_account_id`) for the character-select query.
- **`Player.is_bot`** is a boolean discriminator. Bot characters share the player
  save shape, so they live in `players` with `is_bot = true` (single-table
  inheritance) rather than a separate table. Backfilled from the `__bots__`
  account; stamped on the bot-row-creation path in `save_player`.
- `PlayerItem` / `PlayerEquipment` store items **slim**: `item_path` (the canonical
  `.tres`), `item_id`, `quantity`, and a `variant` JSONB blob for per-instance rolls
  (random stats, crafting). Static fields are re-derived in Godot from the `.tres`.
- `Player.last_map` defaults to `"town"` — new characters spawn at the Maple
  Town hub on first login. Existing rows from earlier defaults may need a one-off
  `UPDATE players SET last_map='town' WHERE last_map='game';` after pulling.
- **Quest progress lives in the `player_quests` table** — one row per
  `(player, quest_id)` with `status` (`'active'`/`'completed'`), `progress` JSONB
  (objective counters for active quests), and a `tracked` flag. The per-player
  `onboarded` flag is a boolean column on `players`. On the wire it's still the
  `{active, completed, tracked, onboarded}` shape `QuestManager` produces/consumes:
  `load_player` rebuilds it from the rows + flag, `save_player` destructures it
  back (Godot unchanged). Quests have their own `"quests"` save category, so a
  quest-progress tick saves only quests — not a full `"all"` payload. (Was a
  single `players.quests` blob before the persistence-cleanup PR; relocated so a
  growing completed-quest list isn't rewritten on every tick.)
- `Player.pets` is a single **JSONB blob** holding the pet roster:
  `{roster: [<pet records>], summoned: [<uuids>]}`. Same wholesale-only pattern
  as quests. On the wire, the save/load endpoints flatten this into two
  top-level keys (`pets`, `summoned_pet_ids`) to match Godot's existing save
  shape — see `multiplayer_controller_v2.get_save_data` and `PetManager.load_pets`.
- `Player.weapon_mastery` (PR 2) is a **JSONB blob** keyed by lowercase
  discipline name: `{sword: {level, xp}, bow: {level, xp}, staff: {level, xp},
  dagger: {level, xp}}`. NULL on legacy rows; Godot's `WeaponMasteryComponent`
  initializes missing keys to `{level: 0, xp: 0}` on load.
- `Player.ability_points_per_discipline` (PR 4) is a **JSONB blob** keyed by
  the same lowercase discipline names, values are int pools:
  `{sword: 12, bow: 3, staff: 0, dagger: 0}`. The legacy `Player.ability_points`
  int column is still populated as `sum(values)` for one release as a
  fallback safety net but should not be read for spending decisions — the
  authoritative pools live in the JSONB column. NULL on legacy rows; the
  save handler distributes the legacy int evenly into all four pools (with
  remainder going to the player's starting discipline) on first save.
- `Player.attribute_points` (PR 7) is a **JSONB blob** of the player's MANUALLY
  allocated attribute points, keyed by `StatType` int → spent points
  (`{"0": STR, "2": DEX, "1": INT, "3": LUCK, "15": CON}`). Travels at the top
  level of the save payload (alongside `level` / `character_type`). NULL/empty on
  legacy rows → the Godot side default-allocates to the starting weapon
  discipline's ratio on load, so existing characters keep their stats until they
  respec (StatsComponent.reconcile_attribute_points). Idempotent ALTER adds it on
  startup.
- **Purchased ability upgrades (PR 6) live on `PlayerAbility.upgrades`** — a
  per-ability JSONB array of `upgrade_id` strings (e.g.
  `["cc_t1_razor_edge", "cc_t3_razor_wind"]`), co-located with the ability+level
  row they belong to. NULL = no upgrades. On the wire they still travel as the
  `abilities.learned_ability_upgrades` map keyed by `ability_id`: `load_player`
  rebuilds that map from the per-ability columns and `save_player` destructures
  it back onto each `PlayerAbility` row, so Godot's `AbilityComponent` is
  unchanged. (Was a single `players.learned_ability_upgrades` blob before the
  persistence-cleanup PR — relocated so an ability's level and upgrades share one
  row, cascade-clean and uniqueness-enforced.)

## Conventions

- **Route shape**: `@app.route('/api/...', methods=['POST'])`, read `request.json`,
  return `jsonify(...), <status>`. POST is used for almost everything, reads included.
- **No Alembic.** Schema changes go in `_run_migrations()` in `app.py` — an
  idempotent list of `ALTER TABLE` statements, each guarded by a probe `SELECT`. Add
  new columns there; it runs on every `init_db()`. `_check_schema_drift()` runs
  right after and logs a `SCHEMA_DRIFT` warning when model columns and live DB
  columns diverge — catches a stale process running an older schema than `app.py`.
- **Save concurrency**: `/api/player/save` takes a per-player lock
  (`get_player_lock`) so two saves for one character cannot interleave.
- **Dev server runs threaded** (`app.run(threaded=True)`): the single-threaded
  default serialized every request, so the game's heavy save traffic blocked the
  portal map-change flush (`await SaveManager.flush_save`) and starved the
  `/health` probe (container went unhealthy). Threaded handling fixes that —
  Flask-SQLAlchemy's session is thread-local, and the per-player save lock above
  still serializes one character's saves for integrity.
- **Smart-sync**: the save endpoint diffs incoming vs. existing rows by key and
  insert/update/deletes — it does not blindly replace. All five child tables go
  through one `_sync_child_rows(model, existing_by_key, desired_by_key)` helper;
  build a `{key: {column: value}}` desired-dict and call it. Match that when
  extending it.
- **Loader strategy — `selectinload`, NEVER `joinedload`, for the player's child
  collections.** `joinedload` across multiple one-to-many collections is a
  CARTESIAN PRODUCT (items × abilities × equipment × hotbar × buffs) — it exploded
  into tens of thousands of materialized rows as the weapon-overhaul ability
  rosters grew, pegging the DB and slowing every load/spawn/save. `load_player`
  uses `selectinload` (one indexed IN-query per collection). `save_player` eager-
  loads NOTHING — each category block (`if 'inventory'/'abilities'/'buffs' in
  data`) lazy-loads only the collection it touches, so a frequent partial
  ("stats") save does ZERO child queries.
- **Character-select list** (`get_characters`): each entry carries the card fields
  the select screen renders — `level`, `character_class`, `max_health`, `max_mana`,
  `monies`, `attribute_points`, `weapon_mastery`, and `weapons` (the equipped
  `WEAPON` / `SECONDARY_WEAPON` rows as slim `{item_path}` refs; the client resolves
  them to `ItemData` locally). `NetworkManager.get_characters()`'s offline local-save
  branch mirrors this exact shape — change both together.
- **Bots**: bot characters have no account, so they are all owned by one shared
  `__bots__` account (`account_id` is `NOT NULL`). `save_player` accepts an `is_bot`
  flag to create a bot's `Player` row on the fly and stamp the `is_bot` column.

## Adding an endpoint

Use the `add-backend-endpoint` skill — it covers the model, the migration, the
route, and the Godot-side `HTTPRequest` call.

## Security note

`app.py` has a stale `# TODO: Hash passwords!` comment on the `password_hash`
column, but registration **does** hash via `werkzeug.security.generate_password_hash`
and login verifies with `check_password_hash`. Keep all new auth code on those two
functions; never store or compare a plaintext password.
