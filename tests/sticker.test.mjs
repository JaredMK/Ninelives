// Phase 2/3: sticker data model, application rules, store/inventory, and the
// toCard projection that lets the DOM-free engine read sticker behavior.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { DeckManager, CampaignState, StickerTypes, STICKER_SLOTS_PER_CARD } = loadGame();
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

  // Slot cap: a card can hold at most STICKER_SLOTS_PER_CARD stickers.
  const fiveId = byRank(5);
  for (let i = 0; i < STICKER_SLOTS_PER_CARD; i++) c.applySticker(fiveId, "extraHeart");
  r.ok(!c.applySticker(fiveId, "extraHeart"),
    "slot cap blocks more than " + STICKER_SLOTS_PER_CARD + " stickers");
  r.eq(c.getCards().find(x => x.id === fiveId).stickers.length, STICKER_SLOTS_PER_CARD,
    "card holds exactly the slot-cap number of stickers");

  // Tie-Safe is idempotent (no duplicate wasted slot).
  const sixId = byRank(6);
  r.ok(c.applySticker(sixId, "tieSafe"), "first Tie-Safe applies");
  r.ok(!c.applySticker(sixId, "tieSafe"), "duplicate Tie-Safe is blocked");

  // --- store / inventory / coins ----------------------------------------
  const c2 = CampaignState.create();
  r.eq(c2.getCoins(), 0, "new campaign starts with 0 coins");
  r.ok(!c2.buySticker("rankUp"), "cannot buy with no coins");
  c2.addCoins(100);
  const price = StickerTypes.get("rankUp").price;
  r.ok(c2.buySticker("rankUp"), "buy succeeds when affordable");
  r.eq(c2.inventoryCount("rankUp"), 1, "bought sticker enters inventory");
  r.eq(c2.getCoins(), 100 - price, "coins decremented by the price");

  // Inventory + coins persist across a run advance.
  c2.advance();
  r.eq(c2.inventoryCount("rankUp"), 1, "inventory persists across advance()");
  r.eq(c2.getCoins(), 100 - price, "coins persist across advance()");

  // useStickerFromInventory decrements; reset() clears everything.
  r.ok(c2.useStickerFromInventory("rankUp"), "using a sticker decrements inventory");
  r.eq(c2.inventoryCount("rankUp"), 0, "inventory now empty");
  c2.addCoins(50);
  c2.reset();
  r.eq(c2.getCoins(), 0, "reset clears coins");
  r.eq(c2.inventoryCount("rankUp"), 0, "reset clears inventory");

  return r.summary();
}
