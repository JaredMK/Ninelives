// Phase 2/3: sticker data model, application rules, store/inventory, and the
// toCard projection that lets the DOM-free engine read sticker behavior.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { DeckManager, CampaignState, StickerTypes } = loadGame();
  const r = makeRunner("sticker.test.mjs");

  // Persistent cards carry an empty stickers array.
  const deck = DeckManager.buildStandardDeck();
  r.ok(deck.every(c => Array.isArray(c.stickers) && c.stickers.length === 0),
    "fresh cards start with no stickers");

  // (toCard's projection of stickers -> heartsRemaining/tieSafe is covered
  // end-to-end by engine-stickers.test.mjs.)

  // --- applySticker validation ------------------------------------------
  const c = CampaignState.create();
  const byRank = (v) => c.getCards().find(x => x.currentRank === v).id;

  // rankUp on a 10 -> 11, records a modification + a sticker.
  const tenId = byRank(10);
  r.ok(c.applySticker(tenId, "rankUp"), "rankUp applies to a 10");
  const ten = c.getCards().find(x => x.id === tenId);
  r.eq(ten.currentRank, 11, "rankUp bumped currentRank 10 -> 11");
  r.eq(ten.stickers.length, 1, "rankUp recorded a sticker");
  r.eq(ten.modifications.length, 1, "rankUp recorded a modification");

  // rankUp blocked on an Ace; rankDown blocked on a 2 (no wasted stickers).
  r.ok(!c.applySticker(byRank(14), "rankUp"), "rankUp blocked on an Ace");
  r.ok(!c.applySticker(byRank(2), "rankDown"), "rankDown blocked on a 2");

  // No slot cap: a card holds any number of stickers (incl. duplicates).
  const fiveId = byRank(5);
  for (let i = 0; i < 6; i++) r.ok(c.applySticker(fiveId, "extraHeart"), "Extra Heart #" + (i + 1) + " applies (no cap)");
  r.eq(c.getCards().find(x => x.id === fiveId).stickers.length, 6, "card holds all 6 stickers (no cap)");

  // Duplicates of Tie-Safe / Extra Coin are allowed now (uniqueness removed).
  const sixId = byRank(6);
  r.ok(c.applySticker(sixId, "tieSafe"), "first Tie-Safe applies");
  r.ok(c.applySticker(sixId, "tieSafe"), "duplicate Tie-Safe now allowed");
  const sevenId = byRank(7);
  r.ok(c.applySticker(sevenId, "extraCoin"), "first Extra Coin applies");
  r.ok(c.applySticker(sevenId, "extraCoin"), "duplicate Extra Coin now allowed");

  // Stacked rank stickers clamp at the Ace boundary (can't exceed it).
  const queenId = byRank(12);                 // Q (12)
  r.ok(c.applySticker(queenId, "rankUp"), "Q -> K");
  r.ok(c.applySticker(queenId, "rankUp"), "K -> A");
  r.ok(!c.applySticker(queenId, "rankUp"), "A blocks further +1 (clamped)");
  r.eq(c.getCards().find(x => x.id === queenId).currentRank, 14, "stacked +1 clamps at Ace (14)");

  // --- store / inventory / coins with ESCALATING prices -----------------
  const c2 = CampaignState.create();
  r.eq(c2.getCoins(), 0, "new campaign starts with 0 coins");
  r.ok(!c2.buySticker("rankUp"), "cannot buy with no coins");
  c2.addCoins(100);

  const base = StickerTypes.get("rankUp").basePrice;   // 2
  r.eq(c2.priceOf("rankUp"), base, "price starts at basePrice");
  r.ok(c2.buySticker("rankUp"), "buy #1 succeeds");
  r.eq(c2.getCoins(), 100 - base, "charged the base price");
  r.eq(c2.priceOf("rankUp"), base + 1, "price climbs +1 after a purchase");
  r.ok(c2.buySticker("rankUp"), "buy #2 succeeds");
  r.eq(c2.getCoins(), 100 - base - (base + 1), "charged the escalated price on buy #2");
  r.eq(c2.inventoryCount("rankUp"), 2, "two rankUp stickers owned");
  // Escalation is per-type: a different type still starts at its own base.
  r.eq(c2.priceOf("tieSafe"), StickerTypes.get("tieSafe").basePrice,
    "a different type is unaffected by rankUp purchases");

  // Inventory, coins, and price escalation persist across a run advance.
  c2.advance();
  r.eq(c2.priceOf("rankUp"), base + 2, "escalated price persists across advance()");

  // reset() clears coins, inventory, AND the per-type purchase counts.
  c2.reset();
  r.eq(c2.getCoins(), 0, "reset clears coins");
  r.eq(c2.inventoryCount("rankUp"), 0, "reset clears inventory");
  r.eq(c2.priceOf("rankUp"), base, "reset restores base prices");

  return r.summary();
}
