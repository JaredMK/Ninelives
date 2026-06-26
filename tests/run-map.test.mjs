// Run-map structure (replaces the old stages×deals progression). A run travels
// 3 phase-maps (♦ → ♣ → ♠); hearts are pre-held (start = 13 hearts). The deck is
// the ACCUMULATED draft (grows via pickup/pack nodes); a deal deals the WHOLE
// deck across the node's pile count. This suite covers the deck/draft, phase
// advancement, the generated graph's validity, suit-in-play gating, layout, and
// serialize/restore — DOM-free (reads CampaignState + RunMap directly).
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { CampaignState, RunMap, DeckManager } = loadGame();
  const r = makeRunner("run-map.test.mjs");

  // ---- starting deck: 13 hearts, ready to play immediately ----------------
  {
    const c = CampaignState.create();
    r.eq(c.deckSize(), 13, "a fresh campaign holds 13 cards");
    const deck = c.getRunDeck();
    r.eq(deck.length, 13, "getRunDeck() deals the whole 13-card draft");
    r.ok(deck.every(x => x.suit === "♥"), "the starting 13 are all hearts (pre-held)");
    r.eq(c.getPhaseIndex(), 0, "starts in phase 0 (♦)");
    r.eq(c.phaseSuit(), "♦", "phase 0 travels diamonds");
  }

  // ---- pickups + packs grow the accumulated deck --------------------------
  {
    const c = CampaignState.create();
    const before = c.deckSize();
    const card = c.resolvePickup({ type: "pickup", mixed: false });
    r.ok(card, "a pickup adds a card");
    r.eq(c.deckSize(), before + 1, "the deck grew by one");
    r.eq(c.getRunDeck().length, c.deckSize(), "getRunDeck() reflects the bigger draft");
    // A pack grants ONLY its displayed suit, and EXACTLY its count — the deck is
    // a growing draft, so once a suit's 13 unique cards are spoken for it mints
    // duplicates rather than granting fewer (a +N pack always adds N).
    const added = c.resolvePack({ type: "pack", packCount: 3, suit: "♦" });
    r.eq(added.length, 3, "a +3 ♦ pack adds EXACTLY 3 cards");
    r.ok(added.every(x => x.suit === "♦"), "a ♦ pack grants ONLY diamonds (no off-suit fill)");
    r.eq(c.deckSize(), before + 1 + 3, "the deck grew by exactly the cards added");
    // Every card id in the draft is still unique (minted duplicates get fresh ids).
    const ids = c.getRunDeck().map(x => x.id);
    r.eq(new Set(ids).size, ids.length, "every draft card has a unique id (incl. minted duplicates)");
  }

  // ---- packs ALWAYS grant exactly N, minting once the unique pool is dry ----
  {
    const c = CampaignState.create();
    const before = c.deckSize();
    // 13 ♣ exist; ~7 are reserved by +1 club nodes. Open six +5 packs = 30 clubs
    // far beyond the unique pool → minting must keep each pack at exactly 5.
    let total = 0;
    for (let k = 0; k < 6; k++) {
      const got = c.resolvePack({ type: "pack", packCount: 5, suit: "♣" });
      r.eq(got.length, 5, "club pack #" + (k + 1) + " grants EXACTLY 5 (mints once base ♣ run out)");
      r.ok(got.every(x => x.suit === "♣"), "minted pack cards are all ♣");
      total += got.length;
    }
    r.eq(total, 30, "six +5 ♣ packs grant 30 clubs total (well past the 13 unique)");
    r.eq(c.deckSize(), before + 30, "the deck grew by exactly 30 (now past 52)");
    r.eq(c.getRunDeck().filter(x => x.suit === "♣").length, 30, "the run deck holds all 30 club cards");
    // A grown (>52) deck must still serialize + restore intact.
    const snap = JSON.parse(JSON.stringify(c.serialize()));
    const c2 = CampaignState.create();
    r.ok(c2.restore(snap), "a deck grown past 52 still restores from a save");
    r.eq(c2.deckSize(), c.deckSize(), "restored deck size matches (minted cards persisted)");
    r.eq(c2.getRunDeck().filter(x => x.suit === "♣").length, 30, "restored club cards preserved");
  }

  // ---- a pack grants ONLY its displayed suit, in every phase --------------
  {
    for (const suit of ["♦", "♣", "♠"]) {
      const c = CampaignState.create();
      let all = [];
      // open several packs of `suit`; every granted card must be that suit.
      for (let k = 0; k < 6; k++) all = all.concat(c.resolvePack({ type: "pack", packCount: 5, suit }));
      r.ok(all.length >= 1, "a " + suit + " pack grants at least one card");
      r.ok(all.every(x => x.suit === suit), "every card a " + suit + " pack grants is " + suit + " (no off-suit)");
    }
  }

  // ---- phase advancement: ♦ → ♣ → ♠ → run won -----------------------------
  {
    const c = CampaignState.create();
    r.eq(c.phaseSuit(), "♦", "phase 1 = diamonds");
    r.ok(c.advancePhase(), "advancePhase from ♦ → there is a next phase");
    r.eq(c.getPhaseIndex(), 1, "now phase 2 (♣)");
    r.eq(c.phaseSuit(), "♣", "phase 2 = clubs");
    r.ok(c.advancePhase(), "advancePhase from ♣ → there is a next phase");
    r.eq(c.phaseSuit(), "♠", "phase 3 = spades");
    r.ok(!c.advancePhase(), "advancePhase from ♠ → false (the ♠ boss fell = run won)");
    r.ok(c.isComplete(), "isComplete() once the ♠ boss is beaten");
    // The deck (hearts) persists across phases (the draft is never wiped mid-run).
    r.eq(c.deckSize(), 13, "the accumulated deck carries across phases");
  }

  // ---- suits in play grow with the phase (drives item gating) -------------
  {
    const c = CampaignState.create();
    const inPhase = () => c.suitsInPlay().slice().sort().join("");
    r.eq(inPhase(), ["♥", "♦"].sort().join(""), "phase ♦: hearts + diamonds in play");
    c.advancePhase();
    r.eq(inPhase(), ["♥", "♦", "♣"].sort().join(""), "phase ♣: + clubs");
    c.advancePhase();
    r.eq(inPhase(), ["♥", "♦", "♣", "♠"].sort().join(""), "phase ♠: all four");
  }

  // ---- the generated graph is valid + connected ---------------------------
  {
    for (let s = 1; s <= 6; s++) {
      const m = RunMap.generatePhase(0, s * 12345 + 7);
      r.ok(m && m.nodes.length > 4, "phase " + s + ": a non-trivial graph");
      r.ok(m.row0.length >= 1, "phase " + s + ": has at least one opening node");
      const boss = m.byId[m.bossId];
      r.eq(boss.type, "boss", "phase " + s + ": the top node is the boss");
      r.ok(boss.piles >= 1, "phase " + s + ": the boss shows a pile count");
      // every non-boss node has an outgoing edge (can reach upward).
      r.ok(m.nodes.every(n => n.type === "boss" || n.next.length >= 1), "phase " + s + ": every node leads upward");
      // the boss is reachable from a row-0 node (BFS).
      const seen = new Set(), q = m.row0.slice();
      while (q.length) { const id = q.shift(); if (seen.has(id)) continue; seen.add(id); (m.byId[id].next || []).forEach(x => q.push(x)); }
      r.ok(seen.has(m.bossId), "phase " + s + ": the boss is reachable from the start");
      // deal/boss nodes carry a pile count; pickups/packs carry the phase suit.
      r.ok(m.nodes.filter(n => n.type === "deal").every(n => n.piles >= 1), "phase " + s + ": deals show pile counts");
      r.ok(m.nodes.some(n => n.type === "deal"), "phase " + s + ": has at least one deal node");
    }
  }

  // ---- generateRun: all 3 phases stacked into ONE continuous graph --------
  {
    for (let s = 1; s <= 4; s++) {
      const run = RunMap.generateRun(s * 9001 + 3);
      r.ok(run && run.nodes.length > 12, "run " + s + ": a large combined graph");
      r.eq(run.phases.length, 3, "run " + s + ": three phases");
      // ids are unique across the whole run (namespaced per phase).
      const ids = run.nodes.map(n => n.id);
      r.eq(new Set(ids).size, ids.length, "run " + s + ": no duplicate ids across phases");
      // every node carries its phase + a global row; rows are stacked (♦ < ♣ < ♠).
      r.ok(run.nodes.every(n => n.phase >= 0 && n.phase <= 2 && typeof n.row === "number"), "run " + s + ": nodes carry phase + global row");
      r.ok(run.phases[0].rowStart < run.phases[1].rowStart && run.phases[1].rowStart < run.phases[2].rowStart, "run " + s + ": phases stack bottom→top");
      // the ♦ boss links straight into the ♣ openings (continuous path).
      const dBoss = run.byId[run.phases[0].bossId];
      r.ok(dBoss.next.length >= 1 && dBoss.next.every(id => run.byId[id].phase === 1), "run " + s + ": ♦ boss feeds the ♣ openings");
      const cBoss = run.byId[run.phases[1].bossId];
      r.ok(cBoss.next.every(id => run.byId[id].phase === 2), "run " + s + ": ♣ boss feeds the ♠ openings");
      // the run boss is the ♠ boss and is reachable from the ♦ start via BFS.
      r.eq(run.runBossId, run.phases[2].bossId, "run " + s + ": run boss = the ♠ boss");
      r.ok(run.byId[run.runBossId].next.length === 0, "run " + s + ": the ♠ boss is the terminal node");
      const seen = new Set(), q = run.row0.slice();
      while (q.length) { const id = q.shift(); if (seen.has(id)) continue; seen.add(id); (run.byId[id].next || []).forEach(x => q.push(x)); }
      r.ok(seen.has(run.runBossId), "run " + s + ": the ♠ boss is reachable from the ♦ start");
    }
  }

  // ---- a single-card node shows EXACTLY the card it grants ----------------
  {
    const c = CampaignState.create();
    const map = c.getMap();
    // any pickup (single-card) node carrying an id
    const pickup = map.nodes.find(n => n.type === "pickup" && n.id != null);
    r.ok(pickup, "the map has a single-card (pickup) node");
    const shown = c.previewPickupCard(pickup);
    r.ok(shown && shown.id != null, "previewPickupCard shows a concrete card (rank+suit)");
    const before = c.deckSize();
    const granted = c.resolvePickup(pickup);
    r.eq(granted.id, shown.id, "the card GRANTED is exactly the card SHOWN");
    r.eq(c.deckSize(), before + 1, "taking the single-card node adds exactly one card");
    // the committed card persists for display of the (now cleared) node.
    r.eq(c.nodeCard(pickup).id, shown.id, "the node keeps its committed card for display");
  }

  // ---- Phase 1 is a HARDCODED, swappable data definition ------------------
  {
    const def = RunMap.PHASE_DEFS[0];
    r.ok(def && def.suit === "♦", "Phase 1 has a hardcoded ♦ definition");
    // every edge endpoint is a real node id (no dangling edits).
    const ids = new Set(def.nodes.map(n => n.id));
    r.ok((def.edges || []).every(([f, t]) => ids.has(f) && ids.has(t)), "every edge endpoint is a real node");
    r.eq(def.nodes.filter(n => n.type === "start").length, 1, "exactly one start node");
    r.eq(def.nodes.filter(n => n.type === "boss").length, 1, "exactly one boss node");
    // the definition adapts into the same internal phase shape as the generator.
    const ph = RunMap.definitionToPhase(def, 0);
    r.eq(ph.suit, "♦", "adapted phase travels diamonds");
    r.eq(ph.row0.length, 1, "one opening (the bottom deal)");
    const open = ph.byId[ph.row0[0]];
    r.eq(open.type, "deal", "the opening is a deal");
    r.eq(open.piles, 5, "the opening deal is 5 piles");
    const boss = ph.byId[ph.bossId];
    r.eq(boss.type, "boss", "the top node is the boss");
    r.eq(boss.piles, 6, "the boss is 6 piles");
    r.eq(boss.next.length, 0, "the boss is terminal within the phase");
    // the boss is reachable from the opening (BFS over the adapted graph).
    const seen = new Set(), q = ph.row0.slice();
    while (q.length) { const id = q.shift(); if (seen.has(id)) continue; seen.add(id); (ph.byId[id].next || []).forEach(x => q.push(x)); }
    r.ok(seen.has(ph.bossId), "the boss is reachable from the opening");
    r.eq(seen.size, ph.nodes.length, "every node is reachable (no orphans)");
    // the three parallel deals 4/6/10 and the 9-pile continuation exist.
    const dealPiles = ph.nodes.filter(n => n.type === "deal").map(n => n.piles).sort((a, b) => a - b);
    r.eq(dealPiles.join(","), "4,5,6,7,9,10", "deals are exactly 4,5,6,7,9,10 piles");
    r.eq(ph.nodes.filter(n => n.type === "store").length, 4, "four store chokepoints (mid, recombine, two flanking)");
    // +1 → pickup (single card); +2 or more → pack with that count.
    const packs = ph.nodes.filter(n => n.type === "pack").map(n => n.packCount).sort((a, b) => a - b);
    r.eq(packs.join(","), "3,3,3,5,5,5", "packs are the +3/+5 nodes (three each)");
    r.eq(ph.nodes.filter(n => n.type === "pickup").length, 10, "ten single-card (+1) nodes");
  }

  // ---- the EXPLICIT map spec (node list + edge list + tiers) maps 1:1 -----
  {
    // A tiny worked spec: start → deal → FORK (card/pack) → RECOMBINE (card) →
    // store → boss. Mirrors the authoring template exactly.
    const spec = {
      suit: "♦",
      nodes: [
        { id: "S",  type: "start",            tier: 0, x: 0.5 },
        { id: "D1", type: "deal",  piles: 5,  tier: 1, x: 0.5 },
        { id: "L",  type: "card",  card: "K♦", tier: 2, x: 0.3 },
        { id: "R",  type: "pack",  add: 3,    tier: 2, x: 0.7 },
        { id: "M",  type: "card",             tier: 3, x: 0.5 },
        { id: "ST", type: "store",            tier: 4, x: 0.5 },
        { id: "B",  type: "boss",  piles: 6,  tier: 5, x: 0.5 },
      ],
      edges: [
        ["S", "D1"],
        ["D1", "L"], ["D1", "R"],     // FORK
        ["L", "M"], ["R", "M"],       // RECOMBINE
        ["M", "ST"], ["ST", "B"],
      ],
    };
    const ph = RunMap.parseMapSpec(spec, 0);
    const id = name => ["S", "D1", "L", "R", "M", "ST", "B"].indexOf(name);   // author order → number
    // start is not a drawn node; its out-edge defines the single opening.
    r.eq(ph.nodes.length, 6, "the start node is not rendered (6 real nodes)");
    r.eq(ph.row0.length, 1, "one opening (start's out-edge)");
    r.eq(ph.byId[ph.row0[0]].piles, 5, "the opening is the 5-pile deal");
    // tiers normalize so the lowest real node is row 0 (deal at tier 1 → row 0).
    r.eq(ph.byId[id("D1")].row, 0, "tier 1 normalizes to row 0");
    r.eq(ph.byId[id("B")].row, 4, "the boss tier 5 → row 4 (top)");
    // FORK: the deal points at BOTH branch nodes.
    r.eq(ph.byId[id("D1")].next.slice().sort().join(","), [id("L"), id("R")].sort().join(","), "deal forks to card + pack");
    // node params translate: card→pickup, pack→pack +3, forced card carried.
    r.eq(ph.byId[id("L")].type, "pickup", "a +1 card is a single pickup");
    r.eq(ph.byId[id("L")].forceCard, "K♦", "the forced card id is carried through");
    r.eq(ph.byId[id("R")].type, "pack", "a +N card is a pack");
    r.eq(ph.byId[id("R")].packCount, 3, "the pack carries its +3 count");
    // RECOMBINE: both branches point at the same node M.
    const into = ph.nodes.filter(n => n.next.indexOf(id("M")) !== -1).map(n => n.id).sort();
    r.eq(into.join(","), [id("L"), id("R")].sort().join(","), "card + pack recombine into one node");
    // boss is terminal + the boss-of-phase.
    r.eq(ph.bossId, id("B"), "the boss node is the phase boss");
    r.eq(ph.byId[id("B")].next.length, 0, "the boss is terminal within the phase");
    // reachable from the opening (BFS).
    const seen = new Set(), q = ph.row0.slice();
    while (q.length) { const n = q.shift(); if (seen.has(n)) continue; seen.add(n); (ph.byId[n].next || []).forEach(x => q.push(x)); }
    r.ok(seen.has(ph.bossId) && seen.size === ph.nodes.length, "every node reachable, boss included");
  }

  // ---- every +1 node locks an EXACT card at generation, distinct + fixed --
  {
    const c = CampaignState.create();
    const map = c.getMap();
    const rankLabel = card => (DeckManager.RANKS.find(r => r.value === card.currentRank) || {}).label;
    const pickups = map.nodes.filter(n => n.type === "pickup");
    r.ok(pickups.length > 0, "the map has +1 single-card nodes");
    // EVERY +1 node shows an exact card up front (no lazy/face-down nodes).
    r.ok(pickups.every(n => !!c.nodeCard(n)), "every +1 node is locked to a card at generation");
    // its phase suit (Phase 1 +1 nodes are diamonds).
    r.ok(pickups.filter(n => n.phase === 0).every(n => c.nodeCard(n).suit === "♦"), "Phase 1 +1 nodes lock diamonds");
    // the locked cards are DISTINCT (no two +1 nodes show the same identity).
    const ids = pickups.map(n => c.nodeCard(n).id);
    r.eq(new Set(ids).size, ids.length, "no two +1 nodes lock the same card");
    // FIXED for the run: re-reading (re-render) returns the same card.
    const n0 = pickups[0], first = c.nodeCard(n0).id;
    c.nodeCard(n0); c.previewPickupCard(n0);
    r.eq(c.nodeCard(n0).id, first, "a +1 node's card never re-randomizes");
    // taking it adds EXACTLY that locked card.
    const before = c.deckSize();
    const granted = c.resolvePickup(n0);
    r.eq(granted.id, first, "taking a +1 node adds exactly its locked card");
    r.eq(c.deckSize(), before + 1, "the deck grew by exactly one");
  }

  // ---- a +1 node can FORCE a specific card (when free) --------------------
  {
    const rankLabel = card => (DeckManager.RANKS.find(r => r.value === card.currentRank) || {}).label;
    // Find a campaign with a free diamond rank to force (a +1 node, incl. mixed
    // nodes in later phases, may have already claimed a diamond). Retry to dodge
    // the rare run where all 13 diamonds happen to be locked.
    let c, freeRank;
    for (let attempt = 0; attempt < 25 && !freeRank; attempt++) {
      c = CampaignState.create();
      const lockedDiamonds = new Set(c.getMap().nodes.filter(n => n.type === "pickup")
        .map(n => c.nodeCard(n)).filter(card => card && card.suit === "♦").map(rankLabel));
      freeRank = DeckManager.RANKS.map(r => r.label).find(l => !lockedDiamonds.has(l));
    }
    r.ok(freeRank, "found a free diamond rank to force");
    const card = c.previewPickupCard({ id: 99999, phase: 0, forceCard: freeRank + "♦" });
    r.ok(card && card.suit === "♦", "the forced card resolves to a diamond");
    r.eq(rankLabel(card), freeRank, "forceCard pins the requested rank");
    const granted = c.resolvePickup({ id: 99999, phase: 0, forceCard: freeRank + "♦" });
    r.eq(granted.id, card.id, "the forced card shown is the forced card granted");
  }

  // ---- packs never draw a card a +1 node is showing (reserved) -----------
  {
    const c = CampaignState.create();
    const map = c.getMap();
    const lockedIds = new Set(map.nodes.filter(n => n.type === "pickup").map(n => c.nodeCard(n).id));
    // open several packs; none of their cards should be a +1 node's locked card.
    let clean = true;
    for (let i = 0; i < 6; i++) {
      const cards = c.resolvePack({ type: "pack", packCount: 3, mixed: false });
      if (cards.some(x => lockedIds.has(x.id))) clean = false;
    }
    r.ok(clean, "packs never reveal a card reserved by a +1 node");
  }

  // ---- moveToNode across a phase boss syncs the phase/suit ----------------
  {
    const c = CampaignState.create();
    const map = c.getMap();
    r.ok(map && map.phases && map.phases.length === 3, "getMap() returns the continuous 3-phase run");
    // moving onto a ♣ (phase-1) node flips the campaign into phase ♣.
    const clubNode = map.nodes.find(n => n.phase === 1);
    c.moveToNode(clubNode.id);
    r.eq(c.getPhaseIndex(), 1, "moveToNode onto a ♣ node → phase 1");
    r.eq(c.phaseSuit(), "♣", "…and the suit follows to clubs");
  }

  // ---- layoutForPiles: any pile count → a valid board ---------------------
  {
    const c = CampaignState.create();
    for (let n = 2; n <= 9; n++) {
      const lay = c.layoutForPiles(n);
      r.eq(lay.piles, n, "layoutForPiles(" + n + ") totals " + n + " piles");
      r.ok(lay.cols.every(x => x >= 1), "no empty columns for " + n + " piles");
      r.ok(lay.rows <= 4, "tallest column ≤ 4 for " + n + " piles (board sizing holds)");
    }
  }

  // ---- serialize / restore round-trips the run state (schema 2) -----------
  {
    const c = CampaignState.create();
    c.resolvePickup({ type: "pickup" });
    c.advancePhase();                       // → phase ♣
    const wire = JSON.parse(JSON.stringify(c.serialize()));
    r.eq(wire.schema, 2, "serialize carries schema 2");
    const c2 = CampaignState.create();
    r.ok(c2.restore(wire), "restore accepts a schema-2 snapshot");
    r.eq(c2.getPhaseIndex(), 1, "phase restored");
    r.eq(c2.phaseSuit(), "♣", "phase suit restored");
    r.eq(c2.deckSize(), c.deckSize(), "accumulated deck size restored");
    r.ok(!c2.restore({ schema: 1, baseDeck: new Array(52).fill({}) }), "a schema-1 (old structure) save is rejected");
  }

  // ---- reset() returns to a fresh phase-0 run -----------------------------
  {
    const c = CampaignState.create();
    c.resolvePack({ type: "pack", packCount: 4 });
    c.advancePhase();
    c.reset();
    r.eq(c.getPhaseIndex(), 0, "reset → phase 0");
    r.eq(c.deckSize(), 13, "reset → 13 hearts");
    r.eq(c.phaseSuit(), "♦", "reset → diamonds phase");
  }

  return r.summary();
}
