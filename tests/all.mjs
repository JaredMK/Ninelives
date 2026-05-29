// Test runner: `node tests/all.mjs`
//
// Each *.test.mjs exports run() -> { pass, fail, fails }. Add new suites to
// the SUITES list as features land (economy, stickers, store, apply, ...).
import { run as tieRule } from "./tie-rule.test.mjs";
import { run as economy } from "./economy.test.mjs";
import { run as sticker } from "./sticker.test.mjs";
import { run as engineStickers } from "./engine-stickers.test.mjs";
import { run as stage } from "./stage.test.mjs";
import { run as progression } from "./progression.test.mjs";
import { run as terminology } from "./terminology.test.mjs";

const SUITES = [
  ["tie-rule", tieRule],
  ["economy", economy],
  ["sticker", sticker],
  ["engine-stickers", engineStickers],
  ["stage", stage],
  ["progression", progression],
  ["terminology", terminology],
];

let pass = 0,
  fail = 0;
const allFails = [];
for (const [name, run] of SUITES) {
  const s = run();
  pass += s.pass;
  fail += s.fail;
  allFails.push(...s.fails.map((f) => `${name}: ${f}`));
}

console.log(`\n${pass} passed, ${fail} failed`);
if (fail) {
  allFails.forEach((f) => console.log("FAIL " + f));
  process.exit(1);
}
