// STKLAG3 — piling many store Removals in one visit got laggier per touch (the
// player: "after the FOURTH every touch is extremely lagged"), GROWING per
// removal. Real-browser measurement (Playwright, 6x CPU throttle, heavy Stage-3
// blob) traced it to the ONLY structure that grows per action: the engine's
// display-only event log `run.log`. Each logged action re-ran the debug panel's
// `renderDebugLog`, which did a FULL O(N) reversed remap of the WHOLE log — so
// every touch cost scaled with total run length, and the rendered debug-log DOM
// held 2·N nodes that never stopped growing. (Debug-OFF the path is flat — the
// early-return gate means it only bites with the debug panel open; measured
// flat there. The fix is valuable regardless and lands anyway.)
//
// The fix is cleanup/boundedness only — no feedback removed:
//  (1) run.log is a display-only RING BUFFER: appends keep only the newest
//      LOG_CAP (+SLACK) entries, trimmed in batches (amortized O(1)), so memory
//      can't grow across a long run. The log is never serialized (confirmed) and
//      never read by game logic, so capping it changes no save byte and no rule.
//  (2) renderDebugLog renders only the newest DEBUG_LOG_SHOWN entries (newest-
//      first, a screenful), so its cost + node count are FLAT regardless of log
//      length — O(1) per action instead of O(N).
//
// This suite proves both accumulators are BOUNDED and independent of N:
//  (a) BEHAVIORAL: drive a real GameEngine, append thousands of log entries, and
//      assert run.log never exceeds LOG_CAP+LOG_SLACK, stays flat across batches
//      (ring, not O(N)), keeps the NEWEST entry, and drops the OLDEST.
//  (b) EXTRACTED RENDER: run the real renderDebugLog body over a huge synthetic
//      log and assert the rendered entry/node count is capped at DEBUG_LOG_SHOWN
//      and IDENTICAL for N=1000 vs N=5000 (flat in N), with an "older not shown"
//      marker when truncated.
//  (c) STRUCTURAL: the O(N) full-log remap is gone (bounded slice), the push
//      path trims, and run.log is not in the save blob.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadGame, makeRunner } from "./_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

function fullHtml() { return readFileSync(join(HERE, "..", "index.html"), "utf8"); }
function gameScript(html) {
  const blocks = html.match(/<script>([\s\S]*?)<\/script>/g) || [];
  return blocks
    .map((b) => b.replace(/^<script>/, "").replace(/<\/script>$/, ""))
    .find((c) => c.includes("const GameEngine")) || "";
}
function bodyAt(src, sig) {
  const at = src.indexOf(sig);
  if (at === -1) return "";
  const open = src.indexOf("{", at);
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === "{") depth++;
    else if (src[i] === "}" && --depth === 0) return src.slice(open, i + 1);
  }
  return "";
}
function fnBody(src, name) { return bodyAt(src, "function " + name + "("); }
function countOf(hay, needle) {
  let n = 0, i = 0;
  while ((i = hay.indexOf(needle, i)) !== -1) { n++; i += needle.length; }
  return n;
}

export function run() {
  const r = makeRunner("stklag3.test.mjs");
  const html = fullHtml();
  const src = gameScript(html);
  const g = loadGame();
  const { GameEngine, DeckManager } = g;
  r.ok(!!(GameEngine && DeckManager), "game script evaluates with the STKLAG3 wiring in place");

  // Read the live caps from source (never pin a tunable — derive the ceilings).
  const capM = src.match(/const LOG_CAP = (\d+), LOG_SLACK = (\d+);/);
  const shownM = src.match(/const DEBUG_LOG_SHOWN = (\d+);/);
  r.ok(!!capM, "LOG_CAP / LOG_SLACK constants exist in the engine");
  r.ok(!!shownM, "DEBUG_LOG_SHOWN constant exists in the renderer");
  const LOG_CAP = capM ? Number(capM[1]) : 0;
  const LOG_SLACK = capM ? Number(capM[2]) : 0;
  const DEBUG_LOG_SHOWN = shownM ? Number(shownM[1]) : 0;
  const CEIL = LOG_CAP + LOG_SLACK;
  r.ok(LOG_CAP > 0 && DEBUG_LOG_SHOWN > 0 && DEBUG_LOG_SHOWN <= LOG_CAP,
    "caps are sane (0 < DEBUG_LOG_SHOWN <= LOG_CAP)");

  // ---- (a) BEHAVIORAL: run.log is a bounded ring buffer ---------------------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 9);
    e.start(); e.startRun();
    const base = e.getRun().log.length;   // startRun logs a couple of entries
    // A packed store-Removal spree is one logAction per removal; simulate a very
    // long run's worth (far more than any real visit) and watch the cap hold.
    for (let i = 0; i < 2000; i++) e.logAction("Store: bought a Removal #" + i);
    const len1 = e.getRun().log.length;
    for (let i = 0; i < 2000; i++) e.logAction("Store: bought a Removal (batch2) #" + i);
    const len2 = e.getRun().log.length;

    r.ok(len1 <= CEIL, "after 2000 appends run.log stays <= LOG_CAP+LOG_SLACK (" + CEIL + "), got " + len1);
    r.ok(len2 <= CEIL, "…and a second 2000-append batch stays <= " + CEIL + ", got " + len2);
    r.ok(len1 >= LOG_CAP && len2 >= LOG_CAP, "…while retaining a full window (>= LOG_CAP)");
    r.ok(len1 < base + 2000, "run.log did NOT grow O(N) with the number of appends (ring, not append-forever)");

    // Newest is always retained; oldest is pruned (ring semantics).
    e.logAction("SENTINEL_NEWEST_ZZZ");
    const log = e.getRun().log;
    r.eq(log[log.length - 1].title, "SENTINEL_NEWEST_ZZZ", "the newest entry is always at the tail");
    r.ok(!log.some((x) => x.title === "Store: bought a Removal #0"),
      "the oldest entries are dropped (front-trimmed) once the ring overflows");
  }

  // ---- (b) EXTRACTED RENDER: renderDebugLog is capped + flat in N ------------
  // Run the REAL renderDebugLog body against a huge synthetic log and count the
  // rendered entries; DEBUG_LOG_SHOWN is declared just above the function, so we
  // inject its live value.
  {
    const body = fnBody(src, "renderDebugLog");
    r.ok(body.length > 0, "renderDebugLog body extracted from source");
    const render = new Function("el", "engine", "DEBUG_LOG_SHOWN", body.slice(1, -1));
    const runRender = (n) => {
      let captured = "";
      const el = { debugLog: {
        set innerHTML(v) { captured = v; },
        get innerHTML() { return captured; },
        set scrollTop(_v) {},
      } };
      const log = [];
      for (let i = 0; i < n; i++) log.push({ title: "evt " + i, lines: ["a", "b"] });
      const engine = { getRun: () => ({ log }) };
      render(el, engine, DEBUG_LOG_SHOWN);
      return captured;
    };
    const big = runRender(1000);
    const bigger = runRender(5000);
    const entries1000 = countOf(big, 'class="dl-entry"');
    const entries5000 = countOf(bigger, 'class="dl-entry"');
    r.eq(entries1000, DEBUG_LOG_SHOWN, "a 1000-entry log renders exactly DEBUG_LOG_SHOWN entries (capped)");
    r.eq(entries5000, DEBUG_LOG_SHOWN, "a 5000-entry log renders the SAME count — render is FLAT in log length");
    r.ok(big.includes("not shown"), "…with an 'older events not shown' marker when the log is truncated");
    // Node count is bounded: entries + their lines + the marker, all ~O(cap).
    const nodeCount = countOf(bigger, "<div");
    r.ok(nodeCount <= DEBUG_LOG_SHOWN * 4 + 4,
      "rendered debug-log node count is bounded by ~DEBUG_LOG_SHOWN, not by log length (" + nodeCount + ")");

    // A short log renders every entry and no marker (behavior unchanged for the
    // common case; feedback/ordering preserved).
    const few = runRender(3);
    r.eq(countOf(few, 'class="dl-entry"'), 3, "a short log renders all its entries (no truncation)");
    r.ok(!few.includes("not shown"), "…and shows no truncation marker when nothing is hidden");
    // Newest-first ordering preserved (the last pushed is rendered first).
    r.ok(few.indexOf("evt 2") < few.indexOf("evt 0"), "newest-first ordering is preserved");
  }

  // ---- (c) STRUCTURAL: the O(N) remap is gone; trim exists; log not saved ----
  {
    const render = fnBody(src, "renderDebugLog");
    r.ok(!/log\.slice\(\)\.reverse\(\)/.test(render),
      "renderDebugLog no longer full-remaps the WHOLE log (log.slice().reverse() removed)");
    r.ok(render.includes("log.length - DEBUG_LOG_SHOWN") && render.includes("log.slice(start)"),
      "…it renders only the newest DEBUG_LOG_SHOWN entries (bounded tail slice)");

    const pushLog = fnBody(src, "pushLog");
    r.ok(pushLog.includes("run.log.push") && pushLog.includes("splice(0"),
      "pushLog appends then front-trims (ring buffer) so run.log can't grow unbounded");
    r.ok(pushLog.includes("LOG_CAP + LOG_SLACK"),
      "…trimming only when overrunning by LOG_SLACK (amortized O(1), not O(N) per append)");

    // Both append sites go through the capped pushLog (no raw run.log.push left).
    const begin = fnBody(src, "logBegin");
    const action = fnBody(src, "logAction");
    r.ok(begin.includes("pushLog(currentEntry)"), "logBegin routes through the capped pushLog");
    r.ok(action.includes("pushLog("), "logAction routes through the capped pushLog");

    // The event log is display-only — never serialized (capping it can't touch a save byte).
    const serialize = bodyAt(src, "serialize() {");
    r.ok(serialize.length > 0 && !/\blog\b/.test(serialize),
      "run.log is not part of the save blob (serialize() carries no log field)");
  }

  return r.summary();
}
