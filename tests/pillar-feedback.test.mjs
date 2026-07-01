// Pillar-effect VISUAL FEEDBACK is presentation-only, but it rides on a new
// engine event ("pillar-fired") added at each live Pillar-effect site, plus a
// `col` field on the end-of-run payout lines. This guards that those signals
// fire with the right column/amount and — critically — that adding them did NOT
// change any gameplay value (coins paid, what fires, when).
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, PillarTypes } = loadGame();
  const r = makeRunner("pillar-feedback.test.mjs");

  const byEffect = (eff) => PillarTypes.all().find((t) => t.effect === eff);
  const spade = byEffect("suitBounty");        // now the ♥ Heart Bonus
  const streak = byEffect("streakSize");        // Streak Bank → Streak Size
  const club = byEffect("clubTribute");         // 8 Bury (♣ no-sticker)
  const guardian = byEffect("columnAllAlive");
  const specs = () => DeckManager.buildStandardDeck();
  const landHigher = (e, idx, v = 9) => { e.getBoard().top(idx).value = 5; e.debug.setNextCard(v); e.guess(idx, "higher"); };

  // --- Suit Bounty: emits pillar-fired with the column + the SAME coins it pays.
  {
    const e = GameEngine.create(specs(), 9, { cols: [3, 3, 3] });
    const fired = [];
    e.onEvent((t, p) => { if (t === "pillar-fired") fired.push(p); });
    e.start(); e.startRun([spade.id, null, null]);
    const before = e.getRun().bonusCoins;
    e.getBoard().top(0).value = 5;
    const d = e.debug.setNextCard(9); d.suit = spade.suit;   // a matching suit lands correctly
    e.guess(0, "higher");
    const f = fired.find((x) => x.effect === "suitBounty");
    r.ok(!!f, "Suit Bounty emits a pillar-fired event");
    r.eq(f && f.col, 0, "pillar-fired carries the firing column (0)");
    r.eq(f && f.amount, spade.value || 0, "pillar-fired amount = pillar.value");
    r.eq(e.getRun().bonusCoins - before, spade.value || 0, "coins paid are UNCHANGED (value untouched)");
  }

  // --- Streak Size: silent below threshold, pulses once at 3-in-a-row (amount 0).
  {
    const e = GameEngine.create(specs(), 9, { cols: [3, 3, 3] });
    const fired = [];
    e.onEvent((t, p) => { if (t === "pillar-fired" && p.effect === "streakSize") fired.push(p); });
    e.start(); e.startRun([streak.id, null, null]);
    landHigher(e, 0); landHigher(e, 0);
    r.eq(fired.length, 0, "Streak Size stays silent below its threshold");
    landHigher(e, 0);
    r.eq(fired.length, 1, "Streak Size pulses once at 3 in a row");
    r.eq(fired[0].col, 0, "Streak Size pillar-fired column is 0");
    r.eq(fired[0].amount, 0, "Streak Size is a size effect (pulse, amount 0)");
  }

  // --- 8 Bury (clubTribute): non-coin effect → pillar-fired with amount 0.
  {
    const e = GameEngine.create(specs(), 9, { cols: [3, 3, 3] });
    const fired = [];
    e.onEvent((t, p) => { if (t === "pillar-fired" && p.effect === "clubTribute") fired.push(p); });
    e.start(); e.startRun([club.id, null, null]);
    const deckBefore = e.getDeck().remaining();
    e.getBoard().top(0).value = 5;
    const d = e.debug.setNextCard(9); d.suit = "♣"; d.stickers = [];   // a sticker-free ♣ lands
    e.guess(0, "higher");
    r.eq(fired.length, 1, "8 Bury emits a pillar-fired event");
    r.eq(fired[0].amount, 0, "8 Bury is non-coin (amount 0)");
    r.ok(e.getDeck().remaining() < deckBefore, "8 Bury still buries (behaviour unchanged)");
  }

  // --- End-of-run scoring (Guardian): the payout line now carries `col`, with
  //     the amount unchanged.
  {
    const e = GameEngine.create(specs(), 3, { cols: [1, 1, 1] });
    e.start(); e.startRun([guardian.id, null, null]);
    const pp = e.pillarPayout();
    const line = pp.lines.find((l) => l.label === guardian.label);
    r.ok(!!line, "Guardian produces an end-of-run payout line");
    r.eq(line && line.col, 0, "payout line carries its column (0)");
    r.eq(line && line.amount, guardian.value, "payout amount = pillar.value (unchanged)");
  }

  return r.summary();
}
