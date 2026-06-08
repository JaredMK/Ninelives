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
    r.eq(StickerTypes.get("middleColumnReward").value, 3, "Middle Reward pays 3");
    r.eq(StickerTypes.get("gainCoin").value, 1, "Lucky Coin pays 1");
    r.eq(StickerTypes.get("oneTribute").price, 6, "Tribute I price 6");
    r.eq(StickerTypes.get("twoTribute").price, 8, "Tribute II price 8");
    r.eq(StickerTypes.get("twoTribute").coinCost, 4, "Tribute II costs 4 bonus coins");
    r.eq(StickerTypes.get("centerTribute").price, 5, "Center Tribute price 5");
    r.ok(StickerTypes.get("centerTribute").centerOnly === true, "Center Tribute is middle-column only");
    r.eq(PillarTypes.get("sameValueTribute").price, 22, "Double Tribute price 22");
    r.eq(PillarTypes.get("sameValueTribute").tributeCount, 2, "Double Tribute buries 2");
    r.eq(PillarTypes.get("allHeartsCoin").price, 6, "All Hearts price 6 (Common)");
    r.eq(PillarTypes.get("allHeartsCoin").value, 5, "All Hearts pays 5");
    r.eq(PillarTypes.get("allHeartsCoin").tier, "common", "All Hearts is Common");
    // Equivalent all-suit Pillars exist for every suit, end-of-run scoring.
    for (const [id, suit] of [["allSpadesCoin", "♠"], ["allDiamondsCoin", "♦"], ["allClubsCoin", "♣"]]) {
      r.eq(PillarTypes.get(id).suit, suit, id + " is for " + suit);
      r.eq(PillarTypes.get(id).effect, "allSuitTop", id + " uses the shared end-of-run effect");
      r.eq(PillarTypes.get(id).value, 5, id + " pays 5");
    }
    r.eq(PillarTypes.get("allHeartsCoin").effect, "allSuitTop", "All Hearts now end-of-run scoring");
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

  // --- Suit Guard family: one guard sticker per base suit ---------------
  // The four guards share ONE behavior ("suitImmunity"), each locked to its
  // suit. Spade is the original; ♥/♦/♣ are siblings. Same tier + price = a
  // uniform family. Drive each suit through the shared engine path.
  {
    const SUIT_GUARDS = [
      ["suitImmunity", "♠"], ["heartGuard", "♥"],
      ["diamondGuard", "♦"], ["clubGuard", "♣"],
    ];
    SUIT_GUARDS.forEach(([id, suit]) => {
      const t = StickerTypes.get(id);
      r.eq(t && t.behavior, "suitImmunity", id + " reuses the shared suitImmunity behavior");
      r.eq(t && t.suit, suit, id + " is locked to " + suit);
      r.eq(t && t.tier, "uncommon", id + " tier matches the family (uncommon)");
      r.eq(t && t.price, 4, id + " price matches the family (4)");

      const e = GameEngine.create(specsWith(id), 9);
      e.start(); e.startRun();
      const b = e.getBoard();
      r.ok(b.top(0).suitGuards && b.top(0).suitGuards[suit], id + " projects a " + suit + " charge");

      // specsWith() stickers EVERY card, so the drawn cards also carry this guard.
      // Force the top card's OWN suit to a different suit so only the current-side
      // (top) guard is in play — otherwise the symmetric rule could let a drawn
      // guard save when the top happens to be the guarded suit (tested separately).
      const otherSuit = suit === "♠" ? "♥" : "♠";
      const before = e.getDeck().remaining();
      b.top(0).value = 10; b.top(0).suit = otherSuit;
      const d = e.debug.setNextCard(3); d.suit = suit;   // that suit, loses on HIGHER
      e.guess(0, "higher");
      r.ok(b.isActive(0), id + ": a " + suit + " wrong guess is absorbed, pile survives");
      r.ok(!b.top(0).suitGuards[suit], id + ": the " + suit + " charge is spent");
      r.eq(b.top(0).value, 10, id + ": showing card unchanged (drawn card not pushed)");
      r.eq(e.getDeck().remaining(), before, id + ": drawn " + suit + " returned to the deck");

      b.top(0).suit = otherSuit;                          // keep the top a non-guarded suit
      const d2 = e.debug.setNextCard(3); d2.suit = suit;
      e.guess(0, "higher");
      r.ok(!b.isActive(0), id + ": with the charge spent, the next " + suit + " wrong guess kills");
    });
  }
  {
    // A guard ignores OTHER suits: a Heart Guard doesn't stop a ♠ wrong guess
    // (top suit forced to ♠ so the drawn card's ♥ guard can't symmetric-save it).
    const e = GameEngine.create(specsWith("heartGuard"), 9);
    e.start(); e.startRun();
    const b = e.getBoard();
    b.top(1).value = 10; b.top(1).suit = "♠";
    const d = e.debug.setNextCard(3); d.suit = "♠";
    e.guess(1, "higher");
    r.ok(!b.isActive(1), "Heart Guard ignores a non-♥ (♠) wrong guess (pile dies)");
  }
  {
    // Two guards on one card → independent per-suit charges.
    const specs = DeckManager.buildStandardDeck();
    specs.forEach(c => { c.stickers.push({ type: "suitImmunity" }); c.stickers.push({ type: "heartGuard" }); });
    const e = GameEngine.create(specs, 9);
    e.start(); e.startRun();
    const b = e.getBoard();
    b.top(0).value = 10;
    const ds = e.debug.setNextCard(3); ds.suit = "♠";
    e.guess(0, "higher");
    r.ok(b.isActive(0) && !b.top(0).suitGuards["♠"], "spent the ♠ charge");
    r.ok(b.top(0).suitGuards["♥"], "the ♥ charge is still ready (independent)");
    const dh = e.debug.setNextCard(3); dh.suit = "♥";
    e.guess(0, "higher");
    r.ok(b.isActive(0) && !b.top(0).suitGuards["♥"], "then the ♥ charge absorbs a ♥ wrong guess");
  }
  {
    // Refreshes next run (re-projected on each deal).
    const specs = specsWith("suitImmunity");
    const e1 = GameEngine.create(specs, 9);
    e1.start(); e1.startRun();
    e1.getBoard().top(0).value = 10;
    const d = e1.debug.setNextCard(3); d.suit = "♠";
    e1.guess(0, "higher");
    r.ok(!e1.getBoard().top(0).suitGuards["♠"], "charge spent in run 1");
    const e2 = GameEngine.create(specs, 9);
    e2.start();
    r.ok(e2.getBoard().top(0).suitGuards["♠"], "Suit Guard refreshed for run 2");
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
    r.eq(e.getRun().bonusCoins, 3, "Middle Reward pays +3 landing in the middle column");
    landHigher(e, 0);   // pile 0 is column 0 (not middle)
    r.eq(e.getRun().bonusCoins, 3, "no reward landing outside the middle column");
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

  // --- All Hearts Pillar: END-OF-RUN +5 when every SURVIVING pile in its
  //     column shows ♥ (no longer a live per-resolution payout). -------------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 3, { cols: [1, 1, 1] });
    e.start(); e.startRun(["allHeartsCoin", null, null]);   // Pillar on column 0
    const b = e.getBoard();
    b.top(0).suit = "♥";                  // col 0's only surviving pile shows ♥
    b.top(1).suit = "♠";                  // another column, ignored (column-scoped)
    r.eq(e.getRun().bonusCoins, 0, "no LIVE payout — All Hearts is end-of-run now");
    r.eq(e.pillarPayout().bonus, 5, "All Hearts scores +5 at run end: its column's survivors are all ♥");
    b.top(0).suit = "♠";                  // col 0 no longer all-♥
    r.eq(e.pillarPayout().bonus, 0, "no score when a surviving pile in the column isn't a ♥");
  }
  {
    // Every SURVIVING pile in the column must match: an in-column non-♥ top blocks it.
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 6, { cols: [2, 2, 2] });
    e.start(); e.startRun(["allHeartsCoin", null, null]);   // column 0 = piles 0,1
    const b = e.getBoard();
    b.top(0).suit = "♥"; b.top(1).suit = "♠";   // both in column 0; pile 1 not ♥
    r.eq(e.pillarPayout().bonus, 0, "in-column non-♥ surviving top blocks the bonus");
    b.top(1).suit = "♥";                        // now all survivors in col 0 are ♥
    r.eq(e.pillarPayout().bonus, 5, "all surviving piles in the column ♥ → +5");
  }
  {
    // The same end-of-run, surviving-piles rule for the other suits (Stage 1
    // can exercise ♠; the rule is identical for ♦/♣).
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 3, { cols: [1, 1, 1] });
    e.start(); e.startRun(["allSpadesCoin", null, null]);
    const b = e.getBoard();
    b.top(0).suit = "♠";
    r.eq(e.pillarPayout().bonus, 5, "All Spades scores +5 when its column's survivors are all ♠");
    b.top(0).suit = "♥";
    r.eq(e.pillarPayout().bonus, 0, "All Spades scores 0 when a survivor isn't a ♠");
  }
  // --- Symmetric Suit Guard: a guard on the DRAWN card saves when the pile's
  //     top is the guarded suit (the second spec case). --------------------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 3);
    e.start(); e.startRun();
    const b = e.getBoard();
    const top = b.top(0);
    top.suit = "♠"; top.value = 14; top.suitGuards = {};   // ♠ on top, NO guard of its own
    const d = e.debug.setNextCard(3); d.suit = "♥"; d.suitGuards = { "♠": true };   // drawn carries a ♠ guard
    e.guess(0, "higher");                 // wrong (3 ≤ Ace), but ♠ is involved (the top)
    r.ok(b.isActive(0), "drawn card's ♠ guard saves the pile (top is ♠)");
    r.ok(!d.suitGuards["♠"], "the DRAWN card's ♠ charge is spent");
    r.eq(b.top(0).suit, "♠", "the ♠ top stays in place (drawn card not pushed)");
  }

  // --- Suit Bounty pays LIVE during play (not at run end) ---------------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    let payload = null;
    e.onEvent((t, p) => { if (t === "won") payload = p; });
    e.start(); e.startRun(["spadeBounty", null, null]);
    e.getBoard().top(0).value = 5;
    const dsb = e.debug.setNextCard(9); dsb.suit = "♠";   // a ♠ LANDS on the column
    e.guess(0, "higher");
    r.eq(e.getRun().bonusCoins, 1, "Suit Bounty ticks the live tally as a ♠ lands");
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
    e.getBoard().top(0).value = 5;
    const dsb = e.debug.setNextCard(9); dsb.suit = "♠";    // one ♠ lands → +1 live
    e.guess(0, "higher");
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
