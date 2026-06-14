/* ============================================================
   EMBERWILDS companion site
   Same-origin client for the Flask game API.
   ============================================================ */
"use strict";

/* ---------- constants ---------- */

const CLASS_NAMES = {
  0: "Sword", 1: "Bow", 2: "Staff", 3: "Dagger", 4: "Beginner",
  5: "Crusader", 6: "Ranger", 7: "Archmage", 8: "Assassin",
};
const CLASS_ICONS = { 0: "⚔", 1: "➶", 2: "⚕", 3: "🗡", 4: "✦", 5: "⚔", 6: "➶", 7: "⚕", 8: "🗡" };
const WEAPON_KEYS = ["sword", "bow", "staff", "dagger"];
const SESSION_KEY = "emberwilds_session";

/* ---------- tiny helpers ---------- */

const $ = (sel) => document.querySelector(sel);

async function api(path, body) {
  const res = await fetch(path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body || {}),
  });
  let data = {};
  try { data = await res.json(); } catch (_) { /* non-JSON error body */ }
  if (!res.ok) throw new Error(data.error || `Request failed (${res.status})`);
  return data;
}

function className(id) { return CLASS_NAMES[id] ?? "Wilder"; }

function prettyMap(key) {
  if (!key) return "Unknown";
  return key.replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[c]);
}

/* ============================================================
   EMBER PARTICLES — rising sparks in the hero
   ============================================================ */
(() => {
  const canvas = $("#ember-canvas");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  let w = 0, h = 0, running = true, raf = 0;
  let embers = [];

  function resize() {
    w = canvas.width = canvas.offsetWidth * devicePixelRatio;
    h = canvas.height = canvas.offsetHeight * devicePixelRatio;
  }

  // pointer interaction — the cursor stirs the sparks
  const mouse = { x: -9999, y: -9999, vx: 0, vy: 0 };
  canvas.parentElement.addEventListener("pointermove", (ev) => {
    const rect = canvas.getBoundingClientRect();
    const nx = (ev.clientX - rect.left) * devicePixelRatio;
    const ny = (ev.clientY - rect.top) * devicePixelRatio;
    mouse.vx = nx - (mouse.x === -9999 ? nx : mouse.x);
    mouse.vy = ny - (mouse.y === -9999 ? ny : mouse.y);
    mouse.x = nx; mouse.y = ny;
  });
  canvas.parentElement.addEventListener("pointerleave", () => { mouse.x = mouse.y = -9999; });

  function spawn(initial) {
    const bright = Math.random() < 0.12;
    return {
      x: Math.random() * w,
      y: initial ? Math.random() * h : h + 10 * devicePixelRatio,
      r: (bright ? 2.2 : 0.8 + Math.random() * 1.4) * devicePixelRatio,
      vy: (0.25 + Math.random() * 0.7) * devicePixelRatio,
      px: 0, py: 0, // pointer-push velocity, decays each frame
      drift: (Math.random() * 2 - 1) * 0.35 * devicePixelRatio,
      phase: Math.random() * Math.PI * 2,
      wobble: 0.4 + Math.random() * 1.2,
      life: 0,
      maxLife: 400 + Math.random() * 500,
      bright,
      hue: bright ? 38 + Math.random() * 10 : 18 + Math.random() * 18,
    };
  }

  function tick() {
    if (!running) return;
    ctx.clearRect(0, 0, w, h);
    const target = Math.min(110, Math.floor(w / (14 * devicePixelRatio)));
    while (embers.length < target) embers.push(spawn(embers.length < target / 2));

    ctx.globalCompositeOperation = "lighter";
    mouse.vx *= 0.82; mouse.vy *= 0.82; // cursor momentum fades when it stops
    for (const e of embers) {
      e.life++;
      // pointer repulsion: stir embers near the cursor, carrying its motion
      const mdx = e.x - mouse.x, mdy = e.y - mouse.y;
      const mdist2 = mdx * mdx + mdy * mdy;
      const reach = 130 * devicePixelRatio;
      if (mdist2 < reach * reach) {
        const mdist = Math.sqrt(mdist2) || 1;
        const force = (1 - mdist / reach) * 1.6 * devicePixelRatio;
        e.px += (mdx / mdist) * force + mouse.vx * 0.06;
        e.py += (mdy / mdist) * force + mouse.vy * 0.06;
      }
      e.px *= 0.9; e.py *= 0.9;
      e.y -= e.vy - e.py;
      e.x += e.drift + e.px + Math.sin(e.phase + e.life * 0.02) * e.wobble * devicePixelRatio * 0.25;
      const fade = Math.min(1, e.life / 60) * Math.max(0, 1 - e.life / e.maxLife);
      const flick = 0.75 + 0.25 * Math.sin(e.life * 0.18 + e.phase);
      const a = fade * flick * (e.bright ? 0.95 : 0.55);
      if (a <= 0 || e.y < -12) { Object.assign(e, spawn(false)); continue; }

      const g = ctx.createRadialGradient(e.x, e.y, 0, e.x, e.y, e.r * 4);
      g.addColorStop(0, `hsla(${e.hue}, 100%, ${e.bright ? 78 : 62}%, ${a})`);
      g.addColorStop(0.4, `hsla(${e.hue}, 95%, 50%, ${a * 0.45})`);
      g.addColorStop(1, "hsla(20, 90%, 40%, 0)");
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.arc(e.x, e.y, e.r * 4, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.globalCompositeOperation = "source-over";
    raf = requestAnimationFrame(tick);
  }

  resize();
  addEventListener("resize", () => { resize(); });
  if (!matchMedia("(prefers-reduced-motion: reduce)").matches) {
    // only burn cycles while the hero is on screen
    new IntersectionObserver(([entry]) => {
      const want = entry.isIntersecting;
      if (want && !running) { running = true; tick(); }
      else if (!want && running) { running = false; cancelAnimationFrame(raf); }
      else if (want) { cancelAnimationFrame(raf); tick(); }
    }).observe(canvas);
  }
})();

/* ============================================================
   SCROLL EFFECTS — nav state, reveals, hero parallax
   ============================================================ */
(() => {
  const nav = $("#nav");
  const heroContent = document.querySelector(".hero-content");
  addEventListener("scroll", () => {
    nav.classList.toggle("scrolled", scrollY > 40);
    if (heroContent && scrollY < innerHeight) {
      heroContent.style.transform = `translateY(${scrollY * 0.28}px)`;
      heroContent.style.opacity = String(Math.max(0, 1 - scrollY / (innerHeight * 0.65)));
    }
  }, { passive: true });

  const obs = new IntersectionObserver((entries) => {
    for (const en of entries) {
      if (en.isIntersecting) { en.target.classList.add("in"); obs.unobserve(en.target); }
    }
  }, { threshold: 0.12, rootMargin: "0px 0px -40px 0px" });
  document.querySelectorAll(".reveal").forEach((el) => obs.observe(el));
})();

/* ============================================================
   SCREENSHOT SHOWCASE — thumbnail swaps the featured shot
   ============================================================ */
(() => {
  const main = $("#shot-main"), caption = $("#shot-caption");
  if (!main) return;
  document.querySelectorAll(".shot-thumb").forEach((btn) => {
    btn.addEventListener("click", () => {
      document.querySelectorAll(".shot-thumb").forEach((t) => t.classList.toggle("active", t === btn));
      // restart the fade-in animation on swap
      main.style.animation = "none";
      void main.offsetWidth;
      main.style.animation = "";
      main.src = btn.dataset.src;
      caption.textContent = btn.dataset.caption;
    });
  });
})();

/* ============================================================
   LEADERBOARD
   ============================================================ */
const Leaderboard = (() => {
  let entries = [];
  let sort = "level";

  function bestMastery(e) {
    let best = { key: null, level: 0 };
    for (const k of WEAPON_KEYS) {
      const lvl = e.weapon_mastery?.[k]?.level ?? 0;
      if (lvl > best.level) best = { key: k, level: lvl };
    }
    return best;
  }

  // the big number + caption shown for the current sort mode
  function metric(e) {
    if (sort === "monies") return { value: Number(e.monies || 0), label: "MONIES", row: `◉ ${Number(e.monies || 0).toLocaleString()}` };
    if (sort === "mastery") {
      const b = bestMastery(e);
      const cap = b.key ? b.key.charAt(0).toUpperCase() + b.key.slice(1) : "Unbound";
      return { value: b.level, label: cap.toUpperCase(), row: `${cap} ${b.level}` };
    }
    return { value: e.level, label: "LEVEL", row: `Lv ${e.level}` };
  }

  function podiumCard(e, rank) {
    const m = metric(e);
    return `
      <div class="podium-card rank-${rank}" data-armory="${escapeHtml(e.name)}" tabindex="0" role="button">
        <p class="podium-rank">${["FIRST", "SECOND", "THIRD"][rank - 1]}</p>
        <p class="podium-name" title="${escapeHtml(e.name)}">${escapeHtml(e.name)}</p>
        <p class="podium-class">${CLASS_ICONS[e.character_class] ?? "✦"} ${className(e.character_class)} · ${escapeHtml(prettyMap(e.last_map))}</p>
        <p class="podium-level"><span class="countup" data-n="${m.value}">0</span><small>${m.label}</small></p>
        ${e.is_bot ? '<p class="podium-bot">Hearthfolk</p>' : ""}
      </div>`;
  }

  function row(e, rank, i) {
    return `
      <div class="lb-row" data-armory="${escapeHtml(e.name)}" tabindex="0" role="button" style="animation-delay:${Math.min(i * 0.05, 0.6)}s">
        <span class="lb-rank">${rank}</span>
        <span class="lb-name"><span title="${escapeHtml(e.name)}">${escapeHtml(e.name)}</span>${e.is_bot ? '<span class="lb-chip">Hearthfolk</span>' : ""}</span>
        <span class="lb-class">${className(e.character_class)}</span>
        <span class="lb-level">${metric(e).row}</span>
      </div>`;
  }

  function runCountups(root) {
    root.querySelectorAll(".countup").forEach((el) => {
      const target = Number(el.dataset.n);
      const dur = 900;
      const t0 = performance.now();
      let done = false;
      (function step(t) {
        if (done) return;
        const p = Math.min(1, (t - t0) / dur);
        const eased = 1 - Math.pow(1 - p, 3);
        el.textContent = Math.round(target * eased).toLocaleString();
        if (p < 1) requestAnimationFrame(step);
        else done = true;
      })(t0);
      // rAF is suspended in background tabs — guarantee the final value lands
      setTimeout(() => { done = true; el.textContent = target.toLocaleString(); }, dur + 150);
    });
  }

  function render() {
    const list = entries.slice(0, 25);
    const podium = $("#lb-podium"), table = $("#lb-table"), status = $("#lb-status");

    if (!list.length) {
      podium.innerHTML = "";
      table.innerHTML = "";
      status.textContent = "The ledger is empty. Be the first to carve your name.";
      return;
    }
    // visual order: 2nd, 1st, 3rd
    const top = list.slice(0, 3);
    const order = top.length === 3 ? [top[1], top[0], top[2]] : top;
    const ranks = top.length === 3 ? [2, 1, 3] : top.map((_, i) => i + 1);
    podium.innerHTML = order.map((e, i) => podiumCard(e, ranks[i])).join("");
    table.innerHTML = list.slice(3).map((e, i) => row(e, i + 4, i)).join("");
    status.textContent = "";
    runCountups(podium);
  }

  async function load() {
    const status = $("#lb-status");
    status.classList.remove("error");
    status.textContent = "Consulting the ledger…";
    try {
      const data = await api("/api/leaderboard", { limit: 100, sort });
      entries = data.leaderboard || [];
      render();
    } catch (err) {
      status.classList.add("error");
      status.textContent = `Couldn't reach the ledger: ${err.message}`;
    }
  }

  document.querySelectorAll(".lb-tab").forEach((tab) => {
    tab.addEventListener("click", () => {
      sort = tab.dataset.sort;
      document.querySelectorAll(".lb-tab").forEach((t) => t.classList.toggle("active", t === tab));
      load();
    });
  });
  $("#lb-refresh").addEventListener("click", load);
  return { load };
})();

/* ============================================================
   ARMORY — full character inspection via /api/player/load
   ============================================================ */
const Armory = (() => {
  const overlay = $("#armory");
  const body = $("#armory-body");
  const ATTR_NAMES = { 0: "STR", 1: "INT", 2: "DEX", 3: "LUCK", 15: "CON" };
  const ATTR_ORDER = ["0", "2", "1", "3", "15"];
  const RARITY = { 0: "common", 1: "uncommon", 2: "rare", 3: "epic", 4: "legendary" };
  // Slot keys as the game persists them: weapon slots are strings, armor
  // slots are ArmorType enum ints serialized as "0".."3".
  const EQUIP_SLOTS = [
    ["WEAPON", "Weapon"], ["SECONDARY_WEAPON", "Secondary Weapon"],
    ["0", "Head"], ["1", "Chest"], ["2", "Legs"], ["3", "Feet"],
  ];

  function itemName(path) {
    if (!path) return null;
    const file = path.split("/").pop().replace(/\.tres$/, "");
    return file.replace(/_/g, " ");
  }

  function prettyId(id) {
    return String(id).replace(/_/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
  }

  function attrBars(points) {
    const vals = ATTR_ORDER.map((k) => Number(points?.[k] ?? 0));
    const max = Math.max(...vals, 1);
    return ATTR_ORDER.map((k, i) => `
      <div class="ar-attr">
        <span class="ar-attr-name">${ATTR_NAMES[k]}</span>
        <span class="ar-attr-bar"><i style="--w:${Math.round((vals[i] / max) * 100)}%"></i></span>
        <span class="ar-attr-val">${vals[i]}</span>
      </div>`).join("");
  }

  function equipGrid(equipment) {
    return EQUIP_SLOTS.map(([key, label]) => {
      const it = equipment?.[key];
      const name = it ? itemName(it.original_resource_path || it.item_path) : null;
      const rarity = RARITY[it?.rarity] || RARITY[it?.variant?.rarity] || "";
      return `
        <div class="ar-slot ${name ? "filled " + rarity : ""}">
          <span class="ar-slot-type">${label}</span>
          <span class="ar-slot-item">${name ? escapeHtml(name) : "—"}</span>
        </div>`;
    }).join("");
  }

  function abilityChips(abilities) {
    const levels = abilities?.ability_levels || {};
    const upgrades = abilities?.learned_ability_upgrades || {};
    const ids = Object.keys(levels).sort((a, b) => levels[b] - levels[a]);
    if (!ids.length) return '<p class="ar-empty">No abilities learned yet.</p>';
    return ids.map((id) => {
      const up = (upgrades[id] || []).length;
      return `<span class="ar-ability">${escapeHtml(prettyId(id))} <b>${levels[id]}</b>${up ? `<i title="${up} upgrades">✦${up}</i>` : ""}</span>`;
    }).join("");
  }

  function masteryBars(mastery) {
    return WEAPON_KEYS.map((k) => {
      const lvl = mastery?.[k]?.level ?? 0;
      const max = Math.max(...WEAPON_KEYS.map((w) => mastery?.[w]?.level ?? 0), 1);
      return `
        <div class="ar-attr">
          <span class="ar-attr-name">${k.charAt(0).toUpperCase() + k.slice(1)}</span>
          <span class="ar-attr-bar mastery"><i style="--w:${Math.round((lvl / max) * 100)}%"></i></span>
          <span class="ar-attr-val">${lvl}</span>
        </div>`;
    }).join("");
  }

  function renderProfile(d) {
    const quests = d.quests || {};
    const activeQ = Object.keys(quests.active || {}).length;
    const doneQ = (quests.completed || []).length;
    const pets = d.pets || [];
    const hpPct = Math.round((d.current_health / Math.max(d.max_health, 1)) * 100);
    const mpPct = Math.round((d.current_mana / Math.max(d.max_mana, 1)) * 100);
    body.innerHTML = `
      <header class="ar-head">
        <div>
          <h3 class="ar-name">${escapeHtml(d.username)}</h3>
          <p class="ar-sub">${CLASS_ICONS[d.character_type] ?? "✦"} ${className(d.character_type)} · Level ${d.level} · ${escapeHtml(prettyMap(d.last_map))}</p>
        </div>
        <p class="ar-monies">◉ ${Number(d.monies || 0).toLocaleString()}</p>
      </header>

      <div class="ar-vitals">
        <div class="char-bar hp"><i style="width:${hpPct}%"></i></div>
        <div class="ar-vital-nums"><span>HP ${d.current_health} / ${d.max_health}</span></div>
        <div class="char-bar mp"><i style="width:${mpPct}%"></i></div>
        <div class="ar-vital-nums"><span>MP ${d.current_mana} / ${d.max_mana}</span></div>
      </div>

      <div class="ar-cols">
        <section class="ar-sec">
          <h4>Attributes</h4>
          ${attrBars(d.attribute_points)}
        </section>
        <section class="ar-sec">
          <h4>Weapon Mastery</h4>
          ${masteryBars(d.weapon_mastery)}
        </section>
      </div>

      <section class="ar-sec">
        <h4>Equipment</h4>
        <div class="ar-equip">${equipGrid(d.inventory?.equipment)}</div>
      </section>

      <section class="ar-sec">
        <h4>Abilities</h4>
        <div class="ar-abilities">${abilityChips(d.abilities)}</div>
      </section>

      <footer class="ar-foot">
        <span>📜 ${activeQ} active quest${activeQ === 1 ? "" : "s"}, ${doneQ} completed</span>
        <span>🐾 ${pets.length} pet${pets.length === 1 ? "" : "s"}</span>
      </footer>`;
  }

  async function open(username) {
    overlay.hidden = false;
    document.body.style.overflow = "hidden";
    body.innerHTML = '<p class="ar-loading">Unlocking the armory…</p>';
    try {
      const d = await api("/api/player/load", { username });
      if (!d || !d.username) {
        body.innerHTML = `<p class="ar-loading">The ledger holds no record of <strong>${escapeHtml(username)}</strong>.</p>`;
        return;
      }
      renderProfile(d);
    } catch (err) {
      body.innerHTML = `<p class="ar-loading">Couldn't open the armory: ${escapeHtml(err.message)}</p>`;
    }
  }

  function close() {
    overlay.hidden = true;
    document.body.style.overflow = "";
  }

  $("#armory-close").addEventListener("click", close);
  overlay.addEventListener("click", (ev) => { if (ev.target === overlay) close(); });
  addEventListener("keydown", (ev) => { if (ev.key === "Escape" && !overlay.hidden) close(); });

  // event delegation: anything with data-armory opens the profile
  document.addEventListener("click", (ev) => {
    const el = ev.target.closest("[data-armory]");
    if (el) open(el.dataset.armory);
  });
  document.addEventListener("keydown", (ev) => {
    if (ev.key !== "Enter") return;
    const el = ev.target.closest?.("[data-armory]");
    if (el) open(el.dataset.armory);
  });

  return { open };
})();

/* ============================================================
   ACCOUNT — register / login / characters / create
   NOTE: the game API is account_id-based with no tokens (dev
   stack); the id is kept in localStorage as the "session".
   ============================================================ */
const Account = (() => {
  let mode = "login";

  function session() {
    try { return JSON.parse(localStorage.getItem(SESSION_KEY)); } catch (_) { return null; }
  }
  function setSession(s) {
    if (s) localStorage.setItem(SESSION_KEY, JSON.stringify(s));
    else localStorage.removeItem(SESSION_KEY);
    syncUI();
  }

  function syncUI() {
    const s = session();
    $("#auth-panel").hidden = !!s;
    $("#dashboard").hidden = !s;
    $("#account-title").textContent = s ? "Your Wilders" : "Take Up Your Steel";
    $("#nav-account-link").textContent = s ? s.username : "Sign In";
    if (s) {
      $("#dash-username").textContent = s.username;
      loadCharacters();
    }
  }

  /* ----- auth form ----- */
  document.querySelectorAll(".auth-tab").forEach((tab) => {
    tab.addEventListener("click", () => {
      mode = tab.dataset.tab;
      document.querySelectorAll(".auth-tab").forEach((t) => t.classList.toggle("active", t === tab));
      $("#auth-submit").textContent = mode === "login" ? "Sign In" : "Create Account";
      $("#auth-password").autocomplete = mode === "login" ? "current-password" : "new-password";
      $("#auth-error").textContent = "";
    });
  });

  $("#auth-form").addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const btn = $("#auth-submit"), errEl = $("#auth-error");
    const username = $("#auth-username").value.trim();
    const password = $("#auth-password").value;
    errEl.textContent = "";
    btn.disabled = true;
    btn.textContent = mode === "login" ? "Lighting the lantern…" : "Kindling…";
    try {
      let accountId;
      if (mode === "register") {
        const reg = await api("/api/account/register", { username, password });
        accountId = reg.account_id;
      } else {
        const login = await api("/api/account/login", { username, password });
        accountId = login.account_id;
      }
      setSession({ account_id: accountId, username });
      $("#auth-form").reset();
    } catch (err) {
      errEl.textContent = err.message;
    } finally {
      btn.disabled = false;
      btn.textContent = mode === "login" ? "Sign In" : "Create Account";
    }
  });

  $("#logout-btn").addEventListener("click", () => setSession(null));

  /* ----- characters ----- */
  function masteryChips(mastery) {
    return WEAPON_KEYS.map((k) => {
      const lvl = mastery?.[k]?.level ?? 0;
      return `<span class="${lvl > 0 ? "lit" : ""}">${k.charAt(0).toUpperCase() + k.slice(1)} ${lvl}</span>`;
    }).join("");
  }

  function charCard(c, i) {
    const hpPct = Math.min(100, Math.round((c.max_health / 5000) * 100) + 18);
    const mpPct = Math.min(100, Math.round((c.max_mana / 3000) * 100) + 18);
    return `
      <article class="char-card" data-armory="${escapeHtml(c.name)}" tabindex="0" role="button" style="animation-delay:${i * 0.08}s">
        <div class="char-head">
          <span class="char-name" title="${escapeHtml(c.name)}">${escapeHtml(c.name)}</span>
          <span class="char-level">Lv ${c.level}</span>
        </div>
        <p class="char-class">${CLASS_ICONS[c.character_class] ?? "✦"} ${className(c.character_class)}</p>
        <div class="char-bar hp"><i data-w="${hpPct}"></i></div>
        <div class="char-bar mp"><i data-w="${mpPct}"></i></div>
        <div class="char-vitals"><span>HP ${c.max_health}</span><span>MP ${c.max_mana}</span></div>
        <div class="char-mastery">${masteryChips(c.weapon_mastery)}</div>
        <p class="char-monies">◉ ${Number(c.monies || 0).toLocaleString()} monies</p>
      </article>`;
  }

  async function loadCharacters() {
    const s = session();
    if (!s) return;
    const grid = $("#char-grid");
    grid.innerHTML = '<p class="char-empty">Reading the ledger…</p>';
    try {
      const data = await api("/api/account/characters", { account_id: s.account_id });
      const chars = data.characters || [];
      grid.innerHTML = chars.length
        ? chars.map(charCard).join("")
        : '<p class="char-empty">No Wilders yet — kindle your first below.</p>';
      // animate stat bars in after layout
      requestAnimationFrame(() => requestAnimationFrame(() => {
        grid.querySelectorAll(".char-bar i").forEach((bar) => { bar.style.width = bar.dataset.w + "%"; });
      }));
    } catch (err) {
      grid.innerHTML = `<p class="char-empty">Couldn't load characters: ${escapeHtml(err.message)}</p>`;
    }
  }

  /* ----- create character ----- */
  $("#create-form").addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const s = session();
    if (!s) return;
    const errEl = $("#create-error");
    const name = $("#create-name").value.trim();
    const classId = Number(document.querySelector('input[name="cw"]:checked').value);
    errEl.textContent = "";
    try {
      await api("/api/character/create", { account_id: s.account_id, name, class_id: classId });
      $("#create-form").reset();
      loadCharacters();
      Leaderboard.load();
    } catch (err) {
      errEl.textContent = err.message;
    }
  });

  return { syncUI };
})();

/* ---------- boot ---------- */
Account.syncUI();
Leaderboard.load();
