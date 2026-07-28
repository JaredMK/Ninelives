// Difficulty tiers (difficulty.js): per-tier bands read live by the generator,
// endless lift from the selected tier's stage-3 bands, campaign persistence,
// and generation feasibility on the hardest tier. Deck-select unlock gating is
// browser-verified (localStorage), not unit-tested here.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadGame, makeRunner } from "./_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const DIFFICULTY = join(HERE, "..", "difficulty.js");

/** A difficulty.js source with the live data mutated (validation probes — the
    same pattern as tests/zen1.test.mjs). */
function difficultySourceWith(mutate) {
  const d = JSON.parse(JSON.stringify(
    new Function(readFileSync(DIFFICULTY, "utf8") + "\n;return NINELIVES_DIFFICULTY;")()));
  mutate(d);
  return '"use strict";\nconst NINELIVES_DIFFICULTY = ' + JSON.stringify(d) + ";";
}
/** Load the game against a mutated difficulty.js, capturing the thrown error
    and every console.error line (the fail-loud naming contract). */
function loadExpectingFailure(mutate) {
  const errs = [];
  const orig = console.error;
  console.error = (...a) => errs.push(a.join(" "));
  let threw = null;
  try { loadGame({ difficultySource: difficultySourceWith(mutate) }); }
  catch (e) { threw = e; }
  finally { console.error = orig; }
  return { threw, errs };
}

export function run() {
  const r = makeRunner("difficulty.test.mjs");

  // ---- data: Regular is the legacy baseline; Legendary bosses as derived ---
  {
    const { RunMap, DifficultyData } = loadGame();
    r.eq(RunMap.getDifficultyTier(), "regular", "the generator defaults to Regular");
    // Bands are the source of truth in difficulty.js — read them live so a
    // hand-edit to the Regular bands keeps this green (never pin the values).
    const regT = DifficultyData.tier("regular");
    const reg = RunMap.bandsFor(0);
    r.eq(JSON.stringify([reg.stage, reg.boss]), JSON.stringify([regT.stageBands[0], regT.bossBands[0]]),
      "Regular stage 1 bands come straight from difficulty.js");
    r.eq(JSON.stringify(RunMap.bandsFor(2).boss), JSON.stringify(regT.bossBands[2]), "Regular ♠ boss = difficulty.js bossBands[2]");
  }

  // ---- generator-wide knobs: firstDealBand + subset live in difficulty.js ----
  {
    const { RunMap, DifficultyData } = loadGame();
    const fb = DifficultyData.firstDealBand;
    r.ok(Array.isArray(fb) && fb.length === 2 && fb.every(x => typeof x === "number") && fb[0] <= fb[1],
      "DifficultyData exposes firstDealBand (currently " + JSON.stringify(fb) + ")");
    r.eq(RunMap.GEN_CONFIG.firstDealBand, undefined, "GEN_CONFIG no longer owns firstDealBand");
    const ss = DifficultyData.subset;
    r.ok(ss && ss.threshold > 0 && ss.min > 0 && ss.max >= ss.min,
      "DifficultyData exposes the subset block (currently " + JSON.stringify(ss) + ")");
    r.eq(RunMap.SUBSET, ss, "RunMap.SUBSET reads straight from difficulty.js");
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

  // ---- fixedJokers (JOKER3): the per-deck scheme override is data + accessor --
  {
    const { DifficultyData } = loadGame();
    const reg = DifficultyData.tier("regular");
    r.ok(reg.fixedJokers && typeof reg.fixedJokers === "object",
      "Regular carries the fixedJokers override block");
    r.eq(JSON.stringify(DifficultyData.fixedJokerStages("pink", "regular")),
      JSON.stringify(reg.fixedJokers.pink),
      "fixedJokerStages(pink, regular) reads the data's stage array live");
    r.eq(DifficultyData.fixedJokerStages("mamma", "regular"), null,
      "…a deck the data does NOT list gets null (normal jokerCap rules)");
    r.eq(DifficultyData.fixedJokerStages("pink", "master"), null,
      "…and so does Pinky on Master");
    r.eq(DifficultyData.fixedJokerStages("pink", "legendary"), null,
      "…and Pinky on Legendary");
    r.eq(DifficultyData.fixedJokerStages("pink", "nonsense"), null,
      "…an unknown tier gets null (no silent Regular fallback)");
  }

  // ---- fixedJokers: malformed entries FAIL LOUDLY naming tier + field -------
  {
    const cases = [
      ["block not an object", (d) => { d.tiers.regular.fixedJokers = [0, 1]; }, "tiers.regular", "fixedJokers"],
      ["empty deck-id key", (d) => { d.tiers.regular.fixedJokers = { "": [0] }; }, "tiers.regular", "deck-id key"],
      ["stages not an array", (d) => { d.tiers.regular.fixedJokers.pink = 1; }, "fixedJokers.pink", "non-empty array"],
      ["stages empty", (d) => { d.tiers.regular.fixedJokers.pink = []; }, "fixedJokers.pink", "non-empty array"],
      ["stage index out of range", (d) => { d.tiers.regular.fixedJokers.pink = [0, 3]; }, "fixedJokers.pink[1]", "0-2"],
      ["stage index non-integer", (d) => { d.tiers.regular.fixedJokers.pink = [0.5]; }, "fixedJokers.pink[0]", "0-2"],
      ["stage index negative", (d) => { d.tiers.regular.fixedJokers.pink = [-1]; }, "fixedJokers.pink[0]", "0-2"],
    ];
    for (const [name, mutate, entry, field] of cases) {
      const { threw, errs } = loadExpectingFailure(mutate);
      r.ok(threw && /difficulty\.js validation FAILED/.test(threw.message), `malformed fixedJokers (${name}) throws on load`);
      r.ok(errs.some((l) => l.includes(entry) && l.includes(field)),
        `…and a console.error names "${entry}" + "${field}"`);
    }
    // Control: the field stays OPTIONAL — a tier without it validates clean.
    let ok = true;
    try { loadGame({ difficultySource: difficultySourceWith(d => { delete d.tiers.regular.fixedJokers; }) }); }
    catch (e) { ok = false; }
    r.ok(ok, "a tier with no fixedJokers block still validates clean");
  }

  return r.summary();
}
