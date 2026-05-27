# Game design principles — cited in the GDD

These are the principles the GDD draws on. **Cite them by name** when they
apply — it tells the reader you've thought about the design at the level the
section claims to address. Don't quote definitions back at the reader; refer
to the principle the way a designer would in conversation.

## Table of contents

- [Core loops & nested timescales](#core-loops--nested-timescales)
- [MDA framework](#mda-framework)
- [Bartle's player types](#bartles-player-types)
- [Flow state & challenge calibration](#flow-state--challenge-calibration)
- [Juice & game feel](#juice--game-feel)
- [Compulsion loops (intrinsic vs extrinsic)](#compulsion-loops-intrinsic-vs-extrinsic)
- [Onboarding pyramid (teach–test–validate)](#onboarding-pyramid-teachtestvalidate)
- [Risk / reward & meaningful choice](#risk--reward--meaningful-choice)
- [Pacing & difficulty curve](#pacing--difficulty-curve)
- [Player agency vs designer authorship](#player-agency-vs-designer-authorship)
- [Read-write balance (multiplayer specific)](#read-write-balance-multiplayer-specific)

---

## Core loops & nested timescales

The most important diagram in any GDD. The **30-second loop** is the
moment-to-moment activity: spot → engage → resolve → reward → repeat. The
**session loop** is what brings the player back tonight (5–45 minutes). The
**meta loop** is what brings them back next week (hours/days).

Loops nest: every session is a string of 30-second loops with a deliberate
shape (rising tension to a peak, then resolution). Every week of play is a
string of sessions building toward a meta goal (a new tier of gear, a new
class, a new region).

**A game with a strong 30-second loop and weak meta loop sells one weekend.
A game with a strong meta loop and weak 30-second loop never gets to the
meta because no one finishes the tutorial.** Both matter.

When you cite this, name the loop being violated or supported. "This change
strengthens the session loop (more reasons to return to town) at the cost of
the 30-second loop (interrupts combat with a quest popup)."

## MDA framework

Mechanics → Dynamics → Aesthetics (Hunicke, LeBlanc, Zubek). A canonical
model for how design intent becomes player experience:

- **Mechanics** are the rules. (E.g. "attacks have a 5-frame windup.")
- **Dynamics** are the patterns that emerge in play. (E.g. "players bait
  enemy attacks because the windup is readable.")
- **Aesthetics** are what the player *feels*. (E.g. "combat feels like a
  fencing match — controlled, deliberate.")

**Designers think in M; players experience A.** The chain is causal — change
a mechanic and you change the aesthetic, sometimes in non-obvious ways.

When you cite MDA, do it forwards (here's a mechanic, here's the dynamic it
produces, here's the aesthetic) or backwards (we want this aesthetic, here's
the dynamic that produces it, here's the mechanic that produces the
dynamic). Don't skip levels.

## Bartle's player types

A four-quadrant typology of MMO players (Bartle, 1996):

- **Achievers** — chase mastery, completion, rank. ("100% the map.")
- **Explorers** — chase discovery, knowledge, hidden mechanics. ("What's
  past that fog?")
- **Socializers** — chase relationships, conversation, status within the
  group. ("Who's online?")
- **Killers** — chase impact on other players, dominance, competition.
  ("Beat someone who tried to beat me.")

No game appeals equally to all four; that's fine. The trap is *unconsciously*
appealing to only one. A GDD that names which types it's designed for —
and which it *isn't* — is honest with itself.

For this project: bots-as-population (Erenshor pattern) is a load-bearing
choice for socializers and explorers — the world feels populated even if
your three friends aren't online. State that connection explicitly.

## Flow state & challenge calibration

Csíkszentmihályi's flow channel: challenge tracking with skill produces
flow; challenge above skill produces anxiety; challenge below skill produces
boredom.

```
challenge ^
          |   anxiety
          |  /
          | /  FLOW
          |/  /
          |  /
          | /   boredom
          |/_________________> skill
```

For an RPG, skill grows on two axes simultaneously: **player skill**
(reflexes, pattern recognition) and **character skill** (levels, gear,
abilities). The challenge curve needs to track *both* — boredom shows up
when character power outpaces player ability *too fast*; frustration shows
up when challenge ramps before character power.

When you cite flow, name *which* axis is mistuned and what would correct it.

## Juice & game feel

"Juice" (Swink, 2008; Petri Purho) is everything that exaggerates feedback
without changing the rules: screen shake, hitstop, particles, sound
layering, number popping, animation overshoot. It's the difference between
"the hit registered" and "the hit *landed*."

Juice is the cheapest way to take an OK game to a memorable one. It costs
hours, not weeks. A GDD that doesn't mention juice anywhere is implicitly
deferring it; deferring juice indefinitely produces a game that *works* and
*doesn't feel like anything*.

For each major feedback moment (hit, crit, level-up, death), name the
juice budget — even if the budget is "a screen shake and a number pop."
Naming it forces you to actually do it.

## Compulsion loops (intrinsic vs extrinsic)

A compulsion loop is the structural reason a player keeps playing past the
point of conscious decision. They split into:

- **Intrinsic** — the activity itself is rewarding (mastering combat;
  exploring a beautiful map).
- **Extrinsic** — the activity earns a reward outside itself (XP, gold,
  loot, achievements, social status).

Both work. Both can be over-leveraged. **A game leaning entirely on
extrinsic loops is a slot machine** — eventually the player notices and
quits with a bad taste. A game leaning entirely on intrinsic loops can
struggle to retain players who don't fall in love with the moment-to-moment
within their first session.

For an RPG, the healthy ratio is *intrinsic core loop* + *extrinsic
session/meta layering*. The 30-second loop should be intrinsically fun;
levels, loot, and unlocks are the extrinsic scaffold that frames it.

When you cite compulsion loops, name which kind and whether the design is
leaning on it healthily or compensating for a weak intrinsic core.

## Onboarding pyramid (teach–test–validate)

The first 10 minutes are the most important 10 minutes of the game.
Anything you ask the player to know later must be taught here in the
teach–test–validate pattern:

1. **Teach** — present the mechanic in isolation, with the rest of the
   game paused or simplified. (Movement, then nothing else.)
2. **Test** — give the player a low-stakes situation that requires the
   mechanic. (Walk to the door; nothing can hurt you.)
3. **Validate** — give the player a stakes-bearing situation that
   confirms they own the mechanic. (A small fight where movement matters.)

Mechanics that aren't *teach*-ed get *discovered* — and discovery is
exciting for explorers, frustrating for everyone else. Design which
mechanics get which treatment deliberately.

## Risk / reward & meaningful choice

A choice is meaningful when each option has a real upside AND a real
downside, the player can predict (roughly) what they'll get, and the
outcome matters going forward.

The opposite — a choice with one objectively better option, or a choice
whose outcome doesn't matter — is **fake choice**. Players notice fake
choices and lose trust in the design.

Common fake choices in RPGs: "pick your starting weapon" when one is
straight-up better; "spend stat points" when there's a known optimal
build; "join faction A or B" when the storyline is identical.

A GDD that lists choices should mark each as **meaningful** or **fake**.
Fake choices aren't always bad (they can be flavour), but pretending a
fake choice is meaningful is dishonest with the player.

## Pacing & difficulty curve

The difficulty curve should rise faster than the player's competence so
the player keeps feeling growth, but not so fast they hit a wall. A
curve that flattens (level 30–50 feels the same as 20–30) signals to the
player "you've seen everything; quit when you're ready". A curve that
spikes (a sudden tier of enemy 5 levels harder than the last) signals
"go grind for two hours before continuing the story."

For this project: [enemy-level-balance] memory documents the cascade —
EnemyData.monster_level affects six stat curves AND the combat formula's
hit-chance and damage modifier. Small gaps compound. Anchor mob levels
to the *lowest* player level that will fight them; don't tune for the
average.

## Player agency vs designer authorship

Every design choice trades **player agency** (the player decides) against
**designer authorship** (the designer decides). Total agency produces
Minecraft; total authorship produces a film.

RPGs sit in the middle and the position matters. A GDD should name the
position: "We want the player to author their build (high agency on
progression) and the designer to author the story (low agency on
narrative)." When the boundary blurs — "the player can choose between
three story endings" — the GDD should name it as a deliberate hybrid,
not an accidental one.

## Read-write balance (multiplayer specific)

In a multiplayer game, *what other players do* enters every player's
experience. The balance question is: how much can other players **write**
to my experience versus how much can I **read** from theirs?

- High write, low read: PvP — others affect me directly, I see them
  little.
- Low write, high read: parallel-play MMOs — others are around, but
  largely cosmetic.
- High write, high read: co-op with shared objectives.
- Low write, low read: single-player with friend list.

The [project_topology_steam_lobby] direction (Steam-lobby co-op) is a
**high write, high read** position. Pets and bots adjust the local
balance: a bot in your party is a *medium write, medium read* presence
that fills the social slot without requiring a human.

When you cite this, name the read/write level the system is targeting and
whether it's serving the social pillar.
