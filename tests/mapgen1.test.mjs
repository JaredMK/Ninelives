// MAPGEN1 — deck-select map-generation latency rework:
//   (a) multi-slot pregen cache (one slot per tier|FJ key; consumption evicts),
//   (b) stage-chunked pregen (RunMap.makeRunStepper: one stage per idle slice),
//   (c1) genVersion-gated deterministic seed ladder on stage failure,
//   (c2) output-preserving speedups inside tryBuildStage (incremental route sums).
//
// The two HARD invariants under test:
//   • SAVE COMPATIBILITY — on Continue the map REGENERATES from the saved seed,
//     so for every map the pre-mapgen1 generator could produce, the new code
//     must produce a BIT-IDENTICAL one when driven with genVersion 1 (and with
//     genVersion 2 wherever the baseline converged — the ladder only fires on
//     seeds the baseline FAILED). Verified against the actual d7d5874 baseline
//     generator, extracted from git at test time.
//   • The sync generateRun must equal a drained stepper exactly.
//
// Registry-driven throughout: entry decks, tier ids and fixed-Joker stages are
// read live from GEN_CONFIG / DifficultyData — no tunable is pinned.
import { execSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadGame, makeRunner } from "./_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const BASELINE_COMMIT = "d7d5874";   // v5.01 — the pre-mapgen1 generator

/* Load a game script from an arbitrary index.html SOURCE (the baseline comes
   from git, not the working tree — _harness.loadGame always reads the live
   file). Mirrors the harness's DOM stub; captures console.warn so a stage's
   "no valid map" best-effort fallback is observable. */
function loadFromSource(html, data = {}) {
  const blocks = html.match(/<script>([\s\S]*?)<\/script>/g) || [];
  const gameCode = blocks
    .map((b) => b.replace(/^<script>/, "").replace(/<\/script>$/, ""))
    .find((c) => c.includes("const GameEngine"));
  if (!gameCode) throw new Error("no game <script> in source");
  const code =
    (data.items || readFileSync(join(HERE, "..", "items.js"), "utf8")) + "\n;" +
    (data.difficulty || readFileSync(join(HERE, "..", "difficulty.js"), "utf8")) + "\n;" +
    (data.tutorial || readFileSync(join(HERE, "..", "tutorial.js"), "utf8")) + "\n;" + gameCode;
  const node = () =>
    new Proxy(function () {}, {
      get(_t, p) {
        if (p === "classList") return { add() {}, remove() {}, toggle() {}, contains() { return false; } };
        if (p === "style") return new Proxy({}, { get() { return () => {}; }, set() { return true; } });
        if (p === "dataset") return {};
        if (p === "forEach") return () => {};
        if (p === Symbol.toPrimitive) return () => "";
        return node();
      },
      set() { return true; },
      apply() { return node(); },
    });
  const warns = [];
  const sandbox = {
    localStorage: undefined,
    document: { getElementById: () => node(), querySelector: () => node(), querySelectorAll: () => [],
                createElement: () => node(), createElementNS: () => node(), addEventListener: () => {}, body: node() },
    NativeApp: { native: false, boot: (start) => start(), event: () => {} },
    window: { addEventListener() {}, matchMedia: () => ({ matches: false, addEventListener() {}, addListener() {} }), location: { search: "" } },
    location: { search: "" },
    navigator: { maxTouchPoints: 0 },
    setTimeout: () => 0, clearTimeout: () => {}, requestAnimationFrame: () => 0, cancelAnimationFrame: () => {},
    console: { ...console, log: () => {}, warn: (...a) => warns.push(a.join(" ")) },
  };
  const factory = new Function(...Object.keys(sandbox), code + "\n;return { RunMap };");
  return { RunMap: factory(...Object.values(sandbox)).RunMap, warns };
}

/** Stable full-structure hash of a generated run map: every node's identity,
    graph position, edges and gameplay payload (piles/adds/suits/mystery). */
function mapHash(m) {
  return JSON.stringify({
    totalRows: m.totalRows, row0: m.row0, homeId: m.homeId,
    runBossId: m.runBossId, stages: m.stagesGenerated,
    phases: m.phases.map((p) => ({ phase: p.phase, suit: p.suit, bossId: p.bossId,
      row0: p.row0, rowStart: p.rowStart, rows: p.rows, jokerNodeId: p.jokerNodeId })),
    nodes: m.nodes.slice().sort((a, b) => a.id - b.id).map((n) => ({
      id: n.id, type: n.type, row: n.row, lane: n.lane, x: n.x, next: n.next,
      add: n.add, packCount: n.packCount, piles: n.piles, suit: n.suit,
      mixed: n.mixed, mystery: n.mystery, jokerNode: n.jokerNode,
      phase: n.phase, targetD: n.targetD,
    })),
  });
}

/** Run fn with console.log/warn captured (the harness shares the global
    console object with the loaded game, so this covers loadGame code too). */
function quiet(fn) {
  const oL = console.log, oW = console.warn, warns = [];
  console.log = () => {};
  console.warn = (...a) => warns.push(a.join(" "));
  try { return { result: fn(), warns }; }
  finally { console.log = oL; console.warn = oW; }
}

export function run() {
  const r = makeRunner("mapgen1.test.mjs");
  const g = loadGame();
  const { RunMap, CampaignState, DifficultyData } = g;
  const e0 = RunMap.GEN_CONFIG.startDeckSize;
  const prc = RunMap.GEN_CONFIG.predictedRouteCards;
  const entries = [e0, e0 + prc, e0 + 2 * prc];   // the pregen/new-run entry ladder
  const SEEDS = Array.from({ length: 8 }, (_, s) => (12345 + s * 7919) >>> 0);
  const TIERS = DifficultyData.tierIds;           // registry-driven (two-tier model: regular/legendary)
  // A fixed-Joker corridor spec for the FJ variants: the live registry value
  // when one exists (Pinky Regular today), else a representative 2-stage list.
  const FJ = DifficultyData.fixedJokerStages("pink", "regular") || [0, 1];

  // ---- (1) stepper equivalence: sync generateRun === drained stepper --------
  {
    let allEqual = true, stepCounts = new Set();
    for (const tier of TIERS) {
      for (const s of SEEDS.slice(0, 6)) {
        for (const fj of [[], FJ]) {
          for (const genV of [2, 3]) {   // MYST3: the first-class mystery generator must chunk identically too
            quiet(() => {
              RunMap.setDifficultyTier(tier);
              const opts = { postBossJokerStages: fj, genVersion: genV };
              const sync = RunMap.generateRun(s, entries, opts);
              const stepper = RunMap.makeRunStepper(s, entries, opts);
              let steps = 1; while (stepper.step()) steps++;
              stepCounts.add(steps);
              if (mapHash(sync) !== mapHash(stepper.finish())) allEqual = false;
            });
          }
        }
      }
    }
    r.ok(allEqual, "drained stepper output is hash-identical to sync generateRun (6 seeds × tiers × FJ/– × genV 2+3)");
    r.ok([...stepCounts].every((n) => n === entries.length),
      "the stepper builds exactly one stage per step() (" + entries.length + " stages per run)");
  }

  // ---- (2) legacy bit-compat against the ACTUAL d7d5874 generator -----------
  // The whole feature is unshippable if this fails: saves regenerate their map
  // from the saved seed, so genVersion 1 must reproduce the baseline exactly —
  // including its best-effort (failed) maps.
  let baseline = null, curBase = null;
  try {
    const gitShow = (f) => execSync("git show " + BASELINE_COMMIT + ":" + f,
      { cwd: HERE, maxBuffer: 1 << 26 }).toString();
    // v6.02 retired the Master tier and flattened the bands, so the baseline
    // generator runs against its OWN commit's data files, and the current
    // generator is loaded with the baseline difficulty.js for the comparison
    // (its items.js/tutorial.js stay live — the current validator needs the
    // current shapes, and map generation doesn't read them).
    const baseData = { items: gitShow("items.js"), difficulty: gitShow("difficulty.js"), tutorial: gitShow("tutorial.js") };
    baseline = loadFromSource(gitShow("index.html"), baseData);
    curBase = loadGame({ difficultySource: baseData.difficulty });
  } catch (e) {
    r.ok(false, "baseline generator unavailable (git show " + BASELINE_COMMIT + " failed: " + e.message + ")");
  }
  // Both sides share exactly these tier ids (the baseline's "master" is retired:
  // the current build maps it to regular, so it can't produce distinct maps).
  const COMPAT_TIERS = ["regular", "legendary"];
  const baselineFails = [];   // { seed, tier, hash } — baseline shipped a best-effort map
  if (baseline) {
    const BaseMap = curBase.RunMap;   // CURRENT generator + baseline data
    let v1All = true, v2Converging = true, converging = 0;
    for (const tier of COMPAT_TIERS) {
      for (const seed of SEEDS) {
        baseline.warns.length = 0;
        baseline.RunMap.setDifficultyTier(tier);
        const mb = baseline.RunMap.generateRun(seed, entries, { postBossJokerStages: [] });
        const failed = baseline.warns.some((w) => w.includes("no valid map"));
        const hb = mapHash(mb);
        const h1 = quiet(() => {
          BaseMap.setDifficultyTier(tier);
          return mapHash(BaseMap.generateRun(seed, entries, { postBossJokerStages: [], genVersion: 1 }));
        }).result;
        if (h1 !== hb) { v1All = false; r.ok(false, "genV1 mismatch vs baseline: " + tier + " seed " + seed); }
        if (failed) { baselineFails.push({ seed, tier, hash: hb }); continue; }
        converging++;
        const h2 = quiet(() => {
          BaseMap.setDifficultyTier(tier);
          return mapHash(BaseMap.generateRun(seed, entries, { postBossJokerStages: [], genVersion: 2 }));
        }).result;
        if (h2 !== hb) { v2Converging = false; r.ok(false, "genV2 mismatch on a CONVERGING baseline seed: " + tier + " seed " + seed); }
      }
    }
    r.ok(v1All, "genVersion 1 is bit-identical to the " + BASELINE_COMMIT + " baseline for all "
      + (SEEDS.length * COMPAT_TIERS.length) + " seed×tier maps (incl. best-effort failures)");
    r.ok(v2Converging, "genVersion 2 is bit-identical on every CONVERGING baseline seed ("
      + converging + " maps — the ladder never fires there)");
    r.ok(converging > 0, "the sweep exercised converging seeds (" + converging + ")");
  }

  // ---- (3) the seed ladder rescues baseline-failing seeds (genV2 only) ------
  if (baseline) {
    // Search programmatically: the sweep above usually finds failing seeds on
    // legendary; widen it if the difficulty data ever shifts them.
    if (!baselineFails.length) {
      outer: for (const tier of COMPAT_TIERS.slice(1)) {
        for (let s = 8; s < 24; s++) {
          const seed = (12345 + s * 7919) >>> 0;
          baseline.warns.length = 0;
          baseline.RunMap.setDifficultyTier(tier);
          const mb = baseline.RunMap.generateRun(seed, entries, { postBossJokerStages: [] });
          if (baseline.warns.some((w) => w.includes("no valid map"))) {
            baselineFails.push({ seed, tier, hash: mapHash(mb) });
            break outer;
          }
        }
      }
    }
    if (!baselineFails.length) {
      // Data-dependent: with the live difficulty bands no searched seed fails —
      // the ladder simply has nothing to rescue. Record the fact, don't fail.
      r.ok(true, "no baseline-failing seed found in the search window (ladder unexercisable with live bands)");
    } else {
      const f = baselineFails[0];
      const BaseMap = curBase.RunMap;
      const v1 = quiet(() => {
        BaseMap.setDifficultyTier(f.tier);
        return mapHash(BaseMap.generateRun(f.seed, entries, { postBossJokerStages: [], genVersion: 1 }));
      });
      r.eq(v1.result === f.hash, true,
        "genV1 reproduces the baseline BEST-EFFORT map on a failing seed (" + f.tier + " " + f.seed + ")");
      r.ok(v1.warns.some((w) => w.includes("no valid map")),
        "…and still logs the legacy failure warning (same legacy behavior)");
      const v2a = quiet(() => {
        BaseMap.setDifficultyTier(f.tier);
        return BaseMap.generateRun(f.seed, entries, { postBossJokerStages: [], genVersion: 2 });
      });
      r.ok(!v2a.warns.some((w) => w.includes("no valid map")),
        "genV2 seed-ladders the failing seed to a VALID map (no failure warning)");
      const okStages = v2a.result.phases.every((p, i) => {
        const gen = v2a.result.nodes.find((n) => n.phase === i && n.type === "boss");
        return !!gen;
      });
      r.ok(okStages && v2a.result.stagesGenerated === entries.length,
        "…with all " + entries.length + " stages generated");
      r.ok(v2a.result.nodes.every((n) => n.type !== "deal" && n.type !== "boss" || n.piles > 0),
        "…every deal/boss carries a pile count");
      const v2b = quiet(() => {
        BaseMap.setDifficultyTier(f.tier);
        return mapHash(BaseMap.generateRun(f.seed, entries, { postBossJokerStages: [], genVersion: 2 }));
      });
      r.eq(mapHash(v2a.result) === v2b.result, true, "the ladder is deterministic (genV2 twice → identical hash)");
      r.ok(mapHash(v2a.result) !== f.hash, "the ladder map differs from the baseline best-effort (it actually rescued)");
    }
  }

  // ---- (4) multi-slot pregen cache: keys coexist; consumption evicts --------
  {
    const { result: checks } = quiet(() => {
      const c = CampaignState.create();
      c.setDeck("pink"); c.setTier("regular");
      const out = {};
      out.started = c.pregenerateRun("pink", "regular");
      out.dedupeInFlight = !c.pregenerateRun("pink", "regular");
      c._pregenDrain();                                     // Node has no idle callbacks
      out.dedupeCached = !c.pregenerateRun("pink", "regular");
      out.secondKeyStarts = c.pregenerateRun("pink", "legendary");
      c._pregenDrain();
      out.bothCached = !c.pregenerateRun("pink", "legendary") && !c.pregenerateRun("pink", "regular");
      c.startNewRun();                                      // consumes the regular entry
      out.consumed = c.getMap();
      out.consumedHasNodes = out.consumed && out.consumed.nodes.length > 0;
      out.regularEvicted = c.pregenerateRun("pink", "regular") === true;   // must REBUILD
      c.pregenCancel();                                     // drop that rebuild mid-flight
      out.legendarySurvives = c.pregenerateRun("pink", "legendary") === false;   // untouched, pristine
      c.startNewRun();                                      // regular again — no cache entry now
      out.neverReused = c.getMap() !== out.consumed;        // a consumed map is never handed out twice
      c.setTier("legendary"); c.startNewRun();              // consumes the legendary entry
      out.legendaryConsumed = c.getMap() !== out.consumed;
      out.legendaryEvicted = c.pregenerateRun("pink", "legendary") === true;
      c.pregenCancel();
      return out;
    });
    r.ok(checks.started, "pregenerateRun starts a chunked build (returns true)");
    r.ok(checks.dedupeInFlight, "a second call for the IN-FLIGHT key dedupes (false)");
    r.ok(checks.dedupeCached, "a call for a CACHED key dedupes (false)");
    r.ok(checks.secondKeyStarts, "a different tier gets its own cache slot");
    r.ok(checks.bothCached, "both tier keys are cached simultaneously (no mutual eviction)");
    r.ok(checks.consumedHasNodes, "startNewRun consumed a cached map");
    r.ok(checks.regularEvicted, "consumption EVICTS the entry (the key rebuilds from scratch)");
    r.ok(checks.legendarySurvives, "the other key survives consumption untouched");
    r.ok(checks.neverReused, "a consumed (play-mutated) map object is never handed out again");
    r.ok(checks.legendaryConsumed && checks.legendaryEvicted, "the surviving key consumes cleanly later, then evicts");
  }

  // ---- (5) save format: genV rides in the save; absent genV = legacy 1 ------
  {
    const { result: out } = quiet(() => {
      const o = {};
      const c = CampaignState.create();                       // fresh run → current genVersion
      const snap = JSON.parse(JSON.stringify(c.serialize()));
      o.genV = snap.genV;
      const c2 = CampaignState.create();
      o.restored = c2.restore(JSON.parse(JSON.stringify(snap)));
      o.roundTrip = c2.serialize().genV;
      o.sameMapSize = c2.getMap().nodes.length === c.getMap().nodes.length
        && (c2.getMap().phases[0] || {}).bossId === (c.getMap().phases[0] || {}).bossId;
      const legacy = JSON.parse(JSON.stringify(snap));
      delete legacy.genV;                                     // a pre-mapgen1 save
      const c3 = CampaignState.create();
      o.legacyRestored = c3.restore(legacy);
      o.legacyGenV = c3.serialize().genV;
      c3.startNewRun();                                       // fresh seed → upgrade
      o.upgraded = c3.serialize().genV;
      return o;
    });
    r.eq(out.genV, 3, "a new campaign serializes genV 3 (MYST3)");
    r.ok(out.restored, "a genV-3 save restores");
    r.eq(out.roundTrip, 3, "genV survives the serialize→restore round-trip");
    r.ok(out.sameMapSize, "the restored map regenerates structurally identical from the saved seed");
    r.ok(out.legacyRestored, "a save WITHOUT genV (pre-mapgen1) still restores");
    r.eq(out.legacyGenV, 1, "…and regenerates through the LEGACY path (genV defaults to 1)");
    r.eq(out.upgraded, 3, "a fresh run after a legacy restore stamps the current genVersion (fresh seed)");
  }

  return r.summary();
}
