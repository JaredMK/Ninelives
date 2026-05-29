// Coin payout: win bonus + alive piles × 2 + Extra Coin bonus. (The old
// smallest-alive-pile term has been removed.) Plus the board helper that
// counts alive top cards carrying the Extra Coin sticker.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { Economy, BoardState } = loadGame();
  const r = makeRunner("economy.test.mjs");
  const { WIN_BONUS, PER_ALIVE_PILE, EXTRA_COIN_VALUE } = Economy.COIN_CONFIG;

  r.ok(!("PER_MIN_ALIVE_PILE" in Economy.COIN_CONFIG), "smallest-pile coefficient is gone");

  // No coins on a loss.
  r.eq(Economy.computeRunPayout({ won: false, aliveCount: 9, extraCoinCards: 3 }), 0,
    "loss pays 0 coins");

  // Win = WIN_BONUS + alive*PER_ALIVE_PILE + extraCoinCards*EXTRA_COIN_VALUE.
  const stats = { won: true, aliveCount: 8, extraCoinCards: 3 };
  r.eq(Economy.computeRunPayout(stats),
    WIN_BONUS + 8 * PER_ALIVE_PILE + 3 * EXTRA_COIN_VALUE,
    "win pays bonus + alive*coef + extraCoin*coef");

  // Itemized breakdown matches; total === computeRunPayout.
  const bd = Economy.breakdown(stats);
  r.eq(bd.winBonus, WIN_BONUS, "breakdown win bonus");
  r.eq(bd.alivePiles, 8, "breakdown alive-pile count");
  r.eq(bd.alivePileCoins, 8 * PER_ALIVE_PILE, "breakdown alive-pile coins");
  r.eq(bd.extraCoinCards, 3, "breakdown Extra Coin card count");
  r.eq(bd.extraCoinBonus, 3 * EXTRA_COIN_VALUE, "breakdown Extra Coin bonus");
  r.eq(bd.total, Economy.computeRunPayout(stats), "breakdown total matches computeRunPayout");
  r.ok(!("minPileCoins" in bd) && !("minCards" in bd), "breakdown no longer reports a smallest-pile term");

  const lost = Economy.breakdown({ won: false, aliveCount: 9, extraCoinCards: 5 });
  r.eq(lost.total, 0, "breakdown on a loss totals 0");
  r.eq(lost.extraCoinBonus, 0, "no Extra Coin bonus on a loss");

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

  return r.summary();
}
