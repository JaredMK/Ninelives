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

  // --- Envy: +1 per alive pile in the LEFT column (wraparound) ----------
  {
    // Envy on column 0 → left wraps to the RIGHTMOST column (2), piles 7-9.
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["envy", null, null]);
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 3, "Envy (col 0) reads the RIGHTMOST column as left → 3 alive = +3");
  }
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["envy", null, null]);
    e.getBoard().kill(8);   // one pile in column 2 dies → 2 alive there
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 2, "Envy left-wrap counts only ALIVE piles (2)");
  }
  {
    // Envy on column 2 → left is the NORMAL neighbour, column 1 (piles 3-6, 4).
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun([null, null, "envy"]);
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 4, "Envy (col 2) reads col 1 (no wrap) → 4 alive = +4");
  }

  // --- Symmetry: +6 if alive count equals the RIGHT column (wraparound) -
  {
    // Symmetry on column 2 → right wraps to the LEFTMOST column (0). 3 == 3.
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun([null, null, "symmetry"]);
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 6, "Symmetry (col 2) right-wraps to col 0; 3 == 3 → +6");
  }
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun([null, null, "symmetry"]);
    e.getBoard().kill(0);   // col 0 → 2 alive, col 2 → 3 alive (mismatch)
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 0, "Symmetry right-wrap: 3 != 2 → no bonus");
  }
  {
    // Symmetry on column 0 → right is column 1 (no wrap). Make 3 == 3.
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["symmetry", null, null]);
    e.getBoard().kill(3);   // col 1 → 3 alive, equals col 0's 3
    e.debug.winNow();
    r.eq(won().pillarPayout.bonus, 6, "Symmetry (col 0) reads col 1 (no wrap); 3 == 3 → +6");
  }

  // --- Streak Bank: +1 from the 3rd consecutive in-column correct -------
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start(); e.startRun(["streakBank", null, null]);
    winGuess(e, 0); r.eq(e.getRun().bonusCoins, 0, "Streak Bank: 1st correct, no bonus");
    winGuess(e, 0); r.eq(e.getRun().bonusCoins, 0, "2nd correct, no bonus");
    winGuess(e, 0); r.eq(e.getRun().bonusCoins, 1, "3rd consecutive → +1");
    winGuess(e, 0); r.eq(e.getRun().bonusCoins, 2, "4th consecutive → +1 (total 2)");
  }
  {
    // A guess in ANOTHER column resets the streak (right or wrong).
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start(); e.startRun(["streakBank", null, null]);
    winGuess(e, 0); winGuess(e, 0); winGuess(e, 0);   // streak 3 → bonus 1
    r.eq(e.getRun().bonusCoins, 1, "reached 3 in column 0");
    winGuess(e, 3);   // a correct guess in column 1 — resets column 0's streak
    winGuess(e, 0); winGuess(e, 0);   // rebuild 1,2 — no new bonus
    r.eq(e.getRun().bonusCoins, 1, "a guess in another column reset the streak");
    winGuess(e, 0);   // 3rd again → +1
    r.eq(e.getRun().bonusCoins, 2, "streak rebuilt to 3 → +1");
  }
  {
    // An in-column WRONG guess resets the streak (and kills that pile).
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start(); e.startRun(["streakBank", null, null]);
    winGuess(e, 0); winGuess(e, 0); winGuess(e, 0);   // streak 3 → bonus 1
    e.getBoard().top(0).value = 9; e.debug.setNextCard(2); e.guess(0, "higher");   // wrong, in column → reset
    r.ok(!e.getBoard().isActive(0), "in-column wrong guess killed the pile");
    winGuess(e, 1); winGuess(e, 1);   // rebuild on another col-0 pile: 1,2
    r.eq(e.getRun().bonusCoins, 1, "in-column wrong reset the streak (no bonus at 2)");
    winGuess(e, 1);   // 3rd → +1
    r.eq(e.getRun().bonusCoins, 2, "streak rebuilt → +1");
  }

  // --- Streak Tribute: buries from the 4th consecutive, uncapped --------
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start(); e.startRun(["streakTribute", null, null]);
    // Pile grows by 1 per correct guess until a tribute fires, then by 2 (drawn
    // + 1 buried). Pile size is the deterministic signal (deck counts aren't,
    // because forcing the same rank can synthesize cards once the deck's run out).
    winGuess(e, 0); winGuess(e, 0); winGuess(e, 0);   // streak 3 → no tribute yet
    r.eq(e.getBoard().piles[0].cards.length, 4, "no tribute through the 3rd (pile = 1 deal + 3 drawn)");
    winGuess(e, 0);   // streak 4 → tribute: drawn + 1 buried
    r.eq(e.getBoard().piles[0].cards.length, 6, "4th consecutive buries a tribute (pile +2: drawn + 1 hidden)");
    winGuess(e, 0);   // streak 5 → tribute again (uncapped)
    r.eq(e.getBoard().piles[0].cards.length, 8, "5th consecutive tributes again, uncapped (pile +2)");
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
    r.eq(won().pillarPayout.bonus, 30, "Greedy: sole Pillar + column all-alive → +30");
  }
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    const won = onWon(e);
    e.start(); e.startRun(["greedy", "spadeBounty", null]);   // a second Pillar exists
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
    r.eq(e.getRun().bonusCoins, 2, "Death Bounty: the killing drawn card pays +2");
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

  // --- Collector: pays +1 per OTHER sticker the moment its card LANDS -----
  {
    const e = GameEngine.create(deck(), 9);
    e.start(); e.startRun();
    e.getBoard().top(0).value = 5;
    const d = e.debug.setNextCard(9);
    d.stickers = [{ type: "collector" }, { type: "rankUp" }, { type: "tieSafe" }];
    e.guess(0, "higher");   // lands on a surviving pile
    r.eq(e.getRun().bonusCoins, 2, "Collector pays +1 per other sticker on landing (2 others → +2)");
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
    // Stacked Collectors pay per instance: 2 collectors + 1 other → 2 × (3−1) = 4.
    const e = GameEngine.create(deck(), 9);
    e.start(); e.startRun();
    e.getBoard().top(0).value = 5;
    const d = e.debug.setNextCard(9);
    d.stickers = [{ type: "collector" }, { type: "collector" }, { type: "rankUp" }];
    e.guess(0, "higher");
    r.eq(e.getRun().bonusCoins, 4, "two Collectors each count the other two stickers → +4");
  }

  // --- Compound: N increments per correct guess; pays (N − 1) on top -----
  {
    const e = GameEngine.create(deck(), 9);
    e.start(); e.startRun();
    const top = e.getBoard().top(0);
    top.stickers = [{ type: "compound" }]; top.value = 5;
    e.debug.setNextCard(9); e.guess(0, "higher");   // correct vs the Compound card → hits 0→1
    r.eq(e.getRun().compoundUpdates[top.id], 1, "Compound: a correct guess banks a hit (hits = 1)");
  }
  {
    const e = GameEngine.create(deck(), 9);
    e.start(); e.startRun();
    const t = e.getBoard().top(1);
    t.stickers = [{ type: "compound" }]; t.compoundHits = 3;   // 3 lifetime correct guesses
    e.debug.winNow();   // never guessed → still the untouched top, alive
    r.eq(e.getRun().bonusCoins, 2, "Compound pays (hits − 1): 3 hits → +2");
  }
  {
    const e = GameEngine.create(deck(), 9);
    e.start(); e.startRun();
    const t = e.getBoard().top(0);
    t.stickers = [{ type: "compound" }]; t.compoundHits = 5;
    e.getBoard().kill(0);
    e.debug.winNow();
    r.eq(e.getRun().bonusCoins, 0, "Compound on a dead pile pays nothing (must be alive on top)");
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

  // --- Wallflower: +10 only if the pile was NEVER guessed on ------------
  {
    const e = GameEngine.create(deck(), 9);
    e.start(); e.startRun();
    e.getBoard().top(0).stickers = [{ type: "wallflower" }];
    e.getBoard().pushBottom(0, { stickers: [], value: 7 });   // a burn UNDERNEATH
    e.debug.winNow();
    r.eq(e.getRun().bonusCoins, 10, "Wallflower: never guessed (burn underneath OK) → +10");
  }
  {
    const e = GameEngine.create(deck(), 9);
    e.start(); e.startRun();
    e.getBoard().top(0).stickers = [{ type: "wallflower" }];
    e.getBoard().top(0).value = 5;
    e.debug.setNextCard(9); e.guess(0, "higher");   // a guess on the pile disqualifies it
    e.debug.winNow();
    r.eq(e.getRun().bonusCoins, 0, "guessing on the pile disqualifies Wallflower");
  }
  {
    // Guessed but the card stayed on top via Extra Heart → still disqualified.
    const e = GameEngine.create(deck(), 9);
    e.start(); e.startRun();
    const top = e.getBoard().top(0);
    top.stickers = [{ type: "wallflower" }, { type: "extraHeart" }];
    top.heartsRemaining = 1; top.value = 9;
    e.debug.setNextCard(2); e.guess(0, "higher");   // wrong → heart absorbs; top stays
    r.ok(e.getBoard().isActive(0) && e.getBoard().top(0) === top, "Extra Heart kept the Wallflower card on top");
    e.debug.winNow();
    r.eq(e.getRun().bonusCoins, 0, "a guessed-on pile pays no Wallflower even if its card survives on top");
  }

  // ===== Debug logbook (ground-truth event log) ==========================
  {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start();
    const log = e.getRun().log;
    r.ok(log.length >= 1 && /Run dealt/.test(log[0].title), "logbook: 'Run dealt' entry at run start");
    e.startRun(["spadeBounty", null, null]);
    r.ok(log.some(en => /Start Run/.test(en.title)), "logbook: 'Start Run' entry");

    // Land a ♠ on pile 1 (column 0 holds the Spade Bonus pillar) via a correct guess.
    e.getBoard().top(0).value = 5;
    const dsb = e.debug.setNextCard(9); dsb.suit = "♠";
    e.guess(0, "higher");
    const turn = log[log.length - 1];
    r.ok(/Guess HIGHER on pile 1/.test(turn.title), "logbook: turn titled with the action + pile/column");
    r.ok(turn.lines.some(l => /drew 9♠/.test(l)), "logbook: logs the drawn (already-revealed) card");
    r.ok(turn.lines.some(l => /Spade Bonus/.test(l) && /\+1 coins/.test(l)), "logbook: Pillar coin effect logged");
    r.ok(turn.lines.some(l => /pile survived/.test(l)), "logbook: pile outcome logged");
    r.ok(turn.lines.some(l => /Coins this turn/.test(l)), "logbook: per-turn coins footer");

    e.start();   // a fresh run resets the log
    r.ok(e.getRun().log.length === 1 && /Run dealt/.test(e.getRun().log[0].title), "logbook: resets each run");
  }
  {
    // No-revelation: a buried tribute logs a COUNT only — never a card identity.
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start(); e.startRun(["eightTribute", null, null]);
    e.getBoard().top(0).value = 5;
    e.debug.setNextCard(8); e.guess(0, "higher");   // an 8 lands → tribute buries 1
    const turn = e.getRun().log[e.getRun().log.length - 1];
    const buryLine = turn.lines.find(l => /buried/.test(l));
    r.ok(!!buryLine && /deck −1/.test(buryLine), "logbook: tribute logs a buried count + deck delta");
    r.ok(!/[♠♥♦♣]/.test(buryLine), "logbook: buried card is counts-only — no suit/identity leaked");
  }

  return r.summary();
}
