# 3. Unified tabbed game window (Character / Abilities / Pet)

Date: 2026-05-30
Status: Proposed

## Context

Player-facing progression UI is currently spread across several independent
movable windows, each its own scene + script and its own hotkey:

- `equipment_window` (gear slots, incl. the Pet tab added by the pet system)
- inventory (item grid)
- `stats_window` (derived stats + attribute allocation)
- `abilities_window` (the new v2 skill tree)
- pet management

This fragments the experience: the player opens/positions several windows to do
related things (equip an item, check the stat it changed, spend an attribute
point), and each window is a separate input-lock/drag/sync surface. It also
multiplies maintenance — every window re-implements open/close, dragging, the
panel chrome, and remote-client sync hooks.

## Decision

Build **one unified game window** with **top tabs**, replacing the separate
windows with tab *pages* inside it:

- **Character** tab — Equipment + Inventory + Stats together on one page (the
  things you bounce between while gearing). Equip a piece → see the stat move →
  spend an attribute point, without window juggling.
- **Abilities** tab — the v2 skill tree (`skill_tree_canvas` + the right detail
  panel), unchanged in behavior, hosted as a page.
- **Pet** — its own tab (leaning this way for room), OR folded into a section of
  the Character page. **Open question, decided during implementation** once the
  Character page's space budget is clear.

One window = one open/close + input affordance, one drag handler, one chrome,
and a single place to route remote-client sync. Tabs swap pages; the window
keeps the established non-modal behavior (movable, does not lock input — see the
input-lock convention).

### Approach
- Reuse the existing per-area logic (equipment/inventory/stats/ability/pet
  controllers) as embedded tab pages rather than rewriting their behavior;
  the overhaul is primarily **composition + chrome**, not re-implementing each
  system's data flow.
- Preserve every interaction affordance the separate windows had (drag-to-equip,
  drag-to-hotbar, tooltips, attribute spend, respec, etc.).
- Keep server-authority intact: tabs are pure presentation; all mutations still
  go through the existing component RPCs.

## Consequences

- **+** Fewer windows to manage; related actions co-located; one chrome/drag/
  sync surface to maintain.
- **+** A single hotkey opens the hub; tabs (and possibly a key per tab) swap.
- **−** Larger window; the Character page must budget space for three panels
  (drives the Pet tab-vs-embedded question).
- **−** Migration touches several scenes; care needed to carry over all
  affordances (a known past failure mode in UI rewrites).
- Built incrementally on this PR (`feat/unified-game-window`), targeting the
  `feat/weapon-identity-overhaul` integration branch.
