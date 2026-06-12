// Phase 2: the DOM-free engine honoring behavior stickers by reading card
// flags — Tie-Safe and Extra Heart — and reporting consumption via events.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, StickerTypes } = loadGame();
  const r = makeRunner("engine-stickers.test.mjs");

  // Build a run where EVERY card has the given sticker, so whatever lands on
  // top of a pile carries it (the deal is shuffled).
  const specsWith = (type) => {
    const specs = DeckManager.buildStandardDeck();
    specs.forEach(c => c.stickers.push({ type }));
    return specs;
  };

  // --- Tie-Safe: a tie counts as safe on any guess ----------------------
  {
    const e = GameEngine.create(specsWith("tieSafe"), 9);
    e.start();
    e.startRun();   // explicit Start Run begins active play (guessing gated on it)
    const top = e.getBoard().top(0).value;
    e.debug.setNextCard(top);   // force a tie
    e.guess(0, "higher");       // would normally die on a tie
    r.ok(e.getBoard().isActive(0), "Tie-Safe: tie on HIGHER survives");
  }

  // --- Extra Heart: absorb a wrong guess, return the card, refresh ------
  {
    const e = GameEngine.create(specsWith("extraHeart"), 9);
    let heartBroken = 0;
    e.onEvent((t) => { if (t === "heart-broken") heartBroken++; });
    e.start();
    e.startRun();

    const board = e.getBoard();
    const topCard = board.top(0);
    r.eq(topCard.heartsRemaining, 1, "dealt card has 1 heart from its sticker");

    const before = e.getDeck().remaining();
    const topVal = topCard.value;
    // Force a guaranteed-wrong guess: draw the same value but guess "higher".
    e.debug.setNextCard(topVal);
    e.guess(0, "higher");

    r.ok(board.isActive(0), "Extra Heart: pile survives a wrong guess");
    r.eq(board.top(0).value, topVal, "top card is unchanged (drawn card not pushed)");
    r.eq(board.top(0).heartsRemaining, 0, "the heart was spent (run-local)");
    r.eq(e.getDeck().remaining(), before, "drawn card was returned to the deck");
    r.eq(heartBroken, 1, "a heart-broken event fired");

    // With the heart spent, a second wrong guess kills the pile.
    e.debug.setNextCard(board.top(0).value);
    e.guess(0, "higher");
    r.ok(!board.isActive(0), "without a heart, the next wrong guess kills the pile");
  }

  // --- "refreshes next run": a fresh deal restores heartsRemaining ------
  {
    const specs = specsWith("extraHeart");
    const e1 = GameEngine.create(specs, 9);
    e1.start();
    e1.startRun();
    e1.debug.setNextCard(e1.getBoard().top(0).value);
    e1.guess(0, "higher");                       // spend the heart in run 1
    r.eq(e1.getBoard().top(0).heartsRemaining, 0, "heart spent in run 1");

    const e2 = GameEngine.create(specs, 9);      // same persistent specs
    e2.start();
    r.eq(e2.getBoard().top(0).heartsRemaining, 1, "heart refreshed for run 2");
  }

  // --- stacked Extra Hearts: each grants one survival, decrement independently
  {
    const specs = DeckManager.buildStandardDeck();
    specs.forEach(c => { c.stickers.push({ type: "extraHeart" }); c.stickers.push({ type: "extraHeart" }); });
    const e = GameEngine.create(specs, 9);
    e.start();
    e.startRun();
    r.eq(e.getBoard().top(0).heartsRemaining, 2, "two Extra Hearts -> heartsRemaining 2");
    const top = e.getBoard().top(0).value;
    e.debug.setNextCard(top); e.guess(0, "higher");   // wrong -> break 1
    r.ok(e.getBoard().isActive(0) && e.getBoard().top(0).heartsRemaining === 1, "1st wrong: survive, 1 heart left");
    e.debug.setNextCard(e.getBoard().top(0).value); e.guess(0, "higher"); // wrong -> break 2
    r.ok(e.getBoard().isActive(0) && e.getBoard().top(0).heartsRemaining === 0, "2nd wrong: survive, 0 hearts left");
    e.debug.setNextCard(e.getBoard().top(0).value); e.guess(0, "higher"); // wrong -> die
    r.ok(!e.getBoard().isActive(0), "3rd wrong with no hearts: pile dies");
  }

  // --- Duplicate: copies on a SURVIVED correct Same (drawn OR pile card) -
  {
    // Only the DRAWN card carries Duplicate; force a Same tie on pile 0.
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 9);
    e.start(); e.startRun();
    let copies = 0; e.onEvent((t) => { if (t === "card-duplicated") copies++; });
    const nc = e.debug.setNextCard(e.getBoard().top(0).value);   // a tie
    nc.stickers = [{ type: "duplicate" }];
    e.guess(0, "same");
    r.eq(copies, 1, "Duplicate copies when its (drawn) card survives a correct Same");
    r.ok(e.getBoard().isActive(0), "the pile survives the same");

    // Pile card carries Duplicate (drawn card does not) — still copies.
    const e2 = GameEngine.create(DeckManager.buildStandardDeck(), 9);
    e2.start(); e2.startRun();
    e2.getBoard().top(0).stickers = [{ type: "duplicate" }];
    let copies2 = 0; e2.onEvent((t) => { if (t === "card-duplicated") copies2++; });
    e2.debug.setNextCard(e2.getBoard().top(0).value);
    e2.guess(0, "same");
    r.eq(copies2, 1, "Duplicate fires with the sticker on the PILE card too");

    // A correct NON-Same guess does not copy.
    const e3 = GameEngine.create(specsWith("duplicate"), 9);
    e3.start(); e3.startRun();
    let copies3 = 0; e3.onEvent((t) => { if (t === "card-duplicated") copies3++; });
    const top = e3.getBoard().top(0).value;
    const v = top < 14 ? top + 1 : top - 1;
    e3.debug.setNextCard(v);
    e3.guess(0, v > top ? "higher" : "lower");
    r.eq(copies3, 0, "Duplicate does NOT copy on a correct non-Same guess");
  }

  // --- sticker window: explicit Start Run trigger ------------------------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 9);
    e.start();
    r.ok(e.canApplyStickers(), "window OPEN after deal (sticker phase)");
    r.ok(!e.isRunStarted(), "run not started until Start Run");

    // Guessing is gated on Start Run: a guess before it is a no-op.
    const topVal = e.getBoard().top(0).value;
    const remBefore = e.getDeck().remaining();
    e.guess(0, "higher");
    r.eq(e.getDeck().remaining(), remBefore, "guess before Start Run draws nothing (no-op)");
    r.ok(e.canApplyStickers(), "window still OPEN — a pre-start guess didn't close it");

    e.startRun();
    r.ok(e.isRunStarted(), "isRunStarted true after Start Run");
    r.ok(!e.canApplyStickers(), "window CLOSED by Start Run");

    // startRun is idempotent and guessing now works.
    e.startRun();
    r.ok(e.isRunStarted() && !e.canApplyStickers(), "startRun is idempotent");
    e.guess(0, "higher");
    r.ok(e.getDeck().remaining() < remBefore, "guessing works after Start Run");
  }

  // --- Scout: reveal the next card on placement, display-only ------------
  {
    r.eq(StickerTypes.get("revealNext").tier, "rare", "Scout is a Rare sticker");

    const e = GameEngine.create(DeckManager.buildStandardDeck(), 9);
    let lastDrawn = null;
    e.onEvent((t, p) => { if (p && p.drawn) lastDrawn = p.drawn; });
    e.start(); e.startRun();
    r.ok(e.revealedNextCard() == null, "no reveal active without a placed Scout card");

    // Land a Scout card with a guaranteed-correct guess.
    const top = e.getBoard().top(0); top.value = 5;
    const d = e.debug.setNextCard(9); d.revealNext = true; d.stickers = [{ type: "revealNext" }];
    const realNext = e.getDeck().peek(2)[1];   // the card AFTER the Scout card (its reveal target)
    e.guess(0, "higher");                      // 9 > 5 → correct → Scout lands
    r.ok(e.getBoard().isActive(0), "Scout card landed on the pile");

    const revealed = e.revealedNextCard();
    r.ok(revealed && revealed.id != null, "placing the Scout card reveals the next deck card");
    r.eq(revealed.id, e.getDeck().peek(1)[0].id, "revealed = the deck's REAL next card (no reshuffle)");
    r.eq(revealed.id, realNext.id, "revealed card is exactly the one already queued (draw order unchanged)");

    // The next draw is exactly the revealed card, and the reveal then clears.
    const remBefore = e.getDeck().remaining();
    e.guess(0, "higher");
    r.eq(lastDrawn.id, revealed.id, "the card actually drawn is the one that was revealed");
    r.eq(e.getDeck().remaining(), remBefore - 1, "exactly one card drawn (RNG/order untouched)");
    r.ok(e.revealedNextCard() == null, "reveal clears once the revealed card is drawn");
  }

  // --- Scout on a starting top reveals from run start -------------------
  {
    const e = GameEngine.create(specsWith("revealNext"), 9);   // every top carries Scout
    e.start(); e.startRun();
    const revealed = e.revealedNextCard();
    r.ok(revealed && revealed.id != null, "Scout on a starting top reveals the next card at run start");
    r.eq(revealed.id, e.getDeck().peek(1)[0].id, "starting-top reveal = the deck's real next card");
  }

  // --- a fresh run re-opens the sticker phase ----------------------------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 9);
    e.start(); e.startRun();
    r.ok(!e.canApplyStickers(), "window closed mid-run");
    e.start();   // next run deals fresh
    r.ok(e.canApplyStickers() && !e.isRunStarted(), "new run re-opens the sticker phase");
  }

  return r.summary();
}
