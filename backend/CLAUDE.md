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
`PlayerHotbar`, `PlayerBuff`.

- **`Player.username` is the character name**, and is globally unique. The child
  tables foreign-key to it by `player_username` — not by the integer `id`.
- `PlayerItem` / `PlayerEquipment` store items **slim**: `item_path` (the canonical
  `.tres`), `item_id`, `quantity`, and a `variant` JSONB blob for per-instance rolls
  (random stats, crafting). Static fields are re-derived in Godot from the `.tres`.
- `Player.last_map` defaults to `"town"` — new characters spawn at the Maple
  Town hub on first login. Existing rows from earlier defaults may need a one-off
  `UPDATE players SET last_map='town' WHERE last_map='game';` after pulling.
- `Player.quests` is a single **JSONB blob** holding the whole `QuestManager.save_quests()`
  payload: `{active, completed, onboarded}`. Quests are only ever read/written
  wholesale per character, so there's no separate relational table for them.
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
- `Player.learned_ability_upgrades` (PR 6) is a **JSONB blob** keyed by
  `ability_id`, values are arrays of purchased `upgrade_id` strings:
  `{"<ability_id>": ["cc_t1_razor_edge", "cc_t3_razor_wind"]}`. Wholesale —
  Godot's `AbilityComponent` owns the shape (`save_abilities` writes the whole
  map under the `abilities.learned_ability_upgrades` key; `load_abilities`
  replaces it). NULL on legacy rows → empty dict → no upgrades. Like the other
  ability columns it rides inside the `data['abilities']` save blob but is
  destructured into its own column (the blob is NOT stored verbatim).

## Conventions

- **Route shape**: `@app.route('/api/...', methods=['POST'])`, read `request.json`,
  return `jsonify(...), <status>`. POST is used for almost everything, reads included.
- **No Alembic.** Schema changes go in `_run_migrations()` in `app.py` — an
  idempotent list of `ALTER TABLE` statements, each guarded by a probe `SELECT`. Add
  new columns there; it runs on every `init_db()`.
- **Save concurrency**: `/api/player/save` takes a per-player lock
  (`get_player_lock`) so two saves for one character cannot interleave.
- **Smart-sync**: the save endpoint diffs incoming vs. existing rows by slot and
  insert/update/deletes — it does not blindly replace. Match that when extending it.
- **Bots**: bot characters have no account, so they are all owned by one shared
  `__bots__` account (`account_id` is `NOT NULL`). `save_player` accepts an `is_bot`
  flag to create a bot's `Player` row on the fly.

## Adding an endpoint

Use the `add-backend-endpoint` skill — it covers the model, the migration, the
route, and the Godot-side `HTTPRequest` call.

## Security note

`app.py` has a stale `# TODO: Hash passwords!` comment on the `password_hash`
column, but registration **does** hash via `werkzeug.security.generate_password_hash`
and login verifies with `check_password_hash`. Keep all new auth code on those two
functions; never store or compare a plaintext password.
