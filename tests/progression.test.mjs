// Phase 3/4: advance() walks 3 stages × 3 runs to a campaign win; reset()
// performs the full wipe back to a vanilla Stage 1 Run 1 state.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { CampaignState } = loadGame();
  const r = makeRunner("progression.test.mjs");

  // --- advance walks 1.1 -> 1.2 -> 1.3 -> 2.1 -> ... -> 3.3 -------------
  const c = CampaignState.create();
  const seen = [];
  for (let i = 0; i < 9; i++) {
    seen.push(c.currentStage + "." + c.currentRunIndex);
    c.recordRun({ correctGuesses: 0 }); // simulate finishing a run
    if (i < 8) c.advance();
  }
  r.eq(seen.join(" "), "1.1 1.2 1.3 2.1 2.2 2.3 3.1 3.2 3.3",
    "advance walks every stage/run in order");
  r.ok(c.isComplete(), "campaign is complete after Stage 3 Run 3");

  // advance clamps at the final run (no stage 4).
  c.advance();
  r.eq(c.currentStage + "." + c.currentRunIndex, "3.3", "advance clamps at 3.3");

  // isComplete is false before the 9th run completes.
  const c3 = CampaignState.create();
  for (let i = 0; i < 8; i++) { c3.recordRun({ correctGuesses: 0 }); c3.advance(); }
  r.ok(!c3.isComplete(), "not complete with one run to go");

  // --- the full wipe (reset) --------------------------------------------
  const c2 = CampaignState.create();
  c2.addCoins(50);
  c2.buySticker("rankUp");
  const id = c2.getCards()[0].id;
  c2.applySticker(id, "rankUp");      // mutate a card (rank + sticker)
  for (let i = 0; i < 5; i++) c2.advance();   // move into stage 2/3
  r.ok(c2.currentStage > 1 || c2.currentRunIndex > 1, "campaign progressed before reset");

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
