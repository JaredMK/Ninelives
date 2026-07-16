// HELP2 — the in-play pile-card hold-for-help is rerouted from the fullscreen
// #cardInfo popup to the histogram-band #peekInfo banner (the same idiom a
// Pillar/Base hold already uses). Presentation only (no tunables, no persisted
// state), so this is a structural check in the storehelp1.test.mjs style:
// loadGame() proves the rewired script still evaluates, source-shape checks pin
// the new routing + the removal of the dead openCardInfo path, and the engine
// run-started gate (which peekInBand() reads) is exercised live.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadGame, makeRunner } from "./_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

function fullHtml() {
  return readFileSync(join(HERE, "..", "index.html"), "utf8");
}
/** The single game <script> block (the one defining the engine modules). */
function gameScript(html) {
  const blocks = html.match(/<script>([\s\S]*?)<\/script>/g) || [];
  return blocks
    .map((b) => b.replace(/^<script>/, "").replace(/<\/script>$/, ""))
    .find((c) => c.includes("const GameEngine")) || "";
}
/** Body of a top-level `function name(...) { ... }` (brace-matched). */
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

export function run() {
  const r = makeRunner("help2.test.mjs");
  const html = fullHtml();
  const src = gameScript(html);

  const g = loadGame();
  r.ok(!!(g.GameEngine && g.StickerTypes), "game script evaluates with the HELP2 rewiring in place");

  // ============================================================
  // PART A — the dead fullscreen-popup pile path is gone
  // ============================================================
  {
    // openCardInfo had exactly one caller (the in-play pile hold); rerouted, so
    // the function AND its per-gesture state must be fully removed — no orphans.
    r.ok(!/function openCardInfo\(/.test(src), "openCardInfo (the old pile-hold popup opener) is removed");
    r.ok(!/\bopenCardInfo\b/.test(src), "no dangling openCardInfo caller remains");
    r.ok(!/\binfoHold\b/.test(src), "the infoHold gesture flag is removed");
    r.ok(!/\binfoTimer\b/.test(src), "the infoTimer handle is removed");
    // The popup element + its close path stay — other surfaces still use them.
    r.ok(/id="cardInfo"/.test(html), "the #cardInfo popup element is kept (still used by other surfaces)");
    r.ok(fnBody(src, "closeCardInfo").includes('classList.add("hidden")'), "closeCardInfo is kept intact");
  }

  // ============================================================
  // PART B — the in-play pile hold now routes into the #peekInfo band
  // ============================================================
  {
    // Locate the board pointerdown's active-play pile branch (run started,
    // status playing, no prompt) and confirm it arms the peek machinery.
    const guard = "engine.isRunStarted() && engine.getStatus() === \"playing\" && !promptActive";
    const gi = src.indexOf(guard);
    r.ok(gi !== -1, "the board pointerdown active-play guard is present");
    // A generous window covering the pileDrag arm + the hold timer.
    const branch = src.slice(gi, gi + 1500);
    r.ok(/pileDrag = \{ index/.test(branch), "the branch still arms the drag-to-guess gesture (pileDrag)");
    r.ok(/peekTimer = setTimeout\(/.test(branch), "the hold uses the shared peekTimer (not a private info timer)");
    r.ok(/openCardPeek\(index\)/.test(branch), "the hold opens the card peek in the #peekInfo band (openCardPeek)");
    r.ok(/peeking = true/.test(branch), "the hold sets the shared `peeking` flag so endPeek closes it");
    r.ok(!/openCardInfo/.test(branch), "the hold no longer opens the fullscreen #cardInfo popup");
    r.ok(branch.indexOf("INFO_HOLD_MS") !== -1, "the pile hold keeps the INFO_HOLD_MS threshold");

    // openCardPeek routes into #peekInfo and toggles the band via peekInBand().
    const ocp = fnBody(src, "openCardPeek");
    r.ok(ocp.includes("el.peekInfo.innerHTML = cardPeekHtml("), "openCardPeek renders cardPeekHtml into #peekInfo");
    r.ok(ocp.includes('el.peekInfo.classList.remove("hidden")'), "openCardPeek shows #peekInfo");
    r.ok(/classList\.toggle\("peek-band", peekInBand\(\)\)/.test(ocp), "openCardPeek toggles body.peek-band via peekInBand()");
    // Same band idiom as Pillars/Bases (identical toggle call).
    r.ok(/classList\.toggle\("peek-band", peekInBand\(\)\)/.test(fnBody(src, "openPillarPeek")), "openPillarPeek uses the same peek-band toggle");
    r.ok(/classList\.toggle\("peek-band", peekInBand\(\)\)/.test(fnBody(src, "openBasePeek")), "openBasePeek uses the same peek-band toggle");
    // The band toggle is gated by the run-started state (setup floats, play bands).
    r.ok(fnBody(src, "peekInBand").includes("isRunStarted"), "peekInBand gates the band on the run-started state");

    // Dismissal goes through the shared endPeek → closePeekInfo (removes the band).
    r.ok(fnBody(src, "closePeekInfo").includes('classList.remove("peek-band")'), "closePeekInfo removes body.peek-band (restoring the histogram)");
  }

  // ============================================================
  // C — the histogram band is what CSS hides under a peek (unchanged idiom)
  // ============================================================
  {
    // The peek-band rule hides the #histBand children; the pile peek now rides it.
    r.ok(/body\.peek-band[\s\S]{0,200}#histBand/.test(html), "the peek-band CSS still targets #histBand (the histogram/suit-count/deck area)");
  }

  // ============================================================
  // D — the untouched surfaces STILL open the #cardInfo popup
  // ============================================================
  {
    for (const [fn, note] of [
      ["showStoreItemHelp", "store shelf hold"],
      ["showCardHelp", "deck-inspector + sticker-picker hold"],
      ["openSamePowerInfo", "equipped Same-Power HUD hold"],
    ]) {
      const body = fnBody(src, fn);
      r.ok(body.length > 0, note + ": " + fn + " exists");
      r.ok(/cardInfo/.test(body), note + " (" + fn + ") still targets the #cardInfo popup");
      r.ok(!/peekInfo/.test(body), note + " (" + fn + ") does NOT use the histogram band");
    }
    // The setup pile hold still opens openCardPeek (which floats because
    // peekInBand() is false pre-run) — same opener, band gated by state.
    r.ok(fnBody(src, "peekInBand").length > 0, "peekInBand exists (gates setup-float vs play-band for openCardPeek)");
  }

  // ============================================================
  // E — the run-started gate peekInBand() reads is real (live engine)
  // ============================================================
  {
    const deck = g.DeckManager.buildStandardDeck();
    const e = g.GameEngine.create(deck, 7, { cols: [3, 4, 3] });
    e.start();
    r.ok(e.isRunStarted() === false, "before startRun: not run-started (setup → peekInBand() false → float)");
    e.startRun([null, null, null], [null, null, null]);
    r.ok(e.isRunStarted() === true, "after startRun: run-started (play → peekInBand() true → band)");
    r.eq(e.getStatus(), "playing", "and status is 'playing' (the active-play hold guard)");
  }

  return r.summary();
}
