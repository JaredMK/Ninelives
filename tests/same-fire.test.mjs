// The "Same" mechanic — Layer 2 (Same fires all installed artifacts). Every
// correct Same ALSO re-triggers every installed whole-column Base AND grants the
// coin rewards of installed Pillars — BYPASSING the normal once-per-deal limits
// (a Base already spent this deal re-fires; intentionally very powerful). Manual-
// target Bases (Kamikaze / Sticker Harvest / Demolish) are skipped (no sensible
// auto-target). DOM-free — drive the engine directly and assert on board/deck/run.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager } = loadGame();
  const r = makeRunner("same-fire.test.mjs");

  const deck = () => DeckManager.buildStandardDeck();
  // col 0 = piles 0-2, col 1 = piles 3-6, col 2 = piles 7-9.
  const COLS = [3, 4, 3];
  const game = (pillars, bases) => {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start();
    e.startRun(pillars || [null, null, null], bases || [null, null, null]);
    return e;
  };
  /** Drive a guaranteed-correct Same on pile `i`: pin its top, force a tie, guess
      "same". Returns nothing — the Same banks a charge AND fires every artifact. */
  const sameOn = (e, i, val) => {
    const b = e.getBoard();
    b.top(i).value = (val == null ? 7 : val);
    b.top(i).label = String(b.top(i).value);
    e.debug.setNextCard(b.top(i).value);   // a tie
    e.guess(i, "same");
  };

  // --- a correct Same RE-FIRES a SPENT whole-column Base -----------------
  {
    const e = game(null, ["buryLargest", null, null]);
    const b = e.getBoard();
    // Spend Bury Largest once: it buries one deck card under col 0's biggest pile.
    const remStart = e.getDeck().remaining();
    e.baseActivate(0);
    r.ok(e.getRun().basesUsed[0], "Bury Largest is spent after one activation");
    r.eq(e.getDeck().remaining(), remStart - 1, "one card buried by the manual activation");

    // Now a correct Same on a pile in col 0 must re-fire the SPENT Base. Count the
    // "buried" event so the re-fire is isolated from the Same's own tie-card draw.
    let baseFires = 0, sameBuried = 0;
    e.onEvent((t, p) => {
      if (t === "base-fired") baseFires++;
      if (t === "buried" && p.source === "Sinkhole") sameBuried += p.count;
    });
    sameOn(e, 0, 7);
    r.ok(e.sameCharge(), "the correct Same banked a charge (Layer 1 still holds)");
    r.eq(baseFires, 1, "the Same re-fired the spent Base (one base-fired event)");
    r.eq(sameBuried, 1, "the re-fire buried another deck card (bypassed once-per-deal)");
    r.eq(e.getRun().basesUsed[0], true, "the re-fired Base is spent again afterwards (back to once-per-deal)");
  }

  // --- the Same keeps re-firing on EVERY correct Same (not just once) ----
  {
    const e = game(null, ["buryLargest", null, null]);
    let baseFires = 0;
    e.onEvent((t) => { if (t === "base-fired") baseFires++; });
    sameOn(e, 0, 7);
    sameOn(e, 1, 8);
    sameOn(e, 2, 6);
    r.eq(baseFires, 3, "three correct Sames re-fired the Base three times");
  }

  // --- manual-TARGET Bases are NOT auto-fired (no sensible auto-target) --
  {
    const e = game(null, ["kamikaze", null, null]);
    let baseFires = 0;
    e.onEvent((t) => { if (t === "base-fired") baseFires++; });
    const aliveBefore = e.getBoard().aliveCount();
    sameOn(e, 0, 7);
    r.eq(baseFires, 0, "a target Base (Kamikaze) is skipped by the Same auto-fire");
    r.eq(e.getBoard().aliveCount(), aliveBefore, "no pile was sacrificed (Kamikaze never auto-fired)");
    r.ok(!e.getRun().basesUsed[0], "the target Base stays charged (untouched by the Same)");
  }

  // --- a correct Same grants an END-OF-DEAL scoring Pillar's coins now ---
  {
    // Guardian (+7 if every pile in the column survived). All piles start alive,
    // so the Same should pay its current contribution (+7) immediately.
    const e = game(["columnGuardian", null, null], null);
    const before = e.getRun().bonusCoins;
    sameOn(e, 0, 7);
    r.eq(e.getRun().bonusCoins - before, 7, "the Same paid Guardian's +7 (column all-alive) live");
  }

  // --- a correct Same grants a PER-LANDING coin Pillar's value ----------
  {
    // Prime normally pays +1 only when a prime-rank card lands; on a Same it pays
    // its value regardless (the Same fires the artifact's reward directly). Use a
    // NON-prime tie value (8) so the live guess() pays nothing — the +1 is purely
    // from the Same's auto-fire.
    const e = game(["prime", null, null], null);
    const before = e.getRun().bonusCoins;
    let fired = false;
    e.onEvent((t, p) => { if (t === "pillar-fired" && p.effect === "prime") fired = true; });
    sameOn(e, 0, 8);   // 8 is not prime → live guess pays 0; the +1 is the Same auto-fire's
    r.eq(e.getRun().bonusCoins - before, 1, "the Same granted Prime's +1 coin");
    r.ok(fired, "Prime pulsed (pillar-fired) on the Same");
  }

  // --- a non-coin Pillar still PULSES for feedback on a Same ------------
  {
    const e = game(["columnGuardian", null, null], null);
    // Kill a pile in col 0 so Guardian pays nothing (not all-alive) — it should
    // still pulse for feedback, with amount 0.
    e.getBoard().kill(2);
    let firedAmt = null;
    e.onEvent((t, p) => { if (t === "pillar-fired" && p.col === 0) firedAmt = p.amount; });
    const before = e.getRun().bonusCoins;
    sameOn(e, 0, 7);
    r.eq(e.getRun().bonusCoins - before, 0, "Guardian paid nothing (column not all-alive)");
    r.eq(firedAmt, 0, "the Pillar still pulsed for feedback (amount 0)");
  }

  // ====================================================================
  // LAYER 3 — Same-payoff artifacts (Resonance, Dynamo, Resonator)
  // ====================================================================

  // --- Resonance Pillar: a correct Same grows its column (buries 2 each) -
  {
    const e = game(["resonance", null, null], null);
    const b = e.getBoard();
    const sizesBefore = [0, 1, 2].map(i => b.pileSize(i));
    let grew = 0, firedGrow = false;
    e.onEvent((t, p) => {
      if (t === "buried" && p.source === "Resonance") grew += p.count;
      if (t === "pillar-fired" && p.effect === "sameGrow") firedGrow = true;
    });
    // The Same lands on pile 7 (a DIFFERENT column) — Resonance still grows col 0,
    // because Layer 2 fires every installed artifact on ANY correct Same.
    sameOn(e, 7, 7);
    r.eq(grew, 6, "Resonance buried 2 under each of col 0's 3 alive piles (=6)");
    r.ok(firedGrow, "Resonance pulsed (sameGrow) on the Same");
    r.ok([0, 1, 2].every(i => b.pileSize(i) === sizesBefore[i] + 2), "every alive pile in col 0 grew by 2");
  }

  // --- Dynamo Pillar: a Same-Charge SAVE in its column refills the charge -
  {
    const e = game(["dynamo", null, null], ["", "", ""].map(() => null));
    const b = e.getBoard();
    // Seed a charge by banking a correct Same first.
    sameOn(e, 0, 7);
    r.ok(e.sameCharge(), "charge banked");
    // Now a would-be death on a pile in col 0 (Dynamo's column): the backstop
    // saves it AND Dynamo refills the charge.
    let refilled = false;
    e.onEvent((t, p) => { if (t === "pillar-fired" && p.effect === "sameRecharge") refilled = true; });
    b.top(1).value = 5;
    e.debug.setNextCard(9);
    e.guess(1, "lower");                 // 9 > 5 → wrong → backstop saves pile 1
    r.ok(b.isActive(1), "the backstop saved the pile");
    r.ok(refilled, "Dynamo fired on the save (sameRecharge)");
    r.ok(e.sameCharge(), "Dynamo refilled the Same Charge (repeatable backstop in this column)");

    // A save in a column WITHOUT Dynamo does NOT refill.
    const e2 = game(["dynamo", null, null], ["", "", ""].map(() => null));
    sameOn(e2, 0, 7);                    // bank a charge
    const b2 = e2.getBoard();
    b2.top(7).value = 5;                 // pile 7 is in col 2 (no Dynamo)
    e2.debug.setNextCard(9);
    e2.guess(7, "lower");                // wrong → backstop saves, but col 2 has no Dynamo
    r.ok(b2.isActive(7), "the backstop saved the pile in the Dynamo-less column");
    r.ok(!e2.sameCharge(), "no Dynamo there → the charge stayed spent");
  }

  // --- Resonator sticker: +4 coins when this card lands as a correct Same -
  {
    const e = game(null, null);
    const b = e.getBoard();
    b.top(0).value = 7; b.top(0).label = "7";
    const nc = e.debug.setNextCard(7);              // a tie
    nc.stickers = [{ type: "resonator" }];          // the landing card carries Resonator
    const before = e.getRun().bonusCoins;
    e.guess(0, "same");                              // correct Same → Resonator pays +4
    r.ok(b.isActive(0), "the Same survived");
    r.eq(e.getRun().bonusCoins - before, 4, "Resonator paid +4 coins on the correct Same");

    // It does NOT pay on a non-Same correct land.
    const e2 = game(null, null);
    const b2 = e2.getBoard();
    b2.top(0).value = 5;
    const n2 = e2.debug.setNextCard(9);
    n2.stickers = [{ type: "resonator" }];
    const before2 = e2.getRun().bonusCoins;
    e2.guess(0, "higher");                           // correct, but NOT a Same
    r.eq(e2.getRun().bonusCoins - before2, 0, "Resonator pays nothing on a non-Same land");
  }

  return r.summary();
}
