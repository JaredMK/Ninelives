// Joker + Blank card-pack options.
//  JOKER (rework): ANY guess it's part of is SAFE (drawn AND as the pile top
//         being guessed against). No freebies on higher/lower — the old
//         auto-banked Same Charge is GONE. A SAME call with a Joker on either
//         side counts as a fully correct Same: banks the charge AND fires the
//         equipped Same-Power.
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

  // --- JOKER top + SAME call: a fully correct Same — banks AND fires -------
  {
    let firedPower = false;
    const e = mk();
    e.debug.setSamePower("linkShuffle");
    e.onEvent((t) => { if (t === "same-power") firedPower = true; });
    Object.assign(e.getBoard().top(0), joker(9101));
    e.debug.setNextCard(9);
    e.guess(0, "same");                     // Joker top makes the Same correct
    r.ok(e.getBoard().isActive(0), "the Same call on a Joker top survives");
    r.ok(e.sameCharge(), "…banks the Same Charge");
    r.ok(firedPower, "…AND fires the equipped Same-Power (full Same, Joker on the pile side)");
  }

  // --- JOKER: NO auto-banked charge on a non-Same guess (rework) -----------
  {
    const e = mk();
    r.ok(!e.sameCharge(), "no charge to start");
    e.getBoard().top(0).value = 5;
    e.debug.setNextCardObj(joker());
    e.guess(0, "higher");                 // a HIGHER call, not a Same
    r.ok(e.getBoard().isActive(0), "the Joker landing is safe on higher");
    r.ok(!e.sameCharge(), "a non-Same Joker landing banks NOTHING (auto-charge removed)");
  }
  {
    const e = mk();
    Object.assign(e.getBoard().top(0), joker(9102));
    e.debug.setNextCard(4);
    e.guess(0, "lower");                  // any call on a Joker top is safe
    r.ok(e.getBoard().isActive(0), "lower onto a Joker top is safe");
    r.ok(!e.sameCharge(), "…and banks nothing (auto-charge removed on the pile side too)");
  }

  // --- DRAWN JOKER + SAME call: a fully correct Same — banks AND fires -----
  {
    let firedPower = false;
    const e = mk();
    e.debug.setSamePower("linkShuffle");     // equip a Same-Power live
    e.onEvent((t) => { if (t === "same-power") firedPower = true; });
    e.getBoard().top(0).value = 6;
    e.debug.setNextCardObj(joker());
    e.guess(0, "same");                   // Same call with the drawn Joker
    r.ok(e.sameCharge(), "a drawn-Joker Same banks the charge");
    r.ok(firedPower, "…AND fires the equipped Same-Power (full Same, Joker on the drawn side)");
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

  // --- FREQUENCY: Joker/Blank weight 0.5 each vs the FULL 52-card pool ----
  {
    const c = CampaignState.create();
    // mulberry32 — the old LCG's lattice structure aliased against the roll's
    // variable rng-consumption pattern (ungated sticker pools shifted it) and
    // skewed the observed special rate far beyond binomial noise.
    let seed = 12345;
    const rand = () => {
      seed = (seed + 0x6D2B79F5) | 0;
      let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
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
    // Roll space = 52 cards (weight 1) + Joker (0.5) + Blank (0.5) = 53:
    // P(Joker) = P(Blank) = 0.5/53 ≈ 0.94% each. Normal picks spread evenly
    // over 13 ranks (each ≈ (52/53)/13 of all rolls), so each special lands at
    // 0.5·13/52 = 1/8 of a rank's observed frequency.
    r.ok(jok > 0 && bl > 0, "both Joker and Blank appear in the roll");
    r.ok(Math.abs(jok - avgRank / 8) / (avgRank / 8) < 0.3, "Joker ≈ 1/8 of a rank's frequency (joker " + jok + " vs rank/8 " + Math.round(avgRank / 8) + ")");
    r.ok(Math.abs(bl - avgRank / 8) / (avgRank / 8) < 0.3, "Blank ≈ 1/8 of a rank's frequency (blank " + bl + " vs rank/8 " + Math.round(avgRank / 8) + ")");
    const pJoker = jok / N, pBlank = bl / N;
    r.ok(pJoker > 0.005 && pJoker < 0.015, "P(Joker) ≈ 0.5/53 ≈ 0.94% (got " + (pJoker * 100).toFixed(2) + "%)");
    r.ok(pBlank > 0.005 && pBlank < 0.015, "P(Blank) ≈ 0.5/53 ≈ 0.94% (got " + (pBlank * 100).toFixed(2) + "%)");
  }

  return r.summary();
}
