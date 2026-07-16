// Expansion pack: 6 new Pillars (Envy, Symmetry, Streak Bank, Streak Tribute,
// Second Wind, Greedy) and 5 new stickers (Death Bounty, Heavy, Collector,
// Compound, Wallflower). Engine is DOM-free, so we drive it directly.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, BoardState, CampaignState, StickerTypes, PillarTypes } = loadGame();
  const r = makeRunner("expansion.test.mjs");

  const deck = () => DeckManager.buildStandardDeck();
  // cols [3,4,3] → columns: 0 = piles 0-2, 1 = piles 3-6, 2 = piles 7-9.
  const COLS = [3, 4, 3];
  const onWon = (e) => { let p = null; e.onEvent((t, x) => { if (t === "won") p = x; }); return () => p; };
  // Force a guaranteed-correct HIGHER landing on pile i (mutates the live top).
  const winGuess = (e, i) => { e.getBoard().top(i).value = 5; e.debug.setNextCard(9); e.guess(i, "higher"); };

  // ===== Pillars =========================================================

  // --- Envy: at deal END, +4 coins PER PILE IN THIS COLUMN with a ♥ top --
  // (col 0 = piles 0-2, col 1 = piles 3-6, col 2 = piles 7-9)
  {
    // Registry + description (column-scoped wording). Pillars now use the arrow
    // form ("At deal end → …"); bases keep Trigger/Effect. Accept either shape.
    r.eq(PillarTypes.get("envy").effect, "heartPiles", "Envy fires the per-♥-top-pile scoring effect");
    r.eq(PillarTypes.get("envy").value, 4, "Envy pays 4 per ♥-top pile");
    r.ok(/Trigger:[\s\S]*Effect:/.test(PillarTypes.get("envy").description) || /→/.test(PillarTypes.get("envy").description), "Envy uses the Trigger/Effect or arrow description");
    r.ok(/this column/.test(PillarTypes.get("envy").description), "Envy's description scopes to this column");
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["envy", null, null]);   // Envy bound to COLUMN 0
    const b = e.getBoard();
    for (let i = 0; i < b.size; i++) b.top(i).suit = "♠";   // clear all ♥ tops first
    // ♥ tops in col 0 (piles 0,1) AND in other columns (piles 3,7): only the two
    // in ENVY'S OWN COLUMN count — proves it is column-scoped, not board-wide.
    b.top(0).suit = "♥"; b.top(1).suit = "♥";   // col 0 — counted
    b.top(3).suit = "♥"; b.top(7).suit = "♥";   // cols 1 & 2 — ignored
    e.debug.winNow();   // end of deal
    r.eq(won().pillarPayout.bonus, 8, "Envy pays +4 per ♥-top pile IN ITS COLUMN at deal end (2 × 4 = 8)");
  }
  {
    // Dead piles don't count — a ♥ top on a dead pile (in the column) is ignored.
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["envy", null, null]);   // column 0
    const b = e.getBoard();
    for (let i = 0; i < b.size; i++) b.top(i).suit = "♠";
    b.top(0).suit = "♥"; b.top(2).suit = "♥"; b.kill(2);   // pile 2 (col 0) is ♥ but dead
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 4, "Envy counts only ALIVE ♥-top piles in its column (1 × 4)");
  }

  // (Symmetry was removed in the rebalance — its tests are gone.)

  // --- Streak Size: +1 pile size per streak step from the 3rd, in-column -
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start(); e.startRun(["streakBank", null, null]);   // now "Streak Size"
    // pile 1 (col 0) is not guessed on, so its physical count stays 1; its
    // pileSize reflects the column streak bonus.
    winGuess(e, 0); r.eq(e.getBoard().pileSize(1), 1, "Streak Size: 1st correct, no size bonus");
    winGuess(e, 0); r.eq(e.getBoard().pileSize(1), 1, "2nd correct, still none");
    winGuess(e, 0); r.eq(e.getBoard().pileSize(1), 2, "3rd consecutive → +1 pile size");
    winGuess(e, 0); r.eq(e.getBoard().pileSize(1), 3, "4th consecutive → +2 pile size");
  }
  {
    // A guess in ANOTHER column resets the streak → the size bonus drops.
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start(); e.startRun(["streakBank", null, null]);
    winGuess(e, 0); winGuess(e, 0); winGuess(e, 0);   // streak 3 → +1 size
    r.eq(e.getBoard().pileSize(1), 2, "reached 3 in column 0 → +1 size");
    winGuess(e, 3);   // a guess in column 1 resets column 0's streak
    r.eq(e.getBoard().pileSize(1), 1, "a guess in another column reset the size bonus");
  }

  // --- Streak Bury: buries a FLAT digCount per correct guess from the
  //     items.js `threshold`-th consecutive correct on (currently the 4th) ----
  {
    const th = PillarTypes.get("streakTribute").threshold ?? 4;
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start(); e.startRun(["streakTribute", null, null]);
    // Each correct guess adds the drawn card (+1); from streak `th`, ALSO bury
    // a flat 1 (no escalation). Pile size is the deterministic signal.
    let expected = 1;                              // the dealt card
    for (let s = 1; s < th; s++) { winGuess(e, 0); expected += 1; }
    r.eq(e.getBoard().piles[0].cards.length, expected, "no tribute through streak " + (th - 1));
    winGuess(e, 0); expected += 2;                 // streak th → drawn + bury 1
    r.eq(e.getBoard().piles[0].cards.length, expected, "streak " + th + " buries 1 (pile +2: drawn + 1 hidden)");
    winGuess(e, 0); expected += 2;                 // flat — no escalation
    r.eq(e.getBoard().piles[0].cards.length, expected, "streak " + (th + 1) + " buries 1 more (flat)");
    winGuess(e, 0); expected += 2;
    r.eq(e.getBoard().piles[0].cards.length, expected, "streak " + (th + 2) + " buries 1 more (still flat)");
  }

  // --- Second Wind: first death per column revives once -----------------
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    let sw = null; e.onEvent((t, p) => { if (t === "second-wind") sw = p; });
    e.start(); e.startRun(["secondWind", null, null]);
    winGuess(e, 0); winGuess(e, 0);   // pile 0 → 3 cards
    const deckBefore = e.getDeck().remaining();
    e.getBoard().top(0).value = 9; e.debug.setNextCard(2); e.guess(0, "higher");   // would die → revive
    r.ok(e.getBoard().isActive(0), "Second Wind: the dying pile survives");
    r.eq(e.getBoard().piles[0].cards.length, 1, "revived pile has exactly 1 fresh card");
    r.eq(e.getBoard().pileSize(0), 1, "revived pile counts as size 1 (can lower 'smallest')");
    r.ok(e.getRun().secondWindUsed[0], "Second Wind is marked spent for the column");
    // The 3 old cards + the killing card are recycled and one fresh card dealt,
    // so the deck GREW by at least 2 (≥, since forcing ranks can synthesize cards).
    r.ok(e.getDeck().remaining() >= deckBefore + 2, "old cards + killing card recycled into the deck, one fresh dealt");
    // No card identities leaked on the event.
    r.ok(sw && !("drawn" in sw) && !("cards" in sw) && !("returned" in sw), "second-wind event reveals no recycled-card identities");
    // A SECOND death in the same column this run is NOT revived.
    e.getBoard().top(0).value = 9; e.debug.setNextCard(2); e.guess(0, "higher");
    r.ok(!e.getBoard().isActive(0), "the column's second death is not revived (once per run)");
  }
  {
    // Resets per run; returning cards preserve their stickers/identity.
    const specs = deck(); specs.forEach(c => c.stickers.push({ type: "tieSafe" }));
    const e = GameEngine.create(specs, 10, { cols: COLS });
    e.start(); e.startRun(["secondWind", null, null]);
    e.getBoard().top(0).value = 9; e.debug.setNextCard(2); e.guess(0, "higher");   // revive
    r.ok(e.getDeck()._peekAll().every(c => c.stickers && c.stickers.some(s => s.type === "tieSafe")),
      "recycled cards keep their stickers (identity preserved)");
    e.start();   // next run re-deals
    r.eq(e.getRun().secondWindUsed[0], false, "Second Wind resets each run");
  }

  // --- Greedy: only when it's the SOLE Pillar and its column survived ----
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["greedy", null, null]);
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 20, "Greedy: sole Pillar + column all-alive → +20");
  }
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["greedy", "heartBounty", null]);   // a second Pillar exists
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 0, "Greedy voided by ANY second Pillar on the board");
  }
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["greedy", "greedy", null]);   // two Greedys disqualify each other
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 0, "two Greedys disqualify each other (each is the other's second Pillar)");
  }
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["greedy", null, null]);
    e.getBoard().kill(1);   // a pile in Greedy's column dies
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 0, "Greedy voided when a pile in its column died");
  }

  // ===== Stickers ========================================================

  // --- Death Bounty: the DRAWN killing card pays +2 ---------------------
  {
    const e = GameEngine.create(deck(), 9);
    e.start(); e.startRun();
    e.getBoard().top(0).value = 5;
    const d = e.debug.setNextCard(2); d.stickers = [{ type: "deathBounty" }];   // drawn carries it
    e.guess(0, "higher");   // 2 < 5 → wrong → kills the pile
    r.ok(!e.getBoard().isActive(0), "pile died");
    r.eq(e.getRun().bonusCoins, 5, "Death Bounty (Last Coin): the killing drawn card pays +5");
  }
  {
    const e = GameEngine.create(deck(), 9);
    e.start(); e.startRun();
    e.getBoard().top(0).value = 5;
    const d = e.debug.setNextCard(9); d.stickers = [{ type: "deathBounty" }];
    e.guess(0, "higher");   // 9 > 5 → correct, pile survives
    r.eq(e.getRun().bonusCoins, 0, "Death Bounty pays nothing on a surviving guess");
  }

  // --- Heavy: counts as 2 in every pile-size read, even buried ----------
  {
    const b = BoardState.create(3);
    b.push(0, {}); b.push(0, { stickers: [{ type: "heavy" }] });   // 2 cards, one Heavy → 3
    r.eq(b.pileSize(0), 3, "Heavy card counts as 2 (pile of 2 → size 3)");
    b.push(1, { stickers: [{ type: "heavy" }] }); b.push(1, {});   // Heavy buried under a plain top
    r.eq(b.pileSize(1), 3, "a BURIED Heavy still counts as 2 (size 3)");
    b.push(2, {}); b.push(2, {}); b.push(2, {}); b.push(2, {});    // 4 plain → 4
    r.eq(b.minAliveCards(), 3, "smallest-pile factor uses weighted size (3, not 2)");
  }
  {
    const b = BoardState.create(1);
    b.push(0, { stickers: [{ type: "heavy" }] });                  // buried Heavy
    b.push(0, { stickers: [{ type: "extraCoin" }] });              // top Extra Coin
    r.eq(b.pileSize(0), 3, "size 3 with a buried Heavy under the Extra Coin top");
    r.eq(b.extraCoinUnits(), 3, "Extra Coin payout uses weighted pile size (1 × 3 = 3)");
  }
  {
    const b = BoardState.create(1);
    b.push(0, { stickers: [{ type: "heavy" }, { type: "heavy" }] });
    r.eq(b.pileSize(0), 3, "two Heavies on one card → counts as 3");
  }

  // --- Collector: pays `value` coins per OTHER sticker when its card LANDS
  //     (per-sticker rate read live from items.js — a hand-tunable knob) -----
  const COLLECT_PER = StickerTypes.get("collector").value ?? 1;
  {
    const e = GameEngine.create(deck(), 9);
    e.start(); e.startRun();
    e.getBoard().top(0).value = 5;
    const d = e.debug.setNextCard(9);
    d.stickers = [{ type: "collector" }, { type: "rankUp" }, { type: "tieSafe" }];
    e.guess(0, "higher");   // lands on a surviving pile
    r.eq(e.getRun().bonusCoins, 2 * COLLECT_PER, "Collector pays per other sticker on landing (2 others → +" + 2 * COLLECT_PER + ")");
  }
  {
    const e = GameEngine.create(deck(), 9);
    e.start(); e.startRun();
    e.getBoard().top(0).value = 5;
    const d = e.debug.setNextCard(9); d.stickers = [{ type: "collector" }];
    e.guess(0, "higher");
    r.eq(e.getRun().bonusCoins, 0, "Collector with no other stickers pays 0 (doesn't count itself)");
  }
  {
    // A Collector card on a WRONG guess doesn't land on a surviving pile → no pay.
    const e = GameEngine.create(deck(), 9);
    e.start(); e.startRun();
    e.getBoard().top(0).value = 9;
    const d = e.debug.setNextCard(2); d.stickers = [{ type: "collector" }, { type: "rankUp" }];
    e.guess(0, "higher");   // 2 < 9 → wrong, pile dies, nothing lands
    r.eq(e.getRun().bonusCoins, 0, "Collector pays nothing when its card doesn't land (wrong guess)");
  }
  {
    // Stacked Collectors pay per instance: 2 collectors × 2 other stickers each.
    const e = GameEngine.create(deck(), 9);
    e.start(); e.startRun();
    e.getBoard().top(0).value = 5;
    const d = e.debug.setNextCard(9);
    d.stickers = [{ type: "collector" }, { type: "collector" }, { type: "rankUp" }];
    e.guess(0, "higher");
    r.eq(e.getRun().bonusCoins, 4 * COLLECT_PER, "two Collectors each count the other two stickers → +" + 4 * COLLECT_PER);
  }

  // --- Compound: N increments per correct guess; pays (N − 1) on top -----
  {
    // First correct use pays +0 (hits 0 → 1), LIVE, on the spot.
    const e = GameEngine.create(deck(), 9);
    e.start(); e.startRun();
    const top = e.getBoard().top(0);
    top.stickers = [{ type: "compound" }]; top.value = 5;
    e.debug.setNextCard(9); e.guess(0, "higher");   // correct vs the Compound card → hits 0→1
    r.eq(e.getRun().compoundUpdates[top.id], 1, "Compound: a correct guess banks a hit (hits = 1)");
    r.eq(e.getRun().bonusCoins, 0, "first correct use pays +0 (hits − 1 = 0), live");
  }
  {
    // A later correct use pays (hits − 1) LIVE — e.g. hits 3 → 4 pays +3.
    const e = GameEngine.create(deck(), 9);
    e.start(); e.startRun();
    const t = e.getBoard().top(1);
    t.stickers = [{ type: "compound" }]; t.compoundHits = 3; t.value = 5;   // 3 prior correct uses
    e.debug.setNextCard(9); e.guess(1, "higher");   // correct → hits 4, pays +3 immediately
    r.eq(e.getRun().compoundUpdates[t.id], 4, "Compound: the hit count advances (3 → 4)");
    r.eq(e.getRun().bonusCoins, 3, "Compound pays live on the correct use (hits − 1 = 3)");
  }
  {
    // No "still on top at run end" condition: a card buried AFTER its correct use
    // keeps the coins it already paid; a card never used this run pays nothing.
    const e = GameEngine.create(deck(), 9);
    e.start(); e.startRun();
    const t = e.getBoard().top(0);
    t.stickers = [{ type: "compound" }]; t.compoundHits = 2; t.value = 5;
    e.debug.setNextCard(9); e.guess(0, "higher");   // hits 3, pays +2 LIVE (compound card now buried)
    r.eq(e.getRun().bonusCoins, 2, "Compound paid +2 live even though the card is now buried");
    e.debug.winNow();
    r.eq(e.getRun().bonusCoins, 2, "no extra/duplicate payout at run end (paid live, not at the end)");
  }
  {
    const e = GameEngine.create(deck(), 9);
    e.start(); e.startRun();
    const t = e.getBoard().top(2);
    t.stickers = [{ type: "compound" }]; t.compoundHits = 5;   // pre-existing, but NOT used this run
    e.debug.winNow();
    r.eq(e.getRun().bonusCoins, 0, "Compound pays nothing in a run where the card is never used correctly");
  }
  {
    // Persists across runs (save/restore) and resets on a campaign loss.
    const c = CampaignState.create();
    const card = c.getCards()[0];
    c.setCompoundHits(card.id, 4);
    r.eq(c.getCards().find(x => x.id === card.id).compoundHits, 4, "compoundHits stored on the card identity");
    const c2 = CampaignState.create();
    c2.restore(JSON.parse(JSON.stringify(c.serialize())));
    r.eq(c2.getCards().find(x => x.id === card.id).compoundHits, 4, "compoundHits survives save/restore (carries across runs)");
    c.reset();
    r.eq(c.getCards().find(x => x.id === card.id).compoundHits, 0, "compoundHits resets to 0 on a campaign loss");
  }

  // ===== Debug logbook (ground-truth event log) ==========================
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start();
    const log = e.getRun().log;
    r.ok(log.length >= 1 && /Run dealt/.test(log[0].title), "logbook: 'Run dealt' entry at run start");
    e.startRun(["heartBounty", null, null]);
    r.ok(log.some(en => /Start Run/.test(en.title)), "logbook: 'Start Run' entry");

    // Land a ♥ on pile 1 (column 0 holds the Heart Bonus pillar) via a correct guess.
    e.getBoard().top(0).value = 5;
    const dsb = e.debug.setNextCard(9); dsb.suit = "♥";
    e.guess(0, "higher");
    const turn = log[log.length - 1];
    r.ok(/Guess HIGHER on pile 1/.test(turn.title), "logbook: turn titled with the action + pile/column");
    r.ok(turn.lines.some(l => /drew 9♥/.test(l)), "logbook: logs the drawn (already-revealed) card");
    r.ok(turn.lines.some(l => /Heart Bonus/.test(l) && /\+1 coins/.test(l)), "logbook: Pillar coin effect logged");
    r.ok(turn.lines.some(l => /pile survived/.test(l)), "logbook: pile outcome logged");
    r.ok(turn.lines.some(l => /Coins this turn/.test(l)), "logbook: per-turn coins footer");

    e.start();   // a fresh run resets the log
    r.ok(e.getRun().log.length === 1 && /Run dealt/.test(e.getRun().log[0].title), "logbook: resets each run");
  }
  {
    // No-revelation: a buried tribute logs a COUNT only — never a card identity.
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start(); e.startRun(["clubTribute", null, null]);
    e.getBoard().top(0).value = 5;
    const d = e.debug.setNextCard(8); d.suit = "♣"; d.stickers = [];   // a sticker-free ♣ lands → bury 1
    e.guess(0, "higher");
    const turn = e.getRun().log[e.getRun().log.length - 1];
    const buryLine = turn.lines.find(l => /buried/.test(l));
    r.ok(!!buryLine && /deck −1/.test(buryLine), "logbook: tribute logs a buried count + deck delta");
    r.ok(!/[♠♥♦♣]/.test(buryLine), "logbook: buried card is counts-only — no suit/identity leaked");
  }

  return r.summary();
}
