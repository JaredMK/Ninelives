// Phase 3/4: advance() walks 3 stages × 4 runs to a campaign win; reset()
// performs the full wipe back to a vanilla Stage 1 Run 1 state.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { CampaignState } = loadGame();
  const r = makeRunner("progression.test.mjs");

  // --- per-run layout: three COLUMNS, counts unchanged from the rows -----
  // layoutForRun returns the column sizes for that run. The counts must match
  // the historical row layout exactly (only the orientation changed); `piles`
  // is their sum and `rows` is the tallest column (vertical span).
  const lc = CampaignState.create();
  const expectCols = [
    { run: 1, cols: [4, 3, 4], piles: 11, rows: 4 },   // NEW warmup run
    { run: 2, cols: [3, 4, 3], piles: 10, rows: 4 },
    { run: 3, cols: [3, 3, 3], piles: 9,  rows: 3 },
    { run: 4, cols: [3, 2, 3], piles: 8,  rows: 3 },
  ];
  for (const e of expectCols) {
    const L = lc.layoutForRun(e.run);
    r.eq(JSON.stringify(L.cols), JSON.stringify(e.cols),
      "Run " + e.run + " columns are " + e.cols.join(","));
    r.eq(L.piles, e.piles, "Run " + e.run + " has " + e.piles + " piles (count unchanged)");
    r.eq(L.rows, e.rows, "Run " + e.run + " tallest column = " + e.rows);
    // Symmetric outer columns, balanced layout (outer columns equal).
    r.eq(L.cols[0], L.cols[2], "Run " + e.run + " outer columns are symmetric");
  }
  // runIndex clamps to the valid range (presentation never indexes out of bounds).
  r.eq(JSON.stringify(lc.layoutForRun(0).cols), JSON.stringify([4, 3, 4]), "run 0 clamps to Run 1");
  r.eq(JSON.stringify(lc.layoutForRun(99).cols), JSON.stringify([3, 2, 3]), "run 99 clamps to Run 4");

  // --- advance walks 1.1 -> 1.2 -> 1.3 -> 1.4 -> 2.1 -> ... -> 3.4 ------
  const c = CampaignState.create();
  const seen = [];
  for (let i = 0; i < 12; i++) {
    seen.push(c.currentStage + "." + c.currentRunIndex);
    c.recordRun({ correctGuesses: 0 }); // simulate finishing a run
    if (i < 11) c.advance();
  }
  r.eq(seen.join(" "), "1.1 1.2 1.3 1.4 2.1 2.2 2.3 2.4 3.1 3.2 3.3 3.4",
    "advance walks every stage/run in order (3 × 4)");
  r.ok(c.isComplete(), "campaign is complete after Stage 3 Run 4");

  // advance clamps at the final run (no stage 4).
  c.advance();
  r.eq(c.currentStage + "." + c.currentRunIndex, "3.4", "advance clamps at 3.4");

  // isComplete is false before the 12th run completes.
  const c3 = CampaignState.create();
  for (let i = 0; i < 11; i++) { c3.recordRun({ correctGuesses: 0 }); c3.advance(); }
  r.ok(!c3.isComplete(), "not complete with one run to go");

  // --- the full wipe (reset) --------------------------------------------
  const c2 = CampaignState.create();
  c2.addCoins(50);
  c2.buySticker("rankUp");
  const id = c2.getCards()[0].id;
  c2.applySticker(id, "rankUp");      // mutate a card (rank + sticker)
  for (let i = 0; i < 5; i++) c2.advance();   // move into stage 2/3
  r.ok(c2.currentStage > 1 || c2.currentRunIndex > 1, "campaign progressed before reset");

  // --- end-screen cumulative counters ----------------------------------
  {
    const c4 = CampaignState.create();
    r.eq(c4.totalCardsFlipped, 0, "cards-flipped starts at 0");
    r.eq(c4.totalCoinsEarned, 0, "coins-earned starts at 0");
    // Cards flipped accrue every run end (incl. a loss), independent of win-only recordRun.
    c4.addCardsFlipped(4); c4.addCardsFlipped(7);
    r.eq(c4.totalCardsFlipped, 11, "addCardsFlipped accumulates across runs");
    // earnCoins bumps the balance AND the gross-earned total.
    c4.earnCoins(10);
    r.eq(c4.getCoins(), 10, "earnCoins credits the balance");
    r.eq(c4.totalCoinsEarned, 10, "earnCoins tracks gross earned");
    // Spending lowers the balance but NOT gross earned.
    c4.spendCoins(6);
    r.eq(c4.getCoins(), 4, "spending lowers the balance");
    r.eq(c4.totalCoinsEarned, 10, "gross earned is unaffected by spending");
    // addCoins (non-earned, e.g. debug) does NOT count toward earnings.
    c4.addCoins(100);
    r.eq(c4.totalCoinsEarned, 10, "addCoins doesn't inflate gross earned");
    c4.reset();
    r.eq(c4.totalCardsFlipped, 0, "reset wipes cards flipped");
    r.eq(c4.totalCoinsEarned, 0, "reset wipes coins earned");
  }

  c2.reset();
  r.eq(c2.currentStage, 1, "reset -> Stage 1");
  r.eq(c2.currentRunIndex, 1, "reset -> Run 1");
  r.eq(c2.getCoins(), 0, "reset -> 0 coins");
  r.eq(JSON.stringify(c2.getInventory()), "{}", "reset -> empty inventory");
  r.eq(c2.runsCompleted, 0, "reset -> 0 runs completed");
  const cards = c2.getCards();
  r.eq(cards.length, 52, "reset -> full 52-card identity set");
  r.ok(cards.every(x => x.stickers.length === 0 && x.modifications.length === 0 &&
                        x.currentRank === x.originalRank),
    "reset -> all cards vanilla (no stickers, no modifications, original ranks)");

  return r.summary();
}
