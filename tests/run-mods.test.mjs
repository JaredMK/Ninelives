// Run-level persistence + live behaviors:
//  #1 Cast (setValue) and Wild Sticker (randomSticker) record durable per-card
//     mods (cardId + change) that the UI writes onto the PERSISTENT campaign card
//     — so they last the rest of the run.
//  #5 Fibonacci pays live when a fib-rank card lands CORRECTLY in its column
//     (a wrong placement pays nothing), not only for survivors at end of deal.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, CampaignState } = loadGame();
  const r = makeRunner("run-mods.test.mjs");

  const COLS = [3, 4, 3];   // col 0 = piles 0-2, col 1 = 3-6, col 2 = 7-9
  const card = (value, suit) => ({ value, suit, label: String(value), stickers: [], red: suit === "♥" || suit === "♦" });
  // A fresh pink/regular campaign pre-holds a starting Joker (difficulty.js
  // startJokers) — deal these fixtures a joker-free deck so the random deal
  // can't land ★ on a pile top: a Joker takes the suit/rank write but toCard
  // still projects ★/0 (the durability these fixtures pin is a base-card rule).
  const dealCards = (camp) => camp.getCards().filter(c => !c.joker && !c.blank);

  // --- #1 Cast: value change persists onto the campaign card -------------
  // Cast copies the column's bottom pile RANK onto the other tops. Mimic the real
  // flow: engine fires Cast → res.valueApplied → UI writes each change to the
  // persistent deck (campaign.randomizeCard) → re-materialize.
  {
    const camp = CampaignState.create();
    const e = GameEngine.create(dealCards(camp), 7, { cols: COLS });
    e.start();
    e.startRun([null, null, null], ["setValue", null, null]);   // Cast on col 0
    const b = e.getBoard();
    b.top(0).value = 5; b.top(1).value = 9; b.top(2).value = 3;   // bottom pile (2) → source rank 3
    const res = e.baseActivate(0);
    r.eq(res.sourceValue, 3, "Cast's source is the bottom pile's rank (3)");
    r.eq(res.valueApplied.length, 2, "Cast recorded the 2 changed tops (bottom pile is the source, unchanged)");
    r.ok(res.valueApplied.every(v => v.value === 3 && v.cardId != null), "each record carries cardId + the copied rank");

    for (const v of res.valueApplied) camp.randomizeCard(v.cardId, v.value);   // what the UI does
    for (const v of res.valueApplied) {
      const cc = camp.getCards().find(x => x.id === v.cardId);
      r.eq(cc.currentRank, 3, "campaign card " + v.cardId + " holds the Cast rank");
      r.eq(DeckManager.toCard(cc).value, 3, "a fresh deal materializes card " + v.cardId + " at the Cast rank");
    }
  }

  // --- #1 Suit Setter: suit change persists onto the campaign cards ------
  {
    const camp = CampaignState.create();
    const e = GameEngine.create(dealCards(camp), 7, { cols: COLS });
    e.start();
    e.startRun([null, null, null], ["setSuit", null, null]);   // Suit Setter on col 0
    const b = e.getBoard();
    b.top(0).suit = "♠"; b.top(1).suit = "♥"; b.top(2).suit = "♣";   // bottom pile (2) → source suit ♣
    const res = e.baseActivate(0);
    r.eq(res.sourceSuit, "♣", "Suit Setter's source is the bottom pile's suit (♣)");
    r.ok(res.suitApplied.length >= 1 && res.suitApplied.every(s => s.suit === "♣" && s.cardId != null), "each record carries cardId + the copied suit");

    for (const s of res.suitApplied) camp.setCardSuit(s.cardId, s.suit);   // what the UI does
    for (const s of res.suitApplied) {
      const cc = camp.getCards().find(x => x.id === s.cardId);
      r.eq(cc.suit, "♣", "campaign card " + s.cardId + " holds the new suit");
      r.eq(DeckManager.toCard(cc).suit, "♣", "a fresh deal materializes card " + s.cardId + " at the new suit");
    }
  }

  // --- #1 Wild Sticker: the single-card sticker persists too -------------
  {
    const camp = CampaignState.create();
    const e = GameEngine.create(dealCards(camp), 7, { cols: COLS });
    e.start();
    e.startRun([null, null, null], ["randomSticker", null, null]);
    const res = e.baseActivate(0);
    r.ok(res.stickerApplied && res.stickerApplied.cardId != null, "Wild Sticker recorded the sticker (cardId + type)");
    camp.applySticker(res.stickerApplied.cardId, res.stickerApplied.typeId);
    const cc = camp.getCards().find(x => x.id === res.stickerApplied.cardId);
    r.ok(cc.stickers.some(s => s.type === res.stickerApplied.typeId), "Wild Sticker persists on the campaign card");
  }

  // --- #5 Fibonacci pays LIVE per fib-rank draw, ONLY on a correct placement --
  {
    const fib = (top, drawn, guess) => {
      const e = GameEngine.create(DeckManager.buildStandardDeck(), 7, { cols: COLS });
      e.start();
      e.startRun(["fibonacci", null, null], [null, null, null]);   // Fibonacci on col 0
      const b = e.getBoard();
      b.piles[0].cards = [card(top, "♠")];
      const before = e.getRun().bonusCoins;
      e.debug.setNextCard(drawn);
      e.guess(0, guess);
      return { paid: e.getRun().bonusCoins - before, alive: b.isActive(0) };
    };

    // Fib-rank (5) drawn, WRONG guess → pile dies → Fibonacci pays NOTHING now
    // (payout moved inside the correct-placement path).
    const dead = fib(10, 5, "higher");   // 5 < 10, higher is wrong → die
    r.ok(!dead.alive, "the pile died on the wrong guess");
    r.eq(dead.paid, 0, "Fibonacci pays nothing on a wrong placement (correct-only)");

    // Fib-rank (3) drawn, CORRECT guess → survives and pays.
    const live = fib(2, 3, "higher");    // 3 > 2, higher correct → survive
    r.ok(live.alive, "the pile survived the correct guess");
    r.eq(live.paid, 1, "Fibonacci pays on a correct fib draw too");

    // Ace (14, = 1 in the sequence) counts; a non-fib rank (4) does not.
    r.eq(fib(10, 14, "higher").paid, 1, "Ace counts as a Fibonacci rank");
    r.eq(fib(10, 4, "higher").paid, 0, "a non-fib rank (4) pays nothing");

    // Column scope: a fib draw into a column WITHOUT Fibonacci pays nothing.
    const e2 = GameEngine.create(DeckManager.buildStandardDeck(), 7, { cols: COLS });
    e2.start();
    e2.startRun(["fibonacci", null, null], [null, null, null]);
    const b2 = e2.getBoard();
    b2.piles[5].cards = [card(10, "♠")];   // pile 5 is col 1 (no Fibonacci)
    const before2 = e2.getRun().bonusCoins;
    e2.debug.setNextCard(5);
    e2.guess(5, "higher");
    r.eq(e2.getRun().bonusCoins - before2, 0, "Fibonacci is column-scoped: a fib draw elsewhere pays nothing");
  }

  return r.summary();
}
