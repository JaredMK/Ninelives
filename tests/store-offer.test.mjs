// Store offering: a random roll of EXACTLY 6 slots per visit — 3 individual
// stickers + 3 "mixed" slots (each independently a Base, Pillar, or Pack, by
// MIXED_KIND_WEIGHTS). Buy empties only that slot; reroll-all at 3→4→5 (reset
// per visit); persisted in campaign state (no free reroll via re-render); wiped
// on loss. Suit/stage gating still applies within every draw. DOM-free.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { CampaignState, StickerTypes, PillarTypes, BaseTypes, PackTypes, SamePowerTypes } = loadGame();
  const r = makeRunner("store-offer.test.mjs");
  const stickerIds = new Set(StickerTypes.ids);
  const pillarIds = new Set(PillarTypes.ids);
  const baseIds = new Set(BaseTypes.ids);
  const packIds = new Set(PackTypes.ids);
  const samePowerIds = new Set(SamePowerTypes.ids);
  const idOk = (kind, id) => kind === "pillar" ? pillarIds.has(id)
    : kind === "base" ? baseIds.has(id) : kind === "pack" ? packIds.has(id)
    : kind === "samepower" ? samePowerIds.has(id) : false;

  // Open the store repeatedly until a mixed slot of `kind` is offered; return
  // { c, slot, id }. (Mixed draws are random; a few opens always suffice.)
  const findMixed = (c, kind) => {
    for (let i = 0; i < 200; i++) {
      const offer = c.openStore();
      const slot = offer.mixed.findIndex(s => s && s.kind === kind);
      if (slot !== -1) return { slot, id: offer.mixed[slot].id };
    }
    throw new Error("never offered a mixed " + kind);
  };

  // --- Shape of a fresh offer: exactly 3 stickers + 3 mixed -------------
  {
    const c = CampaignState.create();
    r.eq(c.getStoreOffer(), null, "no offer until the store opens");
    const offer = c.openStore();
    r.eq(offer.stickers.length, 3, "offer has 3 sticker slots");
    r.eq(offer.mixed.length, 3, "offer has 3 mixed slots");
    r.eq(offer.stickers.length + offer.mixed.length, 6, "exactly 6 slots per visit");
    r.ok(offer.stickers.every(id => stickerIds.has(id)), "all offered stickers are real registry ids");
    r.ok(offer.mixed.every(s => s && ["base", "pillar", "pack", "samepower"].includes(s.kind)),
      "every mixed slot is a base / pillar / pack / same-power");
    r.ok(offer.mixed.every(s => idOk(s.kind, s.id)), "every mixed slot's id is real for its kind");
    r.eq(offer.rerollCost, 3, "reroll cost starts at 3");
    r.eq(offer.samePowers, undefined, "no dedicated Same-Power slot (folded into the mixed rotation)");
  }

  // --- Same-Powers now surface PERIODICALLY in the mixed rotation -------
  {
    const c = CampaignState.create();
    const count = { base: 0, pillar: 0, pack: 0, samepower: 0 }, N = 3000;
    for (let i = 0; i < N; i++) c.openStore().mixed.forEach(s => { if (s) count[s.kind]++; });
    r.ok(count.samepower > 0, "Same-Powers appear in mixed slots");
    // weight 1 of base:2 pillar:2 pack:1 samepower:1 (total 6) → ≈1/6 per slot.
    const share = count.samepower / (N * 3);
    r.ok(share > 0.11 && share < 0.23, "Same-Power share ≈1/6 per mixed slot (got " + share.toFixed(3) + ")");
    // can be bought from a mixed slot into the Same-Power inventory.
    c.addCoins(200);
    const found = findMixed(c, "samepower");
    const before = c.samePowerInventoryCount(found.id);
    const res = c.buyMixedSlot(found.slot, () => 0.5);
    r.ok(res.ok && res.kind === "samepower", "buying a mixed Same-Power slot succeeds");
    r.eq(c.samePowerInventoryCount(found.id), before + 1, "the bought Same-Power lands in inventory");
    r.eq(c.getStoreOffer().mixed[found.slot], null, "that mixed slot is now empty");
  }

  // --- Mixed slots draw all three kinds; packs are the rarer category --
  {
    const c = CampaignState.create();
    const count = { base: 0, pillar: 0, pack: 0 };
    for (let i = 0; i < 600; i++) c.openStore().mixed.forEach(s => { if (s) count[s.kind]++; });
    r.ok(count.base > 0 && count.pillar > 0 && count.pack > 0, "mixed slots offer bases, pillars AND packs");
    // base:pillar:pack = 2:2:1 → packs are the least common category.
    r.ok(count.pack < count.base && count.pack < count.pillar, "packs are rarer than bases/pillars (2:2:1 weighting)");
  }

  // --- Reading the offer never re-rolls (no free reroll via re-render) --
  {
    const c = CampaignState.create();
    c.openStore();
    const a = c.getStoreOffer();
    const b = c.getStoreOffer();
    r.ok(a === b && a.stickers === b.stickers && a.mixed === b.mixed,
      "re-reading returns the SAME offer object (a render can't re-roll)");
  }

  // --- Buying a sticker empties ONLY that slot; rest stay --------------
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

  // --- buyMixedSlot: a Pillar slot banks to INVENTORY (placed later) ---
  {
    const c = CampaignState.create();
    c.addCoins(200);
    const { slot, id } = findMixed(c, "pillar");
    const price = c.priceOfMixed(slot);
    r.eq(price, c.priceOfPillar(id), "priceOfMixed reports the Pillar's price");
    const coins0 = c.getCoins();
    const res = c.buyMixedSlot(slot, Math.random);
    r.ok(res.ok && res.kind === "pillar", "buying a mixed Pillar slot succeeds");
    r.ok(!res.reveal, "a Pillar buy has no pack reveal");
    r.eq(c.pillarInventoryCount(id), 1, "bought Pillar went to inventory");
    r.eq(c.columnPillar(1), null, "buying does NOT place it on a column");
    r.eq(c.getStoreOffer().mixed[slot], null, "that mixed slot is now empty");
    r.eq(c.getCoins(), coins0 - price, "charged the fixed Pillar price");
    r.ok(!c.buyMixedSlot(slot, Math.random).ok, "can't buy an already-empty mixed slot");
    r.ok(c.placePillar(id, 1), "place the owned Pillar on column 1");
    r.eq(c.columnPillar(1), id, "Pillar now bound to column 1");
  }

  // --- buyMixedSlot: a Base slot banks to INVENTORY -------------------
  {
    const c = CampaignState.create();
    c.addCoins(200);
    const { slot, id } = findMixed(c, "base");
    const price = c.priceOfMixed(slot);
    const coins0 = c.getCoins();
    const res = c.buyMixedSlot(slot, Math.random);
    r.ok(res.ok && res.kind === "base", "buying a mixed Base slot succeeds");
    r.eq(c.baseInventoryCount(id), 1, "bought Base went to inventory");
    r.eq(c.getStoreOffer().mixed[slot], null, "that mixed slot is now empty");
    r.eq(c.getCoins(), coins0 - price, "charged the fixed Base price");
  }

  // --- buyMixedSlot: a Pack slot charges + opens (returns a reveal) ----
  {
    const c = CampaignState.create();
    c.addCoins(200);
    const { slot, id } = findMixed(c, "pack");
    const price = c.priceOfMixed(slot);
    const coins0 = c.getCoins();
    const res = c.buyMixedSlot(slot, Math.random);
    r.ok(res.ok && res.kind === "pack", "buying a mixed Pack slot succeeds");
    r.ok(res.reveal && res.reveal.packId === id, "the pack reveal carries the pack id");
    r.ok(Array.isArray(res.reveal.items) && res.reveal.items.length > 0, "the pack reveal lists items to pick");
    r.eq(c.getStoreOffer().mixed[slot], null, "that mixed slot is now empty");
    r.eq(c.getCoins(), coins0 - price, "charged the fixed Pack price");

    const broke = CampaignState.create();
    const m = findMixed(broke, "pack");
    r.ok(!broke.buyMixedSlot(m.slot, Math.random).ok, "can't buy a Pack with no coins");
  }

  // --- Reroll: replaces BOTH sections; 3 → 4 → 5; resets on store open -
  {
    const c = CampaignState.create();
    c.addCoins(100);
    c.openStore();
    c.buyOfferedSticker(0);                       // empty a slot...
    r.eq(c.getStoreOffer().stickers[0], null, "slot emptied before reroll");
    r.eq(c.storeRerollCost(), 3, "first reroll costs 3");
    const before = c.getCoins();
    r.ok(c.rerollStore(), "reroll #1");
    r.ok(c.getStoreOffer().stickers.every(id => id !== null), "reroll refills ALL sticker slots");
    r.ok(c.getStoreOffer().mixed.every(s => s && idOk(s.kind, s.id)), "reroll refills ALL mixed slots");
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

  // --- Suit-lock: suited STICKERS only roll once their suit is in play -
  {
    const sample = (c, n) => {
      const seen = new Set();
      for (let i = 0; i < n; i++) c.openStore().stickers.forEach(id => seen.add(id));
      return seen;
    };
    const s1 = sample(CampaignState.create(), 400);          // Stage 1: ♦ ♥
    r.ok(s1.has("diamondGuard") && s1.has("heartGuard"), "Stage 1 offers the ♦ and ♥ guards");
    r.ok(!s1.has("clubGuard"), "Stage 1 NEVER offers the ♣ guard (suit not in play)");
    r.ok(!s1.has("suitImmunity"), "Stage 1 NEVER offers the ♠ guard (suit not in play)");

    const c2 = CampaignState.create();
    c2.advancePhase();                 // → Stage 2: ♦ ♥ ♣
    r.eq(c2.currentStage, 2, "advanced to Stage 2");
    const s2 = sample(c2, 400);
    r.ok(s2.has("clubGuard"), "Stage 2 offers the ♣ guard (its suit is now in play)");
    r.ok(!s2.has("suitImmunity"), "Stage 2 still NEVER offers the ♠ guard");

    const c3 = CampaignState.create();
    c3.advancePhase(); c3.advancePhase();                 // → Stage 3: ♦ ♥ ♣ ♠
    r.eq(c3.currentStage, 3, "advanced to Stage 3");
    const s3 = sample(c3, 400);
    r.ok(s3.has("suitImmunity"), "Stage 3 offers the ♠ guard (all four suits in play)");
  }

  // --- Suit-lock: suited PILLARS in mixed slots obey the same gate -----
  // The rebalance removed the ♠/♣/♦ Bonus pillars — only the ♥ Heart Bonus
  // remains (a Stage-1 suit), so it's always eligible and the deleted ones never
  // surface in any stage.
  {
    const samplePillars = (c, n) => {
      const seen = new Set();
      for (let i = 0; i < n; i++)
        c.openStore().mixed.forEach(s => { if (s && s.kind === "pillar") seen.add(s.id); });
      return seen;
    };
    const p1 = samplePillars(CampaignState.create(), 700);    // Stage 1: ♦ ♥
    r.ok(p1.has("heartBounty"), "Stage 1 offers the ♥ Heart Bonus pillar");
    r.ok(!p1.has("clubBounty") && !p1.has("spadeBounty") && !p1.has("diamondBounty"),
      "the removed ♠/♣/♦ Bonus pillars never appear");
  }

  // --- Suit-lock: suited BASES (the Dig family) in mixed obey the gate -
  {
    const sampleBases = (c, n) => {
      const seen = new Set();
      for (let i = 0; i < n; i++)
        c.openStore().mixed.forEach(s => { if (s && s.kind === "base") seen.add(s.id); });
      return seen;
    };
    const b1 = sampleBases(CampaignState.create(), 700);      // Stage 1: ♦ ♥
    r.ok(!b1.has("clubDig"), "Stage 1 NEVER offers Club Dig (♣ not in play)");
    r.ok(!b1.has("spadeDig"), "Stage 1 NEVER offers Spade Dig (♠ not in play)");

    const cb3 = CampaignState.create();
    cb3.advancePhase(); cb3.advancePhase();                 // → Stage 3: all four
    const b3 = sampleBases(cb3, 700);
    r.ok(b3.has("spadeDig"), "Stage 3 offers Spade Dig (all four suits in play)");
  }

  return r.summary();
}
