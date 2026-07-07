// Difficulty tiers (difficulty.js): per-tier bands read live by the generator,
// endless lift from the selected tier's stage-3 bands, campaign persistence,
// and generation feasibility on the hardest tier. Deck-select unlock gating is
// browser-verified (localStorage), not unit-tested here.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const r = makeRunner("difficulty.test.mjs");

  // ---- data: Regular is the legacy baseline; Legendary bosses as derived ---
  {
    const { RunMap } = loadGame();
    r.eq(RunMap.getDifficultyTier(), "regular", "the generator defaults to Regular");
    const reg = RunMap.bandsFor(0);
    r.eq(JSON.stringify([reg.stage, reg.boss]), JSON.stringify([[1.5, 3.0], [2.3, 3.0]]),
      "Regular stage 1 = the legacy band values");
    r.eq(JSON.stringify(RunMap.bandsFor(2).boss), JSON.stringify([5.5, 6.0]), "Regular ♠ boss = 5.5–6.0 (legacy)");
  }

  // ---- bandsFor follows the selected tier -----------------------------------
  {
    const { RunMap } = loadGame();
    RunMap.setDifficultyTier("master");
    r.eq(RunMap.getDifficultyTier(), "master", "tier selects");
    r.eq(JSON.stringify(RunMap.bandsFor(0).boss), JSON.stringify([3.3, 4.0]), "Master boss 1 = 3.3–4.0");
    r.eq(JSON.stringify(RunMap.bandsFor(2).stage), JSON.stringify([5.0, 6.5]), "Master stage 3 = 5.0–6.5");
    RunMap.setDifficultyTier("legendary");
    r.eq(JSON.stringify(RunMap.bandsFor(1).stage), JSON.stringify([4.0, 6.0]), "Legendary stage 2 = 4.0–6.0");
    r.eq(JSON.stringify(RunMap.bandsFor(0).boss), JSON.stringify([4.3, 5.0]), "Legendary boss 1 = 4.3–5.0 (derived)");
    r.eq(JSON.stringify(RunMap.bandsFor(2).boss), JSON.stringify([7.5, 8.0]), "Legendary boss 3 = 7.5–8.0 (derived)");
    RunMap.setDifficultyTier("nonsense");
    r.eq(RunMap.getDifficultyTier(), "regular", "an unknown tier falls back to Regular");
  }

  // ---- endless: +step per stage FROM THE SELECTED TIER's stage-3 bands ------
  {
    const { RunMap } = loadGame();
    RunMap.setDifficultyTier("legendary");
    const b3 = RunMap.bandsFor(2), b4 = RunMap.bandsFor(3), b5 = RunMap.bandsFor(4);
    const step = b4.stage[0] - b3.stage[0];
    r.ok(Math.abs(step - 1.25) < 1e-9, "endless lift per stage = endlessBandStep (1.25) from difficulty.js");
    r.ok(Math.abs(b4.boss[1] - (b3.boss[1] + step)) < 1e-9, "boss band lifts by the same step");
    r.ok(Math.abs((b5.stage[0] - b4.stage[0]) - step) < 1e-9, "…and keeps rising per endless stage");
    r.eq(JSON.stringify(b4.stage.map(x => +x.toFixed(2))), JSON.stringify([6.75, 8.75]),
      "Legendary endless-1 deals band = stage-3 (5.5–7.5) + 1.25");
  }

  // ---- generation stays FEASIBLE on the hardest tier ------------------------
  {
    const { RunMap } = loadGame();
    RunMap.setDifficultyTier("legendary");
    const run3 = RunMap.generateRun(1234567, [13, 26, 39]);
    r.eq((run3.phases || []).length, 3, "Legendary generates all 3 stages (seed 1234567)");
    const run3b = RunMap.generateRun(987654, [13, 26, 39]);
    r.eq((run3b.phases || []).length, 3, "…and on a second seed");
  }

  // ---- campaign: tier persists with the save, bands follow on restore -------
  {
    const { CampaignState, RunMap } = loadGame();
    const camp = CampaignState.create();
    r.eq(camp.getTier(), "regular", "a fresh campaign is Regular");
    camp.setTier("master"); camp.reset();
    r.eq(RunMap.getDifficultyTier(), "master", "reset() generated the map on the campaign's tier");
    const snap = camp.serialize();
    r.eq(snap.difficultyTier, "master", "serialize() carries the tier");
    const camp2 = CampaignState.create();
    r.ok(camp2.restore(snap), "the save restores");
    r.eq(camp2.getTier(), "master", "…keeping the tier");
    r.eq(RunMap.getDifficultyTier(), "master", "…and the generator regenerated on it");
    const legacy = camp.serialize(); delete legacy.difficultyTier;
    const camp3 = CampaignState.create();
    camp3.restore(legacy);
    r.eq(camp3.getTier(), "regular", "a pre-tier save restores as Regular");
  }

  // ---- tier affects BANDS ONLY: prices identical across tiers --------------
  {
    const { CampaignState } = loadGame();
    const camp = CampaignState.create();
    const at = (tier) => { camp.setTier(tier); camp.reset();
      return [camp.priceOf("gainCoin"), camp.priceOfPack("cardPack"), camp.removalPrice()].join(","); };
    const reg = at("regular");
    r.eq(at("master"), reg, "Master prices = Regular prices");
    r.eq(at("legendary"), reg, "Legendary prices = Regular prices");
  }

  return r.summary();
}
