// Phase 1 guard: the word "round" is banned as a unit — the hierarchy units are
// Run > Stage > Deal. Allowed false positives: "background" (no word boundary)
// and the JS "Math.round" function. Fails if a stray "round/rounds" reappears.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { makeRunner } from "./_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

export function run() {
  const r = makeRunner("terminology.test.mjs");
  for (const file of ["index.html", "README.md"]) {
    const text = readFileSync(join(HERE, "..", file), "utf8");
    const offenders = text
      .split("\n")
      .map((line, i) => [i + 1, line])
      // Allowed false positives: Math.round, and the SVG "round" stroke
      // line-cap/line-join keyword (CSS, attribute, or single-quoted data-URI
      // attribute form) used by the visuals.
      .filter(([, line]) => /\brounds?\b/i.test(
        line.replace(/Math\.round/g, "").replace(/(?:linecap|linejoin)\s*[:=]\s*["']?round["']?/gi, "")));
    r.ok(offenders.length === 0,
      file + ' has no stray "round"' +
      (offenders.length ? " (line " + offenders.map(([n]) => n).join(", ") + ")" : ""));
  }
  return r.summary();
}
