// New gameplay additions — engine-testable items:
//   Pillars: Fibonacci (live), Highest Heart (scoring),
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
    r.eq(PillarTypes.get("fibonacci").price, 8, "Fibonacci costs 8");
    r.ok(!PillarTypes.get("highestOdd"), "Highest Odd is deleted from the registry");
    r.eq(PillarTypes.get("highestEven").effect, "highestHeart", "the highestEven id now runs the Highest Heart effect");
    r.eq(PillarTypes.get("highestEven").label, "Highest Heart", "…and reads Highest Heart");
    r.eq(PillarTypes.get("denseBury").price, 20, "Dense Bury costs 20");
    r.eq(PillarTypes.get("denseBury").tier, "rare", "Dense Bury is Rare");
    r.eq(PillarTypes.get("revive").price, 25, "Revive costs 25");
    r.eq(PillarTypes.get("revive").tier, "rare", "Revive is Rare");
    r.ok(!PillarTypes.get("kamikaze"), "Kamikaze is no longer a Pillar (moved to Bases)");
    r.ok(!!StickerTypes.get("shuffle"), "Shuffle sticker registered");
    r.ok(!!StickerTypes.get("donate"), "Donate sticker registered");
    // Suit-gating is respected: none of the new items carry a `suit`, so they're
    // always eligible regardless of stage.
    r.ok(!PillarTypes.get("fibonacci").suit && !PillarTypes.get("revive").suit, "new pillars are not suit-gated");
  }

  // --- Fibonacci: +1 per Fibonacci-rank (A,2,3,5,8) drawn card landed in this
  //     column. No streak, no escalation, no reset. (Ace counts as 1.)
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start(); e.startRun(["fibonacci", null, null]);
    // Land a card of `rank` correctly on pile `i` (sets a clear higher/lower top).
    const landRank = (i, rank) => {
      const top = rank > 2 ? rank - 1 : rank + 1;
      e.getBoard().top(i).value = top;
      e.debug.setNextCard(rank);
      e.guess(i, rank > top ? "higher" : "lower");
    };
    landRank(0, 5);  r.eq(e.getRun().bonusCoins, 1, "a 5 (Fibonacci) lands → +1");
    landRank(0, 9);  r.eq(e.getRun().bonusCoins, 1, "a 9 (not Fibonacci) → no pay");
    landRank(0, 8);  r.eq(e.getRun().bonusCoins, 2, "an 8 (Fibonacci) → +1 (no escalation)");
    landRank(0, 13); r.eq(e.getRun().bonusCoins, 2, "a King (13) → no pay (not in A/2/3/5/8)");
    landRank(0, 14); r.eq(e.getRun().bonusCoins, 3, "an Ace (counts as 1) → +1");
    landRank(0, 2);  r.eq(e.getRun().bonusCoins, 4, "a 2 (Fibonacci) → +1");
    landRank(0, 3);  r.eq(e.getRun().bonusCoins, 5, "a 3 (Fibonacci) → +1");
    // Column-scoped, and immune to streak/reset coupling.
    landRank(3, 5);  r.eq(e.getRun().bonusCoins, 5, "a 5 in another column does not pay");
    landRank(0, 5);  r.eq(e.getRun().bonusCoins, 6, "still +1 after an other-column guess (no reset/streak)");
  }

  // --- Highest Heart: end-of-deal column scoring -------------------------
  // Coins = the highest ♥ TOP card in the column: 2-10 pay rank, J/Q/K pay 10,
  // the Ace pays 11. Non-♥ tops never qualify.
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["highestEven", null, null]);
    const b = e.getBoard();
    b.top(0).value = 8; b.top(0).suit = "\u2665"; b.top(0).wildSuit = false;   // 8 of hearts
    b.top(1).value = 9; b.top(1).suit = "\u2660"; b.top(1).wildSuit = false;   // higher, but a spade
    b.top(2).value = 6; b.top(2).suit = "\u2665"; b.top(2).wildSuit = false;   // lower heart
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 8, "Highest Heart = 8 (the 9 is not a heart)");
  }
  {
    // NUMBERED hearts only: royals pay 0, the Ace pays 1.
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["highestEven", null, null]);
    const b = e.getBoard();
    b.top(0).value = 13; b.top(0).suit = "\u2665"; b.top(0).wildSuit = false;  // K of hearts -> 0
    b.top(1).value = 7;  b.top(1).suit = "\u2665"; b.top(1).wildSuit = false;  // numbered -> 7
    b.top(2).value = 2;  b.top(2).suit = "\u2660"; b.top(2).wildSuit = false;
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 7, "a King of hearts pays NOTHING — the 7\u2665 wins");

    const e2 = GameEngine.create(deck(), 10, { cols: COLS });
    const won2 = onWon(e2);
    e2.start(); e2.startRun(["highestEven", null, null]);
    const b2 = e2.getBoard();
    b2.top(0).value = 14; b2.top(0).suit = "\u2665"; b2.top(0).wildSuit = false;  // A of hearts -> 1
    b2.top(1).value = 12; b2.top(1).suit = "\u2665"; b2.top(1).wildSuit = false;  // Q -> 0
    b2.top(2).value = 4;  b2.top(2).suit = "\u2660"; b2.top(2).wildSuit = false;
    e2.debug.winNow();
    r.eq(won2().pillarPayout.bonus, 1, "an Ace of hearts pays 1; a Queen pays 0");
  }
  {
    // ONLY the top card of an alive pile counts — a buried higher heart is ignored.
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["highestEven", null, null]);
    // pile 0: bury a 9\u2665 under a 10\u2660 top -> the buried heart must NOT count.
    e.getBoard().top(0).value = 9; e.getBoard().top(0).suit = "\u2665"; e.getBoard().top(0).wildSuit = false;
    const d = e.debug.setNextCard(10); d.suit = "\u2660"; d.wildSuit = false;
    e.guess(0, "higher");
    e.getBoard().top(1).value = 3; e.getBoard().top(1).suit = "\u2665"; e.getBoard().top(1).wildSuit = false;
    e.getBoard().top(2).value = 5; e.getBoard().top(2).suit = "\u2665"; e.getBoard().top(2).wildSuit = false;
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 5, "Highest Heart counts only TOP cards (buried 9\u2665 ignored -> highest \u2665 top = 5)");
  }

  // --- Dense Bury: a ♣ card with 2+ stickers landing buries 1 -----------
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start(); e.startRun(["denseBury", null, null]);
    e.getBoard().top(0).value = 5;
    const d = e.debug.setNextCard(9); d.suit = "♣";
    d.stickers = [{ type: "heavy" }, { type: "tieSafe" }];   // a ♣ with 2 stickers
    const before = e.getBoard().piles[0].cards.length;
    e.guess(0, "higher");
    r.eq(e.getBoard().piles[0].cards.length, before + 2, "♣ 2-sticker landing buries 1 (pile +2: drawn + buried)");
    r.eq(e.getRun().denseBuryUsed[0], 1, "Dense Bury fires on a ♣ at 2 stickers");
  }
  {
    // A NON-♣ card with 2 stickers does NOT fire (suit gate).
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start(); e.startRun(["denseBury", null, null]);
    e.getBoard().top(0).value = 5;
    const d = e.debug.setNextCard(9); d.suit = "♥";
    d.stickers = [{ type: "heavy" }, { type: "tieSafe" }];
    e.guess(0, "higher");
    r.eq(e.getRun().denseBuryUsed[0], 0, "a non-♣ 2-sticker card does not fire Dense Bury");
  }
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start(); e.startRun(["denseBury", null, null]);
    e.getBoard().top(0).value = 5;
    const d = e.debug.setNextCard(9); d.suit = "♣";
    d.stickers = [{ type: "heavy" }];   // a ♣ with only 1 — below the 2+ threshold
    const before = e.getBoard().piles[0].cards.length;
    e.guess(0, "higher");
    r.eq(e.getBoard().piles[0].cards.length, before + 1, "1 sticker → no Dense Bury (pile +1: drawn only)");
    r.eq(e.getRun().denseBuryUsed[0], 0, "no Dense Bury firing under 2 stickers");
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

  // --- Kamikaze (now a BASE): activate to kill a pile + peek 3 (display-only) -
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    let fired = null;
    e.onEvent((t, p) => { if (t === "base-fired") fired = p; });
    e.start(); e.startRun([null, null, null], ["kamikaze", null, null]);
    e.getBoard().top(5).suit = "♠";     // Kamikaze now only sacrifices a ♠-top pile
    r.ok(e.baseAvailable(0), "Kamikaze Base available during play with a ♠ pile + >1 alive");
    r.ok(e.baseNeedsTarget(0), "Kamikaze is a target Base (player picks a pile)");
    const nextBefore = e.getDeck().peek(1)[0].value;
    const res = e.baseActivate(0, 5);   // kill the ♠ pile 5
    r.ok(res && res.cards && res.cards.length === 3, "Kamikaze peeks the next 3 cards");
    r.ok(!e.getBoard().isActive(5), "the chosen pile is killed");
    r.ok(e.getRun().basesUsed[0], "the Base is spent for the deal");
    r.ok(fired && fired.effect === "kamikaze" && fired.index === 5, "base-fired event carries the kill");
    r.eq(e.getDeck().peek(1)[0].value, nextBefore, "draw order is unchanged (display-only look-ahead)");
    r.eq(res.cards[0].value, nextBefore, "the first peeked card is the true next draw");
    r.ok(!e.baseAvailable(0), "the Base is one-shot per deal");
    // The reveal lives ON THE DECK (like Scout), one at a time for 3 draws.
    r.eq(e.getRun().kamikazeRevealLeft, 3, "reveal armed for the next 3 draws");
    r.ok(e.revealedNextCard(), "the upcoming card shows on the deck (Scout-style)");
    r.eq(e.revealedNextCard().value, e.getDeck().peek(1)[0].value, "deck reveal = the real next card");
    winGuess(e, 0);   // draw 1
    r.eq(e.getRun().kamikazeRevealLeft, 2, "counts down one per draw");
    winGuess(e, 0);   // draw 2
    winGuess(e, 0);   // draw 3
    r.eq(e.getRun().kamikazeRevealLeft, 0, "reveal exhausted after the 3rd draw");
    r.ok(!e.revealedNextCard(), "deck returns to hidden after the third draw");
  }
  {
    // Unavailable with only one pile alive on the board.
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start(); e.startRun([null, null, null], ["kamikaze", null, null]);
    for (let i = 1; i < 10; i++) e.getBoard().kill(i);
    r.ok(!e.baseAvailable(0), "Kamikaze unavailable while only one pile is alive");
    r.eq(e.baseActivate(0, 0), null, "activation refused when unavailable");
  }

  // --- Highest Heart: dead piles excluded / column-scoped / no digging ---
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["highestEven", null, null]);
    const b = e.getBoard();
    b.top(0).value = 10; b.top(0).suit = "\u2665"; b.top(0).wildSuit = false; b.kill(0);   // dead 10\u2665 — ignored
    b.top(1).value = 6; b.top(1).suit = "\u2665"; b.top(1).wildSuit = false;
    b.top(2).value = 4; b.top(2).suit = "\u2660"; b.top(2).wildSuit = false;
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 6, "Highest Heart ignores a DEAD pile's higher \u2665 (pays 6, not 10)");
  }
  {
    // Column-scoped: another column's high heart is ignored.
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["highestEven", null, null]);
    const b = e.getBoard();
    for (const [i, v] of [[0, 2], [1, 4], [2, 6]]) { b.top(i).value = v; b.top(i).suit = "\u2665"; b.top(i).wildSuit = false; }
    b.top(3).value = 10; b.top(3).suit = "\u2665"; b.top(3).wildSuit = false;   // col1 — ignored
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 6, "Highest Heart is column-scoped (col1's 10\u2665 ignored)");
  }
  {
    // A non-\u2665-top-only column pays 0 — buried hearts are never scanned.
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["highestEven", null, null]);
    const b = e.getBoard();
    b.piles[0].cards = [{ value: 9, suit: "\u2665", stickers: [] }, { value: 12, suit: "\u2660", stickers: [] }];   // [9\u2665 buried, Q\u2660 top]
    b.kill(1); b.kill(2);   // col 0: only pile 0 alive, spade Queen on top
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 0, "no \u2665 top in the column pays 0 (buried 9\u2665 ignored)");
  }

  // --- Debug: apply a sticker to the next draw card ---------------------
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start(); e.startRun([null, null, null]);
    const card = e.debug.applyStickerToNext("tieSafe");
    r.ok(card && card.tieSafe === true, "debug applyStickerToNext projects the tieSafe flag");
    r.ok(card.stickers.some(s => s.type === "tieSafe"), "the sticker is attached to the next card");
    r.eq(e.getDeck().peek(1)[0], card, "it's the actual next deck card (drawn next)");
    // A rank sticker shifts the value live. Pick one WITHOUT a `suits`
    // restriction (items.js may restrict any given rank sticker — e.g.
    // rankUp ships ♥/♦-only — and the next deck card's suit is arbitrary).
    const rt = StickerTypes.all().find(t => t.kind === "rank" && !t.suits);
    r.ok(rt, "an unrestricted rank sticker exists to exercise the debug hook");
    const e2 = GameEngine.create(deck(), 10, { cols: COLS });
    e2.start(); e2.startRun([null, null, null]);
    const before = e2.getDeck().peek(1)[0].value;
    const c2 = e2.debug.applyStickerToNext(rt.id);
    const expected = Math.max(2, Math.min(14, before + rt.rankDelta));
    r.eq(c2 && c2.value, expected, rt.id + " shifts the next card's value by " + rt.rankDelta);
  }

  // --- Debug: change the active Pillar on a column mid-run --------------
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun([null, null, null]);   // no pillars
    r.eq(e.getRun().pillars[0], null, "column 0 starts with no Pillar");
    r.ok(e.debug.setColumnPillar(0, "highestEven"), "debug.setColumnPillar adds a Pillar mid-run");
    r.eq(e.getRun().pillars[0], "highestEven", "column 0 now holds Highest Heart");
    const hb = e.getBoard();
    hb.top(0).value = 8; hb.top(0).suit = "\u2665"; hb.top(0).wildSuit = false;
    hb.top(1).value = 4; hb.top(1).suit = "\u2660"; hb.top(1).wildSuit = false;
    hb.top(2).value = 2; hb.top(2).suit = "\u2660"; hb.top(2).wildSuit = false;
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 8, "the mid-run Pillar scores at deal end (Highest Heart = 8)");
    // Remove it again.
    const e2 = GameEngine.create(deck(), 10, { cols: COLS });
    e2.start(); e2.startRun(["greedy", null, null]);
    r.ok(e2.debug.setColumnPillar(0, null), "debug.setColumnPillar can clear a column");
    r.eq(e2.getRun().pillars[0], null, "column 0 cleared mid-run");
  }

  return r.summary();
}
