// Two column-scoped peek Pillars — Last Rites (pile death → peek) and Static
// (a ♠ landing correctly → peek). Both reuse the existing deck-reveal
// (run.revealNextActive). The engine is DOM-free, so we drive guess()/
// baseActivate() and read run.revealNextActive directly.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, PillarTypes } = loadGame();
  const r = makeRunner("peek-pillars.test.mjs");

  // col 0 = piles 0-2, col 1 = piles 3-6, col 2 = piles 7-9 (board size 10).
  const COLS = [3, 4, 3];
  const deck = () => DeckManager.buildStandardDeck();
  const game = (pillars, bases) => {
    const e = GameEngine.create(deck(), 7, { cols: COLS });
    e.start();
    e.startRun(pillars, bases);
    return e;
  };
  const card = (value, suit) => ({ value, suit, label: String(value), stickers: [], red: suit === "♥" || suit === "♦" });

  // --- registry: rarity (rare), costs, effects, copy --------------------
  {
    const l = PillarTypes.get("lastRites"), s = PillarTypes.get("static");
    r.ok(!PillarTypes.get("unearth"), "Unearth was removed from the registry");
    r.ok(l && s, "Last Rites + Static registered");
    r.ok([l, s].every(t => t.tier === "rare"), "both are Rare");
    r.eq(l.price, 25, "Last Rites costs 25");
    r.eq(s.price, 6, "Static costs 6");
    r.eq(l.effect, "lastRites", "Last Rites effect id");
    r.eq(s.effect, "static", "Static effect id");
    r.ok([l, s].every(t => t.description && t.icon), "each has a description + icon");
    r.ok([l, s].every(t => !t.suit), "none are suit-gated (always offerable)");
  }

  // --- Last Rites: any pile death in its column peeks (deterministic) ----
  {
    // Last Rites on col 0; a pile in col 0 dies on a wrong guess → peek.
    const e = game(["lastRites", null, null], [null, null, null]);
    const b = e.getBoard();
    b.piles[0].cards = [card(5, "♠")];
    e.debug.setNextCard(5);            // tie on HIGHER → wrong → pile dies
    e.guess(0, "higher");
    r.ok(!b.isActive(0), "the pile died");
    r.ok(e.getRun().revealNextActive, "Last Rites: a death in its column peeks the next card");

    // Column scope: a death in a column WITHOUT Last Rites does NOT peek.
    const e2 = game(["lastRites", null, null], [null, null, null]);
    const b2 = e2.getBoard();
    b2.piles[5].cards = [card(5, "♠")];   // pile 5 is in col 1 (no Last Rites)
    e2.debug.setNextCard(5);
    e2.guess(5, "higher");
    r.ok(!b2.isActive(5), "the col-1 pile died");
    r.ok(!e2.getRun().revealNextActive, "Last Rites is column-scoped: a death elsewhere does not peek");
  }

  // --- Static: a ♠ landing correctly in its column peeks the next card ---
  {
    // A ♠ lands correctly in col 0 → peek (deterministic).
    const e1 = game(["static", null, null], [null, null, null]);
    e1.getBoard().piles[0].cards = [card(5, "♥")];
    const nxt = e1.debug.setNextCard(6); nxt.suit = "♠";   // a ♠ lands
    e1.guess(0, "higher");
    r.ok(e1.getRun().revealNextActive, "Static: a ♠ landing in its column peeks the next card");

    // A NON-♠ landing does not peek.
    const e0 = game(["static", null, null], [null, null, null]);
    e0.getBoard().piles[0].cards = [card(5, "♥")];
    const n0 = e0.debug.setNextCard(6); n0.suit = "♥";
    e0.guess(0, "higher");
    r.ok(!e0.getRun().revealNextActive, "Static: a non-♠ landing does not peek");

    // Column scope: a ♠ landing in a NON-Static column does not peek.
    const e2 = game(["static", null, null], [null, null, null]);
    e2.getBoard().piles[5].cards = [card(5, "♥")];   // pile 5 = col 1 (no Static)
    const n2 = e2.debug.setNextCard(6); n2.suit = "♠";
    e2.guess(5, "higher");
    r.ok(!e2.getRun().revealNextActive, "Static is column-scoped: a ♠ landing elsewhere does not peek");
  }

  // (Unearth was removed from the roster — its bury-peek test is gone with it.)

  return r.summary();
}
