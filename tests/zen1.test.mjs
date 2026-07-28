// ZEN1 — Zen mode (standalone higher/lower): the difficulty.js zen block +
// fail-loud validation, per-difficulty deck construction (suit subsets of a
// fresh unmodified standard deck), pile counts/layouts, engine win/loss under
// a Zen config (no cols → no Pillar machinery, empty Same-Charge bank), the
// ZenStats per-difficulty record (own key; campaign Stats/save untouched),
// and campaign-state isolation across a full Zen game.
//
// Registry-driven: every zen number (suitCount/piles/label) is read LIVE from
// difficulty.js via DifficultyData — deck sizes derive from suitCount × 13,
// never pinned literals.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadGame, makeRunner } from "./_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const DIFFICULTY = join(HERE, "..", "difficulty.js");

/** Evaluate the live difficulty.js into its plain data object. */
function liveDifficultyData() {
  const src = readFileSync(DIFFICULTY, "utf8");
  return new Function(src + "\n;return NINELIVES_DIFFICULTY;")();
}
/** A difficulty.js source with the live data mutated (validation probes). */
function difficultySourceWith(mutate) {
  const d = JSON.parse(JSON.stringify(liveDifficultyData()));
  mutate(d);
  return '"use strict";\nconst NINELIVES_DIFFICULTY = ' + JSON.stringify(d) + ";";
}
/** Load the game against a mutated difficulty.js, capturing the thrown error
    and every console.error line (the fail-loud naming contract). */
function loadExpectingFailure(mutate) {
  const errs = [];
  const orig = console.error;
  console.error = (...a) => errs.push(a.join(" "));
  let threw = null;
  try { loadGame({ difficultySource: difficultySourceWith(mutate) }); }
  catch (e) { threw = e; }
  finally { console.error = orig; }
  return { threw, errs };
}

/** The single game <script> block + brace-matched function body — the
    source-contract pattern (see tests/uifix1.test.mjs). */
function gameScript() {
  const html = readFileSync(join(HERE, "..", "index.html"), "utf8");
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
/** Pull one self-contained top-level function out of the game script and
    return it as a callable (for the pure histogram-bucketing helpers, which
    live inside the UI closure and aren't exported by the harness). */
function extractFn(src, name) {
  const at = src.indexOf("function " + name + "(");
  if (at === -1) return null;
  const open = src.indexOf("{", at);
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === "{") depth++;
    else if (src[i] === "}" && --depth === 0) {
      const text = src.slice(at, i + 1);
      return new Function(text + "\n;return " + name + ";")();
    }
  }
  return null;
}

/** Minimal in-memory localStorage (the harness's storage stub). */
function memStorage(init = {}) {
  const data = { ...init };
  return {
    getItem: (k) => (k in data ? data[k] : null),
    setItem: (k, v) => { data[k] = String(v); },
    removeItem: (k) => { delete data[k]; },
    _data: data,
  };
}

// The spec-fixed Zen suit schedule (R3): 2 suits = ♥♠, 3 = ♥♠♦, 4 = all four.
// Suit IDENTITY is a rule, not a tunable — only the COUNT comes from the data.
const ZEN_SUITS = ["♥", "♠", "♦", "♣"];

export function run() {
  const r = makeRunner("zen1.test.mjs");

  // ---- zen block: well-formed live data loads + exposes the registry -------
  {
    const { DifficultyData } = loadGame();
    r.eq(JSON.stringify(DifficultyData.zenIds), JSON.stringify(["easy", "medium", "hard"]),
      "DifficultyData.zenIds = easy/medium/hard");
    for (const id of DifficultyData.zenIds) {
      const z = DifficultyData.zen(id);
      r.ok(typeof z.label === "string" && z.label.length > 0, `zen.${id}.label is a non-empty string`);
      r.ok(Number.isInteger(z.suitCount) && z.suitCount >= 1 && z.suitCount <= 4,
        `zen.${id}.suitCount is an integer 1-4 (got ${z.suitCount})`);
      r.ok(Number.isInteger(z.piles) && z.piles >= 1, `zen.${id}.piles is a positive integer (got ${z.piles})`);
    }
    r.eq(DifficultyData.zen("nonsense").label, DifficultyData.zen("easy").label,
      "an unknown zen id falls back to easy");
  }

  // ---- zen block: malformed entries FAIL LOUDLY naming zen + entry + field --
  {
    const cases = [
      ["suitCount out of range", (d) => { d.zen.medium.suitCount = 0; }, "zen.medium", "suitCount"],
      ["suitCount non-integer", (d) => { d.zen.hard.suitCount = 2.5; }, "zen.hard", "suitCount"],
      ["piles invalid", (d) => { d.zen.easy.piles = 0; }, "zen.easy", "piles"],
      ["piles missing", (d) => { delete d.zen.medium.piles; }, "zen.medium", "piles"],
      ["label empty", (d) => { d.zen.hard.label = ""; }, "zen.hard", "label"],
      ["entry missing", (d) => { delete d.zen.easy; }, "zen.easy", "missing zen entry"],
      ["zen block missing", (d) => { delete d.zen; }, "zen", "missing object"],
    ];
    for (const [name, mutate, entry, field] of cases) {
      const { threw, errs } = loadExpectingFailure(mutate);
      r.ok(threw && /difficulty\.js validation FAILED/.test(threw.message), `malformed zen (${name}) throws on load`);
      r.ok(errs.some((l) => l.includes(entry) && l.includes(field)),
        `…and a console.error names "${entry}" + "${field}"`);
    }
    // Control: the untouched live file still loads clean.
    const { threw } = { threw: null };
    let ok = true;
    try { loadGame({ difficultySource: difficultySourceWith(() => {}) }); } catch (e) { ok = false; }
    r.ok(ok && !threw, "the unmutated live zen block validates clean");
  }

  // ---- firstDealBand / subset: malformed entries FAIL LOUDLY naming the field --
  {
    const cases = [
      ["firstDealBand missing", (d) => { delete d.firstDealBand; }, "firstDealBand", "[lo, hi]"],
      ["firstDealBand lo > hi", (d) => { d.firstDealBand = [2, 1]; }, "firstDealBand", "lo > hi"],
      ["firstDealBand non-numeric", (d) => { d.firstDealBand = [1, "x"]; }, "firstDealBand", "[lo, hi]"],
      ["subset missing", (d) => { delete d.subset; }, "subset", "missing object"],
      ["subset.threshold invalid", (d) => { d.subset.threshold = 0; }, "subset.threshold", "positive integer"],
      ["subset.min non-integer", (d) => { d.subset.min = 15.5; }, "subset.min", "positive integer"],
      ["subset min > max", (d) => { d.subset.min = 99; }, "subset", "min > max"],
    ];
    for (const [name, mutate, entry, field] of cases) {
      const { threw, errs } = loadExpectingFailure(mutate);
      r.ok(threw && /difficulty\.js validation FAILED/.test(threw.message), `malformed data (${name}) throws on load`);
      r.ok(errs.some((l) => l.includes(entry) && l.includes(field)),
        `…and a console.error names "${entry}" + "${field}"`);
    }
  }

  // ---- deck construction: suitCount × 13 fresh cards, exact copies, clean ---
  {
    const { DifficultyData, DeckManager } = loadGame();
    for (const id of DifficultyData.zenIds) {
      const z = DifficultyData.zen(id);
      const deck = DeckManager.buildZenDeck(z.suitCount);
      r.eq(deck.length, z.suitCount * 13, `${id}: deck = suitCount × 13 cards`);
      // Exactly suitCount copies of each of the 13 ranks (2..A).
      const perRank = {};
      for (const c of deck) perRank[c.currentRank] = (perRank[c.currentRank] || 0) + 1;
      r.eq(Object.keys(perRank).length, 13, `${id}: all 13 ranks present`);
      r.ok(Object.values(perRank).every((n) => n === z.suitCount),
        `${id}: exactly ${z.suitCount} copies of every rank`);
      // The spec-fixed suit subset: first suitCount of ♥ ♠ ♦ ♣.
      const suits = [...new Set(deck.map((c) => c.suit))].sort();
      const want = ZEN_SUITS.slice(0, z.suitCount).sort();
      r.eq(JSON.stringify(suits), JSON.stringify(want), `${id}: suits = ${want.join("")}`);
      // Fresh + unmodified: no jokers, no stickers, no modifications, ranks intact.
      r.ok(deck.every((c) => !c.joker && !c.blank), `${id}: zero jokers/blanks`);
      r.ok(deck.every((c) => (c.stickers || []).length === 0), `${id}: zero stickers`);
      r.ok(deck.every((c) => (c.modifications || []).length === 0 && c.currentRank === c.originalRank),
        `${id}: no rank modifications`);
      // Rebuilding never shares card objects (each game is a truly fresh deck).
      const deck2 = DeckManager.buildZenDeck(z.suitCount);
      r.ok(deck2.length === deck.length && deck2.every((c, i) => c !== deck[i]),
        `${id}: every deal builds fresh card objects`);
    }
  }

  // ---- pile counts + layouts -----------------------------------------------
  {
    const { DifficultyData, CampaignState } = loadGame();
    for (const id of DifficultyData.zenIds) {
      const z = DifficultyData.zen(id);
      const cfg = CampaignState.layoutForPiles(z.piles);
      r.eq(cfg.piles, z.piles, `${id}: layoutForPiles keeps the zen pile count`);
      r.eq(cfg.cols.reduce((a, b) => a + b, 0), z.piles, `${id}: column sizes sum to the pile count`);
      r.eq(cfg.rows, Math.max(...cfg.cols), `${id}: rows = tallest column`);
      r.ok(cfg.cols.length <= 3, `${id}: at most 3 columns`);
    }
    // The three shipped counts map to the documented balanced layouts (pure
    // function behaviour — independent of the zen tunables above).
    r.eq(JSON.stringify(CampaignState.layoutForPiles(7).cols), JSON.stringify([2, 3, 2]), "7 piles → [2,3,2]");
    r.eq(JSON.stringify(CampaignState.layoutForPiles(8).cols), JSON.stringify([3, 2, 3]), "8 piles → [3,2,3]");
    r.eq(JSON.stringify(CampaignState.layoutForPiles(9).cols), JSON.stringify([3, 3, 3]), "9 piles → [3,3,3]");
  }

  // ---- engine under a Zen config: no cols, no Pillars, empty Same bank ------
  {
    const { DifficultyData, DeckManager, GameEngine } = loadGame();
    const z = DifficultyData.zen(DifficultyData.zenIds[0]);
    const freshZen = () => {
      const e = GameEngine.create(DeckManager.buildZenDeck(z.suitCount), z.piles, {});
      e.start();
      e.startRun([], [], null);   // the Zen UI locks in NOTHING
      return e;
    };
    {
      const e = freshZen();
      const run = e.getRun();
      r.eq(run.cols, null, "no runConfig.cols → the engine carries no column info");
      r.eq(run.pileColumns, null, "…and no pile→column map (Pillar logic disabled)");
      r.eq(JSON.stringify(run.pillars), "[]", "no Pillars bound (empty lock)");
      r.eq(JSON.stringify(run.bases), "[]", "no Bases bound (empty lock)");
      r.eq(run.samePower, null, "no Same-Power equipped");
      r.eq(e.sameCharge(), false, "the Same-Charge bank starts EMPTY every game");
      r.eq(e.getBoard().size, z.piles, "board deals the zen pile count");
      r.eq(e.getDeck().remaining(), z.suitCount * 13 - z.piles, "deck after deal = suitCount×13 − piles");
    }
    // Tie kills a directional call; a correct Same banks the charge, which
    // later rescues a pile from death (the built-in bank, R4).
    {
      const e = freshZen();
      const top = e.getBoard().top(0).value;
      e.debug.setNextCard(top);
      e.guess(0, "higher");
      r.ok(!e.getBoard().isActive(0), "zen: tie on HIGHER kills the pile");
    }
    {
      const e = freshZen();
      const top0 = e.getBoard().top(0).value;
      e.debug.setNextCard(top0);
      e.guess(0, "same");
      r.ok(e.getBoard().isActive(0), "zen: correct SAME survives the tie");
      r.eq(e.sameCharge(), true, "…and BANKS the Same Charge");
      const top1 = e.getBoard().top(1).value;
      e.debug.setNextCard(top1);          // lethal tie on a directional call…
      e.guess(1, "higher");
      r.ok(e.getBoard().isActive(1), "…which then RESCUES a dying pile");
      r.eq(e.sameCharge(), false, "…and is spent by the rescue");
    }
    // WIN: guessing with knowledge of the next card never loses a pile, so
    // the deck empties with everything alive → status "won".
    {
      const e = freshZen();
      let guard = 200;
      while (!e.getDeck().isEmpty() && e.getStatus() === "playing" && guard-- > 0) {
        const next = e.getDeck().peek(1)[0];
        const top = e.getBoard().top(0).value;
        e.guess(0, next.value > top ? "higher" : next.value < top ? "lower" : "same");
      }
      r.eq(e.getStatus(), "won", "deck exhausted with piles alive → WIN");
      r.eq(e.getBoard().aliveCount(), z.piles, "…every pile survived the perfect game");
    }
    // LOSS: deliberately wrong guesses kill a pile each (the bank never fills
    // — no correct Same is ever made) → all dead before the deck runs out.
    {
      const e = freshZen();
      let guard = 100;
      while (e.getStatus() === "playing" && guard-- > 0) {
        const board = e.getBoard();
        let idx = -1;
        for (let i = 0; i < board.size; i++) if (board.isActive(i)) { idx = i; break; }
        const next = e.getDeck().peek(1)[0];
        const top = board.top(idx).value;
        e.guess(idx, next.value > top ? "lower" : "higher");   // guaranteed wrong (ties kill H/L)
      }
      r.eq(e.getStatus(), "lost", "all piles dead → LOSS");
      r.eq(e.getBoard().aliveCount(), 0, "…zero piles alive at the loss");
      r.ok(!e.getDeck().isEmpty(), "…with cards still in the deck");
    }
  }

  // ---- ZenStats: per-difficulty recording, defaults, round-trip, isolation --
  {
    const storage = memStorage();
    const g = loadGame({ localStorage: storage });
    const { ZenStats, Stats, DifficultyData } = g;
    const ids = DifficultyData.zenIds;
    // Absent key → zeros + empty distributions (never throws).
    r.eq(JSON.stringify(ZenStats.get(ids[0])),
      JSON.stringify({ games: 0, wins: 0, cardsFlipped: 0, correctGuesses: 0, winPiles: {}, lossCards: {} }),
      "absent zen-stats key reads as zeros + empty distributions");
    // Campaign Stats baseline FIRST — Zen recording must never move it.
    Stats.runPlayed();
    const campaignStatsBefore = storage.getItem("mnesis.stats.v1");
    // Record a small Zen session on the first difficulty.
    ZenStats.gamePlayed(ids[0]);
    ZenStats.guess(ids[0], true);
    ZenStats.guess(ids[0], false);
    ZenStats.guess(ids[0], true);
    ZenStats.win(ids[0]);
    const e0 = ZenStats.get(ids[0]);
    r.eq(e0.games, 1, "gamePlayed increments games");
    r.eq(e0.cardsFlipped, 3, "every guess counts a card flipped");
    r.eq(e0.correctGuesses, 2, "…and correct guesses only when correct");
    r.eq(e0.wins, 1, "win increments wins");
    // Other difficulties stay untouched (per-difficulty breakdown).
    r.eq(JSON.stringify(ZenStats.get(ids[1])),
      JSON.stringify({ games: 0, wins: 0, cardsFlipped: 0, correctGuesses: 0, winPiles: {}, lossCards: {} }),
      "recording on one difficulty never moves another");
    // Campaign stats blob is byte-identical after the Zen recording.
    r.eq(storage.getItem("mnesis.stats.v1"), campaignStatsBefore,
      "campaign Stats blob byte-identical after Zen recording");
    r.ok(storage.getItem("ninelives.zenstats.v1") !== null, "zen stats persist under their own ninelives.* key");
    // Round-trip: a SECOND load over the same storage reads the same numbers.
    const g2 = loadGame({ localStorage: storage });
    r.eq(JSON.stringify(g2.ZenStats.get(ids[0])), JSON.stringify(e0), "zen stats round-trip across loads");
    // Corrupted key → zeros, never throws; reset() empties the store.
    storage.setItem("ninelives.zenstats.v1", "{not json");
    r.eq(g2.ZenStats.get(ids[0]).games, 0, "corrupted zen-stats key reads as zeros (no throw)");
    g2.ZenStats.reset();
    r.eq(g2.ZenStats.get(ids[0]).cardsFlipped, 0, "reset() empties the zen record");
  }

  // ---- source contracts: the Zen page replaced the picker; loss has a sound -
  {
    // ZEN2: the difficulty choice is a dedicated full-screen page (#zenSelect,
    // the #deckSelect menu-screen pattern with a corner Back), not the old
    // prompt-bar picker — the zen-picking CSS lift and showZenPicker must be
    // GONE, and the main menu's Zen item must open the new page.
    const html = readFileSync(join(HERE, "..", "index.html"), "utf8");
    r.ok(!html.includes("zen-picking"), "no body.zen-picking CSS/JS survives (prompt-bar picker removed)");
    r.ok(/<div class="menu-screen hidden" id="zenSelect">/.test(html),
      "the Zen difficulty page exists as a full-screen menu-screen");
    r.ok(/<button class="nav-btn zs-back-btn" id="zsBack"/.test(html),
      "…with the corner-nav Back button (the #deckSelect convention)");
    const src = gameScript();
    r.ok(!src.includes("showZenPicker"), "showZenPicker is gone from the game script");
    const menu = fnBody(src, "showMainMenu");
    r.ok(menu.includes("showZenSelect(canContinue)"),
      "the main-menu Zen item opens the page (Continue preserved for Back)");
    // The end-of-game jingles mirror the campaign's analogous moments.
    const end = fnBody(src, "onZenEnd");
    r.ok(end.includes("Sound.dealWon()"), "zen win plays the deal-won jingle");
    r.ok(end.includes("Sound.dealLost()"), "zen loss plays the deal-lost jingle");
  }

  // ---- ZenStats: a hand-edited SCALAR blob can never break recording -------
  {
    for (const blob of ["5", '"x"', "true", "[1,2]"]) {
      const storage = memStorage({ "ninelives.zenstats.v1": blob });
      const { ZenStats, DifficultyData } = loadGame({ localStorage: storage });
      const id = DifficultyData.zenIds[0];
      r.eq(ZenStats.get(id).games, 0, `scalar zen-stats blob ${blob} reads as zeros`);
      let threw = false;
      try { ZenStats.guess(id, true); } catch (e) { threw = true; }
      r.ok(!threw && ZenStats.get(id).cardsFlipped === 1,
        `…and recording over blob ${blob} replaces it instead of throwing`);
    }
  }

  // ---- source contract: startZenDeal tears down the map/store overlays -----
  // quitToMenu is navigational-only, so quitting from the campaign MAP or
  // STORE leaves those fixed overlays up behind the menu; a Zen deal must
  // drop BOTH (or they cover the Zen board and the map's node taps stay live
  // under the Zen session, mutating the in-memory campaign).
  {
    const body = fnBody(gameScript(), "startZenDeal");
    r.ok(body.length > 0, "startZenDeal exists in the game script");
    r.ok(body.includes("closeStore()"), "startZenDeal closes a leftover store overlay");
    r.ok(body.includes("hideProgressionMap()"), "startZenDeal drops a leftover campaign map (and body.on-map)");
  }

  // ---- campaign isolation: a FULL Zen game leaves the campaign untouched ----
  {
    const storage = memStorage();
    const { DifficultyData, DeckManager, GameEngine, CampaignState, ZenStats, Stats } =
      loadGame({ localStorage: storage });
    const camp = CampaignState.create();
    camp.reset();
    const campBefore = JSON.stringify(camp.serialize());
    const statsBefore = storage.getItem("mnesis.stats.v1");
    // Play one COMPLETE Zen game to a win (with the ZenStats recording the
    // Zen UI performs), on the last (hardest) difficulty.
    const id = DifficultyData.zenIds[DifficultyData.zenIds.length - 1];
    const z = DifficultyData.zen(id);
    const e = GameEngine.create(DeckManager.buildZenDeck(z.suitCount), z.piles, {});
    e.start();
    e.startRun([], [], null);
    let first = true, guard = 200;
    while (!e.getDeck().isEmpty() && e.getStatus() === "playing" && guard-- > 0) {
      const next = e.getDeck().peek(1)[0];
      const top = e.getBoard().top(0).value;
      const dir = next.value > top ? "higher" : next.value < top ? "lower" : "same";
      e.guess(0, dir);
      if (first) { first = false; ZenStats.gamePlayed(id); }
      ZenStats.guess(id, true);
    }
    r.eq(e.getStatus(), "won", "the isolation probe's zen game completed (win)");
    ZenStats.win(id);
    r.eq(JSON.stringify(camp.serialize()), campBefore,
      "campaign serialize() byte-identical after a full Zen game");
    r.eq(storage.getItem("mnesis.stats.v1"), statsBefore,
      "campaign Stats storage untouched by the full Zen game");
    r.ok(ZenStats.get(id).games === 1 && ZenStats.get(id).wins === 1,
      "…while the ZEN record moved as expected");
  }

  // ---- ZenStats distributions: winPiles on a win, lossCards on a loss ------
  // (ZEN3) Each game end folds a count into that difficulty's own map — a win
  // records piles-alive under winPiles, a loss records cards-left under
  // lossCards. Forward-only: the legacy games/wins scalars are never mixed in.
  {
    const storage = memStorage();
    const { ZenStats, DifficultyData } = loadGame({ localStorage: storage });
    const ids = DifficultyData.zenIds;
    const D = ids[ids.length - 1];              // hardest difficulty
    const P = DifficultyData.zen(D).piles;      // its pile count, live
    // A win with the top piles-remaining, twice, plus a smaller win.
    ZenStats.win(D, P);
    ZenStats.win(D, P);
    ZenStats.win(D, 1);
    const e = ZenStats.get(D);
    r.eq(e.winPiles[P], 2, "win(diff, piles) tallies winPiles at the piles-remaining count");
    r.eq(e.winPiles[1], 1, "…each distinct pile count gets its own bucket");
    r.eq(e.wins, 3, "…and the legacy wins scalar still advances alongside");
    // Losses record cards-left; distinct values stack independently.
    ZenStats.loss(D, 5);
    ZenStats.loss(D, 5);
    ZenStats.loss(D, 22);
    const e2 = ZenStats.get(D);
    r.eq(e2.lossCards[5], 2, "loss(diff, cardsLeft) tallies lossCards at the remaining count");
    r.eq(e2.lossCards[22], 1, "…distinct remaining counts get their own bucket");
    // A loss NEVER moves winPiles and a win NEVER moves lossCards (twin maps).
    r.eq(JSON.stringify(e2.winPiles), JSON.stringify(e.winPiles),
      "recording a loss leaves winPiles untouched");
    // Legacy win() with NO piles arg advances wins but records no distribution.
    const D2 = ids[0];
    ZenStats.win(D2);
    r.eq(ZenStats.get(D2).wins, 1, "win(diff) with no piles still counts the win");
    r.eq(JSON.stringify(ZenStats.get(D2).winPiles), "{}",
      "…but records nothing into the winPiles distribution");
    // Round-trip across a reload.
    const g2 = loadGame({ localStorage: storage });
    r.eq(JSON.stringify(g2.ZenStats.get(D).lossCards), JSON.stringify(e2.lossCards),
      "loss distribution round-trips across loads");
    // reset() empties the distributions too.
    g2.ZenStats.reset();
    const e3 = g2.ZenStats.get(D);
    r.ok(Object.keys(e3.winPiles).length === 0 && Object.keys(e3.lossCards).length === 0,
      "reset() empties every difficulty's distribution maps");
  }

  // ---- MIGRATION: a v1 entry lacking the maps reads both as empty ----------
  // A blob written before the distributions existed (only the four scalars)
  // must load without throwing, reading winPiles/lossCards as empty, and keep
  // recording from there.
  {
    const ids0 = loadGame().DifficultyData.zenIds;
    const legacy = { [ids0[0]]: { games: 9, wins: 4, cardsFlipped: 80, correctGuesses: 55 } };
    const storage = memStorage({ "ninelives.zenstats.v1": JSON.stringify(legacy) });
    const { ZenStats, DifficultyData } = loadGame({ localStorage: storage });
    const id = DifficultyData.zenIds[0];
    const e = ZenStats.get(id);
    r.eq(e.games, 9, "legacy scalar fields survive the migration read");
    r.ok(Object.keys(e.winPiles).length === 0 && Object.keys(e.lossCards).length === 0,
      "…and the absent maps read as EMPTY distributions (no throw)");
    let threw = false;
    try { ZenStats.win(id, 3); ZenStats.loss(id, 7); } catch (x) { threw = true; }
    r.ok(!threw && ZenStats.get(id).winPiles[3] === 1 && ZenStats.get(id).lossCards[7] === 1,
      "…recording over a legacy entry adds the maps instead of throwing");
    // A per-entry map that is a hand-edited SCALAR reads as empty, never throws.
    const storage2 = memStorage({
      "ninelives.zenstats.v1": JSON.stringify({ [ids0[0]]: { winPiles: 5, lossCards: "x" } }),
    });
    const g2 = loadGame({ localStorage: storage2 });
    const e2 = g2.ZenStats.get(ids0[0]);
    r.ok(Object.keys(e2.winPiles).length === 0 && Object.keys(e2.lossCards).length === 0,
      "a scalar/garbage distribution map reads as empty (fail-soft)");
  }

  // ---- LOSS BUCKETING: derived live from each difficulty's deck size -------
  // The bucketing is a pure function of the card count. Singletons 1..5, then
  // decades trimmed to the deck; a sub-5 trailing remainder folds into the
  // previous decade so no orphan bucket forms. All boundaries read from the
  // live suitCount×13 deck size — never pinned.
  {
    const src = gameScript();
    const zenLossBuckets = extractFn(src, "zenLossBuckets");
    const zenBucketLabel = extractFn(src, "zenBucketLabel");
    const zenBucketCounts = extractFn(src, "zenBucketCounts");
    r.ok(typeof zenLossBuckets === "function" && typeof zenBucketLabel === "function"
      && typeof zenBucketCounts === "function", "the histogram bucketing helpers are present");
    const { DifficultyData } = loadGame();
    const labelOf = (buckets, v) => {
      for (const b of buckets) if (v >= b[0] && v <= b[1]) return zenBucketLabel(b);
      return null;
    };
    for (const id of DifficultyData.zenIds) {
      const z = DifficultyData.zen(id);
      const deckSize = z.suitCount * 13;         // live deck size
      const buckets = zenLossBuckets(deckSize);
      // Contiguous cover of 1..deckSize (no gaps, no overlaps).
      r.eq(buckets[0][0], 1, `${id}: buckets start at 1`);
      r.eq(buckets[buckets.length - 1][1], deckSize, `${id}: top bucket ends at the deck size (${deckSize})`);
      let contiguous = true;
      for (let i = 1; i < buckets.length; i++) if (buckets[i][0] !== buckets[i - 1][1] + 1) contiguous = false;
      r.ok(contiguous, `${id}: buckets are contiguous (no gaps/overlaps)`);
      // Singletons 1..5.
      r.ok([1, 2, 3, 4, 5].every((n) => labelOf(buckets, n) === String(n)),
        `${id}: values 1..5 are singleton buckets`);
      // No orphan: the top bucket spans at least a singleton-run (≥5) for a
      // real Zen deck (≥ 20 cards), proving the sub-5 remainder folded in.
      const top = buckets[buckets.length - 1];
      r.ok((top[1] - top[0] + 1) >= 5, `${id}: the top bucket is never a sub-5 orphan`);
    }
    // Spec acceptance examples, keyed off the LIVE deck sizes:
    // the widest deck buckets a mid value into its decade and folds its tail.
    const hard = DifficultyData.zenIds
      .map((id) => ({ id, deck: DifficultyData.zen(id).suitCount * 13 }))
      .sort((a, b) => b.deck - a.deck)[0];
    const hb = zenLossBuckets(hard.deck);
    r.eq(labelOf(hb, 25), "21-30", `widest deck (${hard.deck}): 25 → "21-30"`);
    r.eq(labelOf(hb, hard.deck), "41-" + hard.deck, `widest deck: ${hard.deck} → "41-${hard.deck}" (tail folded)`);
    // The smallest deck's top bucket ends at its deck size (a plain trim).
    const easy = DifficultyData.zenIds
      .map((id) => ({ id, deck: DifficultyData.zen(id).suitCount * 13 }))
      .sort((a, b) => a.deck - b.deck)[0];
    const eb = zenLossBuckets(easy.deck);
    r.ok(eb[eb.length - 1][1] === easy.deck && labelOf(eb, easy.deck).endsWith("-" + easy.deck),
      `smallest deck (${easy.deck}): top bucket ends at ${easy.deck}`);
    // zenBucketCounts folds a distribution so the bars SUM to the total losses,
    // clamping a 0-left "died on the final card" into the first bucket.
    const dist = { 0: 2, 3: 1, 25: 4, [hard.deck]: 1 };   // 8 losses total
    const totals = zenBucketCounts(dist, hb, hard.deck);
    const sum = totals.reduce((a, b) => a + b, 0);
    r.eq(sum, 8, "bucket counts sum to the total losses (every loss placed exactly once)");
    r.eq(totals[labelIndex(hb, 25)], 4, "…25-card losses land in their decade bucket");
    r.eq(totals[0], 2, "…a 0-left loss folds into the first bucket (bucket \"1\")");
    r.eq(totals[labelIndex(hb, hard.deck)], 1, "…a full-deck loss lands in the top bucket");
  }

  return r.summary();
}

/** Index of the bucket containing v (helper for the bucketing assertions). */
function labelIndex(buckets, v) {
  for (let i = 0; i < buckets.length; i++) if (v >= buckets[i][0] && v <= buckets[i][1]) return i;
  return -1;
}
