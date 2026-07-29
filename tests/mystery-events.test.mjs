// MYST1 — mystery "?" node events (Stage 1: data + DOM-free core).
//  - items.js `mystery` config validates fail-loudly; cursed stickers parse.
//  - rollMysteryEvent(nodeId) is a pure seeded weighted roll (same seed+node
//    → same key); applyMysteryEvent performs the outcome's state mutation.
//  - Cursed stickers are excluded from EVERY normal grant pool (store offers,
//    sticker packs, pack-card generation, Mr. Smith's grants) yet stay
//    gettable by id and applicable.
//  - Engine: tributeCoin stickers and innately cursed cards pay a negative
//    "sticker-coins" tribute on landing (Bury 2's exact shape).
// RULES only — every expected number is read from ItemData, never pinned.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadGame, makeRunner } from "./_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const ITEMS_SRC = readFileSync(join(HERE, "..", "items.js"), "utf8");

/** mulberry32 — the same deterministic rng idiom joker-blank pins rolls with. */
function mulberry(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function run() {
  const { GameEngine, DeckManager, CampaignState, StickerTypes, ItemData } = loadGame();
  const r = makeRunner("mystery-events.test.mjs");
  const M = ItemData.mystery;
  const CURSED_IDS = ItemData.stickers.filter(t => t.cursed === true).map(t => t.id);
  const isCursed = (id) => { const t = StickerTypes.get(id); return !!(t && t.cursed); };

  // ── data: the mystery config section ──────────────────────────────────────
  r.ok(M && typeof M === "object", "items.js has a mystery config section");
  const wKeys = Object.keys(M.weights || {});
  r.ok(wKeys.length >= 9, "the weights table carries every outcome key (" + wKeys.length + ")");
  r.ok(wKeys.every(k => typeof M.weights[k] === "number" && isFinite(M.weights[k]) && M.weights[k] > 0),
    "every outcome weight is a positive number");
  r.ok(Array.isArray(M.coinRangeByStage) && M.coinRangeByStage.length > 0
    && M.coinRangeByStage.every(p => Array.isArray(p) && p.length === 2
      && typeof p[0] === "number" && typeof p[1] === "number" && p[0] >= 0 && p[1] >= p[0]),
    "coinRangeByStage is a non-empty array of well-formed [min,max] pairs");
  r.ok(["cards", "piles", "bounty"].every(k => typeof M.ambush[k] === "number" && M.ambush[k] > 0),
    "the ambush deal knobs (cards/piles/bounty) are positive numbers");
  r.ok(typeof M.cursedCardTribute === "number" && M.cursedCardTribute > 0,
    "cursedCardTribute is a positive number");
  r.ok(Array.isArray(M.cursedCardRankRange) && M.cursedCardRankRange.length === 2
    && M.cursedCardRankRange[0] >= 2 && M.cursedCardRankRange[1] <= 14
    && M.cursedCardRankRange[0] <= M.cursedCardRankRange[1],
    "cursedCardRankRange is a well-formed [min,max] rank pair");

  // ── data: the cursed stickers ─────────────────────────────────────────────
  r.ok(CURSED_IDS.length >= 2, "at least two cursed sticker entries exist (" + CURSED_IDS.join(", ") + ")");
  r.ok(ItemData.stickers.filter(t => t.cursed).every(t =>
      t.kind === "behavior" && t.behavior === "tributeCoin" && t.price === 0
      && typeof t.value === "number" && t.value > 0),
    "cursed stickers are price-0 tributeCoin behaviors with a positive value knob");
  r.ok(CURSED_IDS.every(id => !!StickerTypes.get(id)), "cursed stickers stay gettable by id");

  // ── validator: a malformed mystery section fails loudly on load ───────────
  {
    let threw = null;
    try { loadGame({ itemsSource: ITEMS_SRC.replace("coinBonus: 20,", "coinBonus: -1,") }); }
    catch (e) { threw = e; }
    r.ok(threw && /items\.js validation FAILED/.test(threw.message), "a negative outcome weight throws on load");
  }
  {
    let threw = null;
    try { loadGame({ itemsSource: ITEMS_SRC.replace("mystery: {", "mysteryGone: {") }); }
    catch (e) { threw = e; }
    r.ok(threw && /items\.js validation FAILED/.test(threw.message), "a missing mystery section throws on load");
  }

  // ── rollMysteryEvent: deterministic + covers every outcome ────────────────
  {
    // Two campaigns restored from the SAME snapshot share runSeed → same rolls.
    const c1 = CampaignState.create();
    const snap = JSON.parse(JSON.stringify(c1.serialize()));
    const c2 = CampaignState.create();
    c2.restore(snap);
    const probeIds = [0, 3, 17, 42, 105, 999];
    r.ok(probeIds.every(id => c1.rollMysteryEvent(id) === c2.rollMysteryEvent(id)),
      "same seed + node → same outcome key across two campaigns");
    r.ok(probeIds.every(id => c1.rollMysteryEvent(id) === c1.rollMysteryEvent(id)),
      "the roll is pure (repeated calls agree, no state consumed)");
    const seen = new Set();
    for (let id = 0; id < 600; id++) seen.add(c1.rollMysteryEvent(id));
    r.ok(wKeys.every(k => seen.has(k)),
      "a node-id sweep covers every weighted outcome (" + seen.size + "/" + wKeys.length + ")");
    r.ok([...seen].every(k => wKeys.indexOf(k) !== -1), "every rolled key is a configured outcome");
  }

  // ── cursed stickers never enter the grant pools ───────────────────────────
  {
    r.ok(StickerTypes.grantable().every(t => !t.cursed), "StickerTypes.grantable() excludes cursed types");
    r.eq(StickerTypes.grantable().length, StickerTypes.all().length - CURSED_IDS.length,
      "grantable() is exactly all() minus the cursed entries");
  }
  {
    // Store offers: fresh visits (seeded) + rerolls (Math.random path shares
    // the same rollUnifiedSlots pool).
    const c = CampaignState.create();
    let stickerSlots = 0, bad = 0;
    for (let i = 0; i < 250; i++) {
      const offer = c.openStore(mulberry(1000 + i));
      for (const s of offer.slots) if (s && s.kind === "sticker") { stickerSlots++; if (isCursed(s.id)) bad++; }
    }
    c.addCoins(100000);
    for (let i = 0; i < 150; i++) {
      c.rerollStore();
      for (const s of c.getStoreOffer().slots) if (s && s.kind === "sticker") { stickerSlots++; if (isCursed(s.id)) bad++; }
    }
    r.ok(stickerSlots > 200, "the store-offer sweep rolled plenty of sticker slots (" + stickerSlots + ")");
    r.eq(bad, 0, "no store sticker slot is ever a cursed sticker");
  }
  {
    // Sticker packs (both sizes) roll through stickerPoolForSuits → grantable.
    const c = CampaignState.create();
    let rolled = 0, bad = 0;
    for (const packId of ["stickerPack", "largeStickerPack"]) {
      for (let i = 0; i < 400; i++)
        for (const id of c.revealPack(packId, mulberry(5000 + i))) { rolled++; if (isCursed(id)) bad++; }
    }
    r.ok(rolled > 1000, "the pack sweep rolled plenty of stickers (" + rolled + ")");
    r.eq(bad, 0, "no sticker-pack roll is ever a cursed sticker");
  }
  {
    // Pack-CARD generation (genPackCard/genStoreCard → genNormalCard's sticker
    // rolls): generated cards never carry a cursed sticker.
    const c = CampaignState.create();
    let stickered = 0, bad = 0;
    const rng = mulberry(777);
    for (let i = 0; i < 4000; i++) {
      const card = c.genPackCard(rng);
      for (const s of card.stickers || []) { stickered++; if (isCursed(s.type)) bad++; }
    }
    r.ok(stickered > 500, "the pack-card sweep generated plenty of stickers (" + stickered + ")");
    r.eq(bad, 0, "no generated pack card ever carries a cursed sticker");
  }
  {
    // Mr. Smith (startStickers): start-card grants + map-grant rolls
    // (rollGrantStickers) never produce a cursed sticker.
    let stickered = 0, bad = 0;
    const scan = (cards) => { for (const card of cards) for (const s of card.stickers || []) { stickered++; if (isCursed(s.type)) bad++; } };
    for (let i = 0; i < 40; i++) {
      const c = CampaignState.create();
      c.setDeck("smith");
      c.reset();   // re-rolls one sticker per start card
      scan(c.getRunDeck());
    }
    // Map grants: resolve every +1 node of a Smith run.
    const c = CampaignState.create();
    c.setDeck("smith");
    c.reset();
    for (const n of c.getMap().nodes.filter(n => n.type === "pickup")) {
      const card = c.resolvePickup(n);
      if (card) scan([card]);
    }
    r.ok(stickered > 400, "the Mr. Smith sweep granted plenty of stickers (" + stickered + ")");
    r.eq(bad, 0, "Mr. Smith's grants (start cards + map pickups) are never cursed stickers");
  }

  // ── applyMysteryEvent: coin outcomes ──────────────────────────────────────
  {
    const c = CampaignState.create();   // fresh campaign: phase 0 → stage-0 range
    const range = M.coinRangeByStage[0];
    const before = c.getCoins();
    const d = c.applyMysteryEvent("coinBonus", 11);
    r.ok(d && d.key === "coinBonus" && typeof d.amount === "number", "coinBonus returns an amount descriptor");
    r.eq(c.getCoins() - before, d.amount, "coinBonus adds exactly the descriptor amount");
    r.ok(d.amount >= range[0] && d.amount <= range[1],
      "the bonus amount lies inside the stage-0 range [" + range[0] + "," + range[1] + "] (got " + d.amount + ")");
  }
  {
    // Same seed + node → same amount across two campaigns.
    const c1 = CampaignState.create();
    const snap = JSON.parse(JSON.stringify(c1.serialize()));
    const c2 = CampaignState.create();
    c2.restore(snap);
    const d1 = c1.applyMysteryEvent("coinBonus", 23);
    const d2 = c2.applyMysteryEvent("coinBonus", 23);
    r.ok(d1 && d2 && d1.amount === d2.amount, "the coin amount is deterministic per (seed, node)");
  }
  {
    const c = CampaignState.create();
    c.addCoins(1000);
    const range = M.coinRangeByStage[0];
    const d = c.applyMysteryEvent("coinLoss", 12);
    const loss = 1000 - c.getCoins();
    r.ok(d && d.key === "coinLoss" && loss === d.amount, "coinLoss deducts exactly the descriptor amount");
    r.ok(d.amount >= range[0] && d.amount <= range[1],
      "the loss amount lies inside the stage-0 range (got " + d.amount + ")");
    const broke = CampaignState.create();   // 0 coins → floored, never negative
    const d0 = broke.applyMysteryEvent("coinLoss", 12);
    r.eq(broke.getCoins(), 0, "coinLoss floors at 0 (never a negative balance)");
    r.eq(d0.amount, 0, "…and the descriptor reports the floored amount");
  }

  // ── applyMysteryEvent: stickerPack / cardPack ─────────────────────────────
  {
    const c = CampaignState.create();
    const d = c.applyMysteryEvent("stickerPack", 13);
    r.ok(d && d.stickerId && StickerTypes.get(d.stickerId), "stickerPack grants a real sticker id");
    r.ok(!isCursed(d.stickerId), "stickerPack never grants a cursed sticker");
    r.eq(c.inventoryCount(d.stickerId), 1, "the granted sticker lands in the inventory");
    r.ok(typeof d.stickerLabel === "string" && d.stickerLabel.length > 0, "the descriptor names the sticker");
  }
  {
    const c = CampaignState.create();
    const sizeBefore = c.deckSize();
    const d = c.applyMysteryEvent("cardPack", 14);
    r.ok(d && d.card && d.cardId != null, "cardPack returns the minted card");
    r.eq(c.deckSize(), sizeBefore + 1, "cardPack grows the deck by exactly one");
    r.ok(c.getRunDeck().some(x => x.id === d.cardId), "the minted card is owned (dealt in the run deck)");
    r.ok(!d.card.cursed, "a cardPack card is never innately cursed");
  }

  // ── applyMysteryEvent: descriptor-only outcomes mutate nothing ────────────
  for (const key of ["freeRemoval", "stickerStrip", "ambush"]) {
    const c = CampaignState.create();
    const coins0 = c.getCoins(), size0 = c.deckSize();
    const d = c.applyMysteryEvent(key, 15);
    r.ok(d && d.key === key && typeof d.title === "string" && typeof d.desc === "string",
      key + " returns a titled descriptor");
    r.ok(c.getCoins() === coins0 && c.deckSize() === size0, key + " mutates no campaign state (descriptor only)");
  }
  {
    const c = CampaignState.create();
    const d = c.applyMysteryEvent("ambush", 16);
    r.ok(d.ambush && d.ambush.cards === M.ambush.cards && d.ambush.piles === M.ambush.piles
      && d.ambush.bounty === M.ambush.bounty, "the ambush descriptor carries the items.js deal knobs");
    r.eq(c.applyMysteryEvent("nonsense", 17), null, "an unknown outcome key resolves to null");
  }

  // ── applyMysteryEvent: curses ─────────────────────────────────────────────
  {
    const c = CampaignState.create();
    const d = c.applyMysteryEvent("cursedSticker", 18);
    r.ok(d && d.stickerId && isCursed(d.stickerId), "cursedSticker picks a cursed sticker type");
    r.ok(c.getRunDeck().some(x => x.id === d.cardId), "…applied to an OWNED card");
    r.ok(c.getCardById(d.cardId).stickers.some(s => s.type === d.stickerId),
      "…and the sticker really lands on that card");
  }
  {
    const c = CampaignState.create();
    const sizeBefore = c.deckSize();
    const d = c.applyMysteryEvent("cursedCard", 19);
    r.ok(d && d.card && d.card.cursed === true, "cursedCard mints a cursed:true card");
    r.ok(d.card.currentRank >= M.cursedCardRankRange[0] && d.card.currentRank <= M.cursedCardRankRange[1],
      "…at a rank inside items.js cursedCardRankRange (got " + d.card.currentRank + ")");
    r.eq(c.deckSize(), sizeBefore + 1, "…grown into the deck");
    r.ok(c.getRunDeck().some(x => x.id === d.cardId), "…owned immediately (appears in the run deck)");
    // serialize → restore round-trip: the cursed flag and ownership survive.
    const snap = JSON.parse(JSON.stringify(c.serialize()));
    const c2 = CampaignState.create();
    r.ok(c2.restore(snap), "the campaign with a cursed card restores");
    const restored = c2.getCardById(d.cardId);
    r.ok(restored && restored.cursed === true, "the cursed flag survives serialize → restore");
    r.ok(c2.getRunDeck().some(x => x.id === d.cardId), "…and the card is still owned after restore");
  }

  // ── removeRandomStickerFrom ───────────────────────────────────────────────
  {
    const c = CampaignState.create();
    const cardId = c.getRunDeck()[0].id;   // a ♥ start card
    c.addStickerToInventory("gainCoin");
    c.addStickerToInventory("wildSuit");
    c.applySticker(cardId, "gainCoin");
    c.applySticker(cardId, "wildSuit");
    r.eq(c.getCardById(cardId).stickers.length, 2, "fixture: the card carries two stickers");
    const removed = c.removeRandomStickerFrom(cardId, mulberry(31));
    r.ok(removed === "gainCoin" || removed === "wildSuit", "removeRandomStickerFrom returns the removed type id");
    r.eq(c.getCardById(cardId).stickers.length, 1, "…and removes EXACTLY one instance");
    r.ok(c.getCardById(cardId).stickers[0].type !== removed, "…leaving the other sticker intact");
    const cleanId = c.getRunDeck()[1].id;
    r.eq(c.removeRandomStickerFrom(cleanId, mulberry(32)), null, "null (no mutation) on a stickerless card");
  }

  // ── engine: tributeCoin sticker + innate curse pay on landing ─────────────
  const COLS = [3, 4, 3];
  const mkEngine = () => {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 9, { cols: COLS });
    e.start(); e.startRun();
    return e;
  };
  const landOn = (e, card) => {
    e.getBoard().top(0).value = 5;
    e.debug.setNextCardObj(card);
    e.guess(0, "higher");   // 7 > 5 → correct, the card lands
  };
  {
    const leech = StickerTypes.get(CURSED_IDS[0]);
    const e = mkEngine();
    let coinEvent = null;
    e.onEvent((t, p) => { if (t === "sticker-coins") coinEvent = p; });
    landOn(e, { id: 9101, label: "7", value: 7, suit: "♥", red: true,
                stickers: [{ type: leech.id }], suitGuards: {}, heartsRemaining: 0 });
    r.ok(e.getBoard().isActive(0), "the Leech carrier lands (pile survives)");
    r.eq(e.getRun().bonusCoins, -leech.value, "the bonus tally drops by the sticker's value knob");
    r.ok(coinEvent && coinEvent.amount === -leech.value && coinEvent.label === leech.label,
      "a negative sticker-coins event fires with the sticker's label");
  }
  {
    const e = mkEngine();
    let coinEvent = null;
    e.onEvent((t, p) => { if (t === "sticker-coins") coinEvent = p; });
    landOn(e, { id: 9102, label: "7", value: 7, suit: "♣", red: false, cursed: true,
                stickers: [], suitGuards: {}, heartsRemaining: 0 });
    r.ok(e.getBoard().isActive(0), "the innately cursed card lands (pile survives)");
    r.eq(e.getRun().bonusCoins, -M.cursedCardTribute, "the bonus tally drops by mystery.cursedCardTribute");
    r.ok(coinEvent && coinEvent.amount === -M.cursedCardTribute && coinEvent.label === "Cursed",
      "a negative sticker-coins event fires with the Cursed label");
  }
  {
    // control: an ordinary card pays nothing (the negative tallies above are
    // the tributes, not ambient landing noise).
    const e = mkEngine();
    landOn(e, { id: 9103, label: "7", value: 7, suit: "♦", red: true,
                stickers: [], suitGuards: {}, heartsRemaining: 0 });
    r.eq(e.getRun().bonusCoins, 0, "control: a plain landing moves no coins");
  }

  return r.summary();
}
