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
    // Registry size + tuning knobs (size / keep / price) are hand-edited in
    // items.js — assert all() matches the live id list and shape-check the knobs.
    r.eq(PackTypes.all().length, PackTypes.ids.length, "pack registry all() matches its live id list");
    r.eq(PackTypes.all().length, 4, "four packs ship: Large/Small Card + Large/Small Sticker");
    r.ok(!PackTypes.get("stickerPack5") && !PackTypes.get("stickerPack3"), "the larger sticker-pack variants are gone");
    // LARGE card pack — keep 2 is the FEATURE contract (large packs let you keep
    // two), so it is asserted; price stays a free tunable (>0, read live).
    r.eq(PackTypes.get("cardPack").size, 5, "the LARGE card pack reveals 5");
    r.eq(PackTypes.get("cardPack").keep, 2, "the LARGE card pack keeps 2 (PACKS1 feature contract)");
    r.ok(PackTypes.get("cardPack").price > 0, "the large card pack has a positive price (currently " + PackTypes.get("cardPack").price + ")");
    r.eq(PackTypes.get("cardPack").label, "Large Card Pack", "the 5-card pack is named Large Card Pack");
    r.eq(PackTypes.get("cardPack").kind, "card", "card pack kind");
    // SMALL card pack — keep 1 (small packs unchanged).
    r.eq(PackTypes.get("smallCardPack").size, 3, "the SMALL card pack reveals 3");
    r.eq(PackTypes.get("smallCardPack").keep, 1, "the small card pack keeps 1 (small packs unchanged)");
    r.ok(PackTypes.get("smallCardPack").price > 0, "the small card pack has a positive price (currently " + PackTypes.get("smallCardPack").price + ")");
    r.eq(PackTypes.get("smallCardPack").tier, "common", "the small card pack is common");
    r.eq(PackTypes.get("smallCardPack").kind, "card", "the small card pack is a CARD pack");
    // SMALL sticker pack (relabelled from "Sticker Pack") — keep 1, unchanged.
    r.eq(PackTypes.get("stickerPack").size, 3, "the small sticker pack reveals 3");
    r.eq(PackTypes.get("stickerPack").keep, 1, "the small sticker pack keeps 1 (small packs unchanged)");
    r.ok(PackTypes.get("stickerPack").price > 0, "the small sticker pack has a positive price (currently " + PackTypes.get("stickerPack").price + ")");
    r.eq(PackTypes.get("stickerPack").kind, "sticker", "sticker pack kind");
    r.eq(PackTypes.get("stickerPack").label, "Small Sticker Pack", "the 3-sticker pack is now named Small Sticker Pack");
    // LARGE sticker pack (new) — keep 2 rides the existing keep>1 sticker loop.
    r.eq(PackTypes.get("largeStickerPack").kind, "sticker", "the large sticker pack is a STICKER pack");
    r.eq(PackTypes.get("largeStickerPack").size, 5, "the LARGE sticker pack reveals 5");
    r.eq(PackTypes.get("largeStickerPack").keep, 2, "the LARGE sticker pack keeps 2 (PACKS1 feature contract)");
    r.ok(PackTypes.get("largeStickerPack").price > 0, "the large sticker pack has a positive price (currently " + PackTypes.get("largeStickerPack").price + ")");
    r.eq(PackTypes.get("largeStickerPack").label, "Large Sticker Pack", "the 5-sticker pack is named Large Sticker Pack");
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
  // (on a NON-PINKY deck: JOKER3 removes Pinky Regular's random Joker half,
  // which would halve the special rate asserted below)
  {
    const c = CampaignState.create();
    c.setDeck("mamma");
    c.reset();
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
      // STORE cards roll ALL FOUR suits by design (stage gating is a MAP-only
      // rule now) — just sanity-check the rolled suit is a real suit.
      const firstChange = (card.modifications || []).find(m => m.op === "changeSuit");
      if (!["\u2666", "\u2665", "\u2663", "\u2660"].includes(firstChange ? firstChange.from : card.suit)) allInPlay = false;
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
    r.ok(allInPlay, "generated card ROLLED suits are always real suits (full-suit store, never stage-gated)");
    r.ok(allValidRank, "generated card ranks stay 2–A even after rank stickers");
    r.ok(allStickersReal, "generated card stickers are all real");
    // v6.73 odds — ONE distribution for every pack: 20% one / 4% two / 1%
    // three → ≈25% ≥1, ≈5% ≥2, ≈1% ≥3 (75% ride bare).
    // (A rank sticker that lands on an at-boundary card doesn't attach, so observed
    //  rates run a touch under nominal; bounds are kept generous for that.)
    const pAny = withAny / normal, pTwo = withTwo / normal, pThree = withThree / normal;
    r.ok(pAny > 0.20 && pAny < 0.30, "≈25% of cards carry ≥1 sticker (got " + pAny.toFixed(3) + ")");
    r.ok(pTwo > 0.02 && pTwo < 0.09, "≈5% of cards carry ≥2 stickers (got " + pTwo.toFixed(3) + ")");
    r.ok(pThree > 0.002 && pThree < 0.030, "≈1% of cards carry ≥3 stickers (got " + pThree.toFixed(3) + ")");
  }

  // --- Stage never gates STORE pack suits (map-only rule) ---------------
  {
    const c = CampaignState.create();
    c.advancePhase();   // → Stage 2 — store rolls are unaffected by the stage
    r.eq(c.currentStage, 2, "advanced to Stage 2");
    const suits = new Set(["♦", "♥", "♣", "♠"]);
    const cards = c.revealPack("cardPack", rngFrom(9));
    r.ok(cards.every(card => (card.joker || card.blank) || suits.has(card.suit)), "Stage-2 store pack cards roll any real suit (♠ included — store is never stage-gated)");
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

  // --- Large CARD pack keep>1: taking `keep` revealed cards grows the tray
  //     by `keep`. The reveal/pick UI (confirmPackPick) loops every chosen
  //     card into the tray; the engine path this rides is addPackCard. Read
  //     the keep count LIVE — a large pack is defined by keeping >1.
  {
    const c = CampaignState.create();
    const keep = PackTypes.get("cardPack").keep;
    r.ok(keep >= 2, "large card pack keep is >1 (the whole point of PACKS1; got " + keep + ")");
    const revealed = c.revealPack("cardPack", rngFrom(21));
    const before = c.packTrayCount();
    // Mirror confirmPackPick's card branch: add EVERY chosen card to the tray.
    const picks = revealed.slice(0, keep);
    picks.forEach(card => r.ok(c.addPackCard(card).ok, "kept card added to tray (cap Infinity, never full)"));
    r.eq(c.packTrayCount(), before + keep, "picking `keep` (" + keep + ") cards grows the tray by `keep`");
    // Both kept identities are distinct and present in the tray.
    const trayIds = new Set(c.getPackTray().map(x => x.id));
    r.ok(picks.every(p => trayIds.has(p.id)), "every kept card is in the tray (none discarded)");
    // Serialize/restore: BOTH kept tray cards survive the round-trip.
    const snap = JSON.parse(JSON.stringify(c.serialize()));
    r.eq(snap.packTray.length, before + keep, "snapshot carries all " + (before + keep) + " tray cards");
    const c2 = CampaignState.create();
    r.ok(c2.restore(snap), "restore accepts a multi-card tray snapshot");
    r.eq(c2.packTrayCount(), before + keep, "restored tray keeps every kept card");
    const restoredIds = new Set(c2.getPackTray().map(x => x.id));
    r.ok(picks.every(p => restoredIds.has(p.id)), "both kept card identities round-trip");
  }

  // --- Large STICKER pack keep>1: reveals `size`, keeping `keep` lands them
  //     all in the sticker inventory (rides the existing keep>1 sticker loop,
  //     no engine change). All values read LIVE from the registry.
  {
    const c = CampaignState.create();
    const t = PackTypes.get("largeStickerPack");
    const ids = c.revealPack("largeStickerPack", rngFrom(22));
    r.eq(ids.length, t.size, "the large sticker pack reveals `size` (" + t.size + ") stickers");
    r.ok(ids.every(id => stickerIds.has(id)), "all revealed stickers are real");
    // Total inventory across the whole sticker registry, so duplicate rolled
    // ids in the kept slice still count once per copy.
    const totalInv = () => [...stickerIds].reduce((n, id) => n + c.inventoryCount(id), 0);
    const before = totalInv();
    ids.slice(0, t.keep).forEach(id => r.ok(c.addStickerToInventory(id), "kept sticker lands in inventory"));
    r.eq(totalInv() - before, t.keep, "keeping `keep` (" + t.keep + ") stickers adds exactly that many to inventory");
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
    // A fresh deck holds the 52 base identities, PLUS any duplicates map
    // generation minted for over-drafted +1 nodes — replacement must keep
    // whatever size it started at.
    const base = c.getCards().length;
    r.ok(base >= 52, "deck starts at the 52 identities (+" + (base - 52) + " map-minted)");
    const ret = c.replaceDeckCard(dealt.id, 0);
    r.ok(ret && ret.id === pick.id, "replaceDeckCard returns the inserted pack card");
    r.eq(c.getCards().length, base, "deck size unchanged by replacement");
    r.ok(!c.getCards().some(x => x.id === dealt.id), "the replaced card (and its stickers) is gone forever");
    r.ok(c.getCards().some(x => x.id === pick.id), "the pack card is now a deck card");
    r.eq(c.packTrayCount(), 0, "the used pack card left the tray");

    const c2 = CampaignState.create();
    r.ok(c2.restore(JSON.parse(JSON.stringify(c.serialize()))), "save/restore accepts the post-replace deck");
    r.eq(c2.getCards().length, base, "restored deck keeps its size");
    r.ok(c2.getCards().some(x => x.id === pick.id), "the replacement persists across save/restore");
    r.ok(!c.replaceDeckCard(99999, 0), "replacing an unknown card id fails safely");
  }

  // ===== Phase 4: suit-locking across stages =============================
  {
    const c = CampaignState.create();
    const stages = [
      { advances: 0 },
      { advances: 1 },
      { advances: 2 },
    ];
    let fresh = CampaignState.create();
    let totalAdv = 0;
    for (const st of stages) {
      while (totalAdv < st.advances) { fresh.advancePhase(); totalAdv++; }
      // STORE cards/packs are FULL-SUIT by design (stage suit-gating applies
      // only to MAP pickups/packs): every stage's rolls span all four suits.
      const seen = new Set();
      let stickersReal = true;
      for (let i = 0; i < 200; i++) {
        const card = fresh.genPackCard(rngFrom(1000 + i));
        if (card.joker || card.blank) continue;                 // special options carry no suit
        const firstChange = (card.modifications || []).find(m => m.op === "changeSuit");
        seen.add(firstChange ? firstChange.from : card.suit);
        if (!card.stickers.every(s => !!StickerTypes.get(s.type))) stickersReal = false;
      }
      const ids = fresh.revealPack("stickerPack", rngFrom(2000 + st.advances));
      if (!ids.every(id => !!StickerTypes.get(id))) stickersReal = false;
      r.eq(seen.size, 4, "Stage " + fresh.currentStage + ": store pack cards roll ALL FOUR suits (never stage-gated)");
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
