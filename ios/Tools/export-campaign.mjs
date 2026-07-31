#!/usr/bin/env node
/* ============================================================================
   export-campaign.mjs — CAMPAIGN-LAYER GROUND TRUTH.

   Drives the REAL web CampaignState through seeded starts, store rolls, node
   drafts, pack commits, mystery rolls and a serialize round-trip, and records
   everything the Swift port must reproduce.

       node ios/Tools/export-campaign.mjs   # → ios/Fixtures/campaign-fixtures.json
============================================================================ */
import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { loadGame } from "../../tests/_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, "..", "Fixtures");
mkdirSync(OUT, { recursive: true });

const quiet = { log() {}, warn() {}, error: console.error };
const G = loadGame({ console: quiet });
const { CampaignState, ItemData, StickerTypes, PackTypes } = G;

const SEEDS = [11, 4242, 777777, 3141592];
const DECKS = ["pink", "mamma", "smith", "lammy"];
const TIERS = ["regular", "master", "legendary"];

const cardShape = (c) => c && ({
  id: c.id, suit: c.suit, originalRank: c.originalRank, currentRank: c.currentRank,
  joker: !!c.joker, blank: !!c.blank,
  stickers: (c.stickers || []).map((s) => s.type),
  modifications: (c.modifications || []).map((m) => ({ op: m.op, from: m.from, to: m.to })),
});

const slotShape = (s) => s && ({ kind: s.kind, id: s.id, card: s.card ? cardShape(s.card) : null });

/* ── 1. Fresh starts per (seed, deck, tier) ───────────────────────────────── */
const starts = [];
for (const seed of SEEDS) {
  for (const deck of DECKS) {
    for (const tier of TIERS) {
      const c = CampaignState.create();
      c.setDeck(deck); c.setTier(tier); c.setSeedOverride(seed);
      c.reset();   // reset() → startNewRun()
      starts.push({
        seed, deck, tier,
        runSeed: c.getRunSeed(),
        exhibition: c.isExhibition(),
        ownedIds: c.getRunDeck().map((x) => x.id),
        deckSize: c.deckSize(),
        baseDeckSize: c.getDeck().length,
        columnPillars: c.getColumnPillars(),
        columnBases: c.getColumnBases(),
        startCards: c.getRunDeck().map(cardShape),
        // Every +1 node's locked card and every revealed +2 pack's pair — the
        // shown == granted contract, per node id.
        nodeCards: (() => {
          const m = c.getMap();
          const out = {};
          for (const n of m.nodes) {
            if (n.type !== "pickup") continue;
            const card = c.nodeCard(n);
            out[n.id] = card ? (card.joker ? "J" : card.blank ? "B" : card.id) : null;
          }
          return out;
        })(),
        packCards: (() => {
          const m = c.getMap();
          const out = {};
          for (const n of m.nodes) {
            if (n.type !== "pack" || n.packCount !== 2) continue;
            const cards = c.packNodeCards(n);
            if (cards && cards.length) out[n.id] = cards.map((x) => (x.joker ? "J" : x.blank ? "B" : x.id));
          }
          return out;
        })(),
        jokerBudget: c.jokerBudget(),
      });
    }
  }
}

/* ── 2. Store offers: fresh open + rerolls, keyed off a node ─────────────── */
const stores = [];
for (const seed of SEEDS) {
  for (const deck of ["pink", "smith", "lammy"]) {
    const c = CampaignState.create();
    c.setDeck(deck); c.setTier("regular"); c.setSeedOverride(seed);
    c.reset();
    // Walk onto the first legal node so the store stream keys to a real node.
    const opens = c.legalNextNodes();
    if (opens.length) c.moveToNode(opens[0].id);
    c.addCoins(10000);
    const visits = [];
    // The UI opens the shelf with the node-keyed stream; mirror that exactly
    // (index.html: `campaign.openStore(campaign.runRng("store", keyId))`).
    const offer = c.openStore(c.runRng("store", c.nodePos()));
    visits.push({ slots: offer.slots.map(slotShape), rerollCost: offer.rerollCost });
    for (let k = 0; k < 3; k++) {
      if (!c.rerollStore()) break;
      const o = c.getStoreOffer();
      visits.push({ slots: o.slots.map(slotShape), rerollCost: o.rerollCost });
    }
    stores.push({ seed, deck, nodePos: c.nodePos(), visits,
                  coinsAfter: c.getCoins(), nextCardId: c.serialize().nextCardId });
  }
}

/* ── 3. Mystery outcome rolls (pure; no state change) ────────────────────── */
const mystery = [];
for (const seed of SEEDS) {
  const c = CampaignState.create();
  c.setSeedOverride(seed);
  c.reset();
  const rolls = [];
  for (let nodeId = 0; nodeId < 40; nodeId++) rolls.push(c.rollMysteryEvent(nodeId));
  for (const nodeId of [1000, 2003, 800000, 900000]) rolls.push(c.rollMysteryEvent(nodeId));
  mystery.push({ seed, runSeed: c.getRunSeed(), rolls });
}

/* ── 4. Pack reveals + store-card mints (seeded directly) ────────────────── */
function makeRng(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const packs = [];
for (const seed of SEEDS) {
  for (const deck of ["pink", "smith", "lammy"]) {
    for (const pt of PackTypes.all()) {
      const c = CampaignState.create();
      c.setDeck(deck); c.setTier("regular"); c.setSeedOverride(seed);
      c.reset();
      const before = c.serialize().nextCardId;
      const items = c.revealPack(pt.id, makeRng(seed ^ 0xabcdef));
      packs.push({
        seed, deck, packId: pt.id, kind: pt.kind,
        items: pt.kind === "card" ? items.map(cardShape) : items.slice(),
        nextCardIdBefore: before, nextCardIdAfter: c.serialize().nextCardId,
      });
    }
  }
}
const storeCards = [];
for (const seed of SEEDS) {
  for (const deck of ["pink", "smith", "lammy"]) {
    const c = CampaignState.create();
    c.setDeck(deck); c.setTier("regular"); c.setSeedOverride(seed);
    c.reset();
    const rng = makeRng(seed ^ 0x51ca5d);
    const out = [];
    for (let i = 0; i < 12; i++) out.push(cardShape(c.genStoreCard(rng)));
    storeCards.push({ seed, deck, cards: out });
  }
}

/* ── 5. Serialize → restore round-trip ──────────────────────────────────── */
const roundTrips = [];
for (const seed of SEEDS.slice(0, 2)) {
  for (const deck of DECKS) {
    const c = CampaignState.create();
    c.setDeck(deck); c.setTier("master"); c.setSeedOverride(seed);
    c.reset();
    const opens = c.legalNextNodes();
    if (opens.length) c.moveToNode(opens[0].id);
    c.addCoins(250);
    c.addRunScore(37);
    const blob = c.serialize();
    const c2 = CampaignState.create();
    const ok = c2.restore(JSON.parse(JSON.stringify(blob)));
    roundTrips.push({
      seed, deck, ok,
      blobKeys: Object.keys(blob).sort(),
      after: {
        deckId: c2.getDeckId(), tier: c2.getTier(), runSeed: c2.getRunSeed(),
        nodePos: c2.nodePos(), coins: c2.getCoins(), runScore: c2.getRunScore(),
        ownedIds: c2.getRunDeck().map((x) => x.id),
        deckSize: c2.deckSize(),
        mapNodeCount: c2.getMap().nodes.length,
        mapTotalRows: c2.getMap().totalRows,
      },
    });
  }
}

/* ── 6. Layout helpers ──────────────────────────────────────────────────── */
const layouts = [];
for (let n = 1; n <= 14; n++) {
  const l = CampaignState.layoutForPiles(n);
  layouts.push({ piles: n, cols: l.cols, sum: l.piles, rows: l.rows });
}

const out = {
  generatedBy: "ios/Tools/export-campaign.mjs",
  starts, stores, mystery, packs, storeCards, roundTrips, layouts,
};
const path = join(OUT, "campaign-fixtures.json");
writeFileSync(path, JSON.stringify(out) + "\n", "utf8");
console.log(`wrote ${path}`);
console.log(`  ${starts.length} starts, ${stores.length} store visits, ${mystery.length} mystery streams,`);
console.log(`  ${packs.length} pack reveals, ${storeCards.length} store-card streams, ${roundTrips.length} round-trips`);
