// Joker + Blank card-pack options.
//  JOKER: a wild card — ANY guess it's part of is CORRECT (drawn AND as the
//         pile top being guessed against) and banks 1 Same Charge on any
//         landing it's in (never firing the Same-Power).
//  BLANK: a removal — swapped in over a chosen card, it removes that card so
//         the deck permanently shrinks by one.
//  Both appear as pack options at HALF a normal rank's frequency.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, CampaignState } = loadGame();
  const r = makeRunner("joker-blank.test.mjs");

  const COLS = [3, 4, 3];
  const mk = (cfg) => {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 9, Object.assign({ cols: COLS }, cfg || {}));
    e.start(); e.startRun();
    return e;
  };
  const joker = (id = 9001) => ({ id, joker: true, label: "★", value: 0, suit: "★", red: false, stickers: [], suitGuards: {}, heartsRemaining: 0 });

  // --- JOKER: correct for EVERY guess direction (never wrong) --------------
  for (const dir of ["higher", "lower", "same"]) {
    const e = mk();
    const b = e.getBoard();
    b.top(0).value = 7;
    e.debug.setNextCardObj(joker());
    e.guess(0, dir);
    r.ok(b.isActive(0), "Joker survives a '" + dir + "' guess (never wrong)");
    r.ok(b.top(0).joker, "the Joker landed as the pile's new top card");
  }

  // --- JOKER as the PILE TOP: any guess ON TOP of it is safe too -----------
  // (regression: a "lower" onto a rankless Joker top compared against value 0
  //  and killed the pile)
  for (const dir of ["higher", "lower", "same"]) {
    const e = mk();
    const b = e.getBoard();
    Object.assign(b.top(0), joker(9100));   // the pile's top card IS a Joker
    e.debug.setNextCard(7);                 // a perfectly ordinary drawn card
    e.guess(0, dir);
    r.ok(b.isActive(0), "a '" + dir + "' guess ON a Joker top is safe (pile survives)");
    r.eq(b.top(0).value, 7, "the drawn card landed on top of the Joker");
  }

  // --- JOKER top: a Same call onto it banks but does NOT fire the power ----
  {
    let firedPower = false;
    const e = mk();
    e.debug.setSamePower("linkShuffle");
    e.onEvent((t) => { if (t === "same-power") firedPower = true; });
    Object.assign(e.getBoard().top(0), joker(9101));
    e.debug.setNextCard(9);
    e.guess(0, "same");                     // freebie-correct on a Joker top
    r.ok(e.getBoard().isActive(0), "the Same call on a Joker top survives");
    r.ok(e.sameCharge(), "…and banks the Same Charge");
    r.ok(!firedPower, "…but does NOT fire the equipped Same-Power (no guaranteed trigger)");
  }

  // --- JOKER: banks a Same Charge on ANY guess (not just a Same call) ------
  {
    const e = mk();
    r.ok(!e.sameCharge(), "no charge to start");
    e.getBoard().top(0).value = 5;
    e.debug.setNextCardObj(joker());
    e.guess(0, "higher");                 // a HIGHER call, not a Same
    r.ok(e.sameCharge(), "the Joker banked a Same Charge on a non-Same guess");
  }

  // --- JOKER: banks the charge but does NOT fire the equipped Same-Power ---
  {
    let firedPower = false;
    const e = mk();
    e.debug.setSamePower("linkShuffle");     // equip a Same-Power live
    e.onEvent((t) => { if (t === "same-power") firedPower = true; });
    e.getBoard().top(0).value = 6;
    e.debug.setNextCardObj(joker());
    e.guess(0, "same");                   // even on a Same call, the Joker only banks
    r.ok(e.sameCharge(), "Joker banked the charge on a Same call");
    r.ok(!firedPower, "Joker did NOT fire the equipped Same-Power (only banked)");
  }

  // --- control: a REAL same (non-Joker) DOES fire the Same-Power ----------
  {
    let firedPower = false;
    const e = mk();
    e.debug.setSamePower("linkShuffle");
    e.onEvent((t) => { if (t === "same-power") firedPower = true; });
    e.getBoard().top(0).value = 8;
    e.debug.setNextCard(8);               // a real tie → correct Same
    e.guess(0, "same");
    r.ok(firedPower, "a real correct Same DOES fire the Same-Power (contrast with the Joker)");
  }

  // --- BLANK: swapped in, it removes the chosen card (deck shrinks by 1) ---
  {
    const c = CampaignState.create();
    const before = c.deckSize();
    // hold a Blank in the tray, then "replace" a real deck card with it
    const blank = { id: 99999, blank: true, suit: "∅", originalRank: 0, currentRank: 0, modifications: [], stickers: [], compoundHits: 0 };
    c.addPackCard(blank);
    const victimId = c.getRunDeck()[0].id;
    const res = c.replaceDeckCard(victimId, 0);
    r.ok(res && res.blank, "replaceDeckCard consumed the Blank");
    r.eq(c.deckSize(), before - 1, "the deck shrank by exactly one card (removal)");
    r.ok(!c.getRunDeck().some(x => x.id === victimId), "the chosen card is gone from the deck");
    r.ok(!c.getRunDeck().some(x => x.blank), "the Blank itself is NOT added to the deck");
  }

  // --- FREQUENCY: Joker/Blank each ≈ half a rank's rate -------------------
  {
    const c = CampaignState.create();
    let rng = 12345;
    const rand = () => { rng = (rng * 1103515245 + 12345) & 0x7fffffff; return rng / 0x7fffffff; };
    const N = 40000;
    let jok = 0, bl = 0, ranks = {};
    for (let i = 0; i < N; i++) {
      const card = c.genPackCard(rand);
      if (card.joker) jok++;
      else if (card.blank) bl++;
      else ranks[card.currentRank] = (ranks[card.currentRank] || 0) + 1;
    }
    const rankVals = Object.values(ranks);
    const avgRank = rankVals.reduce((a, b) => a + b, 0) / rankVals.length;   // avg per-rank count
    // Each specific rank appears ~N/14; Joker and Blank each ~N/28 (half a rank).
    r.ok(jok > 0 && bl > 0, "both Joker and Blank appear in the roll");
    r.ok(Math.abs(jok - avgRank / 2) / (avgRank / 2) < 0.25, "Joker ≈ half a rank's frequency (joker " + jok + " vs half-rank " + Math.round(avgRank / 2) + ")");
    r.ok(Math.abs(bl - avgRank / 2) / (avgRank / 2) < 0.25, "Blank ≈ half a rank's frequency (blank " + bl + " vs half-rank " + Math.round(avgRank / 2) + ")");
  }

  return r.summary();
}
