// CLASS-FIRST STORE ROLL (items.js store.classWeights) + the INDIVIDUAL-CARD
// class: each of the 5 rolled slots picks its CLASS first (sticker 50 /
// pillar 17 / base 10 / pack 10 / card 10 / samepower 3 by default), then an
// item within the class by rarity. Card slots carry a real generated card at
// pack odds — never a Removal card, Jokers at 1/53 priced separately and
// gated by the tier's held-count cap. Max 3 per class; Removal slot 6 fixed.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { CampaignState, ItemData, PackTypes } = loadGame();
  const r = makeRunner("store-class.test.mjs");
  const CW = ItemData.store.classWeights;
  const CLASSES = ["sticker", "pillar", "base", "pack", "card", "samepower"];

  r.ok(CLASSES.every(k => typeof CW[k] === "number" && CW[k] >= 0),
    "classWeights read live from items.js (" + CLASSES.map(k => k + ":" + CW[k]).join(" ") + ")");
  r.ok(typeof ItemData.store.card.price === "number" && typeof ItemData.store.card.jokerPrice === "number",
    "store.card price/jokerPrice read live (" + ItemData.store.card.price + " / " + ItemData.store.card.jokerPrice + ")");

  // --- distribution sweep: many visits, count classes per rolled slot ------
  {
    const c = CampaignState.create();
    c.reset();
    c.openStore(Math.random);
    c.addCoins(1000000);
    const counts = { sticker: 0, pillar: 0, base: 0, pack: 0, card: 0, samepower: 0 };
    let slots = 0, overCap = 0, blanks = 0, removalLast = 0, visits = 0;
    for (let v = 0; v < 300; v++) {
      if (!c.rerollStore()) break;
      visits++;
      const offer = c.getStoreOffer();
      const per = {};
      offer.slots.forEach((s, i) => {
        if (!s) return;
        if (i === offer.slots.length - 1 && s.kind === "removal") { removalLast++; return; }
        counts[s.kind] = (counts[s.kind] || 0) + 1;
        // the cap buckets packs by FAMILY (card packs vs sticker packs), so
        // 2+2 across the families is a legal 4 "pack"-kind slots — count the
        // cap the same way the engine does.
        const capKey = s.kind === "pack" ? (PackTypes.get(s.id).kind === "card" ? "cardpack" : "stickerpack") : s.kind;
        per[capKey] = (per[capKey] || 0) + 1;
        slots++;
        if (s.kind === "card") {
          if (!s.card || s.card.blank) blanks++;
        }
      });
      for (const k in per) if (per[k] > 3) overCap++;
    }
    r.ok(visits >= 250, "swept " + visits + " store visits (" + slots + " rolled slots)");
    r.eq(removalLast, visits, "slot 6 is ALWAYS the fixed Removal slot");
    r.eq(overCap, 0, "no class ever exceeds 3 slots per visit");
    r.eq(blanks, 0, "card slots always carry a real card — never a Removal/Blank");
    const total = CLASSES.reduce((a, k) => a + CW[k], 0);
    for (const k of CLASSES) {
      const expected = CW[k] / total;
      const got = counts[k] / slots;
      // the sticker cap redistributes a few points (50% raw → ~46%), so the
      // sticker bound is wider; ±6pp elsewhere absorbs sampling noise.
      const tol = k === "sticker" ? 0.085 : 0.06;
      r.ok(Math.abs(got - expected) < tol,
        k + " ≈ " + Math.round(expected * 100) + "% of slots (observed " + (got * 100).toFixed(1) + "%)");
    }
  }

  // --- card slots: pack-odds cards, priced from items.js -------------------
  {
    const c = CampaignState.create();
    c.reset();
    c.openStore(Math.random);
    c.addCoins(1000000);
    let found = null, foundSlot = -1;
    for (let v = 0; v < 100 && !found; v++) {
      c.rerollStore();
      const offer = c.getStoreOffer();
      // a NORMAL card slot only — a rolled shelf Joker would price at jokerPrice
      // and already hold a reserved slot, breaking the assertions below.
      offer.slots.forEach((s, i) => { if (!found && s && s.kind === "card" && s.card && !s.card.joker) { found = s; foundSlot = i; } });
    }
    r.ok(!!found, "card slots appear on real shelves");
    r.eq(c.priceOfMixed(foundSlot), ItemData.store.card.price, "a normal card slot costs store.card.price");
    // inject a Joker card into the live offer → jokerPrice + held-count reservation
    const offer = c.getStoreOffer();
    const before = c.jokerBudget().committed;
    offer.slots[foundSlot] = { kind: "card", id: "card", card: { id: 99999, joker: true, suit: "★", originalRank: 0, currentRank: 0, modifications: [], stickers: [], compoundHits: 0 } };
    r.eq(c.priceOfMixed(foundSlot), ItemData.store.card.jokerPrice, "a Joker card slot costs store.card.jokerPrice");
    r.eq(c.jokerBudget().committed, before + 1, "an unbought shelf Joker reserves a held slot (cap-safe)");
    // buying it: charges the joker price, trays the exact card, empties the slot
    const coins0 = c.getCoins();
    const trayLen0 = c.getPackTray().length;
    const res = c.buyMixedSlot(foundSlot, Math.random);
    r.ok(res.ok && res.kind === "card" && res.card && res.card.joker, "buying a card slot returns { kind: 'card' } with the exact card");
    r.eq(coins0 - c.getCoins(), ItemData.store.card.jokerPrice, "…charging the Joker price");
    r.eq(c.getPackTray().length, trayLen0 + 1, "…and the card lands in the pack tray (swap/place flow)");
    r.eq(c.getStoreOffer().slots[foundSlot], null, "…and the slot empties");
  }

  // --- genStoreCard: joker at the 1/53 any-card rate, cap-gated ------------
  {
    const seq = (vals) => { let i = 0; return () => (i < vals.length ? vals[i++] : 0.5); };
    const reg = CampaignState.create();
    reg.setTier("regular");
    reg.reset();
    // Regular holds the guaranteed map Joker (1 of cap 2) → one slot open.
    const j = reg.genStoreCard(seq([0.001, 0.4]));
    r.ok(j.joker, "regular below cap: a store-card special roll mints a Joker");
    const n = reg.genStoreCard(seq([0.5, 0.4, 0.9]));
    r.ok(!n.joker && !n.blank && n.suit, "a non-special roll mints a normal suited card");
    const leg = CampaignState.create();
    leg.setTier("legendary");
    leg.reset();
    const lj = leg.genStoreCard(seq([0.001, 0.4]));
    r.ok(!lj.joker && !lj.blank, "legendary: the same roll falls through to a normal card (cap 0)");
  }

  // --- store cards/packs are FULL-SUIT — never stage-gated ----------------
  {
    const c = CampaignState.create();
    c.reset();   // Pinky stage 1: only ♥ + ♦ are in play on the MAP…
    const seen = {};
    for (let i = 0; i < 400; i++) { const card = c.genStoreCard(Math.random); if (card.suit && !card.joker && !card.blank) seen[card.suit] = (seen[card.suit] || 0) + 1; }
    for (let i = 0; i < 400; i++) { const card = c.genPackCard(Math.random); if (card.suit && !card.joker && !card.blank) seen[card.suit] = (seen[card.suit] || 0) + 1; }
    r.eq(Object.keys(seen).length, 4, "…but STORE cards + pack cards draw all four suits (" + JSON.stringify(seen) + ")");
    r.ok(Object.values(seen).every(n => n > 110), "…roughly equally (~200 each of 800)");
    // (map pickups/packs staying ♦-gated for Pinky is asserted in deck-rules)
  }

  // --- Lammy: card-slot cards never mint stickers --------------------------
  {
    const c = CampaignState.create();
    c.setDeck("lammy");
    c.reset();
    let stickered = 0;
    for (let i = 0; i < 60; i++) { const card = c.genStoreCard(Math.random); if (card.stickers && card.stickers.length) stickered++; }
    r.eq(stickered, 0, "Lammy (noStickers): store-slot cards never carry stickers");
  }

  return r.summary();
}
