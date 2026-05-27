# Backend migration notes

Schema changes that are auto-applied at backend startup (via
`_run_migrations()` in `app.py`) and the equivalent one-line SQL for manual
application to a deployed database that needs the new column added in place.

`_run_migrations()` is idempotent: each migration probes for the column with
a `SELECT col FROM table LIMIT 1` before issuing the `ALTER TABLE`. Fresh
databases hit `db.create_all()` first and skip the migration entirely.

## PR 2 — Weapon mastery (`weapon_mastery` column on `players`)

Adds the `weapon_mastery` column for PR 2 (Weapon Mastery Infrastructure) of
the weapon-identity-overhaul initiative.

```sql
ALTER TABLE players ADD COLUMN weapon_mastery JSONB;
```

- Existing rows will have `NULL` for the column. The load endpoint serves
  `NULL` as an empty dict on the wire; Godot's `WeaponMasteryComponent`
  treats an empty dict as "no progress yet" and populates four zero-state
  tier-1 disciplines on `_ensure_default_disciplines`. No character loses
  progress and no data migration is required.
- Reversible: `ALTER TABLE players DROP COLUMN weapon_mastery;`

Shape of the column once a character has mastery progress:

```json
{
  "sword":  {"level": 3, "xp": 120},
  "bow":    {"level": 0, "xp": 0},
  "staff":  {"level": 0, "xp": 0},
  "dagger": {"level": 1, "xp": 40}
}
```

`level` is the cumulative mastery level (capped at 20 in code); `xp` is the
running progress toward the next level (resets to 0 on level-up). The
backend treats the blob as opaque — Godot owns the shape.
