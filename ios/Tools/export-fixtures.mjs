#!/usr/bin/env node
/* ============================================================================
   export-fixtures.mjs — CROSS-IMPLEMENTATION GROUND TRUTH.

   Runs the REAL web engine (via tests/_harness.mjs, the same loader the 5049-test
   web suite uses) and records, for a set of fixed seeds:

     • rng          — raw mulberry32 outputs (full float precision)
     • seedCode     — the shareable 7-char encoding, both directions
     • shuffle      — DeckManager.create() draw order for a seeded deck
     • economy      — dealFlat / breakdown totals across a grid
     • maps         — the FULL generated run map per (seed, deck, tier)

   The Swift side asserts byte-for-byte agreement (SeedFixtureTests). If these
   ever disagree, iOS and web have diverged and the same seed no longer plays
   the same climb.

       node ios/Tools/export-fixtures.mjs         # → ios/Fixtures/seed-fixtures.json
============================================================================ */
import { writeFileSync, mkdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { loadGame } from "../../tests/_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, "..", "Fixtures");
mkdirSync(OUT, { recursive: true });

// Silence the generator's console.warn/log chatter (best-effort maps, seed
// ladder hits) — it is diagnostic, not part of the fixture.
const quiet = { log() {}, warn() {}, error: console.error };
// Native-only unlock stats swap for a web-legal placeholder (see
// export-traces.mjs) — the fixtures never exercise unlock gates.
const itemsSource = readFileSync(join(HERE, "..", "..", "items.js"), "utf8")
  .replaceAll('"ambushesWon"', '"pilesLost"')
  .replaceAll('"earlyLosses"', '"pilesLost"');
const G = loadGame({ console: quiet, itemsSource });
const { RunMap, DeckManager, Economy, SeedCode, DifficultyData, ItemData } = G;

/* The generator version and Joker scheme the live campaign uses (index.html,
   RUN_GEN_VERSION + runGenOpts). Pinned here so the fixture matches play. */
const RUN_GEN_VERSION = 3;

/** Fixed seeds — a spread of magnitudes incl. 0 and the u32 ceiling. */
const SEEDS = [1, 2, 7, 42, 1234, 99999, 0, 4294967295, 2166136261, 3735928559,
               123456789, 987654321];
const DECKS = ["pink", "mamma", "smith", "lammy"];
const TIERS = ["regular", "master", "legendary"];

/* ── 1. RNG ────────────────────────────────────────────────────────────────
   makeRng isn't exported, but DeckManager.create takes an rng — so instead we
   reconstruct the exact function here. It is copied VERBATIM from index.html;
   the map fixtures below independently prove the real one agrees, because a
   single differing bit would reshape every map. */
function makeRng(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rngFixtures = SEEDS.map((seed) => {
  const r = makeRng(seed);
  // Full precision: the Swift side parses these as Double and compares ==.
  return { seed, values: Array.from({ length: 24 }, () => r()) };
});

/* ── 2. SeedCode ───────────────────────────────────────────────────────── */
const seedCodeFixtures = SEEDS.map((seed) => ({ seed, code: SeedCode.encode(seed) }));
const seedCodeRejects = ["", "ABC", "ABCDEFGH", "AAAAAA0", "999999999", "abcdefg!", "9999999"]
  .map((s) => ({ input: s, decoded: SeedCode.decode(s) }));

/* ── 3. Deck shuffle ───────────────────────────────────────────────────────
   The run deck's draw order for a seeded standard deck — the single most
   sensitive consumer of the rng after map generation. */
const shuffleFixtures = SEEDS.slice(0, 6).map((seed) => {
  const specs = DeckManager.buildStandardDeck();
  const deck = DeckManager.create(specs, makeRng(seed));
  const order = [];
  while (!deck.isEmpty()) order.push(deck.draw().id);
  return { seed, order };
});
/* Zen decks (suitCount slices) — a different card pool through the same shuffle. */
const zenShuffleFixtures = [2, 3, 4].map((suitCount) => {
  const deck = DeckManager.create(DeckManager.buildZenDeck(suitCount), makeRng(4242));
  const order = [];
  while (!deck.isEmpty()) order.push(deck.draw().id);
  return { suitCount, seed: 4242, order };
});

/* ── 4. Economy ────────────────────────────────────────────────────────── */
const economyFixtures = [];
for (const stage of [0, 1, 2, 3, 4, 7]) {
  for (const rating of [0, 1, 2, 3]) {
    for (const isBoss of [false, true]) {
      economyFixtures.push({ stage, rating, isBoss, flat: Economy.dealFlat(stage, rating, isBoss) });
    }
  }
}
const breakdownFixtures = [
  { won: true, flat: 8, stage: 2, rating: 2, aliveCount: 5, minAliveCards: 3, extraCoinUnits: 4, pillarBonus: 6, eventBonus: -2 },
  { won: true, flat: 0, stage: 0, rating: 0, aliveCount: 3, minAliveCards: 2, extraCoinUnits: 0, pillarBonus: 0, eventBonus: 0, ambush: true },
  { won: false, flat: 12, stage: 3, rating: 3, aliveCount: 7, minAliveCards: 4, extraCoinUnits: 9, pillarBonus: 3, eventBonus: 5 },
  { won: true, flat: 4, stage: 1, rating: 1, aliveCount: 2, minAliveCards: 1, extraCoinUnits: 0, pillarBonus: 0, eventBonus: -50 },
].map((stats) => ({ stats, out: (() => { const b = Economy.breakdown(stats); return { total: b.total, product: b.product, extraCoinBonus: b.extraCoinBonus, extraCoinValue: b.extraCoinValue }; })() }));

/* ── 5. Difficulty-derived generator surface ──────────────────────────── */
const bandFixtures = [];
for (const tier of TIERS) {
  RunMap.setDifficultyTier(tier);
  for (const p of [0, 1, 2, 3, 4, 5]) {
    const b = RunMap.bandsFor(p);
    bandFixtures.push({ tier, phase: p, stage: b.stage, boss: b.boss });
  }
}
const scoreFixtures = [];
for (const tier of TIERS) {
  RunMap.setDifficultyTier(tier);
  for (const p of [0, 1, 2, 3]) {
    for (const d of [0.5, 1.5, 2.5, 3.5, 4.5, 5.5, 6.5]) {
      for (const boss of [false, true]) {
        scoreFixtures.push({ tier, phase: p, targetD: d, isBoss: boss, score: RunMap.difficultyScore(d, p, boss) });
      }
    }
  }
}
const subsetPileFixtures = [];
for (const s of [10, 18, 25, 40, 60]) {
  for (const d of [1.0, 2.5, 4.0, 6.0]) {
    subsetPileFixtures.push({ survive: s, targetD: d, piles: RunMap.solveSubsetPiles(s, d) });
  }
}

/* ── 6. MAPS — the headline fixture ───────────────────────────────────────
   The whole run for (seed, deck, tier), generated exactly as the campaign does:
   entry decks laddered by predictedRouteCards from the deck/tier start size,
   the deck/tier fixed-Joker scheme, and RUN_GEN_VERSION. */
function canonicalNode(n) {
  const o = { id: n.id, row: n.row, type: n.type };
  if (n.lane != null) o.lane = n.lane;
  if (n.localRow != null) o.localRow = n.localRow;
  if (n.phase != null) o.phase = n.phase;
  if (n.piles != null) o.piles = n.piles;
  if (n.packCount != null) o.packCount = n.packCount;
  if (n.add != null) o.add = n.add;
  if (n.suit != null) o.suit = n.suit;
  if (n.mystery) o.mystery = true;
  if (n.jokerNode) o.jokerNode = true;
  o.next = n.next.slice();
  return o;
}
const C = RunMap.GEN_CONFIG;
const mapFixtures = [];
for (const seed of SEEDS.slice(0, 8)) {
  for (const deck of DECKS) {
    for (const tier of TIERS) {
      RunMap.setDifficultyTier(tier);
      const start = C.startDeckSize + DifficultyData.startJokers(deck, tier);
      // The campaign's entry ladder: stage 0 is real, later stages predicted.
      const entries = [start, start + C.predictedRouteCards, start + 2 * C.predictedRouteCards];
      const opts = {
        postBossJokerStages: DifficultyData.fixedJokerStages(deck, tier) || [],
        genVersion: RUN_GEN_VERSION,
      };
      const map = RunMap.generateRun(seed, entries, opts);
      mapFixtures.push({
        seed, deck, tier, entries, opts,
        map: {
          totalRows: map.totalRows,
          stagesGenerated: map.stagesGenerated,
          homeId: map.homeId,
          runBossId: map.runBossId,
          row0: map.row0,
          phases: map.phases.map((p) => ({
            phase: p.phase, suit: p.suit, bossId: p.bossId, bossIds: p.bossIds,
            row0: p.row0, rowStart: p.rowStart, rows: p.rows,
            ...(p.jokerNodeId != null ? { jokerNodeId: p.jokerNodeId } : {}),
          })),
          nodes: map.nodes.map(canonicalNode),
        },
      });
    }
  }
}

/* ── 7. Single-stage generation (isolates generateStage from the stacking) ── */
const stageFixtures = [];
for (const seed of SEEDS.slice(0, 6)) {
  for (const tier of TIERS) {
    RunMap.setDifficultyTier(tier);
    for (const [phase, entry] of [[0, 13], [1, 26], [2, 39], [3, 52]]) {
      const ph = RunMap.generateStage(phase, seed, entry, { genVersion: RUN_GEN_VERSION });
      stageFixtures.push({
        seed, tier, phase, entry,
        stage: ph ? {
          rows: ph.rows, bossRow: ph.bossRow, bossId: ph.bossId, row0: ph.row0,
          nodes: ph.nodes.map(canonicalNode),
        } : null,
      });
    }
  }
}
RunMap.setDifficultyTier("regular");

/* ── 8. Data-surface echoes (so a data retune breaks BOTH sides together) ── */
const dataEcho = {
  storeSlots: ItemData.store.slots,
  typeCap: ItemData.store.typeCap,
  stickerIds: ItemData.stickers.map((s) => s.id),
  pillarIds: ItemData.pillars.map((s) => s.id),
  baseIds: ItemData.bases.map((s) => s.id),
  samePowerIds: ItemData.samePowers.map((s) => s.id),
  packIds: ItemData.packs.map((s) => s.id),
  cursedStickerIds: ItemData.stickers.filter((s) => s.cursed).map((s) => s.id),
  genConfig: {
    startDeckSize: C.startDeckSize, predictedRouteCards: C.predictedRouteCards,
    minRouteCards: C.minRouteCards, maxLightRouteCards: C.maxLightRouteCards,
    minPiles: C.minPiles, maxPiles: C.maxPiles, stores: C.stores, rows: C.rows,
    paths: C.paths, lanes: C.lanes, attempts: C.attempts, relaxSteps: C.relaxSteps,
    seedLadderRungs: C.seedLadderRungs, mysteryTypeWeight: C.mysteryTypeWeight,
    dealsPerRouteMax: C.dealsPerRouteMax, preBossStoreRows: C.preBossStoreRows,
    packMax: C.packMax, relaxBandStep: C.relaxBandStep, structAttempts: C.structAttempts,
  },
};

const fixtures = {
  generatedBy: "ios/Tools/export-fixtures.mjs",
  runGenVersion: RUN_GEN_VERSION,
  seeds: SEEDS,
  rng: rngFixtures,
  seedCode: seedCodeFixtures,
  seedCodeRejects,
  shuffle: shuffleFixtures,
  zenShuffle: zenShuffleFixtures,
  economy: economyFixtures,
  breakdown: breakdownFixtures,
  bands: bandFixtures,
  difficultyScore: scoreFixtures,
  subsetPiles: subsetPileFixtures,
  maps: mapFixtures,
  stages: stageFixtures,
  dataEcho,
};

const path = join(OUT, "seed-fixtures.json");
writeFileSync(path, JSON.stringify(fixtures) + "\n", "utf8");
const bytes = JSON.stringify(fixtures).length;
console.log(`wrote ${path}`);
console.log(`  ${(bytes / 1024).toFixed(1)} KiB — ${mapFixtures.length} run maps, ${stageFixtures.length} single stages,`);
console.log(`  ${rngFixtures.length} rng streams, ${shuffleFixtures.length} shuffles, ${economyFixtures.length} economy rows`);
