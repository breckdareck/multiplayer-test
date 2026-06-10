# Bot ambient population: speech routing and identity store

The design goal (per the Erenshor "SimPlayer" pattern) is bots-as-ambient-
population: a small Steam-lobby co-op session should feel like a busy server.
The bots already persist, grind, travel, party, and gear up; what they lack is
*presence* — speech, recognizable identity, seeded levels, companion commands,
and trade consent. Two of those decisions are architectural seams worth
recording.

## Decision 1 — bot speech is server-initiated through ChatManager

Bots have negative peer ids and no client, so a bot can never be the *remote
sender* of a chat RPC — `ChatManager._broadcast_message` attributes the sender
via `get_remote_sender_id()`, which a bot cannot trigger. Bot speech therefore
enters through a **server-side ChatManager entry point** (e.g.
`bot_say(bot_id, text)`) that injects the sender id explicitly and then reuses
the normal authority broadcast (`_show_chat_message`) so every real peer
renders the feed line + overhead bubble on its copy of the bot's character
node. The existing `notify_peer` guard (`is_bot → return`) is unchanged —
sends *to* bots remain impossible.

Spam control lives in ChatManager as a **speech budget**: a server-wide
minimum gap between bot lines plus a per-bot cooldown; personality chattiness
scales the per-bot roll. Lines are event-keyed (level-up, rare drop, death,
greeting, party events) and always *true* — no decorative chatter divorced
from what the bot actually did.

## Decision 2 — bot identity persists in a server-side roster file, not Postgres

Bot *progress* (level, gear, gold, build) already persists through the normal
`SaveManager` → backend `Player` row pipeline (`is_bot = true`, shared
`__bots__` account). Bot *identity* (personality archetype, line-pool key,
chattiness, the one-time random roll for `/bot spawn random` bots) does NOT go
to Postgres. It lives in a **server-side roster file** written by
`BotManager`, alongside `bot_config.json` (authored entries in config remain
the source of truth for named bots; the roster persists rolled identities so
random bots stay recognizable across sessions).

### Considered options

- **New JSONB column on `Player`** — single store, but a schema migration,
  dead weight on every human row, and identity is config-shaped (archetype
  keys referencing line pools) rather than save-shaped.
- **Config-only, no persistence** — zero storage, but random bots re-roll
  every boot, defeating "I recognize Bob from last session."
- **Roster file (chosen)** — no schema change, works in local-save/offline
  mode, and fits the Steam-lobby topology where the host machine carries the
  world. Cost: bot state split across two stores (progress in the save row,
  identity in the roster); acceptable because the two never need a joined
  query.

## Consequences

- New cold-start bots are **seeded** at a level inside their home map's
  `map_difficulty` band via the same path `/bot set_level` uses (EXP + mastery
  together), so the ability/attribute-point reconcile invariant holds; they
  also get band-appropriate gold so the existing restock/equip logic gears
  them on their first town trip. No new gear-generation code.
- Companion commands (`follow` / `stay` / `free`) are party-leader-only,
  dispatched through the existing `/bot` command path, and set a mode flag on
  `BotBrain` — they do not introduce trinity roles (the party model stays
  no-tank/no-healer, roles emergent from weapon identity).
- Bot trades gain consent only for **non-party** initiators (valued via
  `BotEquipmentLogic.score_item()`); party members keep the free give/take
  window (deliberate — it doubles as a mule/testing convenience).
- No new autoload, no new component, no client-side authority: bots stay
  fully server-side and clients only render broadcasts.
