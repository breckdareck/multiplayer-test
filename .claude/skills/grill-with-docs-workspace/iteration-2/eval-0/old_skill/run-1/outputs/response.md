Happy to grill. Before I poke at the feature itself, I need to nail down one term, because if we get this wrong everything downstream gets the wrong shape.

You used **"guild chat channel."** In this codebase **"channel"** is already a loaded word — `ChannelManager` switches ENet **server ports** to move players between instances of the world. That is almost certainly *not* what you mean. You probably mean a third thing: a **chat scope** filter inside `ChatManager` (alongside the existing all-map broadcast), where messages tagged `guild` only fan out to peers whose player record has the same `guild_id`.

My recommendation: drop the word "channel" from the design entirely and call it **guild chat scope** (or just "guild chat"). Implementation-wise it would be a new branch inside `ChatManager.send_chat_message` — `/g <text>` → `rpc_id(1, ...)` → server looks up sender's guild and broadcasts via `call_remote` to only those peer IDs. Mechanically it parallels the existing `/trade` and `/bot` slash-command dispatch in `ChatManager.gd`, not anything in `ChannelManager`.

Does that match what you had in mind, or were you actually thinking of something port-switched / instance-scoped that I'm flattening too aggressively?

(Once we settle this I'll move on to the next thing on my list, which is **where a guild lives in the persistence split** — Postgres rows next to the character record, or `SaveManager` JSON blob, because they have very different multi-character and concurrency stories. But one at a time.)
