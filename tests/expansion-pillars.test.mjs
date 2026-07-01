// Expansion Pillars (content pass): the 10 new Pillars. DOM-free — bind a
// Pillar to a column, drive guesses / set up a board, then assert on the live
// bonus tally, run flags, or the end-of-deal pillarPayout.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, PillarTypes } = loadGame();
  const r = makeRunner("expansion-pillars.test.mjs");

  const baseDeck = () => DeckManager.buildStandardDeck();
  const COLS = [3, 4, 3];   // center column index = 1 (piles 3-6); col 0 = piles 0-2

  const game = (pillars) => {
    const e = GameEngine.create(baseDeck(), 10, { cols: COLS });
    e.start();
    e.startRun(pillars, [null, null, null]);
    return e;
  };
  // Force a correct directional land on pile `i` whose DRAWN card has `value`.
  const landValue = (e, i, value) => {
    const top = e.getBoard().top(i).value;
    // Make the guess correct: set the pile top one step toward `value`.
    const dir = value > top ? "higher" : value < top ? "lower" : "same";
    const real = e.debug.setNextCard(value);
    // Ensure the guess is genuinely correct vs the CURRENT top.
    if (value === top) { e.guess(i, "same"); return real; }
    e.guess(i, value > top ? "higher" : "lower");
    return real;
  };
  // Win immediately and return the pillarPayout from the "won" event.
  const winPayout = (e) => {
    let pp = null;
    e.onEvent((t, p) => { if (t === "won") pp = p.pillarPayout; });
    e.debug.winNow();
    return pp || { bonus: 0, lines: [] };
  };

  // ---- registry --------------------------------------------------------
  {
    const ids = ["insurance", "ditto", "stickerCount", "prime",
      "queensEye", "royalCourt", "excavator", "gambler"];
    r.ok(ids.every(id => !!PillarTypes.get(id)), "expansion Pillars registered");
    r.ok(!PillarTypes.get("sameSpark") && !PillarTypes.get("echo"), "Same Spark + Echo were removed");
    r.eq(PillarTypes.all().length, 26, "pillar registry totals 26 after the rebalance deletions");
    r.ok(ids.every(id => { const t = PillarTypes.get(id); return t.description && t.icon; }), "every expansion Pillar has a description + icon");
  }

  // ---- Prime: +1 per prime-ranked land in this column ------------------
  {
    const e = game(["prime", null, null]);
    const before = e.getRun().bonusCoins;
    landValue(e, 0, 7);            // prime → +1
    r.eq(e.getRun().bonusCoins - before, 1, "Prime pays +1 on a 7 (prime)");
    const mid = e.getRun().bonusCoins;
    landValue(e, 0, 4);            // not prime → +0
    r.eq(e.getRun().bonusCoins - mid, 0, "Prime pays nothing on a 4 (not prime)");
  }

  // ---- Royal Court: +2 per face-card land ------------------------------
  {
    const e = game(["royalCourt", null, null]);
    const before = e.getRun().bonusCoins;
    landValue(e, 0, 13);          // King → +2
    r.eq(e.getRun().bonusCoins - before, 2, "Royal Court pays +2 on a King");
    const mid = e.getRun().bonusCoins;
    landValue(e, 0, 9);           // not a face card → +0
    r.eq(e.getRun().bonusCoins - mid, 0, "Royal Court pays nothing on a 9");
  }

  // ---- Queen's Eye: a Queen land arms the peek -------------------------
  {
    const e = game(["queensEye", null, null]);
    r.ok(!e.getRun().revealNextActive, "no peek before a Queen");
    landValue(e, 0, 12);          // Queen
    r.ok(e.getRun().revealNextActive, "Queen's Eye peeks after a Queen lands in this column");
    // A Queen in ANOTHER column (no pillar) does not arm it.
    const e2 = game([null, "queensEye", null]);
    landValue(e2, 0, 12);         // col 0 has no pillar
    r.ok(!e2.getRun().revealNextActive, "a Queen outside the pillar's column does not peek");
  }

  // (Same Spark was removed in the rebalance — its test is gone.)

  // ---- Insurance: +20 if the board's sole survivor is in this column ----
  {
    const e = game(["insurance", null, null]);
    const b = e.getBoard();
    for (let i = 1; i < b.size; i++) b.kill(i);   // leave only pile 0 (col 0) alive
    const pp = winPayout(e);
    const ins = pp.lines.find(l => l.label === "Insurance");
    r.ok(ins && ins.amount === 20, "Insurance pays +20 when its column holds the only survivor");
    // If the survivor is in another column, nothing.
    const e2 = game(["insurance", null, null]);
    const b2 = e2.getBoard();
    for (let i = 0; i < b2.size; i++) if (i !== 5) b2.kill(i);   // sole survivor in col 1
    const pp2 = winPayout(e2);
    r.ok(!pp2.lines.some(l => l.label === "Insurance"), "Insurance pays nothing when the survivor is elsewhere");
  }

  // ---- Sticker Count: +1 per sticker (buried included) in alive piles ----
  {
    const e = game(["stickerCount", null, null]);
    const b = e.getBoard();
    b.top(0).stickers = [{ type: "anchor" }, { type: "heavy" }];   // 2 on the pile card
    b.pushBottom(0, { value: 5, suit: "♥", label: "5", stickers: [{ type: "gainCoin" }] });  // 1 buried
    const pp = winPayout(e);
    const sc = pp.lines.find(l => l.label === "Sticker Count");
    r.ok(sc && sc.amount === 3, "Sticker Count counts pile-card + buried stickers (3)");
  }

  // ---- Excavator: +1 per buried card in the column's LARGEST alive pile only ----
  {
    const e = game(["excavator", null, null]);
    const b = e.getBoard();
    b.pushBottom(0, { value: 4, suit: "♣", label: "4", stickers: [] });
    b.pushBottom(0, { value: 6, suit: "♦", label: "6", stickers: [] });  // pile 0 → 2 buried (LARGEST)
    b.pushBottom(1, { value: 9, suit: "♠", label: "9", stickers: [] });  // pile 1 → 1 buried (ignored now)
    const pp = winPayout(e);
    const ex = pp.lines.find(l => l.label === "Excavator");
    r.ok(ex && ex.amount === 2, "Excavator pays only the largest alive pile's buried count (2)");
  }

  // ---- Gambler: 50/50 +12 or +0, always shows a line -------------------
  {
    let sawWin = false, sawLoss = false, alwaysLine = true;
    for (let seed = 1; seed <= 30; seed++) {
      const e = GameEngine.create(baseDeck(), 10, { cols: COLS });
      e.start(seed); e.startRun(["gambler", null, null], [null, null, null]);
      const pp = winPayout(e);
      const g = pp.lines.find(l => l.label === "Gambler");
      if (!g) { alwaysLine = false; continue; }
      if (g.amount === 7) sawWin = true;
      if (g.amount === 0) sawLoss = true;
    }
    r.ok(alwaysLine, "Gambler always emits a result line");
    r.ok(sawWin && sawLoss, "Gambler produces both +7 and +0 outcomes across seeds");
  }

  // (Echo was removed in the rebalance — its test is gone.)

  // ---- Ditto: mirrors the center column's Pillar onto this column ------
  {
    // center = col 1. Ditto in col 0 mirrors a Guardian in col 1 → Ditto's col 0
    // earns the Guardian payout for col 0 being fully alive.
    const e = game(["ditto", "columnGuardian", null]);
    const pp = winPayout(e);   // all piles alive (no kills) → col 0 fully alive
    const dittoLine = pp.lines.find(l => l.col === 0 && l.label === "Guardian");
    r.ok(dittoLine && dittoLine.amount === 7, "Ditto mirrors the center Guardian onto its own column (+7)");
    // Ditto IN the center column does nothing.
    const e2 = game(["columnGuardian", "ditto", null]);
    const pp2 = winPayout(e2);
    r.ok(!pp2.lines.some(l => l.col === 1), "Ditto in the center column pays nothing");
    // Ditto with an empty center does nothing.
    const e3 = game(["ditto", null, null]);
    const pp3 = winPayout(e3);
    r.ok(!pp3.lines.some(l => l.col === 0), "Ditto with no center Pillar pays nothing");
  }

  return r.summary();
}
