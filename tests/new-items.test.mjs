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
    r.eq(PillarTypes.get("highestOdd").price, 10, "Highest Odd costs 10");
    r.eq(PillarTypes.get("highestOdd").tier, "uncommon", "Highest Odd is Uncommon");
    r.eq(PillarTypes.get("highestEven").price, 10, "Highest Even costs 10");
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
    e.getBoard().top(1).value = 13;   // King (odd)
    e.getBoard().top(2).value = 6;    // even
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 13, "Highest Odd = 13 (K) among col-0 cards");
  }
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["highestEven", null, null]);
    e.getBoard().top(0).value = 8;
    e.getBoard().top(1).value = 13;
    e.getBoard().top(2).value = 14;   // Ace (even)
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 14, "Highest Even = 14 (A) among col-0 cards");
  }
  {
    // Dead piles are excluded; buried cards still count.
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["highestOdd", null, null]);
    // pile 0: bury a King (13) under an Ace (14) top — the buried K still counts.
    e.getBoard().top(0).value = 13; e.debug.setNextCard(14); e.guess(0, "higher");
    e.getBoard().top(1).value = 9; e.getBoard().top(2).value = 5;
    e.getBoard().kill(1);   // remove the 9 pile
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 13, "Highest Odd counts a BURIED K (13) and excludes the dead pile");
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

  return r.summary();
}
