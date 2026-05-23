Happy to grill this. A guild system touches almost every load-bearing part of this codebase — persistence, server authority, chat, the component model, cross-channel routing — so I want to push on the spots where I think the plan is currently waving its hands. Answer whatever feels useful; I'll keep digging from there.

## 1. Where do guilds live, and who owns the state?

The rule in this repo is "server owns all critical state." Guilds clearly qualify (XP pool, bank, membership). So:

- Is a guild a runtime object on the host process (like `PartyManager._parties`), a persistent record in PostgreSQL, or both?
- Parties today are pure runtime: created on the host, dropped when the host dies. A guild has to outlive *every* server restart and *every* channel switch. That means a Postgres-backed `Guild` model + `GuildMember` table is non-negotiable. Have you thought through which fields are authoritative DB state vs. cached in a `GuildManager` autoload on the server?
- Channels: this game uses `ChannelManager` to swap ports. If two players are on different channels (different server processes), are they in "the same guild" or not? If yes, the guild data can't live in one host's memory — the backend has to be the source of truth and every channel has to query/subscribe to it.

## 2. "Shared XP pool that all members contribute kills to" — define this precisely

This is the phrase I'm most suspicious of. A few questions to pin it down:

- When a player kills an enemy, does the player still get personal XP, *and* the guild gets a copy? Or is some fraction siphoned off the player into the pool?
- What does the pool *do*? Is it spent on something (guild perks, guild levels, unlocks)? Or is it purely a leaderboard score? If it's just a score, "pool" is the wrong word — it implies a withdrawable resource. Which is it?
- Damage attribution: kills in this game go to whoever lands the killing blow (or to a party, depending on how `bot_brain.gd` / combat resolves it — worth checking). If a non-guild party member lands the kill, does the guild get credit? What about solo kills by a guild member who's also in a non-guild party?
- Bots. `BotManager` spawns bots with negative peer IDs and no account. Can a bot be in a guild? If not, what happens when a bot lands the killing blow on a tagged mob — does the guildmate who tagged it still get credit?

## 3. Guild bank — this is the scariest part

Item duplication via a shared inventory is one of the classic MMO bugs. In this codebase the danger is real because items are stored slim (`item_path` + `quantity` + `variant` JSONB), so any code path that copies an item without atomically deleting the source can dupe it. Specific things I want you to answer:

- Is the bank a Postgres table (`GuildBankItem`?), keyed by guild_id, mirroring `PlayerItem`'s schema? It probably has to be.
- Deposit / withdraw flow: does it go through `SaveManager` (debounced!) or is it a synchronous backend call like `TradeManager` does? Debounced is *wrong* here — two players hitting the bank in the same second cannot have their writes coalesced.
- Concurrency: `backend/CLAUDE.md` notes that `/api/player/save` takes a per-player lock. A bank op touches *two* records (the player and the guild bank). You need a deterministic lock-acquisition order or you'll deadlock. Have you thought about that?
- What's the atomic unit? "Withdraw stack of 50 potions, but only 30 fit in my inventory" — does the partial withdraw commit, or does the whole op fail? Trades in this repo (`trade_manager.gd`) do an atomic swap; the bank probably should too.
- Variant items: a `+7 sword` is a unique `PlayerItem` row with its own `variant` JSONB. Deposit must move that *row*, not just decrement a count. How are you representing variant items in the bank?
- Permissions: who can withdraw what? "Leader only" is simple but unfun; per-rank limits ("officers can pull rares") add a lot of design surface. Pick a side now or you'll be retrofitting a rank system later.

## 4. Membership lifecycle — every edge case bites

- Cap of 30: where is that enforced? Both the backend route (last line of defense) and the client UI? Just backend is fine — but the client needs to know to show a friendly error.
- Invite flow: party invites go peer-to-peer through `PartyManager`. Guild invites can't, because the invitee might be offline. Does an invite persist in the DB until they log in?
- What happens when the leader logs out / disconnects? Party leadership in this repo gets transferred on disconnect (worth confirming in `party_manager.gd`). For a guild that's persistent, "leader" needs an heir rule — auto-promote oldest officer? Or does the guild just sit leaderless?
- What happens when the leader deletes their character? Guild dissolves? Auto-transfer?
- Kicking yourself out — does the leader have to disband first, or can they leave and auto-promote?
- Disband: do bank items get returned, mailed (no mail system!), or vaporized? "Vaporized" is the honest MVP answer but you should be saying it out loud.

## 5. Guild chat channel — how does it integrate?

- `ChatManager` exists and already handles slash commands. Does guild chat get a new channel type (`Channels.GUILD`) alongside whatever's there now, or a `/g` slash command, or both?
- This is the one feature that *must* cross server channels. Two guildmates on different ports need to see each other's chat. That means guild chat can't be a pure RPC broadcast — it needs to round-trip through the backend (or through some cross-channel pub/sub the codebase doesn't have yet). What's the plan?
- Offline messages — do you want a guild MOTD that shows on login? That's a one-row addition, but worth deciding before the schema is set.

## 6. Leaderboard "across the server"

- "The server" — singular? This game has channels. Is the leaderboard global (all channels) or per-channel? Global is the only thing that makes intuitive sense, which means it's a backend query, not a Godot-side accumulation.
- How fresh? Every guild XP gain hits the DB immediately? Or do you batch (like `SaveManager` debounces)? A leaderboard updating in real-time on every mob kill across hundreds of players is a write storm — but a 30-second cache is invisible to users.
- How big is the leaderboard? Top 100? Paginated? "All guilds" gets ugly fast.

## 7. The component-vs-manager question

Players are component-based (`Health`, `Stats`, `Inventory` under the player node). Guilds are clearly not a player component — they're cross-player state. So this lives in a new `GuildManager` autoload, mirroring `PartyManager` / `TradeManager`. Sound right? Do you also need a tiny `GuildMembership` component on the player for "what's my guild id?" cached state, or do you just look it up on `GuildManager` every time?

## 8. The MVP cut

If I had to ship this in a week, I'd cut: bank, leaderboard, and guild chat. That leaves: create / invite / kick / leave / display roster / track aggregate XP. Even that is a lot. Which of the six features in your plan is the one you would NOT ship if forced to cut one? Your answer tells me what's actually load-bearing for the experience you want.

---

Pick whichever of these you want to swing at first. My instinct is that **#3 (bank concurrency + variant items)** and **#2 (what "XP pool" actually means)** are the two that will reshape the design most if you nail them down now — everything else is mostly schema and UI work.