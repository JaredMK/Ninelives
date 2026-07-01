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
    r.eq(g.value, 7, "columnGuardian pays 7");
    r.eq(g.price, 7, "columnGuardian fixed price 7");
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
    r.eq(c.priceOfPillar("columnGuardian"), 7, "fixed Pillar price (Column Guardian = 7)");
    r.ok(c.buyPillar("columnGuardian", 0), "buy onto column 0");
    r.eq(c.columnPillar(0), "columnGuardian", "purchase placed it on the column");
    r.eq(c.priceOfPillar("columnGuardian"), 7, "price does NOT escalate after a buy");
    r.eq(c.getCoins(), 93, "spent the fixed price (7)");

    // Buying onto an occupied column overwrites it (the replace path).
    r.ok(c.buyPillar("columnGuardian", 0), "buy again onto the same column");
    r.eq(c.pillarCount(), 1, "replace keeps the slot count at one");
    r.eq(c.getCoins(), 86, "second buy also cost the fixed 7 (no escalation)");

    // Per-type fixed prices.
    r.eq(c.priceOfPillar("heartBounty"), 9, "Heart Bonus = 9");
    r.eq(c.priceOfPillar("columnTieSafe"), 12, "Column Tie-Safe = 12");
    r.eq(c.priceOfPillar("clubTribute"), 25, "8 Bury (clubTribute) = 25");

    const broke = CampaignState.create();   // no coins
    r.ok(!broke.buyPillar("columnGuardian", 0), "can't buy without coins");
    r.ok(!c.buyPillar("columnGuardian", 9), "can't buy onto a bad column");
  }

  // --- Fixed sticker prices --------------------------------------------
  {
    const c = CampaignState.create();
    r.eq(c.priceOf("rankUp"), 1, "+1 Rank = 1");
    r.eq(c.priceOf("changeSuitSpade"), 1, "Change to ♠ = 1");
    r.eq(c.priceOf("changeSuitHeart"), 1, "Change to ♥ = 1");
    r.eq(c.priceOf("tieSafe"), 2, "Same-Safe = 2");
    r.eq(c.priceOf("extraCoin"), 2, "Payout = 2");
    r.eq(c.priceOf("extraHeart"), 5, "Shield = 5");
    r.eq(c.priceOf("anchor"), 3, "Anchor = 3");
    // Buying never changes a price.
    c.addCoins(100); c.buySticker("rankUp"); c.buySticker("rankUp");
    r.eq(c.priceOf("rankUp"), 1, "sticker price stays fixed after buying");
  }

  // --- reset() wipes the Pillar binding (prices are fixed regardless) ----
  {
    const c = CampaignState.create();
    c.addCoins(50);
    c.buyPillar("columnGuardian", 2);
    c.reset();
    r.eq(c.pillarCount(), 0, "reset clears the column binding");
    r.eq(c.priceOfPillar("columnGuardian"), 7, "Pillar price is fixed at 7");
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
    r.eq(payload.pillarPayout.bonus, 7, "all-alive column pays +7");
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
    r.eq(PillarTypes.get("heartBounty").suit, "♥", "Heart Bonus matches the ♥ symbol");
    r.eq(PillarTypes.get("heartBounty").effect, "suitBounty", "Heart Bonus is a suitBounty");
    r.ok(!PillarTypes.get("spadeBounty") && !PillarTypes.get("clubBounty") && !PillarTypes.get("diamondBounty"),
      "the ♠/♣/♦ Bonus pillars were removed (only ♥ remains)");
    r.eq(PillarTypes.all().length, 29, "pillar registry totals 29 after the rebalance");
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

  // --- Suit Bounty: +1 each time a matching-suit card LANDS in the column --
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    let payload = null;
    e.onEvent((t, p) => { if (t === "won") payload = p; });
    e.start();
    e.startRun(["heartBounty", null, null]);   // column 0 earns when a ♥ lands

    // Pile 0 (col 0): land a ♥ via a correct HIGHER guess → one bounty hit.
    e.getBoard().top(0).value = 5;
    const d0 = e.debug.setNextCard(9); d0.suit = "♥";
    e.guess(0, "higher");
    r.eq(e.getRun().suitBountyHits[0], 1, "a ♥ landing on the Bounty column tallies a hit");

    // Pile 1 (also col 0): land a ♠ → no hit (suit mismatch).
    e.getBoard().top(1).value = 5;
    const d1 = e.debug.setNextCard(9); d1.suit = "♠";
    e.guess(1, "higher");
    r.eq(e.getRun().suitBountyHits[0], 1, "a non-♥ landing doesn't tally");

    // Pile 3 (col 1, no Pillar): land a ♥ → no hit (wrong column).
    e.getBoard().top(3).value = 5;
    const d3 = e.debug.setNextCard(9); d3.suit = "♥";
    e.guess(3, "higher");
    r.eq(e.getRun().suitBountyHits[1], 0, "a ♥ landing in an unbountied column doesn't tally");

    // A WRONG guess (the card doesn't LAND on a surviving pile) → no bounty.
    e.getBoard().top(2).value = 9;
    const d2 = e.debug.setNextCard(2); d2.suit = "♥";
    e.guess(2, "higher");   // 2 < 9 → wrong, pile dies
    r.eq(e.getRun().suitBountyHits[0], 1, "a ♥ on a wrong guess (pile dies) earns no bounty");

    // Suit Bounty is paid LIVE into the bonus tally as it resolves (not at run
    // end via pillarPayout) — one ♠ landing → +1 in the live bonus.
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

  // --- clubTribute ("8 Bury"): a ♣ card with NO stickers lands → bury 1 ---
  // Land a specific card correctly on a pile: set the showing card low, force
  // the drawn card (rank/suit/stickers), guess HIGHER.
  const landCard = (e, index, value, suit, stickers) => {
    const top = e.getBoard().top(index); top.value = 5;
    const d = e.debug.setNextCard(value); d.suit = suit; d.stickers = stickers || [];
    e.guess(index, "higher");
  };
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    e.start();
    e.startRun(["clubTribute", null, null]);   // column 0 only
    const len0 = e.getBoard().piles[0].cards.length;   // 1 (the deal)
    const deck0 = e.getDeck().remaining();
    landCard(e, 0, 9, "♣", []);   // a ♣ with no stickers lands
    r.eq(e.getBoard().piles[0].cards.length, len0 + 2, "♣ (no stickers) lands + 1 buried = +2");
    r.eq(e.getDeck().remaining(), deck0 - 2, "deck loses the drawn ♣ and the buried card");

    // A ♣ carrying a sticker does NOT trigger (must be sticker-free).
    const len1 = e.getBoard().piles[1].cards.length;
    landCard(e, 1, 9, "♣", [{ type: "tieSafe" }]);
    r.eq(e.getBoard().piles[1].cards.length, len1 + 1, "a stickered ♣ buries nothing (just the drawn card)");

    // A non-♣ card does NOT trigger.
    const len2 = e.getBoard().piles[2].cards.length;
    landCard(e, 2, 9, "♥", []);
    r.eq(e.getBoard().piles[2].cards.length, len2 + 1, "a non-♣ card buries nothing");
  }

  // --- clubTribute on a non-Pillar column does nothing ------------------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    e.start();
    e.startRun([null, null, null]);
    const deck0 = e.getDeck().remaining();
    landCard(e, 0, 9, "♣", []);
    r.eq(e.getDeck().remaining(), deck0 - 1, "no Pillar → only the drawn ♣ leaves the deck");
    r.eq(e.getBoard().piles[0].cards.length, 2, "pile gains only the drawn card");
  }

  // (Same Tribute / "Tie Bury" was removed in the rebalance — its tests are gone.)

  // --- Suit-change stickers (Defined + Random; Suit Bounty enablers) -----
  {
    r.ok(!!StickerTypes.get("changeSuitSpade") && !!StickerTypes.get("changeSuitHeart"),
      "registry has the Defined-suit stickers (♠, ♥)");
    r.ok(!!StickerTypes.get("changeSuitRandom"), "Random Suit sticker is registered (re-added)");
    r.eq(StickerTypes.get("changeSuitRandom").behavior, "changeSuitRandom", "Random Suit uses the changeSuitRandom behavior");
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
    // A sticker rides into the dealt run deck (the engine deals the OWNED draft;
    // the run starts holding the 13 hearts, so apply to one of those to confirm
    // the badge survives into the deal). The ♦→♥ change above already proved the
    // suit-change identity; here we confirm the sticker materializes when dealt.
    const ownedId = c.getRunDeck()[0].id;   // a card actually in the dealt draft
    r.ok(c.applySticker(ownedId, "anchor"), "apply a sticker to an owned (dealt) card");
    const dealt = c.getRunDeck().find(x => x.id === ownedId);
    r.ok(dealt, "an owned card materializes in the dealt run deck");
    r.ok(dealt.stickers.some(s => s.type === "anchor"),
      "the sticker rides into the dealt run deck (badge survives into the deal)");
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
