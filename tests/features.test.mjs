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
  // A GUARANTEED next draw: setNextCard(v) returns undefined when every copy of
  // v was already dealt onto the opening piles (rare shuffle — a real observed
  // flake), so inject a concrete card object instead (the same path the Joker
  // tests use), immune to the shuffle. `extra` merges extra fields (guards…).
  let __nid = 880001;
  const forceNext = (e, value, suit, extra) => e.debug.setNextCardObj(Object.assign({
    id: __nid++, label: String(value), value, suit: suit || "\u2660",
    red: suit === "\u2665" || suit === "\u2666", stickers: [], suitGuards: {}, heartsRemaining: 0,
  }, extra || {}));
  // Force a guaranteed-correct HIGHER landing on pile `index`: show low, draw
  // high. Uses setNextCard (REORDERS the real deck — its cards carry the
  // specsWith stickers and the deck count is unchanged, which the Tribute
  // blocks assert on); setNextCard returns undefined when every copy of a
  // value was dealt onto the opening piles (rare shuffle), so walk the high
  // ranks until one is still in the deck — any value above 5 lands.
  const landHigher = (e, index) => {
    e.getBoard().top(index).value = 5;
    let c = null;
    for (const v of [9, 10, 11, 12, 13, 8, 7, 6]) { c = e.debug.setNextCard(v); if (c) break; }
    if (!c) throw new Error("landHigher: no high card left in the deck");
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
    r.eq(StickerTypes.get("rankUp2").price, 2, "+2 Rank price 2");
    r.eq(StickerTypes.get("randomFixedValue").price, 1, "Random Rank price 1");
    r.eq(StickerTypes.get("suitImmunity").price, 3, "Spade Guard price 3");
    r.eq(StickerTypes.get("middleColumnReward").value, 3, "Middle Reward pays 3");
    r.eq(StickerTypes.get("gainCoin").value, 1, "Lucky Coin pays 1");
    r.eq(StickerTypes.get("oneTribute").price, 10, "Bury 1 price 10");
    r.eq(StickerTypes.get("twoTribute").price, 16, "Bury 2 price 16");
    r.eq(StickerTypes.get("twoTribute").coinCost, 4, "Bury 2 costs 4 bonus coins");
    r.eq(StickerTypes.get("centerTribute").price, 4, "Middle Bury price 4");
    r.ok(StickerTypes.get("centerTribute").centerOnly === true, "Center Tribute is middle-column only");
    r.eq(PillarTypes.get("allHeartsCoin").price, 8, "All Hearts price 8");
    r.eq(PillarTypes.get("allHeartsCoin").value, 8, "All Hearts pays 8");
    r.eq(PillarTypes.get("allHeartsCoin").tier, "common", "All Hearts is Common");
    // The other-suit All-* Pillars were removed in the rebalance; only ♥ remains.
    for (const id of ["allSpadesCoin", "allDiamondsCoin", "allClubsCoin"]) {
      r.ok(!PillarTypes.get(id), id + " was removed");
    }
    r.eq(PillarTypes.get("allHeartsCoin").effect, "allSuitTop", "All Hearts is end-of-run scoring");
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

  // --- Suit Guard family: one guard sticker per base suit (ONE-DIRECTIONAL) -
  // The four guards share ONE behavior ("suitImmunity"), each locked to its
  // suit. A guard fires ONLY when the GUARD CARD is DRAWN onto a top of its
  // guarded suit; a matching card drawn onto a guard card does nothing.
  {
    // All four suit guards now share a flat price of 3.
    const SUIT_GUARDS = [
      ["suitImmunity", "♠", 3], ["heartGuard", "♥", 3],
      ["diamondGuard", "♦", 3], ["clubGuard", "♣", 3],
    ];
    SUIT_GUARDS.forEach(([id, suit, price]) => {
      const t = StickerTypes.get(id);
      r.eq(t && t.behavior, "suitImmunity", id + " reuses the shared suitImmunity behavior");
      r.eq(t && t.suit, suit, id + " is locked to " + suit);
      r.eq(t && t.tier, "uncommon", id + " tier matches the family (uncommon)");
      r.eq(t && t.price, price, id + " price is " + price);

      const e = GameEngine.create(specsWith(id), 9);
      e.start(); e.startRun();
      const b = e.getBoard();
      r.ok(b.top(0).suitGuards && b.top(0).suitGuards[suit], id + " projects a " + suit + " charge");

      // The GUARD CARD (drawn — carries this family's charge) lands ONTO a top
      // of its guarded suit → the wrong guess is safe. (`before` is read AFTER
      // the injection: forceNext ADDS a card, unlike the old reorder-only
      // setNextCard, so the baseline must include it.)
      b.top(0).value = 10; b.top(0).suit = suit;          // top IS the guarded suit
      const d = forceNext(e, 3, "♠", { suitGuards: { [suit]: true } });   // a drawn guard card
      const before = e.getDeck().remaining();
      e.guess(0, "higher");                               // loses on HIGHER (drawn suit irrelevant)
      r.ok(b.isActive(0), id + ": a guard card drawn onto a " + suit + " absorbs the wrong guess");
      r.ok(!d.suitGuards[suit], id + ": the DRAWN guard card's " + suit + " charge is spent");
      r.eq(b.top(0).value, 10, id + ": the showing card is unchanged (drawn not pushed)");
      r.eq(e.getDeck().remaining(), before, id + ": the drawn guard card returned to the deck");

      // A guard card drawn onto a NON-guarded-suit top does NOT fire (pile dies).
      const otherSuit = suit === "♠" ? "♥" : "♠";
      b.top(0).suit = otherSuit;
      forceNext(e, 3, "♠", { suitGuards: { [suit]: true } });
      e.guess(0, "higher");
      r.ok(!b.isActive(0), id + ": a guard card onto a NON-" + suit + " top does nothing (pile dies)");
    });
  }
  {
    // ONE-DIRECTIONAL: a matching-suit card drawn ONTO a guard-carrying top does
    // NOTHING (the reverse direction no longer saves).
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 9);
    e.start(); e.startRun();
    const b = e.getBoard();
    b.top(0).value = 10; b.top(0).suit = "♣"; b.top(0).suitGuards = { "♠": true };  // guard rides the TOP
    forceNext(e, 3, "♠");               // plain ♠ drawn onto it (no guards)
    e.guess(0, "higher");
    r.ok(!b.isActive(0), "a ♠ drawn onto a ♠-guard TOP does nothing (one-directional → pile dies)");
  }
  {
    // A guard ignores OTHER suits: a Heart Guard card drawn onto a ♠ top doesn't
    // fire (only a ♥ top would).
    const e = GameEngine.create(specsWith("heartGuard"), 9);
    e.start(); e.startRun();
    const b = e.getBoard();
    b.top(1).value = 10; b.top(1).suit = "♠";
    forceNext(e, 3, "♥", { suitGuards: { "♥": true } });   // a ♥-guard card, wrong top suit
    e.guess(1, "higher");
    r.ok(!b.isActive(1), "Heart Guard onto a ♠ top does nothing (pile dies)");
  }
  {
    // Two guards on one drawn card → independent per-suit charges, fired by the
    // TOP's suit.
    const specs = DeckManager.buildStandardDeck();
    specs.forEach(c => { c.stickers.push({ type: "suitImmunity" }); c.stickers.push({ type: "heartGuard" }); });
    const e = GameEngine.create(specs, 9);
    e.start(); e.startRun();
    const b = e.getBoard();
    b.top(0).value = 10; b.top(0).suit = "♠";
    const ds = forceNext(e, 3, "♣", { suitGuards: { "♠": true, "♥": true } });   // guard card lands onto a ♠ top
    e.guess(0, "higher");
    r.ok(b.isActive(0) && !ds.suitGuards["♠"], "the drawn card's ♠ charge is spent (top was ♠)");
    r.ok(ds.suitGuards["♥"], "the ♥ charge on that card is still ready (independent)");
  }
  {
    // Refreshes next run (re-projected on each deal).
    const specs = specsWith("suitImmunity");
    const e1 = GameEngine.create(specs, 9);
    e1.start(); e1.startRun();
    const b1 = e1.getBoard();
    b1.top(0).value = 10; b1.top(0).suit = "♠";
    const d = forceNext(e1, 3, "♣", { suitGuards: { "♠": true } });
    e1.guess(0, "higher");
    r.ok(b1.isActive(0) && !d.suitGuards["♠"], "the drawn guard's ♠ charge is spent in run 1");
    const e2 = GameEngine.create(specs, 9);
    e2.start();
    r.ok(e2.getBoard().top(0).suitGuards["♠"], "Suit Guard re-projects fresh for run 2");
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
    r.eq(e.getRun().bonusCoins, 0, "Tribute I (Bury 1) is now free");
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

  // --- Tribute II sticker: paid bury asks first (item 9) ---------------
  // A coin-cost Tribute never auto-charges. On landing it queues an offer and
  // emits "tribute-offer"; the bury + charge happen only when the player accepts.
  {
    const e = GameEngine.create(specsWith("twoTribute"), 10, { cols: [3, 4, 3] });
    e.start(); e.startRun([null, null, null]);
    let offer = null;
    e.onEvent((type, p) => { if (type === "tribute-offer") offer = p; });
    const len0 = e.getBoard().piles[0].cards.length;
    landHigher(e, 0);
    r.eq(e.getBoard().piles[0].cards.length, len0 + 1, "Tribute II: landing alone buries nothing (asks first)");
    r.eq(e.getRun().bonusCoins, 0, "Tribute II: no charge before confirming");
    r.ok(!!offer, "Tribute II emits a paid-bury offer on landing");
    r.eq(offer.cost, 4, "offer carries the 4-coin cost");
    r.eq(offer.count, 2, "offer buries 2 cards");
    r.ok(!!e.pendingTribute(), "an offer is queued awaiting the answer");
  }
  // Accept → bury 2 + charge 4.
  {
    const e = GameEngine.create(specsWith("twoTribute"), 10, { cols: [3, 4, 3] });
    e.start(); e.startRun([null, null, null]);
    const len0 = e.getBoard().piles[0].cards.length;
    const deck0 = e.getDeck().remaining();
    landHigher(e, 0);
    e.answerTribute(true);
    r.eq(e.getBoard().piles[0].cards.length, len0 + 3, "accept: drawn card + 2 buried");
    r.eq(e.getDeck().remaining(), deck0 - 3, "accept: deck loses drawn + 2 buried");
    r.eq(e.getRun().bonusCoins, -4, "accept: charged the 4-coin cost");
    r.ok(!e.pendingTribute(), "queue drained after accepting");
  }
  // Decline → nothing buried, nothing charged.
  {
    const e = GameEngine.create(specsWith("twoTribute"), 10, { cols: [3, 4, 3] });
    e.start(); e.startRun([null, null, null]);
    const len0 = e.getBoard().piles[0].cards.length;
    const deck0 = e.getDeck().remaining();
    landHigher(e, 0);
    e.answerTribute(false);
    r.eq(e.getBoard().piles[0].cards.length, len0 + 1, "decline: only the drawn card, nothing buried");
    r.eq(e.getDeck().remaining(), deck0 - 1, "decline: deck only loses the drawn card");
    r.eq(e.getRun().bonusCoins, 0, "decline: no charge");
    r.ok(!e.pendingTribute(), "queue drained after declining");
  }

  // (Double Tribute / Double Bury pillar removed — Tie Bury now buries 2.)

  // --- All Hearts Pillar: END-OF-RUN +5 when every SURVIVING pile in its
  //     column shows ♥ (no longer a live per-resolution payout). -------------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 3, { cols: [1, 1, 1] });
    e.start(); e.startRun(["allHeartsCoin", null, null]);   // Pillar on column 0
    const b = e.getBoard();
    b.top(0).suit = "♥";                  // col 0's only surviving pile shows ♥
    b.top(1).suit = "♠";                  // another column, ignored (column-scoped)
    r.eq(e.getRun().bonusCoins, 0, "no LIVE payout — All Hearts is end-of-run now");
    r.eq(e.pillarPayout().bonus, 8, "All Hearts scores +8 at run end: its column's survivors are all ♥");
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
    r.eq(e.pillarPayout().bonus, 8, "all surviving piles in the column ♥ → +8");
  }
  // --- One-directional Suit Guard: the DRAWN guard card saves when it lands
  //     ONTO a top of the guarded suit. --------------------------------------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 3);
    e.start(); e.startRun();
    const b = e.getBoard();
    const top = b.top(0);
    top.suit = "♠"; top.value = 14; top.suitGuards = {};   // ♠ on top, NO guard of its own
    const d = forceNext(e, 3, "♥", { suitGuards: { "♠": true } });   // drawn carries a ♠ guard
    e.guess(0, "higher");                 // wrong (3 ≤ Ace); the guard card landed onto a ♠
    r.ok(b.isActive(0), "drawn ♠-guard card saves the pile (it landed onto a ♠)");
    r.ok(!d.suitGuards["♠"], "the DRAWN card's ♠ charge is spent");
    r.eq(b.top(0).suit, "♠", "the ♠ top stays in place (drawn card not pushed)");
  }

  // --- Suit Bounty pays LIVE during play (not at run end) ---------------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    let payload = null;
    e.onEvent((t, p) => { if (t === "won") payload = p; });
    e.start(); e.startRun(["heartBounty", null, null]);
    e.getBoard().top(0).value = 5;
    forceNext(e, 9, "♥");   // a ♥ LANDS on the column
    e.guess(0, "higher");
    r.eq(e.getRun().bonusCoins, 1, "Suit Bounty ticks the live tally as a ♥ lands");
    e.debug.winNow();
    r.eq(payload.pillarPayout.bonus, 0, "Suit Bounty is NOT re-paid at run end (no double-count)");
  }

  // --- Deck-end death is a LOSS, not a deal clear ----------------------
  // If the final deck card kills the last alive pile, the kill resolves before
  // the end-of-deck check, so it must read as a loss (not a clear).
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    let result = null;
    e.onEvent((t) => { if (t === "won" || t === "lost") result = t; });
    e.start(); e.startRun();
    const b = e.getBoard();
    for (let i = 1; i < b.size; i++) b.kill(i);             // reduce to a single alive pile (0)
    r.eq(b.aliveCount(), 1, "exactly one pile alive going into the final card");
    forceNext(e, b.top(0).value);                   // a tie → wrong on a Higher guess
    e.debug.trimDeck(1);                                    // that tie is the deck's LAST card
    e.guess(0, "higher");
    r.ok(e.getDeck().isEmpty(), "the final deck card was drawn");
    r.ok(!b.anyAlive(), "the last alive pile died on that final card");
    r.eq(result, "lost", "deck-end death emits 'lost' (a loss), not 'won'");
    r.eq(e.getRun().result, "loss", "run result is recorded as a loss");
  }

  // --- A deck-end with a SURVIVOR is still a clear ----------------------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    let result = null;
    e.onEvent((t) => { if (t === "won" || t === "lost") result = t; });
    e.start(); e.startRun();
    const b = e.getBoard();
    for (let i = 1; i < b.size; i++) b.kill(i);             // one survivor (pile 0)
    b.top(0).value = 5;
    forceNext(e, 9);                                 // a correct Higher → survives
    e.debug.trimDeck(1);
    e.guess(0, "higher");
    r.ok(e.getDeck().isEmpty() && b.anyAlive(), "deck empty with a survivor");
    r.eq(result, "won", "surviving to the last card is still a clear");
  }

  // --- Tracker reconciles: live tally + end-of-run bonuses == summary ----
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    let payload = null;
    e.onEvent((t, p) => { if (t === "won") payload = p; });
    e.start();
    e.startRun(["heartBounty", null, "columnGuardian"]);   // col 0 bounty, col 2 guardian
    e.getBoard().top(0).value = 5;
    forceNext(e, 9, "♥");    // one ♥ lands → +1 live
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
    r.eq(pp.bonus, 7, "Column Guardian (col 3 all-alive) pays +7 at run end");
    // The HUD's folded final value is exactly (total − product) = the summary's
    // total bonus, and equals live + Guardian + Extra Coin.
    const finalTracker = bd.total - bd.product;
    r.eq(finalTracker, eventBonus + pp.bonus + bd.extraCoinBonus, "final tracker = live + Guardian + Extra Coin");
    r.eq(finalTracker, 8, "final bonus reconciles to the summary: 1 live + 7 Guardian = 8");
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
