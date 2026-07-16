// ZEN6 — the Stats-screen Zen histogram MODEL: ONE continuous histogram row
// carrying the full column set for THREE view states on a single persistent
// node set, transitioning by a CSS class swap (never an innerHTML re-render).
//
// The semantic key: a WIN = 0 cards remaining, a LOSS = 0 piles remaining, so
// each outcome's TOTAL is the "0" slot of the OTHER outcome's axis. Thus:
//   • both-collapsed — two totals: Wins (green, sum winPiles) + Losses (red,
//     sum lossCards);
//   • wins-expanded  — the Losses total LEADS the win breakdown (piles 1..P);
//   • losses-expanded — the Wins total LEADS the loss breakdown (buckets).
//
// Source-contract style (see zen1/zen2): the game <script> is extracted and
// asserted structurally. Every axis (piles, deck size) is read LIVE from
// DifficultyData — nothing pinned.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadGame, makeRunner } from "./_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

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

export function run() {
  const r = makeRunner("zen6.test.mjs");
  const src = gameScript();
  const html = readFileSync(join(HERE, "..", "index.html"), "utf8");

  // ---- showStats scaffolding still resets the ephemeral view + heads ---------
  {
    const stats = fnBody(src, "showStats");
    r.ok(stats.includes('stats-runs-head">Runs'), "showStats heads the campaign tiles with 'Runs'");
    r.ok(stats.includes('sz-head">Zen') && stats.includes("zenSectionInner()"),
      "the Zen section is one combined histogram built by zenSectionInner()");
    r.ok(stats.includes('zenView = { scope: "all", drill: null }'),
      "each Stats open resets the ephemeral view to All + both-collapsed");
    // The ZEN3/ZEN4 per-block + single-max helpers are gone.
    r.ok(!/function\s+zenHistoBlock\(/.test(src) && !/function\s+zenBar\(/.test(src)
      && !/function\s+zenVBar\(/.test(src),
      "the superseded render helpers (zenHistoBlock/zenBar/zenVBar) are gone");
  }

  // ---- the persistent column builder: three height stops as CSS vars --------
  {
    const col = fnBody(src, "zenVCol");
    r.ok(col.length > 0, "a single zenVCol column builder exists");
    r.ok(col.includes("zv-c") && col.includes("zv-track") && col.includes("zv-bar") && col.includes("zv-k"),
      "zenVCol keeps the count-above / bar / key-beneath anatomy");
    r.ok(col.includes("--hb:") && col.includes("--hw:") && col.includes("--hl:"),
      "the bar carries all THREE per-state height stops as CSS vars (--hb/--hw/--hl)");
    r.ok(col.includes("escHtml(label)"), "the column label is escaped");
    r.ok(!col.includes('"height:'), "the bar height is NOT an inline fixed height (it rides the vars)");
  }

  // ---- zenSectionInner: the full node set for all three states at once ------
  {
    const section = fnBody(src, "zenSectionInner");
    // R1: the segmented filter is unchanged (All + live ladder, one selected).
    r.ok(section.includes('[["all", "All"]].concat(DifficultyData.zenIds.map') && section.includes("zf-opt"),
      "a four-option segmented filter (All + live ladder labels) heads the section");
    r.ok(section.includes('data-scope="') && section.includes('v === sc ? " selected"'),
      "the scoped option is visually distinguished (selected class)");
    // R8: ONE scope stats line, live per scope.
    r.ok(section.includes("zh-scope") && section.includes("d.games") && section.includes("d.wins")
      && section.includes("d.cardsFlipped") && section.includes("d.correctGuesses"),
      "one scope stats line reads games/wins/cards/correct for the current scope");
    // The two TOTALS (both-collapsed) are the forward-only distribution sums.
    r.ok(section.includes("zenSumMap(d.winPiles)") && section.includes("zenSumMap(d.lossCards)"),
      "Wins total = sum(winPiles), Losses total = sum(lossCards)");
    r.ok(section.includes('zenVCol("Wins"') && section.includes('zenVCol("Losses"'),
      "the two aggregate columns are labelled Wins / Losses with their totals");
    // Role classes drive the collapse; the aggregates carry the drill hooks.
    r.ok(section.includes("zc-agg zc-wagg") && section.includes("zc-agg zc-lagg"),
      "both totals are aggregate columns (zc-agg) with a per-outcome role (zc-wagg/zc-lagg)");
    r.ok(section.includes("zh-sum-win") && section.includes("zh-sum-loss"),
      "the aggregate columns carry the drill hooks (tap targets)");
    r.ok(section.includes("zc-wdist") && section.includes("zc-ldist"),
      "the win/loss distribution columns carry their own role classes");
    r.ok(section.includes("zv-win") && section.includes("zv-loss"),
      "wins columns are green (zv-win), loss columns red (zv-loss)");
    // R3: distributions — wins over piles 1..P, losses over the unchanged buckets.
    r.ok(section.includes("d.winPiles[p]") && section.includes("p <= d.piles"),
      "the win distribution is one column per piles-remaining value, axis 1..maxPiles");
    r.ok(section.includes("zenLossBuckets(d.deckSize)") && section.includes("zenBucketCounts(d.lossCards"),
      "the loss distribution reuses the bucket helpers over the scope's deck size");

    // DOM ORDER is fixed [Wins-agg][Losses-agg][win dist…][loss dist…] so that
    // collapsing Wins-agg leaves Losses-agg LEADING the win columns, and
    // collapsing Losses-agg leaves Wins-agg LEADING the loss columns.
    const iWagg = section.indexOf("zc-wagg");
    const iLagg = section.indexOf("zc-lagg");
    const iWdist = section.indexOf("zc-wdist");
    const iLdist = section.indexOf("zc-ldist");
    r.ok(iWagg < iLagg && iLagg < iWdist && iWdist < iLdist,
      "fixed DOM order: Wins-agg, Losses-agg, win dist, loss dist (lead-slot symmetry)");

    // DECOUPLED scales: both-collapsed compares the two TOTALS directly (shared
    // max), but each drilled state scales its breakdown to the breakdown's OWN
    // max so the bars stay legible (the lead total is their SUM, so a shared max
    // would crush them). The lead pins to FULL height (100%) as a grand-total.
    r.ok(section.includes("Math.max(tW, tL)"), "both-collapsed scales to max(totalWins, totalLosses)");
    r.ok(section.includes("h(d.winPiles[p] || 0, winMax)"),
      "the win breakdown scales to the win distribution's OWN max (winMax), not the lead total");
    r.ok(section.includes("h(bTot[i], lossMax)"),
      "the loss breakdown scales to the loss distribution's OWN max (lossMax), not the lead total");
    r.ok(!section.includes("Math.max(tL, winMax)") && !section.includes("Math.max(tW, lossMax)"),
      "the drilled states no longer fold the lead total into a shared max (would crush the breakdown)");

    // The Wins-agg bar's height stops: shown both-collapsed (--hb from maxBoth),
    // FOLDED when wins expand (0), and the FULL-height (100%) LEAD of the loss
    // breakdown (0-cards slot). Losses-agg is symmetric.
    r.ok(section.includes('h(tW, maxBoth), 0, 100'),
      "Wins total: both-collapsed height, folded when wins expand, FULL-height lead of the loss breakdown");
    r.ok(section.includes('h(tL, maxBoth), 100, 0'),
      "Losses total: both-collapsed height, FULL-height lead of the win breakdown, folded when losses expand");

    // R4: Back chip inside a drill wrap flagged only when drilled.
    r.ok(section.includes("zh-drillwrap") && section.includes("zh-back") && section.includes("‹ Back"),
      "a '‹ Back' chip lives in the drill wrap (CSS shows it only when drilled)");
    r.ok(section.includes('drill ? " zh-drilled"'),
      "the drill wrap is flagged zh-drilled only when a side is expanded");
    // The container's state class is one of the three.
    r.ok(section.includes('"zh-wins"') && section.includes('"zh-loss"') && section.includes('"zh-both"'),
      "the histogram container carries one of three state classes (zh-both/zh-wins/zh-loss)");
    r.ok(!section.includes("zh-fill") && !section.includes("zh-track") && !section.includes("zv-histo-many"),
      "no superseded horizontal (.zh-fill/.zh-track) or many-column class remains");
  }

  // ---- zenSetDrill swaps the STATE CLASS in place (no re-render → animates) --
  {
    const setDrill = fnBody(src, "zenSetDrill");
    r.ok(setDrill.length > 0, "a zenSetDrill helper exists");
    r.ok(setDrill.includes("querySelector(\".zv-histo\")") && setDrill.includes('histo.className = "zv-histo "'),
      "zenSetDrill rewrites the histogram's state class in place (no innerHTML swap)");
    r.ok(setDrill.includes('"zh-wins"') && setDrill.includes('"zh-loss"') && setDrill.includes('"zh-both"'),
      "…to one of the three view states");
    r.ok(setDrill.includes('classList.toggle("zh-drilled"'),
      "…and toggles the Back chip via the drill wrap flag");
    r.ok(!setDrill.includes("renderZenSection"), "zenSetDrill never re-renders (so the CSS transition plays)");
  }

  // ---- delegated handler: filter re-renders; drill/back only swap state -----
  {
    const at = src.indexOf("el.statsGrid.addEventListener");
    const region = src.slice(at, at + 1100);
    r.ok(region.includes('closest(".zf-opt")') && region.includes("zenView.scope = opt.dataset.scope")
      && region.includes("zenView.drill = null") && region.includes("renderZenSection()"),
      "a filter tap re-scopes, collapses the drill, and re-renders (new data)");
    r.ok(region.includes('closest(".zh-back")') && region.includes("zenSetDrill(null)"),
      "Back routes to both-collapsed via zenSetDrill(null)");
    r.ok(region.includes('closest(".zh-sum-win")') && region.includes('zenSetDrill("wins")'),
      "tapping the Wins aggregate expands wins via zenSetDrill('wins')");
    r.ok(region.includes('closest(".zh-sum-loss")') && region.includes('zenSetDrill("losses")'),
      "tapping the Losses aggregate expands losses via zenSetDrill('losses')");
    r.ok(region.includes("Sound.tap()"), "every path cues a tap");
  }

  // ---- CSS: state class drives width/opacity + per-state bar height ----------
  {
    r.ok(html.includes(".zh-wins .zv-bar { height: var(--hw); }")
      && html.includes(".zh-loss .zv-bar { height: var(--hl); }")
      && html.includes("height: var(--hb)"),
      "the bar height is driven by the state class picking --hb/--hw/--hl");
    r.ok(/\.zv-col\s*{[^}]*transition:[^}]*max-width/.test(html),
      "columns transition max-width (the expand/contract) — a CSS transition, not a swap");
    r.ok(/\.zv-bar\s*{[^}]*transition:[^}]*height/.test(html),
      "bars transition height as the per-state max shifts");
    r.ok(html.includes(".zh-both .zc-wdist, .zh-both .zc-ldist"),
      "both-collapsed folds away both distributions");
    r.ok(html.includes(".zh-wins .zc-wagg,  .zh-wins .zc-ldist"),
      "wins-expanded folds away the Wins total (now expanded) and the loss dist");
    r.ok(html.includes(".zh-loss .zc-lagg,  .zh-loss .zc-wdist"),
      "losses-expanded folds away the Losses total (now expanded) and the win dist");
    r.ok(html.includes("pointer-events: none"),
      "a folded column is inert (so a hidden aggregate never mis-routes a tap)");
    r.ok(html.includes(".zh-drillwrap .zh-back { display: none; }")
      && html.includes(".zh-drillwrap.zh-drilled .zh-back { display: inline-flex; }"),
      "the Back chip is shown only when drilled (drill wrap flag)");
    r.ok(/prefers-reduced-motion:\s*reduce\s*\)\s*{\s*\.zv-col,\s*\.zv-bar\s*{\s*transition:\s*none/.test(
      html.replace(/\n/g, " ")),
      "reduced-motion makes the state swap instant");
  }

  // ---- LIVE axes: the win breakdown spans the ladder's real pile counts -----
  // Registry-driven — assert the source reads DifficultyData's live piles/deck
  // (not a pinned axis), and that the ladder actually declares them.
  {
    const g = loadGame();
    const ids = g.DifficultyData.zenIds;
    r.ok(ids.length >= 2, `the zen ladder declares real difficulties (${ids.length})`);
    let anyPiles = false, anyDeck = false;
    for (const id of ids) {
      const z = g.DifficultyData.zen(id);
      if (z.piles > 0) anyPiles = true;
      if (z.suitCount * 13 > 0) anyDeck = true;
    }
    r.ok(anyPiles && anyDeck, "every difficulty exposes live piles + deck size for the two axes");
    const scope = fnBody(src, "zenScope");
    r.ok(scope.includes("z.piles") && scope.includes("z.suitCount * 13"),
      "zenScope reads the axes LIVE (piles / suitCount×13), nothing pinned");
    r.ok(scope.includes("agg.winPiles[k]") && scope.includes("agg.lossCards[k]")
      && scope.includes("Math.max(agg.piles"),
      "the 'all' scope aggregates per-key sums and spans the widest axes");
  }

  return r.summary();
}
