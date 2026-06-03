// Balatro-style limited store offering: a random roll of 4 stickers + 2
// Pillars per visit, buy-empties-only-that-slot, reroll-all at 3→4→5 (reset
// per visit), persisted in campaign state (no free reroll via re-render),
// wiped on loss. Engine/economy logic only — no DOM.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { CampaignState, StickerTypes, PillarTypes, PackTypes } = loadGame();
  const r = makeRunner("store-offer.test.mjs");
  const stickerIds = new Set(StickerTypes.ids);
  const pillarIds = new Set(PillarTypes.ids);
  const packIds = new Set(PackTypes.ids);

  // --- Shape of a fresh offer -------------------------------------------
  {
    const c = CampaignState.create();
    r.eq(c.getStoreOffer(), null, "no offer until the store opens");
    const offer = c.openStore();
    r.eq(offer.stickers.length, 4, "offer has 4 sticker slots");
    r.eq(offer.pillars.length, 2, "offer has 2 Pillar slots");
    r.eq(offer.packs.length, 2, "offer has 2 pack slots");
    r.ok(offer.stickers.every(id => stickerIds.has(id)), "all offered stickers are real registry ids");
    r.ok(offer.pillars.every(id => pillarIds.has(id)), "all offered Pillars are real registry ids");
    // Both pack slots are ALWAYS filled with a real pack id (never null/empty).
    r.ok(offer.packs.every(id => packIds.has(id)), "both pack slots are filled with real pack ids (always 2)");
    r.eq(offer.rerollCost, 3, "reroll cost starts at 3");
  }

  // --- Packs re-roll on every store open (not stale across visits) -------
  {
    // Each open rolls 2 packs from the 4-type pool. Across many opens we must
    // see BOTH that every open is full (2 real ids) and that the roll actually
    // varies — proving it regenerates per open rather than caching one result.
    const c = CampaignState.create();
    const seen = new Set();
    let allFull = true;
    for (let i = 0; i < 40; i++) {
      const o = c.openStore();
      if (o.packs.length !== 2 || !o.packs.every(id => packIds.has(id))) allFull = false;
      seen.add(o.packs.join(","));
    }
    r.ok(allFull, "every store open offers exactly 2 filled pack slots");
    r.ok(seen.size > 1, "pack slots re-roll across opens (the offering isn't stale)");
  }

  // --- Persistence: reading the offer never re-rolls (no free reroll) ----
  {
    const c = CampaignState.create();
    c.openStore();
    const a = c.getStoreOffer();
    const b = c.getStoreOffer();
    r.ok(a === b && a.stickers === b.stickers, "re-reading returns the SAME offer object (a render can't re-roll)");
    const snap = a.stickers.slice();
    // A second, unrelated read still matches the snapshot.
    r.ok(c.getStoreOffer().stickers.every((id, i) => id === snap[i]), "offered items are stable across reads");
  }

  // --- Buying a sticker empties ONLY that slot; rest stay ---------------
  {
    const c = CampaignState.create();
    c.addCoins(100);
    c.openStore();
    const offer = c.getStoreOffer();
    const id0 = offer.stickers[0];
    const slot1 = offer.stickers[1];
    const price = c.priceOf(id0);
    const coins0 = c.getCoins();
    r.ok(c.buyOfferedSticker(0), "buy the sticker in slot 0");
    r.eq(c.getStoreOffer().stickers[0], null, "slot 0 is now empty");
    r.eq(c.getStoreOffer().stickers[1], slot1, "slot 1 is untouched (rest stay)");
    r.eq(c.inventoryCount(id0), 1, "bought sticker went to inventory");
    r.eq(c.getCoins(), coins0 - price, "charged the fixed price");
    r.ok(!c.buyOfferedSticker(0), "can't buy an already-empty slot");

    const broke = CampaignState.create();
    broke.openStore();
    r.ok(!broke.buyOfferedSticker(0), "can't buy a sticker with no coins");
  }

  // --- Buying a Pillar empties its slot + places on the chosen column ----
  {
    const c = CampaignState.create();
    c.addCoins(100);
    c.openStore();
    const pid = c.getStoreOffer().pillars[0];
    const price = c.priceOfPillar(pid);
    const coins0 = c.getCoins();
    r.ok(c.buyOfferedPillar(0, 1), "buy offered Pillar slot 0 onto column 1");
    r.eq(c.columnPillar(1), pid, "Pillar placed on column 1");
    r.eq(c.getStoreOffer().pillars[0], null, "offered Pillar slot 0 now empty");
    r.eq(c.getCoins(), coins0 - price, "charged the fixed Pillar price");
    r.ok(!c.buyOfferedPillar(0, 2), "can't buy an already-empty Pillar slot");
    r.ok(!c.buyOfferedPillar(1, 9), "can't place on an out-of-range column");
  }

  // --- Reroll: replaces ALL slots; 3 → 4 → 5; resets on store open -------
  {
    const c = CampaignState.create();
    c.addCoins(100);
    c.openStore();
    c.buyOfferedSticker(0);                       // empty a slot...
    r.eq(c.getStoreOffer().stickers[0], null, "slot emptied before reroll");
    r.eq(c.storeRerollCost(), 3, "first reroll costs 3");
    const before = c.getCoins();
    r.ok(c.rerollStore(), "reroll #1");
    r.ok(c.getStoreOffer().stickers.every(id => id !== null), "reroll refills ALL slots (none empty)");
    r.ok(c.getStoreOffer().packs.every(id => packIds.has(id)), "reroll refills the pack slots too (all sections together)");
    r.eq(c.getCoins(), before - 3, "reroll #1 charged 3");
    r.eq(c.storeRerollCost(), 4, "cost climbs to 4");
    r.ok(c.rerollStore(), "reroll #2");
    r.eq(c.storeRerollCost(), 5, "cost climbs to 5");
    r.eq(c.getCoins(), before - 3 - 4, "reroll #2 charged 4");

    c.openStore();   // a new run's store visit
    r.eq(c.storeRerollCost(), 3, "reroll cost resets to 3 when the store re-opens");

    // Unaffordable reroll is blocked.
    const poor = CampaignState.create();
    poor.addCoins(2);
    poor.openStore();
    r.ok(!poor.canReroll(), "canReroll false when too poor");
    r.ok(!poor.rerollStore(), "reroll blocked when unaffordable");
    r.eq(poor.getCoins(), 2, "blocked reroll spends nothing");
  }

  // --- Wipe on campaign loss (reset clears the offer) -------------------
  {
    const c = CampaignState.create();
    c.addCoins(100);
    c.openStore();
    c.reset();
    r.eq(c.getStoreOffer(), null, "reset() wipes the offer");
    r.eq(c.storeRerollCost(), Infinity, "no reroll cost without an offer");
    r.ok(!c.canReroll(), "can't reroll after a wipe");
  }

  return r.summary();
}
