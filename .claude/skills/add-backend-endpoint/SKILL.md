---
name: add-backend-endpoint
description: >-
  Use when adding or changing a Flask API route or database model in the
  backend. Covers the SQLAlchemy model, the in-app migration runner, the route,
  and the Godot-side HTTPRequest call.
paths: backend/**
---

# Adding a backend endpoint

The whole backend is `backend/app.py` — one Flask file with the models, routes,
and migration runner. There is **no Alembic**.

## Steps

1. **Schema changes** (only if you need new storage):
   - **New table** → add a SQLAlchemy model class. Follow `PlayerItem` etc.; for
     per-character data, foreign-key to `players.username` via a
     `player_username` column.
   - **New column on an existing table** → add it to the model **and** append an
     idempotent `ALTER TABLE` to `_run_migrations()`, guarded by a probe
     `SELECT`. `_run_migrations()` runs on every `init_db()`.

2. **Add the route:**
   ```python
   @app.route('/api/<noun>/<verb>', methods=['POST'])
   def my_endpoint():
       content = request.json
       if not content or not content.get('username'):
           return jsonify({"error": "username required"}), 400
       # ... do the work ...
       return jsonify({"status": "success"}), 200
   ```
   POST is the convention for almost everything, reads included.

3. **Character-scoped writes** — take the per-player lock like `save_player`
   does (`lock = get_player_lock(username)`), and prefer **smart-sync** (diff
   incoming vs. existing rows by key, then insert/update/delete) over a blind
   replace.

4. **Call it from Godot.** Add a method in
   `scripts/Networking/network_manager.gd` that POSTs to
   `http://localhost:5000/api/...` with an `HTTPRequest`.

5. **Apply it.** `docker-compose restart api` (migrations run on startup); if
   `requirements.txt` changed, rebuild the image.

6. **Test.** Hit the endpoint, and check `docker-compose logs api` for errors.

## Conventions

- Error responses are `jsonify({"error": "..."}), <4xx/5xx>`.
- Wrap DB writes in `try/except` with `db.session.rollback()` on failure.
- Never store a plaintext password — use `werkzeug.security`'s
  `generate_password_hash` / `check_password_hash`.
