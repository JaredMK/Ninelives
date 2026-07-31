// FONT FLOOR — no text in the game may render below 12px (v5.62, player
// report: the map-key sub-text and others were unreadable). A regression here
// means someone re-introduced a sub-floor font-size; the fix is to give the
// CONTAINER room, not to shrink the text back.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { makeRunner } from "./_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const FLOOR = 12;

export function run() {
  const r = makeRunner("fontfloor.test.mjs");
  const html = readFileSync(join(HERE, "..", "index.html"), "utf8");
  const style = html.slice(html.indexOf("<style>"), html.lastIndexOf("</style>"));

  // Plain px declarations.
  const small = [];
  for (const m of style.matchAll(/font-size:\s*([0-9.]+)px/g)) {
    const v = parseFloat(m.group ? m.group(1) : m[1]);
    if (v < FLOOR) small.push(v + "px");
  }
  r.eq(small.length, 0, "no font-size below the " + FLOOR + "px floor" +
    (small.length ? " (found " + small.join(", ") + ")" : ""));

  // clamp() lower bounds — the ONE sanctioned exception is the 0px collapse
  // that HIDES the cards' corner indices (a hide, not readable text).
  const badClamp = [];
  for (const m of style.matchAll(/font-size:\s*clamp\(\s*([0-9.]+)px/g)) {
    const v = parseFloat(m[1]);
    if (v > 0 && v < FLOOR) badClamp.push(v + "px");
  }
  r.eq(badClamp.length, 0, "no clamp() font MINIMUM below the floor" +
    (badClamp.length ? " (found " + badClamp.join(", ") + ")" : ""));

  // …and no clamp may be inverted (min > max) — that silently pins the max.
  const inverted = [];
  for (const m of style.matchAll(/font-size:\s*clamp\(\s*([0-9.]+)px\s*,[^,]+,\s*([0-9.]+)px\s*\)/g)) {
    if (parseFloat(m[1]) >= parseFloat(m[2])) inverted.push(m[0]);
  }
  r.eq(inverted.length, 0, "no inverted clamp() (min >= max)" +
    (inverted.length ? " (" + inverted.join("; ") + ")" : ""));

  return r.summary();
}
