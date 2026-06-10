// New gameplay additions — engine-testable items:
//   Pillars: Fibonacci (live), Highest Odd / Highest Even (scoring),
//            Dense Bury (composition).
//   Sticker: Random Suit (re-added) — changeSuitRandom behavior.
// (Revive / Kamikaze / Shuffle / Donate also have engine entry points exercised
//  here where they're DOM-free.) The engine is DOM-free, so we drive it directly.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, CampaignState, StickerTypes, PillarTypes } = loadGame();
  const r = makeRunner("new-items.test.mjs");

  const deck = () => DeckManager.buildStandardDeck();
  const COLS = [3, 4, 3];   // col 0 = piles 0-2, col 1 = piles 3-6, col 2 = piles 7-9.
  const onWon = (e) => { let p = null; e.onEvent((t, x) => { if (t === "won") p = x; }); return () => p; };
  const winGuess = (e, i) => { e.getBoard().top(i).value = 5; e.debug.setNextCard(9); e.guess(i, "higher"); };

  // --- registry presence -------------------------------------------------
  {
    r.ok(!!PillarTypes.get("fibonacci"), "Fibonacci pillar registered");
    r.eq(PillarTypes.get("fibonacci").tier, "rare", "Fibonacci is Rare");
    r.eq(PillarTypes.get("fibonacci").price, 6, "Fibonacci costs 6");
    r.eq(PillarTypes.get("highestOdd").price, 13, "Highest Odd costs 13 (3 more than Highest Even)");
    r.eq(PillarTypes.get("highestOdd").tier, "uncommon", "Highest Odd is Uncommon");
    r.eq(PillarTypes.get("highestEven").price, 10, "Highest Even costs 10");
    r.eq(PillarTypes.get("highestOdd").price - PillarTypes.get("highestEven").price, 3, "Highest Odd is priced 3 above Highest Even");
    r.eq(PillarTypes.get("denseBury").price, 15, "Dense Bury costs 15");
    r.eq(PillarTypes.get("denseBury").tier, "rare", "Dense Bury is Rare");
    r.eq(PillarTypes.get("revive").price, 8, "Revive costs 8");
    r.eq(PillarTypes.get("revive").tier, "uncommon", "Revive is Uncommon");
    r.eq(PillarTypes.get("kamikaze").price, 8, "Kamikaze costs 8");
    r.eq(PillarTypes.get("kamikaze").tier, "uncommon", "Kamikaze is Uncommon");
    r.ok(!!StickerTypes.get("shuffle"), "Shuffle sticker registered");
    r.ok(!!StickerTypes.get("donate"), "Donate sticker registered");
    // Suit-gating is respected: none of the new items carry a `suit`, so they're
    // always eligible regardless of stage.
    r.ok(!PillarTypes.get("fibonacci").suit && !PillarTypes.get("revive").suit, "new pillars are not suit-gated");
  }

  // --- Fibonacci: pays 1,1,2,3,5,… from the 2nd consecutive correct guess --
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start(); e.startRun(["fibonacci", null, null]);
    winGuess(e, 0); r.eq(e.getRun().bonusCoins, 0, "1st correct: no Fibonacci pay");
    winGuess(e, 0); r.eq(e.getRun().bonusCoins, 1, "2nd consecutive: +1");
    winGuess(e, 0); r.eq(e.getRun().bonusCoins, 2, "3rd: +1 (total 2)");
    winGuess(e, 0); r.eq(e.getRun().bonusCoins, 4, "4th: +2 (total 4)");
    winGuess(e, 0); r.eq(e.getRun().bonusCoins, 7, "5th: +3 (total 7)");
    winGuess(e, 0); r.eq(e.getRun().bonusCoins, 12, "6th: +5 (total 12)");
  }
  {
    // A guess in ANOTHER column resets the streak (and pays nothing itself).
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start(); e.startRun(["fibonacci", null, null]);
    winGuess(e, 0); winGuess(e, 0); winGuess(e, 0);   // total 2
    r.eq(e.getRun().bonusCoins, 2, "streak built to 3 → total 2");
    winGuess(e, 3);   // column 1 — resets col-0 streak
    r.eq(e.getRun().bonusCoins, 2, "other-column guess pays nothing and resets the streak");
    winGuess(e, 0); r.eq(e.getRun().bonusCoins, 2, "post-reset 1st col-0 correct: no pay");
    winGuess(e, 0); r.eq(e.getRun().bonusCoins, 3, "post-reset 2nd: +1");
  }
  {
    // A WRONG guess in-column resets the streak too.
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start(); e.startRun(["fibonacci", null, null]);
    winGuess(e, 0); winGuess(e, 0);   // total 1
    e.getBoard().top(1).value = 9; e.debug.setNextCard(2); e.guess(1, "higher");   // wrong on col-0 pile → resets
    r.eq(e.getRun().bonusCoins, 1, "wrong in-column guess pays nothing, resets streak");
    winGuess(e, 0); winGuess(e, 0);   // s=1 (no pay), s=2 (+1)
    r.eq(e.getRun().bonusCoins, 2, "streak rebuilt after the reset → +1");
  }

  // --- Highest Odd / Highest Even: end-of-deal column scoring ------------
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["highestOdd", null, null]);
    e.getBoard().top(0).value = 8;    // even
    e.getBoard().top(1).value = 9;    // odd number card
    e.getBoard().top(2).value = 6;    // even
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 9, "Highest Odd = 9 (highest odd number card 2–10)");
  }
  {
    // Face cards (J/Q/K) and Aces do NOT count toward Highest Odd.
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["highestOdd", null, null]);
    e.getBoard().top(0).value = 13;   // King — excluded (face)
    e.getBoard().top(1).value = 7;    // odd number card
    e.getBoard().top(2).value = 11;   // Jack — excluded (face)
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 7, "face cards excluded → highest odd number = 7");
  }
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["highestEven", null, null]);
    e.getBoard().top(0).value = 10;   // highest even number card
    e.getBoard().top(1).value = 9;
    e.getBoard().top(2).value = 14;   // Ace — excluded
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 10, "Highest Even = 10 (Ace excluded)");
  }
  {
    // ONLY the top card of an alive pile counts — a buried higher odd is ignored.
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["highestOdd", null, null]);
    // pile 0: bury a 9 under a 10 top → its TOP is 10 (even); the buried 9 must NOT count.
    e.getBoard().top(0).value = 9; e.debug.setNextCard(10); e.guess(0, "higher");
    e.getBoard().top(1).value = 3; e.getBoard().top(2).value = 5;   // top odds 3, 5
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 5, "Highest Odd counts only TOP cards (buried 9 ignored → highest odd top = 5)");
  }

  // --- Dense Bury: a 3+ sticker landing buries 1 from the deck bottom ----
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start(); e.startRun(["denseBury", null, null]);
    e.getBoard().top(0).value = 5;
    const d = e.debug.setNextCard(9);
    d.stickers = [{ type: "heavy" }, { type: "gainCoin" }, { type: "tieSafe" }];   // 3 stickers
    const before = e.getBoard().piles[0].cards.length;
    e.guess(0, "higher");
    r.eq(e.getBoard().piles[0].cards.length, before + 2, "3-sticker landing buries 1 (pile +2: drawn + buried)");
    r.eq(e.getRun().denseBuryUsed[0], 1, "Dense Bury firing counted");
  }
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start(); e.startRun(["denseBury", null, null]);
    e.getBoard().top(0).value = 5;
    const d = e.debug.setNextCard(9);
    d.stickers = [{ type: "heavy" }, { type: "tieSafe" }];   // only 2
    const before = e.getBoard().piles[0].cards.length;
    e.guess(0, "higher");
    r.eq(e.getBoard().piles[0].cards.length, before + 1, "2 stickers → no Dense Bury (pile +1: drawn only)");
    r.eq(e.getRun().denseBuryUsed[0], 0, "no Dense Bury firing under 3 stickers");
  }

  // --- Random Suit (re-added): changeSuitRandom ------------------------
  {
    const c = CampaignState.create();
    const card = c.getCards().find(x => x.suit === "♠");
    const id = card.id, rankBefore = card.currentRank;
    c.applySticker(id, "changeSuitRandom");
    const after = c.getCards().find(x => x.id === id);
    r.ok(after.suit !== "♠", "Random Suit changed the suit to a different one");
    r.eq(after.currentRank, rankBefore, "Random Suit leaves the rank unchanged");
    r.ok(after.stickers.some(s => s.type === "changeSuitRandom"), "the Random Suit sticker is attached");
    const t = StickerTypes.get("changeSuitRandom");
    r.eq(t.tier, "common", "Random Suit is Common");
    r.eq(t.price, 1, "Random Suit costs 1");
  }

  // ===== Group B: interactive items (engine entry points) ================

  const landSticker = (e, i, type) => {
    e.getBoard().top(i).value = 5;
    const d = e.debug.setNextCard(9);
    d.stickers = [{ type }];
    e.guess(i, "higher");
    return d;
  };

  // --- Shuffle: offered after landing; accept reorders, composition kept --
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    let offer = null, resolved = null;
    e.onEvent((t, p) => { if (t === "action-offer") offer = p; if (t === "action-resolved") resolved = p; });
    e.start(); e.startRun([null, null, null]);
    winGuess(e, 0);   // pile 0 → 2 cards so there's something to shuffle
    landSticker(e, 0, "shuffle");   // pile 0 → 3 cards, Shuffle offered
    r.ok(offer && offer.kind === "shuffle" && offer.index === 0, "Shuffle offered on the landing pile");
    r.ok(e.pendingAction() && e.pendingAction().kind === "shuffle", "pendingAction exposes the shuffle offer");
    const before = e.getBoard().piles[0].cards.map(c => c.value).sort().join(",");
    const len = e.getBoard().piles[0].cards.length;
    e.answerAction(true);
    const after = e.getBoard().piles[0].cards.map(c => c.value).sort().join(",");
    r.eq(e.getBoard().piles[0].cards.length, len, "shuffle keeps the pile size");
    r.eq(after, before, "shuffle keeps the exact composition (no add/remove)");
    r.ok(resolved && resolved.accepted, "action-resolved fired (accepted)");
    r.ok(!e.pendingAction(), "the queue drained after answering");
  }

  // --- Donate: move a bottom card to the smallest pile (not the smallest) --
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    let offer = null;
    e.onEvent((t, p) => { if (t === "action-offer") offer = p; });
    e.start(); e.startRun([null, null, null]);
    winGuess(e, 0); winGuess(e, 0);   // pile 0 → 3 cards (not the smallest)
    landSticker(e, 0, "donate");      // pile 0 → 4 cards; pile 1 is size 1 (smallest)
    r.ok(offer && offer.kind === "donate" && offer.index === 0, "Donate offered on the non-smallest pile");
    r.eq(offer.target, 1, "Donate targets the smallest other pile (pile 1)");
    const a0 = e.getBoard().piles[0].cards.length, a1 = e.getBoard().piles[1].cards.length;
    e.answerAction(true);
    r.eq(e.getBoard().piles[0].cards.length, a0 - 1, "donor pile lost 1 card from the bottom");
    r.eq(e.getBoard().piles[1].cards.length, a1 + 1, "smallest pile gained 1 card at the bottom");
  }
  {
    // Decline → nothing moves.
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start(); e.startRun([null, null, null]);
    winGuess(e, 0); winGuess(e, 0);
    landSticker(e, 0, "donate");
    const a0 = e.getBoard().piles[0].cards.length, a1 = e.getBoard().piles[1].cards.length;
    e.answerAction(false);
    r.eq(e.getBoard().piles[0].cards.length, a0, "declined donate moves nothing (donor unchanged)");
    r.eq(e.getBoard().piles[1].cards.length, a1, "declined donate moves nothing (target unchanged)");
  }
  {
    // No other alive pile → no Donate offer.
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    let offer = null;
    e.onEvent((t, p) => { if (t === "action-offer") offer = p; });
    e.start(); e.startRun([null, null, null]);
    for (let i = 1; i < 10; i++) e.getBoard().kill(i);   // only pile 0 alive
    landSticker(e, 0, "donate");
    r.ok(!offer, "no Donate offer when there's no smaller pile to give to");
  }

  // --- Revive: pile hits 10 → offer; revives one dead pile, once per deal --
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    let offers = 0, last = null;
    e.onEvent((t, p) => { if (t === "revive-offer") { offers++; last = p; } });
    e.start(); e.startRun(["revive", null, null]);
    const b = e.getBoard();
    for (let k = 0; k < 8; k++) b.piles[0].cards.push({ value: 3, suit: "♠", stickers: [] });  // pile 0 → 9
    b.kill(3);   // a dead pile exists (column 1)
    winGuess(e, 0);   // pile 0 → 10 → Revive offered
    r.eq(offers, 1, "Revive offered when a col pile reaches 10 with a dead pile present");
    r.ok(last && last.col === 0 && last.dead.indexOf(3) !== -1, "offer names the column and the dead piles");
    r.ok(!b.isActive(3), "pile 3 still dead before the player picks");
    r.ok(e.reviveDeadPile(0, 3), "reviveDeadPile revives the chosen dead pile");
    r.ok(b.isActive(3), "pile 3 is alive again");
    r.ok(b.top(3) && b.piles[3].cards.length >= 1, "revived pile has a fresh top");
    r.ok(e.getRun().reviveUsed[0], "Revive marked spent for the column");
    winGuess(e, 0);   // pile 0 → 11, still ≥10
    r.eq(offers, 1, "Revive is one-shot per deal (no second offer)");
  }
  {
    // No dead pile when it triggers → skipped, NOT consumed (stays ready).
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    let offers = 0;
    e.onEvent((t, p) => { if (t === "revive-offer") offers++; });
    e.start(); e.startRun(["revive", null, null]);
    const b = e.getBoard();
    for (let k = 0; k < 8; k++) b.piles[0].cards.push({ value: 3, suit: "♠", stickers: [] });
    winGuess(e, 0);   // pile 0 → 10, but nothing is dead
    r.eq(offers, 0, "no Revive offer with no dead pile");
    r.eq(e.getRun().reviveUsed[0], false, "the charge is NOT consumed — it stays ready");
    b.kill(4);
    winGuess(e, 0);   // now a dead pile exists and the pile is ≥10 → offers
    r.eq(offers, 1, "Revive fires later once a pile is dead (it waited, stayed ready)");
  }

  // --- Kamikaze: activate to kill a pile + reveal 3 (display-only) -------
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    let fired = null;
    e.onEvent((t, p) => { if (t === "kamikaze-fired") fired = p; });
    e.start(); e.startRun(["kamikaze", null, null]);
    r.ok(e.kamikazeAvailable(0), "Kamikaze available during play with >1 pile alive");
    const nextBefore = e.getDeck().peek(1)[0].value;
    const cards = e.kamikazeActivate(0, 5);   // kill pile 5
    r.ok(cards && cards.length === 3, "Kamikaze reveals the next 3 cards");
    r.ok(!e.getBoard().isActive(5), "the chosen pile is killed");
    r.ok(e.getRun().kamikazeUsed[0], "Kamikaze is spent");
    r.ok(fired && fired.index === 5 && fired.cards.length === 3, "kamikaze-fired event carries the kill + cards");
    r.eq(e.getDeck().peek(1)[0].value, nextBefore, "draw order is unchanged (display-only look-ahead)");
    r.eq(cards[0].value, nextBefore, "the first revealed card is the true next draw");
    r.ok(!e.kamikazeAvailable(0), "Kamikaze is one-shot per deal");
    // The reveal now lives ON THE DECK (like Scout), one at a time for 3 draws.
    r.eq(e.getRun().kamikazeRevealLeft, 3, "reveal armed for the next 3 draws");
    r.ok(e.revealedNextCard(), "the upcoming card shows on the deck (Scout-style)");
    r.eq(e.revealedNextCard().value, e.getDeck().peek(1)[0].value, "deck reveal = the real next card");
    winGuess(e, 0);   // draw 1
    r.eq(e.getRun().kamikazeRevealLeft, 2, "counts down one per draw");
    r.ok(e.revealedNextCard(), "still revealing through draw 2");
    winGuess(e, 0);   // draw 2
    r.ok(e.revealedNextCard(), "still revealing through draw 3");
    winGuess(e, 0);   // draw 3
    r.eq(e.getRun().kamikazeRevealLeft, 0, "reveal exhausted after the 3rd draw");
    r.ok(!e.revealedNextCard(), "deck returns to hidden after the third draw");
  }
  {
    // Unavailable with only one pile alive on the board.
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start(); e.startRun(["kamikaze", null, null]);
    for (let i = 1; i < 10; i++) e.getBoard().kill(i);
    r.ok(!e.kamikazeAvailable(0), "unavailable while only one pile is alive");
    r.eq(e.kamikazeActivate(0, 0), null, "activation refused when unavailable");
  }
  {
    // Unavailable when its OWN column is entirely dead (others still alive).
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start(); e.startRun(["kamikaze", null, null]);
    e.getBoard().kill(0); e.getBoard().kill(1); e.getBoard().kill(2);   // column 0 all dead
    r.ok(!e.kamikazeAvailable(0), "unavailable when its own column is all dead");
  }

  // --- Highest Even / Odd: dead piles excluded (regression lock) ---------
  // A dead pile in the column holding a HIGHER qualifying card must NOT count.
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["highestEven", null, null]);
    const b = e.getBoard();
    b.top(0).value = 10; b.kill(0);   // dead pile holds a 10 — must be ignored
    b.top(1).value = 6; b.top(2).value = 4;
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 6, "Highest Even ignores a DEAD pile's higher even (pays 6, not 10)");
  }
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["highestOdd", null, null]);
    const b = e.getBoard();
    b.top(0).value = 9; b.kill(0);    // dead pile holds a 9 — must be ignored
    b.top(1).value = 5; b.top(2).value = 4;
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 5, "Highest Odd ignores a DEAD pile's higher odd (pays 5, not 9)");
  }
  {
    // Column-scoped: another column's high even is ignored.
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["highestEven", null, null]);
    const b = e.getBoard();
    b.top(0).value = 2; b.top(1).value = 4; b.top(2).value = 6;   // col0
    b.top(3).value = 10;   // col1 — ignored
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 6, "Highest Even is column-scoped (col1's 10 ignored)");
  }
  {
    // Highest Even is ALSO top-only (the twin) — a buried higher even is ignored.
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["highestEven", null, null]);
    // pile 0: bury a 10 under a 3 top → its TOP is 3 (odd); the buried 10 must NOT count.
    e.getBoard().top(0).value = 10; e.debug.setNextCard(3); e.guess(0, "lower");
    e.getBoard().top(1).value = 4; e.getBoard().top(2).value = 6;   // top evens 4, 6
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 6, "Highest Even counts only TOP cards (buried 10 ignored → highest even top = 6)");
  }

  // --- Debug: apply a sticker to the next draw card ---------------------
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start(); e.startRun([null, null, null]);
    const card = e.debug.applyStickerToNext("tieSafe");
    r.ok(card && card.tieSafe === true, "debug applyStickerToNext projects the tieSafe flag");
    r.ok(card.stickers.some(s => s.type === "tieSafe"), "the sticker is attached to the next card");
    r.eq(e.getDeck().peek(1)[0], card, "it's the actual next deck card (drawn next)");
    // A rank sticker shifts the value live.
    const e2 = GameEngine.create(deck(), 10, { cols: COLS });
    e2.start(); e2.startRun([null, null, null]);
    const before = e2.getDeck().peek(1)[0].value;
    const c2 = e2.debug.applyStickerToNext("rankUp");
    r.eq(c2.value, Math.min(14, before + 1), "rankUp shifts the next card's value +1");
  }

  // --- Debug: change the active Pillar on a column mid-run --------------
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun([null, null, null]);   // no pillars
    r.eq(e.getRun().pillars[0], null, "column 0 starts with no Pillar");
    r.ok(e.debug.setColumnPillar(0, "highestEven"), "debug.setColumnPillar adds a Pillar mid-run");
    r.eq(e.getRun().pillars[0], "highestEven", "column 0 now holds Highest Even");
    e.getBoard().top(0).value = 8; e.getBoard().top(1).value = 4; e.getBoard().top(2).value = 2;
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 8, "the mid-run Pillar scores at deal end (Highest Even = 8)");
    // Remove it again.
    const e2 = GameEngine.create(deck(), 10, { cols: COLS });
    e2.start(); e2.startRun(["greedy", null, null]);
    r.ok(e2.debug.setColumnPillar(0, null), "debug.setColumnPillar can clear a column");
    r.eq(e2.getRun().pillars[0], null, "column 0 cleared mid-run");
  }

  return r.summary();
}
