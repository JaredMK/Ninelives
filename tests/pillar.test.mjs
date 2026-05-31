// Phase 1: Pillars (column modifiers) scaffolding + one scoring Pillar end to
// end. Covers the PillarTypes registry, the CampaignState column-slot binding
// (the holding — no inventory), reset() wiping it, escalating price, the
// engine's pile→column mapping, the "Column Guardian" all-alive scoring Pillar,
// and Economy folding the itemized payout into the coin total.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { PillarTypes, CampaignState, GameEngine, DeckManager, Economy } = loadGame();
  const r = makeRunner("pillar.test.mjs");

  // --- Registry shape ---------------------------------------------------
  {
    const g = PillarTypes.get("columnGuardian");
    r.ok(!!g, "registry has columnGuardian");
    r.eq(g.kind, "scoring", "columnGuardian is a scoring Pillar");
    r.eq(g.effect, "columnAllAlive", "columnGuardian effect key");
    r.eq(g.value, 10, "columnGuardian pays 10");
    r.eq(g.basePrice, 1, "columnGuardian base price 1");
    r.eq(PillarTypes.get("nope"), null, "unknown Pillar id → null");
    r.ok(PillarTypes.all().length === PillarTypes.ids.length, "all() matches ids");
  }

  // --- Column-slot binding: capacity, set, swap, clear, count -----------
  {
    const c = CampaignState.create();
    r.eq(c.columnSlots, 3, "three column slots (one per column)");
    r.eq(c.pillarCount(), 0, "starts with no Pillars bound");
    r.eq(c.getColumnPillars().length, 3, "binding has a slot per column");
    r.ok(c.getColumnPillars().every(x => x === null), "all slots start empty");

    r.ok(c.setColumnPillar(1, "columnGuardian"), "set Pillar on column 1");
    r.eq(c.columnPillar(1), "columnGuardian", "column 1 now holds it");
    r.eq(c.pillarCount(), 1, "pillarCount reflects the binding");
    r.eq(c.firstEmptyColumn(), 0, "firstEmptyColumn finds an open slot");

    r.ok(c.swapColumnPillars(0, 1), "swap columns 0 and 1");
    r.eq(c.columnPillar(0), "columnGuardian", "Pillar moved to column 0");
    r.eq(c.columnPillar(1), null, "column 1 cleared by the swap");
    r.eq(c.pillarCount(), 1, "swap mints/loses nothing");

    r.ok(c.setColumnPillar(0, null), "clear column 0");
    r.eq(c.pillarCount(), 0, "cleared back to zero");
    r.ok(!c.setColumnPillar(9, "columnGuardian"), "out-of-range column rejected");
    r.ok(!c.setColumnPillar(0, "ghost"), "unknown Pillar id rejected");
  }

  // --- Buy = placement (no inventory); escalating price; replace-when-full
  {
    const c = CampaignState.create();
    c.addCoins(100);
    r.eq(c.priceOfPillar("columnGuardian"), 1, "first price = basePrice");
    r.ok(c.buyPillar("columnGuardian", 0), "buy onto column 0");
    r.eq(c.columnPillar(0), "columnGuardian", "purchase placed it on the column");
    r.eq(c.priceOfPillar("columnGuardian"), 2, "price climbs +1 after a buy");
    r.eq(c.getCoins(), 99, "spent the first price");

    // Buying onto an occupied column overwrites it (the replace path).
    r.ok(c.buyPillar("columnGuardian", 0), "buy again onto the same column");
    r.eq(c.pillarCount(), 1, "replace keeps the slot count at one");
    r.eq(c.getCoins(), 97, "spent the escalated price (2)");

    const broke = CampaignState.create();   // no coins
    r.ok(!broke.buyPillar("columnGuardian", 0), "can't buy without coins");
    r.ok(!c.buyPillar("columnGuardian", 9), "can't buy onto a bad column");
  }

  // --- reset() wipes the Pillar binding + purchase counts ---------------
  {
    const c = CampaignState.create();
    c.addCoins(50);
    c.buyPillar("columnGuardian", 2);
    c.reset();
    r.eq(c.pillarCount(), 0, "reset clears the column binding");
    r.eq(c.priceOfPillar("columnGuardian"), 1, "reset clears escalating price");
  }

  // --- Engine pile→column mapping (fill DOWN each column) ----------------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    e.start();
    const pc = e.getRun().pileColumns;
    r.ok(JSON.stringify(pc) === JSON.stringify([0, 0, 0, 1, 1, 1, 1, 2, 2, 2]),
      "pileColumns maps [3,4,3] down each column");

    const legacy = GameEngine.create(DeckManager.buildStandardDeck(), 9);
    legacy.start();
    r.eq(legacy.getRun().pileColumns, null, "no cols → no column map (legacy safe)");
  }

  // --- Column Guardian scores +10 only when its whole column survives ----
  {
    // Column 0 holds the Guardian; all piles alive → +10.
    const win = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    let payload = null;
    win.onEvent((t, p) => { if (t === "won") payload = p; });
    win.start();
    win.startRun(["columnGuardian", null, null]);
    win.debug.winNow();   // empty the deck → win, every pile still alive
    r.eq(payload.pillarPayout.bonus, 10, "all-alive column pays +10");
    r.eq(payload.pillarPayout.lines.length, 1, "one itemized Pillar line");

    // Same setup but kill a pile in column 0 → no payout for that column.
    const dead = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    let p2 = null;
    dead.onEvent((t, p) => { if (t === "won") p2 = p; });
    dead.start();
    dead.startRun(["columnGuardian", null, null]);
    dead.getBoard().kill(1);   // pile 1 is in column 0
    dead.debug.winNow();
    r.eq(p2.pillarPayout.bonus, 0, "a dead pile in the column → no Pillar bonus");
    r.eq(p2.pillarPayout.lines.length, 0, "no itemized line when it didn't pay");

    // A column with no Pillar bound never pays.
    const none = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    none.start();
    none.startRun([null, null, null]);
    r.eq(none.pillarPayout().bonus, 0, "no Pillar bound → no bonus");
  }

  // --- Economy folds the Pillar bonus into the coin total ---------------
  {
    const base = Economy.breakdown({ won: true, aliveCount: 4, minAliveCards: 2, extraCoinUnits: 0 });
    r.eq(base.pillarBonus, 0, "absent pillarBonus defaults to 0 (backward-compatible)");
    r.eq(base.total, 8, "base total without Pillars = 4 × 2");

    const withPillar = Economy.breakdown({
      won: true, aliveCount: 4, minAliveCards: 2, extraCoinUnits: 0,
      pillarBonus: 10, pillarLines: [{ label: "Column Guardian", detail: "Column 1 survived", amount: 10 }],
    });
    r.eq(withPillar.pillarBonus, 10, "pillarBonus carried through");
    r.eq(withPillar.total, 18, "total folds in the Pillar bonus (8 + 10)");
    r.eq(withPillar.pillarLines.length, 1, "itemized lines preserved for the UI");

    // A loss never pays Pillars, even if stats are supplied.
    const lost = Economy.breakdown({ won: false, aliveCount: 4, minAliveCards: 2, pillarBonus: 10 });
    r.eq(lost.pillarBonus, 0, "loss zeroes the Pillar bonus");
    r.eq(lost.total, 0, "loss pays nothing");
  }

  return r.summary();
}
