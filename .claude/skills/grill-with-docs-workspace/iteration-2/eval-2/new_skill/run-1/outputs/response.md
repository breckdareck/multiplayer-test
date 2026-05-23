Before I poke at the edges, I have to surface a head-on collision with the core invariant in `CLAUDE.md`, because every downstream question depends on how you resolve it.

## The contradiction

The root `CLAUDE.md` opens with: *"The rule that governs everything: the server owns all critical state. Clients send intent via RPCs; the server validates it, mutates state, and broadcasts the authoritative result back. Never mutate health, stats, inventory, drops, abilities, or progression on a client and assume it sticks — it will be overwritten."*

Your plan asks the client to do exactly the listed forbidden things while the server is gone:

- **Fight enemies** → mutate enemy HP and player HP on the client
- **Gain XP** → mutate progression on the client
- **Pick up items** → mutate inventory and decide drops on the client

Then "sync back" on reconnect — which is the part the rule explicitly says will be overwritten. There is no merge protocol in the codebase today; `SaveManager` is server-only (`scripts/Managers/save_manager.gd:46-48` bails out immediately if `not _is_server()`), and all damage/drop logic lives behind `if not multiplayer.is_server(): return` guards.

So this isn't "offline mode with some edge cases." It's a second, parallel game simulation that competes with the authoritative one. That's a much bigger build than it sounds, and it's the thing I want to grill first — *before* the smaller mechanical questions.

## The one question I want to start with

**What is the actual user problem you're solving?** Because the answer changes which design is even legal in this repo. I see three very different shapes hiding under "offline mode," and I want to pin yours down before we go further:

1. **"My Wi-Fi blips for 5 seconds and I get booted to the login screen — that's annoying."**
   → This is a *reconnection / session-resume* feature. Server keeps the character alive for N seconds after a disconnect; the client reconnects to the same session and resyncs from the authoritative state. **No client-side simulation, no merge.** Compatible with the invariant. Probably 1–2 weeks of work.

2. **"I want to play this game on a plane with no internet."**
   → This is a *single-player mode*, which in this codebase means **the client hosts its own server** (Godot already supports this via `MultiplayerManager`). The "server" is local, authority still lives in one place, and there's no merge problem because there's no remote server involved during play. Characters would need to be flagged offline-only or you accept that offline progress doesn't touch the canonical Postgres character. Different feature, but legal.

3. **"I want true offline-with-sync — keep my normal online character progressing locally and reconcile later."**
   → This is the one your message literally describes, and it is **fundamentally incompatible with server authority** as currently architected. To make it work you'd need: a deterministic client-side simulation of every system (combat, drops, XP, enemies, buffs, abilities) that the server can re-validate; a conflict-resolution policy for every mutable field; a tamper-resistance story (because a client that can mint XP offline is a client that can mint XP, full stop); and a save-format that can represent "tentative offline deltas." That's a months-long rewrite of the authority model, not a feature.

**My recommendation:** unless you've got a specific reason for shape (3) — and I'd want to hear it — you almost certainly want shape (1), possibly with shape (2) as a separate "single-player practice mode" feature later. (1) is the one that actually delivers what most players mean by "my connection dropped and I lost progress."

Which of those three are you actually after? Or is it a fourth thing I haven't named?
