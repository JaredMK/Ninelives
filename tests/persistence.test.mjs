// Between-runs persistence: CampaignState.serialize()/restore() round-trips the
// full campaign-level state (stage/run, coins, inventory, deck stickers +
// modifications, Pillars, store offer) through a JSON wire, and rejects
// missing/incompatible snapshots. The SaveStore adapter itself is just a
// localStorage shim (untestable in Node), so we test the serializable core.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { CampaignState } = loadGame();
  const r = makeRunner("persistence.test.mjs");

  // --- snapshot shape ---------------------------------------------------
  {
    const s = CampaignState.create().serialize();
    r.eq(s.schema, 1, "snapshot carries schema 1");
    r.eq(s.baseDeck.length, 52, "snapshot holds the full 52-card identity deck");
  }

  // --- full round-trip through JSON (as storage would do) ---------------
  {
    const a = CampaignState.create();
    a.advance();                 // run 1 → 2
    a.addCoins(42);
    a.buySticker("rankUp");      // inventory rankUp:1, coins 42 − 3 = 39
    const card = a.getCards().find(c => c.suit === "♥");
    a.applySticker(card.id, "changeSuitSpade");   // permanent ♥ → ♠ on this card
    a.setColumnPillar(1, "spadeBounty");
    a.debugGrantPillar("greedy"); // an owned-but-unplaced Pillar in inventory
    a.openStore();               // a live store offer to persist too

    const wire = JSON.parse(JSON.stringify(a.serialize()));   // simulate storage
    const b = CampaignState.create();
    r.ok(b.restore(wire), "restore accepts a valid snapshot");
    r.eq(b.currentRunIndex, a.currentRunIndex, "run index restored");
    r.eq(b.getCoins(), a.getCoins(), "coins restored (39)");
    r.eq(b.inventoryCount("rankUp"), 1, "sticker inventory restored");
    r.eq(b.columnPillar(1), "spadeBounty", "column Pillar binding restored");
    r.eq(b.pillarInventoryCount("greedy"), 1, "unplaced Pillar inventory restored");

    const bc = b.getCards().find(c => c.id === card.id);
    r.eq(bc.suit, "♠", "applied suit-change persists on the restored deck card");
    r.ok(bc.stickers.some(s => s.type === "changeSuitSpade"), "the sticker rides on the restored card");
    r.ok(bc.modifications.some(m => m.op === "changeSuit"), "the modification history survives the round-trip");

    r.ok(!!b.getStoreOffer(), "the in-progress store offer is restored");
    r.eq(b.getStoreOffer().rerollCost, a.getStoreOffer().rerollCost, "store reroll cost restored");
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

  return r.summary();
}
