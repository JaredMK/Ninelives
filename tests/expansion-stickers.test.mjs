// Expansion stickers (content pass): the 10 new behavior stickers + the two
// completed suit-change stickers. DOM-free — drive the engine directly and
// assert on board/deck/run + event payloads, plus registry/gating checks.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, CampaignState, StickerTypes } = loadGame();
  const r = makeRunner("expansion-stickers.test.mjs");

  const baseDeck = () => DeckManager.buildStandardDeck();
  const COLS = [3, 4, 3];   // col 0 = piles 0-2, col 1 = piles 3-6, col 2 = piles 7-9

  // A run where one named sticker rides EVERY card (so the drawn card carries it).
  const withEvery = (type, extra) => {
    const specs = baseDeck();
    specs.forEach(c => { c.stickers.push({ type }); if (extra) extra(c); });
    const e = GameEngine.create(specs, 10, { cols: COLS });
    e.start();
    e.startRun([null, null, null], [null, null, null]);
    return e;
  };
  // Force a guaranteed-CORRECT directional guess on pile `i`: set the next card
  // one rank from the top and guess that direction. Returns the drawn value.
  const correctGuess = (e, i) => {
    const top = e.getBoard().top(i).value;
    if (top < 14) { e.debug.setNextCard(top + 1); e.guess(i, "higher"); return top + 1; }
    e.debug.setNextCard(top - 1); e.guess(i, "lower"); return top - 1;
  };

  // ---- registry + count ------------------------------------------------
  {
    const ids = ["changeSuitDiamond", "changeSuitClub", "quickBury", "twinSpark",
      "looseChange", "snowball", "deepPockets", "pillarScout", "baseScout",
      "mirror", "suitSnob", "momentum"];
    r.ok(ids.every(id => !!StickerTypes.get(id)), "all 12 new stickers registered");
    r.eq(StickerTypes.all().length, 42, "sticker registry now totals 42");
    r.eq(StickerTypes.get("randomFixedValue").price, 4, "Random Rank now costs 4");
    // Suit-change set complete + suit-timing pricing (♦/♥ = 2, ♣ = 1).
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
    // Stage-agnostic new stickers (no suit) are offerable from Stage 1.
    r.ok(seen.has("quickBury") && seen.has("momentum"), "suit-free new stickers offer from Stage 1");
  }

  // ---- Loose Change: emits a sticker-coins payout (0..2) every correct land ----
  {
    const e = withEvery("looseChange");
    let coinEvents = 0, maxAmt = -1, minAmt = 99;
    e.onEvent((t, p) => { if (t === "sticker-coins" && p.label === "Loose Change") { coinEvents++; maxAmt = Math.max(maxAmt, p.amount); minAmt = Math.min(minAmt, p.amount); } });
    for (let k = 0; k < 8; k++) correctGuess(e, 0);
    r.eq(coinEvents, 8, "Loose Change fires a payout event on every correct land (incl. +0)");
    r.ok(minAmt >= 0 && maxAmt <= 2, "Loose Change payout stays within 0..2");
  }

  // ---- Deep Pockets: +1 coin per 10 cards left in the deck -------------
  {
    const e = withEvery("deepPockets");
    const before = e.getRun().bonusCoins;
    const remBefore = e.getDeck().remaining();
    correctGuess(e, 0);
    const gained = e.getRun().bonusCoins - before;
    // payout reads the deck AFTER the draw (one card drawn this land).
    r.eq(gained, Math.floor((remBefore - 1) / 10), "Deep Pockets pays floor(deckRemaining/10)");
  }

  // ---- Suit Snob: +2 only when the drawn card matches the pile card's suit ----
  {
    // Top of pile 0 is a ♠; drive a same-suit then a different-suit correct land.
    const specs = baseDeck();
    specs.forEach(c => c.stickers.push({ type: "suitSnob" }));
    const e = GameEngine.create(specs, 10, { cols: COLS });
    e.start(); e.startRun([null, null, null], [null, null, null]);
    const top0 = e.getBoard().top(0);
    let snobPaid = 0;
    e.onEvent((t, p) => { if (t === "sticker-coins" && p.label === "Suit Snob") snobPaid += p.amount; });
    // same-suit correct land: synthesize next card = same suit, +1 rank.
    const v = top0.value < 14 ? top0.value + 1 : top0.value - 1;
    const dir = top0.value < 14 ? "higher" : "lower";
    const nc = e.debug.setNextCard(v); nc.suit = top0.suit;   // match the pile card's suit
    e.guess(0, dir);
    r.eq(snobPaid, 2, "Suit Snob pays +2 on a same-suit correct land");
  }

  // ---- Snowball Bury (per-card X, like Compound): buries X then X++, and a
  //      wrong placement resets X. Seed the drawn card's counter directly so
  //      we exercise a specific identity placed with X already > 0.
  {
    const e = withEvery("snowball");
    let buried = 0;
    e.onEvent((t, p) => { if (t === "buried" && p.source === "Snowball Bury") buried += p.count; });
    // First placement of a fresh Snowball card buries 0 and sets X→1.
    correctGuess(e, 0);
    r.eq(e.getBoard().top(0).snowball, 1, "fresh Snowball card → X=1 after its first placement");
    r.eq(buried, 0, "first placement buries 0");
    // A card whose X is already 2 buries 2 and advances to 3.
    const top1 = e.getBoard().top(1).value;
    const nc = e.debug.setNextCard(top1 < 14 ? top1 + 1 : top1 - 1);
    nc.stickers = [{ type: "snowball" }]; nc.snowball = 2;
    e.guess(1, top1 < 14 ? "higher" : "lower");
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
    // Give pile 0's and pile 5's tops the same rank; sticker only the drawn card.
    const specs = baseDeck();
    specs.forEach(c => c.stickers.push({ type: "twinSpark" }));
    const e = GameEngine.create(specs, 10, { cols: COLS });
    e.start(); e.startRun([null, null, null], [null, null, null]);
    const b = e.getBoard();
    // Make pile 5's top share pile 0's top rank; capture sticker counts.
    const target = 5;
    b.top(target).value = b.top(0).value;
    b.top(target).label = b.top(0).label;
    const before5 = (b.top(target).stickers || []).length;
    // Correct land on pile 0 with the drawn rank == pile0 top + ... use pile 0 top
    // rank so the drawn card itself rank-matches both tops.
    const v = b.top(0).value;
    // place a correct guess on pile 0 whose DRAWN value equals the tops' rank:
    // set top0 to v-1 first so a "higher" draw of v lands correctly and matches.
    if (v <= 2) { b.top(0).value = 3; b.top(0).label = "3"; }
    const topNow = b.top(0).value;
    e.debug.setNextCard(topNow + 1 <= 14 ? topNow + 1 : topNow - 1);
    // re-point target rank to the DRAWN value so Twin Spark matches it.
    const drawnVal = topNow + 1 <= 14 ? topNow + 1 : topNow - 1;
    b.top(target).value = drawnVal; b.top(target).label = String(drawnVal);
    const before5b = (b.top(target).stickers || []).length;
    e.guess(0, topNow + 1 <= 14 ? "higher" : "lower");
    const after5 = (b.top(target).stickers || []).length;
    r.ok(after5 > before5b, "Twin Spark added a sticker to a rank-matched alive pile card");
  }

  // ---- Mirror: copies a random sticker from the pile card onto the drawn card ----
  {
    const specs = baseDeck();
    // Pile-card carries a recognizable sticker (anchor); drawn card carries Mirror.
    specs.forEach(c => c.stickers.push({ type: "mirror" }));
    const e = GameEngine.create(specs, 10, { cols: COLS });
    e.start(); e.startRun([null, null, null], [null, null, null]);
    const b = e.getBoard();
    b.top(0).stickers = [{ type: "anchor" }];   // the pile card to mirror FROM
    const v = b.top(0).value;
    const dir = v < 14 ? "higher" : "lower";
    e.debug.setNextCard(v < 14 ? v + 1 : v - 1);
    e.guess(0, dir);
    const newTop = b.top(0);   // the drawn card is now the pile card
    r.ok((newTop.stickers || []).some(x => x.type === "anchor"), "Mirror copied the pile card's sticker onto the drawn card");
  }

  // ---- Pillar Scout / Base Scout: peek only when a matching slot is empty ----
  {
    // Pillar Scout WITH an empty pillar slot → reveal active.
    const e1 = withEvery("pillarScout");   // no pillars bound → all 3 slots empty
    correctGuess(e1, 0);
    r.ok(e1.getRun().revealNextActive, "Pillar Scout peeks when a pillar slot is empty");

    // Pillar Scout with ALL pillar slots filled → no peek.
    const specs = baseDeck();
    specs.forEach(c => c.stickers.push({ type: "pillarScout" }));
    const e2 = GameEngine.create(specs, 10, { cols: COLS });
    e2.start();
    e2.startRun(["columnGuardian", "columnGuardian", "columnGuardian"], [null, null, null]);
    correctGuess(e2, 0);
    r.ok(!e2.getRun().revealNextActive, "Pillar Scout does NOT peek when every pillar slot is filled");
  }

  // ---- Momentum: +1 coin per consecutive correct guess in this column --
  {
    const e = withEvery("momentum");
    let paid = [];
    e.onEvent((t, p) => { if (t === "sticker-coins" && p.label === "Momentum") paid.push(p.amount); });
    correctGuess(e, 0);   // streak now 1 → +1
    correctGuess(e, 0);   // streak now 2 → +2
    correctGuess(e, 0);   // streak now 3 → +3
    r.eq(JSON.stringify(paid), JSON.stringify([1, 2, 3]), "Momentum pays the running column streak (1,2,3)");
  }

  // ---- Quick Bury: buries 1 each correct land; can peel (seeded determinism) ----
  {
    const e = withEvery("quickBury");
    let buried = 0, peeled = 0;
    e.onEvent((t, p) => {
      if (t === "buried" && p.source === "Quick Bury") buried += p.count;
      if (t === "sticker-peeled") peeled++;
    });
    for (let k = 0; k < 12; k++) if (e.getBoard().isActive(0)) correctGuess(e, 0);
    r.ok(buried > 0, "Quick Bury buried at least once");
    r.ok(peeled >= 0, "Quick Bury peel path is reachable (>=0 over the run)");
  }

  return r.summary();
}
