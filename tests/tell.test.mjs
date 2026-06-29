// Tell — a partial-information sticker. When the stickered card lands correctly
// and becomes the pile card, it arms a DIRECTIONAL hint for the NEXT drawn card:
// higher / lower / same vs the pile card. Display-only (engine.pileHint is a pure
// peek — never changes draw order/RNG), correctly reports "same" on a tie, and is
// a strict ONE-FLIP one-shot: the next draw on ANY pile consumes the predicted
// next card, so it clears then (not only when its own pile is drawn).
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, StickerTypes } = loadGame();
  const r = makeRunner("tell.test.mjs");

  // --- registry ----------------------------------------------------------
  {
    const t = StickerTypes.get("tell");
    r.ok(!!t, "Tell is registered");
    r.eq(t.behavior, "tell", "Tell carries the tell behavior");
    r.eq(t.tier, "uncommon", "Tell is Uncommon");
    r.eq(t.price, 2, "Tell costs 2");
    r.ok(!t.suit, "Tell is not suit-gated (always offerable)");
    r.ok(t.description && t.icon, "Tell has a description + icon");
  }

  /** A started 9-pile run, pile 0's top pinned to `topVal`, then a Tell-stickered
      card of `landVal` drawn onto pile 0 with a guaranteed-correct guess. Returns
      the engine with pile 0's top now = the Tell card. */
  const armTell = (topVal, landVal, guess) => {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 9);
    e.start(); e.startRun();
    e.getBoard().top(0).value = topVal;
    const nc = e.debug.setNextCard(landVal);
    nc.stickers = [{ type: "tell" }];           // the drawn card carries Tell
    e.guess(0, guess);
    return e;
  };

  // --- the hint reports the REAL next card's direction -------------------
  {
    // Tell card (value 9) is now pile 0's top. Force the next card and read the hint.
    const e = armTell(5, 9, "higher");
    r.ok(e.getBoard().isActive(0) && e.getBoard().top(0).value === 9, "Tell card landed as pile 0's top");

    e.debug.setNextCard(11);
    r.eq(e.pileHint(0), "higher", "next card 11 > pile card 9 → higher");
    e.debug.setNextCard(3);
    r.eq(e.pileHint(0), "lower", "next card 3 < pile card 9 → lower");
    e.debug.setNextCard(9);
    r.eq(e.pileHint(0), "same", "next card 9 == pile card 9 → SAME (a tie, reported distinctly)");

    // Unarmed pile has no hint.
    r.eq(e.pileHint(1), null, "a pile with no Tell shows no hint");
  }

  // --- display-only: pileHint() never draws / changes order --------------
  {
    const e = armTell(5, 9, "higher");
    e.debug.setNextCard(7);
    const before = e.getDeck().remaining();
    e.pileHint(0); e.pileHint(0);                 // reading the hint repeatedly
    r.eq(e.getDeck().remaining(), before, "pileHint() does not draw a card");
    // The card the hint described is exactly the one that comes out next.
    e.guess(0, "higher");
    r.eq(e.getBoard().top(0).value, 7, "the real next card (7) was the one drawn — order unchanged");
  }

  // --- the hint clears after the next draw on that pile ------------------
  {
    const e = armTell(5, 9, "higher");
    e.debug.setNextCard(11);
    r.eq(e.pileHint(0), "higher", "hint armed before the next draw");
    // Next draw on pile 0 with a NON-Tell card → consumes the hint, no re-arm.
    e.debug.setNextCard(2);                       // a plain 2 (no stickers)
    e.guess(0, "lower");                          // 2 < 9 → correct, lands a non-Tell card
    r.eq(e.pileHint(0), null, "hint cleared after the next draw on that pile (non-Tell card)");
  }

  // --- one-flip: a draw on a DIFFERENT pile also clears the hint ----------
  {
    // The hint predicts the deck's single NEXT card; drawing it on ANY pile spends
    // it, so a Tell armed on pile 0 must clear after a draw on pile 1 (no lingering
    // re-prediction across other-pile flips).
    const e = armTell(5, 9, "higher");
    e.debug.setNextCard(11);
    r.eq(e.pileHint(0), "higher", "Tell armed on pile 0");
    e.getBoard().top(1).value = 5;
    e.debug.setNextCard(2);                       // a plain 2 (no stickers)
    e.guess(1, "lower");                          // draw on a DIFFERENT pile (1)
    r.eq(e.pileHint(0), null, "hint on pile 0 cleared by a flip on pile 1 (one-flip one-shot)");
  }

  // --- "same" landing (a correct Same guess) also arms correctly --------
  {
    // Pile 0 top = 6; draw a Tell 6 and call Same (a tie that survives) → the Tell
    // card becomes the top, hint armed. Confirms Same-landed Tell works too.
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 9);
    e.start(); e.startRun();
    e.getBoard().top(0).value = 6;
    const nc = e.debug.setNextCard(6);
    nc.stickers = [{ type: "tell" }];
    e.guess(0, "same");
    r.ok(e.getBoard().isActive(0), "pile survived the correct Same");
    e.debug.setNextCard(6);
    r.eq(e.pileHint(0), "same", "Tell armed after a Same landing, reads a tie as same");
  }

  return r.summary();
}
