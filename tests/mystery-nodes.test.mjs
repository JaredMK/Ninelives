// MYSTERY (?) NODES (MYST3): mystery is a FIRST-CLASS node type at genV ≥ 3.
// rollType's weighted table gains a "mystery" entry (GEN_CONFIG
// .mysteryTypeWeight) — the seeded mystery event IS the node's entire
// content: arrival grants ONLY the event outcome (no underlying node, no
// add/packCount, 0 cards / 0 deals in every route sum so the validator
// excludes it for free). genV < 3 (restored legacy saves) keeps the exact old
// behavior: the cosmetic n.mystery mask flag over a normal node — and a
// pre-v3 save's UNVISITED masked nodes are MIGRATED to first-class mysteries
// at restore (visited ones untouched).
import { loadGame, makeRunner } from "./_harness.mjs";

/** Run fn with console.log/warn captured. */
function quiet(fn) {
  const oL = console.log, oW = console.warn, warns = [];
  console.log = () => {};
  console.warn = (...a) => warns.push(a.join(" "));
  try { return { result: fn(), warns }; }
  finally { console.log = oL; console.warn = oW; }
}

export function run() {
  const { RunMap, CampaignState, DifficultyData } = loadGame();
  const r = makeRunner("mystery-nodes.test.mjs");
  const W = RunMap.GEN_CONFIG.mysteryTypeWeight;
  const TW = RunMap.GEN_CONFIG.typeWeights;
  const TARGET = W / (TW.deal + TW.pack + TW.card + W);   // the rollType table share

  r.ok(Number.isFinite(W) && W > 0, "mysteryTypeWeight is a positive number (registry value " + W + ")");
  r.ok(TARGET > 0.05 && TARGET < 0.5, "…a sane table share (" + (TARGET * 100).toFixed(1) + "%)");

  // --- genV ≥ 3: first-class type at the config rate + exclusions ----------
  {
    let typed = 0, mysteries = 0, flags = 0, maps = 0, badFields = 0, badExempt = 0;
    for (let s = 0; s < 40; s++) {
      const c = CampaignState.create();
      c.reset();
      const m = c.getMap();
      if (!m || !m.nodes.length) continue;
      maps++;
      if (maps === 1) r.eq(c.serialize().genV, 3, "a fresh run stamps genV 3");
      for (const n of m.nodes) {
        if (n.mystery) flags++;   // the legacy mask flag must never appear on a genV-3 map
        if (n.type === "mystery") {
          mysteries++;
          if (n.add != null || n.packCount != null || n.piles != null || n.suit != null || n.mixed != null) badFields++;
          if (n.phase === 0 && n.localRow === 0) badExempt++;   // the opening row stays visible
          if (n.jokerNode) badExempt++;
        }
        if (["deal", "pack", "pickup", "mystery"].indexOf(n.type) !== -1) typed++;
      }
    }
    const rate = mysteries / typed;
    r.ok(maps >= 30, "generated " + maps + " genV-3 runs to sweep (" + typed + " type-rolled nodes)");
    r.eq(flags, 0, "genV-3 maps carry NO legacy n.mystery mask flags");
    r.ok(mysteries > 0, "the type roll actually fires (" + mysteries + " first-class mysteries)");
    r.ok(Math.abs(rate - TARGET) < 0.03,
      "~" + Math.round(TARGET * 100) + "% of type-rolled nodes roll mystery (observed " + (rate * 100).toFixed(1) + "%)");
    r.eq(badFields, 0, "a mystery node carries no add / packCount / piles / suit (it grants ONLY its event)");
    r.eq(badExempt, 0, "the stage-0 opening row and joker corridors NEVER roll mystery");
    // Structural exclusions: stores / bosses / home / pass are never mystery.
    let badType = 0;
    for (let s = 0; s < 10; s++) {
      const c = CampaignState.create();
      c.reset();
      for (const n of c.getMap().nodes)
        if (["store", "boss", "home", "pass"].indexOf(n.type) !== -1 && n.type === "mystery") badType++;
    }
    r.eq(badType, 0, "no store / boss / home / pass node is ever a mystery");
  }

  // --- deterministic: same seed → same mystery types; extension-stable -----
  {
    const seed = 123456789;
    const opts = { genVersion: 3 };
    const a = quiet(() => { RunMap.setDifficultyTier("regular"); return RunMap.generateRun(seed, [13, 26, 39], opts); }).result;
    const b = quiet(() => { RunMap.setDifficultyTier("regular"); return RunMap.generateRun(seed, [13, 26, 39], opts); }).result;
    const setOf = m => m.nodes.filter(n => n.type === "mystery").map(n => n.id).sort((x, y) => x - y).join(",");
    r.ok(setOf(a).length > 0, "the fixture map has first-class mysteries");
    r.eq(setOf(a), setOf(b), "identical regeneration rolls the identical mysteries (resume-safe)");
    // Stage 0 only vs the full run: stage-0 mysteries must match — extending
    // the map (endless) never re-rolls an earlier stage.
    const solo = quiet(() => { RunMap.setDifficultyTier("regular"); return RunMap.generateRun(seed, [13], opts); }).result;
    const stage0 = m => m.nodes.filter(n => n.phase === 0 && n.type === "mystery").map(n => n.id).sort((x, y) => x - y).join(",");
    r.eq(stage0(solo), stage0(a), "extending the run never re-rolls an earlier stage's mysteries");
    RunMap.setDifficultyTier("regular");
  }

  // --- SOAK: N seeds × every tier × genV 3 — every stage validates ----------
  // (route card floors / deal counts hold with mysteries excluded: addOf
  //  returns 0 for them, so they contribute nothing to any sum the validator
  //  checks — the floors land on the typed remainder).
  {
    const e0 = RunMap.GEN_CONFIG.startDeckSize;
    const prc = RunMap.GEN_CONFIG.predictedRouteCards;
    const entries = [e0, e0 + prc, e0 + 2 * prc];
    const SEEDS = Array.from({ length: 5 }, (_, s) => (4242 + s * 7919) >>> 0);
    let stages = 0, invalid = 0, fallbacks = 0, mystTotal = 0, firstErr = "";
    for (const tier of DifficultyData.tierIds) {
      for (const seed of SEEDS) {
        for (let p = 0; p < entries.length; p++) {
          const { result: ph, warns } = quiet(() => {
            RunMap.setDifficultyTier(tier);
            return RunMap.generateStage(p, seed, entries[p], { genVersion: 3 });
          });
          stages++;
          if (warns.some(w => w.includes("no valid map"))) fallbacks++;
          if (!ph) { invalid++; firstErr = firstErr || "null phase"; continue; }
          const bandX = ((ph._gen || {}).relax || 0) * RunMap.GEN_CONFIG.relaxBandStep;
          const v = RunMap.validateStage(ph, entries[p], { phaseIndex: p, bandHiExtra: bandX });
          if (!v.ok) { invalid++; firstErr = firstErr || (tier + " seed " + seed + " stage " + p + ": " + v.errors[0]); }
          mystTotal += ph.nodes.filter(n => n.type === "mystery").length;
        }
      }
    }
    RunMap.setDifficultyTier("regular");
    r.ok(mystTotal > 0, "the soak generated first-class mysteries (" + mystTotal + " across " + stages + " stages)");
    r.eq(invalid, 0, "every genV-3 stage validates (" + stages + " stages × " + DifficultyData.tierIds.length
      + " tiers — floors/deals hold with mysteries excluded)" + (firstErr ? " — " + firstErr : ""));
    r.eq(fallbacks, 0, "…with zero best-effort fallbacks (the seed ladder always rescues)");
  }

  // --- genV 1/2: the legacy mask path is untouched ---------------------------
  {
    const seed = 123456789;
    for (const genV of [1, 2]) {
      const m = quiet(() => { RunMap.setDifficultyTier("regular"); return RunMap.generateRun(seed, [13, 26, 39], { genVersion: genV }); }).result;
      const flags = m.nodes.filter(n => n.mystery);
      const types = m.nodes.filter(n => n.type === "mystery");
      r.ok(flags.length > 0, "genV " + genV + ": the cosmetic mask still rolls (" + flags.length + " hidden nodes)");
      r.eq(types.length, 0, "genV " + genV + ": NO first-class mystery types (the type roll is genV-3 only)");
      r.ok(flags.every(n => ["pack", "pickup", "deal", "store"].indexOf(n.type) !== -1),
        "genV " + genV + ": every masked node keeps its real type underneath");
    }
    RunMap.setDifficultyTier("regular");
  }

  // --- campaign API: hidden until arrival, then revealed + persisted --------
  {
    let exercised = false;
    for (let s = 0; s < 20 && !exercised; s++) {
      const c = CampaignState.create();
      c.reset();
      const m = c.getMap();
      const myst = m.nodes.find(n => n.type === "mystery");
      if (!myst) continue;
      r.ok(c.nodeHidden(myst.id), "an un-visited mystery reports hidden");
      const plain = m.nodes.find(n => n.type !== "mystery");
      r.ok(!c.nodeHidden(plain.id), "a normal node never reports hidden");
      c.revealNode(myst.id);
      r.ok(!c.nodeHidden(myst.id), "arrival (revealNode) unhides it");
      // persistence round-trip: the reveal survives save/restore
      const snap = c.serialize();
      const c2 = CampaignState.create();
      r.ok(c2.restore(snap), "the snapshot restores");
      r.ok(!c2.nodeHidden(myst.id), "…and the reveal persists across save/restore");
      // the same node in the regenerated map is STILL a first-class mystery
      const n2 = c2.getMap().byId[myst.id];
      r.ok(n2 && n2.type === "mystery", "…while the regenerated node is still the mystery type");
      // an untouched mystery elsewhere stays hidden after restore
      const other = c2.getMap().nodes.find(n => n.type === "mystery" && n.id !== myst.id);
      if (other) r.ok(c2.nodeHidden(other.id), "an untouched mystery stays hidden after restore");
      exercised = true;
    }
    r.ok(exercised, "found a mystery node to exercise the campaign API");
  }

  // --- moving onto / clearing a mystery also unhides it ----------------------
  {
    let exercised = false;
    for (let s = 0; s < 20 && !exercised; s++) {
      const c = CampaignState.create();
      c.reset();
      const m = c.getMap();
      const myst = m.nodes.find(n => n.type === "mystery" && n.localRow <= 1 && n.phase === 0);
      if (!myst) continue;
      c.moveToNode(myst.id);
      r.ok(!c.nodeHidden(myst.id), "standing on a mystery unhides it (current position is never a ?)");
      c.markNodeCleared(myst.id);
      r.ok(!c.nodeHidden(myst.id), "a cleared mystery stays face-up");
      exercised = true;
    }
    r.ok(exercised, "found a low-row mystery to walk onto");
  }

  // --- MYST3 MIGRATION: a genV-2 save's UNVISITED masked nodes convert -------
  {
    const c = CampaignState.create();   // pink / regular — carries the fixed joker corridors
    c.reset();
    const snap = JSON.parse(JSON.stringify(c.serialize()));
    // The SAME run through genV 2: the legacy mask rolls its "?" flags over
    // fully normal nodes. This is what a pre-MYST3 save regenerates to.
    const fj = DifficultyData.fixedJokerStages(c.getDeckId(), c.getTier()) || [];
    const v2map = quiet(() => {
      RunMap.setDifficultyTier(c.getTier());
      return RunMap.generateRun(snap.runSeed, snap.stageEntryDecks, { postBossJokerStages: fj, genVersion: 2 });
    }).result;
    RunMap.setDifficultyTier("regular");
    const masked = v2map.nodes.filter(n => n.mystery);
    r.ok(masked.length >= 3, "fixture: the genV-2 regeneration carries legacy mask flags (" + masked.length + ")");
    // Fixture: one masked node VISITED-revealed, one CLEARED, the rest unvisited.
    const revealedId = masked[0].id, clearedId = masked[1].id;
    const unvisited = masked.slice(2);
    snap.genV = 2;   // an in-progress pre-MYST3 run
    snap.revealedNodes = [revealedId];
    snap.clearedNodes = [clearedId];
    const c2 = CampaignState.create();
    r.ok(c2.restore(snap), "a genV-2 save with masked nodes restores without a crash");
    r.eq(c2.serialize().genV, 2, "…staying on generator version 2 (the run's own stamp)");
    const m2 = c2.getMap();
    // Unvisited masked nodes → first-class mysteries, scrubbed bare.
    let converted = 0, badConvert = 0;
    for (const n of unvisited) {
      const n2 = m2.byId[n.id];
      if (!n2 || n2.type !== "mystery") { badConvert++; continue; }
      converted++;
      if (n2.mystery || n2.add != null || n2.packCount != null || n2.piles != null || n2.suit != null) badConvert++;
    }
    const s2 = c2.serialize();
    r.ok(unvisited.length > 0 && converted === unvisited.length && badConvert === 0,
      "every UNVISITED masked node converts to a bare first-class mystery (" + converted + "/" + unvisited.length + ")");
    r.ok(unvisited.every(n => s2.nodeCards[String(n.id)] == null && s2.packCards[String(n.id)] == null),
      "…their nodeCards / packCards locks are scrubbed (the content was never seen)");
    r.ok(unvisited.every(n => c2.nodeHidden(n.id)), "…and they report hidden on the type-based path");
    // Visited nodes are DONE and untouched: real type + inert mask flag kept.
    const rv = m2.byId[revealedId], cl = m2.byId[clearedId];
    const rv0 = v2map.byId[revealedId], cl0 = v2map.byId[clearedId];
    r.ok(rv && rv.type === rv0.type && rv.type !== "mystery" && rv.mystery === true,
      "a REVEALED masked node keeps its real type (its content was already shown)");
    r.ok(cl && cl.type === cl0.type && cl.type !== "mystery" && cl.mystery === true,
      "a CLEARED masked node keeps its real type (its content was already played)");
    r.ok(!c2.nodeHidden(revealedId) && !c2.nodeHidden(clearedId),
      "…visited nodes never report hidden on the type-based path");
    // The re-reveal flow is intact: an unvisited convert reveals + persists.
    c2.revealNode(unvisited[0].id);
    r.ok(!c2.nodeHidden(unvisited[0].id), "a converted mystery reveals on arrival");
    const c3 = CampaignState.create();
    r.ok(c3.restore(JSON.parse(JSON.stringify(c2.serialize()))), "…re-serializing restores again");
    r.ok(!c3.nodeHidden(unvisited[0].id) && c3.getMap().byId[unvisited[0].id].type === "mystery",
      "…and the conversion + reveal both survive the round-trip");
  }

  return r.summary();
}
