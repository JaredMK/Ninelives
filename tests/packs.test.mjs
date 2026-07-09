// Card Packs + Sticker Packs — Phase 1: data model + reveal/sticker-roll +
// pending tray (2-cap) + persistence. Pure, DOM-free CampaignState logic.
import { loadGame, makeRunner } from "./_harness.mjs";

// Deterministic RNG so reveal rolls are reproducible.
function rngFrom(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function run() {
  const { CampaignState, PackTypes, StickerTypes, DeckManager } = loadGame();
  const r = makeRunner("packs.test.mjs");
  const stickerIds = new Set(StickerTypes.ids);

  // --- PackTypes registry -----------------------------------------------
  {
    r.eq(PackTypes.all().length, 3, "three pack types registered (large + small card packs, one sticker pack)");
    r.ok(!PackTypes.get("stickerPack5") && !PackTypes.get("stickerPack3"), "the larger sticker-pack variants are gone");
    r.eq(PackTypes.get("cardPack").size, 5, "the LARGE card pack reveals 5");
    r.eq(PackTypes.get("cardPack").keep, 1, "the large card pack keeps 1");
    r.eq(PackTypes.get("cardPack").price, 10, "the large card pack costs 10");
    r.eq(PackTypes.get("cardPack").label, "Large Card Pack", "the 5-card pack is named Large Card Pack");
    r.eq(PackTypes.get("smallCardPack").size, 3, "the SMALL card pack reveals 3");
    r.eq(PackTypes.get("smallCardPack").keep, 1, "the small card pack keeps 1");
    r.eq(PackTypes.get("smallCardPack").price, 8, "the small card pack costs 8");
    r.eq(PackTypes.get("smallCardPack").tier, "common", "the small card pack is common");
    r.eq(PackTypes.get("smallCardPack").kind, "card", "the small card pack is a CARD pack");
    r.eq(PackTypes.get("stickerPack").size, 3, "the sticker pack reveals 3");
    r.eq(PackTypes.get("stickerPack").keep, 1, "the sticker pack keeps 1");
    r.eq(PackTypes.get("stickerPack").price, 5, "the sticker pack costs 5");
    r.eq(PackTypes.get("cardPack").kind, "card", "card pack kind");
    r.eq(PackTypes.get("stickerPack").kind, "sticker", "sticker pack kind");
    const missing = PackTypes.all().filter(t => !t.description || !t.description.trim());
    r.eq(missing.length, 0, "every pack has help text");
  }

  // --- Card-pack reveal: N cards, valid rank + IN-PLAY suit, unique ids --
  {
    const c = CampaignState.create();   // Stage 1 → suits ♦ ♥
    const inPlay = new Set(["♦", "♥"]);
    const cards = c.revealPack("cardPack", rngFrom(1));
    r.eq(cards.length, 5, "the card pack reveals 5 cards");
    const okShape = cards.every(card =>
      (card.joker || card.blank) ||    // special options carry no rank/suit
      (card.currentRank >= 2 && card.currentRank <= 14 &&
      ["♦", "♥", "♣", "♠"].includes(card.suit) && card.id >= 52 &&
      Array.isArray(card.modifications) && Array.isArray(card.stickers) && card.compoundHits === 0));
    r.ok(okShape, "every revealed card: rank 2–A, a real suit, fresh id ≥52, proper shape (Jokers/Blanks exempt)");
    const ids = cards.map(c2 => c2.id);
    r.eq(new Set(ids).size, 5, "revealed card ids are unique");
    r.ok(cards.every(card => card.stickers.every(s => stickerIds.has(s.type))),
      "any on-card stickers are real registry stickers");
  }

  // --- Sticker-pack reveal: N sticker ids, suit-locked ------------------
  {
    const c = CampaignState.create();
    const ids = c.revealPack("stickerPack", rngFrom(2));
    r.eq(ids.length, 3, "the sticker pack reveals 3 stickers");
    r.ok(ids.every(id => stickerIds.has(id)), "all revealed stickers are real");
    // (Stage gating REMOVED: a revealed sticker may be ANY registry sticker —
    //  suit-locked ones included — at any stage. "All real" above covers it.)
  }

  // --- On-card stickers stay in-play even via Change-Suit Random + rough dist
  {
    const c = CampaignState.create();
    const inPlay = new Set(["♦", "♥"]);
    const rng = rngFrom(7);
    let withAny = 0, withTwo = 0, withThree = 0;
    const N = 8000;
    let normal = 0, specials = 0;
    let allInPlay = true, allValidRank = true, allStickersReal = true;
    for (let i = 0; i < N; i++) {
      const card = c.genPackCard(rng);
      if (card.joker || card.blank) { specials++; continue; }    // special options (no rank/suit/stickers)
      normal++;
      // The ROLLED suit stays in-play (deck-composition pacing). An ungated
      // suit-changing sticker may then move it anywhere — recover the rolled
      // suit from the card's modification history before checking.
      const firstChange = (card.modifications || []).find(m => m.op === "changeSuit");
      if (!inPlay.has(firstChange ? firstChange.from : card.suit)) allInPlay = false;
      if (!(card.currentRank >= 2 && card.currentRank <= 14)) allValidRank = false;
      if (!card.stickers.every(s => stickerIds.has(s.type))) allStickersReal = false;
      if (card.stickers.length >= 1) withAny++;
      if (card.stickers.length >= 2) withTwo++;
      if (card.stickers.length >= 3) withThree++;
    }
    // Joker + Blank each carry weight 0.5 against the FULL 52-card pool →
    // P(special) = 1/53 ≈ 1.9% of options (regardless of suit gating).
    const pSpecial = specials / N;
    r.ok(pSpecial > 0.010 && pSpecial < 0.028, "≈1.9% of options are Joker/Blank (got " + pSpecial.toFixed(4) + ")");
    r.ok(allInPlay, "generated card ROLLED suits stay in-play (ungated stickers may re-suit them after)");
    r.ok(allValidRank, "generated card ranks stay 2–A even after rank stickers");
    r.ok(allStickersReal, "generated card stickers are all real");
    // New odds: 33% one / 11% two / 3% three / 1% four → ≈48% ≥1, ≈15% ≥2, ≈4% ≥3.
    // (A rank sticker that lands on an at-boundary card doesn't attach, so observed
    //  rates run a touch under nominal; bounds are kept generous for that.)
    const pAny = withAny / normal, pTwo = withTwo / normal, pThree = withThree / normal;
    r.ok(pAny > 0.42 && pAny < 0.53, "≈48% of cards carry ≥1 sticker (got " + pAny.toFixed(3) + ")");
    r.ok(pTwo > 0.10 && pTwo < 0.19, "≈15% of cards carry ≥2 stickers (got " + pTwo.toFixed(3) + ")");
    r.ok(pThree > 0.015 && pThree < 0.065, "≈4% of cards carry ≥3 stickers (got " + pThree.toFixed(3) + ")");
  }

  // --- Stage 2 widens the suit pool (basic cross-stage check) -----------
  {
    const c = CampaignState.create();
    c.advancePhase();   // → Stage 2 (4 runs/stage; suits ♦ ♥ ♣)
    r.eq(c.currentStage, 2, "advanced to Stage 2");
    const ok = ["♦", "♥", "♣"];
    const cards = c.revealPack("cardPack", rngFrom(9));
    r.ok(cards.every(card => (card.joker || card.blank) || ok.includes(card.suit)), "Stage-2 pack cards never roll ♠ (not in play yet)");
  }

  // --- Pending tray: UNLIMITED (cap removed), discard, take -------------
  {
    const c = CampaignState.create();
    r.eq(c.packTrayCap, Infinity, "tray cap removed (unlimited)");
    const [a, b, d, e, f] = c.revealPack("cardPack", rngFrom(3));
    r.ok(c.addPackCard(a).ok, "1st pack card held");
    r.ok(c.addPackCard(b).ok, "2nd pack card held");
    const third = c.addPackCard(d);
    r.ok(third.ok && !third.full, "3rd add succeeds — no cap, never 'full'");
    r.ok(c.addPackCard(e).ok && c.addPackCard(f).ok, "4th and 5th held too");
    r.eq(c.packTrayCount(), 5, "tray holds all five (unlimited)");
    r.ok(c.discardPackCard(0), "discard one");
    r.eq(c.packTrayCount(), 4, "tray down to 4 after discard");
    const taken = c.takePackCard(0);
    r.ok(taken && taken.id != null, "takePackCard returns the card");
    r.eq(c.packTrayCount(), 3, "takePackCard removes it from the tray");
  }

  // --- Sticker-pack keep → normal inventory -----------------------------
  {
    const c = CampaignState.create();
    r.eq(c.inventoryCount("rankUp"), 0, "no rankUp yet");
    r.ok(c.addStickerToInventory("rankUp"), "keep a revealed sticker");
    r.eq(c.inventoryCount("rankUp"), 1, "kept sticker lands in inventory");
    r.ok(!c.addStickerToInventory("nope"), "unknown sticker id rejected");
  }

  // --- Persistence: tray + nextCardId round-trip; reset wipes -----------
  {
    const c = CampaignState.create();
    const [pick] = c.revealPack("cardPack", rngFrom(5));
    c.addPackCard(pick);
    const snap = JSON.parse(JSON.stringify(c.serialize()));
    r.ok(Array.isArray(snap.packTray) && snap.packTray.length === 1, "snapshot carries the pending tray");
    r.ok(typeof snap.nextCardId === "number" && snap.nextCardId > 52, "snapshot carries nextCardId");

    const c2 = CampaignState.create();
    r.ok(c2.restore(snap), "restore accepts the snapshot");
    r.eq(c2.packTrayCount(), 1, "tray restored");
    r.eq(c2.getPackTray()[0].id, pick.id, "the held pack card's identity restored");
    // A newly generated card after restore gets a non-colliding id.
    const fresh = c2.genPackCard(rngFrom(6));
    r.ok(fresh.id >= snap.nextCardId, "post-restore card id doesn't collide with restored ids");

    c.reset();
    r.eq(c.packTrayCount(), 0, "reset wipes the pending tray");
    // nextCardId returns to the base 52 PLUS any duplicates the fresh map's
    // own +1 nodes minted at lock time (a stage can carry more pickups than
    // its suit has unique cards — rare, but legitimate).
    const snap2 = c.serialize();
    const minted = snap2.baseDeck.length - 52;
    r.eq(snap2.nextCardId, 52 + minted, "reset resets nextCardId to the fresh deck's size (52 + " + minted + " map-minted)");
  }

  // --- A pack card has the same shape as a base-deck card ---------------
  {
    const c = CampaignState.create();
    const base = c.getCards()[0];
    const pack = c.genPackCard(rngFrom(11));
    const baseKeys = Object.keys(base).sort().join(",");
    const packKeys = Object.keys(pack).sort().join(",");
    r.eq(packKeys, baseKeys, "pack card carries the same identity fields as a deck card");
  }

  // ===== Phase 2: store roll + buy/reveal (packs live in unified slots) ===
  // Find a store visit whose slots include a pack; return { c, slot, id }.
  const findMixedPack = (c) => {
    for (let i = 0; i < 400; i++) {
      const offer = c.openStore();
      const slot = offer.slots.findIndex(s => s && s.kind === "pack");
      if (slot !== -1) return { slot, id: offer.slots[slot].id };
    }
    throw new Error("never offered a pack slot");
  };
  {
    const c = CampaignState.create();
    c.addCoins(100);
    const { slot, id: packId } = findMixedPack(c);
    const t = PackTypes.get(packId);
    const before = c.getCoins();
    const res = c.buyMixedSlot(slot, rngFrom(99));
    r.ok(res.ok && res.kind === "pack" && res.reveal && res.reveal.packId === packId, "buyMixedSlot reveals the bought pack");
    r.eq(res.reveal.items.length, t.size, "reveals `size` items");
    r.eq(res.reveal.keep, t.keep, "carries the keep count");
    r.eq(c.getStoreOffer().slots[slot], null, "buying empties only that slot");
    r.eq(c.getCoins(), before - t.price, "charged the fixed pack price (no escalation)");
    r.ok(!c.buyMixedSlot(slot, rngFrom(1)).ok, "can't buy an already-empty mixed slot");

    const broke = CampaignState.create();
    const m = findMixedPack(broke);
    r.ok(!broke.buyMixedSlot(m.slot, rngFrom(2)).ok, "can't buy a pack with no coins");
  }

  // --- Pack draws: both pack TYPES can appear across many visits ----------
  {
    const c = CampaignState.create();
    const kinds = new Set();
    for (let i = 0; i < 1200; i++)
      c.openStore().slots.forEach(s => { if (s && s.kind === "pack") kinds.add((PackTypes.get(s.id) || {}).kind); });
    r.ok(kinds.has("card") && kinds.has("sticker"), "pack slots can roll BOTH a Card Pack and a Sticker Pack");
  }

  // ===== Phase 3: permanent deck replacement =============================
  {
    const c = CampaignState.create();
    const [pick] = c.revealPack("cardPack", rngFrom(5));
    c.addPackCard(pick);
    const dealt = c.getCards().find(x => x.suit === "♦");   // an in-play card
    c.applySticker(dealt.id, "tieSafe");                    // build it up, to verify destruction
    r.eq(c.getCards().length, 52, "deck starts at 52");
    const ret = c.replaceDeckCard(dealt.id, 0);
    r.ok(ret && ret.id === pick.id, "replaceDeckCard returns the inserted pack card");
    r.eq(c.getCards().length, 52, "deck stays 52 after replacement");
    r.ok(!c.getCards().some(x => x.id === dealt.id), "the replaced card (and its stickers) is gone forever");
    r.ok(c.getCards().some(x => x.id === pick.id), "the pack card is now a deck card");
    r.eq(c.packTrayCount(), 0, "the used pack card left the tray");

    const c2 = CampaignState.create();
    r.ok(c2.restore(JSON.parse(JSON.stringify(c.serialize()))), "save/restore accepts the post-replace deck");
    r.eq(c2.getCards().length, 52, "restored deck still 52");
    r.ok(c2.getCards().some(x => x.id === pick.id), "the replacement persists across save/restore");
    r.ok(!c.replaceDeckCard(99999, 0), "replacing an unknown card id fails safely");
  }

  // ===== Phase 4: suit-locking across stages =============================
  {
    const c = CampaignState.create();
    const stages = [
      { advances: 0, ok: ["♦", "♥"] },
      { advances: 1, ok: ["♦", "♥", "♣"] },
      { advances: 2, ok: ["♦", "♥", "♣", "♠"] },
    ];
    let fresh = CampaignState.create();
    let totalAdv = 0;
    for (const st of stages) {
      while (totalAdv < st.advances) { fresh.advancePhase(); totalAdv++; }
      const allowed = new Set(st.ok);
      let cardsOk = true, stickersReal = true;
      for (let i = 0; i < 200; i++) {
        const card = fresh.genPackCard(rngFrom(1000 + i));
        if (card.joker || card.blank) continue;                 // special options carry no suit
        // The ROLLED suit follows the stage (composition pacing); an ungated
        // suit-changing sticker may re-suit it — recover the roll from the
        // modification history. (Sticker gating itself is REMOVED by design.)
        const firstChange = (card.modifications || []).find(m => m.op === "changeSuit");
        if (!allowed.has(firstChange ? firstChange.from : card.suit)) cardsOk = false;
        if (!card.stickers.every(s => !!StickerTypes.get(s.type))) stickersReal = false;
      }
      const ids = fresh.revealPack("stickerPack", rngFrom(2000 + st.advances));
      if (!ids.every(id => !!StickerTypes.get(id))) stickersReal = false;
      r.ok(cardsOk, "Stage " + fresh.currentStage + ": pack-card ROLLED suits stay in play");
      r.ok(stickersReal, "Stage " + fresh.currentStage + ": every rolled sticker is a real registry sticker");
    }
  }

  // --- Duplicate sticker: deep, independent copy into the card inventory --
  {
    const c = CampaignState.create();
    const src = c.getCards()[0];
    c.applySticker(src.id, "tieSafe");           // give the source a sticker
    const before = c.packTrayCount();
    const copy = c.duplicateCard(src.id);
    r.ok(copy && copy.id !== src.id, "duplicate gets a fresh, distinct id");
    r.eq(c.packTrayCount(), before + 1, "the copy lands in the card inventory (pack tray)");
    r.eq(copy.suit, c.getCards().find(x => x.id === src.id).suit, "copy keeps the suit");
    r.ok(copy.stickers.some(s => s.type === "tieSafe"), "copy includes the original's stickers");
    // Independence: editing the copy must not touch the original (and vice versa).
    copy.stickers.push({ type: "heavy" });
    const srcNow = c.getCards().find(x => x.id === src.id);
    r.ok(!srcNow.stickers.some(s => s.type === "heavy"), "editing the copy does NOT change the original");
    c.applySticker(src.id, "anchor");
    r.ok(!copy.stickers.some(s => s.type === "anchor"), "editing the original does NOT change the copy");
  }

  return r.summary();
}
