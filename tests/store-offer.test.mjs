// Store offering: CLASS-FIRST roll — items.js store.slots slots per visit,
// every slot picks its item CLASS by items.js store.classWeights, then an
// item within that class by rarity (TIER_WEIGHTS), with a per-CLASS cap of
// store.typeCap slots (card packs and sticker packs count as separate types;
// "card" is a generated individual playing card). Buy empties only that
// slot; reroll-all at store.reroll.baseCost, climbing store.reroll.step per
// reroll (reset per visit); persisted in campaign state (no free reroll via
// re-render); wiped on loss. Every number reads LIVE from ItemData — nothing
// is pinned here. DOM-free.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { CampaignState, StickerTypes, PillarTypes, BaseTypes, PackTypes, SamePowerTypes, ItemData, Stats } = loadGame();
  const r = makeRunner("store-offer.test.mjs");
  // The shelf-shape knobs — read live from items.js so a data retune stays green.
  const SLOTS = ItemData.store.slots;
  const TYPE_CAP = ItemData.store.typeCap;
  const REROLL0 = ItemData.store.reroll.baseCost;
  const REROLL_STEP = ItemData.store.reroll.step;
  const stickerIds = new Set(StickerTypes.ids);
  const pillarIds = new Set(PillarTypes.ids);
  const baseIds = new Set(BaseTypes.ids);
  const packIds = new Set(PackTypes.ids);
  const samePowerIds = new Set(SamePowerTypes.ids);
  const idOk = (kind, id, s) => kind === "sticker" ? stickerIds.has(id)
    : kind === "pillar" ? pillarIds.has(id)
    : kind === "base" ? baseIds.has(id) : kind === "pack" ? packIds.has(id)
    : kind === "samepower" ? samePowerIds.has(id)
    : kind === "card" ? !!(s && s.card && !s.card.blank) : false;
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

  // --- Shape of a fresh offer: exactly store.slots unified slots, filled ---
  {
    const c = CampaignState.create();
    r.eq(c.getStoreOffer(), null, "no offer until the store opens");
    const offer = c.openStore();
    r.eq(offer.slots.length, SLOTS, "offer has exactly store.slots slots (" + SLOTS + ")");
    r.ok(offer.slots.every(s => s != null), "all slots are FILLED on a fresh roll");
    // Default: the last slot is the permanent Removal; the rest roll from the pool.
    r.eq(offer.slots[SLOTS - 1].kind, "removal", "the last slot is the permanent Removal (default ON)");
    const rolled0 = offer.slots.slice(0, SLOTS - 1);
    r.ok(rolled0.every(s => ["sticker", "base", "pillar", "pack", "card", "samepower"].includes(s.kind)),
      "the rolled slots are a sticker / base / pillar / pack / card / same-power");
    r.ok(rolled0.every(s => idOk(s.kind, s.id, s)), "every rolled slot's id is real for its kind");
    r.eq(offer.rerollCost, REROLL0, "reroll cost starts at store.reroll.baseCost (" + REROLL0 + ")");
    r.eq(offer.stickers, undefined, "no segmented sticker section (one unified pool)");
    r.eq(offer.mixed, undefined, "no segmented mixed section (one unified pool)");
  }

  // --- slots always filled + per-TYPE cap ≤ store.typeCap across MANY rolls ---
  {
    const c = CampaignState.create();
    let minFilled = SLOTS, maxOfOneType = 0;
    for (let i = 0; i < 2000; i++) {
      const offer = c.openStore();
      const filled = offer.slots.filter(Boolean);
      minFilled = Math.min(minFilled, filled.length);
      const perType = {};
      filled.filter(s => s.kind !== "removal").forEach(s => { const k = typeKey(s); perType[k] = (perType[k] || 0) + 1; });
      maxOfOneType = Math.max(maxOfOneType, ...Object.values(perType));
    }
    r.eq(minFilled, SLOTS, "every one of 2000 rolls fills all " + SLOTS + " slots");
    r.ok(maxOfOneType <= TYPE_CAP, "no type ever exceeds store.typeCap of the rolled slots (saw max " + maxOfOneType + ")");
    r.eq(maxOfOneType, TYPE_CAP, "the cap is reachable — some roll uses all " + TYPE_CAP + " of one type");
  }

  // --- Every kind surfaces; commons dominate rares (rarity weighting) ---
  {
    const c = CampaignState.create();
    const kindCount = { sticker: 0, pillar: 0, base: 0, pack: 0, card: 0, samepower: 0 };
    const tierCount = { common: 0, uncommon: 0, rare: 0 };
    const reg = { sticker: StickerTypes, pillar: PillarTypes, base: BaseTypes, pack: PackTypes, samepower: SamePowerTypes };
    for (let i = 0; i < 3000; i++) c.openStore().slots.forEach(s => {
      if (!s || s.kind === "removal") return;
      kindCount[s.kind]++;
      if (s.kind === "card") return;   // a generated card carries no rarity tier
      const t = reg[s.kind].get(s.id);
      if (t && tierCount[t.tier] != null) tierCount[t.tier]++;
    });
    r.ok(Object.values(kindCount).every(n => n > 0),
      "ALL kinds surface in the unified pool (" + JSON.stringify(kindCount) + ")");
    // Rarity weighting is per-ITEM (tierWeights common > uncommon > rare), so the
    // right invariant is the per-item OFFER RATE — offeredCount ÷ (#items of that
    // tier). This is robust to how many items each tier happens to hold (a pool
    // that skews uncommon must not flip the weighting conclusion).
    const poolCount = { common: 0, uncommon: 0, rare: 0 };
    for (const k of ["sticker", "pillar", "base", "pack", "samepower"])
      reg[k].all().forEach(t => { if (poolCount[t.tier] != null) poolCount[t.tier]++; });
    const rate = (t) => poolCount[t] ? tierCount[t] / poolCount[t] : 0;
    r.ok(rate("common") > rate("uncommon") && rate("uncommon") > rate("rare"),
      "rarity weighting holds per item: common offered more per item than uncommon than rare"
      + " (counts " + JSON.stringify(tierCount) + " / pool " + JSON.stringify(poolCount) + ")");
  }

  // --- Pack pricing + rarity: card packs 10, sticker packs 5, both common
  {
    const t = PackTypes.get("cardPack");
    r.ok(t.price > 0, "Card Packs have a positive price (items.js knob; currently " + t.price + ")");
    r.ok(["common", "uncommon", "rare"].includes(t.tier), "Card Packs carry a valid rarity (currently " + t.tier + ")");
    const sp = PackTypes.get("stickerPack");
    r.ok(sp.price > 0, "Sticker Packs have a positive price (currently " + sp.price + ")");
    r.ok(["common", "uncommon", "rare"].includes(sp.tier), "Sticker Packs carry a valid rarity (currently " + sp.tier + ")");
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

  // --- Reroll: replaces ALL rolled slots; baseCost → +step → +2·step; resets on store open ---
  {
    const c = CampaignState.create();
    c.addCoins(100);
    const s = findSlot(c, "sticker");
    c.buyOfferedSticker(s.slot);                  // empty a slot...
    r.eq(c.getStoreOffer().slots[s.slot], null, "slot emptied before reroll");
    r.eq(c.storeRerollCost(), REROLL0, "first reroll costs reroll.baseCost");
    const before = c.getCoins();
    r.ok(c.rerollStore(), "reroll #1");
    r.ok(c.getStoreOffer().slots.every(x => x && (x.kind === "removal" || idOk(x.kind, x.id, x))), "reroll refills ALL rolled slots (Removal slot stays)");
    r.eq(c.getCoins(), before - REROLL0, "reroll #1 charged reroll.baseCost");
    r.eq(c.storeRerollCost(), REROLL0 + REROLL_STEP, "cost climbs by reroll.step");
    r.ok(c.rerollStore(), "reroll #2");
    r.eq(c.storeRerollCost(), REROLL0 + 2 * REROLL_STEP, "cost climbs by reroll.step again");
    r.eq(c.getCoins(), before - REROLL0 - (REROLL0 + REROLL_STEP), "reroll #2 charged the climbed cost");

    c.openStore();   // a new run's store visit
    r.eq(c.storeRerollCost(), REROLL0, "reroll cost resets to baseCost when the store re-opens");

    const poor = CampaignState.create();
    poor.addCoins(REROLL0 - 1);   // one short of the base reroll cost
    poor.openStore();
    r.ok(!poor.canReroll(), "canReroll false when too poor");
    r.ok(!poor.rerollStore(), "reroll blocked when unaffordable");
    r.eq(poor.getCoins(), REROLL0 - 1, "blocked reroll spends nothing");
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
    // Suit-STAGE gating stays removed: off-stage suits roll at Stage 1,
    // proven via UNGATED suit items (the guards are unlock-gated now).
    r.ok(s1.has("changeSuitClub") && s1.has("changeSuitSpade"),
      "Stage 1 offers ♣/♠ suit items (suit-stage gating stays removed)");
    // UNLOCK2: at zero lifetime stats no GATED sticker ever rolls —
    // registry-driven over whatever items.js currently gates.
    const gatedStickers = ItemData.stickers.filter(d => d.unlock).map(d => d.id);
    r.ok(gatedStickers.every(id => !s1.has(id)),
      "zero-stat store never offers a gated sticker (" + gatedStickers.length + " gated)");
    // …and satisfying a gate opens the roll: seed the guards' stats and the
    // (previously absent) guards can appear.
    ["dealsSurvived", "cardsBuried", "pilesLost", "stickersApplied",
     "correctSames", "samesCalled"].forEach(s => Stats.bump(s, 999));
    Stats.bump("coinsEarnedLifetime", 9999);
    const s2 = sample(CampaignState.create(), 2000);
    // The four Guards now gate on the NATIVE-only suit counters, which have no
    // reader here — so they can never roll in this build. Exemplars have to be
    // stickers whose gate this build can actually satisfy.
    r.ok(s2.has("collector") || s2.has("massive") || s2.has("quickBury") || s2.has("twoTribute"),
      "…and once the stats are met, gated stickers roll again");
    Stats.reset();
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
    // Suit-STAGE gating stays removed; Club Dig is unlock-gated now, so the
    // any-stage rule is proven by seeding its stat and re-sampling.
    r.ok(b1.has("tax"), "Stage 1 offers Heart Tax (♥ in play)");
    const gatedBases = ItemData.bases.filter(d => d.unlock).map(d => d.id);
    r.ok(gatedBases.every(id => !b1.has(id)),
      "zero-stat store never offers a gated base (" + gatedBases.length + " gated)");
    // Club Dig now gates on the native-only clubsPlayed counter, which has no
    // reader here — Reactor carries the any-stage rule instead.
    Stats.bump("cardsBuried", 999);
    Stats.bump("basesPlaced", 999);
    const b2 = sampleBases(CampaignState.create(), 3000);
    r.ok(b2.has("refreshBases"), "Stage 1 CAN offer Reactor once its gate is met (any-stage rule holds)");
    Stats.reset();
  }

  // --- Removal store slot (default ON): permanent last slot, fixed price, repeatable
  {
    const c = CampaignState.create();
    const removalPrice = c.removalPrice();   // items.js store knob — read live
    r.ok(c.removalSlotOn(), "the Removal slot defaults ON");
    r.ok(removalPrice > 0, "a Removal has a price (items.js store knob; currently " + removalPrice + ")");
    const offer = c.openStore();
    r.eq(offer.slots.filter(s => s && s.kind === "removal").length, 1, "exactly one Removal slot");
    r.eq(offer.slots[SLOTS - 1].kind, "removal", "the Removal is the last slot");
    r.eq(c.priceOfMixed(SLOTS - 1), removalPrice, "priceOfMixed reports the live Removal price for the Removal slot");
    r.ok(!c.buyMixedSlot(SLOTS - 1, Math.random).ok, "buyMixedSlot rejects the Removal slot (bought via buyRemoval)");
    // buyRemoval charges + removes a chosen card; the slot is NOT consumed.
    c.addCoins(100);
    const before = c.deckSize();
    const coins0 = c.getCoins();
    const victim = c.getRunDeck()[0].id;
    r.ok(c.buyRemoval(victim), "buyRemoval succeeds when affordable");
    r.eq(c.getCoins(), coins0 - removalPrice, "charged the live Removal price");
    r.eq(c.deckSize(), before - 1, "the deck shrank by one");
    r.ok(!c.getRunDeck().some(x => x.id === victim), "the chosen card is gone from the deck");
    r.eq(c.getStoreOffer().slots[SLOTS - 1].kind, "removal", "the Removal slot is NOT depleted — repeatable");
    // repeatable: buy again.
    const v2 = c.getRunDeck()[0].id;
    r.ok(c.buyRemoval(v2), "a SECOND Removal purchase works (repeatable)");
    r.eq(c.deckSize(), before - 2, "the deck shrank again");
    // affordability guard.
    const poor = CampaignState.create(); poor.openStore();
    r.ok(!poor.buyRemoval(poor.getRunDeck()[0].id), "can't buy a Removal with no coins");
    r.eq(poor.deckSize(), poor.getRunDeck().length, "a blocked Removal removes nothing");
    // toggle OFF → all slots rolled, no Removal.
    const off = CampaignState.create();
    off.setRemovalSlot(false);
    r.ok(!off.removalSlotOn(), "setRemovalSlot(false) turns it off");
    const o2 = off.openStore();
    r.eq(o2.slots.length, SLOTS, "OFF: still exactly store.slots slots");
    r.ok(o2.slots.every(s => s && s.kind !== "removal"), "OFF: no Removal slot — all slots roll from the pool");
    r.ok(o2.slots.every(s => idOk(s.kind, s.id, s)), "OFF: every slot is a real rolled item");
    // reroll keeps it off.
    off.addCoins(20);
    off.rerollStore();
    r.ok(off.getStoreOffer().slots.every(s => s && s.kind !== "removal"), "OFF: reroll stays Removal-free");
  }

  return r.summary();
}
