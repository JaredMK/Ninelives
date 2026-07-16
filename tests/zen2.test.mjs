// ZEN2 — the Zen difficulty page's unlock LADDER (ZenUnlocks): the first
// difficulty is always playable, each later one unlocks when its predecessor
// has a recorded Zen win. The store is DeckUnlocks' model under its own
// ninelives.* key — grant-on-win (new vs repeat), retroactive grant at load
// from pre-existing ZenStats wins, fail-soft reads over corrupted/scalar
// blobs, and RESET-SAFETY (a stats reset never re-locks a difficulty).
//
// Registry-driven: every difficulty id comes LIVE from DifficultyData.zenIds
// (order included) — no id, label or count is pinned.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadGame, makeRunner } from "./_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const UNLOCK_KEY = "ninelives.zenunlocks.v1";
const STATS_KEY = "ninelives.zenstats.v1";

/** The single game <script> block + brace-matched function body — the
    source-contract pattern (see tests/zen1.test.mjs). */
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

export function run() {
  const r = makeRunner("zen2.test.mjs");

  // ---- fresh profile: only the first difficulty is playable ---------------
  {
    const storage = memStorage();
    const { ZenUnlocks, DifficultyData } = loadGame({ localStorage: storage });
    const ids = DifficultyData.zenIds;
    r.ok(ids.length >= 2, `difficulty.js declares a zen ladder (${ids.length} ids)`);
    r.ok(ZenUnlocks.unlocked(ids[0]), "the FIRST zen difficulty is always unlocked");
    for (let i = 1; i < ids.length; i++)
      r.ok(!ZenUnlocks.unlocked(ids[i]), `fresh profile: ${ids[i]} is locked (predecessor unbeaten)`);
    r.ok(!ZenUnlocks.beaten(ids[0]), "…and nothing reads as beaten yet");
  }

  // ---- grant-on-win: new vs repeat; the ladder opens one rung per win ------
  {
    const storage = memStorage();
    const { ZenUnlocks, DifficultyData } = loadGame({ localStorage: storage });
    const ids = DifficultyData.zenIds;
    r.ok(ZenUnlocks.recordWin(ids[0]) === true, "the FIRST win at a difficulty reports a NEW grant");
    r.ok(ZenUnlocks.unlocked(ids[1]), "…which unlocks the next difficulty");
    if (ids.length > 2)
      r.ok(!ZenUnlocks.unlocked(ids[2]), "…but not the one after (one rung per beaten difficulty)");
    r.ok(ZenUnlocks.recordWin(ids[0]) === false, "a REPEAT win reports no new grant (no unlock line)");
    r.ok(ZenUnlocks.recordWin(ids[1]) === true, "beating the next difficulty is again a new grant");
    if (ids.length > 2)
      r.ok(ZenUnlocks.unlocked(ids[2]), "…opening the rung after it");
    r.ok(ZenUnlocks.recordWin("") === false && ZenUnlocks.recordWin(null) === false,
      "an empty/absent id never grants");
    // Round-trip: persisted under its OWN ninelives.* key, read back by a
    // second load over the same storage.
    r.ok(storage.getItem(UNLOCK_KEY) !== null, "unlocks persist under their own ninelives.* key");
    const g2 = loadGame({ localStorage: storage });
    r.ok(g2.ZenUnlocks.beaten(ids[0]) && g2.ZenUnlocks.beaten(ids[1]),
      "unlocks round-trip across loads");
  }

  // ---- retroactive grant: pre-existing ZenStats wins open the ladder -------
  // A profile that won Zen games BEFORE the unlock store existed: at module
  // load (before any UI reads locks) every difficulty with wins >= 1 is
  // credited, so the page opens the next difficulty on the first visit.
  {
    const ids0 = loadGame().DifficultyData.zenIds;   // live ids for the seeded blob
    const storage = memStorage({
      [STATS_KEY]: JSON.stringify({ [ids0[0]]: { games: 5, wins: 2, cardsFlipped: 40, correctGuesses: 30 } }),
    });
    const { ZenUnlocks, DifficultyData } = loadGame({ localStorage: storage });
    const ids = DifficultyData.zenIds;
    r.ok(ZenUnlocks.beaten(ids[0]), "existing zenstats wins grant retroactively at load");
    r.ok(ZenUnlocks.unlocked(ids[1]), "…so the next difficulty is unlocked on first visit");
    if (ids.length > 2)
      r.ok(!ZenUnlocks.unlocked(ids[2]), "…and unwon difficulties grant nothing");
    r.ok(storage.getItem(UNLOCK_KEY) !== null,
      "the retroactive grant was PERSISTED at load (module-load placement, before any UI)");
    // A repeat of the retroactively-granted win is NOT a new grant (no line).
    r.ok(ZenUnlocks.recordWin(ids[0]) === false,
      "a live win after the retroactive grant reports no new grant");
  }

  // ---- fail-soft: corrupted/scalar unlock blobs read as nothing beaten -----
  {
    for (const blob of ["{not json", "5", '"x"', "true", "[1,2]"]) {
      const storage = memStorage({ [UNLOCK_KEY]: blob });
      let g = null, threw = false;
      try { g = loadGame({ localStorage: storage }); } catch (e) { threw = true; }
      r.ok(!threw, `unlock blob ${JSON.stringify(blob)} never throws at load`);
      if (!g) continue;
      const ids = g.DifficultyData.zenIds;
      r.ok(g.ZenUnlocks.unlocked(ids[0]) && !g.ZenUnlocks.unlocked(ids[1]),
        `…and reads as nothing beaten (first open, rest locked) over ${JSON.stringify(blob)}`);
      r.ok(g.ZenUnlocks.recordWin(ids[0]) === true && g.ZenUnlocks.unlocked(ids[1]),
        `…while recording over it replaces the blob instead of throwing`);
    }
  }

  // ---- RESET-SAFE: a stats reset zeroes tallies but never re-locks ---------
  {
    const storage = memStorage();
    const g = loadGame({ localStorage: storage });
    const ids = g.DifficultyData.zenIds;
    g.ZenStats.win(ids[0]);          // the win path records BOTH stores
    g.ZenUnlocks.recordWin(ids[0]);
    g.ZenStats.reset();              // the Stats screen's reset button scope
    r.ok(g.ZenStats.get(ids[0]).wins === 0, "ZenStats.reset() zeroes the tallies");
    r.ok(g.ZenUnlocks.unlocked(ids[1]), "…but the ladder stays open (locks never derive from stats)");
    // Even across a fresh load AFTER the reset (zenstats now empty, so the
    // retroactive pass re-grants nothing) the unlock store alone keeps it open.
    const g2 = loadGame({ localStorage: storage });
    r.ok(g2.ZenUnlocks.unlocked(ids[1]), "…and stays open across a reload after the reset");
    // The store deliberately has NO reset — nothing for the button to call.
    r.ok(typeof g2.ZenUnlocks.reset === "undefined", "ZenUnlocks exposes no reset()");
  }

  // ---- source contracts: page rendering, win path, overlay unchanged -------
  {
    const src = gameScript();
    r.ok(!src.includes("ZenUnlocks.reset"), "nothing in the game (incl. the stats Reset button) resets ZenUnlocks");
    // R2: the page reads every number LIVE from the registries — ids/labels
    // via DifficultyData, deck size derived suitCount×13, gate via ZenUnlocks.
    const page = fnBody(src, "showZenSelect");
    r.ok(page.includes("DifficultyData.zenIds.map"), "page entries iterate DifficultyData.zenIds in order");
    r.ok(page.includes("z.suitCount * 13"), "card counts derive live from suitCount × 13");
    r.ok(page.includes("z.piles"), "pile counts read live from difficulty.js");
    r.ok(page.includes("ZenUnlocks.unlocked(id)"), "each entry's gate reads the unlock store");
    r.ok(page.includes("ZenStats.get(id).wins"), "each entry shows its ZenStats win count");
    r.ok(page.includes("escHtml(z.label)") && page.includes("to unlock"),
      "locked entries keep their REAL label with the unlock condition stated");
    r.ok(page.includes('disabled'), "locked entries render disabled (taps inert)");
    r.ok(page.includes("showMainMenu(canContinue)"),
      "Back returns to the main menu with Continue preserved (deckSelectReturn pattern)");
    // R6/R7: the win path grants once and rides the existing minimal overlay —
    // still exactly Play Again + Menu (to the MAIN menu), never the new page.
    const end = fnBody(src, "onZenEnd");
    r.ok(end.includes("ZenUnlocks.recordWin(zenMode.diff)"), "onZenEnd's win path records the unlock grant");
    r.ok(end.includes('unlocked!"'), "a NEW grant arms the one-line unlock note");
    r.ok(end.includes('btnLabel: "Play Again"') && end.includes('btn2Label: "Menu"')
      && end.includes("btn2Action: zenQuitToMenu"),
      "the end overlay is unchanged: Play Again + Menu → main menu (zenQuitToMenu)");
    // R10: the page adds no tutorial hooks (deck select owns the tour entry).
    r.ok(!page.includes("Tutorial."), "the Zen page arms no tutorial hooks");
  }

  // ---- ZEN3: select-then-Start on #zenSelect -------------------------------
  // Tapping a difficulty SELECTS it; only Start begins the game. Start is
  // disabled until a pick; selection resets each time the page is shown.
  {
    const html = readFileSync(join(HERE, "..", "index.html"), "utf8");
    r.ok(/<button class="zs-start" id="zsStart"[^>]*disabled/.test(html),
      "the page ships a Start button, disabled by default (nothing selected)");
    const src = gameScript();
    const show = fnBody(src, "showZenSelect");
    r.ok(show.includes("zenSelectedId = null") && show.includes('el.zsStart.disabled = true'),
      "showZenSelect resets the selection + re-disables Start each show");
    const pick = fnBody(src, "zenSelectPick");
    r.ok(pick.length > 0 && pick.includes('classList.toggle("selected"')
      && pick.includes("el.zsStart.disabled = false"),
      "zenSelectPick marks the entry selected and enables Start");
    // The list handler SELECTS (no startZen); Start alone starts via startZen.
    const listIdx = src.indexOf("el.zsList.addEventListener");
    const listHandler = src.slice(listIdx, listIdx + 400);
    r.ok(listHandler.includes("zenSelectPick(") && !listHandler.includes("startZen("),
      "tapping an entry only selects (the list handler never calls startZen)");
    r.ok(listHandler.includes('entry.disabled') && listHandler.includes('classList.contains("locked")'),
      "…and a locked/disabled entry can never be selected (the guard stays)");
    const startIdx = src.indexOf("el.zsStart.addEventListener");
    const startHandler = src.slice(startIdx, startIdx + 300);
    r.ok(startHandler.includes("startZen(zenSelectedId)") && startHandler.includes("Sound.tap()"),
      "only the Start button begins play — startZen(selectedId), with a tap cue");
  }

  // ---- ZEN3: per-game end-overlay lines + distribution recording -----------
  {
    const src = gameScript();
    const end = fnBody(src, "onZenEnd");
    r.ok(end.includes("ZenStats.win(zenMode.diff, alive)"),
      "a win records piles-alive into the winPiles distribution");
    r.ok(end.includes("ZenStats.loss(zenMode.diff, cardsLeft)"),
      "a loss records cards-left into the lossCards distribution");
    r.ok(end.includes("payload.deck") && end.includes("remaining()"),
      "cards-left is the draw pile remaining at the loss");
    r.ok(end.includes("zenMode.flips") && end.includes("zenMode.correct"),
      "the overlay lines read the live per-game counters (not cumulative ZenStats)");
    r.ok(end.includes('"Cards guessed"') && end.includes('"Correct"'),
      "the overlay always shows flips + correct");
    r.ok(end.includes('"Piles remaining"') && end.includes('"Cards left in deck"'),
      "…plus piles-remaining on a win / cards-left on a loss");
    r.ok(end.includes("zenStats:"), "the lines ride the overlay via opts.zenStats");
    // The per-game counters are incremented in the guess handlers and reset per deal.
    const deal = fnBody(src, "startZenDeal");
    r.ok(deal.includes("zenMode.flips = 0") && deal.includes("zenMode.correct = 0"),
      "per-game counters reset each deal (Play Again reuses zenMode)");
  }

  // ---- ZEN4: Stats screen — ONE combined histogram, filter + drill + vertical
  // Re-points the ZEN3 per-difficulty structural assertions to the reworked
  // single-histogram markup (segmented filter, two-bar summary, vertical drill).
  {
    const src = gameScript();
    const stats = fnBody(src, "showStats");
    r.ok(stats.includes('stats-runs-head">Runs') , "showStats renders a 'Runs' header over the campaign tiles");
    r.ok(stats.includes('sz-head">Zen'), "…and a 'Zen' header over the Zen section");
    // R9: no per-difficulty stacking — one section built by zenSectionInner(),
    // and the ephemeral view resets to All + summary on every open.
    r.ok(!stats.includes("zenHistoBlock") && stats.includes("zenSectionInner()"),
      "the Zen section is one combined histogram (zenSectionInner), not per-difficulty blocks");
    r.ok(stats.includes('zenView = { scope: "all", drill: null }'),
      "each Stats open resets the ephemeral view to All + the two-bar summary");
    r.ok(!/function\s+zenHistoBlock\(/.test(src) && !/function\s+zenBar\(/.test(src),
      "the ZEN3 per-block render helpers (zenHistoBlock/zenBar) are gone");
    // R1: the segmented filter — always All + the live ladder, one selected, All open.
    const section = fnBody(src, "zenSectionInner");
    r.ok(section.includes('[["all", "All"]].concat(DifficultyData.zenIds.map')
      && section.includes("zf-opt"),
      "a four-option segmented filter (All + live ladder labels) heads the section");
    r.ok(section.includes('data-scope="') && section.includes('v === sc ? " selected"'),
      "the scoped option is visually distinguished (selected class)");
    // R8: ONE scope stats line, live per scope (not three stacked lines).
    r.ok(section.includes("zh-scope") && section.includes("d.games") && section.includes("d.wins")
      && section.includes("d.cardsFlipped") && section.includes("d.correctGuesses"),
      "one scope stats line reads games/wins/cards/correct for the current scope");
    // R2: level 0 is exactly two vertical summary columns (forward-only sums).
    r.ok(section.includes('zenVBar("Wins"') && section.includes('zenVBar("Losses"')
      && section.includes("zenSumMap(d.winPiles)") && section.includes("zenSumMap(d.lossCards)"),
      "level 0 shows two columns: Wins = winPiles sum, Losses = lossCards sum");
    r.ok(section.includes("zh-sum-win") && section.includes("zh-sum-loss"),
      "the two summary columns carry the drill hooks");
    r.ok(section.includes("zv-win") && section.includes("zv-loss"),
      "wins columns are green (zv-win), loss columns red (zv-loss)");
    // R3: drill levels — wins over piles 1..P, losses over the unchanged buckets.
    r.ok(section.includes('drill === "wins"') && section.includes("d.winPiles[p]")
      && section.includes("p <= d.piles"),
      "the wins drill renders one column per piles-remaining value, axis 1..maxPiles");
    r.ok(section.includes('drill === "losses"') && section.includes("zenLossBuckets(d.deckSize)")
      && section.includes("zenBucketCounts(d.lossCards"),
      "the losses drill reuses the bucket helpers over the scope's deck size");
    // R4: the Back chip appears only when drilled.
    r.ok(section.includes("zh-back") && section.includes("‹ Back"),
      "a '‹ Back' chip is emitted at level 1 (drilled) only");
    // R6: vertical, baseline-anchored bars replace the horizontal fill.
    const vbar = fnBody(src, "zenVBar");
    r.ok(vbar.includes("zv-bar") && vbar.includes("height:") && vbar.includes("zv-k") && vbar.includes("zv-c"),
      "zenVBar emits a vertical column (height-driven bar, key beneath, count above)");
    r.ok(!src.includes("zh-fill") && !src.includes("zh-track"),
      "no horizontal .zh-fill/.zh-track markup remains in the Zen section");
    // R1/R4/R3/R5: the delegated handler drives filter/back/drill and always
    // collapses drill on a filter change, with a tap cue on every path.
    const region = src.slice(src.indexOf("el.statsGrid.addEventListener"), src.indexOf("el.statsGrid.addEventListener") + 900);
    r.ok(region.includes('closest(".zf-opt")') && region.includes("zenView.scope = opt.dataset.scope")
      && region.includes("zenView.drill = null"),
      "a filter tap re-scopes and collapses the drill (R5)");
    r.ok(region.includes('closest(".zh-back")') && region.includes('closest(".zh-sum-win")')
      && region.includes('closest(".zh-sum-loss")'),
      "the handler wires Back + both summary-column drills");
    r.ok(region.includes('zenView.drill = "wins"') && region.includes('zenView.drill = "losses"')
      && region.includes("renderZenSection()") && region.includes("Sound.tap()"),
      "drills set the level, re-render in place, and cue a tap");
    // R1: "all" scope SUMS every difficulty's maps per key + spans the widest axes.
    const scope = fnBody(src, "zenScope");
    r.ok(scope.includes('scope !== "all"') && scope.includes("agg.winPiles[k]")
      && scope.includes("agg.lossCards[k]") && scope.includes("Math.max(agg.piles")
      && scope.includes("z.suitCount * 13"),
      "the 'all' scope aggregates per-key sums and spans max piles/deck across the ladder");
  }

  return r.summary();
}
