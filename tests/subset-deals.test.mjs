// Subset deals: the PURE numeric contract exposed on RunMap — difficulty score
// bucketing, pile solving from a rolled survive count, and the generator storing
// a target danger (targetD) on every deal/boss node so the 1-3 score is stable.
// (The DOM wiring — drawing the actual subset, hiding it in the histogram, and
//  persisting it for resume — lives in the UI layer and is covered by E2E.)
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { RunMap, DifficultyData } = loadGame();
  const r = makeRunner("subset-deals.test.mjs");
  const C = RunMap.GEN_CONFIG;
  const S = RunMap.SUBSET;

  // --- config shape: the knobs live in difficulty.js -------------------
  {
    const D = DifficultyData.subset;
    r.eq(S, D, "RunMap.SUBSET is difficulty.js's subset block (single source)");
    r.ok(D.threshold > 0 && D.min > 0 && D.max >= D.min,
      "subset knobs are sane (threshold/min/max positive, min ≤ max — currently "
      + D.threshold + "/" + D.min + "/" + D.max + ")");
    r.eq(S.scoreT1, undefined, "no fixed global score thresholds (now stage-relative)");
  }

  // --- difficultyScore is STAGE-RELATIVE: each stage's own band → thirds ----
  {
    // No stage context → neutral 2 (never a fixed global scale).
    r.eq(RunMap.difficultyScore(4.0), 2, "no phase arg → neutral 2");
    r.eq(RunMap.difficultyScore(0, 0), 2, "invalid target → neutral 2");
    // For every base stage, the band [lo,hi] splits at lo+span/3 and lo+2span/3;
    // a D in the low/mid/high third buckets to 1/2/3 RELATIVE to that stage.
    for (let phase = 0; phase <= 2; phase++) {
      const tiers = RunMap.difficultyTiers(phase, false);
      const [lo, hi] = tiers.band, span = hi - lo;
      r.eq(RunMap.difficultyScore(lo + span * 0.01, phase), 1, "stage " + phase + ": bottom of band → 1");
      r.eq(RunMap.difficultyScore(lo + span * 0.5, phase), 2, "stage " + phase + ": middle of band → 2");
      r.eq(RunMap.difficultyScore(hi - span * 0.01, phase), 3, "stage " + phase + ": top of band → 3");
      r.eq(RunMap.difficultyScore(tiers.t1 - 1e-6, phase), 1, "stage " + phase + ": just below t1 → 1");
      r.eq(RunMap.difficultyScore(tiers.t1, phase), 2, "stage " + phase + ": at t1 → 2");
      r.eq(RunMap.difficultyScore(tiers.t2, phase), 3, "stage " + phase + ": at t2 → 3");
    }
    // The SAME absolute danger scores DIFFERENTLY per stage — a mid-stage-2
    // danger reads as HARD (3) in the easier stage 0 but EASY (1) in stage 2.
    const midStage1 = (RunMap.difficultyTiers(1, false).band[0] + RunMap.difficultyTiers(1, false).band[1]) / 2;
    const s0 = RunMap.difficultyScore(midStage1, 0);
    const s2 = RunMap.difficultyScore(midStage1, 2);
    r.ok(s0 > s2, "the same danger scores higher in an easier stage (" + s0 + " @stage0 > " + s2 + " @stage2)");
    // bands ascend across stages, so a "3" means a harder deal each stage.
    const t = [0, 1, 2].map(ph => RunMap.difficultyTiers(ph, false).t2);
    r.ok(t[0] < t[1] && t[1] < t[2], "the '3' threshold rises stage to stage (" + t.map(x => x.toFixed(2)).join(" < ") + ")");
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
    let deals = 0, bosses = 0, missing = 0, outOfRange = 0;
    const perStageScores = { 0: new Set(), 1: new Set(), 2: new Set() };
    for (let phase = 0; phase <= 2; phase++) {
      const entry = [20, 40, 55][phase];
      const ph = RunMap.generateStage(phase, 12345 + phase, entry);
      for (const n of ph.nodes) {
        if (n.type !== "deal" && n.type !== "boss") continue;
        if (n.type === "boss") bosses++; else deals++;
        if (!(typeof n.targetD === "number" && n.targetD > 0)) { missing++; continue; }
        const isBoss = n.type === "boss";
        const sc = RunMap.difficultyScore(n.targetD, phase, isBoss);   // generateStage nodes carry no .phase; pass the known one
        if (sc < 1 || sc > 3) outOfRange++;
        if (!isBoss && perStageScores[phase]) perStageScores[phase].add(sc);
      }
    }
    r.ok(deals > 0 && bosses > 0, "stages produced deal + boss nodes (" + deals + " deals, " + bosses + " bosses)");
    r.eq(missing, 0, "every deal/boss node carries a positive targetD");
    r.eq(outOfRange, 0, "every node score falls in 1..3");
    // Within a SINGLE stage the deals should span more than one tier (the point:
    // it shows which deals are hardest among that stage's own choices).
    const spread = [0, 1, 2].filter(ph => perStageScores[ph].size >= 2).length;
    r.ok(spread >= 1, "at least one stage's deals span multiple relative tiers "
      + "(sizes " + [0,1,2].map(ph => perStageScores[ph].size).join("/") + ")");
  }

  return r.summary();
}
