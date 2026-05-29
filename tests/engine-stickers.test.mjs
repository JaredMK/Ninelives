// Phase 2: the DOM-free engine honoring behavior stickers by reading card
// flags — Tie-Safe and Extra Heart — and reporting consumption via events.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager } = loadGame();
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
    e1.debug.setNextCard(e1.getBoard().top(0).value);
    e1.guess(0, "higher");                       // spend the heart in run 1
    r.eq(e1.getBoard().top(0).heartsRemaining, 0, "heart spent in run 1");

    const e2 = GameEngine.create(specs, 9);      // same persistent specs
    e2.start();
    r.eq(e2.getBoard().top(0).heartsRemaining, 1, "heart refreshed for run 2");
  }

  return r.summary();
}
