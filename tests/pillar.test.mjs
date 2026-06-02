// Phase 1: Pillars (column modifiers) scaffolding + one scoring Pillar end to
// end. Covers the PillarTypes registry, the CampaignState column-slot binding
// (the holding — no inventory), reset() wiping it, escalating price, the
// engine's pile→column mapping, the "Column Guardian" all-alive scoring Pillar,
// and Economy folding the itemized payout into the coin total.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { PillarTypes, StickerTypes, CampaignState, GameEngine, DeckManager, BoardState, Economy } = loadGame();
  const r = makeRunner("pillar.test.mjs");

  // --- Registry shape ---------------------------------------------------
  {
    const g = PillarTypes.get("columnGuardian");
    r.ok(!!g, "registry has columnGuardian");
    r.eq(g.kind, "scoring", "columnGuardian is a scoring Pillar");
    r.eq(g.effect, "columnAllAlive", "columnGuardian effect key");
    r.eq(g.value, 5, "columnGuardian pays 5");
    r.eq(g.price, 12, "columnGuardian fixed price 12");
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

  // --- Buy = placement (no inventory); FIXED price; replace-when-full -----
  {
    const c = CampaignState.create();
    c.addCoins(100);
    r.eq(c.priceOfPillar("columnGuardian"), 12, "fixed Pillar price (Column Guardian = 12)");
    r.ok(c.buyPillar("columnGuardian", 0), "buy onto column 0");
    r.eq(c.columnPillar(0), "columnGuardian", "purchase placed it on the column");
    r.eq(c.priceOfPillar("columnGuardian"), 12, "price does NOT escalate after a buy");
    r.eq(c.getCoins(), 88, "spent the fixed price (12)");

    // Buying onto an occupied column overwrites it (the replace path).
    r.ok(c.buyPillar("columnGuardian", 0), "buy again onto the same column");
    r.eq(c.pillarCount(), 1, "replace keeps the slot count at one");
    r.eq(c.getCoins(), 76, "second buy also cost the fixed 12 (no escalation)");

    // Per-type fixed prices.
    r.eq(c.priceOfPillar("spadeBounty"), 8, "Suit Bounty = 8");
    r.eq(c.priceOfPillar("columnTieSafe"), 12, "Column Tie-Safe = 12");
    r.eq(c.priceOfPillar("eightTribute"), 15, "8 Tribute = 15");
    r.eq(c.priceOfPillar("sameTribute"), 15, "Same Tribute = 15");

    const broke = CampaignState.create();   // no coins
    r.ok(!broke.buyPillar("columnGuardian", 0), "can't buy without coins");
    r.ok(!c.buyPillar("columnGuardian", 9), "can't buy onto a bad column");
  }

  // --- Fixed sticker prices --------------------------------------------
  {
    const c = CampaignState.create();
    r.eq(c.priceOf("rankUp"), 3, "+1 Rank = 3");
    r.eq(c.priceOf("changeSuitRandom"), 1, "Change to Random Suit = 1");
    r.eq(c.priceOf("changeSuitSpade"), 3, "Change to ♠ = 3");
    r.eq(c.priceOf("changeSuitHeart"), 3, "Change to ♥ = 3");
    r.eq(c.priceOf("tieSafe"), 4, "Tie-Safe = 4");
    r.eq(c.priceOf("extraCoin"), 6, "Extra Coin = 6");
    r.eq(c.priceOf("extraHeart"), 7, "Extra Heart = 7");
    r.eq(c.priceOf("anchor"), 4, "Anchor = 4 (kept)");
    // Buying never changes a price.
    c.addCoins(100); c.buySticker("rankUp"); c.buySticker("rankUp");
    r.eq(c.priceOf("rankUp"), 3, "sticker price stays fixed after buying");
  }

  // --- reset() wipes the Pillar binding (prices are fixed regardless) ----
  {
    const c = CampaignState.create();
    c.addCoins(50);
    c.buyPillar("columnGuardian", 2);
    c.reset();
    r.eq(c.pillarCount(), 0, "reset clears the column binding");
    r.eq(c.priceOfPillar("columnGuardian"), 12, "Pillar price is fixed at 12");
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
    r.eq(payload.pillarPayout.bonus, 5, "all-alive column pays +5");
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

  // --- Phase 3 registry additions --------------------------------------
  {
    r.eq(PillarTypes.get("columnTieSafe").kind, "guess", "Column Tie-Safe is a guess Pillar");
    r.eq(PillarTypes.get("spadeBounty").suit, "♠", "Spade Bounty matches the ♠ symbol");
    r.eq(PillarTypes.get("heartBounty").effect, "suitBounty", "Heart Bounty is a suitBounty");
    r.eq(PillarTypes.all().length, 10, "all Pillars registered (incl. Double Tribute + All Hearts)");
  }

  // --- Column Tie-Safe: a tie survives only in the Pillar's column -------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    e.start();
    e.startRun(["columnTieSafe", null, null]);   // column 0 only

    // Pile 0 is in column 0 (covered); pile 3 is in column 1 (not). Force a
    // tie on each by drawing the showing card's rank and guessing HIGHER.
    const t0 = e.getBoard().top(0); t0.value = 7;
    e.debug.setNextCard(7);
    e.guess(0, "higher");
    r.ok(e.getBoard().isActive(0), "tie in the Column Tie-Safe column survives");

    const t3 = e.getBoard().top(3); t3.value = 7;
    e.debug.setNextCard(7);
    e.guess(3, "higher");
    r.ok(!e.getBoard().isActive(3), "tie in an uncovered column still dies");
  }

  // --- Suit Bounty: +1 per correct guess off a matching-suit top ---------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    let payload = null;
    e.onEvent((t, p) => { if (t === "won") payload = p; });
    e.start();
    e.startRun(["spadeBounty", null, null]);   // column 0 earns on ♠ tops

    // Pile 0 (col 0): a ♠ showing + a correct HIGHER guess → one bounty hit.
    const a = e.getBoard().top(0); a.value = 5; a.suit = "♠";
    e.debug.setNextCard(9);
    e.guess(0, "higher");
    r.eq(e.getRun().suitBountyHits[0], 1, "correct guess off a ♠ top tallies a hit");

    // Pile 1 (also col 0) but a ♥ showing → no hit (suit mismatch).
    const b = e.getBoard().top(1); b.value = 5; b.suit = "♥";
    e.debug.setNextCard(9);
    e.guess(1, "higher");
    r.eq(e.getRun().suitBountyHits[0], 1, "wrong suit doesn't tally");

    // Pile 3 (col 1, no Pillar) with a ♠ showing → no hit (wrong column).
    const c = e.getBoard().top(3); c.value = 5; c.suit = "♠";
    e.debug.setNextCard(9);
    e.guess(3, "higher");
    r.eq(e.getRun().suitBountyHits[1], 0, "♠ in an unbountied column doesn't tally");

    // A WRONG guess off a ♠ top doesn't tally (only correct guesses count).
    const d = e.getBoard().top(2); d.value = 9; d.suit = "♠";
    e.debug.setNextCard(2);
    e.guess(2, "higher");   // 2 < 9 → wrong
    r.eq(e.getRun().suitBountyHits[0], 1, "a wrong guess earns no bounty");

    // Suit Bounty is paid LIVE into the bonus tally as it resolves (not at run
    // end via pillarPayout) — one ♠ hit → +1 in the live bonus.
    r.eq(e.getRun().bonusCoins, 1, "Suit Bounty pays into the live bonus tally during play");

    e.debug.winNow();
    r.eq(payload.pillarPayout.bonus, 0, "Suit Bounty is NOT re-paid at run end (no double-count)");
    r.eq(payload.pillarPayout.lines.length, 0, "no Suit Bounty line in the run-end Pillar payout");
  }

  // --- A guess-kind Pillar never produces a payout line ------------------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    let payload = null;
    e.onEvent((t, p) => { if (t === "won") payload = p; });
    e.start();
    e.startRun(["columnTieSafe", null, null]);
    e.debug.winNow();
    r.eq(payload.pillarPayout.bonus, 0, "Column Tie-Safe pays no coins itself");
    r.eq(payload.pillarPayout.lines.length, 0, "guess-kind Pillar adds no breakdown line");
  }

  // --- Phase 4: low-level deck/board bottom ops --------------------------
  {
    const d = DeckManager.create(DeckManager.buildStandardDeck());
    const before = d.remaining();
    const bottom = d.drawFromBottom();
    r.ok(!!bottom, "drawFromBottom returns a card");
    r.eq(d.remaining(), before - 1, "drawFromBottom removes one card");

    const b = BoardState.create(2);
    b.push(0, { value: 9 });
    b.pushBottom(0, { value: 2 });
    r.eq(b.piles[0].cards.length, 2, "pushBottom adds a card to the pile");
    r.eq(b.piles[0].cards[0].value, 2, "pushBottom seats the card at the BOTTOM");
    r.eq(b.top(0).value, 9, "pushBottom leaves the top untouched");

    const empty = DeckManager.create([]);
    r.eq(empty.drawFromBottom(), null, "drawFromBottom on an empty deck → null");
  }

  // --- 8 Tribute: a drawn 8 buries a deck-bottom card (capped) -----------
  // Force a correct guess that lands an 8: set the showing card low, force
  // the next draw to an 8 (rank 8), guess HIGHER.
  const landEight = (e, index) => {
    const top = e.getBoard().top(index); top.value = 5;
    e.debug.setNextCard(8);
    e.guess(index, "higher");
  };
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    e.start();
    e.startRun(["eightTribute", null, null]);   // column 0 only (uncapped)

    const pileLenBefore = e.getBoard().piles[0].cards.length;   // 1 (the deal)
    const deckBefore = e.getDeck().remaining();
    landEight(e, 0);
    r.eq(e.getRun().eightTributesUsed[0], 1, "8 on the Tribute column triggers once");
    // Pile gained the 8 (top) + a buried tribute card = +2; deck lost both.
    r.eq(e.getBoard().piles[0].cards.length, pileLenBefore + 2, "pile gains 8 + a buried card");
    r.eq(e.getDeck().remaining(), deckBefore - 2, "deck loses the 8 and the tributed card");

    landEight(e, 1);   // pile 1 is also column 0
    r.eq(e.getRun().eightTributesUsed[0], 2, "second 8 fires again (uncapped)");
    landEight(e, 2);   // pile 2, column 0 — still fires (no cap)
    r.eq(e.getRun().eightTributesUsed[0], 3, "third 8 fires too — caps removed");
    r.eq(e.getBoard().piles[2].cards.length, 3, "third 8 still gets its buried tribute (1 deal + 8 + tribute)");
  }

  // --- 8 on a non-Tribute column does nothing ---------------------------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    e.start();
    e.startRun([null, null, null]);
    const deckBefore = e.getDeck().remaining();
    landEight(e, 0);
    r.eq(e.getRun().eightTributesUsed[0], 0, "no Pillar → no tribute");
    r.eq(e.getDeck().remaining(), deckBefore - 1, "only the drawn 8 leaves the deck");
    r.eq(e.getBoard().piles[0].cards.length, 2, "pile gains only the 8");
  }

  // --- Guardrail: the buried card is never revealed in any event --------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    let resolved = null;
    e.onEvent((t, p) => { if (t === "resolved") resolved = p; });
    e.start();
    e.startRun(["eightTribute", null, null]);
    landEight(e, 0);
    r.ok(resolved && !("tributed" in resolved) && !("tribute" in resolved),
      "resolved event exposes no tributed-card field");
    const keys = Object.keys(resolved).sort().join(",");
    r.eq(keys, "board,correct,current,deck,drawn,guess,index,run",
      "resolved payload carries only its known fields (no order leak)");
  }

  // --- Deck-empty edge: tribute is skipped, no crash --------------------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    e.start();
    e.startRun(["eightTribute", null, null]);
    const top = e.getBoard().top(0); top.value = 5;
    e.debug.setNextCard(8);    // an 8 on top of the deck
    e.debug.trimDeck(1);       // ...and it's the ONLY card left
    e.guess(0, "higher");      // draws the 8 → deck empty → tribute skipped
    r.eq(e.getRun().eightTributesUsed[0], 0, "no tribute when the deck is empty");
    r.eq(e.getStatus(), "won", "emptying the deck still wins the run");
  }

  // --- Same Tribute: burns on a SURVIVED TIE (correct Same OR shield-saved) ---
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    let resolved = null;
    e.onEvent((t, p) => { if (t === "resolved") resolved = p; });
    e.start();
    e.startRun(["sameTribute", null, null]);   // column 0 (cap 2)
    const deck0 = e.getDeck().remaining();
    const len0 = e.getBoard().piles[0].cards.length;

    // (a) a correctly-called Same guess (drawn ties the showing card).
    const a = e.getBoard().top(0); a.value = 7;
    e.debug.setNextCard(7);
    e.guess(0, "same");
    r.eq(e.getRun().sameTributesUsed[0], 1, "fires on a correct Same guess");
    r.eq(e.getBoard().piles[0].cards.length, len0 + 2, "pile gains the Same card + a buried tribute");
    r.eq(e.getDeck().remaining(), deck0 - 2, "deck loses the drawn card and the tributed card");
    r.eq(Object.keys(resolved).sort().join(","), "board,correct,current,deck,drawn,guess,index,run",
      "resolved payload carries no tributed-card field (no order leak)");

    // (b) a tie SAVED by the card's Tie-Safe (guessed higher) — also counts.
    const b = e.getBoard().top(1); b.value = 7; b.tieSafe = true;
    e.debug.setNextCard(7);
    e.guess(1, "higher");
    r.ok(e.getBoard().isActive(1), "Tie-Safe saved the tie (pile survives)");
    r.eq(e.getRun().sameTributesUsed[0], 2, "ALSO fires on a shield-saved tie (cap now reached)");

    // (c) uncapped: a third survived tie buries again.
    const c2 = e.getBoard().top(2); c2.value = 7;
    e.debug.setNextCard(7);
    e.guess(2, "same");
    r.eq(e.getRun().sameTributesUsed[0], 3, "third survived tie fires too — caps removed");
    r.eq(e.getBoard().piles[2].cards.length, 3, "survived tie still buries (1 deal + Same card + tribute)");
  }

  // --- Same Tribute does NOT fire on a non-tie win or an off-column tie ---
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    e.start();
    e.startRun(["sameTribute", null, null]);
    const a = e.getBoard().top(0); a.value = 5;
    const deck0 = e.getDeck().remaining();
    e.debug.setNextCard(9);
    e.guess(0, "higher");   // 9 > 5, correct but NOT a tie
    r.eq(e.getRun().sameTributesUsed[0], 0, "no burn on a non-tie correct guess");
    r.eq(e.getDeck().remaining(), deck0 - 1, "only the drawn card leaves the deck");

    // A survived tie in a column WITHOUT the Pillar burns nothing.
    const d = e.getBoard().top(3); d.value = 7;   // pile 3 = column 1 (no Pillar)
    e.debug.setNextCard(7);
    e.guess(3, "same");
    r.eq(e.getRun().sameTributesUsed[1], 0, "a survived tie in a non-tribute column doesn't burn");
  }

  // --- Suit-change stickers (Defined + Random; Suit Bounty enablers) -----
  {
    r.ok(!!StickerTypes.get("changeSuitSpade") && !!StickerTypes.get("changeSuitHeart"),
      "registry has the Defined-suit stickers (♠, ♥)");
    r.ok(!!StickerTypes.get("changeSuitRandom"), "registry has the Random-suit sticker");
    r.eq(StickerTypes.get("changeSuit"), null, "old cycle Change Suit is removed");

    // Defined suit: set a ♦ card to ♥ (rank untouched).
    const c = CampaignState.create();
    const card = c.getCards().find(x => x.suit === "♦");
    const id = card.id, rank0 = card.currentRank;
    r.ok(c.applySticker(id, "changeSuitHeart"), "apply Change to ♥ to a ♦ card");
    const after = c.getCards().find(x => x.id === id);
    r.eq(after.suit, "♥", "Defined-suit sets ♦ → ♥");
    r.eq(after.currentRank, rank0, "rank/value is untouched by a suit change");
    r.ok(after.modifications.some(m => m.op === "changeSuit"), "records a changeSuit modification");
    // Uniform data model: the one-time suit sticker rides in card.stickers like
    // any ongoing sticker, so the badge renderer (which reads card.stickers)
    // shows it. This is the root-cause guard for the missing-badge bug.
    r.eq(after.stickers.filter(s => s.type === "changeSuitHeart").length, 1,
      "suit-change sticker is recorded in card.stickers (persistent identity)");
    // Flows into the run deck the engine deals from (a Heart Bounty would see it).
    // ♥ is active in Stage 1, so it appears in the run deck.
    const dealt = c.getRunDeck().find(x => x.id === id);
    r.eq(dealt.suit, "♥", "changed suit materializes in the run deck");
    r.ok(dealt.stickers.some(s => s.type === "changeSuitHeart"),
      "the suit-change sticker rides into the dealt run deck (badge survives a later deal)");

    // Random suit: changes to a DIFFERENT valid suit, and records its sticker.
    const sid = c.getCards().find(x => x.suit === "♠").id;
    c.applySticker(sid, "changeSuitRandom");
    const sCard = c.getCards().find(x => x.id === sid);
    r.ok(["♠", "♥", "♦", "♣"].includes(sCard.suit) && sCard.suit !== "♠", "Random suit picks a different valid suit");
    r.ok(sCard.stickers.some(s => s.type === "changeSuitRandom"), "Random-suit sticker is recorded for its badge");
  }

  // --- Debug grant: free sticker to inventory, no coins / no escalation --
  {
    const c = CampaignState.create();
    const before = c.priceOf("tieSafe");
    r.ok(c.debugGrantSticker("tieSafe"), "debugGrantSticker adds the sticker");
    r.eq(c.inventoryCount("tieSafe"), 1, "granted sticker lands in inventory");
    r.eq(c.getCoins(), 0, "grant spends no coins");
    r.eq(c.priceOf("tieSafe"), before, "grant doesn't escalate the price");
    r.ok(!c.debugGrantSticker("nope"), "unknown sticker id rejected");
  }

  // --- Store help text lives in the registry (single source) ------------
  // The store "?" help popup reads `description` straight from the registry,
  // so every sticker and Pillar must carry non-empty text.
  {
    const missing = [];
    StickerTypes.all().forEach(t => { if (!t.description || !t.description.trim()) missing.push("sticker:" + t.id); });
    PillarTypes.all().forEach(t => { if (!t.description || !t.description.trim()) missing.push("pillar:" + t.id); });
    r.eq(missing.join(",") || "none", "none", "every sticker & Pillar has a description for the help popup");
  }

  return r.summary();
}
