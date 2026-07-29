// Between-runs persistence: CampaignState.serialize()/restore() round-trips the
// full campaign-level state (stage/run, coins, inventory, deck stickers +
// modifications, Pillars, store offer) through a JSON wire, and rejects
// missing/incompatible snapshots. The SaveStore adapter itself is just a
// localStorage shim (untestable in Node), so we test the serializable core.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { CampaignState, DifficultyData } = loadGame();
  const r = makeRunner("persistence.test.mjs");

  // --- snapshot shape ---------------------------------------------------
  {
    const s = CampaignState.create().serialize();
    r.eq(s.schema, 2, "snapshot carries schema 2 (run-map structure)");
    // The 52 base identities (ids 0..51) are always present. The deck may
    // already be LARGER at creation: map generation mints duplicate suit
    // cards when a stage rolls more +1 pickup nodes than the suit has
    // unowned cards (draftIdForNode's exhausted-pool fallback), and the
    // tier's startJokers (difficulty.js) mint their Jokers at run start.
    const baseIds = new Set(s.baseDeck.filter(c => c.id <= 51).map(c => c.id));
    r.eq(baseIds.size, 52, "snapshot holds all 52 base card identities");
    const extras = s.baseDeck.filter(c => c.id > 51);
    const startJ = DifficultyData.startJokers("pink", "regular");
    r.eq(extras.filter(c => c.joker).length, startJ,
      "creation-time Joker extras are exactly the tier's startJokers (" + startJ + ")");
    r.ok(extras.every(c => !c.blank), "creation-time extras are only minted suit duplicates + startJokers (never Blanks)");
  }

  // --- full round-trip through JSON (as storage would do) ---------------
  {
    const a = CampaignState.create();
    a.advance();                 // run 1 → 2
    a.addCoins(42);
    a.buySticker("rankUp");      // inventory rankUp:1, coins 42 − 3 = 39
    const card = a.getCards().find(c => c.suit === "♥");
    a.applySticker(card.id, "changeSuitSpade");   // permanent ♥ → ♠ on this card
    a.setColumnPillar(1, "heartBounty");
    a.debugGrantPillar("greedy"); // an owned-but-unplaced Pillar in inventory
    a.openStore();               // a live store offer to persist too

    const wire = JSON.parse(JSON.stringify(a.serialize()));   // simulate storage
    const b = CampaignState.create();
    r.ok(b.restore(wire), "restore accepts a valid snapshot");
    r.eq(b.currentRunIndex, a.currentRunIndex, "run index restored");
    r.eq(b.getCoins(), a.getCoins(), "coins restored (39)");
    r.eq(b.inventoryCount("rankUp"), 1, "sticker inventory restored");
    r.eq(b.columnPillar(1), "heartBounty", "column Pillar binding restored");
    r.eq(b.pillarInventoryCount("greedy"), 1, "unplaced Pillar inventory restored");

    const bc = b.getCards().find(c => c.id === card.id);
    r.eq(bc.suit, "♠", "applied suit-change persists on the restored deck card");
    r.ok(bc.stickers.some(s => s.type === "changeSuitSpade"), "the sticker rides on the restored card");
    r.ok(bc.modifications.some(m => m.op === "changeSuit"), "the modification history survives the round-trip");

    r.ok(!!b.getStoreOffer(), "the in-progress store offer is restored");
    r.eq(b.getStoreOffer().rerollCost, a.getStoreOffer().rerollCost, "store reroll cost restored");
  }

  // --- load tolerance: a snapshot carrying a DELETED-id sticker instance on a
  //     card must restore without throwing; the unknown sticker is dropped. ---
  {
    const a = CampaignState.create();
    const wire = JSON.parse(JSON.stringify(a.serialize()));
    // Simulate an older save whose card still carries a since-removed sticker id.
    wire.baseDeck[0].stickers = [{ type: "extraHeart" }, { type: "tieSafe" }];
    const b = CampaignState.create();
    let ok = false;
    try { ok = b.restore(wire); } catch (e) { ok = false; }
    r.ok(ok, "restore tolerates a deleted-id sticker instance (no throw)");
    const rc = b.getCards().find(c => c.id === wire.baseDeck[0].id);
    r.ok(rc && !rc.stickers.some(s => s.type === "extraHeart"), "the unknown deleted-id sticker is filtered out on load");
    r.ok(rc && rc.stickers.some(s => s.type === "tieSafe"), "known stickers on the same card survive the load");
  }

  // --- guards: bad/incompatible snapshots are rejected, state untouched -
  {
    const c = CampaignState.create();
    c.advance();                 // move off the default so we can detect changes
    const stage0 = c.currentStage, run0 = c.currentRunIndex;
    r.ok(!c.restore(null), "restore(null) → false");
    r.ok(!c.restore({ schema: 99, baseDeck: new Array(52).fill({}) }), "wrong schema → false");
    r.ok(!c.restore({ schema: 1, baseDeck: [] }), "bad deck length → false");
    r.ok(!c.restore({ schema: 1, baseDeck: new Array(52).fill({}), currentStage: 9, currentRunIndex: 1 }),
      "out-of-range stage → false");
    r.eq(c.currentStage, stage0, "a rejected restore leaves the stage untouched");
    r.eq(c.currentRunIndex, run0, "a rejected restore leaves the run untouched");
  }

  // --- Trashing a Pillar removes it permanently and persists ------------
  {
    const c = CampaignState.create();
    c.addCoins(100);
    c.buyPillar("columnGuardian", 1);
    r.eq(c.columnPillar(1), "columnGuardian", "Pillar bound to column 1");
    const coinsBefore = c.getCoins();
    c.setColumnPillar(1, null);   // the trash action (UI confirms first); no refund
    r.eq(c.columnPillar(1), null, "trash leaves the column EMPTY (not replaced)");
    r.eq(c.pillarCount(), 0, "trashed Pillar is gone");
    r.eq(c.getCoins(), coinsBefore, "trashing gives no coin refund");
    // The removal survives a save/restore (doesn't come back next run).
    const c2 = CampaignState.create();
    c2.restore(JSON.parse(JSON.stringify(c.serialize())));
    r.eq(c2.columnPillar(1), null, "the trashed column stays empty after save/restore");
  }

  // --- Progression-map fossils: record, look up, round-trip, reset -------
  {
    const c = CampaignState.create();
    r.eq(c.getRunFossils().length, 0, "no fossils on a fresh campaign");
    r.eq(c.getRunFossil(1, 1), null, "missing fossil → null");

    const fossil = {
      alive: 3, total: 9,
      nodes: [{ x: 0, y: 0 }, { x: 1, y: 1 }, { x: 2, y: 2 }],
      edges: [[0, 1], [1, 2]],
    };
    c.recordRunFossil(1, 1, fossil);
    const got = c.getRunFossil(1, 1);
    r.ok(!!got, "fossil recorded + retrievable");
    r.eq(got.alive, 3, "fossil alive count stored");
    r.eq(got.total, 9, "fossil total piles stored");
    r.eq(got.nodes.length, 3, "fossil nodes stored");
    r.eq(got.edges.length, 2, "fossil edges stored");

    // Recording the SAME stage+run replaces (no duplicate).
    c.recordRunFossil(1, 1, { alive: 5, total: 9, nodes: [{ x: 0, y: 0 }], edges: [] });
    r.eq(c.getRunFossils().length, 1, "re-recording a run replaces, not duplicates");
    r.eq(c.getRunFossil(1, 1).alive, 5, "the replacement is kept");

    // A second run records alongside.
    c.recordRunFossil(1, 2, { alive: 7, total: 10, nodes: [{ x: 0, y: 0 }, { x: 1, y: 0 }], edges: [[0, 1]] });
    r.eq(c.getRunFossils().length, 2, "a second run adds its own fossil");

    // Returned copies are independent (mutating them can't corrupt the store).
    const copy = c.getRunFossil(1, 1);
    copy.nodes.push({ x: 9, y: 9 });
    r.eq(c.getRunFossil(1, 1).nodes.length, 1, "getRunFossil returns an independent copy");

    // Round-trips through the JSON wire. STKPERF1: fossils deliberately no
    // longer ride serialize() (they shrank every coalesced save write by
    // ~45%) — their persistence contract is the serializeFossils /
    // restoreFossils sidecar pair (ninelives.fossils.v1, UI-owned).
    const restored = CampaignState.create();
    r.ok(restored.restore(JSON.parse(JSON.stringify(c.serialize()))), "restore accepts the snapshot");
    r.eq(restored.getRunFossils().length, 0, "serialize() carries NO fossils (sidecar-owned, STKPERF1)");
    restored.restoreFossils(JSON.parse(JSON.stringify(c.serializeFossils())));
    r.eq(restored.getRunFossils().length, 2, "both fossils survive the sidecar round-trip");
    r.eq(restored.getRunFossil(1, 2).alive, 7, "restored fossil keeps its alive count");
    r.eq(restored.getRunFossil(1, 2).edges.length, 1, "restored fossil keeps its edges");
    // Migration: an OLD save's INLINE runFossils is still adopted by restore()
    // (one-time, into the sidecar) and left dirty so the UI populates the
    // sidecar on the same boot.
    const legacyBlob = JSON.parse(JSON.stringify(c.serialize()));
    legacyBlob.runFossils = JSON.parse(JSON.stringify(c.serializeFossils()));
    const migrated = CampaignState.create();
    r.ok(migrated.restore(legacyBlob), "an old inline-fossil save still restores");
    r.eq(migrated.getRunFossils().length, 2, "…its inline fossils are adopted (migration path)");
    r.ok(migrated.hasUnsavedFossils(), "…and left dirty so the sidecar gets populated");

    // Backward-compat: a save with no runFossils field restores to [].
    const legacy = JSON.parse(JSON.stringify(c.serialize()));
    delete legacy.runFossils;
    const old = CampaignState.create();
    r.ok(old.restore(legacy), "restore accepts a pre-map save (no runFossils)");
    r.eq(old.getRunFossils().length, 0, "missing runFossils defaults to []");

    // reset() wipes them.
    c.reset();
    r.eq(c.getRunFossils().length, 0, "reset() clears all fossils");
  }

  return r.summary();
}
