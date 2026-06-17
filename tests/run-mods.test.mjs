// Run-level persistence + live behaviors:
//  #1 Cast (setValue) and Sticker Storm / Wild Sticker (randomStickerAll /
//     randomSticker) record durable per-card mods (cardId + change) that the UI
//     writes onto the PERSISTENT campaign card — so they last the rest of the run.
//  #3 Each Cast rolls its OWN value (no shared per-deal roll).
//  #5 Fibonacci pays live the moment a fib-rank card is drawn into its column,
//     win or lose, not only for survivors at end of deal.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, CampaignState } = loadGame();
  const r = makeRunner("run-mods.test.mjs");

  const COLS = [3, 4, 3];   // col 0 = piles 0-2, col 1 = 3-6, col 2 = 7-9
  const card = (value, suit) => ({ value, suit, label: String(value), stickers: [], red: suit === "♥" || suit === "♦" });

  // --- #1 Cast: value change persists onto the campaign card -------------
  // Mimic the real flow: engine fires Cast → res.valueApplied → UI writes each
  // change to the persistent deck (campaign.randomizeCard) → re-materialize.
  {
    const camp = CampaignState.create();
    const e = GameEngine.create(camp.getCards(), 7, { cols: COLS });
    e.start();
    e.startRun([null, null, null], ["setValue", null, null]);   // Cast on col 0
    const res = e.baseActivate(0);
    const y = res.valueApplied[0].value;
    r.ok(res.valueApplied.length === 3, "Cast recorded all 3 column cards for persistence");
    r.ok(res.valueApplied.every(v => v.value === y && v.cardId != null), "each record carries cardId + the rolled value");

    for (const v of res.valueApplied) camp.randomizeCard(v.cardId, v.value);   // what the UI does
    for (const v of res.valueApplied) {
      const cc = camp.getCards().find(x => x.id === v.cardId);
      r.eq(cc.currentRank, y, "campaign card " + v.cardId + " holds the Cast value");
      r.eq(DeckManager.toCard(cc).value, y, "a fresh deal materializes card " + v.cardId + " at the Cast value");
    }
  }

  // --- #1 Sticker Storm: stickers persist onto the campaign cards --------
  {
    const camp = CampaignState.create();
    const e = GameEngine.create(camp.getCards(), 7, { cols: COLS });
    e.start();
    e.startRun([null, null, null], ["randomStickerAll", null, null]);   // Sticker Storm on col 0
    const res = e.baseActivate(0);
    r.ok(res.stickersApplied && res.stickersApplied.length > 0, "Sticker Storm recorded the stickers it applied");
    r.ok(res.stickersApplied.every(a => a.cardId != null && a.typeId), "each record carries cardId + sticker type");

    for (const a of res.stickersApplied) camp.applySticker(a.cardId, a.typeId);   // what the UI does
    for (const a of res.stickersApplied) {
      const cc = camp.getCards().find(x => x.id === a.cardId);
      r.ok(cc.stickers.some(s => s.type === a.typeId), "campaign card " + a.cardId + " keeps the Storm sticker");
      r.ok(DeckManager.toCard(cc).stickers.some(s => s.type === a.typeId), "a fresh deal materializes the sticker");
    }
  }

  // --- #1 Wild Sticker: the single-card sticker persists too -------------
  {
    const camp = CampaignState.create();
    const e = GameEngine.create(camp.getCards(), 7, { cols: COLS });
    e.start();
    e.startRun([null, null, null], ["randomSticker", null, null]);
    const res = e.baseActivate(0);
    r.ok(res.stickerApplied && res.stickerApplied.cardId != null, "Wild Sticker recorded the sticker (cardId + type)");
    camp.applySticker(res.stickerApplied.cardId, res.stickerApplied.typeId);
    const cc = camp.getCards().find(x => x.id === res.stickerApplied.cardId);
    r.ok(cc.stickers.some(s => s.type === res.stickerApplied.typeId), "Wild Sticker persists on the campaign card");
  }

  // --- #3 Multiple Casts roll INDEPENDENT values ------------------------
  {
    // Two Casts in one deal. A shared per-deal roll would force equal values;
    // independent rolls (consecutive rng draws) differ for this seed.
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 7, { cols: COLS });
    e.start();
    e.startRun([null, null, null], ["setValue", "setValue", null]);   // Cast on col 0 AND col 1
    const a = e.baseActivate(0).valueApplied[0].value;
    const b = e.baseActivate(1).valueApplied[0].value;
    r.ok(a !== b, "two Casts rolled independent values (got " + a + " and " + b + ", not a shared roll)");
  }

  // --- #5 Fibonacci pays LIVE per fib-rank draw, win or lose -------------
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

    // Fib-rank (5) drawn, WRONG guess → pile dies, but Fibonacci STILL pays.
    const dead = fib(10, 5, "higher");   // 5 < 10, higher is wrong → die
    r.ok(!dead.alive, "the pile died on the wrong guess");
    r.eq(dead.paid, 1, "Fibonacci paid +1 for the fib-rank draw even though the pile died");

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
