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
