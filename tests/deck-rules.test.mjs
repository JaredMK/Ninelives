// Deck differentiation (DECK_RULES): Pinky unchanged; Mamma/Smith/Lammy share
// the alt-deck rules (random-suit 13-card start, unsegmented stages, all-suit
// pickups); Smith pays 2x and starts stickered; Lammy starts pre-equipped and
// can never use stickers. DOM-free over CampaignState + GameEngine.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const r = makeRunner("deck-rules.test.mjs");

  const fresh = (deck) => {
    const G = loadGame();
    const camp = G.CampaignState.create({ pileCount: 9 });
    if (deck) { camp.setDeck(deck); camp.reset(); }
    return { G, camp };
  };
  const startCards = (camp) => camp.getRunDeck();

  // ---- PINKY: completely unchanged (the baseline every existing test runs) --
  {
    const { G, camp } = fresh(null);
    const cards = startCards(camp);
    const startJ = G.DifficultyData.startJokers("pink", "regular");
    r.eq(camp.getDeckId(), "pink", "a fresh campaign defaults to Pinky");
    r.eq(cards.length, 13 + startJ, "Pinky starts with 13 + the tier's startJokers cards (" + (13 + startJ) + ")");
    r.eq(cards.filter(c => c.joker).length, startJ, "…exactly the data's startJokers count are Jokers");
    r.ok(cards.filter(c => !c.joker).every(c => c.suit === "♥"), "Pinky's other start cards are the 13 hearts");
    r.ok(cards.every(c => c.stickers.length === 0), "Pinky starts unstickered");
    r.eq(camp.getColumnPillars().filter(Boolean).length, 0, "Pinky starts with empty Pillar slots");
    r.eq(camp.priceOf("gainCoin"), G.StickerTypes.get("gainCoin").price, "Pinky pays list price");
    r.eq(camp.suitsInPlay().length, 2, "Pinky stage 1 has 2 suits in play (♥ + ♦)");
    // Master/Legendary carry no startJokers: the start deck stays the pure 13.
    for (const tier of ["master", "legendary"]) {
      camp.setTier(tier); camp.reset();
      const t = startCards(camp);
      r.eq(t.length, 13 + G.DifficultyData.startJokers("pink", tier),
        "Pinky " + tier + " starts at 13 + startJokers (" + (13 + G.DifficultyData.startJokers("pink", tier)) + ")");
      r.ok(t.every(c => !c.joker && c.suit === "♥"), "…pure hearts, no Jokers, on " + tier);
    }
    camp.setTier("regular"); camp.reset();   // leave the campaign as found
  }

  // ---- SHARED (Mamma): random-suit start, all suits, no extra modifier -----
  {
    const { G, camp } = fresh("mamma");
    const cards = startCards(camp);
    r.eq(cards.length, 13 + G.DifficultyData.startJokers("mamma", "regular"),
      "Mamma starts with 13 + her startJokers cards");
    const ranks = cards.map(c => c.currentRank).sort((a, b) => a - b).join(",");
    r.eq(ranks, "2,3,4,5,6,7,8,9,10,11,12,13,14", "Mamma holds one card of EVERY rank");
    r.eq(camp.suitsInPlay().length, 4, "Mamma has all four suits in play from the start");
    r.ok(cards.every(c => c.stickers.length === 0), "Mamma starts unstickered (shared rules only)");
    r.eq(camp.getColumnPillars().filter(Boolean).length, 0, "Mamma starts with empty slots");
    r.eq(camp.priceOf("gainCoin"), 2, "Mamma pays list price (gainCoin list = 2)");
    // Random suits: across 12 fresh rolls the start deck is essentially never
    // single-suit (odds (1/4)^12 per roll) — require at least one mixed roll
    // AND record suit variety across rolls.
    let mixed = 0; const seen = new Set();
    for (let k = 0; k < 12; k++) {
      camp.reset();
      const suits = new Set(startCards(camp).map(c => c.suit));
      suits.forEach(s => seen.add(s));
      if (suits.size > 1) mixed++;
    }
    r.ok(mixed >= 11, "Mamma's start suits are random (mixed in " + mixed + "/12 rolls)");
    r.eq(seen.size, 4, "all four suits appear across Mamma's start rolls");
  }

  // ---- SHARED: +1 map pickups roll ALL suits from stage 1 ------------------
  {
    const { camp } = fresh("mamma");
    camp._setMapSpecialRoll(() => null);   // no Joker/Removal — pure suit check
    // MYST3: ~1/4 of type-rolled nodes are first-class mysteries now, so one
    // run holds only a handful of pickups — union the locked suits across
    // several fresh runs (the RULE is "pickups roll all suits", unchanged).
    const suits = new Set();
    let pickups = 0;
    // Sweep until BOTH pins have enough evidence (suit span AND pickup count) —
    // exiting on suits.size alone could strand the pickups tally on a lucky
    // first run (a rare flake: 3 suits met by ~4 pickups).
    for (let k = 0; k < 8 && (suits.size < 3 || pickups < 6); k++) {
      camp.reset();
      const map = camp.getMap();
      map.nodes.filter(n => n.type === "pickup")
        .forEach(n => { pickups++; const c = camp.nodeCard(n); if (c && c.suit && !c.joker && !c.blank) suits.add(c.suit); });
    }
    r.ok(pickups >= 6, "the sweep met enough +1 pickups (" + pickups + ")");
    r.ok(suits.size >= 3, "Mamma's +1 pickups span suits across runs (" + [...suits].join(" ") + ")");
    // Pinky control: stage-0 (♦-phase) pickups lock only ♦ cards.
    {
      const { camp: pk } = fresh(null);
      pk._setMapSpecialRoll(() => null); pk.reset();
      const pkSuits = new Set();
      // (specials excluded like the Mamma sweep above — the per-tier GUARANTEED
      // map Joker may re-lock any one pickup, Pinky's included)
      pk.getMap().nodes.filter(n => n.type === "pickup" && n.phase === 0)
        .forEach(n => { const c = pk.nodeCard(n); if (c && c.suit && !c.joker && !c.blank) pkSuits.add(c.suit); });
      r.ok([...pkSuits].every(s => s === "♦"), "Pinky's stage-1 pickups stay all-♦ (unchanged)");
    }
    camp._setMapSpecialRoll(null);
    // Map packs: resolve a stage-0-suit pack node many times → multiple suits.
    const packSuits = new Set();
    for (let k = 0; k < 12; k++) {
      camp.reset(); camp._setMapSpecialRoll(() => null);
      const node = { packCount: 3, suit: "♦", phase: 0 };
      camp.resolvePack(node).forEach(c => { if (c && c.suit) packSuits.add(c.suit); });
      camp._setMapSpecialRoll(null);
    }
    r.ok(packSuits.size >= 3, "Mamma's map packs grant mixed suits (" + [...packSuits].join(" ") + ")");
    // Pinky control: the same ♦ pack node grants ONLY ♦.
    const { camp: pinky } = fresh(null);
    pinky._setMapSpecialRoll(() => null);
    const pinkySuits = new Set();
    pinky.resolvePack({ packCount: 3, suit: "♦", phase: 0 }).forEach(c => pinkySuits.add(c.suit));
    r.eq([...pinkySuits].join(""), "♦", "Pinky's ♦ pack node still grants only ♦ (unchanged)");
  }

  // ---- MR. SMITH: 2x prices + a random eligible sticker on every card ------
  {
    const { G, camp } = fresh("smith");
    const cards = startCards(camp);
    r.eq(cards.length, 13 + G.DifficultyData.startJokers("smith", "regular"),
      "Smith starts with 13 + his startJokers cards");
    r.ok(cards.every(c => c.stickers.length === 1), "every Smith start card carries exactly 1 sticker");
    r.eq(camp.priceOf("gainCoin"), 4, "Smith pays 2x for stickers (gainCoin list 2 → 4)");
    r.eq(camp.priceOfPillar("heartBounty"), 18, "Smith pays 2x for Pillars (9 → 18)");
    r.eq(camp.priceOfPack("cardPack"), 20, "Smith pays 2x for packs (10 → 20)");
    r.eq(camp.priceOfSamePower("linkBury"), 10, "Smith pays 2x for Same-Powers (5 → 10)");
    const baseRemoval = fresh(null).camp.removalPrice();   // Pinky base price, read live
    r.eq(camp.removalPrice(), baseRemoval * 2, "Smith pays 2x for Removal (" + baseRemoval + " → " + baseRemoval * 2 + ")");
    // The charge matches the doubled price (not the list price).
    camp.addCoins(100);
    const before = camp.getCoins();
    r.ok(camp.buySticker("gainCoin"), "Smith can buy at the doubled price");
    r.eq(before - camp.getCoins(), 4, "the purchase charged the DOUBLED price");
  }
  // Smith's start stickers respect a runtime `suits` restriction.
  {
    const G = loadGame();
    for (const t of G.StickerTypes.all()) t.suits = ["♥"];   // everything ♥-only
    const camp = G.CampaignState.create({ pileCount: 9 });
    camp.setDeck("smith"); camp.reset();
    let cards = startCards(camp);
    // Smith's 13 start suits are random — a 0-heart start (~2% of rolls) has
    // nothing to assert on; re-roll until at least one heart shows.
    for (let tries = 0; tries < 20 && !cards.some(c => c.suit === "\u2665"); tries++) {
      camp.reset(); cards = startCards(camp);
    }
    const bad = cards.filter(c => c.suit !== "♥" && c.stickers.length > 0
      && !(c.modifications || []).some(m => m.op === "changeSuit"));
    r.eq(bad.length, 0, "with every sticker ♥-only, Smith's never-♥ start cards roll NO sticker");
    const hearts = cards.filter(c => c.suit === "♥" || (c.modifications || []).some(m => m.op === "changeSuit"));
    r.ok(hearts.every(c => c.stickers.length === 1) && hearts.length > 0,
      "…while his ♥ start cards still roll one (" + hearts.length + " hearts)");
  }

  // ---- LAMMY: pre-equipped slots + stickers unusable everywhere ------------
  {
    const { G, camp } = fresh("lammy");
    const pillars = camp.getColumnPillars(), bases = camp.getColumnBases();
    r.eq(pillars.filter(Boolean).length, 3, "Lammy starts with 3 Pillars equipped");
    r.eq(bases.filter(Boolean).length, 3, "Lammy starts with 3 Bases equipped");
    r.eq(new Set(pillars).size, 3, "…the 3 Pillars are distinct");
    r.eq(new Set(bases).size, 3, "…the 3 Bases are distinct");
    r.ok(pillars.every(id => G.PillarTypes.get(id)), "the Pillars are real registry entries");
    r.ok(!bases.includes("randomSticker") && !bases.includes("stickerHarvest"),
      "the sticker-centric Bases never pre-equip for Lammy");
    // Stickers unusable: the campaign gate refuses every card × type.
    const card = startCards(camp)[0];
    r.ok(G.StickerTypes.ids.every(id => !camp.canApplySticker(card, id)),
      "Lammy: canApplySticker refuses every sticker type");
    // Store: a sticker slot can't be bought even with coins.
    camp.addCoins(500);
    let seed = 11;
    const rng = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; };
    let stickerChecked = false, packChecked = false, sawSticker = false;
    for (let guard = 0; guard < 300 && !(stickerChecked && packChecked); guard++) {
      const offer = camp.openStore(rng);
      offer.slots.forEach((s, i) => {
        if (s && s.kind === "sticker" && !stickerChecked) {
          sawSticker = true;
          r.ok(!camp.buyOfferedSticker(i), "Lammy: sticker purchase refused");
          r.ok(camp.getStoreOffer().slots[i] && camp.getStoreOffer().slots[i].kind === "sticker",
            "…the refused sticker stays on the shelf (normal roll ratio)");
          stickerChecked = true;
        }
        if (s && s.kind === "pack" && s.id === "stickerPack" && !packChecked) {
          r.ok(!camp.buyMixedSlot(i).ok, "Lammy: sticker-PACK purchase refused");
          packChecked = true;
        }
      });
    }
    r.ok(stickerChecked && packChecked, "store rolls offered both a sticker and a sticker pack to test");
    // Card packs mint NO stickered cards for Lammy.
    let stickered = 0;
    for (let k = 0; k < 200; k++) { const c = camp.genPackCard(rng); if (c.stickers && c.stickers.length) stickered++; }
    r.eq(stickered, 0, "Lammy's card packs mint no stickered cards (200 rolls)");
  }
  // Lammy in-run: no effect may sticker his cards (engine noStickers).
  {
    const { G } = fresh(null);
    const e = G.GameEngine.create(G.DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3], noStickers: true });
    e.start(); e.startRun([null, null, null], ["randomSticker", null, null]);
    r.ok(!e.baseAvailable(0), "noStickers: the Wild Sticker Base is never available");
    r.eq(e.debug.applyStickerToNext("gainCoin"), null, "noStickers: even the debug sticker-on-next-draw refuses");
  }

  // ---- persistence: the deck travels with the save --------------------------
  {
    const { G, camp } = fresh("smith");
    const snap = camp.serialize();
    r.eq(snap.deckId, "smith", "serialize() carries the deck id");
    const camp2 = G.CampaignState.create({ pileCount: 9 });
    r.ok(camp2.restore(snap), "a Smith save restores");
    r.eq(camp2.getDeckId(), "smith", "…and the restored campaign keeps Smith's rules");
    r.eq(camp2.priceOf("gainCoin"), 4, "…including 2x pricing");
    const legacy = camp.serialize(); delete legacy.deckId;
    const camp3 = G.CampaignState.create({ pileCount: 9 });
    camp3.restore(legacy);
    r.eq(camp3.getDeckId(), "pink", "a pre-deck-rules save restores as a Pinky campaign");
  }

  return r.summary();
}
