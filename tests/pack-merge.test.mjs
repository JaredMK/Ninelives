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
        if (n.type === "pass") {
          passes++;
          if (n.packCount != null || !(n.next || []).length) badPass++;
        }
        if (n.type !== "pack" || !n.next || n.next.length !== 1) continue;
        let cur = m.byId[n.next[0]];
        while (cur && cur.type === "pass" && cur.next.length === 1) cur = m.byId[cur.next[0]];
        if (cur && cur.type === "pack" && (parents[cur.id] || []).length === 1) corridorsLeft++;
      }
    }
    r.ok(maps >= 30, "generated " + maps + " runs to sweep");
    r.ok(passes > 0, "the merge fires on real maps (" + passes + " pass points across the sweep)");
    r.eq(corridorsLeft, 0, "no forced pack→pack corridor survives generation");
    r.eq(badPass, 0, "every pass point is edge-connected and grants nothing");
  }

  // --- legalNextNodes expands THROUGH pass points --------------------------
  {
    let checked = false;
    for (let s = 0; s < 40 && !checked; s++) {
      const c = CampaignState.create();
      c.reset();
      const m = c.getMap();
      const pass = m.nodes.find(n => n.type === "pass");
      if (!pass) continue;
      // stand on the pass's parent (the merged pack) and read the legal nexts
      const parent = m.nodes.find(n => (n.next || []).indexOf(pass.id) !== -1);
      c.moveToNode(parent.id);
      const legal = c.legalNextNodes();
      r.ok(!legal.some(n => n.type === "pass"), "pass points are never legal destinations");
      const beyond = (pass.next || [])[0];
      // walk the chain end to find the true beyond set
      let cur = pass;
      while (cur && cur.type === "pass" && cur.next.length === 1 && m.byId[cur.next[0]].type === "pass") cur = m.byId[cur.next[0]];
      const target = (cur.next || []).map(id => m.byId[id]).filter(n => n && n.type !== "pass");
      r.ok(target.every(t => legal.some(l => l.id === t.id)),
        "the node(s) beyond the corridor are offered instead");
      checked = true;
    }
    r.ok(checked, "found a pass corridor to exercise within the sweep");
  }

  return r.summary();
}
