/* One Dinner in New Orleans: the city of lights.
   One canvas, one metaphor. Every light is a restaurant, drawn the way a star atlas draws stars: a flat dot.
     size and brightness = how many reviews it has
     colour              = how it is rated (blue below the city's middle, gold in the best quarter)
     flicker             = how uncertain that rating is
     ring                = it is in the top ten of the current draw
   The picture is a function of the scroll position: every bit of scrolling moves something.
   All numbers come from assets/data/site_data.js, which R/12_site_data.R exports from the
   same result files as the report. */
(() => {
  "use strict";

  const D = window.SITE_DATA, R = D.restaurants, N = D.numbers;
  // no animation for readers who asked their system for less motion (or with ?still in the address)
  const still = matchMedia("(prefers-reduced-motion: reduce)").matches || new URLSearchParams(location.search).has("still");
  const $ = (id) => document.getElementById(id);
  // the page's colours and typefaces are defined once, in site.css; the canvas reads them from there
  const token = (name) => getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  const GROUND = token("--ground") || "#0b0c0e", LAND = "#15161a", INK = "237,236,232", GOLD_CSS = token("--gold") || "#f0a63a";
  const SANS = token("--sans") || "sans-serif", SERIF = token("--serif") || "serif";
  const fmt = (x) => x.toLocaleString("en-US");
  const pct = (x) => Math.round(100 * x) + "%";
  const clamp = (x, a, b) => Math.max(a, Math.min(b, x));
  const lerp = (a, b, t) => a + (b - a) * t;
  const ramp = (x, a, b) => clamp((x - a) / (b - a), 0, 1);              // 0 before a, 1 after b
  const smooth = (t) => t * t * (3 - 2 * t);
  const stagger = (v, order, spread) => clamp(v * (1 + spread) - order * spread, 0, 1);   // lets items take turns
  const WORDS = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten"];
  const NTH = ["", "First", "Second", "Third", "Fourth", "Fifth", "Sixth", "Seventh", "Eighth", "Ninth", "Tenth"];
  const ordinal = (n) => n + (n % 100 >= 11 && n % 100 <= 13 ? "th" : ["th", "st", "nd", "rd"][n % 10] || "th");
  const pretty = (hood) => hood.replace(" - ", "‑").replace("Treme", "Tremé");
  const where = (r) => {                                 // the neighborhood, plus the part of town unless its name already says so
    const hood = pretty(r.hood);
    return r.part.includes(hood.split("‑")[0]) ? hood : `${hood}, ${r.part}`;
  };
  const list = (items) => items.length < 2 ? items.join("") : items.slice(0, -1).join(", ") + " and " + items[items.length - 1];

  /* ---------- geography: longitude and latitude to a flat "world" 1000 units wide ---------- */
  const VIEW = { lonMin: -90.152, lonMax: -89.938, latMin: 29.893, latMax: 30.068 };
  const K = Math.cos((29.98 * Math.PI) / 180), WW = 1000;
  const S = WW / ((VIEW.lonMax - VIEW.lonMin) * K), WH = (VIEW.latMax - VIEW.latMin) * S;
  const wx = (lon) => (lon - VIEW.lonMin) * K * S, wy = (lat) => (VIEW.latMax - lat) * S;

  let seed = 9426;                                       // the project's seed, so the sparks look the same every visit
  const rand = () => { seed |= 0; seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };

  /* ---------- restaurants: what each light looks like ---------- */
  const ratings = R.map((r) => r.avg).sort((a, b) => a - b);
  const middle = ratings[Math.floor(ratings.length / 2)], low10 = ratings[Math.floor(ratings.length * 0.1)];
  const mostReviews = Math.max(...R.map((r) => r.reviews));
  // Blue and gold have the same lightness (checked with a colour-vision simulation: they stay far apart for
  // red-green colour blindness), so colour does not leak into brightness, which belongs to the number of reviews.
  const NEUTRAL = [188, 184, 174], COOL = [138, 176, 255], GOLD = [240, 166, 58], HOT = [242, 150, 44], PLAIN = [214, 212, 205];
  const mix = (a, b, t) => [lerp(a[0], b[0], t), lerp(a[1], b[1], t), lerp(a[2], b[2], t)];

  R.forEach((r, i) => {
    r.name = r.name.replace(/'/g, "’");                                          // a real apostrophe in Gus’s and Brigtsen’s
    r.i = i; r.x = wx(r.lon); r.y = wy(r.lat);
    r.b = Math.sqrt(r.reviews / mostReviews);                                   // 0..1, brightness
    const warmth = r.avg >= middle ? (r.avg - middle) / (N.greatCut - middle) : (r.avg - middle) / (middle - low10);
    r.colour = warmth < 0 ? mix(NEUTRAL, COOL, clamp(-warmth, 0, 1))
             : warmth <= 1 ? mix(NEUTRAL, GOLD, Math.pow(warmth, 0.85))
             : mix(GOLD, HOT, clamp((warmth - 1) / 1.3, 0, 1));
    r.doubt = clamp(((r.high - r.low) / 2 - 0.03) / 0.2, 0.04, 1);             // half-width of the interval, 0..1
    r.phase = rand() * 6.283; r.phase2 = rand() * 6.283; r.speed = 2.1 + rand() * 3.4;
    r.turnLit = rand();                                                         // when it switches on
  });
  // as the reader scrolls, lights take turns: the quiet places brighten first, the best ones turn gold last
  R.slice().sort((a, b) => a.reviews - b.reviews).forEach((r, k) => { r.turnBright = k / (R.length - 1); });
  R.slice().sort((a, b) => a.avg - b.avg).forEach((r, k) => { r.turnWarm = k / (R.length - 1); });
  const paintOrder = R.slice().sort((a, b) => b.reviews - a.reviews);          // big dots first, so small ones are never hidden
  const observedTen = R.filter((r) => r.rank <= 10).map((r) => r.i);
  const regularsTen = R.filter((r) => r.rankAdjusted <= 10).map((r) => r.i);

  /* ---------- parts of town ---------- */
  const P = D.parts.map((p) => {
    const path = new Path2D(); const box = [1e9, 1e9, -1e9, -1e9]; let biggest = 0, center = [0, 0], perimeter = 0;
    p.rings.forEach((ring) => {
      let area = 0, cx = 0, cy = 0, length = 0;
      ring.forEach((pt, j) => {
        const x = wx(pt[0]), y = wy(pt[1]); if (j) path.lineTo(x, y); else path.moveTo(x, y);
        box[0] = Math.min(box[0], x); box[1] = Math.min(box[1], y); box[2] = Math.max(box[2], x); box[3] = Math.max(box[3], y);
        const q = ring[(j + 1) % ring.length], x2 = wx(q[0]), y2 = wy(q[1]), cross = x * y2 - x2 * y;
        area += cross; cx += (x + x2) * cross; cy += (y + y2) * cross; length += Math.hypot(x2 - x, y2 - y);
      });
      path.closePath();
      if (Math.abs(area) > biggest) { biggest = Math.abs(area); center = [cx / (3 * area), cy / (3 * area)]; perimeter = length; }
    });
    return Object.assign({}, p, { path, box, center, perimeter });
  });
  const part = (name) => P.find((p) => p.name === name);
  const compared = P.filter((p) => p.compared).sort((a, b) => b.share - a.share);
  const best = compared[0], second = compared[1], quarter = part("French Quarter");
  const centerParts = ["French Quarter", "CBD / Warehouse District"];
  const water = new Path2D();
  (D.water || []).forEach((w) => w.rings.forEach((ring) => {
    ring.forEach((pt, j) => (j ? water.lineTo(wx(pt[0]), wy(pt[1])) : water.moveTo(wx(pt[0]), wy(pt[1])))); water.closePath();
  }));
  // where to write the two names: in open water, away from the lights
  const riverPoints = (D.water || []).filter((w) => /Mississippi Riv$/.test(w.name || "")).flatMap((w) => w.rings.flat());
  const nearest = (lon, lat) => riverPoints.reduce((best, pt) => (Math.hypot(pt[0] - lon, pt[1] - lat) < Math.hypot(best[0] - lon, best[1] - lat) ? pt : best), riverPoints[0] || [lon, lat]);
  const riverAt = nearest(-90.0445, 29.9445), lakeAt = [-90.062, 30.041];
  function partAt(x, y) {                                // which part of town holds this world point
    const lon = x / (K * S) + VIEW.lonMin, lat = VIEW.latMax - y / S;
    return P.find((p) => p.rings.some((ring) => {
      let inside = false;
      for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
        const a = ring[i], b = ring[j];
        if ((a[1] > lat) !== (b[1] > lat) && lon < ((b[0] - a[0]) * (lat - a[1])) / (b[1] - a[1]) + a[0]) inside = !inside;
      }
      return inside;
    })) || null;
  }
  const union = (boxes, pad) => [Math.min(...boxes.map((b) => b[0])) - pad, Math.min(...boxes.map((b) => b[1])) - pad,
                                 Math.max(...boxes.map((b) => b[2])) + pad, Math.max(...boxes.map((b) => b[3])) + pad];
  const cityBox = [Math.min(...R.map((r) => r.x)) - 46, Math.min(...R.map((r) => r.y)) - 56, Math.max(...R.map((r) => r.x)) + 40, Math.max(...R.map((r) => r.y)) + 46];
  const coreBox = union(compared.filter((p) => p.name !== "Lakeview").map((p) => p.box), 6);
  const centerBox = union(centerParts.map((n) => part(n).box), 34);
  const warmBox = union([best.box, quarter.box, part("CBD / Warehouse District").box], 26);

  /* ---------- canvas and camera ---------- */
  const canvas = $("sky"), ctx = canvas.getContext("2d");
  let vw = 0, vh = 0, dpr = 1, region = { x: 0, y: 0, w: 1, h: 1 }, base = 1, wide = true;
  const cam = { cx: WW / 2, cy: WH / 2, z: 1 };
  const sx = (x) => region.x + region.w / 2 + (x - cam.cx) * cam.z * base;
  const sy = (y) => region.y + region.h / 2 + (y - cam.cy) * cam.z * base;
  function frameBox(b, cap) {
    const z = Math.min(region.w / ((b[2] - b[0]) * base), region.h / ((b[3] - b[1]) * base));
    return { cx: (b[0] + b[2]) / 2, cy: (b[1] + b[3]) / 2, z: clamp(z, 0.6, cap || 3.2) };
  }
  function shot(scene) {                                 // where the camera rests in each scene
    const focus = SCENES[scene].focus;
    return focus === "center" ? frameBox(centerBox, 2.7) : focus === "warm" ? frameBox(warmBox, 2.0)
         : focus === "core" ? frameBox(coreBox, 2.0)
         : focus === "pick" ? { cx: state.pick.x, cy: state.pick.y, z: wide ? 2.1 : 1.7 } : frameBox(cityBox, 1.6);
  }
  let snap = true;
  function resize() {
    dpr = Math.min(window.devicePixelRatio || 1, 2); vw = window.innerWidth; vh = window.innerHeight; wide = vw >= 900;
    canvas.width = Math.round(vw * dpr); canvas.height = Math.round(vh * dpr);
    region = wide ? { x: vw * 0.41, y: vh * 0.09, w: vw * 0.56, h: vh * 0.82 } : { x: vw * 0.03, y: vh * 0.09, w: vw * 0.94, h: vh * 0.44 };
    base = Math.min(region.w / WW, region.h / WH);
    snap = true;
    document.querySelectorAll(".step:not(.hero)").forEach((step) => {
      const copy = step.firstElementChild; copy.classList.remove("tall"); step.style.minHeight = "";
      if (!wide) return;
      const holdAt = parseFloat(getComputedStyle(copy).top) || 0, height = copy.offsetHeight;
      if (holdAt + height > vh - 16) copy.classList.add("tall");              // would not fit while pinned
      else step.style.minHeight = Math.max(vh * 1.5, height + vh * 1.05) + "px";
    });
  }

  /* ---------- scenes ----------
     Each scene is the state the picture reaches by the end of its step. Scrolling through a step moves every
     value from the previous scene's state to this one, each inside its own window (see WINDOWS). */
  const SCENES = [
    /* 0 title    */ { count: 0.42, others: 1, keepers: 1, gather: 0, map: 0.85, lights: 0, bright: 0, warm: 0, flick: 0,    rings: 0, dim: 0, glow: 0, focus: "city",   legend: [] },
    /* 1 all      */ { count: 1,   others: 1, keepers: 1, gather: 0, map: 0.85, lights: 0, bright: 0, warm: 0, flick: 0,    rings: 0, dim: 0, glow: 0, focus: "city",   legend: [] },
    /* 2 filter   */ { count: 1,   others: 0, keepers: 1, gather: 1, map: 1, lights: 0, bright: 0, warm: 0, flick: 0,    rings: 0, dim: 0, glow: 0, focus: "city",   legend: [] },
    /* 3 guess    */ { count: 1,   others: 0, keepers: 0, gather: 1, map: 1,   lights: 1, bright: 0, warm: 0, flick: 0,    rings: 0, dim: 0, glow: 0, focus: "core",   legend: ["lights"] },
    /* 4 bright   */ { count: 1,   others: 0, keepers: 0, gather: 1, map: 1,   lights: 1, bright: 1, warm: 0, flick: 0,    rings: 0, dim: 0, glow: 0, focus: "center", legend: ["lights", "bright"], labels: centerParts, outline: centerParts },
    /* 5 colour   */ { count: 1,   others: 0, keepers: 0, gather: 1, map: 1,   lights: 1, bright: 1, warm: 1, flick: 0,    rings: 0, dim: 0, glow: 0, focus: "core",   legend: ["lights", "bright", "warm"] },
    /* 6 warmest  */ { count: 1,   others: 0, keepers: 0, gather: 1, map: 1,   lights: 1, bright: 1, warm: 1, flick: 0,    rings: 0, dim: 0, glow: 1, focus: "warm",   legend: ["lights", "bright", "warm"], labels: [best.name, "French Quarter"] },
    /* 7 flicker  */ { count: 1,   others: 0, keepers: 0, gather: 1, map: 1,   lights: 1, bright: 1, warm: 1, flick: 1,    rings: 0, dim: 0, glow: 0, focus: "core",   legend: ["lights", "bright", "warm", "flick"] },
    /* 8 top ten  */ { count: 1,   others: 0, keepers: 0, gather: 1, map: 1,   lights: 1, bright: 1, warm: 1, flick: 1,    rings: 1, dim: 0, glow: 0, focus: "city",   legend: ["lights", "bright", "warm", "flick", "rings"] },
    /* 9 regulars */ { count: 1,   others: 0, keepers: 0, gather: 1, map: 1,   lights: 1, bright: 1, warm: 1, flick: 0.35, rings: 1, dim: 0, glow: 0, focus: "city",   legend: ["lights", "bright", "warm", "rings"] },
    /* 10 table   */ { count: 1,   others: 0, keepers: 0, gather: 1, map: 1,   lights: 1, bright: 1, warm: 1, flick: 0,    rings: 1, dim: 1, glow: 0, focus: "pick",   legend: ["lights", "bright", "warm"] },
  ];
  // before the first scroll: a faint city under a thin scatter of sparks. The first movement brings the map up.
  const START = Object.assign({}, SCENES[0], { count: 0.26, map: 0.5 });
  const KEYS = ["count", "others", "keepers", "gather", "map", "lights", "bright", "warm", "flick", "rings", "dim", "glow"];
  const WINDOWS = {                                      // the part of each step (0 = its start, 1 = its end) in which a value changes
    0: { map: [0, 0.45], count: [0, 1] },
    1: { count: [0, 0.8] },
    2: { others: [0, 0.5], gather: [0.28, 0.98], map: [0.2, 0.8] },
    3: { lights: [0, 0.6], keepers: [0.15, 0.6], map: [0, 0.4] },
    4: { bright: [0, 0.75] },
    5: { warm: [0.05, 0.85] },
    6: { glow: [0.05, 0.75] },
    7: { flick: [0, 0.7], glow: [0, 0.25] },
    8: { rings: [0, 0.3] },
    9: { flick: [0, 0.5] },
    10: { dim: [0, 0.5], flick: [0, 0.3] },
  };
  const CAMERA_ARRIVES = 0.62;                           // the camera reaches a scene's framing here, then keeps pushing in slowly
  const now = Object.assign({}, START);                  // what is on screen right now
  const state = { scene: 0, u: 0, guess: null, whose: "everyone", chose: false, sure: true, where: "", turn: 0, pick: R[0], hover: null };

  function goal(scene, u) {                              // the picture this exact scroll position asks for
    const from = scene ? SCENES[scene - 1] : START, to = SCENES[scene], windows = WINDOWS[scene] || {}, out = {};
    KEYS.forEach((k) => { const w = windows[k] || [0, 0.55]; out[k] = lerp(from[k], to[k], smooth(ramp(u, w[0], w[1]))); });
    const a = shot(Math.max(0, scene - 1)), b = shot(scene), t = smooth(ramp(u, 0, CAMERA_ARRIVES));
    const push = 1 + 0.085 * ramp(u, CAMERA_ARRIVES * 0.6, 1);   // a slow push-in, so the map never stands still while scrolling
    out.cx = lerp(a.cx, b.cx, t); out.cy = lerp(a.cy, b.cy, t) - (5 * ramp(u, CAMERA_ARRIVES, 1)) / lerp(a.z, b.z, t);
    out.z = lerp(a.z, b.z, t) * push;
    return out;
  }

  /* ---------- the sparks: one for every thousand reviews in the dataset ---------- */
  const sparkCount = Math.round(N.reviewsRead / 1000), keeperCount = Math.round(N.themeReviews / 1000);
  const sparks = Array.from({ length: sparkCount }, (_, i) => ({
    u: rand(), v: rand(), du: (rand() - 0.5) * 0.006, dv: (rand() - 0.5) * 0.004, size: 0.7 + rand() * 1.5,
    phase: rand() * 6.283, keeper: i < keeperCount, home: R[i % R.length], lag: rand(),
    turnIn: rand(), turnOut: rand(),                     // when it appears, and when it winks out
  }));

  /* ---------- the live redraw: a bootstrap resample of every restaurant, in the browser ---------- */
  const cumulative = R.map((r) => { const n = r.stars.reduce((a, b) => a + b, 0); let s = 0; return { n, c: r.stars.map((v) => (s += v) / n) }; });
  function redrawnTopTen() {
    const means = R.map((r, i) => {
      const { n, c } = cumulative[i]; let total = 0;
      for (let k = 0; k < n; k++) { const u = Math.random(); total += u < c[0] ? 1 : u < c[1] ? 2 : u < c[2] ? 3 : u < c[3] ? 4 : 5; }
      return total / n;
    });
    return R.map((r) => r.i).sort((a, b) => means[b] - means[a]).slice(0, 10);
  }
  const live = { draws: 0, same: 0, kept: new Uint32Array(R.length), order: observedTen.slice(), timer: 0, at: 0, when: 0 };
  const ringNow = new Float32Array(R.length), ringTo = new Float32Array(R.length);
  function setRings(indices) { ringTo.fill(0); indices.forEach((i) => { ringTo[i] = 1; }); }

  const liveRows = new Map();
  function renderLive() {
    const box = $("live"), rowHeight = (box.offsetHeight || 310) / 10;   // the list is shorter on small screens
    liveRows.forEach((row) => row.classList.add("out"));           // a restaurant that drops out fades where it stands
    live.order.forEach((i, place) => {
      let row = liveRows.get(i);
      if (!row) {                                                    // a newcomer fades in at its place
        row = document.createElement("li"); row.className = R[i].rank > 10 ? "new out" : "out";
        row.innerHTML = `<span class="rk"></span><span class="nm">${R[i].name}</span><span class="kp"><i></i><span></span></span>`;
        row.style.transform = `translateY(${place * rowHeight}px)`;
        box.appendChild(row); liveRows.set(i, row); void row.offsetWidth;
      }
      row.classList.remove("out"); row.style.transform = `translateY(${place * rowHeight}px)`;
      row.querySelector(".rk").textContent = place + 1;
      const share = live.draws ? live.kept[i] / live.draws : R[i].chance;
      row.querySelector(".kp i").style.setProperty("--k", share.toFixed(3));
      row.querySelector(".kp span").textContent = live.draws ? `${live.kept[i]}/${live.draws}` : pct(R[i].chance);
    });
    $("liveInfo").textContent = live.draws
      ? `${fmt(live.draws)} reshuffle${live.draws === 1 ? "" : "s"} so far. The original ten came back intact ${live.same === 1 ? "once" : live.same + " times"}. Scroll to shake it again.`
      : "Next to each name: how often it stayed in the top ten across 2,000 reshuffles.";
  }
  function tick() {
    const order = redrawnTopTen();
    live.draws++; order.forEach((i) => live.kept[i]++);
    if (order.every((i) => R[i].rank <= 10)) live.same++;
    live.order = order; live.when = performance.now(); setRings(order); renderLive();
  }

  /* ---------- the table: one restaurant, chosen by a stated rule ---------- */
  function candidates() {
    const pool = R.filter((r) => !state.where || r.part === state.where);
    if (state.sure) return pool.slice().sort((a, b) => b.low - a.low);          // best rating we can be confident of
    const open = pool.filter((r) => r.chance < 0.9).sort((a, b) => b.high - a.high);   // not a sure thing, ordered by how good it could be
    return open.length ? open : pool.slice().sort((a, b) => b.high - a.high);
  }
  function renderTicket(animate) {
    const pool = candidates(), r = pool[state.turn % pool.length]; state.pick = r;
    const regular = `${Math.abs(r.adjusted).toFixed(2)} stars ${r.adjusted >= 0 ? "above" : "below"}`;
    const place = state.turn % pool.length, scope = state.where ? "in this part of town" : "in the city";
    const why = state.sure
      ? `${fmt(r.reviews)} reviews and a ${r.avg.toFixed(2)} average. Even if I read those reviews as pessimistically as the numbers allow, it comes out at ${r.low.toFixed(2)}. ` +
        (place === 0 ? `Nobody ${scope} beats that.` : `That’s the ${ordinal(place + 1)} best ${scope}.`)
      : `Only ${fmt(r.reviews)} reviews, so that ${r.avg.toFixed(2)} could really be anywhere from ${r.low.toFixed(2)} to ${r.high.toFixed(2)}. If it’s the high end, this is one of the best tables in town. ` +
        (r.low >= 4 ? "If it’s the low end, you still ate well." : "If it’s the low end, it’s an ordinary night out.");
    const ticket = $("ticket");
    ticket.innerHTML =
      `<p class="kicker">${state.sure ? "Playing it safe" : "Taking a chance"} · ${NTH[place + 1] ? NTH[place + 1].toLowerCase() + " choice" : "choice " + (place + 1)}</p>` +
      `<h3>${r.name}</h3><p class="place">${where(r)}</p>` +
      `<dl><div><dt>Average rating</dt><dd>${r.avg.toFixed(2)}<small>of 5</small></dd></div>` +
      `<div><dt>Reviews</dt><dd>${fmt(r.reviews)}</dd></div>` +
      `<div><dt>Rank in the city</dt><dd>${r.rank}<small>of ${R.length}</small></dd></div>` +
      `<div><dt>Stays in the top ten</dt><dd>${pct(r.chance)}<small>of reshuffles</small></dd></div></dl>` +
      `<p class="why">${why} Regulars rate it ${regular} their own average.</p>`;
    if (animate) { ticket.classList.remove("swap"); void ticket.offsetWidth; ticket.classList.add("swap"); }
    if (state.scene === 10) setRings([r.i]);
  }

  /* ---------- drawing ---------- */
  function label(text, x, y, strong, alpha, align) {
    const lines = text.toUpperCase().split(" / ");
    ctx.font = `500 10.5px ${SANS}`; ctx.textAlign = align || "center"; ctx.textBaseline = "middle";
    if ("letterSpacing" in ctx) ctx.letterSpacing = "1.2px";
    ctx.globalAlpha = alpha;
    lines.forEach((line, i) => {
      const yy = y + (i - (lines.length - 1) / 2) * 14;
      ctx.lineWidth = 3.5; ctx.strokeStyle = LAND; ctx.strokeText(line, x, yy);
      ctx.fillStyle = `rgba(${INK},${strong ? 0.96 : 0.62})`; ctx.fillText(line, x, yy);
    });
    ctx.globalAlpha = 1; if ("letterSpacing" in ctx) ctx.letterSpacing = "0px";
  }
  function waterName(text, lon, lat, alpha) {            // names of the lake and the river, in italics like on a printed map
    if (alpha < 0.02) return;
    ctx.font = `italic 400 14px ${SERIF}`; ctx.textAlign = "center"; ctx.textBaseline = "middle";
    ctx.fillStyle = `rgba(${INK},${0.4 * alpha})`; ctx.fillText(text, sx(wx(lon)), sy(wy(lat)));
  }
  const MILE = S / 68.9;                                 // one mile, in map units
  function scaleBar(alpha) {                             // a map without a scale cannot say how far anything is
    if (!wide || alpha < 0.02) return;
    const px = MILE * cam.z * base, half = px > 150, length = half ? px / 2 : px;
    const x = vw * 0.56, y = vh - 30;
    ctx.globalAlpha = alpha; ctx.strokeStyle = `rgba(${INK},.5)`; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(x + 0.5, y - 4); ctx.lineTo(x + 0.5, y + 0.5); ctx.lineTo(x + length, y + 0.5); ctx.lineTo(x + length, y - 4); ctx.stroke();
    ctx.font = `400 11.5px ${SANS}`; ctx.textAlign = "left"; ctx.textBaseline = "alphabetic"; ctx.fillStyle = `rgba(${INK},.5)`;
    ctx.fillText(half ? "half a mile" : "1 mile", x, y - 9);
    ctx.globalAlpha = 1;
  }

  let last = 0, shownUp = "", shownDown = "", opener = null;
  function frame(time) {
    const t = time / 1000, dt = Math.min(5, last ? t - last : 0.016); last = t;   // real elapsed time, so a slow device still keeps up
    const sc = SCENES[state.scene], u = still ? 1 : state.u, want = goal(state.scene, u);
    const follow = snap || still ? 1 : 1 - Math.exp(-dt * 9), glide = snap || still ? 1 : 1 - Math.exp(-dt * 5.5);
    KEYS.forEach((k) => { now[k] += (want[k] - now[k]) * follow; });
    cam.cx += (want.cx - cam.cx) * glide; cam.cy += (want.cy - cam.cy) * glide; cam.z += (want.z - cam.z) * glide; snap = false;
    for (let i = 0; i < R.length; i++) ringNow[i] = still ? ringTo[i] : ringNow[i] + (ringTo[i] - ringNow[i]) * (1 - Math.exp(-dt * 5));

    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.globalCompositeOperation = "source-over"; ctx.globalAlpha = 1;
    ctx.fillStyle = GROUND; ctx.fillRect(0, 0, vw, vh);
    const scale = cam.z * base;

    /* the city: land one shade lighter than the water, hairlines between the parts of town */
    if (now.map > 0.01) {
      ctx.save();
      ctx.translate(region.x + region.w / 2, region.y + region.h / 2); ctx.scale(scale, scale); ctx.translate(-cam.cx, -cam.cy);
      ctx.globalAlpha = now.map;
      ctx.fillStyle = LAND; P.forEach((p) => ctx.fill(p.path));
      ctx.lineWidth = 1 / scale; ctx.strokeStyle = `rgba(${INK},.15)`; P.forEach((p) => ctx.stroke(p.path));
      ctx.fillStyle = GROUND; ctx.fill(water);                                 // the lake and the river, cut out of the land
      ctx.lineWidth = 1 / scale; ctx.strokeStyle = `rgba(${INK},.1)`; ctx.stroke(water);
      const appear = smooth(ramp(u, 0.25, 0.6));
      (sc.outline || []).forEach((name) => { ctx.lineWidth = 1 / scale; ctx.strokeStyle = `rgba(${INK},${0.6 * appear})`; ctx.stroke(part(name).path); });
      if (now.glow > 0.01) {                             // the best part of town: a gold line that draws itself as the reader scrolls
        const drawing = state.scene === 6;               // in its own scene the line is drawn; afterwards the whole outline fades
        ctx.globalAlpha = now.map * now.glow * 0.08; ctx.fillStyle = GOLD_CSS; ctx.fill(best.path);
        ctx.globalAlpha = now.map * (drawing ? 1 : now.glow); ctx.lineWidth = 1.5 / scale; ctx.strokeStyle = GOLD_CSS;
        ctx.setLineDash([best.perimeter * (drawing ? now.glow : 1), best.perimeter * 2]); ctx.stroke(best.path); ctx.setLineDash([]);
        ctx.globalAlpha = now.map;
      }
      const picked = state.guess && (state.scene === 3 || state.scene === 6) && part(state.guess);
      if (picked && !(picked === best && state.scene === 6)) { ctx.lineWidth = 1 / scale; ctx.strokeStyle = `rgba(${INK},.9)`; ctx.stroke(picked.path); }
      ctx.restore();
    }

    /* the sparks: they arrive as the reader scrolls, drift with the page, then wink out or fly to the city */
    if (now.others > 0.01 || now.keepers > 0.01) {
      ctx.fillStyle = `rgb(${INK})`;
      const drift = still ? 0 : window.scrollY / vh;
      for (let i = 0; i < sparks.length; i++) {
        const s = sparks[i];
        const present = ramp(now.count, s.turnIn - 0.03, s.turnIn + 0.03) * (s.keeper ? now.keepers : ramp(now.others, s.turnOut - 0.04, s.turnOut + 0.04));
        if (present < 0.01) continue;
        if (!still) { s.u = (s.u + s.du * dt + 1) % 1; s.v = (s.v + s.dv * dt + 1) % 1; }
        let x = s.u * vw, y = ((((s.v - drift * 0.05 * s.size) % 1) + 1) % 1) * vh;    // nearer sparks slide faster: depth
        if (s.keeper && now.gather > 0.001) {
          const g = clamp(now.gather * 1.7 - s.lag * 0.7, 0, 1), e = g * g * (3 - 2 * g);
          x = lerp(x, sx(s.home.x), e); y = lerp(y, sy(s.home.y), e);
        }
        ctx.globalAlpha = present * (0.3 + 0.7 * (0.5 + 0.5 * Math.sin(t * 1.3 + s.phase)));
        ctx.fillRect(x, y, s.size, s.size);
      }
      ctx.globalAlpha = 1;
    }

    /* the title screen shows one gold dot: the table this page ends on */
    if (state.scene === 0 && !still && opener && now.map > 0.05) {
      const a = 1 - smooth(ramp(u, 0.05, 0.6));
      if (a > 0.01) {
        const x = sx(opener.x), y = sy(opener.y);
        ctx.globalAlpha = a; ctx.fillStyle = GOLD_CSS; ctx.beginPath(); ctx.arc(x, y, 4, 0, 6.2832); ctx.fill();
        ctx.lineWidth = 1; ctx.strokeStyle = GOLD_CSS; ctx.globalAlpha = a * 0.55; ctx.beginPath(); ctx.arc(x, y, 10, 0, 6.2832); ctx.stroke();
        ctx.globalAlpha = 1;
      }
    }

    /* the lights: flat dots, as in a star atlas. Bigger and brighter with more reviews. */
    if (now.lights > 0.01) {
      const zoom = Math.sqrt(cam.z) * (wide ? 1 : 0.8);
      for (let k = 0; k < paintOrder.length; k++) {
        const r = paintOrder[k], x = sx(r.x), y = sy(r.y);
        const lit = stagger(now.lights, r.turnLit, 1.3);
        if (lit < 0.01 || x < -40 || y < -40 || x > vw + 40 || y > vh + 40) { r.sr = 0; continue; }
        const turnedUp = stagger(now.bright, r.turnBright, 0.9), coloured = stagger(now.warm, r.turnWarm, 1.1);
        const flicker = 1 - now.flick * r.doubt * 0.9 * (0.5 + 0.5 * Math.sin(t * r.speed + r.phase)) * (0.55 + 0.45 * Math.sin(t * r.speed * 0.37 + r.phase2));
        const chosen = state.scene === 10 && r === state.pick;
        const alpha = lit * lerp(0.82, 0.7 + 0.3 * Math.sqrt(r.b), turnedUp) * flicker * (chosen ? 1 : 1 - 0.84 * now.dim);
        // a dot swells for a moment as it switches on, and again as it turns gold
        const swell = 1 + 0.45 * Math.sin(Math.PI * lit) + (r.great ? 0.3 * Math.sin(Math.PI * coloured) : 0);
        const radius = (1.6 + 7 * lerp(0.14, r.b, turnedUp)) * zoom * swell;
        const colour = mix(PLAIN, r.colour, coloured);
        ctx.beginPath(); ctx.arc(x, y, radius, 0, 6.2832);
        ctx.globalAlpha = Math.min(1, alpha); ctx.fillStyle = `rgb(${colour[0] | 0},${colour[1] | 0},${colour[2] | 0})`; ctx.fill();
        ctx.globalAlpha = lit * (1 - 0.7 * now.dim) * 0.8; ctx.lineWidth = 0.75; ctx.strokeStyle = LAND; ctx.stroke();   // a hairline of night keeps neighbours apart
        r.sx = x; r.sy = y; r.sr = radius;
      }
      ctx.globalAlpha = 1;

      /* rings: the top ten of the current draw */
      const pulse = still ? 0 : Math.max(0, 1 - (time - live.when) / 500);       // rings breathe once at each new draw
      for (let i = 0; i < R.length; i++) {
        const a = ringNow[i] * now.rings * now.lights; if (a < 0.02 || !R[i].sr) continue;
        const r = R[i], radius = Math.max(7, r.sr + 4.5) + (state.scene === 8 ? 4 * pulse : 0);
        ctx.lineWidth = 1; ctx.strokeStyle = `rgba(${INK},${a})`;
        if (still && state.scene === 8 && r.chance < 0.9) ctx.setLineDash([3, 3]);
        ctx.beginPath(); ctx.arc(r.sx, r.sy, radius, 0, 6.2832); ctx.stroke(); ctx.setLineDash([]);
      }
      if (state.hover && state.hover.sr) { ctx.lineWidth = 1; ctx.strokeStyle = `rgba(${INK},.8)`; ctx.beginPath(); ctx.arc(state.hover.sx, state.hover.sy, state.hover.sr + 3.5, 0, 6.2832); ctx.stroke(); }
    }

    /* the lake and the river are named while the whole city is in view */
    if (now.map > 0.05) {
      const wideView = now.map * ramp(2.0 - cam.z, 0, 0.5) * (1 - 0.75 * now.dim) * (state.scene === 0 && !still ? smooth(ramp(u, 0.45, 1)) : 1);
      waterName("Lake Pontchartrain", lakeAt[0], lakeAt[1], wideView);
      if (riverPoints.length) waterName("Mississippi River", riverAt[0] + 0.012, riverAt[1] - 0.006, wideView);
    }

    /* names on the map fade in once the camera has arrived */
    if (now.map > 0.6) {
      const appear = smooth(ramp(u, 0.3, 0.6));
      (sc.labels || []).forEach((name) => {             // the two center labels sit outside the crowd of dots, above and below it
        const p = part(name);
        if (name === "French Quarter" && state.scene === 6) { label(name, sx(p.box[2]) + 12, sy(p.box[3]) - 4, false, appear, "left"); return; }   // off its corner, over the river
        const shift = name === "French Quarter" ? -30 : name.startsWith("CBD") ? 40 : 0;
        label(name, sx(p.center[0]) + (shift > 0 && state.scene === 4 ? -18 * cam.z : 0), sy(p.center[1]) + shift * Math.sqrt(cam.z), name === best.name && state.scene === 6, appear);
      });
      if (state.guess && state.scene === 3) { const p = part(state.guess); label(state.guess, sx(p.center[0]), sy(p.center[1]), true, 1); }
      if (state.scene === 10 && state.pick.sr) label(state.pick.name, state.pick.sx, state.pick.sy - state.pick.sr - 16, true, still ? 1 : now.dim);
    }
    scaleBar(now.map * now.lights * (1 - now.dim));

    /* the two counters follow the sparks: reviews pour in, then most of them leave */
    if (state.scene <= 3) {
      const arriving = now.count > 0.995 ? N.reviewsRead : Math.round(now.count * sparkCount) * 1000;
      const remaining = now.others < 0.005 ? N.themeReviews : Math.round(N.themeReviews + (N.reviewsRead - N.themeReviews) * now.others);
      if (fmt(arriving) !== shownUp) $("countUp").textContent = shownUp = fmt(arriving);
      if (fmt(remaining) !== shownDown) $("countDown").textContent = shownDown = fmt(remaining);
    }
    $("bars").style.setProperty("--grow", (state.scene > 6 || still ? 1 : state.scene === 6 ? smooth(ramp(u, 0.15, 0.8)) : 0).toFixed(3));
    requestAnimationFrame(frame);
  }

  /* ---------- reacting to the reader ---------- */
  const steps = Array.from(document.querySelectorAll(".step"));
  function enter(scene) {                                // the things that switch once per scene, not continuously
    const before = state.scene; state.scene = scene;
    const sc = SCENES[scene];
    document.querySelectorAll("#legend li").forEach((li) => li.classList.toggle("on", sc.legend.includes(li.dataset.key)));
    canvas.style.cursor = scene === 3 ? "crosshair" : "default";
    clearInterval(live.timer);
    if (scene === 8) {
      if (still) { live.order = observedTen.slice(); setRings(observedTen); renderLive(); }
      else { tick(); live.at = window.scrollY; live.timer = setInterval(() => { if (performance.now() - live.when > 900) tick(); }, 300); }
    }
    else if (scene === 9) setRings(state.whose === "regulars" ? regularsTen : observedTen);
    else if (scene === 10) setRings([state.pick.i]);
    else setRings(observedTen);
    if (before === 8 && scene !== 8) live.order = observedTen.slice();
    $("tip").hidden = true; state.hover = null;
  }
  function whose(who, byHand) {
    state.whose = who; if (byHand) state.chose = true;
    $("everyone").setAttribute("aria-pressed", String(who === "everyone")); $("regulars").setAttribute("aria-pressed", String(who === "regulars"));
    if (state.scene === 9) setRings(who === "regulars" ? regularsTen : observedTen);
  }

  function onScroll() {
    let scene = 0, u = 0;
    steps.forEach((step) => {
      const box = step.getBoundingClientRect();
      if (box.top <= vh * 0.55) { scene = +step.dataset.scene; u = clamp((vh * 0.55 - box.top) / box.height, 0, 1); }
      if (wide && !still && !step.classList.contains("hero")) {       // the text rises into place, holds, and lifts away at the end of its step
        const copy = step.firstElementChild, holdAt = parseFloat(getComputedStyle(copy).top) || 0;
        const pinned = !copy.classList.contains("tall");
        const arriving = smooth(ramp(vh * 0.96 - box.top, 0, vh * 0.42));
        const leaving = pinned ? smooth(ramp(box.bottom - (holdAt + copy.offsetHeight), 0, vh * 0.22)) : smooth(ramp(box.bottom - vh * 0.12, 0, vh * 0.3));
        copy.style.opacity = Math.min(arriving, leaving).toFixed(3);
        copy.style.transform = `translateY(${((1 - arriving) * 44 - (1 - leaving) * 44).toFixed(1)}px)`;
      }
    });
    if (scene === 0) u = clamp(window.scrollY / Math.max(1, steps[1].offsetTop - vh * 0.55), 0, 1);
    if (!still) {                                        // the title drifts up and fades as the reader leaves it
      const hero = steps[0].firstElementChild, gone = clamp(window.scrollY / (vh * 0.42), 0, 1);
      hero.style.opacity = (1 - gone).toFixed(3); hero.style.transform = `translateY(${(-gone * 70).toFixed(1)}px)`;
    }
    state.u = u;
    if (scene !== state.scene) enter(scene);
    if (scene === 8 && !still && Math.abs(window.scrollY - live.at) > 95) { live.at = window.scrollY; tick(); }   // scrolling shakes the ranking
    if (scene === 9 && !state.chose && !still) { const who = u > 0.5 ? "regulars" : "everyone"; if (who !== state.whose) whose(who, false); }

    const story = document.querySelector(".story"), span = story.offsetHeight - vh;
    $("progress").style.transform = `scaleX(${clamp(window.scrollY / span, 0, 1)})`;
    const ending = document.querySelector(".end").getBoundingClientRect().top;     // the plain list covers the map: put the legend away
    document.body.classList.toggle("at-end", ending < 70);
    $("legend").classList.toggle("on", ending >= vh * 0.85 && SCENES[state.scene].legend.length > 0);
  }

  function world(ev) {
    return [(ev.clientX - region.x - region.w / 2) / (cam.z * base) + cam.cx, (ev.clientY - region.y - region.h / 2) / (cam.z * base) + cam.cy];
  }
  canvas.addEventListener("click", (ev) => {
    if (state.scene !== 3) return;
    const [x, y] = world(ev), p = partAt(x, y), box = $("guess");
    if (!p) { box.innerHTML = `<div class="verdict"><div><h3>That’s water, or it’s outside the city.</h3><p>Try a spot on the land.</p></div></div>`; return; }
    state.guess = p.name;
    const answer = p.compared
      ? `<div class="big">${pct(p.share)}</div><div><h3>${p.name}. Noted.</h3><p>That number is the share of its restaurants that turn out to be among the city’s best. Keep scrolling and you’ll see how it stacks up.</p></div>`
      : `<div><h3>${p.name}. Noted.</h3><p>${p.restaurants ? `Only ${p.restaurants} of the ranked restaurants ${p.restaurants === 1 ? "is" : "are"} out here` : "None of the ranked restaurants are out here"}, which is too few to say anything about the area. Keep scrolling.</p></div>`;
    box.innerHTML = `<div class="verdict">${answer}</div>`;
    $("guessRecall").innerHTML = p.name === best.name ? `That was your pick. Nice.`
      : p.compared ? `You picked ${p.name}: <b>${p.great} of ${p.restaurants}</b>.` : `You picked ${p.name}, which has too few ranked restaurants to compare.`;
    document.querySelectorAll("#bars .name i").forEach((tag) => tag.remove());
    const row = document.querySelector(`#bars [data-part="${CSS.escape(p.name)}"] .name`);
    if (row) row.insertAdjacentHTML("beforeend", "<i>your pick</i>");
  });
  canvas.addEventListener("mousemove", (ev) => {
    const tip = $("tip");
    if (state.scene < 4 || now.lights < 0.6) { tip.hidden = true; state.hover = null; return; }
    let nearest = null, distance = 1e9;                  // the dot under the pointer, or the closest one within a few pixels
    for (const r of R) { if (!r.sr) continue; const d = Math.hypot(r.sx - ev.clientX, r.sy - ev.clientY) - r.sr; if (d < 7 && d < distance) { distance = d; nearest = r; } }
    state.hover = nearest; canvas.style.cursor = nearest ? "pointer" : "default";
    if (!nearest) { tip.hidden = true; return; }
    const rating = state.scene >= 5 ? `${nearest.avg.toFixed(2)} stars, ` : "";
    tip.innerHTML = `<b>${nearest.name}</b><span>${rating}${fmt(nearest.reviews)} reviews</span><span>${where(nearest)}</span>`;
    tip.hidden = false;
    tip.style.left = Math.min(ev.clientX + 16, vw - 256) + "px"; tip.style.top = Math.min(ev.clientY + 16, vh - 96) + "px";
  });
  canvas.addEventListener("mouseleave", () => { $("tip").hidden = true; state.hover = null; });

  $("everyone").addEventListener("click", () => whose("everyone", true));
  $("regulars").addEventListener("click", () => whose("regulars", true));
  function press(on, off, action) { $(on).addEventListener("click", () => { $(on).setAttribute("aria-pressed", "true"); $(off).setAttribute("aria-pressed", "false"); action(); }); }
  press("safe", "gamble", () => { state.sure = true; state.turn = 0; renderTicket(true); });
  press("gamble", "safe", () => { state.sure = false; state.turn = 0; renderTicket(true); });
  $("again").addEventListener("click", () => { state.turn++; renderTicket(true); });
  $("where").addEventListener("change", (ev) => { state.where = ev.target.value; state.turn = 0; renderTicket(true); });

  /* ---------- the words that depend on the data ---------- */
  function write() {
    document.querySelectorAll("[data-n]").forEach((node) => { const v = N[node.dataset.n]; node.textContent = "plain" in node.dataset ? v : fmt(v); });
    const center = R.filter((r) => centerParts.includes(r.part)), reviews = (rows) => rows.reduce((a, r) => a + r.reviews, 0);
    $("centerShare").textContent = pct(center.length / R.length);
    $("centerReviews").textContent = pct(reviews(center) / reviews(R));
    $("greatCount").textContent = R.filter((r) => r.great).length;
    $("greatCut").textContent = N.greatCut.toFixed(2);
    $("centerAvg").textContent = N.centerAverage.toFixed(2); $("restAvg").textContent = N.restAverage.toFixed(2);
    $("bestName").textContent = list(best.name.replace(/-/g, "‑").split(" / ")) + ".";   // a hyphen that does not break across lines
    $("bestGreat").textContent = best.great; $("bestCount").textContent = best.restaurants;
    $("fqGreat").textContent = quarter.great; $("fqCount").textContent = quarter.restaurants;
    $("runnerUp").textContent = `I wouldn’t swear to first place: ${second.name} is right behind (${second.great} of ${second.restaurants}), and when I reshuffle the restaurants this district wins ${pct(best.chanceFirst)} of the time. Both beat the French Quarter in at least ${pct(Math.min(best.beatsQuarter, second.beatsQuarter))} of reshuffles.`;
    const busiest = R.reduce((a, r) => (r.reviews > a.reviews ? r : a));
    $("steady").textContent = `${busiest.name}, with ${fmt(busiest.reviews)} reviews, hardly moves.`;
    $("surePlaces").textContent = WORDS[N.surePlaces] || N.surePlaces;
    $("fewest").textContent = Math.min(...R.map((r) => r.reviews));
    $("lastMonth").textContent = N.lastMonth; $("lastMonth2").textContent = N.lastMonth;
    $("countUp").textContent = fmt(N.reviewsRead); $("countDown").textContent = fmt(N.themeReviews);

    $("bars").innerHTML = compared.map((p) =>
      `<div class="bar-row${p === best ? " lead" : ""}" data-part="${p.name}"><span class="name">${p.name}</span>` +
      `<span class="track"><span class="fill" style="width:${clamp(p.share / 0.45, 0, 1) * 100}%"></span></span><span class="value">${pct(p.share)}</span></div>`).join("");

    const stay = observedTen.filter((i) => regularsTen.includes(i)).length;
    $("stayCount").textContent = WORDS[stay] || stay;
    const leaving = observedTen.filter((i) => !regularsTen.includes(i)).map((i) => `${R[i].name} (down to ${ordinal(R[i].rankAdjusted)})`);
    const arriving = regularsTen.filter((i) => !observedTen.includes(i)).map((i) => `${R[i].name} (${ordinal(R[i].rank)} before)`);
    $("movers").textContent = `${list(leaving)} drop${leaving.length === 1 ? "s" : ""} out. ${list(arriving)} move${arriving.length === 1 ? "s" : ""} in.`;

    const counts = {}; R.forEach((r) => { counts[r.part] = (counts[r.part] || 0) + 1; });
    $("where").innerHTML = `<option value="">the whole city (${R.length})</option>` +
      Object.keys(counts).sort((a, b) => counts[b] - counts[a]).map((name) => `<option value="${name}">${name} (${counts[name]})</option>`).join("");

    $("ten").innerHTML = R.filter((r) => r.rank <= 10).map((r) =>
      `<li><span class="rk">${r.rank}</span><span class="nm">${r.name}<small>${where(r)}</small></span><span class="dots" aria-hidden="true"></span>` +
      `<span class="num stars">${r.avg.toFixed(2)}</span><span class="num reviews">${fmt(r.reviews)}</span>` +
      `<span class="num chance">${pct(r.chance)}</span></li>`).join("");
    renderLive(); renderTicket(false);
  }

  let queued = false;                                    // at most one measurement per frame, however fast the wheel turns
  const scrolled = () => { if (queued) return; queued = true; requestAnimationFrame(() => { queued = false; onScroll(); }); };

  write(); opener = state.pick; resize(); setRings(observedTen); enter(0); onScroll();
  window.addEventListener("resize", () => { resize(); onScroll(); });
  window.addEventListener("scroll", scrolled, { passive: true });
  requestAnimationFrame(frame);
})();
