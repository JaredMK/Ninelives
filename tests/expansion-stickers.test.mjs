// Expansion stickers (content pass): the 10 new behavior stickers + the two
// completed suit-change stickers. DOM-free — drive the engine directly and
// assert on board/deck/run + event payloads, plus registry/gating checks.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, CampaignState, StickerTypes, Stats } = loadGame();
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
      "suitSnob"];
    r.ok(ids.every(id => !!StickerTypes.get(id)), "the new stickers are registered");
    r.eq(StickerTypes.all().length, StickerTypes.ids.length, "sticker registry all() matches its live id list");
    r.ok(!StickerTypes.get("mirror"), "Mirror sticker is gone from the registry");
    r.ok(!StickerTypes.get("duplicate"), "Duplicate sticker is gone from the registry");
    r.ok(!StickerTypes.get("momentum"), "Momentum sticker is gone from the registry");
    r.ok(!StickerTypes.get("extraHeart"), "Shield (extraHeart) sticker is gone from the registry");
    r.ok(!StickerTypes.get("middleColumnReward"), "Focus (middleColumnReward) sticker is gone");
    r.ok(!StickerTypes.get("centerTribute"), "Middle Bury (centerTribute) sticker is gone");
    r.eq(StickerTypes.get("randomFixedValue").price, 1, "Random Rank now costs 1");
    r.eq(StickerTypes.get("changeSuitDiamond").suit, "♦", "Change to ♦ locked to ♦");
    r.eq(StickerTypes.get("changeSuitDiamond").price, 1, "Change to ♦ = 1");
    r.eq(StickerTypes.get("changeSuitClub").price, 1, "Change to ♣ = 1");
    r.ok(StickerTypes.all().every(t => t.description && t.icon), "every sticker has a description + icon");
  }

  // ---- stage gating REMOVED: every sticker can offer at any time ----------
  {
    const c = CampaignState.create();   // Stage 1 = ♦ ♥
    const seen = new Set();
    for (let i = 0; i < 1500; i++)
      c.openStore().slots.forEach(s => { if (s && s.kind === "sticker") seen.add(s.id); });
    r.ok(seen.has("changeSuitDiamond"), "Stage 1 offers Change to ♦");
    r.ok(seen.has("changeSuitClub"), "Stage 1 offers Change to ♣ too (gating removed — all items any time)");
    r.ok(seen.has("changeSuitSpade"), "…and Change to ♠");
    // quickBury is unlock-gated now (UNLOCK2): prove the any-stage rule by
    // seeding its stat and resampling.
    {
      Stats.bump("cardsBuried", 999);
      const c2 = CampaignState.create();
      const seen2 = new Set();
      for (let i = 0; i < 1500 && !seen2.has("quickBury"); i++)
        c2.openStore().slots.forEach(s => { if (s && s.kind === "sticker") seen2.add(s.id); });
      r.ok(seen2.has("quickBury"), "suit-free stickers offer from Stage 1 once unlocked");
      Stats.reset();
    }
  }

  // ---- Loose Change: emits a sticker-coins payout (0..max) every correct land ----
  {
    const e = game();
    let coinEvents = 0, maxAmt = -1, minAmt = 99;
    e.onEvent((t, p) => { if (t === "sticker-coins" && p.label === "Loose Change") { coinEvents++; maxAmt = Math.max(maxAmt, p.amount); minAmt = Math.min(minAmt, p.amount); } });
    for (let k = 0; k < 8; k++) land(e, 0, ["looseChange"]);
    r.eq(coinEvents, 8, "Loose Change fires a payout event on every correct land (incl. +0)");
    const lcMax = Number(StickerTypes.get("looseChange").max);
    r.ok(minAmt >= 0 && maxAmt <= lcMax, "Loose Change payout stays within 0.." + lcMax);
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

  // ---- SPADE Snob: the snob sits on the PILE TOP and PEEKS when a ♠ LANDS
  //      ON it (direction flip — the DRAWN card's suit decides). --------------
  {
    const e = game();
    const top1 = e.getBoard().top(1);
    top1.stickers = [{ type: "suitSnob" }]; top1.wildSuit = false;   // snob rides the pile top
    const up = top1.value < 14;
    const nc = e.debug.setNextCard(up ? top1.value + 1 : top1.value - 1);
    nc.suit = "♠"; nc.wildSuit = false;                              // a ♠ lands on it
    e.guess(1, up ? "higher" : "lower");
    r.ok(e.getRun().revealNextActive, "Spade Snob peeks when a ♠ lands on the stickered top");

    // A non-♠ landing does not peek (and pays no coins).
    const e2 = game();
    const t2 = e2.getBoard().top(2);
    t2.stickers = [{ type: "suitSnob" }]; t2.wildSuit = false;
    const up2 = t2.value < 14;
    const before = e2.getRun().bonusCoins;
    const n2 = e2.debug.setNextCard(up2 ? t2.value + 1 : t2.value - 1);
    n2.suit = "♥"; n2.wildSuit = false;                              // a ♥ lands on it
    e2.guess(2, up2 ? "higher" : "lower");
    r.ok(!e2.getRun().revealNextActive, "Spade Snob does NOT peek when a non-♠ lands on it");
    r.eq(e2.getRun().bonusCoins - before, 0, "Spade Snob pays no coins");
  }

  // ---- Heart / Diamond / Club Snobs: each fires when its suit LANDS ON the
  //      stickered top (snob on the pile card, matching-suit card drawn). ------
  {
    // Heart Snob: +value coins when a ♥ lands on the stickered top.
    const hv = StickerTypes.get("heartSnob").value ?? 4;
    const e = game();
    const t = e.getBoard().top(1); t.stickers = [{ type: "heartSnob" }]; t.wildSuit = false;
    const before = e.getRun().bonusCoins;
    const nc = e.debug.setNextCard(t.value < 14 ? t.value + 1 : t.value - 1);
    nc.suit = "♥"; nc.wildSuit = false;
    e.guess(1, t.value < 14 ? "higher" : "lower");
    r.eq(e.getRun().bonusCoins - before, hv, "Heart Snob pays +" + hv + " when a ♥ lands on it");

    const e2 = game();
    const t2 = e2.getBoard().top(2); t2.stickers = [{ type: "heartSnob" }]; t2.wildSuit = false;
    const b2 = e2.getRun().bonusCoins;
    const n2 = e2.debug.setNextCard(t2.value < 14 ? t2.value + 1 : t2.value - 1);
    n2.suit = "♣"; n2.wildSuit = false;
    e2.guess(2, t2.value < 14 ? "higher" : "lower");
    r.eq(e2.getRun().bonusCoins - b2, 0, "Heart Snob pays nothing when a non-♥ lands on it");
  }
  {
    // Diamond Snob: a ♦ landing on the stickered top shuffles ALL alive piles
    // (composition only — assert via the pillar-fired shuffler event).
    const e = game();
    let fired = null;
    e.onEvent((type, x) => { if (type === "pillar-fired" && x.label === "Diamond Snob") fired = x; });
    const t = e.getBoard().top(1); t.stickers = [{ type: "diamondSnob" }]; t.wildSuit = false;
    const nc = e.debug.setNextCard(t.value < 14 ? t.value + 1 : t.value - 1);
    nc.suit = "♦"; nc.wildSuit = false;
    e.guess(1, t.value < 14 ? "higher" : "lower");
    r.ok(fired && fired.effect === "shuffler", "Diamond Snob fires the shuffle when a ♦ lands on it");

    const e2 = game();
    let fired2 = null;
    e2.onEvent((type, x) => { if (type === "pillar-fired" && x.label === "Diamond Snob") fired2 = x; });
    const t2 = e2.getBoard().top(2); t2.stickers = [{ type: "diamondSnob" }]; t2.wildSuit = false;
    const n2 = e2.debug.setNextCard(t2.value < 14 ? t2.value + 1 : t2.value - 1);
    n2.suit = "♠"; n2.wildSuit = false;
    e2.guess(2, t2.value < 14 ? "higher" : "lower");
    r.ok(!fired2, "Diamond Snob does nothing when a non-♦ lands on it");
  }
  {
    // Club Snob: a ♣ landing on the stickered top buries digCount deck cards.
    const dig = StickerTypes.get("clubSnob").digCount ?? 1;
    const e = game();
    const t = e.getBoard().top(1); t.stickers = [{ type: "clubSnob" }]; t.wildSuit = false;
    const len0 = e.getBoard().piles[1].cards.length;
    const deck0 = e.getDeck().remaining();
    const nc = e.debug.setNextCard(t.value < 14 ? t.value + 1 : t.value - 1);
    nc.suit = "♣"; nc.wildSuit = false;
    e.guess(1, t.value < 14 ? "higher" : "lower");
    r.eq(e.getBoard().piles[1].cards.length, len0 + 1 + dig, "Club Snob buries " + dig + " when a ♣ lands on it (pile: drawn + buried)");
    r.eq(e.getDeck().remaining(), deck0 - 1 - dig, "…drawn from the deck");

    const e2 = game();
    const t2 = e2.getBoard().top(2); t2.stickers = [{ type: "clubSnob" }]; t2.wildSuit = false;
    const l2 = e2.getBoard().piles[2].cards.length;
    const n2 = e2.debug.setNextCard(t2.value < 14 ? t2.value + 1 : t2.value - 1);
    n2.suit = "♥"; n2.wildSuit = false;
    e2.guess(2, t2.value < 14 ? "higher" : "lower");
    r.eq(e2.getBoard().piles[2].cards.length, l2 + 1, "Club Snob buries nothing when a non-♣ lands on it");
  }

  // ---- suit-SYNERGY family: scale by OTHER piles topped by their suit ----
  {
    // Heart Choir: +value per other \u2665-topped pile (the landing pile never counts).
    const hv = StickerTypes.get("heartChoir").value ?? 1;
    const e = game();
    const b = e.getBoard();
    for (let i = 0; i < b.size; i++) { b.top(i).suit = "\u2660"; b.top(i).wildSuit = false; }
    b.top(3).suit = "\u2665"; b.top(7).suit = "\u2665";      // two OTHER hearts
    b.top(1).suit = "\u2665";                                 // the landing pile - excluded
    const before = e.getRun().bonusCoins;
    land(e, 1, ["heartChoir"]);
    r.eq(e.getRun().bonusCoins - before, 2 * hv, "Heart Choir pays per OTHER \u2665 top (2 others, landing pile excluded)");
  }
  {
    // Diamond Ripple: shuffles every OTHER \u2666-topped pile (event contract).
    const e = game();
    const b = e.getBoard();
    for (let i = 0; i < b.size; i++) { b.top(i).suit = "\u2660"; b.top(i).wildSuit = false; }
    b.top(2).suit = "\u2666"; b.top(5).suit = "\u2666";
    let fired = null;
    e.onEvent((type, x) => { if (type === "pillar-fired" && x.label === "Diamond Ripple") fired = x; });
    land(e, 1, ["diamondRipple"]);
    r.ok(fired && fired.effect === "shuffler", "Diamond Ripple fires the shuffle when other \u2666 tops exist");

    const e2 = game();
    const b2 = e2.getBoard();
    for (let i = 0; i < b2.size; i++) { b2.top(i).suit = "\u2660"; b2.top(i).wildSuit = false; }
    let fired2 = null;
    e2.onEvent((type, x) => { if (type === "pillar-fired" && x.label === "Diamond Ripple") fired2 = x; });
    land(e2, 1, ["diamondRipple"]);
    r.ok(!fired2, "Diamond Ripple does nothing with no other \u2666 tops");
  }
  {
    // Club Roots: buries digCount under EACH OTHER \u2663-topped pile \u2014 never the
    // LANDING pile (even if its own top is \u2663 after the land).
    const dig = StickerTypes.get("clubRoots").digCount ?? 1;
    const e = game();
    const b = e.getBoard();
    for (let i = 0; i < b.size; i++) { b.top(i).suit = "\u2660"; b.top(i).wildSuit = false; }
    b.top(0).suit = "\u2663"; b.top(4).suit = "\u2663"; b.top(8).suit = "\u2663";   // three OTHER clubs
    const l0 = b.piles[0].cards.length, l4 = b.piles[4].cards.length, l8 = b.piles[8].cards.length;
    const l1 = b.piles[1].cards.length;
    land(e, 1, ["clubRoots"]);
    r.eq(e.getBoard().piles[1].cards.length, l1 + 1, "Club Roots buries nothing under the LANDING pile (drawn card only)");
    r.eq(e.getBoard().piles[0].cards.length, l0 + dig, "\u2026buries " + dig + " under other \u2663 pile 0");
    r.eq(e.getBoard().piles[4].cards.length, l4 + dig, "\u2026and under \u2663 pile 4");
    r.eq(e.getBoard().piles[8].cards.length, l8 + dig, "\u2026and under \u2663 pile 8");
  }
  {
    // Spade Whispers: the next X draws hint on EVERY pile, X = other \u2660 tops.
    const e = game();
    const b = e.getBoard();
    for (let i = 0; i < b.size; i++) { b.top(i).suit = "\u2665"; b.top(i).wildSuit = false; }
    b.top(2).suit = "\u2660"; b.top(6).suit = "\u2660";      // two OTHER spades -> X = 2
    r.ok(e.pileHint(3) == null, "no hints before the Whisper lands");
    land(e, 1, ["spadeWhispers"]);
    r.eq(e.getRun().tellDrawsLeft, 2, "Spade Whispers arms X = other \u2660 tops (2)");
    r.ok(e.pileHint(3) != null && e.pileHint(5) != null, "EVERY alive pile hints while whispered");
    land(e, 0, []);   // one draw consumes one whisper
    r.eq(e.getRun().tellDrawsLeft, 1, "a draw consumes one whispered hint");
    r.ok(e.pileHint(3) != null, "hints persist while whispers remain");
    land(e, 0, []);
    r.eq(e.getRun().tellDrawsLeft, 0, "the second draw spends the last whisper");
    r.ok(e.pileHint(3) == null, "hints gone once the whispers are spent");
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

  // ---- Twin Spark: peek the next card if another alive pile shares the rank ----
  {
    const e = game();
    const b = e.getBoard();
    const top0 = b.top(0).value;
    const up = top0 < 14;
    const drawnVal = up ? top0 + 1 : top0 - 1;
    // A second alive pile whose top shares the DRAWN rank → the peek arms.
    b.top(5).value = drawnVal; b.top(5).label = String(drawnVal);
    const nc = e.debug.setNextCard(drawnVal);
    nc.stickers = [{ type: "twinSpark" }];
    e.guess(0, up ? "higher" : "lower");
    r.ok(e.getRun().revealNextActive, "Twin Spark peeks the next card when another pile shares the drawn rank");
  }

  // ---- Twin Spark: no matching pile → no peek ----
  {
    const e = game();
    const b = e.getBoard();
    const top0 = b.top(0).value;
    const up = top0 < 14;
    const drawnVal = up ? top0 + 1 : top0 - 1;
    // Make sure NO other alive pile shares the drawn rank.
    for (let i = 1; i < b.size; i++) { const v = drawnVal === 2 ? 3 : 2; b.top(i).value = v; b.top(i).label = String(v); }
    const nc = e.debug.setNextCard(drawnVal);
    nc.stickers = [{ type: "twinSpark" }];
    e.guess(0, up ? "higher" : "lower");
    r.ok(!e.getRun().revealNextActive, "Twin Spark does NOT peek when no other pile shares the drawn rank");
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

  // (Momentum was removed from the roster — its per-card coin counter is gone.)

  // ---- Quick Bury: buries 1 each correct land and NEVER peels -----------
  {
    const e = game();
    let buried = 0, peeled = 0;
    e.onEvent((t, p) => {
      if (t === "buried" && p.source === "Quick Bury") buried += p.count;
      if (t === "sticker-peeled") peeled++;
    });
    for (let k = 0; k < 12; k++) if (e.getBoard().isActive(0)) land(e, 0, ["quickBury"]);
    r.eq(buried, 12, "Quick Bury buries 1 on every correct land");
    r.eq(peeled, 0, "Quick Bury never peels — the sticker persists (peelChance gone)");
  }

  return r.summary();
}
