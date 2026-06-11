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
    r.eq(offer.pillars.length, 3, "offer has 3 Pillar slots");
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

  // --- Buying a Pillar empties its slot + banks it to INVENTORY (placed later) -
  {
    const c = CampaignState.create();
    c.addCoins(100);
    c.openStore();
    const pid = c.getStoreOffer().pillars[0];
    const price = c.priceOfPillar(pid);
    const coins0 = c.getCoins();
    r.ok(c.buyOfferedPillar(0), "buy offered Pillar slot 0 (to inventory)");
    r.eq(c.pillarInventoryCount(pid), 1, "bought Pillar went to inventory");
    r.eq(c.columnPillar(1), null, "buying does NOT place it on a column");
    r.eq(c.getStoreOffer().pillars[0], null, "offered Pillar slot 0 now empty");
    r.eq(c.getCoins(), coins0 - price, "charged the fixed Pillar price");
    r.ok(!c.buyOfferedPillar(0), "can't buy an already-empty Pillar slot");
    // Placement (setup phase) moves it inventory → column.
    r.ok(c.placePillar(pid, 1), "place the owned Pillar on column 1");
    r.eq(c.columnPillar(1), pid, "Pillar now bound to column 1");
    r.eq(c.pillarInventoryCount(pid), 0, "placing consumes it from inventory");
    r.ok(!c.placePillar(pid, 1), "can't place a Pillar you no longer own");
  }

  // --- Pillar inventory: place / displace-swap / pick-up round-trips ------
  {
    const c = CampaignState.create();
    c.addCoins(200);
    c.debugGrantPillar("columnGuardian");
    c.debugGrantPillar("greedy");
    r.eq(c.pillarInventoryCount("columnGuardian"), 1, "owned 1 Guardian");
    r.ok(c.placePillar("columnGuardian", 0), "place Guardian on col 0");
    r.eq(c.pillarInventoryCount("columnGuardian"), 0, "Guardian left inventory");
    // Placing onto an occupied column returns the displaced Pillar to inventory.
    r.ok(c.placePillar("greedy", 0), "place Greedy on the same column");
    r.eq(c.columnPillar(0), "greedy", "Greedy now holds col 0");
    r.eq(c.pillarInventoryCount("columnGuardian"), 1, "displaced Guardian returned to inventory");
    // Pick-up clears the column and banks it.
    r.eq(c.unplacePillar(0), "greedy", "pick up returns the placed id");
    r.eq(c.columnPillar(0), null, "column 0 now empty");
    r.eq(c.pillarInventoryCount("greedy"), 1, "Greedy back in inventory");
    r.eq(c.unplacePillar(0), null, "pick up an empty column returns null");
    r.ok(!c.placePillar("columnGuardian", 9), "placement rejects an out-of-range column");
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

  // --- Suit-lock: suited stickers only roll once their suit is in play ---
  // ♣/♠ Suit Guards must not be offered before their stage introduces that
  // suit; ♦/♥ guards are always available (Stage 1's base pair). Many opens:
  // an out-of-play guard appearing even once is a lock failure (0 probability).
  {
    const sample = (c, n) => {
      const seen = new Set();
      for (let i = 0; i < n; i++) c.openStore().stickers.forEach(id => seen.add(id));
      return seen;
    };
    const s1 = sample(CampaignState.create(), 300);          // Stage 1: ♦ ♥
    r.ok(s1.has("diamondGuard") && s1.has("heartGuard"), "Stage 1 offers the ♦ and ♥ guards");
    r.ok(!s1.has("clubGuard"), "Stage 1 NEVER offers the ♣ guard (suit not in play)");
    r.ok(!s1.has("suitImmunity"), "Stage 1 NEVER offers the ♠ guard (suit not in play)");

    const c2 = CampaignState.create();
    for (let i = 0; i < 4; i++) c2.advance();                 // → Stage 2 (4 runs/stage): ♦ ♥ ♣
    r.eq(c2.currentStage, 2, "advanced to Stage 2");
    const s2 = sample(c2, 300);
    r.ok(s2.has("clubGuard"), "Stage 2 offers the ♣ guard (its suit is now in play)");
    r.ok(!s2.has("suitImmunity"), "Stage 2 still NEVER offers the ♠ guard");

    const c3 = CampaignState.create();
    for (let i = 0; i < 8; i++) c3.advance();                 // → Stage 3 (4 runs/stage): ♦ ♥ ♣ ♠
    r.eq(c3.currentStage, 3, "advanced to Stage 3");
    const s3 = sample(c3, 300);
    r.ok(s3.has("suitImmunity"), "Stage 3 offers the ♠ guard (all four suits in play)");
  }

  // --- Suit-lock: suited PILLARS only roll once their suit is in play -----
  // The four suit Bonus pillars carry a `suit`; ♣/♠ Bonus must not be offered
  // before their stage introduces that suit (the receptor leak). ♦/♥ Bonus are
  // always available. Many opens; any out-of-play appearance fails.
  {
    const sampleP = (c, n) => {
      const seen = new Set();
      for (let i = 0; i < n; i++) c.openStore().pillars.forEach(id => seen.add(id));
      return seen;
    };
    const p1 = sampleP(CampaignState.create(), 400);          // Stage 1: ♦ ♥
    r.ok(p1.has("diamondBounty") && p1.has("heartBounty"), "Stage 1 offers the ♦ and ♥ Bonus pillars");
    r.ok(!p1.has("clubBounty"), "Stage 1 NEVER offers the ♣ Bonus pillar (suit not in play)");
    r.ok(!p1.has("spadeBounty"), "Stage 1 NEVER offers the ♠ Bonus pillar (suit not in play)");

    const cp2 = CampaignState.create();
    for (let i = 0; i < 4; i++) cp2.advance();                 // → Stage 2: ♦ ♥ ♣
    const p2 = sampleP(cp2, 400);
    r.ok(p2.has("clubBounty"), "Stage 2 offers the ♣ Bonus pillar (its suit is now in play)");
    r.ok(!p2.has("spadeBounty"), "Stage 2 still NEVER offers the ♠ Bonus pillar");

    const cp3 = CampaignState.create();
    for (let i = 0; i < 8; i++) cp3.advance();                 // → Stage 3: ♦ ♥ ♣ ♠
    const p3 = sampleP(cp3, 400);
    r.ok(p3.has("spadeBounty"), "Stage 3 offers the ♠ Bonus pillar (all four suits in play)");

    // Reroll obeys the same lock (it shares freshOffer's pillar pool).
    const cr = CampaignState.create();
    cr.addCoins(10000);
    cr.openStore();
    const rerollSeen = new Set();
    for (let i = 0; i < 400 && cr.canReroll(); i++) {
      cr.getStoreOffer().pillars.forEach(id => rerollSeen.add(id));
      cr.rerollStore();
      cr.addCoins(10000);   // keep rerolls affordable
    }
    r.ok(!rerollSeen.has("clubBounty") && !rerollSeen.has("spadeBounty"),
      "Stage 1 rerolls never surface a ♣/♠ Bonus pillar either");
  }

  return r.summary();
}
