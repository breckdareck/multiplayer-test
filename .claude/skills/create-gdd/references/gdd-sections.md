# GDD section guidance

Per-section guidance for the bundled template. **Read the entry for a section
before you fill it in.** Each entry has the same shape: what the section
answers, what bad looks like (so you can spot it in your own draft), and what
good looks like.

## Table of contents

- [1. Executive summary](#1-executive-summary)
- [2. Design pillars](#2-design-pillars)
- [3. Game overview](#3-game-overview)
- [4. Player experience goals](#4-player-experience-goals)
- [5. Core loops](#5-core-loops)
- [6. Story, setting & world](#6-story-setting--world)
- [7. Characters & classes](#7-characters--classes)
- [8. Combat system](#8-combat-system)
- [9. Progression systems](#9-progression-systems)
- [10. Items, equipment & economy](#10-items-equipment--economy)
- [11. Enemies & AI](#11-enemies--ai)
- [12. Levels, maps & world topology](#12-levels-maps--world-topology)
- [13. Multiplayer & social systems](#13-multiplayer--social-systems)
- [14. Quests & onboarding](#14-quests--onboarding)
- [15. UI & UX](#15-ui--ux)
- [16. Art direction](#16-art-direction)
- [17. Audio design](#17-audio-design)
- [18. Technical architecture](#18-technical-architecture)
- [19. Production roadmap](#19-production-roadmap)
- [20. Risks, open questions & appendix](#20-risks-open-questions--appendix)

---

## 1. Executive summary

**Answers:** What is this game? Who is it for? Why does it deserve to exist?

**Bad:** "An immersive multiplayer RPG experience with engaging combat and
rich progression." This is the failure mode — it could describe ten thousand
games. The reader learns nothing.

**Good:** Names a *specific* fantasy, a *specific* audience, and *specific*
reference games. "MapleStory's side-scrolling class fantasy, but the player's
identity comes from their weapon rather than their class — pick a sword and
you're a different character than if you pick an axe. For lapsed MMO players
who miss the social density of 2007 Maple but want to play with three friends
over a Steam lobby, not a 50-player guild."

**Length:** Two paragraphs max. If you can't pitch it in two paragraphs the
pitch isn't yet pitchable.

## 2. Design pillars

**Answers:** What does every later decision get measured against?

**Pillars are veto-strength.** A feature that violates a pillar doesn't get
cut down; it gets cut. If a pillar can't realistically veto a feature, it
isn't a pillar — it's a wish.

**Bad pillars:** "Fun." "Engaging." "Polished." These can't reject anything.

**Good pillars:** "Server-authoritative without exception" (rejects any
client-side state shortcut). "Weapon is identity, class is implicit"
(rejects any UI that surfaces class as the primary axis). "Bots are
*invisible* — a stranger should think the bot is a real player" (rejects
nameplate styling that flags bots).

3–5 pillars. More and you've made them un-rankable; fewer and you've
under-specified.

## 3. Game overview

**Answers:** The factual shape of the game — genre, platforms, network
model, length, audience.

This is the section to be most factual and least poetic. It's a reference
table for everyone who has to refer back to "wait, what platforms again?"

**Pull from CLAUDE.md** for engine and network model. Don't restate the rule
("server-authoritative"); just state it as a fact.

## 4. Player experience goals

**Answers:** What is the player **feeling** at each timescale?

The three timescales (seconds / minutes / hours) force you to think about
different design layers. A game can be great moment-to-moment and tedious
session-to-session, or compelling long-term and frustrating moment-to-moment.

**Bad:** "Players should feel powerful and accomplished." (Could be any
RPG.) "Players should have fun." (Tautological.)

**Good:** Specific *sensory* and *emotional* descriptions tied to specific
*moments*. "When I land a crit, the screen shakes briefly, the number pops
in red and arcs up, and there's a low 'thunk' — I want the feeling of a bat
hitting a piñata." "When I finish a quest, I should be slightly annoyed
that the next quest is across the map — that small friction is what makes
me notice I've travelled."

## 5. Core loops

**Answers:** What is the player **doing**, over and over, at each scale?

The 30-second loop is the single most important diagram in the document.
If the 30-second loop isn't fun, nothing built on top of it will be.

**Use a Mermaid `flowchart LR`** for each loop. Each box is a player action
or decision; each arrow is what triggers the next.

**Bad:** Skipping the loop diagram. Or drawing it but not annotating what
the player is *thinking* at each beat.

**Good:** Diagram + walkthrough. "At 'Spot enemy' the player is *scanning*
— eyes on threat detection. At 'Engage' they've already picked the
combo (committed). At 'Land hit' is the dopamine beat. At 'Loot' is the
*decision* — keep grinding or break for town?"

The session and meta loops layer the same thinking at longer scales.

## 6. Story, setting & world

**Answers:** Where, when, who, and what mood?

If the game doesn't have story (e.g. it's a sandbox), this section still
covers *setting* and *tone*. Tone is mandatory; story is optional.

**Bad:** Dumping lore. Three paragraphs of "the realm of Aetherius was
formed when the Old Gods…" — no reader wants this, and the game probably
doesn't either.

**Good:** Plot **beats** keyed to player levels. "By lvl 5 the player knows
their starting town's NPC by name. By lvl 30 they've met all four faction
representatives and chosen one." Beats can be skeletal — the discipline is
mapping story to play, not writing fiction.

## 7. Characters & classes

**Answers:** Who is the player, and what choices define them?

For this project specifically: the **art constraint** (4 fixed sprites) is
load-bearing. State it here, then build the section around it. "Class" may
be implicit (under weapon-driven identity) — if so, explain how the section
maps to weapons instead of classes.

Use a **table** for the class/weapon roster. Tables are non-negotiable here
— a wall of prose obscures the contrasts that make classes feel different.

**Bad:** Listing classes with a paragraph of flavour but no functional
contrasts. "The Warrior is a brave hero who fights with valour." The reader
can't compare classes.

**Good:** Table with **stat focus**, **weapons**, **role**, and **what
makes this class feel different** in one sentence. "Mage — INT/LUK, wand
or staff, burst + utility, *feels different because* every cast commits to
a long animation; mages are punished for panicking and rewarded for reading
fights."

## 8. Combat system

**Answers:** What does the player *do* in a fight, and why does it feel
the way it feels?

Combat is usually the most-played section of an RPG. It deserves the most
specific section in the GDD.

**Pull the damage formula from the code** (`CombatComponent.gd`). Don't
guess. The balance simulator addon mirrors the in-game formula — that's
the canonical source.

**Bad:** Hand-waving the formula. "Damage is calculated based on the
player's stats and the enemy's defence." Useless to a designer trying to
tune.

**Good:** The actual formula as a code block. One **worked example** with
real numbers ("A lvl 30 warrior with sword, 50 STR, 80 weapon attack hits
a lvl 28 boar with 20 defence for…"). Then call out the **levers** ("crit
chance compounds with crit damage — be careful tuning both at once").

## 9. Progression systems

**Answers:** How does the player get stronger over time?

For this project, progression is multi-axis: **levels, stat points,
abilities (three-layer), weapon mastery, class advancement**. Each axis
needs its own subsection.

The **three-layer ability model** ([ability-mechanics-shape] memory) is
non-obvious and worth documenting in full: Layer 1 = formula-driven level
numbers (MP/CD/dmg%); Layer 2 = `ActiveBehaviorData.logic_script` custom
behaviour; Layer 3 = `on_*_proc` procs. A reader who doesn't understand all
three layers will mis-balance abilities.

**Bad:** "Players level up, learn abilities, and become more powerful."
(Could be any game.)

**Good:** Each progression axis as its own subsection, with a clear answer
to "what does the player choose, and what does the choice cost?"

## 10. Items, equipment & economy

**Answers:** What does the player *acquire*, *equip*, *use*, *trade*, and
*spend*?

The economy section is where most GDDs get lazy. Faucets and sinks must
balance — name them both. If you can't list three sinks, the economy will
inflate.

**Bad:** Listing item categories without rarity rules or trade rules.
Calling something "the economy" without naming a sink.

**Good:** Items table with **stack**, **tradeable**, **rarity** columns.
Currency section with faucets and sinks explicitly enumerated. If crafting
is in scope, cross-reference [project_crafting_roadmap] memory and note v1
vs. later.

## 11. Enemies & AI

**Answers:** What does the player fight, and how do those fights vary?

**This project has three distinct non-player entity types** (CONTEXT.md):
**Pet**, **Bot**, **Enemy**. They are NOT interchangeable. The combat
section is about Enemies; this section also covers Bots and Pets because
they're part of the play experience.

**Bad:** Conflating Bots and Enemies. Calling a Pet a "companion" or a
Bot an "AI player".

**Good:** Use the CONTEXT.md definitions verbatim. Make the distinction
obvious to the reader: Pets are *owner-bound passive helpers*, Bots are
*server-side AI that drive a player character*, Enemies are *hostile mobs*.

Enemy tier table is mandatory. AI patterns get a state-machine sketch
(idle → aggro → attack → leash) even if it's two sentences.

## 12. Levels, maps & world topology

**Answers:** What is the spatial shape of the world, and how do players
move through it?

This project uses 2D side-scrolling maps connected by portals, with
**channels** (port-switched parallel instances of the same map). Channels
are unusual and need explaining.

**Map roster table** is mandatory. Include level range and *theme* so the
reader can visualise the world at a glance.

## 13. Multiplayer & social systems

**Answers:** What can players *do with* other players?

For this project, the **topology decision** ([project_topology_steam_lobby]
memory) is load-bearing. Steam-lobby co-op is the direction; ENet+Postgres
is dev/test; an official server is a later opt-in. State this up front so
the rest of the section makes sense.

Cover parties, trading, chat, friends, guilds. For each, name the v1 scope
explicitly. "Friends list — v2." Tells the reader what's *not* in the
first slice.

## 14. Quests & onboarding

**Answers:** How does a new player learn the game, and what keeps them
moving after they've learned it?

[quest-system-shape] memory: quests are defined in code,
server-authoritative, level 1→30 guided journey + onboarding. State the
philosophy first, then the types.

**Onboarding** is its own subsection. The first 10 minutes are the most
important 10 minutes of the game — most players who quit, quit there.
Walk through it beat by beat.

## 15. UI & UX

**Answers:** What's on screen at any moment, and how does the player
navigate the windows behind the scenes?

**Screen-flow Mermaid diagram** is mandatory — shows how the player moves
between hub, character select, inventory, abilities, pet window, trade.

Note the [feedback_input_lock_pattern] memory: every in-game overlay MUST
call `InputManager.set_input_locked(true/false)` on open/close. If a
designer adds a new overlay without knowing this rule, movement and
hotkeys leak. State it in the GDD; it's a real design constraint, not just
a code convention.

**Accessibility** is a subsection, not an afterthought. Colorblind palette,
font scaling, rebindable keys, motion sensitivity, subtitles — name each
explicitly even if v1 is "not yet".

## 16. Art direction

**Answers:** What does the game *look* like, and why?

For this project, [project_art_constraint] is the **single most important
sentence in this section**: 4 static sprites, asset packs, no paperdoll,
no budget for more. This isn't a preference — it's a hard constraint that
shapes the entire game.

**Style references must be real games**, ideally with specific screens.
"MapleStory's silhouette legibility" is more useful than "vibrant fantasy
aesthetic". Name what you're stealing.

## 17. Audio design

**Answers:** What does the game *sound* like, and where does sound come
from?

[project_visible_doesnt_gate_audio] memory: hiding a map's render tree
doesn't gate its audio. This is a real audio-design rule for this project
— call it out so future audio decisions don't trip over it.

Per-map music plan, SFX taxonomy (combat / UI / ambient), ambient loops.
Reference `AudioManager`.

## 18. Technical architecture

**Answers:** How is this built? (Compressed view — full picture is in
CLAUDE.md.)

This section is the bridge between design and engineering. Don't restate
CLAUDE.md; **summarise** the parts that affect design:

- Server authority (one paragraph)
- Autoload singletons (table with name + role)
- Component-based characters (one paragraph)
- Data-driven content (one paragraph — call out the auto-load exception
  for enemies)
- Persistence (one paragraph — Postgres for accounts, JSON for in-game)
- Performance targets (table)

**Bad:** Pasting the autoload table from CLAUDE.md verbatim.

**Good:** A one-sentence-per-autoload explanation of what role each plays
*in the player experience* — not just what it does technically.

## 19. Production roadmap

**Answers:** What's built, what's next, what's not in scope?

**Out-of-scope section is mandatory.** What you've decided *not to build*
in v1 is as informative as what you have.

Milestones table with **status** column — "in progress", "planned",
"blocked". Don't be aspirational; reflect actual state.

## 20. Risks, open questions & appendix

**Answers:** What might go wrong, what's still undecided, where do I look
for more?

**Risks table** with likelihood × impact × mitigation. Risks specific to
this project: the 4-sprite art constraint, multiplayer desync edge cases,
the weapon-vs-class tension.

**Open questions** are tagged with `> ⚠ Open question:` callouts
throughout the doc. This section *also* lists them in one place so the
reader can find them.

**Glossary** points to CONTEXT.md — don't duplicate.
