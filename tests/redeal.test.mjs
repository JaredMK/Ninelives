// Redeal (pre-run reshuffle): the engine-level guarantees that back the paid
// pre-run Redeal button. The cost escalation + button gating live in the
// (DOM-bound) UIRenderer, but the two properties that make Redeal correct are
// in the DOM-free engine and are tested here:
//   1. start(seed) is a deterministic replay — the same seed re-deals the EXACT
//      same board + draw order, and getSeed() reports it. This is what lets a
//      refresh resume the same board (so a refresh is NOT a free redeal).
//   2. A redeal re-deals from the CURRENT deck, so applied stickers ride along
//      (Rule B): re-building the engine from a stickered deck still deals those
//      cards with their sticker flags intact — nothing is lost in the reshuffle.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager } = loadGame();
  const r = makeRunner("redeal.test.mjs");

  // Full ordering signature of a deal: the dealt board tops (pile order) then
  // the remaining draw order. Two deals with the same signature are identical.
  const signature = (e) => {
    const board = e.getBoard();
    const tops = [];
    for (let i = 0; i < board.size; i++) tops.push(board.top(i).value);
    const deck = e.getDeck();
    const rest = [];
    while (!deck.isEmpty()) rest.push(deck.draw().value);
    return tops.join(",") + "|" + rest.join(",");
  };

  // --- start(seed) is a deterministic replay; getSeed() reports it ------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 9);
    e.start(12345);
    r.eq(e.getSeed(), 12345, "getSeed() returns the seed the deal used");

    const e1 = GameEngine.create(DeckManager.buildStandardDeck(), 9);
    e1.start(12345);
    const e2 = GameEngine.create(DeckManager.buildStandardDeck(), 9);
    e2.start(12345);
    r.eq(signature(e1), signature(e2),
      "same seed re-deals the EXACT same board + draw order (resume restores it)");
  }

  // --- a fresh seed genuinely reshuffles (redeal changes the board) -----
  {
    const base = GameEngine.create(DeckManager.buildStandardDeck(), 9);
    base.start(1);
    const baseSig = signature(base);
    // Find any other seed whose deal differs — a real reshuffle. (Adjacent
    // seeds essentially always differ; scanning a handful makes it robust.)
    let differs = false;
    for (let s = 2; s <= 12 && !differs; s++) {
      const e = GameEngine.create(DeckManager.buildStandardDeck(), 9);
      e.start(s);
      if (signature(e) !== baseSig) differs = true;
    }
    r.ok(differs, "a different seed produces a different deal (a real reshuffle)");
  }

  // --- start() with no seed rolls a fresh random one --------------------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 9);
    e.start();
    r.ok(typeof e.getSeed() === "number", "start() with no override rolls a seed");
  }

  // --- Rule B: stickers ride across a redeal (deck re-snapshot) ---------
  {
    // Count of cards carrying a Tie-Safe sticker in a deal. A redeal re-deals
    // from the SAME (stickered) deck, so the count is preserved — the reshuffle
    // moves cards around but never strips their stickers.
    const countTieSafe = (e) => {
      const board = e.getBoard();
      let n = 0;
      for (let i = 0; i < board.size; i++) if (board.top(i).tieSafe) n++;
      const deck = e.getDeck();
      while (!deck.isEmpty()) { if (deck.draw().tieSafe) n++; }
      return n;
    };

    const specs = DeckManager.buildStandardDeck();
    specs[0].stickers.push({ type: "tieSafe" });   // exactly one stickered card

    const first = GameEngine.create(specs, 9);
    first.start(7);
    r.eq(countTieSafe(first), 1, "the stickered card is dealt with its Tie-Safe flag");

    // Redeal = re-build the engine from the same deck with a fresh seed (this
    // mirrors startRun() re-snapshotting campaign.getRunDeck()).
    const redealt = GameEngine.create(specs, 9);
    redealt.start(99);
    r.eq(countTieSafe(redealt), 1, "after a redeal the sticker still rides on its card (Rule B)");
  }

  // --- cost escalation formula (documents the UI's 5→6→7… schedule) -----
  {
    // The UIRenderer charges REDEAL_BASE_COST (5) for the first redeal in a
    // pre-run phase and +REDEAL_STEP (1) each subsequent redeal, resetting to
    // base every new run. Mirror that pure schedule so the contract is pinned.
    const BASE = 5, STEP = 1;
    const cost = (n) => BASE + n * STEP;   // n = redeals already done this phase
    r.eq(cost(0), 5, "first redeal costs 5");
    r.eq(cost(1), 6, "second redeal costs 6");
    r.eq(cost(2), 7, "third redeal costs 7");
  }

  return r.summary();
}
