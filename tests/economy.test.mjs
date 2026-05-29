// Phase 1: coin payout formula + board helpers.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { Economy, BoardState } = loadGame();
  const r = makeRunner("economy.test.mjs");
  const { WIN_BONUS, PER_MIN_ALIVE_PILE, PER_ALIVE_PILE } = Economy.COIN_CONFIG;

  // No coins on a loss.
  r.eq(Economy.computeRunPayout({ won: false, aliveCount: 9, minAlivePileCards: 4 }), 0,
    "loss pays 0 coins");

  // Win formula: WIN_BONUS + min*PER_MIN + alive*PER_ALIVE.
  r.eq(
    Economy.computeRunPayout({ won: true, aliveCount: 9, minAlivePileCards: 3 }),
    WIN_BONUS + 3 * PER_MIN_ALIVE_PILE + 9 * PER_ALIVE_PILE,
    "win pays bonus + min*coef + alive*coef"
  );

  // Win with zero alive piles (deck emptied as the last pile died): min term
  // must contribute 0 even if minAlivePileCards is Infinity/garbage.
  r.eq(Economy.computeRunPayout({ won: true, aliveCount: 0, minAlivePileCards: Infinity }),
    WIN_BONUS, "win with 0 alive piles pays only the win bonus");

  // BoardState per-pile helpers.
  const b = BoardState.create(4);
  b.push(0, {}); b.push(0, {});            // pile 0: 2 cards
  b.push(1, {});                           // pile 1: 1 card
  b.push(2, {}); b.push(2, {}); b.push(2, {}); // pile 2: 3 cards
  b.push(3, {}); b.kill(3);                // pile 3: dead
  r.eq(JSON.stringify(b.aliveCardCounts()), JSON.stringify([2, 1, 3]),
    "aliveCardCounts ignores dead piles");
  r.eq(b.minAliveCards(), 1, "minAliveCards is the smallest alive pile");
  r.eq(b.aliveCount(), 3, "aliveCount excludes the dead pile");

  return r.summary();
}
