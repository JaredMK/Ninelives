// FORCED PACK-CHAIN MERGE (map generation post-pass): corridor packs collapse
// into one bigger pack; freed slots become PASS points the marker glides past.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { RunMap, CampaignState } = loadGame();
  const r = makeRunner("pack-merge.test.mjs");

  // --- unit: a hand-built corridor merges fully ---------------------------
  {
    // A(pack2) -> B(pack3) -> C(pack4) -> D(deal); B,C each single-parent.
    const nodes = [
      { id: 1, type: "pack", packCount: 2, add: 2, row: 0, next: [2] },
      { id: 2, type: "pack", packCount: 3, add: 3, row: 1, next: [3] },
      { id: 3, type: "pack", packCount: 4, add: 4, row: 2, next: [4] },
      { id: 4, type: "deal", row: 3, next: [] },
    ];
    const ph = { nodes, byId: Object.fromEntries(nodes.map(n => [n.id, n])) };
    RunMap.mergeForcedPackChains(ph);
    r.eq(nodes[0].packCount, 9, "the whole chain sums into the first pack (2+3+4)");
    r.eq(nodes[1].type, "pass", "the middle pack became a pass point");
    r.eq(nodes[2].type, "pass", "…and the third");
    r.ok(nodes[1].packCount == null && nodes[2].packCount == null, "pass points grant nothing");
    r.eq(nodes[3].type, "deal", "the deal beyond the corridor is untouched");
    r.ok(nodes[1].next.length === 1 && nodes[2].next.length === 1, "pass points keep their edges (routes hold)");
  }
  {
    // NOT forced: B has a second parent → no merge.
    const nodes = [
      { id: 1, type: "pack", packCount: 2, add: 2, row: 0, next: [3] },
      { id: 2, type: "deal", row: 0, next: [3] },
      { id: 3, type: "pack", packCount: 3, add: 3, row: 1, next: [] },
    ];
    const ph = { nodes, byId: Object.fromEntries(nodes.map(n => [n.id, n])) };
    RunMap.mergeForcedPackChains(ph);
    r.eq(nodes[0].packCount, 2, "a two-parent pack is NOT absorbed (the other route has a choice)");
    r.eq(nodes[2].type, "pack", "…and stays a pack");
  }
  {
    // NOT packs: pickup -> pack corridors never merge.
    const nodes = [
      { id: 1, type: "pickup", add: 1, row: 0, next: [2] },
      { id: 2, type: "pack", packCount: 3, add: 3, row: 1, next: [] },
    ];
    const ph = { nodes, byId: Object.fromEntries(nodes.map(n => [n.id, n])) };
    RunMap.mergeForcedPackChains(ph);
    r.eq(nodes[0].type, "pickup", "pickups are untouched");
    r.eq(nodes[1].type, "pack", "…and so is the pack after them");
  }

  // --- generation invariants across many real maps ------------------------
  {
    let maps = 0, passes = 0, corridorsLeft = 0, badPass = 0;
    for (let s = 0; s < 40; s++) {
      const c = CampaignState.create();
      c.reset();
      const m = c.getMap();
      if (!m || !m.nodes.length) continue;
      maps++;
      const parents = {};
      m.nodes.forEach(n => (n.next || []).forEach(id => { (parents[id] = parents[id] || []).push(n.id); }));
      for (const n of m.nodes) {
        // v5.82: at genV >= 3 a merged-away pack becomes a MYSTERY, never an
        // empty pass point — no node on the map is allowed to grant nothing.
        if (n.type === "pass") passes++;
        if (n.type === "mystery") {
          if (n.packCount != null || n.add != null || n.suit != null || !(n.next || []).length) badPass++;
        }
        if (n.type !== "pack" || !n.next || n.next.length !== 1) continue;
        let cur = m.byId[n.next[0]];
        while (cur && cur.type === "pass" && cur.next.length === 1) cur = m.byId[cur.next[0]];
        if (cur && cur.type === "pack" && (parents[cur.id] || []).length === 1) corridorsLeft++;
      }
    }
    r.ok(maps >= 30, "generated " + maps + " runs to sweep");
    r.eq(passes, 0, "no empty pass point survives generation (" + passes + " found)");
    r.eq(corridorsLeft, 0, "no forced pack→pack corridor survives generation");
    r.eq(badPass, 0, "every mystery is edge-connected and carries no granted content");
  }

  // --- no node on a generated map is EMPTY ---------------------------------
  {
    let maps = 0, empties = 0;
    for (let s = 0; s < 40; s++) {
      const c = CampaignState.create();
      c.reset();
      const m = c.getMap();
      maps++;
      for (const n of m.nodes) {
        // Every type either runs a deal, opens a shop, grants cards, fires a
        // mystery event, or is home. "pass" was the one that did nothing.
        if (n.type === "pass") empties++;
      }
    }
    r.ok(maps >= 30, "generated " + maps + " campaigns to sweep");
    r.eq(empties, 0, "every node on the map does something");
  }

  return r.summary();
}
