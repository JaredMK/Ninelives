// Three column-scoped peek Pillars — Unearth (bury → 50% peek), Last Rites
// (pile death → peek), Static (drawn card → 10%/sticker peek, rolled once). All
// reuse the existing deck-reveal (run.revealNextActive). The engine is DOM-free,
// so we drive guess()/baseActivate() and read run.revealNextActive directly.
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
    const u = PillarTypes.get("unearth"), l = PillarTypes.get("lastRites"), s = PillarTypes.get("static");
    r.ok(u && l && s, "all three Pillars registered");
    r.ok([u, l, s].every(t => t.tier === "rare"), "all three are Rare");
    r.eq(u.price, 7, "Unearth costs 7");
    r.eq(l.price, 5, "Last Rites costs 5");
    r.eq(s.price, 6, "Static costs 6");
    r.eq(u.effect, "unearth", "Unearth effect id");
    r.eq(l.effect, "lastRites", "Last Rites effect id");
    r.eq(s.effect, "static", "Static effect id");
    r.ok([u, l, s].every(t => t.description && t.icon), "each has a description + icon");
    r.ok([u, l, s].every(t => !t.suit), "none are suit-gated (always offerable)");
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

  // --- Static: peek chance scales with the DRAWN card's sticker count ----
  {
    // 0 stickers → chance 0 → never peeks (deterministic).
    const e0 = game(["static", null, null], [null, null, null]);
    e0.getBoard().piles[0].cards = [card(5, "♠")];
    e0.debug.setNextCard(6);            // a 0-sticker card
    e0.guess(0, "higher");             // 6 > 5 correct, drawn into col 0
    r.ok(!e0.getRun().revealNextActive, "Static: a 0-sticker drawn card never peeks");

    // 10 stickers → chance 1.0 → always peeks (deterministic).
    const e1 = game(["static", null, null], [null, null, null]);
    e1.getBoard().piles[0].cards = [card(5, "♠")];
    const nxt = e1.debug.setNextCard(6);
    nxt.stickers = Array.from({ length: 10 }, () => ({ type: "anchor" }));
    e1.guess(0, "higher");
    r.ok(e1.getRun().revealNextActive, "Static: a heavily-stickered drawn card peeks (chance ≥ 1)");

    // Column scope: a stickered draw into a NON-Static column does not peek.
    const e2 = game(["static", null, null], [null, null, null]);
    e2.getBoard().piles[5].cards = [card(5, "♠")];   // pile 5 = col 1 (no Static)
    const nxt2 = e2.debug.setNextCard(6);
    nxt2.stickers = Array.from({ length: 10 }, () => ({ type: "anchor" }));
    e2.guess(5, "higher");
    r.ok(!e2.getRun().revealNextActive, "Static is column-scoped: a stickered draw elsewhere does not peek");
  }

  // --- Unearth: a bury in its column rolls ~50% to peek (any bury source) -
  {
    // Statistical over fixed seeds (deterministic): a Sinkhole bury under a pile
    // in the Unearth column rolls 50% each time → roughly half should peek.
    const trial = (pillars, seed) => {
      const e = GameEngine.create(deck(), seed, { cols: COLS });
      e.start();
      e.startRun(pillars, ["buryLargest", null, null]);   // Sinkhole on col 0
      e.baseActivate(0);                                   // buries 1 under col-0's largest pile
      return e.getRun().revealNextActive;
    };
    let peeks = 0;
    const N = 40;
    for (let s = 0; s < N; s++) if (trial(["unearth", null, null], s)) peeks++;
    r.ok(peeks > 5 && peeks < N - 5, "Unearth: ~50% of buries peek (got " + peeks + "/" + N + ")");

    // Control: with no Unearth, the same bury never peeks on its own.
    let ctrl = 0;
    for (let s = 0; s < 12; s++) if (trial([null, null, null], s)) ctrl++;
    r.eq(ctrl, 0, "no Unearth: a bury never peeks by itself");
  }

  return r.summary();
}
