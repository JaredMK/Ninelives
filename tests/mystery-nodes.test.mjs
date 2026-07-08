// MYSTERY (?) NODES: at generation each eligible node (pack/pickup/deal/store)
// rolls GEN_CONFIG.mysteryChance to DISPLAY as a "?" until the player arrives.
// Purely cosmetic — the node underneath generates completely normally. Bosses,
// home and pass points are always visible. The roll is deterministic from
// (runSeed, node id) so resume/extend regenerations hide the same nodes.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { RunMap, CampaignState } = loadGame();
  const r = makeRunner("mystery-nodes.test.mjs");
  const CHANCE = RunMap.GEN_CONFIG.mysteryChance;

  r.ok(CHANCE > 0 && CHANCE < 1, "mysteryChance is a real probability (registry value " + CHANCE + ")");

  // --- rate + exemptions across many real runs ----------------------------
  {
    let eligible = 0, hidden = 0, exemptHidden = 0, maps = 0;
    for (let s = 0; s < 40; s++) {
      const c = CampaignState.create();
      c.reset();
      const m = c.getMap();
      if (!m || !m.nodes.length) continue;
      maps++;
      for (const n of m.nodes) {
        const exempt = n.type === "boss" || n.type === "home" || n.type === "pass";
        if (exempt) { if (n.mystery) exemptHidden++; continue; }
        eligible++;
        if (n.mystery) hidden++;
      }
    }
    const rate = hidden / eligible;
    r.ok(maps >= 30, "generated " + maps + " runs to sweep (" + eligible + " eligible nodes)");
    r.eq(exemptHidden, 0, "bosses / home / pass points are NEVER mysteries");
    r.ok(Math.abs(rate - CHANCE) < 0.05,
      "~" + Math.round(CHANCE * 100) + "% of eligible nodes roll mystery (observed " + (rate * 100).toFixed(1) + "%)");
    r.ok(hidden > 0, "the roll actually fires (" + hidden + " mysteries across the sweep)");
  }

  // --- purely cosmetic: the node underneath is a normal node --------------
  {
    let bad = 0, checkedDeal = false;
    for (let s = 0; s < 10; s++) {
      const c = CampaignState.create();
      c.reset();
      const m = c.getMap();
      for (const n of m.nodes) {
        if (!n.mystery) continue;
        if (["pack", "pickup", "deal", "store"].indexOf(n.type) === -1) bad++;
        if (!(n.next || []).length && n.type !== "home") { /* top-row nodes feed the boss */ }
        if (n.type === "deal" && n.piles != null) checkedDeal = true;
        if (n.type === "pack" && !(n.packCount >= 2)) bad++;
      }
    }
    r.eq(bad, 0, "every mystery keeps its real type + fields intact underneath");
    r.ok(checkedDeal, "hidden deals still carry their piles (playable when revealed)");
  }

  // --- deterministic: same seed → same mysteries; extension-stable --------
  {
    const seed = 123456789;
    const a = RunMap.generateRun(seed, [13, 26, 39]);
    const b = RunMap.generateRun(seed, [13, 26, 39]);
    const setOf = m => m.nodes.filter(n => n.mystery).map(n => n.id).sort().join(",");
    r.eq(setOf(a), setOf(b), "identical regeneration hides the identical nodes (resume-safe)");
    // Stage 0 only vs the full run: stage-0 mysteries must match — extending
    // the map (endless / legacy grow-as-you-go) never re-rolls earlier stages.
    const solo = RunMap.generateRun(seed, [13]);
    const stage0 = m => m.nodes.filter(n => n.phase === 0 && n.mystery).map(n => n.id).sort().join(",");
    r.eq(stage0(solo), stage0(a), "extending the run never re-rolls an earlier stage's mysteries");
  }

  // --- campaign API: hidden until arrival, then revealed + persisted ------
  {
    let exercised = false;
    for (let s = 0; s < 20 && !exercised; s++) {
      const c = CampaignState.create();
      c.reset();
      const m = c.getMap();
      const myst = m.nodes.find(n => n.mystery && n.type !== "pass");
      if (!myst) continue;
      r.ok(c.nodeHidden(myst.id), "an un-visited mystery reports hidden");
      const plain = m.nodes.find(n => !n.mystery);
      r.ok(!c.nodeHidden(plain.id), "a normal node never reports hidden");
      c.revealNode(myst.id);
      r.ok(!c.nodeHidden(myst.id), "arrival (revealNode) unhides it");
      // persistence round-trip: the reveal survives save/restore
      const snap = c.serialize();
      const c2 = CampaignState.create();
      r.ok(c2.restore(snap), "the snapshot restores");
      r.ok(!c2.nodeHidden(myst.id), "…and the reveal persists across save/restore");
      // the same node in the regenerated map still CARRIES the mystery flag
      const n2 = c2.getMap().byId[myst.id];
      r.ok(n2 && !!n2.mystery, "…while the regenerated node still carries its mystery roll");
      // an untouched mystery elsewhere stays hidden after restore
      const other = c2.getMap().nodes.find(n => n.mystery && n.id !== myst.id);
      if (other) r.ok(c2.nodeHidden(other.id), "an untouched mystery stays hidden after restore");
      exercised = true;
    }
    r.ok(exercised, "found a mystery node to exercise the campaign API");
  }

  // --- moving onto / clearing a mystery also unhides it --------------------
  {
    let exercised = false;
    for (let s = 0; s < 20 && !exercised; s++) {
      const c = CampaignState.create();
      c.reset();
      const m = c.getMap();
      const myst = m.nodes.find(n => n.mystery && n.row === 0);
      if (!myst) continue;
      c.moveToNode(myst.id);
      r.ok(!c.nodeHidden(myst.id), "standing on a mystery unhides it (current position is never a ?)");
      c.markNodeCleared(myst.id);
      r.ok(!c.nodeHidden(myst.id), "a cleared mystery stays face-up");
      exercised = true;
    }
    r.ok(exercised, "found a row-0 mystery to walk onto");
  }

  return r.summary();
}
