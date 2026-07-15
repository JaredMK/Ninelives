// RESUME1 — Continue-resume crash fix + the resume save-loss window.
//
// The bug: resumeSavedGame rebuilt the board to the run layout while the
// engine from the deal the player quit was still live with a smaller board —
// renderNetwork's pileEls.length-bounded loops then read board.isActive(i)
// past the stale board's piles (TypeError reading 'dead'), aborting resume in
// a half-resumed limbo from which the save could be wiped.
//
// Covered here (the DOM-free slice + source-shape contracts):
//   R1  menu invariant — entering the MAIN menu tears down any live engine
//       (one shared teardown, invoked by showMainMenu, which every menu-entry
//       path funnels through: quitToMenu, zenQuitToMenu, failed/victory exits);
//   R2  clamped loops — every pileEls.length-bounded loop that dereferences
//       engine board state clamps to the board it reads (plus the engine-side
//       pileHint bounds guard, unit-tested for real out-of-range indexes);
//   R3  transactional resume — resumeSavedGame writes nothing to the save
//       itself and fails SAFE back to the main menu on a throw;
//   R4  save-wipe discipline — a boot-time restore() that THROWS preserves
//       the blob (fail safe, no Continue this boot); a restore() that returns
//       false keeps the designed structural-mismatch discard.
//
// Structural checks follow the uifix1/boot2 source-contract style; the R4
// checks are BEHAVIORAL (real boot under the harness with an injected
// localStorage stub carrying a real/corrupted save blob). No tunables pinned.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadGame, makeRunner } from "./_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

/** The single game <script> block (the one defining the engine modules). */
function gameScript() {
  const html = readFileSync(join(HERE, "..", "index.html"), "utf8");
  const blocks = html.match(/<script>([\s\S]*?)<\/script>/g) || [];
  return blocks
    .map((b) => b.replace(/^<script>/, "").replace(/<\/script>$/, ""))
    .find((c) => c.includes("const GameEngine")) || "";
}
/** Body of a top-level `function name(...) { ... }` (brace-matched). `sig`
    disambiguates same-named functions (e.g. the UI startRun vs the engine's
    internal one) by matching the start of the parameter list. */
function fnBody(src, name, sig = "") {
  const at = src.indexOf("function " + name + "(" + sig);
  if (at === -1) return "";
  const open = src.indexOf("{", at);
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === "{") depth++;
    else if (src[i] === "}" && --depth === 0) return src.slice(open, i + 1);
  }
  return "";
}
/** Minimal in-memory localStorage (same stub shape as the other suites). */
function memStorage(init = {}) {
  const data = { ...init };
  return {
    getItem: (k) => (k in data ? data[k] : null),
    setItem: (k, v) => { data[k] = String(v); },
    removeItem: (k) => { delete data[k]; },
    _data: data,
  };
}
const SAVE_KEY = "ninelives.save.v1";

export function run() {
  const r = makeRunner("resume1.test.mjs");
  const src = gameScript();

  // The reworked script still evaluates + exposes the engine modules.
  const g = loadGame();
  r.ok(!!(g.GameEngine && g.CampaignState), "game script evaluates with the RESUME1 wiring in place");

  // ---- R2 (engine unit): out-of-range pileHint = null, never a deref -------
  // This is the exact deref class the UI loops hit: index >= board.size →
  // piles[index] is undefined → '.dead' TypeError before the guard. The tell
  // state is armed directly on the live run object (Spade Whispers' whispered
  // mode + a stale tellPiles entry) so BOTH pre-guard paths are exercised.
  {
    const { GameEngine, DeckManager } = loadGame();
    const piles = 9;
    const e = GameEngine.create(DeckManager.buildStandardDeck(), piles);
    e.start(); e.startRun();
    const size = e.getBoard().size;
    r.eq(size, piles, "board.size matches the deal's pile count");
    e.getRun().tellDrawsLeft = 3;             // whispered: every pile hints
    let threw = null, v;
    try {
      v = e.pileHint(size);                   // first index past the board
      if (v === null) v = e.pileHint(size + 90);
      if (v === null) v = e.pileHint(-1);
      if (v === null) v = e.pileHint(2.5);
    } catch (err) { threw = err; }
    r.ok(!threw, "pileHint(out-of-range) never throws (whispered)" + (threw ? " — threw " + threw.message : ""));
    r.eq(v, null, "pileHint(out-of-range) reads as absent (null)");
    r.ok(["higher", "lower", "same"].includes(e.pileHint(0)), "in-range whispered pileHint still hints");
    // Stale tellPiles entry pointing past the board (the armed-pile path).
    e.getRun().tellDrawsLeft = 0;
    e.getRun().tellPiles.add(size + 3);
    let threw2 = null, v2;
    try { v2 = e.pileHint(size + 3); } catch (err) { threw2 = err; }
    r.ok(!threw2 && v2 === null, "a stale armed Tell past the board reads as absent (null, no throw)");
  }

  // ---- R1 (shape): one shared menu-entry teardown, wired into showMainMenu --
  {
    const td = fnBody(src, "teardownEngineForMenu");
    r.ok(!!td, "teardownEngineForMenu exists (the shared menu-entry teardown)");
    r.ok(td.includes("engine = null"), "teardown drops the live engine (engine = null)");
    r.ok(td.includes("stopAutoPlay()"), "teardown stops the debug auto-play stepper");
    r.ok(td.includes("setAutopilotRunning(false)"), "teardown stops the debug autopilot timer");
    r.ok(td.includes("pendingRunEnd = null"), "teardown drops a quit deal's deferred loss recap");
    r.ok(td.includes("endAwaitingDeathAnim = false"), "teardown clears the awaiting-death-anim latch");

    const smm = fnBody(src, "showMainMenu");
    const tdAt = smm.indexOf("teardownEngineForMenu()");
    r.ok(tdAt !== -1, "showMainMenu invokes the teardown (menu invariant: engine-free backdrop)");
    r.ok(tdAt < smm.indexOf('classList.remove("hidden")'),
      "teardown runs BEFORE the menu is revealed");
    // Every menu-entry path funnels through showMainMenu (so the invariant
    // holds however the menu was reached).
    for (const fn of ["quitToMenu", "zenQuitToMenu", "showCampaignFailed", "showPinkyHome"]) {
      r.ok(fnBody(src, fn).includes("showMainMenu("), fn + " routes through showMainMenu");
    }
  }

  // ---- R2 (shape): every board-reading pileEls.length loop is clamped ------
  {
    const rn = fnBody(src, "renderNetwork");
    r.ok(rn.includes("Math.min(pileEls.length, board.size)"),
      "renderNetwork clamps to the board it reads");
    r.ok(!/<\s*pileEls\.length;/.test(rn),
      "renderNetwork keeps NO unclamped pileEls.length-bounded loop");

    const rf = fnBody(src, "refreshNetwork");
    r.ok(rf.includes("Math.min(pileEls.length, b.size)"),
      "refreshNetwork clamps to its (possibly captured) board");
    r.ok(!/<\s*pileEls\.length;/.test(rf),
      "refreshNetwork keeps NO unclamped pileEls.length-bounded loop");

    const rh = fnBody(src, "renderPileHints");
    r.ok(rh.includes("Math.min(pileEls.length, hintBoard.size)"),
      "renderPileHints clamps hint reads to the engine's board");
    r.ok(/i < nHints/.test(rh), "renderPileHints gates pileHint(i) behind the clamp");

    // The two event-handler repaint loops (base-fired, pillar-fired) read the
    // EVENT's board snapshot — both clamp to it.
    const he = fnBody(src, "handleEvent");
    r.ok(he.includes("Math.min(pileEls.length, board.size)"),
      "base-fired repaint loop clamps to the event's board");
    r.ok(he.includes("Math.min(pileEls.length, payload.board.size)"),
      "pillar-fired repaint loop clamps to the event's board");

    // The mirror direction: paintPileCounts (board.size-bounded, indexes the
    // DOM) skips a missing pile element instead of dereferencing it.
    const pc = fnBody(src, "paintPileCounts");
    r.ok(pc.includes("const pe = pileEls[i];") && pc.includes("if (!pe) continue;"),
      "paintPileCounts skips pile elements the rebuilt DOM no longer has");
  }

  // ---- A6 sweep: no remaining pileEls.length loop derefs board state -------
  {
    // Every `< pileEls.length` loop head in the script: its body (the next
    // stretch of source) must not index engine board state with the loop var.
    const rx = /<\s*pileEls\.length;/g;
    const bad = [];
    let m;
    while ((m = rx.exec(src))) {
      const body = src.slice(m.index, m.index + 420);
      if (/\b(?:board|b|payload\.board)\.(?:isActive|top|pileSize|isAnchored|addSizeBonus)\(/.test(body))
        bad.push(src.slice(Math.max(0, m.index - 60), m.index + 120).replace(/\s+/g, " "));
    }
    r.ok(bad.length === 0,
      "sweep: no pileEls.length-bounded loop dereferences engine board state unclamped"
      + (bad.length ? " — offenders: " + bad.join(" | ") : ""));
  }

  // ---- R3 (shape): resume is transactional for the save --------------------
  {
    const rs = fnBody(src, "resumeSavedGame");
    r.ok(/try\s*\{/.test(rs) && /catch\s*\(/.test(rs), "resumeSavedGame wraps the rebuild in try/catch");
    const cat = rs.slice(rs.search(/catch\s*\(/));
    r.ok(cat.includes("showMainMenu("), "a failed resume fails SAFE back to the main menu (Continue re-offered)");
    // No save writes of its own: the only persist is startRun's own
    // end-of-deal checkpoint — a throw before it leaves the blob untouched.
    r.ok(!rs.includes("persistCampaign(") && !rs.includes("SaveStore.save(") && !rs.includes("clearSave("),
      "resumeSavedGame itself never writes or clears the save");
    const sr = fnBody(src, "startRun", "seedOverride");   // the UI startRun (not the engine's)
    const persistAt = sr.indexOf('persistCampaign("run")');
    r.ok(persistAt !== -1 && persistAt > sr.indexOf("engine.start("),
      "startRun persists only after the engine deal succeeded (checkpoint at the end)");
  }

  // ---- R4 (behavioral): boot-time restore() outcomes vs the blob -----------
  // A real boot under the harness: the game script's init runs SaveStore.load
  // + campaign.restore against an injected storage stub.
  {
    // (a) valid blob → restore succeeds → blob PRESERVED (Continue offered).
    const valid = { schema: 1, phase: "run", deckId: "pink",
      campaign: loadGame().CampaignState.create().serialize() };
    const ls1 = memStorage({ [SAVE_KEY]: JSON.stringify(valid) });
    loadGame({ localStorage: ls1 });
    r.ok(!!ls1._data[SAVE_KEY], "a valid save blob survives boot (Continue path)");

    // (b) restore() RETURNS FALSE (wrong schema) → the designed discard fires.
    const incompat = { schema: 1, phase: "run", deckId: "pink",
      campaign: { schema: 99, baseDeck: new Array(52).fill({}) } };
    const ls2 = memStorage({ [SAVE_KEY]: JSON.stringify(incompat) });
    loadGame({ localStorage: ls2 });
    r.ok(!(SAVE_KEY in ls2._data), "a structurally incompatible blob (restore → false) is still discarded");

    // (c) restore() THROWS (structurally valid schema, poisoned deck entries:
    // the per-card rebuild derefs null.modifications) → boot must NOT throw
    // and must NOT clear the blob — no Continue this boot, save preserved.
    const poisoned = JSON.parse(JSON.stringify(valid));
    poisoned.campaign.baseDeck = new Array(poisoned.campaign.baseDeck.length).fill(null);
    const ls3 = memStorage({ [SAVE_KEY]: JSON.stringify(poisoned) });
    const errs = [];
    const orig = console.error;
    console.error = (...a) => errs.push(a.join(" "));
    let bootThrew = null;
    try { loadGame({ localStorage: ls3 }); }
    catch (err) { bootThrew = err; }
    finally { console.error = orig; }
    r.ok(!bootThrew, "a restore() that throws no longer escapes boot"
      + (bootThrew ? " — threw " + bootThrew.message : ""));
    r.ok(!!ls3._data[SAVE_KEY], "a restore() that throws PRESERVES the blob (no wipe)");
    r.ok(errs.some((e) => e.includes("save preserved")),
      "the preserved-save fallback is reported (console.error)");
  }

  return r.summary();
}
