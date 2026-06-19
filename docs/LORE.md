# Emberwilds — World Bible

> *Rekindle the wilds.*

A cozy-but-dangerous co-op RPG. The catastrophe is generations behind us; the
present is a hopeful frontier age — warm hearth-towns at the edge of wild,
ember-touched lands, and the adventurers who venture out to push them back.

> **How to read this doc.** The first half is the *world* — premise, history,
> the Weave, embers, the people. The second half is the *gazetteer and
> bestiary* — every region and creature the game actually contains, in
> level order, with the in-world reason it's there. Everything in the
> gazetteer is grounded in real maps (`scenes/Levels/`), enemies
> (`resources/Enemies/`), and quests (`resources/Quests/`). When you add
> content, extend the matching section so the fiction and the build stay in
> sync.

---

## The premise, in one breath

Long ago the **Weave** — the lattice that held all magic — **shattered**. Its
power didn't vanish; it scattered across the land as **embers**: glowing,
elemental shards of broken magic. That night is remembered as **the Emberfall**
(scholars call it the Sundering). The old kingdoms broke with the Weave. Raw
embers warped the beasts of the deep woods into monsters, and the wilds swallowed
the roads.

Generations passed. The survivors did what people do — they **rebuilt**. They
raised **Hearths**: small, warm frontier towns ringed by ember-lanterns that keep
the monsters at bay. And they discovered something the old world never needed: an
ember can't be wielded by a bare hand, but **bound into a weapon, it can be
channelled**. A sword drinks an ember of stone; a staff, a shard of frost. Master
the weapon and you deepen the bond.

So the wilds aren't only a threat — they're the harvest. Out past the lantern-light
lie embers to gather, ruins to delve, and monsters to fell. That's where the
**Wilders** come in: you, and the party you run with.

---

## A short history

There is no single chronicle of the old world — it broke too thoroughly, and the
people who'd have written it down died in the Emberfall. What the Hearths keep is
an oral history, four ages deep.

- **The Woven Age** *(before)* — magic was everywhere and casual, drawn straight
  from the Weave the way you'd draw water from a well. Kingdoms rose on it. Bare
  hands shaped fire. Nobody bound embers into weapons because nobody had to;
  there were no embers, only the seamless Weave.

- **The Emberfall** *(the night it broke)* — the Weave shattered. Why is the
  oldest argument in the world: some say it was overdrawn, some say a single
  reaching hand tore it, some say it was simply too beautiful to last. The power
  it held fell to earth as embers, thickest where the Weave's knot had been — a
  place now called the **Sundered Heart**. Magic stopped answering bare hands.
  Beasts caught in the ember-rain warped overnight. The roads went dark.

- **The Long Dark** *(the generations after)* — survivors huddled, fought,
  starved, and slowly learned the one trick that kept them alive: an ember bound
  into steel or wood could be *channelled* — controlled, aimed, lived with. The
  first lanterns were lit. The first Hearths held through a winter, then another.

- **The Rekindling** *(now)* — the present, a hopeful frontier age. The Hearths
  are no longer just surviving; they're *pushing out*. New Wilders take up the
  weapon-bound trade, the lantern-line creeps further into the wilds every season,
  and for the first time in living memory people argue not about whether they'll
  last the winter but about what to *do* with the world they've reclaimed —
  including the oldest, most dangerous question of all: whether the Weave should
  be mended.

---

## The Weave

The Weave was the lattice that held all magic in a single, living order. When it
broke, three things were left behind, and the whole world runs on them:

- **Embers** — the Weave's scattered power, frozen into elemental shards. The
  world's mana and its loot, its danger and its harvest, all at once.
- **The wound** — the Weave didn't merely vanish; it *tore*, and the tear is
  still open at the Sundered Heart. Raw, un-shaped magic still seeps from it. The
  closer you stand to the wound, the stranger the world gets (see *The bestiary
  arc*, below).
- **The question** — *can it be mended, and should it?* A re-woven Weave might
  mean the return of the Woven Age: easy magic, no monsters, the lanterns
  unneeded. Or it might mean a second Emberfall, because nobody actually knows
  how the first one happened. The Hearths are genuinely split. **One man already
  tried** — and what he became is the reason the question is dangerous (see *The
  Eternal Warlord*).

> **The wound is widening — slowly.** This is the game's long horizon, not a
> doom clock. The astral creatures at the Weave's Edge are newer than the
> beast-knights, which are newer than the warped woodland animals. The frontier
> is winning the daily fight and losing the century-long one. That tension —
> *the heartbeat is hopeful, the horizon is grave* — is the whole tone.

---

## Embers, elements, and attunement

An ember is a shard of broken Weave, and it carries an **element** — the *kind*
of magic it froze out of. You cannot hold one in a bare hand and do anything but
burn it. Bound into a weapon, it becomes an **attunement**: a controllable
channel you deepen through **mastery** (your bond with the ember growing through
use).

Crucially, **the kind of ember a weapon can hold is part of the weapon itself.**
The disciplines are not interchangeable vessels — each binding-art settles a
different element, and only one art can hold the volatile ones:

| Discipline | Ember-kind it binds | Why, in the world |
|---|---|---|
| **Sword** | **Earth / Stone** | Heavy steel takes a *grounded* ember — stable, immovable, the most forgiving bond. The first weapon-art the Long Dark figured out. |
| **Bow** | **Wind** | A loosed arrow rides a wind-ember; range and precision are the wind's gifts. |
| **Dagger** | **Shadow** | The subtlest, most slippery ember — it hides its bearer as readily as it cuts. |
| **Staff** | **Fire / Ice / Lightning** + **Arcane** | Wood lattice and crystal is the *only* binding that can hold a *volatile* ember — and the only one that can **swap** which it holds, mid-fight. This is why a staff has elemental **stances** and the martial weapons don't. |

The three "raw" embers — **fire, ice, lightning** — never settled. They're the
Weave's power still half-loose, and they'll gutter out or burst in anything but a
staff's arcane lattice. **Arcane** itself is the staff's native, un-elemented
state: raw Weave-stuff, the closest any Wilder gets to touching the Weave
directly. It is not a coincidence that mages are the ones who theorize about
mending it.

> **In game.** The staff's `StaffElementComponent` cycles `FIRE / ICE /
> LIGHTNING`; martial weapons carry a fixed elemental character expressed
> through their abilities (sword *Earthsplitter*, bow *Wind Rider / Sky
> Volley*, dagger *Shadowstep / Death Mark*). New elements should be appended
> to the staff cycle or expressed as a new discipline's identity — never
> retro-fitted as a free-floating system, which would dissolve the
> weapon-driven identity the whole game is built on.

---

## Sigils

If embers are raw power, **sigils** are *instructions*. They're crystallised
Weave-fragments — tiny pieces of the old lattice's pattern that survived the
Sundering still carrying a scrap of meaning. Slotted into an attuned weapon, a
sigil **reshapes what the ember does**: a flame that bleeds instead of burns, an
arrow that finds a second target, a frost that heals the one who lands it.

Sigils are the in-world face of the game's **cards / runes / ability-upgrade
trees**. A Wilder's *identity* is their weapon (the ember they bound); their
*build* is the sigils they've slotted to shape it. Two swordsmen carrying the
same earth-ember can fight nothing alike, because they read different
instructions into it.

---

## The disciplines, as crafts

A Wilder is defined by what they **wield**, not by birth or class. The four
binding-arts are trades you take up:

- **The Sword** — the grounded art. Stand, hold, break the line. The
  Long Dark's first answer to the dark, and still the one taught to frightened
  new Wilders first.
- **The Bow** — the wind art. Reach out and end it before it reaches you. The
  art of scouts, hunters, and anyone who'd rather the monster never closed the
  distance.
- **The Dagger** — the shadow art. Be elsewhere; be behind. Distrusted in polite
  Hearth company and quietly indispensable in the deep ruins.
- **The Staff** — the arcane art. Juggle the embers nobody else can hold. The
  closest thing the frontier has to the old Woven-Age mages — and the loudest
  voices in the argument about the Weave.

**Two attunements at once.** A working Wilder carries *two* weapons (the dual-kit).
Versatility is survival in the wilds; the deep ruins punish anyone who can only
do one thing. Carrying two bound embers at once is itself a mark of a real
Wilder — most Hearthfolk never bind even one.

---

## The people

- **Wilders** *(the players)* — anyone who attunes to a weapon and walks past the
  lantern-line. Not a chosen bloodline, not a class you're born into — a **trade
  you take up**. Farmers, smiths, runaways, retired soldiers. You're defined by
  what you choose to **wield**.
- **The Embersworn** — Wilders who've gone deep, bound their embers well, and
  carved a real legend. A loose fellowship more than an order: no oaths, no
  ranks, just the people who've been furthest out and come back. They garrison
  the forward hearth, keep the **vigil** at the Weave's Edge, and are the closest
  thing the frontier has to authority on the dangerous questions.
- **Hearthfolk** — the people who keep the towns alive: the smith who reforges
  your blade, the cartographer mapping the next valley, the kids who want to be
  Wilders someday. The frontier is **lived-in and crowded** — you're one
  adventurer among many. *(In game: this is the bots-as-population design — a
  world that feels inhabited.)*

---

## The world, a ring closing on the wound

The frontier is not a line — it is a **ring closing on the wound**. The Sundered
Heart lies at the dead centre of the blighted interior; the reclaimed country
circles it. On the **outer ring** sit the lit, garrisoned **Hearths**, joined by
gentle low wilds you can walk between — the safe, settled rim. From that rim the
land **spokes inward**: every step toward the centre is older, stranger, and more
dangerous, until the spokes meet at **Emberwatch**, the last great hold. Below
Emberwatch the ground opens into **the Core** — the deep descent to the Sundered
Heart itself, where the Weave still bleeds and the Warlord is sealed.

- **The Emberwilds** — the untamed, ember-saturated country between the rim and the
  Core: bramble downs, old battlefields, bandit bluffs, drowned mines, sunken
  vaults. Beautiful, overgrown, and full of teeth. Embers pool thicker the deeper
  you go; so do the monsters they warped. *(The game's namesake.)*
- **The Hearths (Hearthholds)** — frontier towns rebuilt on the bones of the old
  world. Safe hubs: a market, a forge, a board of work, neighbours who remember
  your name. Ringed by **ember-lanterns** — captured embers that ward off the wild.
  Several stand on the outer rim; one, **Emberwatch**, holds the centre.
- **The Ruins** — what the Emberfall left behind: shattered castles, collapsed
  vaults, the workshops of the people who first learned to bind magic into steel.
  Their lost arts are still down there, on the inward spokes.
- **The Core & the Sundered Heart** — beneath Emberwatch the spokes give way to the
  Core, a deepening descent to the place the Weave's knot used to be. The centre of
  everything, and the most dangerous ground in the world.

### The Hearths

Five lit towns ring and pierce the frontier:

- **Lantern's Rest** — a **home Hearth** on the outer rim (the starting hub). The
  smallest and safest of the lit towns, far enough back that a child can grow up
  here. Where new Wilders take up their first weapon and walk out the lantern-line
  for the first time. *(In game: `lanterns_rest`, the default map.)*
- **Wickmoor** — an outer-rim Hearth on the lantern-moors, a short walk around the
  ring from Lantern's Rest. A working town of trappers and peat-cutters. *(In game:
  `wickmoor`.)*
- **Hollowmere** — an outer-rim Hearth beside a still, ember-lit mere. Quiet and
  older, a little superstitious about the deep. *(In game: `hollowmere`.)*
- **Emberwatch** — the **central Hearth** (~level 48), held by the Embersworn where
  the inward spokes meet. The last great hold before the Core; you resupply here
  before the descent. Soldierly, harder than the rim towns — a watch-post that
  happens to have a forge. *(In game: `emberwatch`, the hub at the centre of the
  ring; the Core opens below it.)*
- **Ashvigil** — the **vigil-camp** at the bottom of the Core (~level 96), the last
  lit ground before the Sundered Heart. Barely a town — a ring of lanterns, a
  quest-board, and the Embersworn who keep the final watch. From here Wilders breach
  the Warlord. *(In game: `ashvigil`, the staging hub for the Warlord instance.)*

> The old "two standing Hearths" line is retired: the lantern-line has crept far
> enough to ring the wilds. More Hearths can still join the rim without contradiction.

---

## The bestiary arc — why the monsters change

This is the most important piece of deep lore, because the game *shows* it
without ever saying it: **the closer you get to the Sundered Heart, the less the
monsters look like warped animals and the more they look like something the
Weave is deliberately building.** The broken Weave, bleeding from its wound, is
blindly trying to reweave itself — and with no pattern left to follow, it
reaches into the nearest living things and *organizes* them. The arc runs in
three stages, and the game's difficulty curve walks you straight up it:

1. **Warped** *(the near wilds)* — ordinary woodland animals, lightly
   ember-touched. A bunny that bites, a slime that's just barely alive, a boar
   that won't stop charging. The Weave's reach is faint this far out; it only
   *agitates*. These are the monsters generations of Hearthfolk have always
   known.

2. **Organized** *(the mid frontier and the Keep)* — animals warped *enough to
   use tools, cast, and soldier*. Foxes that fence, hares that sling spells,
   wolves that pack-hunt with intent — and past the Keep, full **beast-knights**:
   armored, disciplined, near-human martial creatures wearing the *shape* of the
   old world's soldiers. The Weave isn't just agitating anymore; it's imposing a
   pattern. (Tellingly, that pattern is *the Warlord's old garrison* — see below.)

3. **Transfigured** *(the Ember-Scar and the Weave's Edge)* — creatures so
   saturated with raw ember they've stopped being animals at all. Boars that
   *burn*, slimes that "drink raw arcana and shimmer," hares gone **celestial**
   and slimes gone **astral** — cosmic, half-unreal things forming right at the
   lip of the wound. This is the Weave's reweaving at its furthest and least
   restrained: it has run out of animal to work with and started spinning matter
   straight out of leaked magic.

The **Eternal Warlord** is the end of this arc — the single most complete thing
the broken Weave ever made, except *he* wasn't made by the wound. He walked in.

---

## Gazetteer — the wheel, rim to core

Each region below is a real map. Levels are the band of warped life that dwells
there (from `EnemyData.monster_level`); the creatures are the actual enemies
placed in the world. The world reads **outer rim → inward spokes → Emberwatch →
the Core → the Sundered Heart at the centre**.

### The outer ring — the settled rim (Lv 1–15)

A walkable loop of lit Hearths and the gentle low wilds between them.

| Region *(map)* | Level | What it is | What dwells there |
|---|---|---|---|
| **Lantern's Rest** *(`lanterns_rest`)* | — | Home Hearth. Market, forge, work-board, the first lantern-line. | *(safe)* |
| **Wickmoor** *(`wickmoor`)* | — | Outer-rim Hearth of the lantern-moors; trappers and peat-cutters. | *(safe)* |
| **Hollowmere** *(`hollowmere`)* | — | Outer-rim Hearth beside a still ember-mere; quiet and old. | *(safe)* |
| **The Near-Wilds** *(`near_wilds`)* | 1–9 | The first step past the lanterns; gentle, grassy, deceptively calm. | Bunny, Slime, Bird, Boar, Deer, Fox |
| **Slime Meadow** *(`meadow_path`)* | 1–9 | A boggy pocket off the meadows where the slimes breed thick. | Slime, Bunny *(the "slime threat" quests)* |
| **Tinderfields** *(`tinderfields`)* | 6–12 | Dry rim-grass where loose embers catch like tinder; herds graze the haze. | Boar, Deer, Slime |
| **Ember-Meadows** *(`ember_meadows`)* | 1–13 | Rolling country where embers first start to glitter in the grass. | Boar, Deer, Fox, Goblin Warrior |
| **Brackenway** *(`brackenway`)* | 10–15 | Bracken-choked bluffs along the rim's edge, where the first goblins scout. | Fox, Boar, Goblin Warrior |

### The spokes — climbing inward (Lv 18–46)

Three routes off the rim toward the centre; here the warping turns *clever* — the first tool-using beasts.

| Region *(map)* | Level | What it is | What dwells there |
|---|---|---|---|
| **The Ruins** *(`ruins`)* | 18–28 | Shattered old-world stonework; the first sign of the people who fell. Goblins nest in the rubble. | Goblin Warrior, Goblin, Cave Goblin, Tusk Brute |
| **Windmill Terraces** *(`three_terraces`)* | 18–28 | Stepped farmland gone feral around three broken windmills. | Goblin, Cave Goblin |
| **The Old Battlefield** *(`old_battlefield`)* | 20–28 | Where an old-world host fell in the Emberfall; the ground still bristles with rusted iron. | Tusk Brute, Cave Goblin, Goblin |
| **Mirefen** *(`mirefen`)* | 22–30 | A sunken bog-cavern off the spoke — lightless, dripping, goblin-haunted. | Cave Goblin, Stone Slime, Tusk Brute |
| **Bandit Bluffs** *(`bandit_bluffs`)* | 28–34 | Ravine-country where bandit-beasts den in the crags and prey on the spoke. | Cat Robber, Fox Swordsman, Tusk Brute |
| **Thornroot Hollow** *(`thornroot`)* | 28–38 | Overgrown sunken hollow where the warping turns clever. | Tusk Brute, Fox Swordsman, Stone Slime, Cat Robber |
| **The Reliquary** *(`the_reliquary`)* | 38–42 | An old-world vault where the first binding-arts were kept; tool-beasts den among the relics. *(Lantern's delve, deepest before Emberwatch.)* | Fox Swordsman, Stone Slime, Wolf Pathfinder |
| **Stonereach** *(`stonereach`)* | 34–42 | Old-world quarry-mesas, worked for binding-stone then abandoned. | Cat Robber, Dust Fox, Wolf Pathfinder |
| **The Dust Warren** *(`dust_warren`)* | 36–44 | A dry burrow-country of bandit-beasts and dust-pale foxes. | Cat Robber, Dust Fox, Wolf Pathfinder, Mithril Hare |
| **Wolfsreach** *(`wolfsreach`)* | 42–46 | Wind-scoured crags past the Warren where the wolf-packs reach deepest. *(Wickmoor overland, deepest before Emberwatch.)* | Wolf Pathfinder, Mithril Hare, War Goblin |
| **The Drowned Mines** *(`mines`)* | 40–48 | Flooded old-world workings, goblin-thick and dark; pathfinder wolves stalk the tunnels. | Wolf Pathfinder, War Goblin, Rabbit Wizard, Deer Druid, Mithril Hare |
| **The Undercroft** *(`the_undercroft`)* | 44–48 | The vaults beneath the mines — deeper, older, where the diggings broke into the dark. *(Hollowmere deep road, deepest before Emberwatch.)* | War Goblin, Wolf Pathfinder, Rabbit Wizard |

### The centre & the Core (Lv 48–100)

The spokes meet at Emberwatch; below it the Core descends to the wound. The bestiary arc runs hardest here: Organized beast-knights give way to Transfigured, half-unreal things as you near the Sundered Heart.

| Region *(map)* | Level | What it is | What dwells there |
|---|---|---|---|
| **Emberwatch** *(`emberwatch`)* | ~48 | Central Hearth. The last great hold where the spokes meet; the Core opens below it. | *(safe)* |
| **The Deep Woods** *(`deep_woods`)* | 52–58 | Old-growth dark where the Warlord's garrison musters before it marches. | Bear Warrior, Dark Bunny, Lion Knight, Adamant Crawler |
| **The Warded Keep** *(`keep`)* | 52–63 | The Warlord's old-world fortress, its wards failing, re-occupied by his beast-knights. **You breach it; you don't rest here.** | Bear Warrior, Panda Warrior, Shadow Fox |
| **The Mustering Fields** *(`mustering_fields`)* | 60–68 | Where the beast-knight host forms up under the Core's red light. | Lion Knight, Panda Warrior, Bear Warrior |
| **The Scorchline** *(`the_scorchline`)* | 66–72 | The burning front where the knights give way to things that simply burn. | Lion Knight, Runed Boar, Fire Slime |
| **The Ember-Scar** *(`emberscar`)* | 68–83 | Where the embers fell thickest — even the boars burn, and the "bloom" spreads. | Runed Boar, Fire Slime, Ember Fox, Wild Boar |
| **The Cinderwaste** *(`cinderwaste`)* | 83–88 | Burnt-out ash-waste; the fire has cooled to glowing cinder, the silence wrong. | Ember Fox, Fire Slime, Runed Boar |
| **The Weave's Edge** *(`weave`)* | 88–93 | The lip of the wound. Creatures here "drink raw arcana and shimmer." | Celestial Hare, Astral Slime |
| **The Unraveling** *(`the_unraveling`)* | 92–96 | Where the Weave comes apart and the world stops holding its shape. | Celestial Hare, Astral Slime |
| **Ashvigil** *(`ashvigil`)* | ~96 | The vigil-camp — last lit ground, a quest-board, and the breach-point for the wound. | *(safe)* |
| **The Sundered Heart** *(`warlord`)* | 100 | Where the Weave tore. Breached as an **instanced** fight (party or solo) from Ashvigil. | **The Eternal Warlord** |

> **Layout is not fixed.** The wheel's *radius* is the level curve (rim low →
> centre high); which map portals to which is tunable (`MapManager.MAP_SCENES` +
> each scene's portals + `tools/rebuild_portals.gd`). If you reshuffle, keep a
> region's band matching the creatures placed in it — the fiction tracks the
> numbers, not the current portal graph.

---

## The Eternal Warlord

> *"He bound a hundred embers and forgot how to die."*

At the Sundered Heart waits the one creature the broken Weave didn't make — a man
who *unmade himself*.

He was an **old-world general**, a soldier of the kingdoms that fell. He survived
the Emberfall, and where everyone else learned to *live with* the broken world,
he refused it. He went to the Heart — to the wound itself — and set out to
**mend the Weave by force**: to bind ember after ember into himself, gathering
the scattered power back into one place, one body, until the lattice might knit
closed again. He was, in the truest sense, **the first Wilder** — the first to
discover that a bound ember could be channelled, and the only one ever to test
how far that could go.

He bound a hundred embers. He did not mend anything.

What he became instead is the most complete thing at the Sundered Heart: a
deathless, hollowed-out monument to over-reach. The embers reknit his wounds
faster than anything can open them — he *forgot how to die*. But there was no
pattern left for a hundred raw embers to follow inside one man, and the same
blind reweaving that turns boars into burning things and slimes into astral ones
turned *him* into a warlord that no longer remembers being a man. His old garrison
still musters in the Keep below, soldiering on out of a habit the Weave wrote
into them.

And he **guards the wound.** *"Whatever the Hearths decide about the Weave, he
will not let you near it."* Read that as grief, not malice: he is the one being
alive who knows exactly what trying to mend the Weave costs, because he paid it,
and he will not let another soul reach the Heart to make his mistake — or, worse,
to succeed where he failed and find out what a re-woven Weave actually does.

**He is the player's mirror.** A Wilder binds *two* embers and deepens the bond
through mastery. He bound a *hundred*. Every point you spend chasing
weapon-power walks a single step down the road that ends at the Sundered Heart.
That rhyme — *your whole build, taken to its monstrous limit* — is the point of
the capstone.

> **In game.** `EternalWarlord` (level 100, `is_boss`), fought at the dead centre
> of the wheel in the `warlord` map ("The Sundered Heart"), **breached as an
> instanced fight (party or solo) from the Ashvigil vigil-camp** — not an
> always-open room, but a sealed wound you queue into. Quest **q_warlord** of the
> same name. Three phases (66% / 33%) and an enrage at 20% — read them as the
> hundred embers in him guttering and flaring as he's worn down.

---

## The ending question

Killing the Warlord doesn't answer the question he died asking — it *opens* it.
With the wound's keeper gone, the Hearths can finally reach the Weave's Edge
freely, and the oldest argument on the frontier stops being theoretical:

- **Mend it,** and maybe the Woven Age returns — easy magic, no monsters, the
  lanterns unneeded. Or maybe it's a second Emberfall, because the only person
  who ever tried is the thing you just had to put down.
- **Leave it,** and keep the world as it is — dangerous, warm, *yours*. The
  frontier you built stays a frontier. The wilds stay worth protecting.

The game's tone says the second answer is the honest one — **the heartbeat is
building a legend in a place worth protecting**, not winning a war that ends the
world's story. But the door is deliberately left open. The Weave is a *horizon*,
not a final boss with a cutscene. The Warlord is the cautionary tale that keeps
the easy answer from looking easy.

---

## Tone

**Hopeful, not grim.** The apocalypse already happened and the world *survived
it*. Days are spent in a warm town with people you know; nights and expeditions
are where the danger lives. Think a frontier that's equal parts campfire and
monster den — cozy at the center, wild at the edges. Stakes can rise (the
widening wound, the deep ruins, the question of the Weave), but the heartbeat of
the game is **building a legend in a place worth protecting.**

The grave notes — the widening wound, the Warlord's grief, the open question —
are *horizon*, not *weather*. They give the cozy frontier something to be cozy
*against*. Never let them flip the day-to-day into despair; the lanterns are
winning the fight that's in front of you.

---

## Naming kit (for in-game text)

- **Embers** — elemental shards of broken magic (the world's "mana"/resource flavor)
- **Element / ember-kind** — fire / ice / lightning / arcane (staff), earth (sword), wind (bow), shadow (dagger)
- **The Emberfall / the Sundering** — the cataclysm
- **The Woven Age / the Long Dark / the Rekindling** — before / after / now
- **Attunement** — binding an ember-kind to a weapon; deepened via **mastery** (the bond)
- **Sigils** — slottable Weave-fragments (cards / runes / ability upgrades)
- **The Weave / the wound** — the broken lattice and the still-open tear at the Heart
- **Wilder / Embersworn** — adventurer / a deep-frontier veteran
- **Hearthfolk** — the townspeople; the living population
- **Hearth / Hearthhold** — safe frontier town (hub). Home: **Lantern's Rest**. Forward: **Emberwatch**.
- **The Emberwilds** — the dangerous lands (and the game's name)
- **The Sundered Heart** — where the Weave tore; the end of the road
- **The Eternal Warlord** — the first, failed mender; the capstone

---

## How the world explains the game

| In the game | In the world |
|---|---|
| Your power comes from your **weapon**, not a class | After the Emberfall, magic can only be channelled **through an attuned weapon** |
| **Sword / Bow / Staff / Dagger** disciplines | Four binding-arts, each settling a different ember-kind |
| **Two equipped weapons** (dual-kit) | Carrying two attunements at once — versatility is survival in the wilds |
| **Staff has elemental stances; other weapons don't** | Only the staff's arcane lattice can hold the **volatile** embers (fire/ice/lightning) and swap between them |
| **Weapon mastery** that grows as you fight | Your **bond** with the ember deepening through use |
| **Cards / runes / ability upgrades** that reshape abilities | **Sigils** — crystallised Weave-fragments that re-instruct an ember |
| **Difficulty rises toward one fixed endgame zone** | You're walking *up the bestiary arc* toward the wound the monsters grow out of |
| **Monsters get armored, then cosmic, deeper in** | The broken Weave reweaving itself — warping, then organizing, then transfiguring living things |
| **The level-100 boss** | The **Eternal Warlord** — the first Wilder, who bound a hundred embers trying to mend the Weave |
| **Parties / co-op** | Wilders run the deep wilds **together** — nobody clears a ruin alone |
| **Endless monsters / respawns** | The wilds are still **saturated with raw embers**, and the wound still seeps |
| **Two safe hub towns** | **Lantern's Rest** (home) and **Emberwatch** (forward) — lit, garrisoned, lived-in |
| **A populated, living town** | The **Hearthfolk** and fellow Wilders — the frontier is rebuilt and busy |

---

## Opening blurb (usable on a title / intro screen)

> *The Weave broke, and the world caught fire.*
> *Generations on, the embers still burn in the wilds — and we've learned to
> wield them. Light your lantern. Take up your steel. The frontier won't tame
> itself.*
