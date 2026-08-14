// New gameplay features: rarity tiers, ±2 rank + Random Rank stickers, Spade
// Guard, the live bonus-coin effects (Middle Reward, Lucky Coin, sticker
// Tributes), the new Pillars (Double Tribute, All Hearts), and Economy folding
// the live bonus into the payout. Engine modules are DOM-free (see _harness).
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, CampaignState, StickerTypes, PillarTypes, Economy } = loadGame();
  const r = makeRunner("features.test.mjs");

  // Every card carries `type`, so whatever is drawn/showing carries it.
  const specsWith = (type) => {
    const specs = DeckManager.buildStandardDeck();
    specs.forEach(c => c.stickers.push({ type }));
    return specs;
  };
  // A GUARANTEED next draw: setNextCard(v) returns undefined when every copy of
  // v was already dealt onto the opening piles (rare shuffle — a real observed
  // flake), so inject a concrete card object instead (the same path the Joker
  // tests use), immune to the shuffle. `extra` merges extra fields (guards…).
  let __nid = 880001;
  const forceNext = (e, value, suit, extra) => e.debug.setNextCardObj(Object.assign({
    id: __nid++, label: String(value), value, suit: suit || "\u2660",
    red: suit === "\u2665" || suit === "\u2666", stickers: [], suitGuards: {}, heartsRemaining: 0,
  }, extra || {}));
  // Force a guaranteed-correct HIGHER landing on pile `index`: show low, draw
  // high. Uses setNextCard (REORDERS the real deck — its cards carry the
  // specsWith stickers and the deck count is unchanged, which the Tribute
  // blocks assert on); setNextCard returns undefined when every copy of a
  // value was dealt onto the opening piles (rare shuffle), so walk the high
  // ranks until one is still in the deck — any value above 5 lands.
  const landHigher = (e, index) => {
    e.getBoard().top(index).value = 5;
    // Pick a rank that is REALLY still in the deck: since the swap-on-
    // synthesize rewrite, _setNext always returns a card — for an exhausted
    // rank it returns a SYNTHETIC sticker-less one, which silently broke the
    // sticker blocks on shuffles that dealt all four copies onto the piles.
    const inDeck = new Set(e.getDeck()._peekAll().map(c => c.value));
    const v = [9, 10, 11, 12, 13, 8, 7, 6].find(x => inDeck.has(x));
    if (v == null) throw new Error("landHigher: no high card left in the deck");
    e.debug.setNextCard(v);
    e.guess(index, "higher");
  };

  // --- Rarity tiers: every type carries a valid tier --------------------
  {
    const valid = new Set(["common", "uncommon", "rare"]);
    const bad = [];
    StickerTypes.all().forEach(t => { if (!valid.has(t.tier)) bad.push("sticker:" + t.id); });
    PillarTypes.all().forEach(t => { if (!valid.has(t.tier)) bad.push("pillar:" + t.id); });
    r.eq(bad.join(",") || "none", "none", "every sticker & Pillar has a valid rarity tier");
  }

  // --- New registry entries: SEMANTIC knobs pinned (they define the item),
  //     TUNING knobs (price / value / coinCost) checked for shape only —
  //     those are hand-edited in items.js and must stay free to change. ----
  {
    const num = (t, k, name) => r.ok(typeof StickerTypes.get(t)[k] === "number" && StickerTypes.get(t)[k] > 0, name + " is a positive number (items.js knob; currently " + StickerTypes.get(t)[k] + ")");
    r.eq(StickerTypes.get("rankUp2").rankDelta, +2, "+2 Rank delta");
    r.eq(StickerTypes.get("rankDown2").rankDelta, -2, "−2 Rank delta");
    num("rankUp2", "price", "+2 Rank price");
    num("randomFixedValue", "price", "Random Rank price");
    num("suitImmunity", "price", "Spade Guard price");
    num("gainCoin", "value", "Lucky Coin payout");
    // v6.51: Bury 1 / Bury 2 are retired; Quick Bury (ungated, rare) is the
    // cardsBuried ladder's only seed source.
    r.ok(!StickerTypes.get("oneTribute") && !StickerTypes.get("twoTribute"), "Bury 1 / Bury 2 are retired");
    num("quickBury", "price", "Quick Bury price");
    r.eq(PillarTypes.get("allHeartsCoin").price, 4, "All Hearts price 4");
    r.eq(PillarTypes.get("allHeartsCoin").value, 4, "All Hearts pays 4");
    r.eq(PillarTypes.get("allHeartsCoin").tier, "common", "All Hearts is Common");
    // The other-suit All-* Pillars were removed in the rebalance; only ♥ remains.
    for (const id of ["allSpadesCoin", "allDiamondsCoin", "allClubsCoin"]) {
      r.ok(!PillarTypes.get(id), id + " was removed");
    }
    r.eq(PillarTypes.get("allHeartsCoin").effect, "allSuitTop", "All Hearts is end-of-run scoring");
  }

  // --- ±2 Rank clamps at the rank boundaries ----------------------------
  {
    const c = CampaignState.create();
    const king = c.getCards().find(x => x.currentRank === 13);
    r.ok(c.applySticker(king.id, "rankUp2"), "apply +2 to a King");
    r.eq(c.getCards().find(x => x.id === king.id).currentRank, 14, "+2 on a King clamps to Ace (14)");
    r.ok(!c.canApplyStickerById(king.id, "rankUp2"), "+2 blocked once already at Ace");

    const three = c.getCards().find(x => x.currentRank === 3);
    r.ok(c.applySticker(three.id, "rankDown2"), "apply −2 to a 3");
    r.eq(c.getCards().find(x => x.id === three.id).currentRank, 2, "−2 on a 3 clamps to a 2");
    r.ok(!c.canApplyStickerById(three.id, "rankDown2"), "−2 blocked once already at 2");
  }

  // --- Random Rank: sets a rank in [2,14], records it -------------------
  {
    const c = CampaignState.create();
    const card = c.getCards()[0];
    r.ok(c.applySticker(card.id, "randomFixedValue"), "apply Random Rank");
    const after = c.getCards().find(x => x.id === card.id);
    r.ok(after.currentRank >= 2 && after.currentRank <= 14, "Random Rank lands in [2, Ace]");
    r.ok(after.modifications.some(m => m.op === "randomRank"), "records a randomRank modification");
    r.ok(after.stickers.some(s => s.type === "randomFixedValue"), "Random Rank sticker recorded for its badge");
  }

  // --- Suit Guard family: one guard sticker per base suit (BIDIRECTIONAL +
  // UNLIMITED). The four guards share ONE behavior ("suitImmunity"), each locked
  // to its suit. A guard fires whenever the guarded suit is involved in a draw,
  // in EITHER direction, and NEVER spends — it saves repeatedly all run.
  {
    const SUIT_GUARDS = [
      ["suitImmunity", "♠"], ["heartGuard", "♥"],
      ["diamondGuard", "♦"], ["clubGuard", "♣"],
    ];
    SUIT_GUARDS.forEach(([id, suit]) => {
      const t = StickerTypes.get(id);
      r.eq(t && t.behavior, "suitImmunity", id + " reuses the shared suitImmunity behavior");
      r.eq(t && t.suit, suit, id + " is locked to " + suit);
      // Tier + price are hand-tuned in items.js — assert shape, read live.
      r.ok(t && t.price > 0, id + " has a positive price (items.js knob; currently " + (t && t.price) + ")");

      const e = GameEngine.create(specsWith(id), 9);
      e.start(); e.startRun();
      const b = e.getBoard();
      r.ok(b.top(0).suitGuards && b.top(0).suitGuards[suit], id + " projects a " + suit + " charge");

      // DIRECTION (a): the GUARD CARD is DRAWN onto a top of its guarded suit →
      // the wrong guess is safe. (`before` read AFTER the injection: forceNext
      // ADDS a card, so the baseline must include it.)
      b.top(0).value = 10; b.top(0).suit = suit;          // top IS the guarded suit
      const d = forceNext(e, 3, "♠", { suitGuards: { [suit]: true } });   // a drawn guard card
      const before = e.getDeck().remaining();
      e.guess(0, "higher");                               // loses on HIGHER (drawn suit irrelevant)
      r.ok(b.isActive(0), id + ": a guard card drawn onto a " + suit + " absorbs the wrong guess");
      r.ok(d.suitGuards[suit], id + ": the guard is UNLIMITED — its " + suit + " charge is NOT spent");
      r.eq(b.top(0).value, 10, id + ": the showing card is unchanged (drawn not pushed)");
      r.eq(e.getDeck().remaining(), before, id + ": the drawn guard card returned to the deck");

      // A card that matches NEITHER guard direction dies: the drawn card's suit
      // is not the guarded suit (so direction (b) off the top's own guard can't
      // fire) and it carries no guard of its own (direction (a) off).
      const otherSuit = suit === "♠" ? "♥" : "♠";
      b.top(0).suit = otherSuit;
      forceNext(e, 3, otherSuit);   // a plain non-guarded-suit card, no guards
      e.guess(0, "higher");
      r.ok(!b.isActive(0), id + ": a non-matching card onto a non-" + suit + " top does nothing (pile dies)");
    });
  }
  {
    // DIRECTION (b): a matching-suit card drawn ONTO a guard-carrying TOP now
    // SAVES the pile (the guard sits on the pile top).
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 9);
    e.start(); e.startRun();
    const b = e.getBoard();
    b.top(0).value = 10; b.top(0).suit = "♣"; b.top(0).suitGuards = { "♠": true };  // guard rides the TOP
    forceNext(e, 3, "♠");               // plain ♠ drawn onto it (no guards)
    const before = e.getDeck().remaining();   // AFTER the inject (forceNext adds a card)
    e.guess(0, "higher");
    r.ok(b.isActive(0), "a ♠ drawn onto a ♠-guard TOP saves the pile (bidirectional)");
    r.ok(b.top(0).suitGuards["♠"], "the top's ♠ guard is NOT spent (unlimited)");
    r.eq(b.top(0).value, 10, "the guard top stays in place (drawn not pushed)");
    r.eq(e.getDeck().remaining(), before, "the drawn ♠ card returned to the deck");
    // UNLIMITED: it saves AGAIN on a second matching draw.
    forceNext(e, 3, "♠");
    e.guess(0, "higher");
    r.ok(b.isActive(0) && b.top(0).suitGuards["♠"], "the same guard saves a SECOND matching draw (never spent)");
  }
  {
    // A guard ignores OTHER suits: a ♥-guard TOP is not saved by a ♠ landing on it.
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 9);
    e.start(); e.startRun();
    const b = e.getBoard();
    b.top(1).value = 10; b.top(1).suit = "♣"; b.top(1).suitGuards = { "♥": true };   // ♥ guard on top
    forceNext(e, 3, "♠");               // a ♠ lands on it — wrong suit for the guard
    e.guess(1, "higher");
    r.ok(!b.isActive(1), "a ♥ guard ignores a ♠ landing on it (pile dies)");
  }
  {
    // Two guards on one drawn card → each fires independently on the top's suit,
    // and neither spends.
    const specs = DeckManager.buildStandardDeck();
    specs.forEach(c => { c.stickers.push({ type: "suitImmunity" }); c.stickers.push({ type: "heartGuard" }); });
    const e = GameEngine.create(specs, 9);
    e.start(); e.startRun();
    const b = e.getBoard();
    b.top(0).value = 10; b.top(0).suit = "♠";
    const ds = forceNext(e, 3, "♣", { suitGuards: { "♠": true, "♥": true } });   // guard card lands onto a ♠ top
    e.guess(0, "higher");
    r.ok(b.isActive(0) && ds.suitGuards["♠"], "the ♠ charge saved (top was ♠) and is NOT spent");
    r.ok(ds.suitGuards["♥"], "the ♥ charge on that card is untouched (independent)");
  }
  {
    // Refreshes next run (re-projected on each deal).
    const specs = specsWith("suitImmunity");
    const e1 = GameEngine.create(specs, 9);
    e1.start(); e1.startRun();
    const b1 = e1.getBoard();
    b1.top(0).value = 10; b1.top(0).suit = "♠";
    const d = forceNext(e1, 3, "♣", { suitGuards: { "♠": true } });
    e1.guess(0, "higher");
    r.ok(b1.isActive(0) && d.suitGuards["♠"], "the drawn guard saved run 1 and stays charged (unlimited)");
    const e2 = GameEngine.create(specs, 9);
    e2.start();
    r.ok(e2.getBoard().top(0).suitGuards["♠"], "Suit Guard re-projects fresh for run 2");
  }

  // --- Lucky Coin: +1 on a surviving landing ----------------------------
  {
    const e = GameEngine.create(specsWith("gainCoin"), 9);
    e.start(); e.startRun();
    r.eq(e.getRun().bonusCoins, 0, "bonus tally starts at 0");
    landHigher(e, 0);
    r.eq(e.getRun().bonusCoins, 1, "Lucky Coin pays +1 when the card lands and survives");
  }

  // --- Quick Bury sticker: FREE + automatic — buries 1 per instance on
  //     landing, no prompt, no charge (it carries no coinCost). --------------
  {
    const e = GameEngine.create(specsWith("quickBury"), 10, { cols: [3, 4, 3] });
    e.start(); e.startRun([null, null, null]);
    const len0 = e.getBoard().piles[0].cards.length;     // 1 (deal)
    const deck0 = e.getDeck().remaining();
    landHigher(e, 0);
    r.eq(e.getBoard().piles[0].cards.length, len0 + 2, "Quick Bury: pile gains the drawn card + 1 buried");
    r.eq(e.getDeck().remaining(), deck0 - 2, "deck loses the drawn card and the buried card");
    r.eq(e.getRun().bonusCoins, 0, "Quick Bury charges nothing");
    r.ok(!e.pendingTribute || !e.pendingTribute(), "no offer is queued — the bury is automatic");
  }
  // Two landings bury one more each time; the sticker never peels.
  {
    const e = GameEngine.create(specsWith("quickBury"), 10, { cols: [3, 4, 3] });
    e.start(); e.startRun([null, null, null]);
    const len0 = e.getBoard().piles[0].cards.length;
    landHigher(e, 0);
    landHigher(e, 0);
    r.eq(e.getBoard().piles[0].cards.length, len0 + 4, "two Quick Bury landings bury 1 each (+ 2 drawn cards)");
    r.eq(e.getRun().bonusCoins, 0, "two Quick Bury landings still charge nothing");
  }

  // (Double Tribute / Double Bury pillar removed — Tie Bury now buries 2.)

  // --- All Hearts Pillar: END-OF-RUN +5 when every SURVIVING pile in its
  //     column shows ♥ (no longer a live per-resolution payout). -------------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 3, { cols: [1, 1, 1] });
    e.start(); e.startRun(["allHeartsCoin", null, null]);   // Pillar on column 0
    const b = e.getBoard();
    b.top(0).suit = "♥";                  // col 0's only surviving pile shows ♥
    b.top(1).suit = "♠";                  // another column, ignored (column-scoped)
    r.eq(e.getRun().bonusCoins, 0, "no LIVE payout — All Hearts is end-of-run now");
    r.eq(e.pillarPayout().bonus, 4, "All Hearts scores +4 at run end: its column's survivors are all ♥");
    b.top(0).suit = "♠";                  // col 0 no longer all-♥
    r.eq(e.pillarPayout().bonus, 0, "no score when a surviving pile in the column isn't a ♥");
  }
  {
    // Every SURVIVING pile in the column must match: an in-column non-♥ top blocks it.
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 6, { cols: [2, 2, 2] });
    e.start(); e.startRun(["allHeartsCoin", null, null]);   // column 0 = piles 0,1
    const b = e.getBoard();
    b.top(0).suit = "♥"; b.top(1).suit = "♠";   // both in column 0; pile 1 not ♥
    r.eq(e.pillarPayout().bonus, 0, "in-column non-♥ surviving top blocks the bonus");
    b.top(1).suit = "♥";                        // now all survivors in col 0 are ♥
    r.eq(e.pillarPayout().bonus, 4, "all surviving piles in the column ♥ → +4");
  }
  // --- Bidirectional Suit Guard: the DRAWN guard card saves when it lands ONTO
  //     a top of the guarded suit — and the charge is never spent. -----------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 3);
    e.start(); e.startRun();
    const b = e.getBoard();
    const top = b.top(0);
    top.suit = "♠"; top.value = 14; top.suitGuards = {};   // ♠ on top, NO guard of its own
    const d = forceNext(e, 3, "♥", { suitGuards: { "♠": true } });   // drawn carries a ♠ guard
    e.guess(0, "higher");                 // wrong (3 ≤ Ace); the guard card landed onto a ♠
    r.ok(b.isActive(0), "drawn ♠-guard card saves the pile (it landed onto a ♠)");
    r.ok(d.suitGuards["♠"], "the DRAWN card's ♠ charge is NOT spent (unlimited)");
    r.eq(b.top(0).suit, "♠", "the ♠ top stays in place (drawn card not pushed)");
  }

  // --- Suit Bounty pays LIVE during play (not at run end) ---------------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    let payload = null;
    e.onEvent((t, p) => { if (t === "won") payload = p; });
    e.start(); e.startRun(["heartBounty", null, null]);
    e.getBoard().top(0).value = 5;
    forceNext(e, 9, "♥");   // a ♥ LANDS on the column
    e.guess(0, "higher");
    r.eq(e.getRun().bonusCoins, 1, "Suit Bounty ticks the live tally as a ♥ lands");
    e.debug.winNow();
    r.eq(payload.pillarPayout.bonus, 0, "Suit Bounty is NOT re-paid at run end (no double-count)");
  }

  // --- Deck-end death is a LOSS, not a deal clear ----------------------
  // If the final deck card kills the last alive pile, the kill resolves before
  // the end-of-deck check, so it must read as a loss (not a clear).
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    let result = null;
    e.onEvent((t) => { if (t === "won" || t === "lost") result = t; });
    e.start(); e.startRun();
    const b = e.getBoard();
    for (let i = 1; i < b.size; i++) b.kill(i);             // reduce to a single alive pile (0)
    r.eq(b.aliveCount(), 1, "exactly one pile alive going into the final card");
    forceNext(e, b.top(0).value);                   // a tie → wrong on a Higher guess
    e.debug.trimDeck(1);                                    // that tie is the deck's LAST card
    e.guess(0, "higher");
    r.ok(e.getDeck().isEmpty(), "the final deck card was drawn");
    r.ok(!b.anyAlive(), "the last alive pile died on that final card");
    r.eq(result, "lost", "deck-end death emits 'lost' (a loss), not 'won'");
    r.eq(e.getRun().result, "loss", "run result is recorded as a loss");
  }

  // --- A deck-end with a SURVIVOR is still a clear ----------------------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    let result = null;
    e.onEvent((t) => { if (t === "won" || t === "lost") result = t; });
    e.start(); e.startRun();
    const b = e.getBoard();
    for (let i = 1; i < b.size; i++) b.kill(i);             // one survivor (pile 0)
    b.top(0).value = 5;
    forceNext(e, 9);                                 // a correct Higher → survives
    e.debug.trimDeck(1);
    e.guess(0, "higher");
    r.ok(e.getDeck().isEmpty() && b.anyAlive(), "deck empty with a survivor");
    r.eq(result, "won", "surviving to the last card is still a clear");
  }

  // --- Tracker reconciles: live tally + end-of-run bonuses == summary ----
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    let payload = null;
    e.onEvent((t, p) => { if (t === "won") payload = p; });
    e.start();
    e.startRun(["heartBounty", null, "columnGuardian"]);   // col 0 bounty, col 2 guardian
    e.getBoard().top(0).value = 5;
    forceNext(e, 9, "♥");    // one ♥ lands → +1 live
    e.guess(0, "higher");
    r.eq(e.getRun().bonusCoins, 1, "live tally during play = 1 (the Suit Bounty)");
    e.debug.winNow();                                      // all piles alive → Guardian +5

    // Rebuild the run-complete summary exactly as onRunEnd does (ECON1: the
    // flat base is 0 here — this fixture drives no map node).
    const board = payload.board, pp = payload.pillarPayout;
    const eventBonus = payload.run.bonusCoins;             // live part (Suit Bounty = 1)
    const bd = Economy.breakdown({
      won: true, aliveCount: board.aliveCount(), minAliveCards: board.minAliveCards(),
      extraCoinUnits: board.extraCoinUnits(), pillarBonus: pp.bonus, pillarLines: pp.lines,
      eventBonus, eventLines: [],
    });
    r.eq(pp.bonus, 4, "Column Guardian (col 3 all-alive) pays +4 at run end");
    // The HUD's folded final value is exactly (total − flat) = the summary's
    // total bonus, and equals live + Guardian + Extra Coin.
    const finalTracker = bd.total - bd.flat;
    r.eq(finalTracker, eventBonus + pp.bonus + bd.extraCoinBonus, "final tracker = live + Guardian + Extra Coin");
    r.eq(finalTracker, 5, "final bonus reconciles to the summary: 1 live + 4 Guardian = 5");
  }

  // --- Economy folds the live bonus into the total ----------------------
  {
    const FLAT = Economy.dealFlat(1, 1, false);   // stage-1 easy base, from the items.js knobs
    const withEvent = Economy.breakdown({
      won: true, flat: FLAT, aliveCount: 3, minAliveCards: 2,
      eventBonus: 4, eventLines: [{ label: "Middle Reward", amount: 4 }],
    });
    r.eq(withEvent.eventBonus, 4, "eventBonus carried through");
    r.eq(withEvent.total, FLAT + 4, "total folds in the live bonus (flat + 4)");
    r.eq(withEvent.eventLines.length, 1, "itemized event lines preserved for the UI");

    const neg = Economy.breakdown({ won: true, aliveCount: 1, minAliveCards: 1, eventBonus: -5 });
    r.eq(neg.total, 0, "a Tribute cost can't push the total below 0");

    const lost = Economy.breakdown({ won: false, aliveCount: 3, minAliveCards: 2, eventBonus: 4 });
    r.eq(lost.eventBonus, 0, "a loss zeroes the live bonus");
    r.eq(lost.total, 0, "a loss pays nothing");
  }

  return r.summary();
}
