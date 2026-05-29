// Test harness for Nine Lives.
//
// The game ships as a single index.html with all logic in one <script>.
// The "engine" modules (DeckManager, BoardState, GameEngine, CampaignState,
// DeckStats) are DOM-free by design, so we can unit-test them in Node by
// extracting the <script>, evaluating it with a minimal stubbed `document`
// (just enough that UIRenderer.init() doesn't throw on load), and returning
// the module objects.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));
const HTML = join(HERE, "..", "index.html");

/** Load the game's modules with a stubbed DOM. Returns the engine modules. */
export function loadGame() {
  const html = readFileSync(HTML, "utf8");
  const m = html.match(/<script>([\s\S]*?)<\/script>/);
  if (!m) throw new Error("No <script> block found in index.html");
  const code = m[1];

  // Every DOM access returns a chainable no-op proxy. The modules under test
  // never touch the DOM; this only keeps UIRenderer.init() (which runs on
  // load) from throwing.
  const node = () =>
    new Proxy(function () {}, {
      get(_t, p) {
        if (p === "classList")
          return { add() {}, remove() {}, toggle() {}, contains() { return false; } };
        if (p === "style")
          return new Proxy({}, { get() { return () => {}; }, set() { return true; } });
        if (p === "dataset") return {};
        if (p === "forEach") return () => {};
        if (p === Symbol.toPrimitive) return () => "";
        return node();
      },
      set() { return true; },
      apply() { return node(); },
    });

  const documentStub = {
    getElementById: () => node(),
    querySelector: () => node(),
    querySelectorAll: () => [],
    createElement: () => node(),
    addEventListener: () => {},
    body: node(),
  };

  const sandbox = {
    document: documentStub,
    window: {
      addEventListener() {},
      matchMedia: () => ({ matches: false, addEventListener() {}, addListener() {} }),
      location: { search: "" },
    },
    location: { search: "" },
    navigator: { maxTouchPoints: 0 },
    setTimeout: () => 0,
    clearTimeout: () => {},
    requestAnimationFrame: () => 0,
    cancelAnimationFrame: () => {},
    console,
  };

  const factory = new Function(
    ...Object.keys(sandbox),
    code +
      "\n;return { DeckManager, DeckStats, BoardState, GameEngine, CampaignState," +
      " Economy, StickerTypes, STICKER_SLOTS_PER_CARD };"
  );
  return factory(...Object.values(sandbox));
}

/** Tiny assertion runner: collects pass/fail and prints a line per check. */
export function makeRunner(label) {
  let pass = 0,
    fail = 0;
  const fails = [];
  if (label) console.log(label);
  function ok(cond, name) {
    if (cond) pass++;
    else {
      fail++;
      fails.push(name);
    }
    console.log((cond ? "  ✓ " : "  ✗ ") + name);
  }
  function eq(actual, expected, name) {
    ok(actual === expected, `${name} (expected ${expected}, got ${actual})`);
  }
  return { ok, eq, summary: () => ({ pass, fail, fails }) };
}
