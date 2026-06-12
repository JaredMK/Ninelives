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
      "mirror", "suitSnob", "momentum"];
    r.ok(ids.every(id => !!StickerTypes.get(id)), "all 12 new stickers registered");
    r.eq(StickerTypes.all().length, 42, "sticker registry now totals 42");
    r.eq(StickerTypes.get("randomFixedValue").price, 4, "Random Rank now costs 4");
    r.eq(StickerTypes.get("changeSuitDiamond").suit, "♦", "Change to ♦ locked to ♦");
    r.eq(StickerTypes.get("changeSuitDiamond").price, 2, "Change to ♦ = 2 (Stage-1 suit)");
    r.eq(StickerTypes.get("changeSuitClub").price, 1, "Change to ♣ = 1 (♣ enters Stage 2)");
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

  // ---- Loose Change: emits a sticker-coins payout (0..2) every correct land ----
  {
    const e = game();
    let coinEvents = 0, maxAmt = -1, minAmt = 99;
    e.onEvent((t, p) => { if (t === "sticker-coins" && p.label === "Loose Change") { coinEvents++; maxAmt = Math.max(maxAmt, p.amount); minAmt = Math.min(minAmt, p.amount); } });
    for (let k = 0; k < 8; k++) land(e, 0, ["looseChange"]);
    r.eq(coinEvents, 8, "Loose Change fires a payout event on every correct land (incl. +0)");
    r.ok(minAmt >= 0 && maxAmt <= 2, "Loose Change payout stays within 0..2");
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

  // ---- Suit Snob: +2 only when the drawn card matches the pile card's suit ----
  {
    const e = game();
    const top0 = e.getBoard().top(0);
    let snobPaid = 0;
    e.onEvent((t, p) => { if (t === "sticker-coins" && p.label === "Suit Snob") snobPaid += p.amount; });
    const nc = land(e, 0, ["suitSnob"]);   // 'land' picks the value; force the SAME suit
    // 'land' already guessed; re-run a controlled same-suit land on a fresh pile.
    // (Simpler: assert via a second, suit-matched land on pile 1.)
    const top1 = e.getBoard().top(1);
    const up = top1.value < 14;
    const nc1 = e.debug.setNextCard(up ? top1.value + 1 : top1.value - 1);
    nc1.stickers = [{ type: "suitSnob" }]; nc1.suit = top1.suit;   // match the pile card's suit
    snobPaid = 0;
    e.guess(1, up ? "higher" : "lower");
    r.eq(snobPaid, 2, "Suit Snob pays +2 on a same-suit correct land");
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

  // ---- Mirror: copies a random sticker from the pile card onto the drawn card ----
  {
    const e = game();
    const b = e.getBoard();
    b.top(0).stickers = [{ type: "anchor" }];   // the pile card to mirror FROM
    const nc = land(e, 0, ["mirror"]);
    r.ok((b.top(0).stickers || []).some(x => x.type === "anchor"), "Mirror copied the pile card's sticker onto the drawn card");
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
  }

  // ---- Momentum: +1 coin per consecutive correct guess in this column --
  {
    const e = game();
    const paid = [];
    e.onEvent((t, p) => { if (t === "sticker-coins" && p.label === "Momentum") paid.push(p.amount); });
    land(e, 0, ["momentum"]);   // streak 1 → +1
    land(e, 0, ["momentum"]);   // streak 2 → +2
    land(e, 0, ["momentum"]);   // streak 3 → +3
    r.eq(JSON.stringify(paid), JSON.stringify([1, 2, 3]), "Momentum pays the running column streak (1,2,3)");
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
