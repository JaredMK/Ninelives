// Coin payout (ECON1): a cleared deal pays a FLAT base by stage & difficulty
//     dealBase + stage × (1 + rating)     (items.js `economy` section)
// (a boss forces rating 3 and adds bossBonus) PLUS the item-driven bonuses
// (Extra Coin units × the Payout sticker's `value`, pillar payouts, the live
// in-run event tally). The old piles × smallest product survives as the deal
// SCORE (breakdown still reports it) but no longer feeds the coin total.
// Ambush/subset deals carry no stage/rating → no flat base (the bounty is the
// reward); a flagged AMBUSH additionally scores 0 (v5.63 — coins only). All
// expectations below derive from the items.js knobs — a data retune must not
// break this suite.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadGame, makeRunner } from "./_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const ITEMS_SRC = readFileSync(join(HERE, "..", "items.js"), "utf8");

export function run() {
  const { Economy, BoardState, ItemData } = loadGame();
  const r = makeRunner("economy.test.mjs");
  const { EXTRA_COIN_VALUE } = Economy.COIN_CONFIG;
  const BASE = ItemData.economy.dealBase;
  const BOSS = ItemData.economy.bossBonus;
  const CAP = ItemData.economy.stageCap;
  // ENDLESS FREEZE (v6.78): the stage term caps at stageCap (phase 3).
  const flat = (stage, rating) => BASE + Math.min(stage, CAP) * (1 + rating);

  // Old coefficients are gone.
  r.ok(!("WIN_BONUS" in Economy.COIN_CONFIG), "flat win bonus coefficient is gone");
  r.ok(!("PER_ALIVE_PILE" in Economy.COIN_CONFIG), "alive-piles×2 coefficient is gone");

  // --- Validation: the economy section is required and fail-loud ----------
  {
    let threw = null;
    try { loadGame({ itemsSource: ITEMS_SRC.replace("economy: {", "economyGone: {") }); }
    catch (e) { threw = e; }
    r.ok(threw && /items\.js validation FAILED/.test(threw.message), "a missing economy section fails loudly at load");
  }
  {
    let threw = null;
    try { loadGame({ itemsSource: ITEMS_SRC.replace(/dealBase: \d+/, "dealBase: -1") }); }
    catch (e) { threw = e; }
    r.ok(threw && /items\.js validation FAILED/.test(threw.message), "a non-positive dealBase fails loudly at load");
  }
  {
    let threw = null;
    try { loadGame({ itemsSource: ITEMS_SRC.replace(/bossBonus: \d+/, 'bossBonus: "1"') }); }
    catch (e) { threw = e; }
    r.ok(threw && /items\.js validation FAILED/.test(threw.message), "a non-numeric bossBonus fails loudly at load");
  }

  // --- dealFlat: the flat table, read straight from the knobs -------------
  {
    r.eq(Economy.dealFlat(1, 1, false), flat(1, 1), "stage 1 easy = dealBase + 1×2 (the 3-coin anchor)");
    r.eq(Economy.dealFlat(1, 2, false), flat(1, 2), "stage 1 mid");
    r.eq(Economy.dealFlat(1, 3, false), flat(1, 3), "stage 1 hard");
    r.eq(Economy.dealFlat(2, 1, false), flat(2, 1), "stage 2 easy");
    r.eq(Economy.dealFlat(2, 3, false), flat(2, 3), "stage 2 hard");
    r.eq(Economy.dealFlat(3, 2, false), flat(3, 2), "stage 3 mid");
    // ENDLESS FREEZE (v6.78): past phase 3 the payout stops growing — every
    // endless stage pays exactly the phase-3 rate for its difficulty.
    r.eq(Economy.dealFlat(4, 1, false), Economy.dealFlat(3, 1, false), "endless stage 4 pays phase-3 rates");
    r.eq(Economy.dealFlat(5, 3, false), Economy.dealFlat(3, 3, false), "endless stage 5 pays phase-3 rates");
    r.eq(Economy.dealFlat(40, 2, false), Economy.dealFlat(3, 2, false), "…forever");
    // Boss: rating forced 3 (whatever is passed) + bossBonus.
    r.eq(Economy.dealFlat(1, 1, true), flat(1, 3) + BOSS, "boss forces rating 3 (passed rating ignored) + bossBonus");
    r.eq(Economy.dealFlat(3, 3, true), flat(3, 3) + BOSS, "stage 3 boss");
    r.eq(Economy.dealFlat(4, 2, true), Economy.dealFlat(3, 2, true), "endless bosses freeze too");
    // Ambush / no stage context / no rating → no flat base.
    r.eq(Economy.dealFlat(0, 2, false), 0, "no stage → 0 (ambush/subset)");
    r.eq(Economy.dealFlat(2, 0, false), 0, "no rating → 0 (node without a difficulty)");
    r.eq(Economy.dealFlat(2, undefined, false), 0, "missing rating → 0");
  }

  // No coins on a loss.
  r.eq(Economy.computeRunPayout({ won: false, flat: 9, aliveCount: 9, minAliveCards: 4, extraCoinUnits: 3 }), 0,
    "loss pays 0 coins");

  // Win = flat + extraCoinUnits × EXTRA_COIN_VALUE (product NOT in the total).
  const stats = { won: true, flat: Economy.dealFlat(2, 2, false), stage: 2, rating: 2,
    aliveCount: 5, minAliveCards: 4, extraCoinUnits: 12 };
  r.eq(Economy.computeRunPayout(stats), flat(2, 2) + 12 * EXTRA_COIN_VALUE,
    "win pays flat + Extra Coin bonus (product excluded)");

  // Itemized breakdown matches the run-complete structure.
  const bd = Economy.breakdown(stats);
  r.eq(bd.flat, flat(2, 2), "breakdown flat base");
  r.eq(bd.stage, 2, "breakdown stage carried through");
  r.eq(bd.rating, 2, "breakdown rating carried through");
  r.eq(bd.alivePiles, 5, "breakdown alive-pile count");
  r.eq(bd.minPileCards, 4, "breakdown smallest-alive-pile card count");
  r.eq(bd.product, 20, "breakdown product (5 × 4) — the SCORE, still reported");
  r.eq(bd.extraCoinUnits, 12, "breakdown Extra Coin units");
  r.eq(bd.extraCoinBonus, 12 * EXTRA_COIN_VALUE, "breakdown Extra Coin bonus");
  r.eq(bd.total, flat(2, 2) + 12 * EXTRA_COIN_VALUE, "breakdown total = flat + Extra Coin bonus");
  r.eq(bd.total, Economy.computeRunPayout(stats), "breakdown total matches computeRunPayout");
  r.ok(!("extraCoinCards" in bd), "breakdown no longer reports the old per-card count");

  // The product no longer feeds the total: same flat, wildly different
  // products → identical totals.
  {
    const big = Economy.breakdown({ won: true, flat: 7, aliveCount: 6, minAliveCards: 9 });
    const small = Economy.breakdown({ won: true, flat: 7, aliveCount: 1, minAliveCards: 1 });
    r.eq(big.total, small.total, "product no longer feeds the coin total (score only)");
    r.ok(big.product > small.product, "…while the products themselves still differ (score)");
    r.eq(big.total, 7, "a bare win pays exactly the flat base");
  }

  // Edge guard: 0 alive piles -> product 0 (not NaN), even with stickers.
  const none = Economy.breakdown({ won: true, flat: 3, aliveCount: 0, minAliveCards: 6, extraCoinUnits: 2 });
  r.eq(none.product, 0, "0 alive piles -> product 0");
  r.ok(!Number.isNaN(none.total), "0 alive piles -> total is a number (not NaN)");
  r.eq(none.total, 3 + 2 * EXTRA_COIN_VALUE, "0 alive piles -> total is flat + Extra Coin bonus");

  // Missing fields default to 0 (no NaN leak) — ambush shape: no flat, just
  // the bounty riding the event tally.
  const noMin = Economy.breakdown({ won: true, aliveCount: 4, extraCoinUnits: 0 });
  r.eq(noMin.flat, 0, "missing flat -> 0 (ambush zero-base)");
  r.eq(noMin.total, 0, "missing flat + no bonuses -> total 0");
  const ambush = Economy.breakdown({ won: true, aliveCount: 4, minAliveCards: 2,
    eventBonus: ItemData.mystery.ambush.bounty, eventLines: [{ label: "Ambush", amount: ItemData.mystery.ambush.bounty }] });
  r.eq(ambush.total, ItemData.mystery.ambush.bounty, "ambush win pays exactly the bounty (no flat base)");
  // NOTE: this shape only omits the flat base — it does NOT carry the v5.63
  // `ambush: true` flag, so it still scores. The real ambush path (which the
  // payout site flags) is covered in the AMBUSH block above.
  r.eq(ambush.product, 8, "…a no-flat-base shape alone still scores (the FLAG is what zeroes it)");

  const lost = Economy.breakdown({ won: false, flat: 9, aliveCount: 9, minAliveCards: 4, extraCoinUnits: 5 });
  r.eq(lost.total, 0, "breakdown on a loss totals 0");
  r.eq(lost.flat, 0, "no flat base on a loss");
  r.eq(lost.extraCoinBonus, 0, "no Extra Coin bonus on a loss");

  // Negative clamp: a Tribute cost can drag the bonus below zero; the total
  // clamps at 0 (a win never charges the player).
  const neg = Economy.breakdown({ won: true, flat: 2, aliveCount: 1, minAliveCards: 1, eventBonus: -5 });
  r.eq(neg.total, 0, "a Tribute cost can't push the total below 0");
  const negPart = Economy.breakdown({ won: true, flat: 5, eventBonus: -3 });
  r.eq(negPart.total, 2, "a smaller Tribute cost just eats into the flat base");

  // Interest (the +1/10-coins-held payout) has been REMOVED — passing a stray
  // interest stat must NOT affect the total any more.
  const noInterest = Economy.breakdown({ won: true, flat: 4, aliveCount: 2, minAliveCards: 1, interest: 4 });
  r.eq(noInterest.interest, undefined, "interest is no longer itemized on the breakdown");
  r.eq(noInterest.total, 4, "total ignores any interest stat (flat only)");

  // --- BoardState.minAliveCards (dead piles excluded) --------------------
  {
    const b = BoardState.create(3);
    b.push(0, {}); b.push(0, {}); b.push(0, {});   // pile 0: 3 cards
    b.push(1, {}); b.push(1, {});                  // pile 1: 2 cards (alive minimum)
    b.push(2, {});                                 // pile 2: 1 card, but DEAD
    b.kill(2);
    r.eq(b.minAliveCards(), 2, "minAliveCards ignores the dead 1-card pile -> 2");
    const e2e = Economy.breakdown({ won: true, flat: 6, aliveCount: b.aliveCount(),
      minAliveCards: b.minAliveCards(), extraCoinUnits: b.extraCoinUnits() });
    r.eq(e2e.product, 2 * 2, "end-to-end product (score) from a real board (2 × 2 = 4)");
    r.eq(e2e.total, 6, "end-to-end total is the flat base alone (no stickers)");
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
    const b2 = BoardState.create(3);
    b2.push(0, {}); b2.push(0, ANCHOR());          // pile 0: 2 cards, anchor on TOP
    b2.push(1, {}); b2.push(1, {}); b2.push(1, {}); b2.push(1, {}); b2.push(1, {}); // pile 1: 5
    b2.push(2, {}); b2.push(2, {}); b2.push(2, {}); b2.push(2, {});                  // pile 2: 4
    r.ok(b2.isAnchored(0), "pile 0 top carries Anchor -> anchored");
    r.ok(!b2.isAnchored(1), "pile 1 has no Anchor");
    r.eq(b2.trueMinAliveCards(), 2, "trueMin counts the anchored 2-card pile");
    r.eq(b2.minAliveCards(), 4, "score min EXCLUDES the anchored pile -> 4 (pile 2)");
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
    // score: min non-anchored = 4 (pile 1); alive = 3; product = 12
    // coins: flat + extraCoin 4 × value
    const bd2 = Economy.breakdown({ won: true, flat: 5, aliveCount: b.aliveCount(),
      minAliveCards: b.minAliveCards(), extraCoinUnits: b.extraCoinUnits() });
    r.eq(b.minAliveCards(), 4, "e2e: anchored pile excluded -> min 4");
    r.eq(b.extraCoinUnits(), 4, "e2e: Extra Coin on a 4-card pile -> 4 units");
    r.eq(bd2.product, 12, "e2e: product (score) = 3×4 = 12");
    r.eq(bd2.total, 5 + 4 * EXTRA_COIN_VALUE, "e2e: total = flat + Extra Coin (product excluded)");
  }

  // ── AMBUSH: no flat base, but it SCORES like any battle (v5.82) ────────
  {
    const stats = { won: true, flat: 0, aliveCount: 4, minAliveCards: 3,
      extraCoinUnits: 0, eventBonus: 25 };
    const normal = Economy.breakdown(stats);
    r.eq(normal.product, 12, "a normal clear scores piles x smallest (4x3)");
    const amb = Economy.breakdown({ ...stats, ambush: true });
    r.eq(amb.product, 12, "an AMBUSH scores the same 4x3 — every battle counts");
    r.eq(amb.total, normal.total, "…while its COINS are unchanged (bounty still paid)");
    r.eq(amb.alivePiles, normal.alivePiles, "…the factors still report (UI reads them)");
    r.eq(amb.minPileCards, normal.minPileCards, "…both of them");
  }

  // ── Economy.liveBonus — the above-board "base + bonus" live readout ──
  // Must agree with breakdown(): liveBonus(stats) === total − flat for the
  // same inputs whenever the clamp doesn't fire (the UI/summary reconciliation
  // invariant), reading the SAME EXTRA_COIN_VALUE knob.
  {
    const cases = [
      { liveBonusCoins: 0, pillarBonus: 0, extraCoinUnits: 0 },
      { liveBonusCoins: 3, pillarBonus: 2, extraCoinUnits: 4 },
      { liveBonusCoins: 7, pillarBonus: 0, extraCoinUnits: 1 },
    ];
    for (const c of cases) {
      const lb = Economy.liveBonus(c);
      const bd = Economy.breakdown({ won: true, flat: 5, aliveCount: 3, minAliveCards: 4,
        extraCoinUnits: c.extraCoinUnits, pillarBonus: c.pillarBonus, eventBonus: c.liveBonusCoins });
      r.eq(lb, bd.total - 5, "liveBonus === breakdown total − flat (live " +
        c.liveBonusCoins + " / pillars " + c.pillarBonus + " / extra " + c.extraCoinUnits + ")");
    }
    // A Tribute-dragged tally passes through signed (the UI shows it red);
    // breakdown clamps its TOTAL at 0 — the two only diverge under the clamp.
    r.eq(Economy.liveBonus({ liveBonusCoins: -4, pillarBonus: 0, extraCoinUnits: 0 }), -4,
      "liveBonus passes a negative live tally through signed");
    r.eq(Economy.liveBonus({}), 0, "liveBonus of empty stats is 0 (never NaN)");
  }

  return r.summary();
}
