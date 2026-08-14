// BALANCE BATCH v6.51 — the web-side contract:
//   (a) FREEBIE-BUG GUARD: every store item bought through the FULL path
//       (injected slot → priceOfMixed → buyMixedSlot / buyOfferedSticker)
//       deducts EXACTLY its items.js def price — no freebies, no overcharges.
//   (b) MYSTERY SAME-POWER slot: id-less { kind:"samepower", mystery:true },
//       at most one per shelf, fixed store.mysterySamePower price, buy-time
//       reveal roll (ONE uniform draw over unlocked-and-unequipped powers),
//       KEEP equips (displaced returns to inventory), DISCARD destroys
//       without refund, legacy concrete slots still buy from their def.
//   (c) DEMOLISH: destroys ITS OWN column's Pillar (no target pick),
//       unavailable without one there, peeks == def peekCount.
//   (d) CLUB ORACLE (clubTell): a Tell-style hint for EVERY ♣-topped alive
//       pile in its column, ascending pile order, vs deck peek(1) — no rng.
// Engine + campaign are DOM-free, so we drive them directly.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadGame, makeRunner } from "./_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

export function run() {
  const { GameEngine, DeckManager, CampaignState,
    StickerTypes, PillarTypes, BaseTypes, PackTypes, SamePowerTypes, ItemData } = loadGame();
  const r = makeRunner("balance-v651.test.mjs");

  const deck = () => DeckManager.buildStandardDeck();
  const COLS = [3, 4, 3];   // col 0 = piles 0-2, col 1 = piles 3-6, col 2 = piles 7-9
  const game = (bases, pillars) => {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start();
    e.startRun(pillars || [null, null, null], bases);
    return e;
  };

  // ── (a) the freebie-bug guard: EVERY item's full buy path charges its def ──
  {
    // Stickers buy through buyOfferedSticker (place-then-pay UI rides on it).
    for (const t of StickerTypes.grantable()) {   // the sellable pool (cursed never sell)
      const c = CampaignState.create();
      c.addCoins(1000);
      c.openStore();
      c.getStoreOffer().slots[0] = { kind: "sticker", id: t.id };
      r.eq(c.priceOfMixed(0), t.price, "sticker slot prices " + t.id + " at its def (" + t.price + ")");
      const before = c.getCoins();
      r.ok(c.buyOfferedSticker(0), "bought " + t.id + " through the offered-sticker path");
      r.eq(c.getCoins(), before - t.price, "…deducting exactly its def price");
      r.eq(c.getStoreOffer().slots[0], null, "…emptying the slot");
    }
    // Pillars / bases / packs / legacy concrete same-powers buy through buyMixedSlot.
    const mixed = [
      ...PillarTypes.all().map(t => ({ kind: "pillar", id: t.id, price: t.price })),
      ...BaseTypes.all().map(t => ({ kind: "base", id: t.id, price: t.price })),
      ...PackTypes.all().map(t => ({ kind: "pack", id: t.id, price: t.price })),
      ...SamePowerTypes.all().map(t => ({ kind: "samepower", id: t.id, price: t.price })),   // legacy concrete slot
    ];
    for (const it of mixed) {
      const c = CampaignState.create();
      c.addCoins(1000);
      c.openStore();
      c.getStoreOffer().slots[0] = { kind: it.kind, id: it.id };
      r.eq(c.priceOfMixed(0), it.price, it.kind + " slot prices " + it.id + " at its def (" + it.price + ")");
      const before = c.getCoins();
      const res = c.buyMixedSlot(0, () => 0.42);
      r.ok(res.ok, "bought " + it.id + " through buyMixedSlot");
      r.eq(c.getCoins(), before - it.price, "…deducting exactly its def price");
      r.eq(c.getStoreOffer().slots[0], null, "…emptying the slot");
    }
  }

  // ── (b) Mystery Same-Power -------------------------------------------------
  {
    // Slot shape + at-most-one-per-shelf over many rolls.
    let sawMystery = false, multi = 0;
    for (let s = 0; s < 400; s++) {
      const c = CampaignState.create();
      c.openStore();   // no node → the QA Math.random path (shape only)
      const slots = c.getStoreOffer().slots.filter(x => x && x.kind === "samepower");
      if (slots.length) {
        sawMystery = true;
        if (!slots.every(x => x.mystery === true && x.id == null)) multi = 99;
        if (slots.length > 1) multi = Math.max(multi, slots.length);
      }
    }
    r.ok(sawMystery, "the samepower class rolls onto the shelf");
    r.eq(multi, 0, "every rolled same-power slot is the id-less mystery slot, AT MOST ONE per shelf");

    // Slot shape / price / reveal roll / charging.
    const c = CampaignState.create();
    c.addCoins(100);
    c.openStore();
    c.getStoreOffer().slots[0] = { kind: "samepower", mystery: true };
    r.eq(c.priceOfMixed(0), ItemData.store.mysterySamePower.price,
      "priceOfMixed: the mystery slot costs store.mysterySamePower.price (" + ItemData.store.mysterySamePower.price + ")");
    // Deterministic reveal: the same seeded rng picks the same pool member.
    const pool = SamePowerTypes.all().filter(t => !(t.unlock));   // ungated powers at zero stats
    const before = c.getCoins();
    const res = c.buyMixedSlot(0, () => 0);   // rng → 0: pool[0]
    r.ok(res.ok && res.kind === "samepower" && res.mystery === true, "buying the mystery slot succeeds");
    const expectedPool = SamePowerTypes.all().filter(t => !(t.unlock));   // nothing equipped yet
    r.eq(res.samePowerId, expectedPool[0].id, "the reveal roll is ONE uniform draw over the pool (rng 0 → pool[0])");
    r.eq(c.getCoins(), before - ItemData.store.mysterySamePower.price, "charged exactly the mystery price");
    r.eq(c.samePowerInventoryCount(res.samePowerId), 1, "the revealed power sits in the Same-Power inventory");
    r.eq(c.getStoreOffer().slots[0], null, "the slot is empty after the buy");
    r.ok(pool.length > 0, "…the zero-stat pool is non-empty (ungated powers exist)");

    // The EQUIPPED power is excluded from the pool (iOS parity).
    const c2 = CampaignState.create();
    c2.addCoins(100);
    c2.openStore();
    const equipped = expectedPool[0].id;
    c2.debugGrantSamePower(equipped); c2.equipSamePower(equipped);
    c2.getStoreOffer().slots[0] = { kind: "samepower", mystery: true };
    const res2 = c2.buyMixedSlot(0, () => 0);   // rng 0 → first UN-equipped pool member
    r.ok(res2.ok && res2.samePowerId !== equipped, "the equipped Same-Power is excluded from the reveal roll");

    // Empty pool → refund-and-fail (no charge, slot intact). Drove it with a
    // mutated items.js where EVERY Same-Power is gated beyond reach.
    {
      const src0 = readFileSync(join(HERE, "..", "items.js"), "utf8");
      // Gate EVERY Same-Power beyond reach (generic over the samePowers block).
      const spStart = src0.indexOf("samePowers: [");
      const spEnd = src0.indexOf("],", spStart);
      const spBlock = src0.slice(spStart, spEnd)
        .replace(/\{ id: "/g, '{ unlock: { type: "milestone", stat: "cardsBuried", count: 999999 }, id: "');
      const src = src0.slice(0, spStart) + spBlock + src0.slice(spEnd);
      const g2 = loadGame({ itemsSource: src });
      const cx = g2.CampaignState.create();
      cx.addCoins(100);
      cx.openStore();
      cx.getStoreOffer().slots[0] = { kind: "samepower", mystery: true };
      const cxBefore = cx.getCoins();
      const resx = cx.buyMixedSlot(0, () => 0.5);
      r.ok(!resx.ok, "an empty reveal pool (all powers locked) fails the buy");
      r.eq(cx.getCoins(), cxBefore, "…WITHOUT charging (refund-and-fail)");
      r.ok(cx.getStoreOffer().slots[0] && cx.getStoreOffer().slots[0].mystery === true, "…and the slot stays on the shelf");
    }

    // KEEP = equip (a displaced power returns to inventory, per the current
    // buy flow); DISCARD = destroyed, no refund.
    const k = CampaignState.create();
    k.debugGrantSamePower("linkBury"); k.debugGrantSamePower("linkCoins");
    k.equipSamePower("linkBury");
    k.equipSamePower("linkCoins");   // KEEP-equipping the reveal over an occupied slot
    r.eq(k.getSamePower(), "linkCoins", "KEEP equips the revealed power");
    r.eq(k.samePowerInventoryCount("linkBury"), 1, "…the displaced power returns to inventory (no sell-back)");
    const d = CampaignState.create();
    d.addCoins(50);
    d.debugGrantSamePower("linkBury");
    const dCoins = d.getCoins();
    r.ok(d.discardSamePowerFromInventory("linkBury"), "DISCARD removes the revealed power");
    r.eq(d.getCoins(), dCoins, "…with NO refund");
    r.eq(d.samePowerInventoryCount("linkBury"), 0, "…gone from the inventory");

    // The mystery slot survives save/restore (the "mystery": true flag rides
    // the offer serialization), and a LEGACY concrete slot still decodes + buys.
    const c4 = CampaignState.create();
    c4.addCoins(100);
    c4.openStore();
    c4.getStoreOffer().slots[0] = { kind: "samepower", mystery: true };
    c4.getStoreOffer().slots[1] = { kind: "samepower", id: "samePeek" };   // legacy shape
    const c5 = CampaignState.create();
    r.ok(c5.restore(JSON.parse(JSON.stringify(c4.serialize()))), "the save restores");
    const slots5 = c5.getStoreOffer().slots;
    r.ok(slots5[0] && slots5[0].mystery === true, "the mystery flag survives save/restore");
    r.ok(slots5[1] && slots5[1].id === "samePeek" && !slots5[1].mystery, "the legacy concrete slot survives save/restore");
    const b5 = c5.getCoins();
    r.eq(c5.priceOfMixed(1), SamePowerTypes.get("samePeek").price, "a legacy concrete slot prices from its own def");
    const res5 = c5.buyMixedSlot(1, () => 0.5);
    r.ok(res5.ok && !res5.mystery && c5.samePowerInventoryCount("samePeek") === 1,
      "…and buys straight into inventory (no reveal)");
    r.eq(c5.getCoins(), b5 - SamePowerTypes.get("samePeek").price, "…charging the def price");
  }

  // ── (c) Demolish: own-column only ------------------------------------------
  {
    const pk = BaseTypes.get("demolish").peekCount;
    const e = game(["demolish", null, null], ["columnGuardian", "insurance", null]);
    const run = e.getRun();
    r.ok(e.baseAvailable(0), "Demolish available: its own column holds a Pillar");
    r.ok(!e.baseNeedsTarget(0), "Demolish is NOT a target Base (no column picker)");
    const res = e.baseActivate(0);   // no target argument
    r.ok(res && res.demolishedCol === 0, "Demolish destroys ITS OWN column's Pillar");
    r.eq(run.pillars[0], null, "…gone from the run");
    r.eq(run.pillars[1], "insurance", "…other columns' Pillars untouched");
    r.eq(res.cards.length, pk, "…and peeks exactly the def peekCount (" + pk + ")");
    r.ok(run.kamikazeRevealLeft >= pk, "…the shared peek window is armed");

    const e2 = game(["demolish", null, null], [null, "columnGuardian", "insurance"]);
    r.ok(!e2.baseAvailable(0), "Demolish unavailable when only OTHER columns hold Pillars");
    r.eq(e2.baseActivate(0), null, "…activation refused (stays yellow)");
    const e3 = game(["demolish", null, null]);
    r.ok(!e3.baseAvailable(0), "Demolish unavailable with no Pillars at all");
  }

  // ── (d) Club Oracle (clubTell): a tell for EVERY ♣ top in the column -------
  {
    const e = game(["clubOracle", null, null]);
    const b = e.getBoard();
    b.top(0).suit = "♣"; b.top(0).wildSuit = false;
    b.top(1).suit = "♣"; b.top(1).wildSuit = false;
    b.top(2).suit = "♦"; b.top(2).wildSuit = false;   // same column, not a club
    b.top(3).suit = "♣"; b.top(3).wildSuit = false;   // another column's club — NOT read
    r.ok(e.baseAvailable(0), "Club Oracle available with ♣ tops in its column");
    const next = e.getDeck().peek(1)[0];
    const res = e.baseActivate(0);
    r.ok(res && res.tells, "activation returns a tells list");
    r.eq(JSON.stringify(res.tells), JSON.stringify([0, 1]), "…covering EVERY alive ♣-topped pile in the column, ascending");
    const want = (i) => next.value > b.top(i).value ? "higher" : next.value < b.top(i).value ? "lower" : "same";
    r.eq(e.pileHint(0), want(0), "pile 1 shows its tell vs the real next card");
    r.eq(e.pileHint(1), want(1), "pile 2 shows its tell vs the real next card");
    r.eq(e.pileHint(2), null, "the non-♣ pile in the column shows nothing");
    r.eq(e.pileHint(3), null, "a ♣ top in ANOTHER column shows nothing (column-scoped)");
    r.eq(res.cards.length, 1, "the activation snapshot is peek(1) — one next card");
    r.ok(!e.baseAvailable(0), "one-shot per deal (spent)");

    const e2 = game(["clubOracle", null, null]);
    for (let i = 0; i < 3; i++) { e2.getBoard().top(i).suit = "♠"; e2.getBoard().top(i).wildSuit = false; }
    r.ok(!e2.baseAvailable(0), "Club Oracle unavailable with no ♣ top in its column");
    r.eq(e2.baseActivate(0), null, "…activation refused");
  }

  return r.summary();
}
