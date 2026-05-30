// Coin payout: (alive piles) × (cards in the smallest NON-anchored alive pile)
// + Extra Coin bonus. Extra Coin now pays the pile's card count per sticker
// (Σ stickers × pile cards). Anchor excludes a pile from the "smallest" term.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { Economy, BoardState } = loadGame();
  const r = makeRunner("economy.test.mjs");
  const { EXTRA_COIN_VALUE } = Economy.COIN_CONFIG;

  // Old coefficients are gone.
  r.ok(!("WIN_BONUS" in Economy.COIN_CONFIG), "flat win bonus coefficient is gone");
  r.ok(!("PER_ALIVE_PILE" in Economy.COIN_CONFIG), "alive-piles×2 coefficient is gone");

  // No coins on a loss.
  r.eq(Economy.computeRunPayout({ won: false, aliveCount: 9, minAliveCards: 4, extraCoinUnits: 3 }), 0,
    "loss pays 0 coins");

  // Win = aliveCount × minAliveCards + extraCoinUnits × EXTRA_COIN_VALUE.
  const stats = { won: true, aliveCount: 5, minAliveCards: 4, extraCoinUnits: 12 };
  r.eq(Economy.computeRunPayout(stats), 5 * 4 + 12 * EXTRA_COIN_VALUE,
    "win pays product + Extra Coin bonus (5×4 + 12 = 32)");

  // Itemized breakdown matches the run-complete structure.
  const bd = Economy.breakdown(stats);
  r.eq(bd.alivePiles, 5, "breakdown alive-pile count");
  r.eq(bd.minPileCards, 4, "breakdown smallest-alive-pile card count");
  r.eq(bd.product, 20, "breakdown product (5 × 4)");
  r.eq(bd.extraCoinUnits, 12, "breakdown Extra Coin units");
  r.eq(bd.extraCoinBonus, 12 * EXTRA_COIN_VALUE, "breakdown Extra Coin bonus");
  r.eq(bd.total, 32, "breakdown total = product + Extra Coin bonus");
  r.eq(bd.total, Economy.computeRunPayout(stats), "breakdown total matches computeRunPayout");
  r.ok(!("extraCoinCards" in bd), "breakdown no longer reports the old per-card count");

  // Edge guard: 0 alive piles -> product 0 (not NaN), even with stickers.
  const none = Economy.breakdown({ won: true, aliveCount: 0, minAliveCards: 6, extraCoinUnits: 2 });
  r.eq(none.product, 0, "0 alive piles -> product 0");
  r.ok(!Number.isNaN(none.total), "0 alive piles -> total is a number (not NaN)");
  r.eq(none.total, 2 * EXTRA_COIN_VALUE, "0 alive piles -> total is just the Extra Coin bonus");

  // Missing fields default to 0 (no NaN leak).
  const noMin = Economy.breakdown({ won: true, aliveCount: 4, extraCoinUnits: 0 });
  r.eq(noMin.total, 0, "missing minAliveCards -> product 0");

  const lost = Economy.breakdown({ won: false, aliveCount: 9, minAliveCards: 4, extraCoinUnits: 5 });
  r.eq(lost.total, 0, "breakdown on a loss totals 0");
  r.eq(lost.extraCoinBonus, 0, "no Extra Coin bonus on a loss");

  // --- BoardState.minAliveCards (dead piles excluded) --------------------
  {
    const b = BoardState.create(3);
    b.push(0, {}); b.push(0, {}); b.push(0, {});   // pile 0: 3 cards
    b.push(1, {}); b.push(1, {});                  // pile 1: 2 cards (alive minimum)
    b.push(2, {});                                 // pile 2: 1 card, but DEAD
    b.kill(2);
    r.eq(b.minAliveCards(), 2, "minAliveCards ignores the dead 1-card pile -> 2");
    const e2e = Economy.breakdown({ won: true, aliveCount: b.aliveCount(),
      minAliveCards: b.minAliveCards(), extraCoinUnits: b.extraCoinUnits() });
    r.eq(e2e.total, 2 * 2, "end-to-end product from a real board (2 × 2 = 4)");
  }
  {
    const dead = BoardState.create(2);
    dead.push(0, {}); dead.push(1, {}); dead.kill(0); dead.kill(1);
    r.eq(dead.minAliveCards(), 0, "no alive piles -> minAliveCards 0");
  }

  // --- Anchor: excluded from the "smallest alive pile" -------------------
  const ANCHOR = () => ({ stickers: [{ type: "anchor" }] });
  {
    // pile 0: 2 cards but ANCHORED; pile 1: 5 cards; pile 2: 4 cards.
    // Smallest NON-anchored = 4 (pile 2). True smallest = 2 (anchored pile 0).
    const b = BoardState.create(3);
    b.push(0, ANCHOR()); b.push(0, {});            // anchored, 2 cards (anchor still on top? no — buried!)
    // Re-do: anchor must be the TOP card to count. Build so anchor is top.
    const b2 = BoardState.create(3);
    b2.push(0, {}); b2.push(0, ANCHOR());          // pile 0: 2 cards, anchor on TOP
    b2.push(1, {}); b2.push(1, {}); b2.push(1, {}); b2.push(1, {}); b2.push(1, {}); // pile 1: 5
    b2.push(2, {}); b2.push(2, {}); b2.push(2, {}); b2.push(2, {});                  // pile 2: 4
    r.ok(b2.isAnchored(0), "pile 0 top carries Anchor -> anchored");
    r.ok(!b2.isAnchored(1), "pile 1 has no Anchor");
    r.eq(b2.trueMinAliveCards(), 2, "trueMin counts the anchored 2-card pile");
    r.eq(b2.minAliveCards(), 4, "payout min EXCLUDES the anchored pile -> 4 (pile 2)");
  }
  {
    // Anchor buried (not the top) does NOT exclude.
    const b = BoardState.create(2);
    b.push(0, ANCHOR()); b.push(0, {});            // anchor buried under a plain top
    b.push(1, {}); b.push(1, {}); b.push(1, {});   // pile 1: 3
    r.ok(!b.isAnchored(0), "buried Anchor (not top) is not anchored");
    r.eq(b.minAliveCards(), 2, "buried Anchor doesn't exclude -> min 2");
  }
  {
    // Fallback: ALL alive piles anchored -> revert to true smallest.
    const b = BoardState.create(2);
    b.push(0, {}); b.push(0, ANCHOR());            // 2 cards, anchored top
    b.push(1, {}); b.push(1, {}); b.push(1, ANCHOR()); // 3 cards, anchored top
    r.ok(b.isAnchored(0) && b.isAnchored(1), "both piles anchored");
    r.eq(b.minAliveCards(), 2, "all-anchored fallback -> true smallest (2)");
  }

  // --- Extra Coin pays the PILE'S card count (× stickers) ----------------
  {
    // pile 0: 6 cards, 1 Extra Coin on top -> 6 units.
    const b = BoardState.create(3);
    for (let i = 0; i < 5; i++) b.push(0, {});
    b.push(0, { stickers: [{ type: "extraCoin" }] });   // 6th card, on top
    r.eq(b.extraCoinUnits(), 6, "1 Extra Coin on a 6-card alive top pays 6");

    // pile 1: 4 cards, 2 Extra Coin stickers on top -> 2 × 4 = 8 (total 14).
    b.push(1, {}); b.push(1, {}); b.push(1, {});
    b.push(1, { stickers: [{ type: "extraCoin" }, { type: "extraCoin" }] }); // 4th card
    r.eq(b.extraCoinUnits(), 6 + 2 * 4, "stacked Extra Coin: 2 stickers × 4 cards = 8 (total 14)");

    // pile 2: Extra Coin but DEAD -> contributes nothing.
    b.push(2, { stickers: [{ type: "extraCoin" }] }); b.kill(2);
    r.eq(b.extraCoinUnits(), 14, "dead pile's Extra Coin pays nothing");
  }
  {
    // Buried Extra Coin (not on top) pays nothing.
    const b = BoardState.create(1);
    b.push(0, { stickers: [{ type: "extraCoin" }] }); b.push(0, {});  // coin buried
    r.eq(b.extraCoinUnits(), 0, "buried Extra Coin (not top) pays nothing");
  }

  // --- End-to-end with Anchor + Extra Coin -------------------------------
  {
    const b = BoardState.create(3);
    // pile 0: 2 cards, anchored top (excluded from min)
    b.push(0, {}); b.push(0, ANCHOR());
    // pile 1: 4 cards, Extra Coin top -> 4 units
    b.push(1, {}); b.push(1, {}); b.push(1, {});
    b.push(1, { stickers: [{ type: "extraCoin" }] });
    // pile 2: 5 cards plain
    for (let i = 0; i < 5; i++) b.push(2, {});
    // min non-anchored = 4 (pile 1); alive = 3; product = 12; extraCoin = 4 -> 16
    const bd2 = Economy.breakdown({ won: true, aliveCount: b.aliveCount(),
      minAliveCards: b.minAliveCards(), extraCoinUnits: b.extraCoinUnits() });
    r.eq(b.minAliveCards(), 4, "e2e: anchored pile excluded -> min 4");
    r.eq(b.extraCoinUnits(), 4, "e2e: Extra Coin on a 4-card pile -> 4 units");
    r.eq(bd2.total, 3 * 4 + 4, "e2e total = 3×4 + 4 = 16");
  }

  return r.summary();
}
