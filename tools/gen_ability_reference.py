#!/usr/bin/env python3
"""
Ability Reference / Balance report renderer.

Reads docs/ability_data_dump.json (produced by tools/dump_ability_data.gd, which
evaluates the real .tres formulas through the game's own code) and renders a
self-contained, styled HTML report at docs/ability_balance_report.html.

For EVERY ability (active + passive) across all four weapon disciplines it shows:
  - per-level Mana / Cooldown / Damage% / Hits / Targets / Cast / status / custom
    values / passive stat bonuses / buff+debuff durations
  - the full 3-tier upgrade tree (T1 / T2 / T3 variants) with point cost,
    variant group (mutex), effect_key and magnitude
  - automatic VERIFY flags: missing tiers, lone T3 variants, zero-magnitude
    effects, flat curves, orphaned upgrade .tres on disk.

Run (after the dump):
  python tools/gen_ability_reference.py
Out:
  docs/ability_balance_report.html
"""

import json, os, re, html, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DUMP = os.path.join(ROOT, "docs", "ability_data_dump.json")
OUT  = os.path.join(ROOT, "docs", "ability_balance_report.html")
SCRIPTS = os.path.join(ROOT, "scripts")
UPGRADE_DIRS = {w: os.path.join(ROOT, "resources", "Abilities", w, "Upgrades")
                for w in ("Sword", "Bow", "Staff", "Dagger")}

# effect_keys consumed CENTRALLY (apply to ANY ability regardless of its own AL):
#   - AbilityComponent (ability.gd) generic dispatch
#   - CombatComponent (combat.gd) per-hit application
GENERIC_KEYS = {
    "cooldown_flat_reduction", "mana_flat_reduction", "conditional_damage_bonus",
    "passive_stat_flat_bonus", "passive_stat_percent_bonus",
    "bonus_damage_mult", "bonus_hits", "bonus_targets", "bonus_lifesteal",
    "channel_time_reduction",
}


def scan_effect_consumers():
    """Map effect_key string -> set of .gd basenames that reference it."""
    consumers = {}
    for p in glob.glob(os.path.join(SCRIPTS, "**", "*.gd"), recursive=True):
        try:
            txt = open(p, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        base = os.path.basename(p)
        for m in re.finditer(r'["\']([a-z][a-z0-9_]+)["\']', txt):
            consumers.setdefault(m.group(1), set()).add(base)
    return consumers


def precondition_noop(effect_key, maxrow):
    """Reason an upgrade is a no-op at MAX LEVEL (the only level it's buyable),
    or '' if fine. Upgrades are gated behind ability max-level (can_purchase_upgrade
    → 'not_maxed'), so the max-level row is the only state that matters."""
    cd = maxrow.get("cooldown", 0)
    mana = maxrow.get("mana", 0)
    cast = maxrow.get("cast", 0)
    if effect_key == "cooldown_flat_reduction" and cd == 0:
        return "cooldown is 0 at max level — CD reduction does nothing"
    if effect_key == "mana_flat_reduction" and mana == 0:
        return "mana is 0 at max level — mana reduction does nothing"
    if effect_key == "channel_time_reduction" and cast == 0:
        return "cast/channel time is 0 at max level — channel-time reduction does nothing"
    return ""


def upgrade_status(effect_key, al_script, consumers):
    """('generic'|'wired'|'dead', reason) for one upgrade on one ability."""
    if not effect_key:
        return ("wired", "")  # pure stat/desc upgrade, nothing to dispatch
    if effect_key in GENERIC_KEYS:
        return ("generic", "")
    cons = consumers.get(effect_key, set())
    if al_script and al_script in cons:
        return ("wired", "")
    if {"ability.gd", "combat.gd"} & cons:
        return ("generic", "")
    if not cons:
        return ("dead", f"effect_key '{effect_key}' is read by NO script")
    return ("dead", f"effect_key '{effect_key}' is only read by {sorted(cons)}, not this ability's AL ({al_script or 'none'})")

WEAPON_COLOR = {"Sword": "#7ec2ff", "Bow": "#5fd175", "Staff": "#c79bff", "Dagger": "#ff8a9a"}

# Static gauge context (constants read from the *_component.gd files, 2026-06-02).
GAUGES = {
    "Sword":  ("Combo (max 3)",        "Build +1/landed hit (cap 3, 5s decay). Spenders amplify: Crescent Cleave +100%/pt, Sundering Blow +200%/pt."),
    "Bow":    ("Momentum (max 10)",    "Build +1/landed hit. +35% damage & +30% attack-speed at 10 stacks; 2s decay delay. Snipe consumes all (+12%/stack)."),
    "Staff":  ("Element Stance",       "Cycle Fire / Ice / Lightning (R). Fire = 12%/tick burn ×3 (4s); Ice = 40% slow (2.5s); Lightning = +50% + chain 3 hops/180px (40%)."),
    "Dagger": ("Shadowmeld (stealth)", "Enter stealth (R, 6s CD, 8s max). Next hit out of stealth ×2.0 ambush. Several abilities gain stealth-modified behavior."),
}

# Per-level column order + header label. Only present columns render.
LEVEL_COLS = [
    ("mana", "Mana"), ("cooldown", "CD (s)"), ("damage", "Dmg %"),
    ("hits", "Hits"), ("targets", "Targets"), ("cast", "Cast (s)"),
    ("status_chance", "Status %"), ("status_duration", "Status (s)"),
    ("range", "Range×"), ("knockback", "KB"),
    ("buff_duration", "Buff (s)"), ("debuff_duration", "Debuff (s)"),
]


def esc(s):
    return html.escape(str(s), quote=True)


def fmt_num(v):
    if isinstance(v, float):
        return f"{v:g}"
    return str(v)


def format_desc(text):
    """Convert the .tres BBCode-ish description into safe HTML."""
    if not text:
        return ""
    # Escape first, then re-introduce a whitelist of tags.
    t = esc(text)
    # [color=#xxx]..[/color]  (escaped form: [color=#xxx])
    t = re.sub(r"\[color=(#?[0-9a-zA-Z]+)\]", lambda m: f'<span style="color:{m.group(1)}">', t)
    t = t.replace("[/color]", "</span>")
    t = re.sub(r"\[/?b\]", lambda m: "<b>" if m.group(0) == "[b]" else "</b>", t)
    # $[placeholder] -> highlighted chip
    t = re.sub(r"\$\[([^\]]+)\]", lambda m: f'<span class="ph">${{{m.group(1)}}}</span>', t)
    return t


def collapse_curve(rows, key):
    """Return (is_flat, first, last) for a per-level field."""
    vals = [r[key] for r in rows if key in r]
    if not vals:
        return (True, None, None)
    return (len(set(vals)) == 1, vals[0], vals[-1])


def ability_flags(ab, referenced_ids):
    """Auto-detected verification flags for one ability."""
    flags = []  # (severity, text)  severity in {bad, warn, info}
    ups = ab["upgrades"]
    tiers = {1: [], 2: [], 3: []}
    for u in ups:
        tiers.get(u["tier"], tiers.setdefault(u["tier"], [])).append(u)

    is_active = ab["type"] == "Active"
    if not ups:
        flags.append(("bad", "No upgrades at all — empty tree."))
    else:
        for t in (1, 2, 3):
            if not tiers[t]:
                flags.append(("warn", f"No Tier-{t} upgrade."))
        # T3 shape differs by ability type:
        #   Actives  → T3 should be a "pick 1 of N" variant set (shared variant_group).
        #   Passives → T3 is conventionally a single flat stacking upgrade (no group).
        t3 = tiers[3]
        groups = {}
        for u in t3:
            groups.setdefault(u["variant_group"] or "(none)", []).append(u)
        if is_active:
            for g, members in groups.items():
                if g == "(none)" and members:
                    flags.append(("warn", f"{len(members)} Tier-3 upgrade(s) with no variant_group — won't be mutually exclusive."))
                elif len(members) == 1:
                    flags.append(("warn", f"Tier-3 variant group '{g}' has only 1 option — no real choice (design wants 3+)."))
        else:
            # passive: only note it, don't warn
            lone = groups.get("(none)", [])
            if len(lone) == 1 and len(t3) == 1:
                flags.append(("info", "Passive Tier-3 is a single flat upgrade (no variant choice — by convention)."))
            elif any(g != "(none)" and len(m) == 1 for g, m in groups.items()):
                flags.append(("warn", "Passive Tier-3 has a variant_group with only 1 option."))
        # zero-magnitude effects
        for u in ups:
            if u["effect_key"] and abs(u["magnitude"]) < 1e-9 and u["effect_key"] not in ("execute_gate",):
                flags.append(("info", f"Upgrade '{u['name']}' has effect_key '{u['effect_key']}' but magnitude 0."))

    # Active with no damage/targets/hits and no custom/buff — likely missing scaling
    p = ab["present"]
    if ab["type"] == "Active" and not p["damage"] and not ab["custom_keys"] \
            and not ab["applies_buff"] and not ab["stat_bonus_types"]:
        flags.append(("info", "Active with no damage%, custom value, or buff — effect lives entirely in its AL script."))

    # Flat damage across levels
    if p["damage"]:
        flat, a, b = collapse_curve(ab["levels"], "damage")
        if flat and ab["max_level"] > 1:
            flags.append(("info", f"Damage% is flat ({a}) across all {ab['max_level']} levels."))
    return flags, tiers


def render_level_table(ab):
    rows = ab["levels"]
    present = ab["present"]
    # which base columns to show
    cols = [(k, label) for (k, label) in LEVEL_COLS
            if any(k in r for r in rows)]
    custom_keys = ab["custom_keys"]
    stat_types = ab["stat_bonus_types"]

    head = "<th>Lvl</th>"
    for _, label in cols:
        head += f"<th>{esc(label)}</th>"
    for ck in custom_keys:
        head += f'<th title="custom_value">{esc(ck)}</th>'
    for st in stat_types:
        head += f'<th title="passive stat bonus">+{esc(st)}</th>'

    body = ""
    for i, r in enumerate(rows):
        is_max = (i == len(rows) - 1)
        rowcls = " class='maxrow'" if is_max else ""
        lvlabel = f"{r['level']} ★" if is_max else str(r["level"])
        body += f"<tr{rowcls}><td class='lv'>{lvlabel}</td>"
        for k, _ in cols:
            body += f"<td>{fmt_num(r[k]) if k in r else '·'}</td>"
        cust = r.get("custom", {})
        for ck in custom_keys:
            body += f"<td>{fmt_num(cust.get(ck, '·'))}</td>"
        sbmap = {}
        for sb in r.get("stat_bonuses", []):
            val = sb["flat"] if sb["flat"] else (f"{sb['percent']}%" if sb["percent"] else 0)
            sbmap[sb["stat"]] = val
        for st in stat_types:
            body += f"<td>{fmt_num(sbmap.get(st, '·'))}</td>"
        body += "</tr>"
    colcount = 1 + len(cols) + len(custom_keys) + len(stat_types)
    cap = "<div class='maxnote'>★ = max level — the only level upgrades unlock; judge every upgrade against this row.</div>"
    return f"<table class='lvl'><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table>{cap}", colcount


TIER_TAG = {1: "t1", 2: "t2", 3: "t3"}


def render_upgrades(tiers, al_script, consumers, maxrow):
    if not any(tiers.values()):
        return "<p class='dim'>No upgrades.</p>"
    out = ""
    for t in (1, 2, 3):
        ups = tiers.get(t, [])
        if not ups:
            out += f"<div class='tierrow'><span class='tier {TIER_TAG[t]}'>T{t}</span><span class='dim'>— none —</span></div>"
            continue
        # group T3 by variant_group
        cards = ""
        for u in sorted(ups, key=lambda x: (x["variant_group"], x["name"])):
            vg = u["variant_group"]
            vgbadge = f"<span class='vg' title='mutually-exclusive group'>⊕ {esc(vg)}</span>" if vg else ""
            status, reason = upgrade_status(u["effect_key"], al_script, consumers)
            noop = precondition_noop(u["effect_key"], maxrow)
            mag = ""
            if u["effect_key"]:
                mag = f"<code class='ek'>{esc(u['effect_key'])}</code>"
                if abs(u["magnitude"]) > 1e-9:
                    mag += f" <span class='mag'>= {fmt_num(u['magnitude'])}</span>"
                else:
                    mag += " <span class='mag zero'>= 0</span>"
            sbadge = ""
            cls = ""
            if status == "dead":
                sbadge = f"<span class='sbadge dead' title='{esc(reason)}'>DEAD</span>"
                cls = " deadup"
            elif noop:
                sbadge = f"<span class='sbadge noop' title='{esc(noop)}'>NO-OP@MAX</span>"
                cls = " deadup"
            cards += (
                f"<div class='up{cls}'><div class='uphead'>"
                f"<b>{esc(u['name'])}</b> <span class='cost'>{u['point_cost']} pt</span> {vgbadge}{sbadge}</div>"
                f"<div class='updesc'>{format_desc(u['description'])}</div>"
                f"<div class='upmeta'>{mag}</div></div>"
            )
        out += f"<div class='tierrow'><span class='tier {TIER_TAG[t]}'>T{t}</span><div class='ups'>{cards}</div></div>"
    return out


def find_orphan_upgrades(referenced_ids):
    """Upgrade .tres on disk whose upgrade_id is never referenced by an ability."""
    orphans = {}
    for w, d in UPGRADE_DIRS.items():
        miss = []
        for path in sorted(glob.glob(os.path.join(d, "*.tres"))):
            txt = open(path, encoding="utf-8", errors="ignore").read()
            m = re.search(r'upgrade_id\s*=\s*"([^"]*)"', txt)
            uid = m.group(1) if m else ""
            if uid and uid not in referenced_ids:
                miss.append((os.path.basename(path), uid))
        if miss:
            orphans[w] = miss
    return orphans


def main():
    data = json.load(open(DUMP, encoding="utf-8"))
    roster = data["roster"]
    consumers = scan_effect_consumers()
    referenced_ids = set()
    dead_upgrades = []   # (weapon, ability, upgrade, reason)
    noop_upgrades = []   # (weapon, ability, upgrade, reason) — useless at max level
    for w in data["weapons"]:
        for ab in roster[w]:
            maxrow = ab["levels"][-1]
            for u in ab["upgrades"]:
                referenced_ids.add(u["id"])
                st, reason = upgrade_status(u["effect_key"], ab["al_script"], consumers)
                if st == "dead":
                    dead_upgrades.append((w, ab["name"], u, reason))
                noop = precondition_noop(u["effect_key"], maxrow)
                if noop:
                    noop_upgrades.append((w, ab["name"], u, noop))
    orphans = find_orphan_upgrades(referenced_ids)

    # ---- summary numbers ----
    weap_rows = ""
    total_flags = 0
    for w in data["weapons"]:
        abs = roster[w]
        ups = sum(len(a["upgrades"]) for a in abs)
        t1 = sum(1 for a in abs for u in a["upgrades"] if u["tier"] == 1)
        t2 = sum(1 for a in abs for u in a["upgrades"] if u["tier"] == 2)
        t3 = sum(1 for a in abs for u in a["upgrades"] if u["tier"] == 3)
        weap_rows += (f"<tr><td class='ab' style='color:{WEAPON_COLOR[w]}'>{w}</td>"
                      f"<td>{len(abs)}</td><td>{sum(1 for a in abs if a['type']=='Active')}</td>"
                      f"<td>{sum(1 for a in abs if a['type']=='Passive')}</td>"
                      f"<td>{ups}</td><td>{t1}</td><td>{t2}</td><td>{t3}</td></tr>")

    # ---- per-weapon ability sections ----
    sections = ""
    nav_links = ""
    for w in data["weapons"]:
        color = WEAPON_COLOR[w]
        gname, gdesc = GAUGES[w]
        nav_links += f"<a href='#w-{w}' style='color:{color}'>{w}</a>"
        cards = ""
        for ab in roster[w]:
            flags, tiers = ability_flags(ab, referenced_ids)
            total_flags += sum(1 for s, _ in flags if s in ("bad", "warn"))
            tbl, _ = render_level_table(ab)
            ups_html = render_upgrades(tiers, ab["al_script"], consumers, ab["levels"][-1])
            badge = "active" if ab["type"] == "Active" else "passive"
            dstat = "magic" if ab["damage_stat"] == "MAGICATTACK" else "phys"
            dstat_label = "Magic" if dstat == "magic" else "Phys"
            tree = (f"path {ab['tree_path']} · depth {ab['tree_depth']}"
                    if ab["tree_path"] >= 0 else "not in tree")
            flag_html = ""
            if flags:
                items = "".join(f"<li class='fl-{s}'>{esc(txt)}</li>" for s, txt in flags)
                flag_html = f"<ul class='flags'>{items}</ul>"
            n_t3 = len(tiers.get(3, []))
            up_summary = f"{len(ab['upgrades'])} upgrades · T1×{len(tiers.get(1,[]))} T2×{len(tiers.get(2,[]))} T3×{n_t3}"
            cards += f"""
<div class="card ability" data-name="{esc(ab['name'].lower())}" data-type="{badge}">
  <div class="abhead">
    <span class="aname">{esc(ab['name'])}</span>
    <span class="tag {badge}">{ab['type']}</span>
    <span class="tag {dstat}">{dstat_label}</span>
    <span class="lvl-pill">max L{ab['max_level']}</span>
    <span class="dim tree">{esc(tree)}</span>
    <span class="dim file">{esc(ab['file'])}{(' · ' + esc(ab['al_script'])) if ab['al_script'] else ''}</span>
  </div>
  <div class="desc">{format_desc(ab['description'])}</div>
  {flag_html}
  <div class="block-h">Per-level values</div>
  <div class="tblwrap">{tbl}</div>
  <div class="block-h">Upgrade tree <span class="dim">({esc(up_summary)})</span></div>
  {ups_html}
</div>"""
        orphan_note = ""
        if w in orphans:
            lst = "".join(f"<li><code>{esc(fn)}</code> <span class='dim'>(id {esc(uid)})</span></li>"
                          for fn, uid in orphans[w])
            orphan_note = (f"<div class='find bad'><h4>Orphaned upgrade files ({len(orphans[w])})</h4>"
                           f"<p>These <code>.tres</code> exist in <code>{w}/Upgrades/</code> but no ability references them:</p>"
                           f"<ul class='flags'>{lst}</ul></div>")
        sections += f"""
<h2 class="section" id="w-{w}" style="color:{color};border-color:{color}44">{w}
  <span class="meta">— {esc(gname)}</span></h2>
<div class="gauge-card" style="border-left-color:{color}"><b>Gauge:</b> {esc(gdesc)}</div>
{orphan_note}
{cards}"""

    # ---- audit summary (dead upgrades, empty trees, lone variants, orphans) ----
    empty_trees, lone_variants = [], []
    for w in data["weapons"]:
        for ab in roster[w]:
            tiers = {1: [], 2: [], 3: []}
            for u in ab["upgrades"]:
                tiers.setdefault(u["tier"], []).append(u)
            if not ab["upgrades"]:
                empty_trees.append((w, ab["name"]))
            if ab["type"] == "Active":
                groups = {}
                for u in tiers.get(3, []):
                    groups.setdefault(u["variant_group"] or "(none)", []).append(u)
                for g, m in groups.items():
                    if g != "(none)" and len(m) == 1:
                        lone_variants.append((w, ab["name"], g))

    def _ul(items):
        return "<ul class='flags'>" + "".join(f"<li>{x}</li>" for x in items) + "</ul>" if items else "<p class='dim'>none</p>"

    dead_li = [f"<span class='fl-bad'>[{esc(w)}] {esc(an)}</span> — <b>{esc(u['name'])}</b> "
               f"(T{u['tier']}) <code>{esc(u['effect_key'])}</code>: {esc(reason)}"
               for w, an, u, reason in dead_upgrades]
    noop_li = [f"<span class='fl-bad'>[{esc(w)}] {esc(an)}</span> — <b>{esc(u['name'])}</b> "
               f"(T{u['tier']}) <code>{esc(u['effect_key'])}</code>: {esc(reason)}"
               for w, an, u, reason in noop_upgrades]
    empty_li = [f"[{esc(w)}] <b>{esc(an)}</b>" for w, an in empty_trees]
    lone_li = [f"[{esc(w)}] <b>{esc(an)}</b> — variant group <code>{esc(g)}</code> has 1 option"
               for w, an, g in lone_variants]
    orphan_li = [f"[{esc(w)}] <code>{esc(fn)}</code> (id {esc(uid)})"
                 for w, lst in orphans.items() for fn, uid in lst]
    audit_html = f"""
<div class="card audit">
  <h3 style="margin-top:0">⚠ Upgrade audit</h3>
  <div class="block-h">Dead upgrades — effect_key not consumed by this ability ({len(dead_li)})</div>
  {_ul(dead_li)}
  <div class="block-h">No-op at max level — upgrades unlock only at max level, where their target value is already 0 ({len(noop_li)})</div>
  {_ul(noop_li)}
  <div class="block-h">Empty trees — active abilities with no upgrades ({len(empty_li)})</div>
  {_ul(empty_li)}
  <div class="block-h">Lone T3 variant groups — "pick 1 of N" with only 1 option ({len(lone_li)})</div>
  {_ul(lone_li)}
  <div class="block-h">Orphaned upgrade .tres — on disk, referenced by no ability ({len(orphan_li)})</div>
  {_ul(orphan_li)}
</div>"""

    generated = data.get("generated_note", "")
    html_doc = f"""<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Ability Reference &amp; Balance Report</title>
<style>
:root{{--bg:#0f1117;--card:#171a23;--ink:#e7e9ee;--mut:#9aa3b2;--line:#262b38;--acc:#6db1ff;--good:#3fb950;--warn:#e0a800;--bad:#f85149;}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--ink);font:13.5px/1.5 -apple-system,Segoe UI,Roboto,sans-serif}}
.wrap{{max-width:1280px;margin:0 auto;padding:26px 20px 90px}}
h1{{font-size:28px;margin:0 0 4px}}
.sub{{color:var(--mut);margin:0 0 18px;font-size:13px}}
.nav{{position:sticky;top:0;z-index:20;background:rgba(15,17,23,.95);backdrop-filter:blur(6px);border-bottom:1px solid var(--line);padding:10px 0;margin:0 0 18px;display:flex;gap:14px;align-items:center;flex-wrap:wrap}}
.nav a{{text-decoration:none;font-weight:600;font-size:13px}}
.nav input{{margin-left:auto;background:#0b0d13;border:1px solid var(--line);color:var(--ink);border-radius:7px;padding:6px 10px;font-size:13px;width:230px}}
.nav button{{background:#1a2030;border:1px solid var(--line);color:var(--ink);border-radius:7px;padding:6px 10px;cursor:pointer;font-size:12.5px}}
h2.section{{margin:34px 0 6px;font-size:22px;border-bottom:2px solid var(--line);padding-bottom:6px}}
h2.section .meta{{color:var(--mut);font-weight:400;font-size:13px}}
.card{{background:var(--card);border:1px solid var(--line);border-radius:11px;padding:14px 16px;margin:12px 0}}
.gauge-card{{background:#1c2230;border-left:3px solid var(--acc);padding:9px 13px;border-radius:6px;margin:8px 0 4px;color:#cdd6e4;font-size:12.5px}}
table{{border-collapse:collapse;font-size:12.5px}}
th,td{{padding:4px 9px;text-align:right;border-bottom:1px solid var(--line);white-space:nowrap}}
th{{color:var(--mut);font-weight:600;background:#0c0f15;text-align:right}}
table.lvl td.lv,table.lvl th:first-child{{text-align:center;color:#fff;font-weight:600}}
table.summary{{width:auto;margin:6px 0 4px}}
table.summary td,table.summary th{{text-align:center;padding:6px 14px}}
td.ab,table.summary td.ab{{font-weight:700;text-align:left}}
.abhead{{display:flex;align-items:center;gap:9px;flex-wrap:wrap}}
.aname{{font-size:16px;font-weight:700;color:#fff}}
.tag{{display:inline-block;padding:1px 8px;border-radius:9px;font-size:10.5px;font-weight:700;letter-spacing:.3px}}
.tag.active{{background:#1a3050;color:#7ec2ff}}.tag.passive{{background:#321a45;color:#c79bff}}
.tag.phys{{background:#33260f;color:#f0b95a}}.tag.magic{{background:#0e2d33;color:#5fd1c9}}
.lvl-pill{{font-size:11px;color:var(--mut);border:1px solid var(--line);border-radius:9px;padding:1px 8px}}
.dim{{color:var(--mut);font-size:11.5px}}
.tree{{margin-left:2px}} .file{{margin-left:auto;font-family:monospace;font-size:11px}}
.desc{{margin:8px 0;color:#cdd6e4;font-size:12.5px}}
.ph{{background:#10202e;color:#7ec2ff;border-radius:4px;padding:0 4px;font-size:11.5px}}
.block-h{{margin:12px 0 5px;font-size:11px;text-transform:uppercase;letter-spacing:1px;color:var(--mut);border-top:1px dashed var(--line);padding-top:8px}}
.tblwrap{{overflow:auto}}
.flags{{margin:7px 0;padding-left:18px}}
.flags li{{margin:2px 0;font-size:12px}}
.fl-bad{{color:#ff9b93}}.fl-warn{{color:#f0c66a}}.fl-info{{color:var(--mut)}}
.tierrow{{display:flex;gap:10px;align-items:flex-start;margin:6px 0}}
.tier{{flex:none;font-weight:700;font-size:11px;border-radius:6px;padding:2px 8px;margin-top:4px}}
.tier.t1{{background:#15331e;color:#5fd175}}.tier.t2{{background:#33260f;color:#f0b95a}}.tier.t3{{background:#3a1330;color:#ff8ad0}}
.ups{{display:flex;gap:8px;flex-wrap:wrap}}
.up{{background:#0e1119;border:1px solid var(--line);border-radius:8px;padding:8px 10px;max-width:280px;font-size:12px}}
.up.deadup{{border-color:var(--bad);background:#1f1113}}
.sbadge.dead{{background:#41121e;color:#ff8a9a;font-size:10px;font-weight:700;border-radius:8px;padding:1px 6px;letter-spacing:.4px}}
.sbadge.noop{{background:#3a2d12;color:#f0c66a;font-size:10px;font-weight:700;border-radius:8px;padding:1px 6px;letter-spacing:.4px}}
table.lvl tr.maxrow td{{background:#13202b;color:#cfe6ff;font-weight:600;border-top:2px solid var(--acc)}}
.maxnote{{color:var(--acc);font-size:11px;margin:4px 0 0}}
.card.audit{{border-color:#3a2330}}
.card.audit .flags li{{margin:3px 0;font-size:12.5px}}
.uphead{{display:flex;gap:6px;align-items:center;flex-wrap:wrap}}
.cost{{font-size:10.5px;color:#9fb4d6;background:#15203a;border-radius:8px;padding:0 6px}}
.vg{{font-size:10px;color:#ff8ad0;background:#3a1330;border-radius:8px;padding:0 6px}}
.updesc{{color:#c2cad6;margin:4px 0}}
.upmeta{{margin-top:3px}}
code,.ek{{background:#0b0d13;border:1px solid var(--line);padding:0 5px;border-radius:4px;font-size:11px;color:#cdd6e4}}
.mag{{color:#7ec2ff;font-size:11px}} .mag.zero{{color:var(--bad)}}
.find{{background:var(--card);border:1px solid var(--line);border-left:4px solid var(--warn);border-radius:8px;padding:10px 14px;margin:10px 0}}
.find.bad{{border-left-color:var(--bad)}} .find h4{{margin:0 0 5px}}
.legend{{color:var(--mut);font-size:12px;margin:4px 0 0}}
.hidden{{display:none}}
</style></head><body>
<div class="wrap">
<h1>Ability Reference &amp; Balance Report</h1>
<p class="sub">{esc(generated)} · <b>{data['total_abilities']} abilities</b> · <b>{data['total_upgrades']} referenced upgrades</b> · <b>{total_flags}</b> verify flags · generated by <code>tools/gen_ability_reference.py</code> from <code>tools/dump_ability_data.gd</code>.</p>

<table class="summary card">
<thead><tr><th class="ab">Weapon</th><th>Abilities</th><th>Active</th><th>Passive</th><th>Upgrades</th><th>T1</th><th>T2</th><th>T3</th></tr></thead>
<tbody>{weap_rows}</tbody>
</table>
<p class="legend">Per-level numbers are evaluated through the game's own <code>AbilityScalingFormula.calculate()</code> — they are exactly what the game produces. <b>Verify flags</b>: <span class="fl-bad">red = likely bug</span>, <span class="fl-warn">amber = incomplete/odd</span>, <span class="fl-info">grey = informational</span>. T3 <span class="vg">⊕ group</span> = mutually-exclusive variant set. A <span class="sbadge dead">DEAD</span> badge marks an upgrade whose <code>effect_key</code> no code path consumes for that ability.</p>
{audit_html}

<div class="nav">
  {nav_links}
  <button onclick="toggleAll(false)">Collapse curves</button>
  <button onclick="setFilter('all')">All</button>
  <button onclick="setFilter('active')">Actives</button>
  <button onclick="setFilter('passive')">Passives</button>
  <input id="q" placeholder="filter abilities…" oninput="doFilter()">
</div>
{sections}
</div>
<script>
function doFilter(){{
  const q=(document.getElementById('q').value||'').toLowerCase().trim();
  document.querySelectorAll('.ability').forEach(c=>{{
    const okName=!q||c.dataset.name.includes(q);
    const okType=window._tf==='all'||!window._tf||c.dataset.type===window._tf;
    c.classList.toggle('hidden',!(okName&&okType));
  }});
}}
function setFilter(t){{window._tf=t;doFilter();}}
function toggleAll(show){{
  document.querySelectorAll('.tblwrap').forEach(t=>t.classList.toggle('hidden'));
}}
window._tf='all';
</script>
</body></html>"""

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "w", encoding="utf-8").write(html_doc)
    print(f"Wrote {OUT}  ({len(html_doc)//1024} KB, {data['total_abilities']} abilities, "
          f"{data['total_upgrades']} upgrades, {total_flags} flags)")
    if orphans:
        print("Orphaned upgrade files:", {w: len(v) for w, v in orphans.items()})


if __name__ == "__main__":
    main()
