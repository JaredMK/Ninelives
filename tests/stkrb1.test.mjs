// STKRB1 — the sticker-apply picker internals rebuild (batched grid open,
// targeted confirm update, flatter in-picker chip paint) + Stats write
// coalescing.
//
// Step 0 profiling found the apply JS is µs-scale; the seconds lived in the
// SHARED RENDER LAYER: (1) the picker grid mounted all N card buttons on open
// AND re-mounted them on every modifying-sticker confirm (a full-grid
// style/layout/paint per tap), (2) btn.scrollIntoView forced a SYNCHRONOUS
// layout on the confirm tap frame, (3) Stats.bump did a synchronous
// localStorage round-trip (+ iOS native bridge post) per call.
//
// The rebuild: renderStickerApplyCards mounts the first APPLY_FIRST_BATCH
// cards synchronously and streams the rest in generation-guarded rAF chunks
// (close/re-open cancels — the pregenBuildId idiom, no setInterval); the
// modifying/strip confirms update ONLY the touched card through the sig cache
// (updateApplyCardInPlace: one rebuild + one move + O(N) classList-only
// eligibility sync) and never force layout on the tap frame (the one
// bring-into-view rides a rAF and only fires when the card is actually
// outside the visible window); .sa-lite flattens .dcs chip paint INSIDE the
// picker grid only; Stats put() schedules ONE trailing 250ms debounced write
// with Stats.flush() at the durability points (flushCampaignSave).
//
// This suite: (a) structural pins on the new wiring (stklag1/2 idiom);
// (b) behavioral — the extracted picker region driven with a fake DOM proves
// the batching (first chunk sync, rest in rAF chunks, generation/hidden
// guards cancel), the node-reuse cache, and the targeted single-card confirm
// update (one createElement, one move, no full re-mount); (c) behavioral —
// the extracted Stats IIFE driven with fake timers + a counting storage
// proves write coalescing, live reads, and the synchronous flush.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { makeRunner } from "./_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

function fullHtml() {
  return readFileSync(join(HERE, "..", "index.html"), "utf8");
}
function gameScript(html) {
  const blocks = html.match(/<script>([\s\S]*?)<\/script>/g) || [];
  return blocks
    .map((b) => b.replace(/^<script>/, "").replace(/<\/script>$/, ""))
    .find((c) => c.includes("const GameEngine")) || "";
}
function fnBody(src, name) {
  const at = src.indexOf("function " + name + "(");
  if (at === -1) return "";
  const open = src.indexOf("{", at);
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === "{") depth++;
    else if (src[i] === "}" && --depth === 0) return src.slice(open, i + 1);
  }
  return "";
}
function countOf(hay, needle) {
  let n = 0, i = 0;
  while ((i = hay.indexOf(needle, i)) !== -1) { n++; i += needle.length; }
  return n;
}
/** The contiguous picker-internals region (SUIT_ORDER … updateApplyCardInPlace),
    extracted so it can be driven with a fake DOM. (The SUIT_ORDER anchor is the
    picker's own one-line const — the deck inspector scopes a different one.) */
function pickerRegion(src) {
  const end = src.indexOf("/* Move the .sa-selected ring");
  // The deck inspector scopes an identical SUIT_ORDER line — take the one
  // immediately BEFORE the picker region's end anchor.
  const at = end === -1 ? -1 : src.lastIndexOf('const SUIT_ORDER = { "♠": 0, "♥": 1, "♣": 2, "♦": 3 };', end);
  if (at === -1 || end === -1 || end <= at) return "";
  return src.slice(at, end);
}
/** The Stats IIFE source (`const Stats = (() => { … })();`). */
function statsSource(src) {
  const at = src.indexOf("const Stats = (() => {");
  if (at === -1) return "";
  const open = src.indexOf("{", at);
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === "{") depth++;
    else if (src[i] === "}" && --depth === 0) {
      if (src.slice(i + 1, i + 5) !== ")();") return "";
      return src.slice(at, i + 5);
    }
  }
  return "";
}

/* ---- minimal fake DOM (nodes track children/parent/classList/attrs; the
   innerHTML setter counts PARSES; fragments splice like the real thing) ---- */
function makeFakeDom() {
  const created = [];
  let parses = 0;
  function mkNode(tag) {
    return {
      tag, children: [], parent: null, className: "", dataset: {}, _attrs: {}, _cls: null, _html: "",
      get parentNode() { return this.parent; },
      get classList() {
        if (!this._cls) this._cls = new Set((this.className || "").split(/\s+/).filter(Boolean));
        const s = this._cls;
        return {
          add: (...c) => c.forEach((x) => s.add(x)),
          remove: (...c) => c.forEach((x) => s.delete(x)),
          toggle: (c, f) => { if (f === undefined) f = !s.has(c); if (f) s.add(c); else s.delete(c); },
          contains: (c) => s.has(c),
        };
      },
      setAttribute(k, v) { this._attrs[k] = String(v); },
      removeAttribute(k) { delete this._attrs[k]; },
      set innerHTML(v) { parses++; this._html = String(v); },
      get innerHTML() { return this._html; },
      _detach(n) {
        if (n && n.parent) {
          const i = n.parent.children.indexOf(n);
          if (i !== -1) n.parent.children.splice(i, 1);
          n.parent = null;
        }
      },
      appendChild(n) {
        if (n && n._isFrag) {
          const kids = n.children.slice();
          n.children.length = 0;
          kids.forEach((k) => this.appendChild(k));
          return n;
        }
        this._detach(n);
        this.children.push(n);
        n.parent = this;
        return n;
      },
      insertBefore(n, ref) {
        if (n && n._isFrag) {
          const kids = n.children.slice();
          n.children.length = 0;
          kids.forEach((k) => this.insertBefore(k, ref));
          return n;
        }
        this._detach(n);
        const j = ref == null ? -1 : this.children.indexOf(ref);
        if (j === -1) this.children.push(n); else this.children.splice(j, 0, n);
        n.parent = this;
        return n;
      },
      replaceChildren(...nodes) {
        this.children.forEach((c) => { c.parent = null; });
        this.children = [];
        nodes.forEach((n) => this.appendChild(n));
      },
      removeChild(n) {
        const i = this.children.indexOf(n);
        if (i !== -1) { this.children.splice(i, 1); n.parent = null; }
        return n;
      },
      get isConnected() { return true; },
    };
  }
  const document = {
    createElement: (t) => { const n = mkNode(t); created.push(n); return n; },
    createDocumentFragment: () => ({
      _isFrag: true, children: [],
      appendChild(n) { this.children.push(n); return n; },
    }),
  };
  return { document, created, parses: () => parses, mkNode };
}
function makeDeck(n) {
  const suits = ["♠", "♥", "♣", "♦"];
  const deck = [];
  for (let i = 0; i < n; i++)
    deck.push({ id: i, currentRank: (i % 13) + 2, suit: suits[i % 4], stickers: [] });
  return deck;
}
const SORT_KEY = (c) => c.currentRank * 10 + { "♠": 0, "♥": 1, "♣": 2, "♦": 3 }[c.suit];
/** Build the extracted picker region over a fake DOM. `opts.canApply(c)` is
    read LIVE at every eligibility check (tests mutate it between calls). */
function buildPicker(src, deck, opts = {}) {
  const region = pickerRegion(src);
  if (!region) throw new Error("picker region anchors not found");
  const dom = makeFakeDom();
  let rafQ = [];
  let modalHidden = true;
  const el = {
    saCards: dom.mkNode("div"),
    stickerApplyModal: { classList: { contains: (c) => c === "hidden" && modalHidden } },
  };
  const campaign = {
    getRunDeckLive: () => deck,
    canApplySticker: (c, t) => (opts.canApply ? opts.canApply(c, t) : true),
    getCardById: (id) => deck.find((c) => c.id === id) || null,
  };
  const factory = new Function(
    "campaign", "el", "document", "requestAnimationFrame", "miniCardHtml",
    "cardPickMode", "pendingApplyStickerId", "selectedApplyCardId",
    region + "\n;return { renderStickerApplyCards, drainApplyGrid, refreshApplyEligibility,"
    + " updateApplyCardInPlace, applyCardNodes, FIRST: APPLY_FIRST_BATCH, CHUNK: APPLY_CHUNK,"
    + " _gen: () => applyGridGen, _appended: () => applyGridAppended, _bump: () => { applyGridGen++; } };");
  const api = factory(
    campaign, el, dom.document,
    (fn) => { rafQ.push(fn); return rafQ.length; },
    (c) => "<i>" + c.id + "</i>",
    opts.mode || "sticker", "rankUp", null);
  return {
    api, el, dom,
    rafPending: () => rafQ.length,
    fire: () => { const q = rafQ; rafQ = []; q.forEach((f) => f()); },
    setModalHidden: (h) => { modalHidden = h; },
  };
}
/** Build the extracted Stats IIFE over a counting storage + fake timers. */
function buildStats(src) {
  const ss = statsSource(src);
  if (!ss) throw new Error("Stats IIFE anchors not found");
  let timers = [], nextId = 1;
  const setT = (fn) => { const id = nextId++; timers.push({ id, fn }); return id; };
  const clrT = (id) => { timers = timers.filter((t) => t.id !== id); };
  const fire = () => { const t = timers; timers = []; t.forEach((x) => x.fn()); };
  const data = {};
  let writes = 0;
  const storage = {
    getItem: (k) => (k in data ? data[k] : null),
    setItem: (k, v) => { writes++; data[k] = String(v); },
    removeItem: (k) => { delete data[k]; },
  };
  const Stats = new Function("localStorage", "setTimeout", "clearTimeout", ss + "\n;return Stats;")(storage, setT, clrT);
  return { Stats, storage, fire, pending: () => timers.length, writes: () => writes, blob: () => data["ninelives.stats.v1"] };
}

export function run() {
  const r = makeRunner("stkrb1.test.mjs");
  const html = fullHtml();
  const src = gameScript(html);
  const render = fnBody(src, "renderStickerApplyCards");
  const drain = fnBody(src, "drainApplyGrid");
  const eligSync = fnBody(src, "refreshApplyEligibility");
  const targeted = fnBody(src, "updateApplyCardInPlace");
  const confirm = fnBody(src, "confirmApplySticker");
  const closeFn = fnBody(src, "closeStickerApply");
  const flush = fnBody(src, "flushCampaignSave");
  const stats = statsSource(src);
  r.ok(!!(render && drain && eligSync && targeted && confirm && stats), "the STKRB1 wiring extracts cleanly");

  // ── Structural: batched open --------------------------------------------
  {
    r.ok(render.includes("const gen = ++applyGridGen;"),
      "renderStickerApplyCards arms a fresh generation per open (kills stale chunks)");
    r.ok(render.includes("Math.min(APPLY_FIRST_BATCH, order.length)") && render.includes("el.saCards.replaceChildren(frag)"),
      "…the first batch mounts synchronously (one replaceChildren)");
    r.ok(render.includes("Math.min(applyGridAppended + APPLY_CHUNK, order.length)")
      && render.includes("requestAnimationFrame(step)"),
      "…the rest streams in rAF chunks of APPLY_CHUNK");
    r.ok(render.includes("if (gen !== applyGridGen) return;"),
      "…chunks are generation-guarded (stale streams self-terminate)");
    r.ok(render.includes('el.stickerApplyModal.classList.contains("hidden")'),
      "…and stop once the picker modal is hidden (close cancels)");
    r.ok(!pickerRegion(src).includes("setInterval("),
      "…no setInterval anywhere in the picker internals (one animation clock)");
    r.ok(closeFn.includes("applyGridGen++"),
      "closeStickerApply cancels a pending mount stream");
    r.ok(drain.includes("applyGridGen++") && drain.includes("applyGridAppended = applyGridOrder.length"),
      "drainApplyGrid finishes the mount synchronously + cancels the stream (confirm path)");
  }

  // ── Structural: targeted confirm update ---------------------------------
  {
    r.eq(countOf(targeted, "createElement"), 1,
      "updateApplyCardInPlace builds at most ONE button (the touched card, via the sig cache)");
    r.ok(targeted.includes("campaign.getCardById(cardId)") && targeted.includes("drainApplyGrid()")
      && targeted.includes("el.saCards.insertBefore(btn, before)") && targeted.includes("refreshApplyEligibility()"),
      "…rebuild-one + move-to-sorted-slot + classList-only eligibility sync");
    r.ok(!targeted.includes("replaceChildren(") && !targeted.includes("scrollIntoView("),
      "…no full re-mount, no forced layout");
    r.ok(!eligSync.includes("innerHTML"),
      "refreshApplyEligibility never re-parses (classList + attribute only)");
    r.ok(confirm.includes("updateApplyCardInPlace(flashId)") && confirm.includes("updateApplyCardInPlace(stripId)"),
      "the modifying-sticker AND Cleanse-strip confirms both ride the targeted update");
    r.ok(!confirm.includes("renderStickerApplyCards("),
      "…no confirm path re-renders the whole grid");
    const rafAt = confirm.indexOf("requestAnimationFrame(() => {");
    r.ok(rafAt !== -1 && rafAt < confirm.indexOf("scrollIntoView"),
      "the one bring-into-view rides a rAF after the tap frame");
    r.ok(confirm.includes("if (bR.top < cR.top || bR.bottom > cR.bottom)"),
      "…and only fires when the card is actually outside the visible window");
  }

  // ── Structural: .sa-lite scoped to the picker grid -----------------------
  {
    r.ok(html.includes('class="deck-cards sa-cards sa-lite" id="saCards"'),
      "the picker grid carries the .sa-lite scope class");
    const rules = html.match(/\.sa-lite[^{\n]*\{/g) || [];
    r.ok(rules.length >= 5 && rules.every((s) => s.indexOf(".sa-lite .dcs") === 0),
      "every .sa-lite rule is a picker-scoped .dcs descendant selector (nothing else touched)");
    r.ok(html.includes(".sa-lite .dcs-gloss { display: none; }"),
      "…the gloss layer drops inside the picker");
    r.ok((html.match(/\.sa-lite \.dcs\.dcs-cursed/g) || []).length >= 1,
      "…the cursed routing keeps a (flattened) treatment inside the picker");
    const base = /\n  \.dcs \{\n[\s\S]*?\n  \}/.exec(html);
    r.ok(!!base && base[0].includes("radial-gradient") && base[0].includes("box-shadow")
      && base[0].includes("rotate(var(--dcs-rot))"),
      "the base .dcs vinyl (board / store / banner) keeps its full treatment");
  }

  // ── Structural: Stats write coalescing -----------------------------------
  {
    r.ok(stats.includes("STATS_WRITE_DEBOUNCE_MS = 250") && stats.includes("setTimeout(writeStatsNow, STATS_WRITE_DEBOUNCE_MS)"),
      "Stats.put schedules ONE trailing 250ms debounced write");
    r.ok(stats.includes("if (cache) return { ...cache };"),
      "…reads stay live off the in-memory cache while a write is pending");
    r.ok(stats.includes("flush() { writeStatsNow(); }"),
      "…Stats.flush() forces the pending write synchronously");
    r.ok(flush.includes("Stats.flush()"),
      "flushCampaignSave flushes Stats too (covers every transition + pagehide/visibilitychange)");
  }

  // ── Behavioral: batched open over a fake DOM ------------------------------
  {
    // 13-card deck: the whole grid mounts synchronously, no chunks queued.
    const p13 = buildPicker(src, makeDeck(13));
    p13.setModalHidden(false);
    p13.api.renderStickerApplyCards();
    r.eq(p13.el.saCards.children.length, 13, "13-card open: all 13 cards mount synchronously");
    r.eq(p13.rafPending(), 0, "…no rAF chunk queued (nothing left to stream)");
    r.eq(p13.dom.created.length, 13, "…cold cache parses exactly one button per card");

    // 50-card deck: first batch sync, the rest in two generation-guarded chunks.
    const p50 = buildPicker(src, makeDeck(50));
    p50.setModalHidden(false);
    p50.api.renderStickerApplyCards();
    r.eq(p50.el.saCards.children.length, p50.api.FIRST,
      "50-card open: only the FIRST batch mounts synchronously");
    r.eq(p50.rafPending(), 1, "…one chunk stream armed");
    p50.fire();
    r.eq(p50.el.saCards.children.length, p50.api.FIRST + p50.api.CHUNK,
      "…first chunk appends APPLY_CHUNK more");
    p50.fire();
    r.eq(p50.el.saCards.children.length, 50, "…second chunk completes the grid");
    r.eq(p50.rafPending(), 0, "…the stream self-terminates (no re-armed frames)");
    const sorted = makeDeck(50).sort((a, b) => SORT_KEY(a) - SORT_KEY(b)).map((c) => String(c.id));
    r.eq(JSON.stringify(p50.el.saCards.children.map((n) => String(n.dataset.cardId))),
      JSON.stringify(sorted), "…the mounted grid is in sorted (rank, suit) order");

    // Generation guard: a re-open/close kills a pending stream mid-flight.
    const pc = buildPicker(src, makeDeck(50));
    pc.setModalHidden(false);
    pc.api.renderStickerApplyCards();
    pc.api._bump();   // what closeStickerApply / a re-open does
    pc.fire();
    r.eq(pc.el.saCards.children.length, pc.api.FIRST,
      "a generation bump mid-stream cancels the remaining chunks (close cancels)");

    // Hidden-modal guard: chunks never append behind a closed picker.
    const ph = buildPicker(src, makeDeck(50));
    ph.api.renderStickerApplyCards();   // modal still hidden (open hasn't shown it yet)
    ph.setModalHidden(true);
    ph.fire();
    r.eq(ph.el.saCards.children.length, ph.api.FIRST,
      "…a hidden modal also stops the stream (no appends under a closed overlay)");

    // Warm cache: a re-open reuses the parsed nodes (zero new parses).
    p50.api.renderStickerApplyCards();
    r.eq(p50.dom.created.length, 50, "a warm re-open parses NOTHING (the sig cache serves every card)");
    r.eq(p50.el.saCards.children.length, p50.api.FIRST,
      "…and re-mounts batched (first batch sync again)");
  }

  // ── Behavioral: the modifying confirm touches ONLY the one card -----------
  {
    const deck = makeDeck(50);
    const p = buildPicker(src, deck);
    p.setModalHidden(false);
    p.api.renderStickerApplyCards();
    p.fire(); p.fire();   // complete the mount
    const before = p.el.saCards.children.slice();
    const createdBefore = p.dom.created.length;
    // A rank sticker lands on the lowest card: 2♠ (id 0) → 14♠ (re-sorts last).
    deck[0].currentRank = 14;
    deck[0].stickers = [{ type: "rankUp" }];
    const btn = p.api.updateApplyCardInPlace(0);
    r.ok(!!btn, "the targeted update returns the touched card's button");
    r.eq(p.dom.created.length - createdBefore, 1,
      "…exactly ONE button rebuilt (the sig-changed card) — not 50");
    r.eq(p.el.saCards.children.length, 50, "…the grid stays complete (no re-mount)");
    // The grid must be in non-decreasing (rank, suit) order with the bumped
    // card in the rank-14 group (its exact slot among the 14♠ twins is free).
    const keys = p.el.saCards.children.map((n) => SORT_KEY(deck.find((c) => c.id === Number(n.dataset.cardId))));
    r.ok(keys.every((k, i) => i === 0 || keys[i - 1] <= k),
      "…the grid is still in sorted (rank, suit) order after the move");
    r.ok(SORT_KEY(deck[0]) >= keys[0] && String(p.el.saCards.children[keys.lastIndexOf(SORT_KEY(deck[0]))].dataset.cardId) === "0",
      "…the bumped card sits in its new rank-14 slot (no longer first)");
    const stillThere = before.filter((n) => p.el.saCards.children.indexOf(n) !== -1);
    r.eq(stillThere.length, 49, "…every other node is identity-preserved (moved, never re-parsed)");
    r.ok(!btn.classList.contains("sa-selected") && !btn.classList.contains("sa-flash"),
      "…transient confirm-FX classes are stripped from the rebuilt button");

    // Eligibility sync: flip the rule so ONE other card becomes ineligible —
    // a classList-only toggle (no rebuild, node identity preserved).
    const eligDeck = makeDeck(13);
    const opts = { canApply: () => true };
    const pe = buildPicker(src, eligDeck, opts);
    pe.setModalHidden(false);
    pe.api.renderStickerApplyCards();
    const created0 = pe.dom.created.length;
    const node7 = pe.el.saCards.children.find((n) => Number(n.dataset.cardId) === 7);
    opts.canApply = (c) => c.id !== 7;
    pe.api.updateApplyCardInPlace(3);   // an unchanged card — no rebuild expected
    r.ok(node7.classList.contains("sa-disabled") && "disabled" in node7._attrs,
      "a card whose eligibility flipped gets sa-disabled + the disabled attribute");
    r.eq(pe.dom.created.length, created0,
      "…with ZERO button rebuilds (classList-only sync)");
    r.ok(pe.el.saCards.children.indexOf(node7) !== -1,
      "…the greyed node is the same element (never re-parsed)");
  }

  // ── Behavioral: Stats writes coalesce + flush -----------------------------
  {
    // A burst of bumps: nothing writes synchronously; the trailing timer lands
    // EXACTLY ONE write carrying every delta; reads are live throughout.
    const s = buildStats(src);
    for (let i = 0; i < 5; i++) s.Stats.bump("cardsBuried");
    r.eq(s.writes(), 0, "5 bumps write 0 setItems synchronously (scheduled, not written)");
    r.eq(s.Stats.get().cardsBuried, 5, "…reads stay live off the in-memory cache");
    r.eq(s.pending(), 1, "…exactly one trailing timer armed for the whole burst");
    s.fire();
    r.eq(s.writes(), 1, "…the trailing write lands EXACTLY ONE setItem");
    r.eq(JSON.parse(s.blob()).cardsBuried, 5, "…carrying the full folded count");

    // flush() writes synchronously NOW; a clean flush is inert; the disarmed
    // timer can never double-write.
    const s2 = buildStats(src);
    s2.Stats.bumpAll({ cardsBuried: 2, pilesLost: 1 });
    s2.Stats.flush();
    r.eq(s2.writes(), 1, "flush() writes synchronously NOW");
    r.eq(s2.pending(), 0, "…and disarms the trailing timer");
    s2.fire();
    r.eq(s2.writes(), 1, "…the now-dead timer writes nothing");
    s2.Stats.flush();
    r.eq(s2.writes(), 1, "…a flush with nothing dirty is a no-op");
    r.eq(JSON.parse(s2.blob()).pilesLost, 1, "…the flushed blob carries both deltas");

    // reset() rides the same coalescing; an all-empty bumpAll never schedules.
    const s3 = buildStats(src);
    s3.Stats.reset();
    r.eq(s3.writes(), 0, "reset() is scheduled, not written synchronously");
    s3.Stats.flush();
    r.eq(s3.writes(), 1, "…and flush() lands it");
    const w = s3.writes();
    s3.Stats.bumpAll({});
    s3.fire();
    r.eq(s3.writes(), w, "an all-empty bumpAll batch never touches storage (unchanged)");
  }

  return r.summary();
}
