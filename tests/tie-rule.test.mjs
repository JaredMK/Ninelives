// Phase 0 regression test: locks the real tie rule.
//
// Rule: the player guesses Higher, Lower, or Same. A tie (drawn rank ===
// current top rank) counts as WRONG on a Higher or Lower guess and kills the
// pile; only a correct "Same" guess survives a tie.
//
// The engine already implements this (GameEngine.guess uses strict >/< for
// higher/lower and === for same). This test keeps it from silently regressing.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager } = loadGame();
  const r = makeRunner("tie-rule.test.mjs");

  // Fresh engine with a full standard deck dealt across 9 piles.
  const fresh = () => {
    const engine = GameEngine.create(DeckManager.buildStandardDeck(), 9);
    engine.start();
    return engine;
  };

  // --- ties ---------------------------------------------------------------
  {
    const e = fresh();
    const top = e.getBoard().top(0).value;
    e.debug.setNextCard(top); // force a tie
    e.guess(0, "higher");
    r.ok(!e.getBoard().isActive(0), "tie on HIGHER kills the pile");
  }
  {
    const e = fresh();
    const top = e.getBoard().top(0).value;
    e.debug.setNextCard(top);
    e.guess(0, "lower");
    r.ok(!e.getBoard().isActive(0), "tie on LOWER kills the pile");
  }
  {
    const e = fresh();
    const top = e.getBoard().top(0).value;
    e.debug.setNextCard(top);
    e.guess(0, "same");
    r.ok(e.getBoard().isActive(0), "correct SAME on a tie survives");
    r.eq(e.getBoard().top(0).value, top, "SAME tie pushes the drawn card as new top");
  }

  // --- genuine (non-tie) outcomes still resolve as before -----------------
  {
    const e = fresh();
    const top = e.getBoard().top(0).value;
    if (top < 14) {
      e.debug.setNextCard(top + 1);
      e.guess(0, "higher");
      r.ok(e.getBoard().isActive(0), "HIGHER with a strictly greater card survives");
    } else {
      r.ok(true, "(skipped HIGHER case: pile 0 top is an Ace)");
    }
  }
  {
    const e = fresh();
    const top = e.getBoard().top(0).value;
    if (top > 2) {
      e.debug.setNextCard(top - 1);
      e.guess(0, "higher");
      r.ok(!e.getBoard().isActive(0), "HIGHER with a lower card kills the pile");
    } else {
      r.ok(true, "(skipped: pile 0 top is a 2)");
    }
  }

  return r.summary();
}
