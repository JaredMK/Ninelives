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
    const added = c.resolvePack({ type: "pack", packCount: 3, mixed: false });
    r.eq(added.length, 3, "a +3 pack adds three cards");
    r.eq(c.deckSize(), before + 4, "deck size is start + pickup + pack");
    // No duplicate ids (the draft is a subset of distinct identities).
    const ids = c.getRunDeck().map(x => x.id);
    r.eq(new Set(ids).size, ids.length, "the draft has no duplicate card ids");
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
    // every edge points at a real node id (no dangling edits).
    const ids = new Set(def.nodes.map(n => n.id));
    r.ok(def.nodes.every(n => (n.next || []).every(t => ids.has(t))), "every edge targets a real node");
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
    r.eq(ph.nodes.filter(n => n.type === "pickup").length, 6, "six single-card (+1) nodes");
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
