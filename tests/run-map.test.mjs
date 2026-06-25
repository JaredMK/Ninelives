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
