// Coin payout: (alive piles) × (cards in the smallest alive pile) + Extra Coin
// bonus. The old flat win bonus and alive×2 term are gone — superseded by the
// product. Plus the board helpers feeding the multiplier (minAliveCards) and
// the Extra Coin count (aliveTopStickerCount).
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { Economy, BoardState } = loadGame();
  const r = makeRunner("economy.test.mjs");
  const { EXTRA_COIN_VALUE } = Economy.COIN_CONFIG;

  // Old coefficients are gone.
  r.ok(!("WIN_BONUS" in Economy.COIN_CONFIG), "flat win bonus coefficient is gone");
  r.ok(!("PER_ALIVE_PILE" in Economy.COIN_CONFIG), "alive-piles×2 coefficient is gone");

  // No coins on a loss.
  r.eq(Economy.computeRunPayout({ won: false, aliveCount: 9, minAliveCards: 4, extraCoinCards: 3 }), 0,
    "loss pays 0 coins");

  // Win = aliveCount × minAliveCards + extraCoinCards × EXTRA_COIN_VALUE.
  const stats = { won: true, aliveCount: 5, minAliveCards: 4, extraCoinCards: 3 };
  r.eq(Economy.computeRunPayout(stats), 5 * 4 + 3 * EXTRA_COIN_VALUE,
    "win pays product + Extra Coin bonus (5×4 + 3 = 23)");

  // Itemized breakdown matches the structure shown on the run-complete screen.
  const bd = Economy.breakdown(stats);
  r.eq(bd.alivePiles, 5, "breakdown alive-pile count");
  r.eq(bd.minPileCards, 4, "breakdown smallest-alive-pile card count");
  r.eq(bd.product, 20, "breakdown product (5 × 4)");
  r.eq(bd.extraCoinCards, 3, "breakdown Extra Coin card count");
  r.eq(bd.extraCoinBonus, 3 * EXTRA_COIN_VALUE, "breakdown Extra Coin bonus");
  r.eq(bd.total, 23, "breakdown total = product + Extra Coin bonus");
  r.eq(bd.total, Economy.computeRunPayout(stats), "breakdown total matches computeRunPayout");
  r.ok(!("winBonus" in bd) && !("alivePileCoins" in bd), "breakdown drops the old win/alive-coef terms");

  // Edge guard: 0 alive piles -> product 0 (not NaN), even with stickers.
  const none = Economy.breakdown({ won: true, aliveCount: 0, minAliveCards: 6, extraCoinCards: 2 });
  r.eq(none.product, 0, "0 alive piles -> product 0");
  r.ok(!Number.isNaN(none.total), "0 alive piles -> total is a number (not NaN)");
  r.eq(none.total, 2 * EXTRA_COIN_VALUE, "0 alive piles -> total is just the Extra Coin bonus");

  // Missing minAliveCards is treated as 0 (no NaN leak).
  const noMin = Economy.breakdown({ won: true, aliveCount: 4, extraCoinCards: 0 });
  r.eq(noMin.total, 0, "missing minAliveCards -> product 0");

  const lost = Economy.breakdown({ won: false, aliveCount: 9, minAliveCards: 4, extraCoinCards: 5 });
  r.eq(lost.total, 0, "breakdown on a loss totals 0");
  r.eq(lost.extraCoinBonus, 0, "no Extra Coin bonus on a loss");

  // --- BoardState.minAliveCards (the payout multiplier) -------------------
  {
    const b = BoardState.create(3);
    b.push(0, {}); b.push(0, {}); b.push(0, {});   // pile 0: 3 cards
    b.push(1, {}); b.push(1, {});                  // pile 1: 2 cards (alive minimum)
    b.push(2, {});                                 // pile 2: 1 card, but DEAD
    b.kill(2);
    r.eq(b.minAliveCards(), 2, "minAliveCards ignores the dead 1-card pile -> 2");
    // A full end-to-end: 2 alive piles × 2 smallest = 4, no stickers.
    const e2e = Economy.breakdown({ won: true, aliveCount: b.aliveCount(),
      minAliveCards: b.minAliveCards(), extraCoinCards: b.aliveTopStickerCount("extraCoin") });
    r.eq(e2e.total, 2 * 2, "end-to-end product from a real board (2 × 2 = 4)");
  }
  {
    const dead = BoardState.create(2);
    dead.push(0, {}); dead.push(1, {}); dead.kill(0); dead.kill(1);
    r.eq(dead.minAliveCards(), 0, "no alive piles -> minAliveCards 0");
  }

  // --- BoardState.aliveTopStickerCount -----------------------------------
  const EC = { stickers: [{ type: "extraCoin" }] };
  const PLAIN = { stickers: [] };
  const b = BoardState.create(4);
  b.push(0, { ...EC });                          // pile 0: extraCoin on top -> counts
  b.push(1, { ...PLAIN }); b.push(1, { ...EC });  // pile 1: extraCoin on top -> counts
  b.push(2, { ...EC }); b.kill(2);                // pile 2: extraCoin top but DEAD -> excluded
  b.push(3, { ...EC }); b.push(3, { ...PLAIN });  // pile 3: extraCoin buried, plain on top -> excluded
  r.eq(b.aliveTopStickerCount("extraCoin"), 2,
    "counts only alive piles whose TOP card carries the sticker");

  // Stacked Extra Coin on a single alive top: N stickers -> +N (no cap).
  const b2 = BoardState.create(2);
  b2.push(0, { stickers: [{ type: "extraCoin" }, { type: "extraCoin" }, { type: "extraCoin" }] });
  b2.push(1, { stickers: [{ type: "extraCoin" }] });
  r.eq(b2.aliveTopStickerCount("extraCoin"), 4,
    "sums stacked Extra Coin across tops (3 + 1 = 4)");

  // Extra Coin bonus stays additive on top of the product: N tops -> +N, and
  // the run total = product + N (each card its OWN stickers array). 2 and 3.
  [2, 3].forEach(n => {
    const piles = n + 2;                       // plus a couple of plain piles
    const bb = BoardState.create(piles);
    for (let i = 0; i < piles; i++) {
      bb.push(i, { stickers: i < n ? [{ type: "extraCoin" }] : [] });  // 1 card each
    }
    r.eq(bb.aliveTopStickerCount("extraCoin"), n,
      n + " separate alive Extra-Coin tops are each counted (not collapsed)");
    const bd2 = Economy.breakdown({ won: true, aliveCount: bb.aliveCount(),
      minAliveCards: bb.minAliveCards(), extraCoinCards: n });
    r.eq(bd2.extraCoinBonus, n * EXTRA_COIN_VALUE, n + " Extra-Coin tops -> +" + n + " bonus");
    r.eq(bd2.total, bb.aliveCount() * bb.minAliveCards() + n * EXTRA_COIN_VALUE,
      "run total = product + full Extra-Coin bonus for " + n + " cards");
  });

  return r.summary();
}
