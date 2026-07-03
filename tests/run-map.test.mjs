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
  // (map specials pinned OFF — this block asserts the NORMAL-card contract;
  //  the Joker/Blank special contract has its own block below)
  {
    const c = CampaignState.create();
    c._setMapSpecialRoll(() => null);
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
    c._setMapSpecialRoll(() => null);   // normal-card contract (specials below)
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
      c._setMapSpecialRoll(() => null);   // normal-card contract (specials below)
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

  // ---- the GENERATED stage graph meets the full map spec ------------------
  {
    for (let s = 1; s <= 6; s++) {
      const entry = 13;
      const m = RunMap.generateStage(0, s * 12345 + 7, entry);
      r.ok(m && m.nodes.length > 4, "stage " + s + ": a non-trivial graph");
      r.ok(m.row0.length >= 1, "stage " + s + ": has at least one opening node");
      const boss = m.byId[m.bossId];
      r.eq(boss.type, "boss", "stage " + s + ": the top node is the boss");
      r.ok(boss.piles >= 1, "stage " + s + ": the boss shows a pile count");
      r.ok(m.nodes.every(n => n.type === "boss" || n.next.length >= 1), "stage " + s + ": every node leads upward");
      const seen = new Set(), q = m.row0.slice();
      while (q.length) { const id = q.shift(); if (seen.has(id)) continue; seen.add(id); (m.byId[id].next || []).forEach(x => q.push(x)); }
      r.ok(seen.has(m.bossId), "stage " + s + ": the boss is reachable from the start");
      r.ok(m.nodes.filter(n => n.type === "deal").every(n => n.piles >= 1), "stage " + s + ": deals show pile counts");
      // The FULL spec holds (route cards, deal counts, stores, difficulty bands
      // at both deck extremes) — the same validator the generator accepted with.
      const v = RunMap.validateStage(m, entry, { phaseIndex: 0,
        bandHiExtra: (m._gen ? m._gen.relax : 0) * RunMap.GEN_CONFIG.relaxBandStep });
      r.ok(v.ok, "stage " + s + ": validateStage passes (" + (v.errors[0] || "") + ")");
      r.ok(v.report.cards[0] >= 11, "stage " + s + ": every route collects ≥11 cards");
      r.ok(v.report.cards[0] <= 15, "stage " + s + ": a route ≤15 cards exists");
      r.ok(v.report.dealsPerRoute[0] >= 3 && v.report.dealsPerRoute[1] <= 5, "stage " + s + ": 3–5 deals on every route");
      // 2–3 stores per stage.
      r.ok(v.report.stores >= 2 && v.report.stores <= 3, "stage " + s + ": has 2–3 stores (" + v.report.stores + ")");
      // ≥2 starting nodes (player picks where to start).
      r.ok(m.row0.length >= 2, "stage " + s + ": has " + m.row0.length + " starting nodes (≥2)");
      // EXACTLY ONE boss, terminal on the top row (twin bosses removed — they
      // were a fork with no information behind the choice).
      const bosses = m.nodes.filter(n => n.type === "boss");
      r.eq(bosses.length, 1, "stage " + s + ": exactly 1 boss");
      r.ok(bosses.every(n => n.row === m.bossRow && n.next.length === 0), "stage " + s + ": the boss is terminal on the top row");
      r.eq(m.bossIds.length, 1, "stage " + s + ": bossIds lists the single boss");
      // The map actually forks (braiding is emergent from overlapping paths).
      // Fake/dominated forks are no longer hard errors — the StS-style random
      // rolls + vetoes replace the old construction gates (fakes are a soft
      // warning only), so we no longer assert every fork is DISTINCT.
      r.ok(v.report.forks.length >= 1, "stage " + s + ": the map actually forks");
      // STORE ACCESS: no start is locked out of ALL stores (reaches ≥1).
      r.ok(v.report.storeReach.every(sr => sr.reaches >= 1),
        "stage " + s + ": every start reaches at least one store (not store-locked)");
      // Row widths are informational now (no fixed 3-4 band under random paths),
      // but the openings row still has ≥2 starts and the boss row ≤2.
      const widths = v.report.widthPerRow;
      r.ok(widths[0] >= 2, "stage " + s + ": ≥2 opening nodes (" + widths[0] + ")");
      r.ok(widths[m.bossRow] <= 2, "stage " + s + ": ≤2 boss nodes (" + widths[m.bossRow] + ")");
      // PLANARITY: edges never swap sides (monotone lanes ⇒ no crossings).
      let swaps = 0;
      const rows = {};
      m.nodes.forEach(n => (rows[n.row] = rows[n.row] || []).push(n));
      for (const rr in rows) {
        const A = rows[rr].slice().sort((a, b) => a.lane - b.lane);
        for (let i = 0; i < A.length; i++) for (let k = i + 1; k < A.length; k++) {
          if (!A[i].next.length || !A[k].next.length) continue;
          const maxI = Math.max(...A[i].next.map(id => m.byId[id].lane));
          const minK = Math.min(...A[k].next.map(id => m.byId[id].lane));
          if (maxI > minK) swaps++;
        }
      }
      r.eq(swaps, 0, "stage " + s + ": no edge ever swaps sides (planar by construction)");
      // Adjacent lanes only, one row up (the boss-row merge may span lanes —
      // it converges on a centered node, which cannot cross anything).
      r.ok(m.nodes.every(n => n.next.every(id => {
        const t = m.byId[id];
        if (t.row !== n.row + 1) return false;
        if (t.row === m.bossRow) return true;
        return Math.abs((t.lane != null ? t.lane : 1) - (n.lane != null ? n.lane : 1)) <= 1;
      })), "stage " + s + ": edges go one row up, same/adjacent lane");
      // The run's FIRST deal sits at row 0 in its band at deck 13.
      const first = m.byId[m.row0[0]];
      r.eq(first.type, "deal", "stage " + s + ": stage 0 opens on the run's first deal");
      const d0 = (entry - first.piles) / first.piles;
      r.ok(d0 >= 1.25 - 1e-9 && d0 <= 1.75 + 1e-9, "stage " + s + ": first deal difficulty " + d0.toFixed(2) + " ∈ [1.25,1.75]");
    }
  }

  // ---- later stages generate against their REAL entry deck ----------------
  {
    for (const [p, entry] of [[1, 27], [2, 40]]) {
      const m = RunMap.generateStage(p, 4242 + p, entry);
      // a stage may carry a LOGGED relax step (the band top stretches when
      // integer piles + card floors leave no strict solution) — honor it
      const bandX = (m._gen ? m._gen.relax : 0) * RunMap.GEN_CONFIG.relaxBandStep;
      const v = RunMap.validateStage(m, entry, { phaseIndex: p, bandHiExtra: bandX });
      r.ok(v.ok, "stage " + p + " (entry " + entry + "): validateStage passes (" + (v.errors[0] || "") + ")");
      const boss = v.report.perDeal.find(d => d.type === "boss");
      const band = RunMap.GEN_CONFIG.bossBands[p];
      r.ok(boss.dMin >= band[0] - 1e-6 && boss.dMax <= band[1] + bandX + 1e-6,
        "stage " + p + ": boss difficulty [" + boss.dMin + "," + boss.dMax + "] inside its band [" + band + "] (+" + bandX + " logged relax)");
    }
  }

  // ---- every stage ends at a SINGLE boss all routes converge on ----------
  {
    const p = 1, entry = 26;
    for (let s2 = 1; s2 <= 5; s2++) {
      const m = RunMap.generateStage(p, s2 * 6007, entry);
      r.eq(m.bossIds.length, 1, "seed " + s2 + ": exactly one boss (twins removed)");
      const routes = RunMap.enumerateRoutes(m);
      r.ok(routes.every(rt => rt[rt.length - 1] === m.bossId), "seed " + s2 + ": every route converges on THE boss");
    }
  }

  // ---- generateRun: stages stack; later stages appear as they're entered --
  {
    for (let s = 1; s <= 4; s++) {
      const run = RunMap.generateRun(s * 9001 + 3, [13, 27, 40]);
      r.ok(run && run.nodes.length > 12, "run " + s + ": a large combined graph");
      r.eq(run.phases.length, 3, "run " + s + ": three phases when all entries are known");
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
    // LAZY: with only stage 0 entered, only stage 0 exists — and no node can
    // falsely count as the run boss until the ♠ stage is generated.
    const partial = RunMap.generateRun(777, [13]);
    r.eq(partial.phases.length, 1, "a fresh run generates only the ♦ stage");
    r.eq(partial.runBossId, null, "no run boss until the ♠ stage exists");
    const two = RunMap.generateRun(777, [13, 26]);
    r.eq(two.phases.length, 2, "entering ♣ generates the second stage");
    r.eq(two.phases[0].bossId, partial.phases[0].bossId, "the ♦ stage regenerates IDENTICALLY (same seed + entry)");
    r.eq(two.runBossId, null, "still no run boss before the ♠ stage");
  }

  // ---- a single-card node shows EXACTLY the card it grants ----------------
  // (The braided generator's card floor makes every generated draft node a
  //  pack, so +1 CARD nodes now come from authored definitions — the preview/
  //  grant contract is exercised on a node object directly.)
  {
    const c = CampaignState.create();
    c._setMapSpecialRoll(() => null);   // normal-card contract (specials below)
    const pickup = { id: 900001, type: "pickup", suit: "♦", mixed: false };
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
    r.eq(ph.nodes.filter(n => n.type === "store").length, 5, "five store chokepoints (after-D1, mid, recombine, two flanking)");
    // The opening deal (D1) feeds ONLY the new store, which fans back out to the
    // two original D2 forks (a +3 pack and a +5 pack).
    const d1 = open;                                  // the row-0 opening (5-pile deal)
    r.eq(d1.next.length, 1, "D1 links to exactly one node");
    const afterD1 = ph.byId[d1.next[0]];
    r.eq(afterD1.type, "store", "the node right after D1 is the new store");
    r.eq(afterD1.next.length, 2, "the after-D1 store fans out to the two D2 forks");
    r.eq(afterD1.next.map(id => ph.byId[id].type).sort().join(","), "pack,pack", "both D2 forks are packs (the +3 / +5)");
    // +1 → pickup (single card); +2 or more → pack with that count.
    const packs = ph.nodes.filter(n => n.type === "pack").map(n => n.packCount).sort((a, b) => a - b);
    r.eq(packs.join(","), "3,3,3,5,5,5", "packs are the +3/+5 nodes (three each)");
    r.eq(ph.nodes.filter(n => n.type === "pickup").length, 9, "nine single-card (+1) nodes (D-13-2 / c_1i was removed)");
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

  // ---- +1 nodes lock an EXACT card, distinct + fixed -----------------------
  // (The braided generator's card floor makes every generated draft node a
  //  pack; the +1 lock contract is exercised on node objects directly —
  //  authored maps route through the same commit/preview API.)
  {
    const c = CampaignState.create();
    c._setMapSpecialRoll(() => null);   // normal-card contract (specials below)
    const nA = { id: 910001, type: "pickup", suit: "♦", mixed: false };
    const nB = { id: 910002, type: "pickup", suit: "♦", mixed: false };
    const a = c.previewPickupCard(nA), b = c.previewPickupCard(nB);
    r.ok(a && b, "+1 nodes lock a concrete card on first preview");
    // The node's phase suit wins while the suit still has unreserved cards. A
    // fresh campaign's own card-heavy map occasionally reserves ALL 13 diamonds
    // up front (14-row maps make +1 nodes common), which triggers the
    // documented any-suit fallback — so sample a few fresh campaigns: the suit
    // lock must hold on at least one (a real suit-lock bug would miss on all).
    let suitHeld = a.suit === "♦";
    for (let t = 0; t < 5 && !suitHeld; t++) {
      const c2 = CampaignState.create();
      c2._setMapSpecialRoll(() => null);
      const p2 = c2.previewPickupCard({ id: 910050 + t, type: "pickup", suit: "♦", mixed: false });
      suitHeld = !!p2 && p2.suit === "♦";
    }
    r.ok(suitHeld, "a ♦ +1 node locks a diamond (while the suit has free cards)");
    r.ok(a.id !== b.id, "no two +1 nodes lock the same card");
    // FIXED for the run: re-reading (re-render) returns the same card.
    const first = c.nodeCard(nA).id;
    c.nodeCard(nA); c.previewPickupCard(nA);
    r.eq(c.nodeCard(nA).id, first, "a +1 node's card never re-randomizes");
    // taking it adds EXACTLY that locked card.
    const before = c.deckSize();
    const granted = c.resolvePickup(nA);
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
    // Specials pinned OFF, and the map re-locked under the pin: the fresh map's
    // +1 nodes committed at create() (production rolls could lock a Joker/Blank
    // sentinel, which has no base-card id to reserve — not this test's subject).
    c._setMapSpecialRoll(() => null);
    c.startNewRun();
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

  // ---- stages generate as they're ENTERED (real deck size at generation) --
  {
    const c = CampaignState.create();
    let map = c.getMap();
    r.ok(map && map.phases && map.phases.length === 1, "a fresh run's map holds only the ♦ stage");
    r.ok(!c.isRunBoss(map.phases[0].bossId), "the ♦ boss is NOT the run boss (map still grows)");
    // grow the deck a little, then fell the ♦ boss → the ♣ stage generates
    // against the REAL deck size at that moment.
    c.resolvePack({ type: "pack", packCount: 5, suit: "♦" });
    c.resolvePack({ type: "pack", packCount: 5, suit: "♦" });
    const deckAtEntry = c.deckSize();
    // clear via the LAST boss id — with twin bosses this exercises the
    // either-boss membership path (a single boss is just bossIds[0]).
    const dBossIds = map.phases[0].bossIds || [map.phases[0].bossId];
    c.markNodeCleared(dBossIds[dBossIds.length - 1]);
    map = c.getMap();
    r.eq(map.phases.length, 2, "clearing EITHER ♦ boss generates the ♣ stage");
    const wire = JSON.parse(JSON.stringify(c.serialize()));
    r.eq(wire.stageEntryDecks[1], deckAtEntry, "the ♣ stage's entry deck is the REAL deck size when it generated");
    // moving onto a ♣ (phase-1) node flips the campaign into phase ♣.
    const clubNode = map.nodes.find(n => n.phase === 1);
    c.moveToNode(clubNode.id);
    r.eq(c.getPhaseIndex(), 1, "moveToNode onto a ♣ node → phase 1");
    r.eq(c.phaseSuit(), "♣", "…and the suit follows to clubs");
    // the grown map restores IDENTICALLY from the save (seed + entry decks).
    const c2 = CampaignState.create();
    r.ok(c2.restore(wire), "a mid-run save with a grown map restores");
    const m2 = c2.getMap();
    r.eq(m2.phases.length, 2, "the restored map holds the same two stages");
    r.eq(m2.phases[1].bossId, map.phases[1].bossId, "the restored ♣ stage is IDENTICAL (same seed + entry deck)");
    // felling the ♣ then ♠ bosses completes the ladder; only the ♠ boss is the
    // run boss. Grow the deck like a real ♣ traversal would (every route
    // collects 11+ cards) — the ♠ stage generates against that REAL deck.
    c.resolvePack({ type: "pack", packCount: 5, suit: "♣" });
    c.resolvePack({ type: "pack", packCount: 5, suit: "♣" });
    c.markNodeCleared(map.phases[1].bossId);
    const m3 = c.getMap();
    r.eq(m3.phases.length, 3, "clearing the ♣ boss generates the ♠ stage");
    r.ok(m3.phases[2].bossIds.every(id => c.isRunBoss(id)), "EVERY ♠ boss is a run boss (either one wins)");
    const v = RunMap.validateStage ? null : null;   // (stage validity is covered above)
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

  // ---- MAP SPECIALS: Joker + Blank as +1 pickups (roll pinned) -------------
  {
    // JOKER on a +1 node: previews face-up as a Joker, grants an OWNED Joker.
    const c = CampaignState.create();
    c._setMapSpecialRoll(() => true);   // every special roll → Joker
    const nJ = { id: 920001, type: "pickup", suit: "♦", mixed: false };
    const shown = c.previewPickupCard(nJ);
    r.ok(shown && shown.joker, "a special +1 node previews as a JOKER (shown on the map)");
    const before = c.deckSize();
    const granted = c.resolvePickup(nJ);
    r.ok(granted && granted.joker, "taking the node grants a Joker");
    r.eq(c.deckSize(), before + 1, "the Joker joins the deck like any card (+1)");
    r.ok(c.getRunDeck().some(x => x.joker), "the run deck holds the Joker");
    r.eq(c.jokerCount(), 1, "jokerCount() sees the owned Joker (histogram feed)");
    // A save round-trips both the owned Joker and any still-locked sentinel.
    const wire = JSON.parse(JSON.stringify(c.serialize()));
    const c2 = CampaignState.create();
    r.ok(c2.restore(wire), "a save with an owned Joker restores");
    r.eq(c2.jokerCount(), 1, "the restored deck still holds the Joker");
    r.eq(c2.deckSize(), c.deckSize(), "restored deck size matches");
    r.ok(c2.nodeCard(nJ) && c2.nodeCard(nJ).joker, "the cleared node still displays its Joker after restore");
  }
  {
    // BLANK on a +1 node: previews face-up as a Blank; grants a REMOVAL, not a
    // card — the deck only changes when removeDeckCard applies the choice.
    const c = CampaignState.create();
    c._setMapSpecialRoll(() => false);   // every special roll → Blank
    const nB = { id: 920002, type: "pickup", suit: "♦", mixed: false };
    const shown = c.previewPickupCard(nB);
    r.ok(shown && shown.blank, "a special +1 node previews as a BLANK (shown on the map)");
    r.ok(c.nodeCard(nB) && c.nodeCard(nB).blank, "the committed Blank persists for node display");
    const before = c.deckSize();
    const granted = c.resolvePickup(nB);
    r.ok(granted && granted.blank, "resolving returns the Blank marker");
    r.eq(c.deckSize(), before, "a Blank adds NOTHING to the deck");
    // Its effect — choose a card to remove; the deck permanently shrinks by 1.
    const victim = c.getRunDeck()[0];
    r.ok(c.removeDeckCard(victim.id), "removeDeckCard removes the chosen card");
    r.eq(c.deckSize(), before - 1, "the deck permanently shrank by one");
    r.ok(!c.getRunDeck().some(x => x.id === victim.id), "the removed card is gone");
    r.ok(!c.removeDeckCard(victim.id), "removing it again fails (already gone)");
  }
  // ---- MAP SPECIALS: Joker + Blank inside map packs ------------------------
  {
    const c = CampaignState.create();
    c._setMapSpecialRoll(() => true);
    const before = c.deckSize();
    const cards = c.resolvePack({ type: "pack", packCount: 3, suit: "♦" });
    r.eq(cards.length, 3, "an all-special +3 pack still reveals 3 items");
    r.ok(cards.every(x => x.joker), "…all Jokers (roll pinned)");
    r.eq(c.deckSize(), before + 3, "every pack Joker joined the deck");
    r.eq(c.jokerCount(), 3, "jokerCount() reflects all three");
    c._setMapSpecialRoll(() => false);
    const blanks = c.resolvePack({ type: "pack", packCount: 2, suit: "♦" });
    r.eq(blanks.length, 2, "an all-Blank +2 pack reveals 2 items");
    r.ok(blanks.every(x => x.blank), "…both Blanks (roll pinned)");
    r.eq(c.deckSize(), before + 3, "Blanks added NOTHING to the deck");
  }
  // ---- MAP SPECIALS: a new run prunes stale Joker identities ---------------
  {
    const c = CampaignState.create();
    c._setMapSpecialRoll(() => true);
    c.resolvePickup({ id: 930001, type: "pickup", suit: "♦" });
    r.eq(c.jokerCount(), 1, "a Joker owned mid-run");
    c._setMapSpecialRoll(() => null);   // the fresh map's locks roll normally
    c.startNewRun();
    r.eq(c.jokerCount(), 0, "a new run's deck starts without the old Joker");
    r.ok(!c.getDeck().some(x => x.joker), "…and the stale Joker identity was pruned from the base deck");
  }

  return r.summary();
}
