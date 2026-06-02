// New gameplay features: rarity tiers, ±2 rank + Random Rank stickers, Spade
// Guard, the live bonus-coin effects (Middle Reward, Lucky Coin, sticker
// Tributes), the new Pillars (Double Tribute, All Hearts), and Economy folding
// the live bonus into the payout. Engine modules are DOM-free (see _harness).
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, CampaignState, StickerTypes, PillarTypes, Economy } = loadGame();
  const r = makeRunner("features.test.mjs");

  // Every card carries `type`, so whatever is drawn/showing carries it.
  const specsWith = (type) => {
    const specs = DeckManager.buildStandardDeck();
    specs.forEach(c => c.stickers.push({ type }));
    return specs;
  };
  // Force a guaranteed-correct HIGHER landing on pile `index`: show low, draw high.
  const landHigher = (e, index, drawVal = 9) => {
    e.getBoard().top(index).value = 5;
    e.debug.setNextCard(drawVal);
    e.guess(index, "higher");
  };

  // --- Rarity tiers: every type carries a valid tier --------------------
  {
    const valid = new Set(["common", "uncommon", "rare"]);
    const bad = [];
    StickerTypes.all().forEach(t => { if (!valid.has(t.tier)) bad.push("sticker:" + t.id); });
    PillarTypes.all().forEach(t => { if (!valid.has(t.tier)) bad.push("pillar:" + t.id); });
    r.eq(bad.join(",") || "none", "none", "every sticker & Pillar has a valid rarity tier");
  }

  // --- New registry entries + their prices ------------------------------
  {
    r.eq(StickerTypes.get("rankUp2").rankDelta, +2, "+2 Rank delta");
    r.eq(StickerTypes.get("rankDown2").rankDelta, -2, "−2 Rank delta");
    r.eq(StickerTypes.get("rankUp2").price, 4, "+2 Rank price 4");
    r.eq(StickerTypes.get("randomFixedValue").price, 3, "Random Rank price 3");
    r.eq(StickerTypes.get("suitImmunity").price, 4, "Spade Guard price 4");
    r.eq(StickerTypes.get("middleColumnReward").value, 2, "Middle Reward pays 2");
    r.eq(StickerTypes.get("gainCoin").value, 1, "Lucky Coin pays 1");
    r.eq(StickerTypes.get("oneTribute").price, 6, "Tribute I price 6");
    r.eq(StickerTypes.get("twoTribute").price, 8, "Tribute II price 8");
    r.eq(StickerTypes.get("twoTribute").coinCost, 4, "Tribute II costs 4 bonus coins");
    r.eq(StickerTypes.get("centerTribute").price, 5, "Center Tribute price 5");
    r.ok(StickerTypes.get("centerTribute").centerOnly === true, "Center Tribute is middle-column only");
    r.eq(PillarTypes.get("sameValueTribute").price, 22, "Double Tribute price 22");
    r.eq(PillarTypes.get("sameValueTribute").tributeCount, 2, "Double Tribute buries 2");
    r.eq(PillarTypes.get("allHeartsCoin").price, 10, "All Hearts price 10");
    r.eq(PillarTypes.get("allHeartsCoin").value, 5, "All Hearts pays 5");
  }

  // --- ±2 Rank clamps at the rank boundaries ----------------------------
  {
    const c = CampaignState.create();
    const king = c.getCards().find(x => x.currentRank === 13);
    r.ok(c.applySticker(king.id, "rankUp2"), "apply +2 to a King");
    r.eq(c.getCards().find(x => x.id === king.id).currentRank, 14, "+2 on a King clamps to Ace (14)");
    r.ok(!c.canApplyStickerById(king.id, "rankUp2"), "+2 blocked once already at Ace");

    const three = c.getCards().find(x => x.currentRank === 3);
    r.ok(c.applySticker(three.id, "rankDown2"), "apply −2 to a 3");
    r.eq(c.getCards().find(x => x.id === three.id).currentRank, 2, "−2 on a 3 clamps to a 2");
    r.ok(!c.canApplyStickerById(three.id, "rankDown2"), "−2 blocked once already at 2");
  }

  // --- Random Rank: sets a rank in [2,14], records it -------------------
  {
    const c = CampaignState.create();
    const card = c.getCards()[0];
    r.ok(c.applySticker(card.id, "randomFixedValue"), "apply Random Rank");
    const after = c.getCards().find(x => x.id === card.id);
    r.ok(after.currentRank >= 2 && after.currentRank <= 14, "Random Rank lands in [2, Ace]");
    r.ok(after.modifications.some(m => m.op === "randomRank"), "records a randomRank modification");
    r.ok(after.stickers.some(s => s.type === "randomFixedValue"), "Random Rank sticker recorded for its badge");
  }

  // --- Spade Guard: absorbs one ♠ wrong guess per run -------------------
  {
    const e = GameEngine.create(specsWith("suitImmunity"), 9);
    e.start(); e.startRun();
    const b = e.getBoard();
    r.ok(b.top(0).spadeImmunity, "suitImmunity projects the spadeImmunity charge");

    const before = e.getDeck().remaining();
    b.top(0).value = 10;
    const d = e.debug.setNextCard(3); d.suit = "♠";   // a ♠ that loses on HIGHER
    e.guess(0, "higher");
    r.ok(b.isActive(0), "Spade Guard: a ♠ wrong guess is absorbed, pile survives");
    r.ok(!b.top(0).spadeImmunity, "the guard charge is spent");
    r.eq(b.top(0).value, 10, "showing card unchanged (drawn ♠ not pushed)");
    r.eq(e.getDeck().remaining(), before, "drawn ♠ returned to the deck");

    const d2 = e.debug.setNextCard(3); d2.suit = "♠";
    e.guess(0, "higher");
    r.ok(!b.isActive(0), "with the charge spent, the next ♠ wrong guess kills");
  }
  {
    // A non-♠ wrong guess is NOT guarded.
    const e = GameEngine.create(specsWith("suitImmunity"), 9);
    e.start(); e.startRun();
    const b = e.getBoard();
    b.top(1).value = 10;
    const d = e.debug.setNextCard(3); d.suit = "♥";
    e.guess(1, "higher");
    r.ok(!b.isActive(1), "Spade Guard ignores non-♠ wrong guesses (pile dies)");
  }
  {
    // Refreshes next run (re-projected on each deal).
    const specs = specsWith("suitImmunity");
    const e1 = GameEngine.create(specs, 9);
    e1.start(); e1.startRun();
    e1.getBoard().top(0).value = 10;
    const d = e1.debug.setNextCard(3); d.suit = "♠";
    e1.guess(0, "higher");
    r.ok(!e1.getBoard().top(0).spadeImmunity, "charge spent in run 1");
    const e2 = GameEngine.create(specs, 9);
    e2.start();
    r.ok(e2.getBoard().top(0).spadeImmunity, "Spade Guard refreshed for run 2");
  }

  // --- Lucky Coin: +1 on a surviving landing ----------------------------
  {
    const e = GameEngine.create(specsWith("gainCoin"), 9);
    e.start(); e.startRun();
    r.eq(e.getRun().bonusCoins, 0, "bonus tally starts at 0");
    landHigher(e, 0);
    r.eq(e.getRun().bonusCoins, 1, "Lucky Coin pays +1 when the card lands and survives");
  }

  // --- Middle Reward: +2 only in the middle column ----------------------
  {
    const e = GameEngine.create(specsWith("middleColumnReward"), 10, { cols: [3, 4, 3] });
    e.start(); e.startRun([null, null, null]);
    landHigher(e, 3);   // pile 3 is the middle column (col 1)
    r.eq(e.getRun().bonusCoins, 2, "Middle Reward pays +2 landing in the middle column");
    landHigher(e, 0);   // pile 0 is column 0 (not middle)
    r.eq(e.getRun().bonusCoins, 2, "no reward landing outside the middle column");
  }

  // --- Tribute I sticker: bury 1 + cost 1 bonus coin --------------------
  {
    const e = GameEngine.create(specsWith("oneTribute"), 10, { cols: [3, 4, 3] });
    e.start(); e.startRun([null, null, null]);
    const len0 = e.getBoard().piles[0].cards.length;     // 1 (deal)
    const deck0 = e.getDeck().remaining();
    landHigher(e, 0);
    r.eq(e.getBoard().piles[0].cards.length, len0 + 2, "Tribute I: pile gains the drawn card + 1 buried");
    r.eq(e.getDeck().remaining(), deck0 - 2, "deck loses the drawn card and the tributed card");
    r.eq(e.getRun().bonusCoins, -1, "Tribute I costs 1 bonus coin (negative tally)");
  }

  // --- Center Tribute sticker: only fires in the middle column ----------
  {
    const e = GameEngine.create(specsWith("centerTribute"), 10, { cols: [3, 4, 3] });
    e.start(); e.startRun([null, null, null]);
    const l0 = e.getBoard().piles[0].cards.length;
    landHigher(e, 0);   // column 0 — no fire
    r.eq(e.getBoard().piles[0].cards.length, l0 + 1, "Center Tribute does nothing outside the middle column");
    r.eq(e.getRun().bonusCoins, 0, "no cost outside the middle column");

    const l3 = e.getBoard().piles[3].cards.length;
    landHigher(e, 3);   // middle column — fires
    r.eq(e.getBoard().piles[3].cards.length, l3 + 2, "Center Tribute buries 1 in the middle column");
    r.eq(e.getRun().bonusCoins, 0, "Center Tribute has no coin cost");
  }

  // --- Double Tribute Pillar: buries TWO on a survived tie --------------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    e.start(); e.startRun(["sameValueTribute", null, null]);
    const len0 = e.getBoard().piles[0].cards.length;
    const deck0 = e.getDeck().remaining();
    e.getBoard().top(0).value = 7;
    e.debug.setNextCard(7);
    e.guess(0, "same");
    r.ok(e.getBoard().isActive(0), "correct Same guess survives the tie");
    r.eq(e.getRun().sameValueTributesUsed[0], 1, "Double Tribute fired once");
    r.eq(e.getBoard().piles[0].cards.length, len0 + 3, "buries TWO (drawn Same card + 2 tributes)");
    r.eq(e.getDeck().remaining(), deck0 - 3, "deck loses the drawn card and 2 tributed cards");
  }

  // --- All Hearts Pillar: +5 when every alive pile IN ITS COLUMN shows ♥ ----
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 3, { cols: [1, 1, 1] });
    e.start(); e.startRun(["allHeartsCoin", null, null]);   // Pillar on column 0
    const b = e.getBoard();
    // Column 1 (pile 1) shows a non-heart and stays ALIVE — it must NOT block
    // column 0's bonus (column-scoped, not board-wide).
    b.top(1).suit = "♠";
    b.top(0).value = 5;
    const d = e.debug.setNextCard(9); d.suit = "♥";
    e.guess(0, "higher");                 // pile 0 (col 0) now shows a ♥
    r.ok(b.isActive(0) && b.isActive(1), "both piles still alive");
    r.eq(e.getRun().bonusCoins, 5, "All Hearts pays +5: its column is all-♥ (other columns ignored)");

    const d2 = e.debug.setNextCard(10); d2.suit = "♠";
    e.guess(0, "higher");                 // col 0's own top is now a ♠
    r.eq(e.getRun().bonusCoins, 5, "no pay when a pile IN the Pillar's column isn't a ♥");
  }
  {
    // The Pillar's column must be ALL hearts: a non-heart alive top in-column blocks it.
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 6, { cols: [2, 2, 2] });
    e.start(); e.startRun(["allHeartsCoin", null, null]);   // column 0 = piles 0,1
    const b = e.getBoard();
    b.top(1).suit = "♠";                  // pile 1 is in column 0, not a ♥
    b.top(0).value = 5;
    const d = e.debug.setNextCard(9); d.suit = "♥";
    e.guess(0, "higher");                 // pile 0 ♥, but pile 1 (same column) is ♠
    r.eq(e.getRun().bonusCoins, 0, "in-column non-♥ top blocks the bonus");
  }

  // --- Suit Bounty pays LIVE during play (not at run end) ---------------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    let payload = null;
    e.onEvent((t, p) => { if (t === "won") payload = p; });
    e.start(); e.startRun(["spadeBounty", null, null]);
    const a = e.getBoard().top(0); a.value = 5; a.suit = "♠";
    e.debug.setNextCard(9); e.guess(0, "higher");   // correct ♠ guess → +1 live
    r.eq(e.getRun().bonusCoins, 1, "Suit Bounty ticks the live tally as it resolves");
    e.debug.winNow();
    r.eq(payload.pillarPayout.bonus, 0, "Suit Bounty is NOT re-paid at run end (no double-count)");
  }

  // --- Tracker reconciles: live tally + end-of-run bonuses == summary ----
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    let payload = null;
    e.onEvent((t, p) => { if (t === "won") payload = p; });
    e.start();
    e.startRun(["spadeBounty", null, "columnGuardian"]);   // col 0 bounty, col 2 guardian
    const a = e.getBoard().top(0); a.value = 5; a.suit = "♠";
    e.debug.setNextCard(9); e.guess(0, "higher");          // one ♠ bounty → +1 live
    r.eq(e.getRun().bonusCoins, 1, "live tally during play = 1 (the Suit Bounty)");
    e.debug.winNow();                                      // all piles alive → Guardian +5

    // Rebuild the run-complete summary exactly as onRunEnd does.
    const board = payload.board, pp = payload.pillarPayout;
    const eventBonus = payload.run.bonusCoins;             // live part (Suit Bounty = 1)
    const bd = Economy.breakdown({
      won: true, aliveCount: board.aliveCount(), minAliveCards: board.minAliveCards(),
      extraCoinUnits: board.extraCoinUnits(), pillarBonus: pp.bonus, pillarLines: pp.lines,
      eventBonus, eventLines: [],
    });
    r.eq(pp.bonus, 5, "Column Guardian (col 3 all-alive) pays +5 at run end");
    // The HUD's folded final value is exactly (total − product) = the summary's
    // total bonus, and equals live + Guardian + Extra Coin.
    const finalTracker = bd.total - bd.product;
    r.eq(finalTracker, eventBonus + pp.bonus + bd.extraCoinBonus, "final tracker = live + Guardian + Extra Coin");
    r.eq(finalTracker, 6, "final bonus reconciles to the summary: 1 live + 5 Guardian = 6");
  }

  // --- Economy folds the live bonus into the total ----------------------
  {
    const withEvent = Economy.breakdown({
      won: true, aliveCount: 3, minAliveCards: 2,
      eventBonus: 4, eventLines: [{ label: "Middle Reward", amount: 4 }],
    });
    r.eq(withEvent.eventBonus, 4, "eventBonus carried through");
    r.eq(withEvent.total, 10, "total folds in the live bonus (3×2 + 4)");
    r.eq(withEvent.eventLines.length, 1, "itemized event lines preserved for the UI");

    const neg = Economy.breakdown({ won: true, aliveCount: 1, minAliveCards: 1, eventBonus: -5 });
    r.eq(neg.total, 0, "a Tribute cost can't push the total below 0");

    const lost = Economy.breakdown({ won: false, aliveCount: 3, minAliveCards: 2, eventBonus: 4 });
    r.eq(lost.eventBonus, 0, "a loss zeroes the live bonus");
    r.eq(lost.total, 0, "a loss pays nothing");
  }

  return r.summary();
}
