// Test runner: `node tests/all.mjs`
//
// Each *.test.mjs exports run() -> { pass, fail, fails }. Add new suites to
// the SUITES list as features land (economy, stickers, store, apply, ...).
import { run as tieRule } from "./tie-rule.test.mjs";
import { run as economy } from "./economy.test.mjs";
import { run as sticker } from "./sticker.test.mjs";
import { run as engineStickers } from "./engine-stickers.test.mjs";
// [run-map rework] stage.test.mjs (old stages×deals schedule) retired — rewritten in reconcile section
import { run as progression } from "./progression.test.mjs";
import { run as terminology } from "./terminology.test.mjs";
import { run as pillar } from "./pillar.test.mjs";
import { run as storeOffer } from "./store-offer.test.mjs";
import { run as features } from "./features.test.mjs";
import { run as persistence } from "./persistence.test.mjs";
import { run as expansion } from "./expansion.test.mjs";
import { run as packs } from "./packs.test.mjs";
import { run as packReplace } from "./pack-replace.test.mjs";
import { run as redeal } from "./redeal.test.mjs";
import { run as pillarFeedback } from "./pillar-feedback.test.mjs";
import { run as wildPeel } from "./wild-peel.test.mjs";
import { run as newItems } from "./new-items.test.mjs";
import { run as bases } from "./bases.test.mjs";
import { run as expansionStickers } from "./expansion-stickers.test.mjs";
import { run as expansionPillars } from "./expansion-pillars.test.mjs";
import { run as expansionBases } from "./expansion-bases.test.mjs";
import { run as lifetimeStats } from "./lifetime-stats.test.mjs";
import { run as broadcast } from "./broadcast.test.mjs";
import { run as peekPillars } from "./peek-pillars.test.mjs";
import { run as runMods } from "./run-mods.test.mjs";
import { run as tell } from "./tell.test.mjs";
import { run as sameCharge } from "./same-charge.test.mjs";
import { run as samePower } from "./same-power.test.mjs";

const SUITES = [
  ["tie-rule", tieRule],
  ["economy", economy],
  ["sticker", sticker],
  ["engine-stickers", engineStickers],
  // ["stage", stage],  // retired with the old stage schedule (see run-map reconcile)
  ["progression", progression],
  ["terminology", terminology],
  ["pillar", pillar],
  ["store-offer", storeOffer],
  ["features", features],
  ["persistence", persistence],
  ["expansion", expansion],
  ["packs", packs],
  ["pack-replace", packReplace],
  ["redeal", redeal],
  ["pillar-feedback", pillarFeedback],
  ["wild-peel", wildPeel],
  ["new-items", newItems],
  ["bases", bases],
  ["expansion-stickers", expansionStickers],
  ["expansion-pillars", expansionPillars],
  ["expansion-bases", expansionBases],
  ["lifetime-stats", lifetimeStats],
  ["broadcast", broadcast],
  ["peek-pillars", peekPillars],
  ["run-mods", runMods],
  ["tell", tell],
  ["same-charge", sameCharge],
  ["same-power", samePower],
];

let pass = 0,
  fail = 0;
const allFails = [];
for (const [name, run] of SUITES) {
  let s;
  try {
    s = run();
  } catch (e) {
    // A suite that THROWS (rather than returning fails) is reported as one
    // failure instead of crashing the whole runner.
    fail += 1;
    allFails.push(`${name}: THREW ${e && e.message ? e.message : e}`);
    continue;
  }
  pass += s.pass;
  fail += s.fail;
  allFails.push(...s.fails.map((f) => `${name}: ${f}`));
}

console.log(`\n${pass} passed, ${fail} failed`);
if (fail) {
  allFails.forEach((f) => console.log("FAIL " + f));
  process.exit(1);
}
