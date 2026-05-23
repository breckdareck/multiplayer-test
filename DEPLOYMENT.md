# Deploying the backend

The game runs a Flask + PostgreSQL backend (the `api` and `db` Docker services
in `docker-compose.yml`) that holds accounts, characters, items, equipment,
abilities, hotbar configs, buffs, and quest progress. Out of the box it runs on
`http://localhost:5000` for solo development. To let friends outside your
network play with persistent characters, you need to host that backend
somewhere reachable from the public internet.

This doc covers the canonical recipe (a $5 VPS) plus the in-game flow for
pointing the client at a remote backend.

---

## 1. Host the backend on a VPS

Any provider that lets you run Docker works (DigitalOcean, Hetzner, Linode,
AWS Lightsail, …). The recipe below is generic. Pick a small instance
(1 vCPU / 1 GB RAM is plenty) running Ubuntu 22.04+.

### SSH in and install Docker

```bash
ssh root@YOUR_SERVER_IP
apt-get update
apt-get install -y docker.io docker-compose git
systemctl enable --now docker
```

### Pull and start the stack

```bash
cd /opt
git clone https://github.com/YOUR_USERNAME/multiplayer-test.git
cd multiplayer-test
docker-compose up -d --build
docker-compose ps    # api + db + adminer should all be Up
```

### Open the API port

Make sure port **5000** is reachable from the public internet — open it in your
provider's firewall / security group. Port **8080** (Adminer DB UI) and
**5432** (Postgres) should stay closed; only the game client needs the API.

### Verify

```bash
curl http://YOUR_SERVER_IP:5000/health
# → {"status": "ok"}
```

---

## 2. Point the game at the remote backend

The Godot client reads its API URL from `UserConfig`, which falls back to a
`BACKEND_API_URL` environment variable, and finally to `http://127.0.0.1:5000/api`.

### In-game (per-player)

1. Launch the game, reach **LoginScreen**.
2. Click **Backend Settings ▶** to expand the panel.
3. Either press the **Cloud** preset and edit the URL, or just paste your URL
   directly into the API URL field: `http://YOUR_SERVER_IP:5000/api`
4. Click **Apply**. The status label flips to green when the `/health` probe
   succeeds.

The setting is persisted in `user://user_config.cfg` — players only do this
once.

### From the command line / launchers

```bash
BACKEND_API_URL=http://YOUR_SERVER_IP:5000/api godot
```

### Permanent default for everyone

Edit `scripts/Managers/user_config.gd`:

```gdscript
const DEFAULT_API_URL = "http://YOUR_SERVER_IP:5000/api"
```

This is the value new installs start with, before any user override.

---

## 3. Routine ops

| Action | Command |
|---|---|
| View API logs | `docker-compose logs -f api` |
| Restart API only | `docker-compose restart api` |
| Pull new code & rebuild | `git pull && docker-compose up -d --build api` |
| Stop everything (keep data) | `docker-compose stop` |
| Database UI | Open `http://YOUR_SERVER_IP:8080` from an SSH tunnel — **do not** expose 8080 publicly |

### Backups

PostgreSQL data lives in a Docker volume — nuke the volume and you've lost
every character. A dead-simple nightly dump:

```bash
mkdir -p /opt/backups
cat > /opt/backup_db.sh <<'EOF'
#!/bin/bash
docker exec multiplayer-test-db-1 pg_dump -U postgres gamedb \
  | gzip > /opt/backups/gamedb_$(date +%Y%m%d_%H%M%S).sql.gz
EOF
chmod +x /opt/backup_db.sh

# Run nightly at 02:00 (crontab -e)
0 2 * * * /opt/backup_db.sh
```

---

## 4. Things this guide deliberately doesn't cover

- **HTTPS / domain names.** You're sending plaintext over port 5000. For a
  hobby project among friends this is fine; for anything public, put the API
  behind a reverse proxy (Caddy, Nginx, or Traefik) with Let's Encrypt.
- **Auth tokens / rate limiting.** The API trusts whoever calls it — anyone
  with the URL can register an account. Add JWT and rate limiting before
  exposing it broadly.
- **The game server itself.** The Flask backend is just for accounts and saves.
  Players still listen-host the actual game session (ENet) on their own
  machine; see the root [README](README.md) for the host/join flow.

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Backend Settings status stuck on "checking…" | Port 5000 isn't reachable from the client — firewall or wrong IP |
| "Connection refused" on login | `docker-compose ps` shows `api` is down, or the DB never came up healthy |
| Characters create but don't persist between sessions | API saves silently failing — `docker-compose logs api` will show the trace |
| Schema mismatch errors after pulling new code | `_run_migrations()` in `backend/app.py` runs on `init_db()` — restart the api container to apply |
