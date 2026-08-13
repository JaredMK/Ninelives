// Wild Suit sticker (a card counts as EVERY suit, everywhere suit is checked)
// and the Peel-stickers action (revert a card to its base state; peeled stickers
// are destroyed). Engine + CampaignState behaviour.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, CampaignState, StickerTypes } = loadGame();
  const r = makeRunner("wild-peel.test.mjs");

  // --- registry + projection -------------------------------------------
  {
    const t = StickerTypes.get("wildSuit");
    r.ok(!!t, "Wild Suit is registered");
    r.eq(t && t.behavior, "wildSuit", "Wild Suit uses the wildSuit behavior");
    r.ok(["common", "uncommon", "rare"].includes(t && t.tier), "Wild Suit carries a valid tier (a hand-tunable items.js knob; currently " + (t && t.tier) + ")");
    r.ok(!t.suit, "Wild Suit carries no fixed suit (it's all suits)");
    const specs = DeckManager.buildStandardDeck();
    specs[0].stickers.push({ type: "wildSuit" });
    r.ok(DeckManager.toCard(specs[0]).wildSuit === true, "toCard projects the wildSuit flag");
    r.ok(DeckManager.toCard(specs[1]).wildSuit === false, "a plain card is not wild");
  }

  // --- Wild Suit TOP lets a guard card fire on it ------------------------
  // A guard fires when the GUARD CARD is drawn ONTO a top of its guarded suit;
  // a Wild Suit top counts as every suit, so any guard card landing on it fires.
  // Guards are unlimited now — they never spend.
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 9, { cols: [3, 3, 3] });
    e.start(); e.startRun([null, null, null]);
    const b = e.getBoard();
    b.top(0).value = 10; b.top(0).suit = "♣"; b.top(0).wildSuit = true;   // a WILD top
    const before = e.getDeck().remaining();
    const d = e.debug.setNextCard(3); d.suit = "♠"; d.suitGuards = { "♥": true };  // a ♥ guard card drawn onto it
    e.guess(0, "higher");
    r.ok(b.isActive(0), "a ♥ guard card drawn onto a WILD top fires (wild counts as ♥)");
    r.ok(d.suitGuards["♥"], "the drawn guard card's ♥ charge is NOT spent (unlimited)");
    r.eq(e.getDeck().remaining(), before, "the drawn guard card was returned to the deck (guard save)");
  }
  {
    // Control: the same ♥ guard card onto a plain ♠ top does NOT fire.
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 9, { cols: [3, 3, 3] });
    e.start(); e.startRun([null, null, null]);
    const b = e.getBoard();
    b.top(0).value = 10; b.top(0).suit = "♠";   // plain ♠ top (no wild)
    const d = e.debug.setNextCard(3); d.suit = "♠"; d.suitGuards = { "♥": true };
    e.guess(0, "higher");
    r.ok(!b.isActive(0), "a ♥ guard card onto a plain ♠ top does NOT fire (pile dies)");
  }

  // --- Wild Suit satisfies any Suit Bonus pillar (as the drawn card) -----
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 9, { cols: [3, 3, 3] });
    e.start(); e.startRun(["heartBounty", null, null]);   // Heart Bonus on column 0
    const b = e.getBoard();
    b.top(0).value = 5;
    const d = e.debug.setNextCard(9); d.suit = "♠"; d.wildSuit = true;   // a ♠ WILD lands correctly
    e.guess(0, "higher");
    r.eq(e.getRun().bonusCoins, 1, "a Wild ♠ card earns the ♥ Bonus (counts as ♥)");
  }

  // --- Wild Suit counts as the matching suit for an all-suit pillar ------
  {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 9, { cols: [3, 3, 3] });
    e.start(); e.startRun(["allHeartsCoin", null, null]);   // All Hearts on column 0 (piles 0,1,2)
    const b = e.getBoard();
    b.top(0).suit = "♥"; b.top(1).suit = "♥";
    b.top(2).suit = "♠"; b.top(2).wildSuit = true;   // a wild ♠ top
    r.eq(e.pillarPayout().bonus, 4, "a Wild top counts as ♥ for All Hearts (+4)");
    b.top(2).wildSuit = false;
    r.eq(e.pillarPayout().bonus, 0, "without wild, the ♠ top breaks All Hearts (0)");
  }

  // --- Peel: revert to base state; stickers destroyed -------------------
  {
    const c = CampaignState.create();
    const card = c.getCards().find(x => x.originalRank === 7 && x.suit === "♥");
    const id = card.id;
    c.applySticker(id, "rankUp");          // 7 → 8 (+modification, +sticker)
    c.applySticker(id, "changeSuitHeart"); // already ♥ → records a changeSuit ♥→♥; keep simple
    c.applySticker(id, "changeSuitSpade"); // ♥ → ♠
    c.applySticker(id, "wildSuit");
    const live = c.getCards().find(x => x.id === id);
    r.eq(live.currentRank, 8, "current rank reflects the rank sticker (8)");
    r.eq(live.suit, "♠", "current suit reflects the Change-Suit (♠)");
    r.eq(live.stickers.length, 4, "four stickers attached");

    const base = c.baseStateOf(id);
    r.eq(base.rank, 7, "base rank is the ORIGINAL 7 (read-only)");
    r.eq(base.suit, "♥", "base suit is the ORIGINAL ♥ (pre any Change-Suit)");
    r.ok(c.getCards().find(x => x.id === id).stickers.length === 4, "baseStateOf does not mutate");

    const peeled = c.peelStickers(id);
    r.eq(peeled.rank, 7, "peel returns the base rank");
    r.eq(peeled.suit, "♥", "peel returns the base suit");
    const after = c.getCards().find(x => x.id === id);
    r.eq(after.currentRank, 7, "card reverted to original rank");
    r.eq(after.suit, "♥", "card reverted to original suit");
    r.eq(after.stickers.length, 0, "all stickers removed");
    r.eq(after.modifications.length, 0, "modifications cleared");
    r.eq(after.compoundHits, 0, "compound reset");
    // Destroyed, not returned: peeling never adds to the sticker inventory.
    const inv = c.getInventory();
    r.eq(Object.values(inv).reduce((a, n) => a + n, 0), 0, "peeled stickers are NOT returned to inventory");
  }

  // --- Peel reveals/reverts a hidden Random-Rank base -------------------
  {
    const c = CampaignState.create();
    const card = c.getCards().find(x => x.originalRank === 4);
    const id = card.id;
    c.applySticker(id, "randomFixedValue");   // currentRank now hidden/random
    r.eq(c.baseStateOf(id).rank, 4, "base reveals the true underlying rank (4) behind Random Rank");
    c.peelStickers(id);
    r.eq(c.getCards().find(x => x.id === id).currentRank, 4, "peel reverts a Random-Rank card to its true base (4)");
  }

  return r.summary();
}
