// Wild Suit membership (WILD2) — cardMatchesSuit is THE single suit-membership
// test for item effects: printed match OR Wild Suit (which counts as every
// suit), on BOTH card shapes (live projected `.wildSuit` flag / persistent
// sticker record). Also the one behavior change that rode the consolidation:
// Spade Peeker now counts wild tops like every other suit-gated effect.
// Registry-driven: the wild sticker is found by BEHAVIOR, never a pinned id.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, BaseTypes, StickerTypes, cardMatchesSuit, cardIsWildSuit } = loadGame();
  const r = makeRunner("wild-suit.test.mjs");
  const SUITS = ["♠", "♥", "♦", "♣"];
  const wildDef = StickerTypes.all().find(t => t.behavior === "wildSuit");
  r.ok(!!wildDef, "a wildSuit-behavior sticker is registered in items.js");

  // --- helper coverage: wild matches all four suits, plain only its printed
  // suit — on both card shapes. ---------------------------------------------
  {
    const live = { value: 5, suit: "♣", stickers: [], wildSuit: true };        // live board shape
    const persistent = { value: 5, suit: "♣", stickers: [{ type: wildDef.id }] }; // persistent deck shape
    const plain = { value: 5, suit: "♣", stickers: [] };
    for (const s of SUITS) {
      r.ok(cardMatchesSuit(live, s), "live wild flag counts as " + s);
      r.ok(cardMatchesSuit(persistent, s), "persistent wild sticker record counts as " + s);
      r.eq(cardMatchesSuit(plain, s), s === "♣", "plain ♣ vs " + s + " matches only the printed suit");
    }
    r.ok(cardIsWildSuit(live) && cardIsWildSuit(persistent) && !cardIsWildSuit(plain),
      "cardIsWildSuit agrees on all three shapes");
    r.ok(!cardMatchesSuit(null, "♠"), "a missing card matches nothing");
  }

  // --- Spade Peeker in-engine (the ONLY behavior change) -------------------
  // col 0 = piles 0-2, col 1 = piles 3-6, col 2 = piles 7-9 (bases.test.mjs layout).
  const COLS = [3, 4, 3];
  const game = (bases) => {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: COLS });
    e.start();
    e.startRun([null, null, null], bases);
    return e;
  };
  const card = (value, suit, stickers = []) =>
    ({ value, suit, label: String(value), stickers, red: suit === "♥" || suit === "♦" });

  // Mixed column: printed-♠ top + wild non-♠ top (sticker-record shape,
  // exercising the persistent detection through the effect) + plain ♥ top → 2.
  {
    const e = game(["spadePeek", null, null]);
    const b = e.getBoard();
    b.piles[0].cards = [card(5, "♠")];
    b.piles[1].cards = [card(6, "♥", [{ type: wildDef.id }])];   // wild via the sticker RECORD
    b.piles[2].cards = [card(7, "♥")];
    r.ok(e.baseAvailable(0), "mixed ♠/wild column offers Spade Peeker");
    const res = e.baseActivate(0);
    r.eq(res.peekCount, 2, "peeks 2 (printed ♠ + wild top; plain ♥ excluded)");
    r.eq((res.cards || []).length, 2, "the peek snapshot carries both cards");
  }

  // Only-wild column (live projected-flag shape) → available, peeks exactly 1.
  {
    const e = game(["spadePeek", null, null]);
    const b = e.getBoard();
    const wild = card(9, "♦");
    wild.wildSuit = true;                                        // wild via the LIVE flag
    b.piles[0].cards = [wild];
    b.piles[1].cards = [card(4, "♥")];
    b.piles[2].cards = [card(3, "♦")];
    r.ok(e.baseAvailable(0), "an only-wild column offers Spade Peeker");
    const res = e.baseActivate(0);
    r.eq(res.peekCount, 1, "peeks exactly 1 (the wild top)");
  }

  // No ♠-or-wild top anywhere in the column → the gate still closes.
  {
    const e = game(["spadePeek", null, null]);
    const b = e.getBoard();
    b.piles[0].cards = [card(5, "♥")];
    b.piles[1].cards = [card(6, "♦")];
    b.piles[2].cards = [card(7, "♣")];
    r.ok(!e.baseAvailable(0), "no ♠/wild top → Spade Peeker unavailable");
  }

  // --- copy (items.js): the printed-♠ wild exclusion is gone ---------------
  {
    const d = BaseTypes.get("spadePeek").description || "";
    r.ok(!/printed/i.test(d) && !/don't count/i.test(d),
      "spadePeek copy carries no printed-♠ / wild-exclusion parenthetical");
  }

  return r.summary();
}
