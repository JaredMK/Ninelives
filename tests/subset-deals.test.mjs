// Subset deals: the PURE numeric contract exposed on RunMap — difficulty score
// bucketing, pile solving from a rolled survive count, and the generator storing
// a target danger (targetD) on every deal/boss node so the 1-3 score is stable.
// (The DOM wiring — drawing the actual subset, hiding it in the histogram, and
//  persisting it for resume — lives in the UI layer and is covered by E2E.)
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { RunMap } = loadGame();
  const r = makeRunner("subset-deals.test.mjs");
  const C = RunMap.GEN_CONFIG;
  const S = RunMap.SUBSET;

  // --- config shape -----------------------------------------------------
  {
    r.eq(S.threshold, 35, "subset kicks in past a 35-card deck");
    r.eq(S.min, 15, "survive subset floor is 15");
    r.eq(S.max, 35, "survive subset ceiling is 35");
    r.ok(S.scoreT1 < S.scoreT2, "score thresholds ascend (T1 < T2)");
  }

  // --- difficultyScore buckets a target danger into 1 | 2 | 3 -----------
  {
    r.eq(RunMap.difficultyScore(1.5), 1, "D 1.5 → score 1 (easy)");
    r.eq(RunMap.difficultyScore(S.scoreT1 - 0.01), 1, "just below T1 → 1");
    r.eq(RunMap.difficultyScore(S.scoreT1), 2, "at T1 → 2 (medium)");
    r.eq(RunMap.difficultyScore(4.0), 2, "D 4.0 → score 2");
    r.eq(RunMap.difficultyScore(S.scoreT2 - 0.01), 2, "just below T2 → 2");
    r.eq(RunMap.difficultyScore(S.scoreT2), 3, "at T2 → 3 (hard)");
    r.eq(RunMap.difficultyScore(6.0), 3, "D 6.0 → score 3");
    r.eq(RunMap.difficultyScore(0), 2, "no/invalid target → neutral 2");
  }

  // --- solveSubsetPiles: piles = nearest(S / D), clamped to board range --
  {
    // D = survive/piles → piles = survive/D. 30 survive at D=3 → 10 piles.
    r.eq(RunMap.solveSubsetPiles(30, 3), 10, "30 survive @ D3 → 10 piles");
    r.eq(RunMap.solveSubsetPiles(24, 4), 6, "24 survive @ D4 → 6 piles");
    r.eq(RunMap.solveSubsetPiles(15, 5), 3, "15 survive @ D5 → 3 piles");
    // clamps to the board's [minPiles, maxPiles].
    r.eq(RunMap.solveSubsetPiles(35, 1.5), C.maxPiles, "very easy target clamps to maxPiles");
    r.eq(RunMap.solveSubsetPiles(15, 9), C.minPiles, "very hard target clamps to minPiles");
    // realized danger lands NEAR the target across the whole roll range.
    let worst = 0;
    for (let surv = S.min; surv <= S.max; surv++) {
      for (const D of [2.0, 3.0, 4.0, 5.0]) {
        const p = RunMap.solveSubsetPiles(surv, D);
        r.ok(p >= C.minPiles && p <= C.maxPiles, "piles in board range (" + surv + "," + D + " → " + p + ")");
        const realized = surv / p;
        // only measure drift when the clamp did NOT bind (unclamped solves should be tight)
        const unclamped = Math.max(C.minPiles, Math.min(C.maxPiles, Math.round(surv / D)));
        if (unclamped > C.minPiles && unclamped < C.maxPiles) worst = Math.max(worst, Math.abs(realized - D) / D);
      }
    }
    r.ok(worst < 0.20, "unclamped realized danger stays within 20% of target (worst " + worst.toFixed(3) + ")");
  }

  // --- the generator stamps targetD on EVERY deal + boss node -----------
  // Generate stages at a big entry deck (subset territory) and assert every
  // deal/boss carries a positive targetD that buckets to a sane 1-3 score.
  {
    let deals = 0, bosses = 0, missing = 0;
    const scores = new Set();
    for (let phase = 0; phase <= 2; phase++) {
      const entry = [20, 40, 55][phase];
      const ph = RunMap.generateStage(phase, 12345 + phase, entry);
      for (const n of ph.nodes) {
        if (n.type !== "deal" && n.type !== "boss") continue;
        if (n.type === "boss") bosses++; else deals++;
        if (!(typeof n.targetD === "number" && n.targetD > 0)) { missing++; continue; }
        scores.add(RunMap.difficultyScore(n.targetD));
      }
    }
    r.ok(deals > 0 && bosses > 0, "stages produced deal + boss nodes (" + deals + " deals, " + bosses + " bosses)");
    r.eq(missing, 0, "every deal/boss node carries a positive targetD");
    r.ok([...scores].every(s => s >= 1 && s <= 3), "all node scores fall in 1..3");
    r.ok(scores.size >= 2, "difficulty scores vary across the run (got " + [...scores].sort().join(",") + ")");
  }

  return r.summary();
}
