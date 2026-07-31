// Four Same-related items (all rare): a STICKER and a BASE each for
//  - Recharge Same Shield  → bank a Same Charge (max 1; no-op if already charged)
//  - Activate Same Power    → fire the equipped Same-Power on linked piles,
//                             WITHOUT banking a charge; no-op if none equipped.
// Stickers fire on correct placement of the carrier; bases on activation
// (once per deal). DOM-free — drive the engine directly.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, CampaignState, StickerTypes, BaseTypes, Stats } = loadGame();
  const r = makeRunner("same-items.test.mjs");

  const deck = () => DeckManager.buildStandardDeck();
  const COLS = [3, 4, 3];   // col 0 = piles 0-2, col 1 = piles 3-6, col 2 = piles 7-9
  const mk = (power) => {
    const e = GameEngine.create(deck(), 10, { cols: COLS, samePower: power || null });
    e.start(); e.startRun([null, null, null], [null, null, null], power || null);
    return e;
  };
  const gameBase = (bases, power) => {
    const e = GameEngine.create(deck(), 10, { cols: COLS, samePower: power || null });
    e.start(); e.startRun([null, null, null], bases, power || null);
    return e;
  };
  /** Land a stickered card on pile `i` via a guaranteed-correct DIRECTIONAL guess
      (so ONLY the sticker fires — not the same-guess bank). top=5, drawn=10. */
  const landSticker = (e, i, stickerId) => {
    const b = e.getBoard();
    b.top(i).value = 5; b.top(i).label = "5";
    e.debug.setNextCard(10);                 // drawn card is a 10
    e.debug.applyStickerToNext(stickerId);   // …carrying the sticker
    e.guess(i, "higher");                    // 10 > 5 → correct, directional
  };

  // ================= REGISTRY =================
  {
    const sIds = ["rechargeSameShield", "activateSamePower"];
    const bIds = ["rechargeSame", "activateSame"];
    r.ok(sIds.every(id => !!StickerTypes.get(id)), "both new stickers registered");
    r.ok(bIds.every(id => !!BaseTypes.get(id)), "both new bases registered");
    const all = [...sIds.map(id => StickerTypes.get(id)), ...bIds.map(id => BaseTypes.get(id))];
    r.ok(all.every(t => t.tier === "rare"), "all four are rare");
    // Descriptions are free-form now (stickers use the arrow form, bases use a
    // short plain sentence) — just require a non-empty description on each.
    r.ok(all.every(t => typeof t.description === "string" && t.description.length > 0), "all four carry a description");
    r.ok(sIds.every(id => /→/.test(StickerTypes.get(id).description)), "the two same-* stickers use the arrow form");
    r.ok(all.every(t => t.icon), "all carry an icon/artwork");
    r.eq(StickerTypes.get("rechargeSameShield").price, 15, "Recharge Shield sticker costs 15");
    r.eq(StickerTypes.get("activateSamePower").price, 12, "Tap Power sticker costs 12");
    r.eq(BaseTypes.get("rechargeSame").price, 25, "Recharge Cell base costs 25");
    r.eq(BaseTypes.get("activateSame").price, 20, "Power Surge base costs 20");
    r.eq(BaseTypes.get("rechargeSame").kind, "active", "Recharge Cell is an activated base");
    r.eq(BaseTypes.get("activateSame").kind, "active", "Power Surge is an activated base");
    r.ok(!BaseTypes.get("rechargeSame").target && !BaseTypes.get("activateSame").target,
      "neither new base needs a hand-picked target");
  }

  // ================= STICKER: Recharge Shield =================
  {
    const e = mk();   // no power needed
    r.ok(!e.sameCharge(), "no charge before");
    landSticker(e, 0, "rechargeSameShield");
    r.ok(e.sameCharge(), "Recharge Shield banked a Same Charge on correct placement");
    // Already charged → banks nothing extra (max 1), no crash.
    landSticker(e, 1, "rechargeSameShield");
    r.ok(e.sameCharge(), "still charged (max 1 — a second recharge is a harmless no-op)");
  }

  // ================= STICKER: Tap Power =================
  {
    // fires the equipped power BOARD-WIDE (v5.66); banks NO charge.
    const e = mk("linkBury");
    e.setLinks({ 0: [1, 2], 1: [0], 2: [0] });
    const b = e.getBoard();
    const s1 = b.pileSize(1), s2 = b.pileSize(2);
    let evt = null;
    e.onEvent((t, p) => { if (t === "same-power") evt = p; });
    landSticker(e, 0, "activateSamePower");
    r.ok(evt && evt.power === "linkBury", "Tap Power fired the equipped Same-Power");
    r.eq(evt.targets.length, b.aliveCount(), "…on EVERY alive pile (v5.66: links no longer scope powers)");
    r.eq(b.pileSize(1), s1 + 1, "a pile got a Burrow bury");
    r.eq(b.pileSize(2), s2 + 1, "…and so did the next one");
    r.ok(!e.sameCharge(), "Tap Power did NOT bank a Same Charge");
  }

  // ================= STICKER: Tap Power with NOTHING equipped =================
  {
    const e = mk();   // no power
    e.setLinks({ 0: [1, 2] });
    let fired = false;
    e.onEvent((t) => { if (t === "same-power") fired = true; });
    landSticker(e, 0, "activateSamePower");
    r.ok(!fired, "no Same-Power equipped → Tap Power does nothing (no event)");
    r.ok(!e.sameCharge(), "…and still banks no charge");
  }

  // ================= BASE: Recharge Cell =================
  {
    const e = gameBase(["rechargeSame", null, null]);
    r.ok(!e.sameCharge(), "no charge before");
    r.ok(e.baseAvailable(0), "Recharge Cell is available while un-charged");
    const res = e.baseActivate(0);
    r.ok(res && res.sameCharge === true, "activation reports the banked charge");
    r.ok(e.sameCharge(), "Recharge Cell banked a Same Charge");
    r.eq(e.getRun().basesUsed[0], true, "activating spent the base (once per deal)");
    // Already charged → unavailable (never wasted).
    const e2 = gameBase(["rechargeSame", null, null]);
    e2.debug.forceSame(0);   // bank a charge first
    r.ok(e2.sameCharge(), "a Same banked a charge");
    r.ok(!e2.baseAvailable(0), "Recharge Cell is unavailable while already charged");
  }

  // ================= BASE: Power Surge =================
  {
    // Every alive pile in col 0 (0,1,2) links to pile 3, so whichever random hub
    // the base picks, pile 3 is a Burrow target.
    const e = gameBase(["activateSame", null, null], "linkBury");
    e.setLinks({ 0: [3], 1: [3], 2: [3], 3: [0] });
    const b = e.getBoard();
    const s3 = b.pileSize(3);
    r.ok(e.baseAvailable(0), "Power Surge is available with a Same-Power equipped");
    let evt = null;
    e.onEvent((t, p) => { if (t === "same-power") evt = p; });
    const res = e.baseActivate(0);
    r.ok(res && [0, 1, 2].includes(res.hub), "Power Surge fired on a random pile in its own column");
    r.ok(evt && evt.power === "linkBury", "…the equipped Same-Power fired");
    r.eq(b.pileSize(3), s3 + 1, "the linked pile got a Burrow bury");
    r.ok(!e.sameCharge(), "Power Surge did NOT bank a Same Charge");
    r.eq(e.getRun().basesUsed[0], true, "activating spent the base (once per deal)");
    // No Same-Power equipped → unavailable (would do nothing, so never offered).
    const e2 = gameBase(["activateSame", null, null]);   // no power
    e2.setLinks({ 0: [3], 1: [3], 2: [3] });
    r.ok(!e2.baseAvailable(0), "Power Surge is unavailable with no Same-Power equipped");
  }

  // ================= STORE POOL: all four roll at rare weight =================
  // (UNLOCK2: all four are Same-mastery gated — seed the counters first.)
  {
    Stats.bumpAll({ samesCalled: 999, correctSames: 999 });
    const c = CampaignState.create();
    const want = new Set(["rechargeSameShield", "activateSamePower", "rechargeSame", "activateSame"]);
    const seen = new Set();
    for (let i = 0; i < 6000 && seen.size < want.size; i++) {
      c.openStore().slots.forEach(s => { if (s && want.has(s.id)) seen.add(s.id); });
    }
    r.eq(seen.size, want.size, "all four new items surface in the unified store pool once unlocked (" + [...seen].sort().join(",") + ")");
    Stats.reset();
  }

  return r.summary();
}
