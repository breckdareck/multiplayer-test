Happy to grill this. Before I start poking, two quick things to get the frame right — then I'll ask you one question at a time and walk down the tree.

**Frame-check 1: this is a new persistent social entity, not content.** A guild isn't an ability/buff/item/enemy/map/endpoint, so none of the existing skills (`add-ability`, `add-item`, etc.) cover it. The closest existing pattern in the repo is `scripts/Managers/party_manager.gd` + `PartyData` — server-authoritative, in-memory, lives behind a manager autoload. A guild is basically "a party that outlives the session, persists across logout, and has a bank." Worth reading that file before we go deep; I'll lean on it as the reference shape.

**Frame-check 2: the word "guild" is doing a lot of work in your plan, and so are several others.** Before we grill mechanics I want to nail terminology, because the server-authority story changes dramatically based on what you actually mean. Specifically:

- **"shared XP pool that all members contribute kills to"** — is this guild XP (a brand-new currency that levels the *guild* and unlocks guild perks), or is it the *players'* personal XP being taxed/shared (members earn less, guild earns the difference)? These are very different systems with very different exploit surfaces. My recommendation: **guild XP is its own separate currency**, accrued as a side-effect of member kills, never substituting for personal XP. Cleaner authority model, no "my XP got stolen by the guild" feel-bad, and it makes the leaderboard meaningful.

- **"guild chat channel"** — `channel` in this codebase already means *a port-switched server instance* (`ChannelManager`). Your "guild chat channel" is a chat scope/room, not a network channel. I'd call it the **guild chat scope** (or just "guild chat"), implemented as a new routing branch in `ChatManager.gd` alongside the existing `/trade`, `/quest`, `/bot` commands — probably `/g <message>`. Confirm?

- **"guild bank"** — is this one shared inventory grid, or per-member deposit slots, or tabs with per-rank permissions? "Bank" implies the first; MMO experience says you'll regret not having the third. Recommendation: **single shared inventory for v1, with a deposit/withdraw log**, and design the schema so tabs can be added later without a save migration.

- **"leaderboard of guild XP across the server"** — "across the server" means across all channels/maps (one game world), right? Not cross-shard? Recommendation: yes, single global leaderboard, served by a Flask endpoint that reads from Postgres, because guild XP needs to persist anyway.

If you push back on any of those, we adjust before going further.

---

**My first real question** (the one with the biggest downstream consequences):

**Where does a guild's authoritative state live — in the running game server's memory (like `PartyManager` holds parties), or in Postgres (like character records)?**

My recommendation: **Postgres is the source of truth; the game server holds a hot cache** of the guilds whose members are currently online. Reasons:

1. Guilds must survive a server restart. Parties don't; characters do — and characters live in Postgres. Guilds belong with characters.
2. Guild XP is monotonically increasing and shared across logged-in *and* logged-out members. Holding it only in RAM means a crash erases real player progress.
3. The leaderboard query is trivially a `SELECT ... ORDER BY guild_xp DESC LIMIT N` against Postgres — no aggregation across in-memory managers.
4. The bank — items the player doesn't currently have on their character — *has* to be in Postgres or you've invented a way to lose items on crash.

The tradeoff: every guild mutation (XP gain, deposit, withdraw, kick) becomes a Flask round-trip. We'd want to debounce guild XP writes the same way `SaveManager` debounces player saves, and decide whether bank ops are write-through (slower, safer) or write-behind (faster, can drop items on crash).

So: **Postgres-authoritative with a server-side cache, or pure in-memory like `PartyManager`?** And if Postgres-authoritative, are bank ops write-through or write-behind?
