// Test runner: `node tests/all.mjs`
//
// Each *.test.mjs exports run() -> { pass, fail, fails }. Add new suites to
// the SUITES list as features land (economy, stickers, store, apply, ...).
import { run as tieRule } from "./tie-rule.test.mjs";
import { run as economy } from "./economy.test.mjs";
import { run as sticker } from "./sticker.test.mjs";
import { run as engineStickers } from "./engine-stickers.test.mjs";
// [run-map rework] stage.test.mjs (old stages×deals schedule) retired — rewritten in reconcile section
import { run as runMap } from "./run-map.test.mjs";  // run-map replaces the old progression (stages×deals)
import { run as terminology } from "./terminology.test.mjs";
import { run as pillar } from "./pillar.test.mjs";
import { run as storeOffer } from "./store-offer.test.mjs";
import { run as features } from "./features.test.mjs";
import { run as persistence } from "./persistence.test.mjs";
import { run as expansion } from "./expansion.test.mjs";
import { run as packs } from "./packs.test.mjs";
import { run as packReplace } from "./pack-replace.test.mjs";
import { run as jokerBlank } from "./joker-blank.test.mjs";
import { run as redeal } from "./redeal.test.mjs";
import { run as pillarFeedback } from "./pillar-feedback.test.mjs";
import { run as wildPeel } from "./wild-peel.test.mjs";
import { run as newItems } from "./new-items.test.mjs";
import { run as bases } from "./bases.test.mjs";
import { run as expansionStickers } from "./expansion-stickers.test.mjs";
import { run as expansionPillars } from "./expansion-pillars.test.mjs";
import { run as expansionBases } from "./expansion-bases.test.mjs";
import { run as lifetimeStats } from "./lifetime-stats.test.mjs";
import { run as peekPillars } from "./peek-pillars.test.mjs";
import { run as packMerge } from "./pack-merge.test.mjs";
import { run as mysteryNodes } from "./mystery-nodes.test.mjs";
import { run as jokerCaps } from "./joker-caps.test.mjs";
import { run as storeClass } from "./store-class.test.mjs";
import { run as runMods } from "./run-mods.test.mjs";
import { run as tell } from "./tell.test.mjs";
import { run as sameCharge } from "./same-charge.test.mjs";
import { run as samePower } from "./same-power.test.mjs";
import { run as subsetDeals } from "./subset-deals.test.mjs";
import { run as sameItems } from "./same-items.test.mjs";
import { run as stickerSuits } from "./sticker-suits.test.mjs";
import { run as deckRules } from "./deck-rules.test.mjs";
import { run as difficulty } from "./difficulty.test.mjs";
import { run as smooth1 } from "./smooth1.test.mjs";
import { run as uifix1 } from "./uifix1.test.mjs";
import { run as tut2 } from "./tut2.test.mjs";
import { run as boot2 } from "./boot2.test.mjs";
import { run as pack2 } from "./pack2.test.mjs";
import { run as packs2 } from "./packs2.test.mjs";
import { run as zen1 } from "./zen1.test.mjs";
import { run as zen2 } from "./zen2.test.mjs";
import { run as zen6 } from "./zen6.test.mjs";
import { run as wildSuit } from "./wild-suit.test.mjs";
import { run as sell1 } from "./sell1.test.mjs";
import { run as resume1 } from "./resume1.test.mjs";
import { run as storehelp1 } from "./storehelp1.test.mjs";
import { run as help2 } from "./help2.test.mjs";
import { run as tut4 } from "./tut4.test.mjs";
import { run as stklag1 } from "./stklag1.test.mjs";
import { run as stklag2 } from "./stklag2.test.mjs";

const SUITES = [
  ["tie-rule", tieRule],
  ["economy", economy],
  ["sticker", sticker],
  ["engine-stickers", engineStickers],
  // ["stage", stage],  // retired with the old stage schedule (see run-map reconcile)
  ["run-map", runMap],
  ["terminology", terminology],
  ["pillar", pillar],
  ["store-offer", storeOffer],
  ["features", features],
  ["persistence", persistence],
  ["expansion", expansion],
  ["packs", packs],
  ["pack-replace", packReplace],
  ["joker-blank", jokerBlank],
  ["redeal", redeal],
  ["pillar-feedback", pillarFeedback],
  ["wild-peel", wildPeel],
  ["new-items", newItems],
  ["bases", bases],
  ["expansion-stickers", expansionStickers],
  ["expansion-pillars", expansionPillars],
  ["expansion-bases", expansionBases],
  ["lifetime-stats", lifetimeStats],
  ["peek-pillars", peekPillars],
  ["pack-merge", packMerge],
  ["mystery-nodes", mysteryNodes],
  ["joker-caps", jokerCaps],
  ["store-class", storeClass],
  ["run-mods", runMods],
  ["tell", tell],
  ["same-charge", sameCharge],
  ["same-power", samePower],
  ["subset-deals", subsetDeals],
  ["same-items", sameItems],
  ["sticker-suits", stickerSuits],
  ["deck-rules", deckRules],
  ["difficulty", difficulty],
  ["smooth1", smooth1],
  ["uifix1", uifix1],
  ["tut2", tut2],
  ["boot2", boot2],
  ["pack2", pack2],
  ["packs2", packs2],
  ["zen1", zen1],
  ["zen2", zen2],
  ["zen6", zen6],
  ["wild-suit", wildSuit],
  ["sell1", sell1],
  ["resume1", resume1],
  ["storehelp1", storehelp1],
  ["help2", help2],
  ["tut4", tut4],
  ["stklag1", stklag1],
  ["stklag2", stklag2],
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
