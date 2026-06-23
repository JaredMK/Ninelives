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

  return r.summary();
}
