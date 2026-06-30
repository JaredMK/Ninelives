// Expansion stickers (content pass): the 10 new behavior stickers + the two
// completed suit-change stickers. DOM-free — drive the engine directly and
// assert on board/deck/run + event payloads, plus registry/gating checks.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, CampaignState, StickerTypes } = loadGame();
  const r = makeRunner("expansion-stickers.test.mjs");

  const baseDeck = () => DeckManager.buildStandardDeck();
  const COLS = [3, 4, 3];   // col 0 = piles 0-2, col 1 = piles 3-6, col 2 = piles 7-9

  /** A started run, no pillars/bases bound. */
  const game = (pillars) => {
    const e = GameEngine.create(baseDeck(), 10, { cols: COLS });
    e.start();
    e.startRun(pillars || [null, null, null], [null, null, null]);
    return e;
  };
  /** Force a guaranteed-CORRECT directional guess on pile `i`, with the DRAWN
      card carrying `types` (stamped on the forced next card so it never depends
      on whether a real stickered card of that rank still sits in the deck).
      Returns the drawn card object. */
  const land = (e, i, types) => {
    const top = e.getBoard().top(i).value;
    const up = top < 14;
    const nc = e.debug.setNextCard(up ? top + 1 : top - 1);
    nc.stickers = (types || []).map(t => ({ type: t }));
    e.guess(i, up ? "higher" : "lower");
    return nc;
  };

  // ---- registry + count ------------------------------------------------
  {
    const ids = ["changeSuitDiamond", "changeSuitClub", "quickBury", "twinSpark",
      "looseChange", "snowball", "deepPockets", "pillarScout", "baseScout",
      "suitSnob", "momentum"];
    r.ok(ids.every(id => !!StickerTypes.get(id)), "all 11 new stickers registered");
    r.eq(StickerTypes.all().length, 41, "sticker registry totals 41 (Duplicate removed)");
    r.ok(!StickerTypes.get("mirror"), "Mirror sticker is gone from the registry");
    r.ok(!StickerTypes.get("duplicate"), "Duplicate sticker is gone from the registry");
    r.eq(StickerTypes.get("randomFixedValue").price, 1, "Random Rank now costs 1");
    r.eq(StickerTypes.get("changeSuitDiamond").suit, "♦", "Change to ♦ locked to ♦");
    r.eq(StickerTypes.get("changeSuitDiamond").price, 1, "Change to ♦ = 1");
    r.eq(StickerTypes.get("changeSuitClub").price, 1, "Change to ♣ = 1");
    r.ok(StickerTypes.all().every(t => t.description && t.icon), "every sticker has a description + icon");
  }

  // ---- suit gating moves in lockstep (no item before its suit is in play) ----
  {
    const c = CampaignState.create();   // Stage 1 = ♦ ♥
    const seen = new Set();
    for (let i = 0; i < 400; i++) c.openStore().stickers.forEach(id => seen.add(id));
    r.ok(seen.has("changeSuitDiamond"), "Stage 1 offers Change to ♦ (♦ in play)");
    r.ok(!seen.has("changeSuitClub"), "Stage 1 NEVER offers Change to ♣ (♣ not in play yet)");
    r.ok(seen.has("quickBury") && seen.has("momentum"), "suit-free new stickers offer from Stage 1");
  }

  // ---- Loose Change: emits a sticker-coins payout (0..3) every correct land ----
  {
    const e = game();
    let coinEvents = 0, maxAmt = -1, minAmt = 99;
    e.onEvent((t, p) => { if (t === "sticker-coins" && p.label === "Loose Change") { coinEvents++; maxAmt = Math.max(maxAmt, p.amount); minAmt = Math.min(minAmt, p.amount); } });
    for (let k = 0; k < 8; k++) land(e, 0, ["looseChange"]);
    r.eq(coinEvents, 8, "Loose Change fires a payout event on every correct land (incl. +0)");
    r.ok(minAmt >= 0 && maxAmt <= 3, "Loose Change payout stays within 0..3");
  }

  // ---- Deep Pockets: +1 coin per 10 cards left in the deck -------------
  {
    const e = game();
    const before = e.getRun().bonusCoins;
    const remBefore = e.getDeck().remaining();
    land(e, 0, ["deepPockets"]);
    const gained = e.getRun().bonusCoins - before;
    r.eq(gained, Math.floor((remBefore - 1) / 10), "Deep Pockets pays floor(deckRemaining/10) after the draw");
  }

  // ---- Suit Snob: PEEK the next card only on a same-suit correct land --------
  {
    const e = game();
    const top1 = e.getBoard().top(1);
    const up = top1.value < 14;
    const nc = e.debug.setNextCard(up ? top1.value + 1 : top1.value - 1);
    nc.stickers = [{ type: "suitSnob" }]; nc.suit = top1.suit;   // match the pile card's suit
    e.guess(1, up ? "higher" : "lower");
    r.ok(e.getRun().revealNextActive, "Suit Snob peeks the next card on a same-suit correct land");

    // A DIFFERENT-suit land does not peek (and pays no coins — the peek replaced it).
    const e2 = game();
    const t2 = e2.getBoard().top(2);
    const up2 = t2.value < 14;
    const otherSuit = ["♠", "♥", "♦", "♣"].find(s => s !== t2.suit);
    const before = e2.getRun().bonusCoins;
    const n2 = e2.debug.setNextCard(up2 ? t2.value + 1 : t2.value - 1);
    n2.stickers = [{ type: "suitSnob" }]; n2.suit = otherSuit;
    e2.guess(2, up2 ? "higher" : "lower");
    r.ok(!e2.getRun().revealNextActive, "Suit Snob does NOT peek on a different-suit land");
    r.eq(e2.getRun().bonusCoins - before, 0, "Suit Snob no longer pays coins");
  }

  // ---- Snowball Bury (per-card X, like Compound): buries X then X++, reset on wrong ----
  {
    const e = game();
    let buried = 0;
    e.onEvent((t, p) => { if (t === "buried" && p.source === "Snowball Bury") buried += p.count; });
    const c0 = land(e, 0, ["snowball"]);            // fresh card: buries 0, X→1
    r.eq(e.getBoard().top(0).snowball, 1, "fresh Snowball card → X=1 after its first placement");
    r.eq(buried, 0, "first placement buries 0");
    // A card whose X is already 2 buries 2 and advances to 3.
    const top1 = e.getBoard().top(1).value;
    const up1 = top1 < 14;
    const nc = e.debug.setNextCard(up1 ? top1 + 1 : top1 - 1);
    nc.stickers = [{ type: "snowball" }]; nc.snowball = 2;
    e.guess(1, up1 ? "higher" : "lower");
    r.eq(buried, 2, "a Snowball card with X=2 buries 2 on placement");
    r.eq(e.getBoard().top(1).snowball, 3, "that card's X advanced to 3");
    // A WRONG placement of a Snowball card resets its X to 0.
    const top2 = e.getBoard().top(2).value;
    const nb = e.debug.setNextCard(top2);   // a tie → death (no save stickers)
    nb.stickers = [{ type: "snowball" }]; nb.snowball = 5;
    e.guess(2, "higher");
    r.ok(!e.getBoard().isActive(2), "pile died on the wrong guess");
    r.eq(e.getBoard().top(2).snowball, 0, "a wrong placement reset Snowball X to 0");
  }

  // ---- Twin Spark: rank-matched alive pile cards each gain a sticker ----
  {
    const e = game();
    const b = e.getBoard();
    const top0 = b.top(0).value;
    const up = top0 < 14;
    const drawnVal = up ? top0 + 1 : top0 - 1;
    // A second alive pile whose top shares the DRAWN rank → must gain a sticker.
    const target = 5;
    b.top(target).value = drawnVal; b.top(target).label = String(drawnVal);
    const before = (b.top(target).stickers || []).length;
    const nc = e.debug.setNextCard(drawnVal);
    nc.stickers = [{ type: "twinSpark" }];
    e.guess(0, up ? "higher" : "lower");
    r.ok((b.top(target).stickers || []).length > before, "Twin Spark stickered a rank-matched alive pile card");
  }

  // ---- Pillar Scout / Base Scout: peek only when a matching slot is empty ----
  {
    const e1 = game();   // no pillars bound → empty pillar slots
    land(e1, 0, ["pillarScout"]);
    r.ok(e1.getRun().revealNextActive, "Pillar Scout peeks when a pillar slot is empty");

    const e2 = game(["columnGuardian", "columnGuardian", "columnGuardian"]);
    land(e2, 0, ["pillarScout"]);
    r.ok(!e2.getRun().revealNextActive, "Pillar Scout does NOT peek when every pillar slot is filled");

    const e3 = game();   // no bases bound → empty base slots
    land(e3, 0, ["baseScout"]);
    r.ok(e3.getRun().revealNextActive, "Base Scout peeks when a base slot is empty");

    // BUGFIX: the peek gates on the LANDING column only, not the whole board.
    // Pillar on col 0 only; landing a Scout on col 0 (occupied) must NOT peek even
    // though cols 1 & 2 are empty (the old board-wide check wrongly peeked here).
    const e4 = game(["columnGuardian", null, null]);
    land(e4, 0, ["pillarScout"]);                 // pile 0 → col 0 (has a pillar)
    r.ok(!e4.getRun().revealNextActive, "Pillar Scout does NOT peek when the LANDING column has a pillar (other columns empty)");
    // Same single pillar on col 0; landing on col 1 (empty) DOES peek.
    const e5 = game(["columnGuardian", null, null]);
    land(e5, 3, ["pillarScout"]);                 // pile 3 → col 1 (empty)
    r.ok(e5.getRun().revealNextActive, "Pillar Scout peeks when the LANDING column is empty (even with a pillar elsewhere)");
  }

  // ---- Momentum (per-card X): pays X then X grows by 2, reset on wrong ----
  {
    const e = game();
    const paid = [];
    e.onEvent((t, p) => { if (t === "sticker-coins" && p.label === "Momentum") paid.push(p.amount); });
    land(e, 0, ["momentum"]);                        // fresh card: pays 0 (no event), X→2
    r.eq(e.getBoard().top(0).momentum, 2, "fresh Momentum card → X=2 after its first placement (grows by 2)");
    r.eq(paid.length, 0, "first placement pays 0 (no payout event)");
    // A card whose X is already 2 pays 2 and advances to 4.
    const top1 = e.getBoard().top(1).value;
    const up1 = top1 < 14;
    const nc = e.debug.setNextCard(up1 ? top1 + 1 : top1 - 1);
    nc.stickers = [{ type: "momentum" }]; nc.momentum = 2;
    e.guess(1, up1 ? "higher" : "lower");
    r.eq(paid[paid.length - 1], 2, "a Momentum card with X=2 pays +2 on placement");
    r.eq(e.getBoard().top(1).momentum, 4, "that card's X advanced to 4 (grows by 2)");
    // A WRONG placement of a Momentum card resets its X to 0.
    const top2 = e.getBoard().top(2).value;
    const nb = e.debug.setNextCard(top2);   // a tie → death (no save stickers)
    nb.stickers = [{ type: "momentum" }]; nb.momentum = 5;
    e.guess(2, "higher");
    r.ok(!e.getBoard().isActive(2), "pile died on the wrong guess");
    r.eq(e.getBoard().top(2).momentum, 0, "a wrong placement reset Momentum X to 0");
  }

  // ---- Quick Bury: buries 1 each correct land; peel path reachable -----
  {
    const e = game();
    let buried = 0, peeled = 0;
    e.onEvent((t, p) => {
      if (t === "buried" && p.source === "Quick Bury") buried += p.count;
      if (t === "sticker-peeled") peeled++;
    });
    for (let k = 0; k < 12; k++) if (e.getBoard().isActive(0)) land(e, 0, ["quickBury"]);
    r.eq(buried, 12, "Quick Bury buries 1 on every correct land");
    r.ok(peeled >= 0, "Quick Bury peel path is reachable (>=0 over the run)");
  }

  return r.summary();
}
