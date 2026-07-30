// Test harness for Shoulda Said Same.
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
const ITEMS = join(HERE, "..", "items.js");
const DIFFICULTY = join(HERE, "..", "difficulty.js");
const TUTORIAL = join(HERE, "..", "tutorial.js");

/** Load the game's modules with a stubbed DOM. Returns the engine modules.
    `opts.difficultySource` replaces the difficulty.js source (validation tests
    load deliberately-malformed data); `opts.itemsSource` does the same for
    items.js; `opts.localStorage` injects a storage
    stub (persistence tests for the localStorage-backed stores — without it
    they degrade to their no-storage no-op, exactly like the browser's
    private mode). */
export function loadGame(opts = {}) {
  const html = readFileSync(HTML, "utf8");
  // The page has more than one inline <script> (e.g. the GA4/gtag init in <head>);
  // pick the GAME script — the one that defines the engine modules.
  const blocks = html.match(/<script>([\s\S]*?)<\/script>/g) || [];
  const gameCode = blocks
    .map((b) => b.replace(/^<script>/, "").replace(/<\/script>$/, ""))
    .find((c) => c.includes("const GameEngine"));
  if (!gameCode) throw new Error("No game <script> block found in index.html");
  // The page loads the shop-item DATA (items.js), the difficulty bands
  // (difficulty.js) and the tutorial copy (tutorial.js) before the game
  // script; mirror that here so ItemData, DifficultyData and TutorialData
  // find their globals. opts.difficultySource / opts.itemsSource swap in a
  // mutated data file (the validation tests load deliberately-malformed data).
  const difficultyCode = opts.difficultySource || readFileSync(DIFFICULTY, "utf8");
  const itemsCode = opts.itemsSource || readFileSync(ITEMS, "utf8");
  const code = itemsCode + "\n;" + difficultyCode
    + "\n;" + readFileSync(TUTORIAL, "utf8") + "\n;" + gameCode;

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
    createElementNS: () => node(),
    addEventListener: () => {},
    body: node(),
  };

  const sandbox = {
    // Optional storage stub — a declared-but-undefined parameter keeps
    // `typeof localStorage === "undefined"` true when not provided.
    localStorage: opts.localStorage,
    document: documentStub,
    // The Capacitor shim (NativeApp) lives in its own head <script>; the game
    // script only calls boot()/event() — stub the web (non-native) behavior.
    NativeApp: { native: false, boot: (start) => start(), event: () => {} },
    window: {
      addEventListener() {},
      matchMedia: () => ({ matches: false, addEventListener() {}, addListener() {} }),
      location: { search: "" },
    },
    location: { search: "" },
    navigator: { maxTouchPoints: 0 },
    setTimeout: () => 0,
    clearTimeout: () => {},
    // Overridable for suites that need to count/observe scheduling (PERFCAP).
    requestAnimationFrame: opts.requestAnimationFrame || (() => 0),
    cancelAnimationFrame: opts.cancelAnimationFrame || (() => {}),
    console: opts.console || console,
  };

  const factory = new Function(
    ...Object.keys(sandbox),
    code +
      "\n;return { DeckManager, DeckStats, BoardState, GameEngine, CampaignState, RunMap," +
      " Economy, StickerTypes, PillarTypes, BaseTypes, PackTypes, SamePowerTypes, ItemData," +
      " TutorialData, DifficultyData, Stats, ZenStats, ZenUnlocks, SeedCode, ItemUnlocks," +
      " DeckUnlocks, SaveStore, Telem, PixelArt," +
      " cardMatchesSuit, cardIsWildSuit, Perf: (typeof window !== \"undefined\" ? window.__perf : undefined) };"
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
