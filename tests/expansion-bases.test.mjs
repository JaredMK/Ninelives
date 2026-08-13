// Expansion Bases (content pass): Club Dig (the surviving suit-gated Dig),
// Demolish (a Pillar-target Base), Heart Tax, and the newest bases (Spade Peeker,
// Suit Setter, Heart Demolish). DOM-free: drive baseActivate() directly and assert
// on board/run, plus the store suit-gating.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, CampaignState, BaseTypes, Stats } = loadGame();
  const r = makeRunner("expansion-bases.test.mjs");

  const baseDeck = () => DeckManager.buildStandardDeck();
  const COLS = [3, 4, 3];   // col 0 = piles 0-2, col 1 = piles 3-6, col 2 = piles 7-9
  const game = (bases, pillars) => {
    const e = GameEngine.create(baseDeck(), 10, { cols: COLS });
    e.start();
    e.startRun(pillars || [null, null, null], bases);
    return e;
  };
  const pileSize = (e, i) => e.getBoard().piles[i].cards.length;

  // ---- registry --------------------------------------------------------
  {
    r.eq(BaseTypes.get("clubDig").digCount, 1, "Club Dig buries 1 per ♣ pile");
    r.eq(BaseTypes.get("clubDig").suit, "♣", "Club Dig is ♣-gated");
    r.eq(BaseTypes.get("clubDig").tier, "rare", "Club Dig is Rare");
    r.ok(!BaseTypes.get("buryAll"), "Landslide (buryAll) was removed from the roster");
    r.eq(BaseTypes.get("demolish").target, "pillar", "Demolish is a Pillar-target Base");
    r.eq(BaseTypes.get("demolish").price, 13, "Demolish costs 13");
    r.eq(BaseTypes.get("tax").suit, "♥", "Heart Tax is ♥-gated");
    r.ok(["spadePeek", "setSuit", "heartDemolish"].every(id => { const t = BaseTypes.get(id); return t && t.description && t.icon; }),
      "the newest bases each have a description + icon");
  }

  // ---- Club Dig buries 1 per ♣-top pile; Wild Suit counts --------------
  {
    const e = game(["clubDig", null, null]);
    const b = e.getBoard();
    b.top(0).suit = "♣";                             // a real ♣ pile card
    b.top(1).suit = "♦"; b.top(1).wildSuit = true;   // a Wild Suit pile card counts too
    b.top(2).suit = "♦";                             // a plain ♦ — no match
    const s0 = pileSize(e, 0), s1 = pileSize(e, 1), s2 = pileSize(e, 2);
    const res = e.baseActivate(0);
    r.ok(res && res.effect === "suitDig", "Club Dig fired");
    r.eq(pileSize(e, 0) - s0, 1, "Club Dig buried 1 under the ♣ pile");
    r.eq(pileSize(e, 1) - s1, 1, "Club Dig buried 1 under the Wild Suit pile");
    r.eq(pileSize(e, 2) - s2, 0, "the plain ♦ pile is untouched");
    r.eq(res.piles, 2, "reported 2 matching piles");
  }

  // ---- Club Dig with no matching ♣ pile can't activate ----------------
  {
    const e = game(["clubDig", null, null]);
    const b = e.getBoard();
    b.top(0).suit = "♥"; b.top(0).wildSuit = false;
    b.top(1).suit = "♦"; b.top(1).wildSuit = false;
    b.top(2).suit = "♠"; b.top(2).wildSuit = false;   // no ♣ in col 0
    r.ok(!e.baseAvailable(0), "Club Dig is unavailable with no ♣ pile card in its column");
  }

  // ---- Demolish: destroy a chosen Pillar, then PEEK the next 2 cards ----
  {
    const pk = BaseTypes.get("demolish").peekCount ?? 2;
    const e = game(["demolish", null, null], [null, "columnGuardian", "insurance"]);
    const run = e.getRun();
    r.ok(e.baseAvailable(0), "Demolish is available while a Pillar exists");
    const before = run.bonusCoins;
    const res = e.baseActivate(0, 1);          // destroy the Pillar in column 1
    r.ok(res && res.demolishedCol === 1, "Demolish reported the destroyed column");
    r.eq(run.pillars[1], null, "the targeted Pillar is gone from the run");
    r.eq(run.pillars[2], "insurance", "other Pillars are untouched");
    r.eq(run.bonusCoins - before, 0, "Demolish pays no coins any more");
    r.eq(res.peekCount, pk, "Demolish peeks the next " + pk + " upcoming cards");
    r.eq(res.cards.length, pk, "…and returned that many peeked cards");
    r.ok(run.kamikazeRevealLeft >= pk, "the shared peek window is armed");
    const e2 = game(["demolish", null, null], [null, "columnGuardian", null]);
    r.eq(e2.baseActivate(0, 0), null, "Demolish can't target a column with no Pillar");
    r.eq(e2.baseActivate(0, 2), null, "Demolish can't target an empty Pillar slot");
    const e3 = game(["demolish", null, null], [null, null, null]);
    r.ok(!e3.baseAvailable(0), "Demolish is unavailable with no Pillars on the board");
  }

  // ---- Heart Tax: +1 coin per ♥ card in the column (top + buried) ------
  {
    const e = game(["tax", null, null]);
    const b = e.getBoard();
    const card = (v, s) => ({ value: v, suit: s, label: String(v), stickers: [], red: s === "♥" || s === "♦" });
    b.piles[0].cards = [card(5, "♥"), card(3, "♥")];   // 2 hearts (buried counts)
    b.piles[1].cards = [card(6, "♠")];                 // 0
    b.piles[2].cards = [card(9, "♥")]; b.kill(2);      // a ♥ pile, but DEAD → ignored
    const before = e.getRun().bonusCoins;
    const res = e.baseActivate(0);
    r.eq(res.gained, 2, "Heart Tax counts only ALIVE piles' ♥ cards");
    r.eq(e.getRun().bonusCoins - before, 2, "Heart Tax paid +2 coins");
  }

  // ---- once-per-deal lifecycle still holds for the new Bases -----------
  {
    const e = game(["tax", null, null]);
    const b = e.getBoard();
    b.top(0).suit = "♥";                 // ensure a heart so Tax is available
    e.baseActivate(0);
    r.ok(!e.baseAvailable(0), "a spent expansion Base is unavailable until the next deal");
  }

  // ---- stage gating REMOVED: every UNLOCKED Base can offer at any time ----
  // (UNLOCK2: several bases are unlock-gated now; the suit-stage rule is
  // asserted by seeding their stats — they still roll at STAGE 1.)
  {
    const sample = (c, n) => { const seen = new Set(); for (let i = 0; i < n; i++) c.openStore().slots.forEach(s => { if (s && s.kind === "base") seen.add(s.id); }); return seen; };
    Stats.bumpAll({ cardsBuried: 999, pillarsPlaced: 999, pilesLost: 999, stickersApplied: 999, correctSames: 999, samesCalled: 999, basesPlaced: 999, bossesBeaten: 999 });
    const s1 = sample(CampaignState.create(), 3000);         // Stage 1 = ♦ ♥
    // Exemplars must be bases whose gate this build can READ: Club Dig and
    // Heart Demolish now gate on native-only suit counters (clubsPlayed /
    // heartsPlayed), which have no reader here, so they stay locked on the web
    // by design and can't demonstrate the any-stage rule.
    r.ok(s1.has("refreshBases"), "Stage 1 CAN offer Reactor once unlocked (any-stage rule holds)");
    r.ok(s1.has("tax"), "Heart Tax (♥) offers from Stage 1");
    r.ok(s1.has("demolish"), "suit-free Base (Demolish) offers from Stage 1 once unlocked");
    r.ok(s1.has("stickerHarvest"), "the suit-free bases offer from Stage 1 once unlocked");
    Stats.reset();
  }

  return r.summary();
}
