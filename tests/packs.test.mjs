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
    r.eq(PackTypes.all().length, 2, "exactly two pack types registered (one card pack, one sticker pack)");
    r.ok(!PackTypes.get("stickerPack5") && !PackTypes.get("stickerPack3"), "the larger sticker-pack variants are gone");
    r.eq(PackTypes.get("cardPack").size, 5, "the card pack reveals 5");
    r.eq(PackTypes.get("cardPack").keep, 1, "the card pack keeps 1");
    r.eq(PackTypes.get("cardPack").price, 12, "the card pack costs 12");
    r.eq(PackTypes.get("stickerPack").size, 3, "the sticker pack reveals 3");
    r.eq(PackTypes.get("stickerPack").keep, 1, "the sticker pack keeps 1");
    r.eq(PackTypes.get("stickerPack").price, 3, "the sticker pack costs 3");
    r.eq(PackTypes.get("cardPack").kind, "card", "card pack kind");
    r.eq(PackTypes.get("stickerPack").kind, "sticker", "sticker pack kind");
    const missing = PackTypes.all().filter(t => !t.description || !t.description.trim());
    r.eq(missing.length, 0, "every pack has help text");
  }

  // --- Card-pack reveal: N cards, valid rank + IN-PLAY suit, unique ids --
  {
    const c = CampaignState.create();   // Stage 1 → suits ♠ ♥
    const inPlay = new Set(["♠", "♥"]);
    const cards = c.revealPack("cardPack", rngFrom(1));
    r.eq(cards.length, 5, "the card pack reveals 5 cards");
    const okShape = cards.every(card =>
      card.currentRank >= 2 && card.currentRank <= 14 &&
      inPlay.has(card.suit) && card.id >= 52 &&
      Array.isArray(card.modifications) && Array.isArray(card.stickers) && card.compoundHits === 0);
    r.ok(okShape, "every revealed card: rank 2–A, in-play suit, fresh id ≥52, proper shape");
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
    // Suit-locked: no revealed sticker requires a not-yet-present suit.
    const inPlay = new Set(["♠", "♥"]);
    r.ok(ids.every(id => { const t = StickerTypes.get(id); return !t.suit || inPlay.has(t.suit); }),
      "revealed stickers never require an out-of-play suit");
  }

  // --- On-card stickers stay in-play even via Change-Suit Random + rough dist
  {
    const c = CampaignState.create();
    const inPlay = new Set(["♠", "♥"]);
    const rng = rngFrom(7);
    let withAny = 0, withTwo = 0, withThree = 0;
    const N = 8000;
    let allInPlay = true, allValidRank = true, allStickersReal = true;
    for (let i = 0; i < N; i++) {
      const card = c.genPackCard(rng);
      if (!inPlay.has(card.suit)) allInPlay = false;             // includes post-Change-Suit-Random
      if (!(card.currentRank >= 2 && card.currentRank <= 14)) allValidRank = false;
      if (!card.stickers.every(s => stickerIds.has(s.type))) allStickersReal = false;
      if (card.stickers.length >= 1) withAny++;
      if (card.stickers.length >= 2) withTwo++;
      if (card.stickers.length >= 3) withThree++;
    }
    r.ok(allInPlay, "generated card suits stay in-play (Change-Suit Random respects in-play suits)");
    r.ok(allValidRank, "generated card ranks stay 2–A even after rank stickers");
    r.ok(allStickersReal, "generated card stickers are all real");
    // New odds: 33% one / 11% two / 3% three / 1% four → ≈48% ≥1, ≈15% ≥2, ≈4% ≥3.
    // (A rank sticker that lands on an at-boundary card doesn't attach, so observed
    //  rates run a touch under nominal; bounds are kept generous for that.)
    const pAny = withAny / N, pTwo = withTwo / N, pThree = withThree / N;
    r.ok(pAny > 0.42 && pAny < 0.53, "≈48% of cards carry ≥1 sticker (got " + pAny.toFixed(3) + ")");
    r.ok(pTwo > 0.10 && pTwo < 0.19, "≈15% of cards carry ≥2 stickers (got " + pTwo.toFixed(3) + ")");
    r.ok(pThree > 0.015 && pThree < 0.065, "≈4% of cards carry ≥3 stickers (got " + pThree.toFixed(3) + ")");
  }

  // --- Stage 2 widens the suit pool (basic cross-stage check) -----------
  {
    const c = CampaignState.create();
    c.advance(); c.advance(); c.advance(); c.advance();   // → Stage 2 (4 runs/stage; suits ♠ ♥ ♦)
    r.eq(c.currentStage, 2, "advanced to Stage 2");
    const ok = ["♠", "♥", "♦"];
    const cards = c.revealPack("cardPack", rngFrom(9));
    r.ok(cards.every(card => ok.includes(card.suit)), "Stage-2 pack cards never roll ♣ (not in play yet)");
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
    r.eq(c.serialize().nextCardId, 52, "reset resets nextCardId to 52");
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

  // ===== Phase 2: store roll + buy/reveal =================================
  {
    const c = CampaignState.create();
    c.addCoins(100);
    // Both pack slots are always filled now, so slot 0 always holds a pack.
    c.openStore(rngFrom(1));
    const offer = c.getStoreOffer();
    r.ok(offer && offer.packs[0], "store offer rolls a pack into the section");
    const packId = offer.packs[0];
    const t = PackTypes.get(packId);
    const before = c.getCoins();
    const result = c.buyOfferedPack(0, rngFrom(99));
    r.ok(result && result.packId === packId, "buyOfferedPack reveals the bought pack");
    r.eq(result.items.length, t.size, "reveals `size` items");
    r.eq(result.keep, t.keep, "carries the keep count");
    r.eq(c.getStoreOffer().packs[0], null, "buying empties only that pack slot");
    r.eq(c.getCoins(), before - t.price, "charged the fixed pack price (no escalation)");
    r.ok(!c.buyOfferedPack(0, rngFrom(1)), "can't buy an already-empty pack slot");

    const broke = CampaignState.create();
    broke.openStore(rngFrom(2));   // slot 0 is always a pack now
    r.ok(broke.getStoreOffer().packs[0], "broke offer still has a pack in slot 0");
    r.ok(!broke.buyOfferedPack(0, rngFrom(2)), "can't buy a pack with no coins");
  }

  // --- Both pack slots are always filled — one of EACH type (no dupes) ---
  {
    const c = CampaignState.create();
    let allFull = true, oneOfEach = true, varied = new Set();
    for (let seed = 1; seed <= 40; seed++) {
      c.openStore(rngFrom(seed));
      const packs = c.getStoreOffer().packs;
      if (packs.length !== 2 || !packs.every(Boolean)) allFull = false;
      // With exactly two pack types for two slots, every visit shows one card
      // pack and one sticker pack (distinct roll), never a duplicate.
      const kinds = packs.map(id => (PackTypes.get(id) || {}).kind).sort().join(",");
      if (kinds !== "card,sticker") oneOfEach = false;
      varied.add(packs.join(","));
    }
    r.ok(allFull, "every visit fills both pack slots (no empty/absent visits)");
    r.ok(oneOfEach, "every visit offers exactly one Card Pack and one Sticker Pack");
    r.ok(varied.size > 1, "pack slots re-roll across visits (slot order varies)");
  }

  // ===== Phase 3: permanent deck replacement =============================
  {
    const c = CampaignState.create();
    const [pick] = c.revealPack("cardPack", rngFrom(5));
    c.addPackCard(pick);
    const dealt = c.getCards().find(x => x.suit === "♠");   // an in-play card
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
      { advances: 0, ok: ["♠", "♥"] },
      { advances: 4, ok: ["♠", "♥", "♦"] },
      { advances: 8, ok: ["♠", "♥", "♦", "♣"] },
    ];
    let fresh = CampaignState.create();
    let totalAdv = 0;
    for (const st of stages) {
      while (totalAdv < st.advances) { fresh.advance(); totalAdv++; }
      const allowed = new Set(st.ok);
      let cardsOk = true, cardStickersOk = true, packStickersOk = true;
      for (let i = 0; i < 200; i++) {
        const card = fresh.genPackCard(rngFrom(1000 + i));
        if (!allowed.has(card.suit)) cardsOk = false;
        if (!card.stickers.every(s => { const t = StickerTypes.get(s.type); return !t.suit || allowed.has(t.suit); })) cardStickersOk = false;
      }
      const ids = fresh.revealPack("stickerPack", rngFrom(2000 + st.advances));
      if (!ids.every(id => { const t = StickerTypes.get(id); return !t.suit || allowed.has(t.suit); })) packStickersOk = false;
      r.ok(cardsOk, "Stage " + fresh.currentStage + ": pack-card suits stay in play");
      r.ok(cardStickersOk, "Stage " + fresh.currentStage + ": on-card stickers never require an out-of-play suit");
      r.ok(packStickersOk, "Stage " + fresh.currentStage + ": sticker-pack stickers never require an out-of-play suit");
    }
  }

  return r.summary();
}
