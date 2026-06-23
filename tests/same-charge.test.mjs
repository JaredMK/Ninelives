// The "Same" mechanic — Layer 1 (Same Charge). A correct Same banks 1 charge
// (max 1); it auto-fires as the LAST-priority backstop to save a pile from death
// (wrong direction OR lethal tie) — landing the killing card as the new pile
// card. Persists across deals via the campaign, resets per run.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, CampaignState } = loadGame();
  const r = makeRunner("same-charge.test.mjs");

  const deck = () => DeckManager.buildStandardDeck();
  const COLS = [3, 4, 3];
  const mk = (cfg) => {
    const e = GameEngine.create(deck(), 9, Object.assign({ cols: COLS }, cfg || {}));
    e.start(); e.startRun();
    return e;
  };

  // --- banking: a correct Same banks 1 charge; max 1 (no stacking) ----
  {
    const e = mk();
    r.ok(!e.sameCharge(), "starts empty (no charge seeded)");
    const b = e.getBoard();
    b.top(0).value = 7;
    e.debug.setNextCard(7);              // a tie
    e.guess(0, "same");                  // correct Same → bank
    r.ok(b.isActive(0), "the Same survived (a correct Same on a tie)");
    r.ok(e.sameCharge(), "a correct Same banked a charge");
    // A second correct Same does not stack (still exactly 1 / true).
    b.top(0).value = 4; e.debug.setNextCard(4);
    e.guess(0, "same");
    r.ok(e.sameCharge(), "a second correct Same keeps it charged (max 1, no stack)");
  }

  // --- the charge is SEEDED from runConfig (campaign persistence path) ---
  {
    const e = mk({ sameCharge: true });
    r.ok(e.sameCharge(), "charge seeded true from runConfig (carried across deals)");
  }

  // --- backstop: saves a WRONG-DIRECTION death; lands the card; spends it -
  {
    const e = mk({ sameCharge: true });
    const b = e.getBoard();
    b.top(0).value = 5;
    e.debug.setNextCard(9);              // draw 9
    e.guess(0, "lower");                 // 9 > 5 → "lower" is WRONG → would die
    r.ok(b.isActive(0), "Same Charge saved the pile from a wrong-direction death");
    r.eq(b.top(0).value, 9, "the would-be-killing card landed as the new pile card");
    r.ok(!e.sameCharge(), "the charge was spent by the save");
  }

  // --- backstop: saves a LETHAL TIE (same death path, uniform) ----------
  {
    const e = mk({ sameCharge: true });
    const b = e.getBoard();
    b.top(0).value = 6;
    e.debug.setNextCard(6);              // a tie
    e.guess(0, "higher");               // a tie on HIGHER is lethal → would die
    r.ok(b.isActive(0), "Same Charge saved the pile from a lethal tie");
    r.eq(b.top(0).value, 6, "the tying card landed as the new pile card");
    r.ok(!e.sameCharge(), "charge spent on the tie save too");
  }

  // --- last-priority: a Shield saves FIRST; Same Charge is NOT consumed --
  {
    const e = mk({ sameCharge: true });
    const b = e.getBoard();
    b.top(0).value = 5;
    b.top(0).heartsRemaining = 1;        // a Shield on the pile card
    e.debug.setNextCard(9);
    e.guess(0, "lower");                 // wrong → Shield (higher priority) absorbs it
    r.ok(b.isActive(0), "the pile survived");
    r.eq(b.top(0).heartsRemaining, 0, "the Shield was the one consumed (fired first)");
    r.ok(e.sameCharge(), "Same Charge is the LAST backstop — untouched while a Shield saved");
  }

  // --- only consumed when it actually saves (a correct guess doesn't) ---
  {
    const e = mk({ sameCharge: true });
    const b = e.getBoard();
    b.top(0).value = 5;
    e.debug.setNextCard(9);
    e.guess(0, "higher");               // 9 > 5 → correct, no death
    r.ok(b.isActive(0) && e.sameCharge(), "a correct guess leaves the charge banked (saved only on a would-be death)");
  }

  // --- campaign: persists across deals, resets per run, round-trips ------
  {
    const c = CampaignState.create();
    r.ok(!c.getSameCharge(), "fresh campaign: no Same Charge");
    c.setSameCharge(true);
    r.ok(c.getSameCharge(), "setSameCharge banks it");
    const wire = JSON.parse(JSON.stringify(c.serialize()));
    const c2 = CampaignState.create();
    c2.restore(wire);
    r.ok(c2.getSameCharge(), "Same Charge survives serialize/restore (persists across deals)");
    c.reset();
    r.ok(!c.getSameCharge(), "reset() clears the charge (resets per run)");
  }

  return r.summary();
}
