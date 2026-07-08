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
  // Force a correct land on pile `i` whose DRAWN card has `value` + `suit`.
  const landSuited = (e, i, value, suit) => {
    const top = e.getBoard().top(i).value;
    const real = e.debug.setNextCard(value); real.suit = suit;
    if (value === top) e.guess(i, "same");
    else e.guess(i, value > top ? "higher" : "lower");
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
    r.eq(PillarTypes.all().length, 28, "pillar registry totals 28 (Highest Odd deleted)");
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

  // ---- Shuffler: a ♦ land shuffles the column's OTHER piles ------------
  {
    const e = game(["royalCourt", null, null]);   // id royalCourt is now "Shuffler"
    let fired = 0; e.onEvent((t, p) => { if (t === "pillar-fired" && p.effect === "shuffler") fired++; });
    landSuited(e, 0, 9, "♦");     // a ♦ lands in col 0 → shuffle the other piles
    r.eq(fired, 1, "Shuffler fires when a ♦ lands in its column");
    landSuited(e, 0, 9, "♠");     // a non-♦ land does nothing
    r.eq(fired, 1, "Shuffler does not fire on a non-♦ land");
  }

  // ---- Queen's Eye: a royal (J/Q/K) ♠ land arms the peek ----------------
  {
    const e = game(["queensEye", null, null]);
    r.ok(!e.getRun().revealNextActive, "no peek before a royal ♠");
    landSuited(e, 0, 13, "♠");    // King of Spades (royal ♠)
    r.ok(e.getRun().revealNextActive, "Queen's Eye peeks after a royal ♠ lands in this column");
    // A royal of a DIFFERENT suit does not arm it.
    const e2 = game(["queensEye", null, null]);
    landSuited(e2, 0, 12, "♥");   // Queen of Hearts — wrong suit
    r.ok(!e2.getRun().revealNextActive, "a non-♠ royal does not peek");
    // A ♠ NON-royal does not arm it.
    const e3 = game(["queensEye", null, null]);
    landSuited(e3, 0, 9, "♠");    // 9 of Spades — not royal
    r.ok(!e3.getRun().revealNextActive, "a non-royal ♠ does not peek");
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

  // ---- Heavy Diamond: every ♦ in the column counts +1 toward pile size --
  {
    const e = game(["stickerCount", null, null]);   // id stickerCount is now "Heavy Diamond"
    const b = e.getBoard();
    b.top(0).suit = "♠";   // the pile card is ♠ (not counted)
    b.pushBottom(0, { value: 6, suit: "♦", label: "6", stickers: [] });   // +1 ♦ buried
    b.pushBottom(0, { value: 4, suit: "♦", label: "4", stickers: [] });   // +1 ♦ buried
    // pile 0 now has 3 physical cards; 2 of them are ♦ → pileSize = 3 + 2 = 5.
    r.eq(b.pileSize(0), 5, "Heavy Diamond: pileSize = physical (3) + one per ♦ (2) = 5");
    // A pile in ANOTHER column doesn't get the bonus.
    b.pushBottom(3, { value: 6, suit: "♦", label: "6", stickers: [] });
    r.eq(b.pileSize(3), 2, "a ♦ in another column is NOT boosted");
  }

  // ---- Excavator: +2 per buried card in the largest ♥-top alive pile ----
  {
    const e = game(["excavator", null, null]);
    const b = e.getBoard();
    b.top(0).suit = "♥";   // pile 0's TOP is a ♥ → it qualifies
    b.pushBottom(0, { value: 4, suit: "♣", label: "4", stickers: [] });
    b.pushBottom(0, { value: 6, suit: "♦", label: "6", stickers: [] });  // pile 0 → 2 buried
    b.top(1).suit = "♠";   // pile 1's TOP is NOT ♥ → ignored even if larger
    b.pushBottom(1, { value: 9, suit: "♠", label: "9", stickers: [] });
    b.pushBottom(1, { value: 3, suit: "♠", label: "3", stickers: [] });
    b.pushBottom(1, { value: 5, suit: "♠", label: "5", stickers: [] });  // pile 1 → 3 buried, but not ♥-topped
    const pp = winPayout(e);
    const ex = pp.lines.find(l => l.label === "Excavator");
    r.ok(ex && ex.amount === 4, "Excavator pays +2 per buried card in the largest ♥-topped pile (2 × 2 = 4)");
  }

  // ---- Gambler: 50/50 +10 or +0 (only with a ♥ top in the column) -------
  {
    let sawWin = false, sawLoss = false, alwaysLine = true;
    for (let seed = 1; seed <= 30; seed++) {
      const e = GameEngine.create(baseDeck(), 10, { cols: COLS });
      e.start(seed); e.startRun(["gambler", null, null], [null, null, null]);
      e.getBoard().top(0).suit = "♥";   // ensure a ♥ top in the column so the flip runs
      const pp = winPayout(e);
      const g = pp.lines.find(l => l.label === "Gambler");
      if (!g) { alwaysLine = false; continue; }
      if (g.amount === 10) sawWin = true;
      if (g.amount === 0) sawLoss = true;
    }
    r.ok(alwaysLine, "Gambler always emits a result line");
    r.ok(sawWin && sawLoss, "Gambler produces both +10 and +0 outcomes across seeds");
    // With NO ♥ top in the column, there is no flip (+0, no win possible).
    const e2 = GameEngine.create(baseDeck(), 10, { cols: COLS });
    e2.start(7); e2.startRun(["gambler", null, null], [null, null, null]);
    for (const i of [0, 1, 2]) e2.getBoard().top(i).suit = "♠";   // clear ♥ tops in col 0
    const pp2 = winPayout(e2);
    const g2 = pp2.lines.find(l => l.label === "Gambler");
    r.ok(g2 && g2.amount === 0, "Gambler pays 0 with no ♥ top in its column");
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

  // ---- Wild Aces: an Ace counts high OR low in this column -------------
  {
    const e = game(["wildAces", null, null]);
    e.getBoard().top(0).value = 5;
    const d = e.debug.setNextCard(14); d.suit = "♠";   // an Ace lands
    e.guess(0, "lower");   // 14 > 5 normally wrong, but Wild Aces lets the Ace be LOW
    r.ok(e.getBoard().isActive(0), "Wild Aces: an Ace can be LOW → a lower guess survives");
    // A column WITHOUT Wild Aces: the same lower-on-Ace dies.
    const e2 = game([null, null, null]);
    e2.getBoard().top(0).value = 5; e2.debug.setNextCard(14);
    e2.guess(0, "lower");
    r.ok(!e2.getBoard().isActive(0), "no Wild Aces: a lower guess on an Ace dies");
  }

  // ---- Diamond Anchor: a ♦ top anchors the pile (out of smallest score) -
  {
    const e = game(["diamondAnchor", null, null]);
    const b = e.getBoard();
    b.top(0).suit = "♦";   // pile 0 (col 0) shows a ♦ on top
    r.ok(b.isAnchored(0), "Diamond Anchor: a ♦ top makes the pile anchored");
    b.top(0).suit = "♠";
    r.ok(!b.isAnchored(0), "a non-♦ top is not anchored");
    // A ♦ top in a column WITHOUT the pillar is not anchored.
    const e2 = game([null, "diamondAnchor", null]);
    e2.getBoard().top(0).suit = "♦";   // pile 0 is col 0 (no pillar)
    r.ok(!e2.getBoard().isAnchored(0), "a ♦ top outside a Diamond Anchor column is not anchored");
  }

  // ---- Diamond Distribution: a ♦ land evens the column's pile sizes -----
  {
    const e = game(["diamondDistribution", null, null]);
    const b = e.getBoard();
    b.pushBottom(0, { value: 9, suit: "♠", label: "9" });
    b.pushBottom(0, { value: 8, suit: "♠", label: "8" });
    b.pushBottom(0, { value: 7, suit: "♠", label: "7" });   // pile 0 → 4 cards; piles 1,2 → 1 each
    b.top(0).value = 5;
    const d = e.debug.setNextCard(6); d.suit = "♦";   // a ♦ lands on pile 0 → redistribute col 0
    e.guess(0, "higher");
    const sizes = [0, 1, 2].map(i => b.piles[i].cards.length).sort();
    r.ok(sizes[2] - sizes[0] <= 1, "Diamond Distribution evens the column's pile sizes (max−min ≤ 1)");
  }

  return r.summary();
}
