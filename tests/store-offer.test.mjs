// Store offering: ONE unified pool — exactly 5 slots per visit, every slot
// independently rolled from ALL item types together (stickers, pillars, bases,
// card packs, sticker packs, Same-Powers) weighted purely by rarity
// (TIER_WEIGHTS), with a per-TYPE cap of 3 slots (card packs and sticker packs
// count as separate types). Buy empties only that slot; reroll-all at 3→4→5
// (reset per visit); persisted in campaign state (no free reroll via
// re-render); wiped on loss. DOM-free.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { CampaignState, StickerTypes, PillarTypes, BaseTypes, PackTypes, SamePowerTypes } = loadGame();
  const r = makeRunner("store-offer.test.mjs");
  const stickerIds = new Set(StickerTypes.ids);
  const pillarIds = new Set(PillarTypes.ids);
  const baseIds = new Set(BaseTypes.ids);
  const packIds = new Set(PackTypes.ids);
  const samePowerIds = new Set(SamePowerTypes.ids);
  const idOk = (kind, id) => kind === "sticker" ? stickerIds.has(id)
    : kind === "pillar" ? pillarIds.has(id)
    : kind === "base" ? baseIds.has(id) : kind === "pack" ? packIds.has(id)
    : kind === "samepower" ? samePowerIds.has(id) : false;
  // The per-type cap distinguishes card packs from sticker packs.
  const typeKey = (s) => s.kind !== "pack" ? s.kind
    : (PackTypes.get(s.id).kind === "card" ? "cardpack" : "stickerpack");

  // Open the store repeatedly until a slot of `kind` is offered; return
  // { slot, id }. (Draws are random; a few opens always suffice.)
  const findSlot = (c, kind) => {
    for (let i = 0; i < 400; i++) {
      const offer = c.openStore();
      const slot = offer.slots.findIndex(s => s && s.kind === kind);
      if (slot !== -1) return { slot, id: offer.slots[slot].id };
    }
    throw new Error("never offered a " + kind + " slot");
  };

  // --- Shape of a fresh offer: exactly 5 unified slots, always filled ---
  {
    const c = CampaignState.create();
    r.eq(c.getStoreOffer(), null, "no offer until the store opens");
    const offer = c.openStore();
    r.eq(offer.slots.length, 5, "offer has exactly 5 slots");
    r.ok(offer.slots.every(s => s != null), "all 5 slots are FILLED on a fresh roll");
    r.ok(offer.slots.every(s => ["sticker", "base", "pillar", "pack", "samepower"].includes(s.kind)),
      "every slot is a sticker / base / pillar / pack / same-power");
    r.ok(offer.slots.every(s => idOk(s.kind, s.id)), "every slot's id is real for its kind");
    r.eq(offer.rerollCost, 3, "reroll cost starts at 3");
    r.eq(offer.stickers, undefined, "no segmented sticker section (one unified pool)");
    r.eq(offer.mixed, undefined, "no segmented mixed section (one unified pool)");
  }

  // --- 5 slots always filled + per-TYPE cap ≤ 3 across MANY rolls -------
  {
    const c = CampaignState.create();
    let minFilled = 5, maxOfOneType = 0;
    for (let i = 0; i < 2000; i++) {
      const offer = c.openStore();
      const filled = offer.slots.filter(Boolean);
      minFilled = Math.min(minFilled, filled.length);
      const perType = {};
      filled.forEach(s => { const k = typeKey(s); perType[k] = (perType[k] || 0) + 1; });
      maxOfOneType = Math.max(maxOfOneType, ...Object.values(perType));
    }
    r.eq(minFilled, 5, "every one of 2000 rolls fills all 5 slots");
    r.ok(maxOfOneType <= 3, "no type ever exceeds 3 of the 5 slots (saw max " + maxOfOneType + ")");
    r.eq(maxOfOneType, 3, "the cap is reachable — some roll uses all 3 of one type");
  }

  // --- Every kind surfaces; commons dominate rares (rarity weighting) ---
  {
    const c = CampaignState.create();
    const kindCount = { sticker: 0, pillar: 0, base: 0, pack: 0, samepower: 0 };
    const tierCount = { common: 0, uncommon: 0, rare: 0 };
    const reg = { sticker: StickerTypes, pillar: PillarTypes, base: BaseTypes, pack: PackTypes, samepower: SamePowerTypes };
    for (let i = 0; i < 3000; i++) c.openStore().slots.forEach(s => {
      if (!s) return;
      kindCount[s.kind]++;
      const t = reg[s.kind].get(s.id);
      if (t && tierCount[t.tier] != null) tierCount[t.tier]++;
    });
    r.ok(Object.values(kindCount).every(n => n > 0),
      "ALL kinds surface in the unified pool (" + JSON.stringify(kindCount) + ")");
    r.ok(tierCount.common > tierCount.uncommon && tierCount.uncommon > tierCount.rare,
      "rarity weighting holds: common > uncommon > rare (" + JSON.stringify(tierCount) + ")");
  }

  // --- Pack pricing + rarity: card packs 10, sticker packs 5, both common
  {
    const t = PackTypes.get("cardPack");
    r.eq(t.price, 10, "Card Packs cost 10");
    r.eq(t.tier, "common", "Card Packs are COMMON rarity");
    const sp = PackTypes.get("stickerPack");
    r.eq(sp.price, 5, "Sticker Packs keep their price (5)");
    r.eq(sp.tier, "common", "Sticker Packs are COMMON rarity");
  }

  // --- Reading the offer never re-rolls (no free reroll via re-render) --
  {
    const c = CampaignState.create();
    c.openStore();
    const a = c.getStoreOffer();
    const b = c.getStoreOffer();
    r.ok(a === b && a.slots === b.slots,
      "re-reading returns the SAME offer object (a render can't re-roll)");
  }

  // --- Buying a sticker empties ONLY that slot; rest stay --------------
  {
    const c = CampaignState.create();
    c.addCoins(100);
    const { slot, id } = findSlot(c, "sticker");
    const offer = c.getStoreOffer();
    const other = offer.slots.findIndex((s, i) => i !== slot && s);
    const otherBefore = offer.slots[other];
    const price = c.priceOf(id);
    r.eq(c.priceOfMixed(slot), price, "priceOfMixed reports the sticker's price for a sticker slot");
    const coins0 = c.getCoins();
    r.ok(c.buyOfferedSticker(slot), "buy the sticker slot");
    r.eq(c.getStoreOffer().slots[slot], null, "that slot is now empty");
    r.eq(c.getStoreOffer().slots[other], otherBefore, "other slots are untouched (rest stay)");
    r.eq(c.inventoryCount(id), 1, "bought sticker went to inventory");
    r.eq(c.getCoins(), coins0 - price, "charged the fixed price");
    r.ok(!c.buyOfferedSticker(slot), "can't buy an already-empty slot");
    r.ok(!c.buyMixedSlot(slot, Math.random).ok, "buyMixedSlot rejects an empty slot too");

    const broke = CampaignState.create();
    const b = findSlot(broke, "sticker");
    r.ok(!broke.buyOfferedSticker(b.slot), "can't buy a sticker with no coins");
  }

  // --- The two buy paths respect the slot's kind ------------------------
  {
    const c = CampaignState.create();
    c.addCoins(200);
    const p = findSlot(c, "pillar");
    r.ok(!c.buyOfferedSticker(p.slot), "buyOfferedSticker rejects a non-sticker slot");
    const s = findSlot(c, "sticker");
    r.ok(!c.buyMixedSlot(s.slot, Math.random).ok, "buyMixedSlot rejects a sticker slot");
  }

  // --- buyMixedSlot: a Pillar slot banks to INVENTORY (placed later) ---
  {
    const c = CampaignState.create();
    c.addCoins(200);
    const { slot, id } = findSlot(c, "pillar");
    const price = c.priceOfMixed(slot);
    r.eq(price, c.priceOfPillar(id), "priceOfMixed reports the Pillar's price");
    const coins0 = c.getCoins();
    const res = c.buyMixedSlot(slot, Math.random);
    r.ok(res.ok && res.kind === "pillar", "buying a Pillar slot succeeds");
    r.ok(!res.reveal, "a Pillar buy has no pack reveal");
    r.eq(c.pillarInventoryCount(id), 1, "bought Pillar went to inventory");
    r.eq(c.columnPillar(1), null, "buying does NOT place it on a column");
    r.eq(c.getStoreOffer().slots[slot], null, "that slot is now empty");
    r.eq(c.getCoins(), coins0 - price, "charged the fixed Pillar price");
    r.ok(!c.buyMixedSlot(slot, Math.random).ok, "can't buy an already-empty slot");
    r.ok(c.placePillar(id, 1), "place the owned Pillar on column 1");
    r.eq(c.columnPillar(1), id, "Pillar now bound to column 1");
  }

  // --- buyMixedSlot: a Base slot banks to INVENTORY -------------------
  {
    const c = CampaignState.create();
    c.addCoins(200);
    const { slot, id } = findSlot(c, "base");
    const price = c.priceOfMixed(slot);
    const coins0 = c.getCoins();
    const res = c.buyMixedSlot(slot, Math.random);
    r.ok(res.ok && res.kind === "base", "buying a Base slot succeeds");
    r.eq(c.baseInventoryCount(id), 1, "bought Base went to inventory");
    r.eq(c.getStoreOffer().slots[slot], null, "that slot is now empty");
    r.eq(c.getCoins(), coins0 - price, "charged the fixed Base price");
  }

  // --- buyMixedSlot: a Pack slot charges + opens (returns a reveal) ----
  {
    const c = CampaignState.create();
    c.addCoins(200);
    const { slot, id } = findSlot(c, "pack");
    const price = c.priceOfMixed(slot);
    r.eq(price, PackTypes.get(id).price, "priceOfMixed reports the pack's fixed price");
    const coins0 = c.getCoins();
    const res = c.buyMixedSlot(slot, Math.random);
    r.ok(res.ok && res.kind === "pack", "buying a Pack slot succeeds");
    r.ok(res.reveal && res.reveal.packId === id, "the pack reveal carries the pack id");
    r.ok(Array.isArray(res.reveal.items) && res.reveal.items.length > 0, "the pack reveal lists items to pick");
    r.eq(c.getStoreOffer().slots[slot], null, "that slot is now empty");
    r.eq(c.getCoins(), coins0 - price, "charged the fixed Pack price");

    const broke = CampaignState.create();
    const m = findSlot(broke, "pack");
    r.ok(!broke.buyMixedSlot(m.slot, Math.random).ok, "can't buy a Pack with no coins");
  }

  // --- buyMixedSlot: a Same-Power slot banks to its inventory ----------
  {
    const c = CampaignState.create();
    c.addCoins(200);
    const { slot, id } = findSlot(c, "samepower");
    const before = c.samePowerInventoryCount(id);
    const res = c.buyMixedSlot(slot, () => 0.5);
    r.ok(res.ok && res.kind === "samepower", "buying a Same-Power slot succeeds");
    r.eq(c.samePowerInventoryCount(id), before + 1, "the bought Same-Power lands in inventory");
    r.eq(c.getStoreOffer().slots[slot], null, "that slot is now empty");
  }

  // --- Reroll: replaces ALL 5 slots; 3 → 4 → 5; resets on store open ---
  {
    const c = CampaignState.create();
    c.addCoins(100);
    const s = findSlot(c, "sticker");
    c.buyOfferedSticker(s.slot);                  // empty a slot...
    r.eq(c.getStoreOffer().slots[s.slot], null, "slot emptied before reroll");
    r.eq(c.storeRerollCost(), 3, "first reroll costs 3");
    const before = c.getCoins();
    r.ok(c.rerollStore(), "reroll #1");
    r.ok(c.getStoreOffer().slots.every(x => x && idOk(x.kind, x.id)), "reroll refills ALL 5 slots");
    r.eq(c.getCoins(), before - 3, "reroll #1 charged 3");
    r.eq(c.storeRerollCost(), 4, "cost climbs to 4");
    r.ok(c.rerollStore(), "reroll #2");
    r.eq(c.storeRerollCost(), 5, "cost climbs to 5");
    r.eq(c.getCoins(), before - 3 - 4, "reroll #2 charged 4");

    c.openStore();   // a new run's store visit
    r.eq(c.storeRerollCost(), 3, "reroll cost resets to 3 when the store re-opens");

    const poor = CampaignState.create();
    poor.addCoins(2);
    poor.openStore();
    r.ok(!poor.canReroll(), "canReroll false when too poor");
    r.ok(!poor.rerollStore(), "reroll blocked when unaffordable");
    r.eq(poor.getCoins(), 2, "blocked reroll spends nothing");
  }

  // --- Wipe on campaign loss (reset clears the offer) -----------------
  {
    const c = CampaignState.create();
    c.addCoins(100);
    c.openStore();
    c.reset();
    r.eq(c.getStoreOffer(), null, "reset() wipes the offer");
    r.eq(c.storeRerollCost(), Infinity, "no reroll cost without an offer");
    r.ok(!c.canReroll(), "can't reroll after a wipe");
  }

  // --- Stage gating REMOVED: suited STICKERS can roll at ANY stage ------
  {
    const sample = (c, n) => {
      const seen = new Set();
      for (let i = 0; i < n; i++)
        c.openStore().slots.forEach(s => { if (s && s.kind === "sticker") seen.add(s.id); });
      return seen;
    };
    const s1 = sample(CampaignState.create(), 2000);          // Stage 1: ♦ ♥
    r.ok(s1.has("diamondGuard") && s1.has("heartGuard"), "Stage 1 offers the ♦ and ♥ guards");
    r.ok(s1.has("clubGuard"), "Stage 1 offers the ♣ guard too (gating removed)");
    r.ok(s1.has("suitImmunity"), "…and the ♠ guard (all items any time)");
  }

  // --- Suit-lock: suited PILLARS obey the same gate ---------------------
  // The rebalance removed the ♠/♣/♦ Bonus pillars — only the ♥ Heart Bonus
  // remains (a Stage-1 suit), so it's always eligible and the deleted ones never
  // surface in any stage.
  {
    const samplePillars = (c, n) => {
      const seen = new Set();
      for (let i = 0; i < n; i++)
        c.openStore().slots.forEach(s => { if (s && s.kind === "pillar") seen.add(s.id); });
      return seen;
    };
    const p1 = samplePillars(CampaignState.create(), 2500);    // Stage 1: ♦ ♥
    r.ok(p1.has("heartBounty"), "Stage 1 offers the ♥ Heart Bonus pillar");
    r.ok(!p1.has("clubBounty") && !p1.has("spadeBounty") && !p1.has("diamondBounty"),
      "the removed ♠/♣/♦ Bonus pillars never appear");
  }

  // --- Stage gating REMOVED: suited BASES can roll at ANY stage ---------
  {
    const sampleBases = (c, n) => {
      const seen = new Set();
      for (let i = 0; i < n; i++)
        c.openStore().slots.forEach(s => { if (s && s.kind === "base") seen.add(s.id); });
      return seen;
    };
    const b1 = sampleBases(CampaignState.create(), 3000);      // Stage 1: ♦ ♥
    r.ok(b1.has("clubDig"), "Stage 1 CAN offer Club Dig (gating removed)");
    r.ok(b1.has("tax"), "Stage 1 offers Heart Tax (♥ in play)");
  }

  return r.summary();
}
