// Expansion Bases (content pass): the 6 new Bases — the suit-gated Dig family,
// Demolish (a Pillar-target Base), and Tax. DOM-free: drive baseActivate()
// directly and assert on board/run, plus the store suit-gating.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, CampaignState, BaseTypes } = loadGame();
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
    const ids = ["heartDig", "diamondDig", "spadeDig", "clubDig", "demolish", "tax"];
    r.ok(ids.every(id => !!BaseTypes.get(id)), "all 6 new Bases registered");
    r.eq(BaseTypes.all().length, 19, "base registry now totals 19");
    r.eq(BaseTypes.get("clubDig").digCount, 3, "Club Dig buries 3 per ♣ pile");
    r.eq(BaseTypes.get("spadeDig").digCount, 2, "Spade Dig buries 2 per ♠ pile");
    r.eq(BaseTypes.get("demolish").target, "pillar", "Demolish is a Pillar-target Base");
    r.ok(ids.every(id => { const t = BaseTypes.get(id); return t.description && t.icon; }), "every new Base has a description + icon");
  }

  // ---- Heart Dig: bury digCount under each ♥ pile card in the column ----
  {
    const e = game(["heartDig", null, null]);
    const b = e.getBoard();
    // col 0 = piles 0,1,2. Make piles 0 and 1 show ♥, pile 2 show ♠.
    b.top(0).suit = "♥"; b.top(1).suit = "♥"; b.top(2).suit = "♠";
    const s0 = pileSize(e, 0), s1 = pileSize(e, 1), s2 = pileSize(e, 2);
    const res = e.baseActivate(0);
    r.ok(res && res.effect === "suitDig", "Heart Dig fired");
    r.eq(pileSize(e, 0) - s0, 1, "buried 1 under the first ♥ pile");
    r.eq(pileSize(e, 1) - s1, 1, "buried 1 under the second ♥ pile");
    r.eq(pileSize(e, 2) - s2, 0, "left the ♠ pile untouched");
    r.eq(res.piles, 2, "reported 2 matching piles");
  }

  // ---- Club Dig buries 3 per ♣ pile; Wild Suit counts -----------------
  {
    const e = game(["clubDig", null, null]);
    const b = e.getBoard();
    b.top(0).suit = "♣";                       // a real ♣ pile card
    b.top(1).suit = "♦"; b.top(1).wildSuit = true;   // a Wild Suit pile card counts too
    b.top(2).suit = "♦";                       // a plain ♦ — no match
    const s0 = pileSize(e, 0), s1 = pileSize(e, 1), s2 = pileSize(e, 2);
    e.baseActivate(0);
    r.eq(pileSize(e, 0) - s0, 3, "Club Dig buried 3 under the ♣ pile");
    r.eq(pileSize(e, 1) - s1, 3, "Club Dig buried 3 under the Wild Suit pile");
    r.eq(pileSize(e, 2) - s2, 0, "the plain ♦ pile is untouched");
  }

  // ---- Dig with no matching pile card can't activate -------------------
  {
    const e = game(["spadeDig", null, null]);
    const b = e.getBoard();
    b.top(0).suit = "♥"; b.top(1).suit = "♦"; b.top(2).suit = "♣";   // no ♠ in col 0
    r.ok(!e.baseAvailable(0), "Spade Dig is unavailable with no ♠ pile card in its column");
  }

  // ---- Demolish: destroy a chosen Pillar for +15 coins -----------------
  {
    const e = game(["demolish", null, null], [null, "columnGuardian", "spadeBounty"]);
    const run = e.getRun();
    r.ok(e.baseAvailable(0), "Demolish is available while a Pillar exists");
    const before = run.bonusCoins;
    const res = e.baseActivate(0, 1);          // destroy the Pillar in column 1
    r.ok(res && res.demolishedCol === 1, "Demolish reported the destroyed column");
    r.eq(run.pillars[1], null, "the targeted Pillar is gone from the run");
    r.eq(run.pillars[2], "spadeBounty", "other Pillars are untouched");
    r.eq(run.bonusCoins - before, 15, "Demolish paid +15 coins");
    // Targeting a column with no Pillar is rejected.
    const e2 = game(["demolish", null, null], [null, "columnGuardian", null]);
    r.eq(e2.baseActivate(0, 0), null, "Demolish can't target a column with no Pillar");
    r.eq(e2.baseActivate(0, 2), null, "Demolish can't target an empty Pillar slot");
    // With no Pillar anywhere, Demolish can't activate at all.
    const e3 = game(["demolish", null, null], [null, null, null]);
    r.ok(!e3.baseAvailable(0), "Demolish is unavailable with no Pillars on the board");
  }

  // ---- Tax: +1 coin per BLACK pile card (♠/♣) on the board -------------
  {
    const e = game(["tax", null, null]);
    const b = e.getBoard();
    for (let i = 0; i < 10; i++) b.top(i).red = true;          // all red → no black cards
    b.top(0).red = false; b.top(3).red = false; b.top(7).red = false;   // 3 alive black tops
    b.top(9).red = false; b.kill(9);                           // a black-topped pile, but DEAD → ignored
    const before = e.getRun().bonusCoins;
    const res = e.baseActivate(0);
    r.eq(res.gained, 3, "Tax counts only ALIVE black pile cards (♠/♣)");
    r.eq(e.getRun().bonusCoins - before, 3, "Tax paid +3 coins");
  }

  // ---- once-per-deal lifecycle still holds for the new Bases -----------
  {
    const e = game(["tax", null, null]);
    e.baseActivate(0);
    r.ok(!e.baseAvailable(0), "a spent expansion Base is unavailable until the next deal");
  }

  // ---- store suit-gating: Dig Bases follow the suit schedule -----------
  {
    // Bases now arrive via the store's MIXED slots — scan those for base kinds.
    const sample = (c, n) => { const seen = new Set(); for (let i = 0; i < n; i++) c.openStore().mixed.forEach(s => { if (s && s.kind === "base") seen.add(s.id); }); return seen; };
    const s1 = sample(CampaignState.create(), 700);          // Stage 1 = ♦ ♥
    r.ok(s1.has("heartDig") && s1.has("diamondDig"), "Stage 1 offers Heart/Diamond Dig (♦♥ in play)");
    r.ok(!s1.has("clubDig"), "Stage 1 NEVER offers Club Dig (♣ not in play)");
    r.ok(!s1.has("spadeDig"), "Stage 1 NEVER offers Spade Dig (♠ not in play)");
    r.ok(s1.has("demolish"), "suit-free Base (Demolish) offers from Stage 1");
    r.ok(!s1.has("tax"), "Tax is gated on ♣ → NOT offered in Stage 1 (no black cards yet)");

    const c2 = CampaignState.create();
    for (let i = 0; i < 4; i++) c2.advance();                 // → Stage 2 = ♦ ♥ ♣
    const s2 = sample(c2, 700);
    r.ok(s2.has("clubDig"), "Stage 2 offers Club Dig (♣ now in play)");
    r.ok(s2.has("tax"), "Stage 2 offers Tax (♣ in play → black cards exist)");
    r.ok(!s2.has("spadeDig"), "Stage 2 still NEVER offers Spade Dig (♠ not yet)");

    const c3 = CampaignState.create();
    for (let i = 0; i < 8; i++) c3.advance();                 // → Stage 3 = ♦ ♥ ♣ ♠
    const s3 = sample(c3, 700);
    r.ok(s3.has("spadeDig"), "Stage 3 offers Spade Dig (all four suits in play)");
  }

  return r.summary();
}
