// Phase 2/3: stage-based deck construction (suit count) + campaign
// progression through 3 stages × 3 runs, with dormant-suit sticker persistence.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { CampaignState } = loadGame();
  const r = makeRunner("stage.test.mjs");

  const SUITS_ORDER = ["♠", "♥", "♦", "♣"]; // canonical; Stage 1 = ♠♥
  const uniqueSuits = (deck) => [...new Set(deck.map(c => c.suit))].sort();

  // --- deck size + active suits per stage -------------------------------
  const c = CampaignState.create();
  const expect = [
    { stage: 1, size: 26, suits: ["♠", "♥"] },
    { stage: 2, size: 39, suits: ["♠", "♥", "♦"] },
    { stage: 3, size: 52, suits: ["♠", "♥", "♦", "♣"] },
  ];
  for (const e of expect) {
    // advance into the target stage (advance walks runs then rolls stages)
    while (c.currentStage < e.stage) { c.advance(); c.advance(); c.advance(); }
    const deck = c.getRunDeck();
    r.eq(c.currentStage, e.stage, "reached stage " + e.stage);
    r.eq(c.activeSuitCount, e.stage + 1, "stage " + e.stage + " has " + (e.stage + 1) + " suits");
    r.eq(deck.length, e.size, "stage " + e.stage + " run deck = " + e.size + " cards");
    r.eq(JSON.stringify(uniqueSuits(deck)), JSON.stringify(e.suits.slice().sort()),
      "stage " + e.stage + " uses exactly suits " + e.suits.join(""));
  }
  r.eq(JSON.stringify(SUITS_ORDER), JSON.stringify(["♠", "♥", "♦", "♣"]),
    "suit introduction order is fixed");

  // --- dormant-suit stickers persist until the suit enters --------------
  const c2 = CampaignState.create();
  // A ♣ card is dormant in Stage 1 (only ♠♥ active). Sticker it anyway.
  const clubId = c2.getCards().find(x => x.suit === "♣").id;
  r.ok(c2.applySticker(clubId, "tieSafe"), "sticker a dormant ♣ card in Stage 1");
  r.ok(!c2.getRunDeck().some(x => x.id === clubId), "♣ card absent from Stage 1 run deck");
  // Advance to Stage 3 (6 advances: 1.1->1.2->1.3->2.1->2.2->2.3->3.1).
  for (let i = 0; i < 6; i++) c2.advance();
  const clubNow = c2.getRunDeck().find(x => x.id === clubId);
  r.ok(!!clubNow, "♣ card present once Stage 3 enters its suit");
  r.ok(clubNow && clubNow.stickers.some(s => s.type === "tieSafe"),
    "dormant card kept its sticker until its suit entered");

  // --- stageComposition (the deck-inspection "full" column) -------------
  const sum = (m) => Object.values(m).reduce((a, b) => a + b, 0);
  const c3 = CampaignState.create();
  let comp = c3.stageComposition();
  r.eq(sum(comp), 26, "Stage 1 full composition totals 26 cards");
  r.ok([2, 3, 4, 14].every(v => comp[v] === 2), "Stage 1: every rank has 2 (2 suits)");

  // Rank stickers shift the composition (current rank, not original).
  const fiveId = c3.getCards().find(x => x.currentRank === 5 && (x.suit === "♠" || x.suit === "♥")).id;
  c3.applySticker(fiveId, "rankUp");   // a 5 -> 6
  comp = c3.stageComposition();
  r.eq(comp[5], 1, "rankUp on a 5 drops rank-5 count to 1");
  r.eq(comp[6], 3, "rankUp on a 5 raises rank-6 count to 3");
  r.eq(sum(comp), 26, "composition still totals 26 after a rank sticker");

  for (let i = 0; i < 6; i++) c3.advance();   // -> Stage 3
  r.eq(sum(c3.stageComposition()), 52, "Stage 3 full composition totals 52 cards");

  return r.summary();
}
