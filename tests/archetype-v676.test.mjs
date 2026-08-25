// ARCHETYPE BATCH v6.76 — the 31 new items' web-engine behavior.
// Covers: the sameTolerance family (R1 — a tolerated Same is a FULL Same),
// the one-per-column family guard, the R3 full-deck composition conditions,
// shop-rolled values (R2 — offer-time roll, slot-riding, save/restore),
// purse gating (Pauper family), on-purchase effects (Rank Purge / Transmute),
// the new Base activations, Flat Purge / Purge Coupon pricing, On the House,
// and the Rank Flood Same-Power. Tunables are read LIVE from the registry —
// a data retune must not break these.
import { loadGame, makeRunner } from "./_harness.mjs";
import { readFileSync } from "node:fs";

export function run() {
  const G = loadGame();
  const { GameEngine, DeckManager, CampaignState, PillarTypes, BaseTypes, SamePowerTypes, ItemData, StickerTypes } = G;
  const r = makeRunner("archetype-v676.test.mjs");
  const COLS = [3, 4, 3];   // col 0 = piles 0-2, col 1 = piles 3-6, col 2 = piles 7-9
  const num = (def, k, fb) => (def && typeof def[k] === "number" ? def[k] : fb);

  /* ---- engine helpers ------------------------------------------------- */
  // A fresh engine; opts: { bases, samePower, pillarRolls, purse:{n}, comp:[cards] }.
  const game = (pillars, opts = {}) => {
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: COLS, samePower: opts.samePower || null });
    if (opts.purse) e.setPurseHook(() => opts.purse.n);
    if (opts.comp) e.setCompositionHook(() => opts.comp);
    e.start();
    e.startRun(pillars || [null, null, null], opts.bases || [null, null, null], undefined, opts.pillarRolls || null);
    return e;
  };
  const compCard = (rank, suit) => ({ currentRank: rank, suit, stickers: [] });
  // Set pile i's top rank/suit directly (test-side board rig).
  const rigTop = (e, i, value, suit) => {
    const t = e.getBoard().top(i);
    t.value = value;
    const rk = DeckManager.RANKS.find(x => x.value === value);
    if (rk) t.label = rk.label;
    if (suit) t.suit = suit;
    return t;
  };
  // Force the next drawn card's rank (+ suit), then guess. Returns the card.
  const drawAs = (e, value, suit) => {
    const real = e.debug.setNextCard(value);
    if (suit) real.suit = suit;
    return real;
  };
  // A CORRECT landing of `value`(+suit) on pile i (same only when values tie).
  const landCorrect = (e, i, value, suit) => {
    const top = e.getBoard().top(i).value;
    const real = drawAs(e, value, suit);
    e.guess(i, value === top ? "same" : (value > top ? "higher" : "lower"));
    return real;
  };
  // A WOULD-BE-WRONG landing of `value`(+suit) on pile i (wrong direction, or a
  // Same call on a non-tie). The guess is only survivable via an effect.
  const landWrong = (e, i, value, suit, guess) => {
    const top = e.getBoard().top(i).value;
    const real = drawAs(e, value, suit);
    e.guess(i, guess || (value > top ? "lower" : "higher"));
    return real;
  };
  const resolvedSpy = (e) => {
    const box = { last: null };
    e.onEvent((t, p) => { if (t === "resolved") box.last = p; });
    return box;
  };
  const jokerCard = (id) => ({ id, label: "★", value: 0, suit: "★", red: false, joker: true, stickers: [] });

  /* ---- registry / data contract ---------------------------------------- */
  {
    const tolIds = ["sameTolNear", "sameTolRoyal", "sameTolSum10", "sameTolSuit"];
    r.ok(tolIds.every(id => {
      const d = PillarTypes.get(id);
      return d && d.effect === "sameTolerance" && d.family === "sameTolerance" && typeof d.tol === "string";
    }), "all four sameTolerance pillars are registered with family + tol");
    r.ok(["absentSuitClubBury", "suitMajoritySafe", "purgeRank"]
      .every(id => PillarTypes.get(id) && PillarTypes.get(id).shopRoll), "the three shopRoll pillars carry the knob");
    r.ok(!PillarTypes.get("rankShield").shopRoll, "Rank Shield's rank is dynamic (v6.78) — no shop roll");
    const tm = BaseTypes.get("transmute");
    r.ok(tm && tm.shopRoll === "suit" && !tm.shopRoll2, "Transmute rolls only its suit (v6.78 — the rank is live most common)");
    r.ok(!!SamePowerTypes.get("rankFlood"), "Rank Flood same-power is registered");
  }

  /* ---- R1: sameTolerance — a tolerated Same is a FULL Same ------------- */
  const tolCase = (id, topV, drawnV, suit, label) => {
    const e = game([id, null, null], { samePower: "samePeek" });
    const spy = resolvedSpy(e);
    rigTop(e, 0, topV, "♥");
    r.ok(!e.sameCharge(), label + ": shield starts empty");
    landWrong(e, 0, drawnV, suit || "♦", "same");
    const p = spy.last;
    r.ok(p && p.correct === true && p.guess === "same", label + ": the would-be-wrong Same survives (resolved payload correct — this is what bumps correctSames)");
    r.ok(e.getBoard().isActive(0), label + ": the pile lives");
    r.ok(e.sameCharge(), label + ": the survived Same charges the Same Shield");
    r.ok(e.getRun().revealNextActive === true, label + ": the survived Same fires the equipped Same-Power");
  };
  tolCase("sameTolNear", 5, 6, null, "Close Call (±1)");
  tolCase("sameTolRoyal", 11, 12, null, "Royal Pair (royal on royal)");
  tolCase("sameTolSum10", 4, 6, null, "Perfect Ten (sum 10)");
  tolCase("sameTolSuit", 5, 9, "♥", "Suit Match (same suit)");
  {
    // Negatives: a relation OUTSIDE the tolerance still kills the pile.
    const neg = (id, topV, drawnV, suit, label) => {
      const e = game([id, null, null]);
      rigTop(e, 0, topV, "♥");
      landWrong(e, 0, drawnV, suit || "♦", "same");
      r.ok(!e.getBoard().isActive(0), label + ": an untolerated Same still kills");
    };
    neg("sameTolNear", 5, 8, null, "Close Call");
    neg("sameTolRoyal", 11, 9, null, "Royal Pair");
    neg("sameTolSum10", 4, 7, null, "Perfect Ten");
    neg("sameTolSuit", 5, 9, null, "Suit Match");
  }
  {
    // Suit Match ALSO makes NON-Same guesses safe on a same-suit landing; the
    // other three tolerate Same calls only.
    const e = game(["sameTolSuit", null, null]);
    rigTop(e, 0, 5, "♥");
    landWrong(e, 0, 3, "♥", "higher");   // 3 < 5 — a wrong "higher", same suit
    r.ok(e.getBoard().isActive(0), "Suit Match: a wrong directional call on a same-suit landing is also safe");
    const e2 = game(["sameTolNear", null, null]);
    rigTop(e2, 0, 5, "♥");
    landWrong(e2, 0, 6, "♦", "lower");   // ±1 but NOT a Same call → no tolerance
    r.ok(!e2.getBoard().isActive(0), "Close Call: a directional call on a ±1 card is NOT tolerated");
  }

  /* ---- the one-per-column family guard (engine-side placement) --------- */
  {
    const c = CampaignState.create();
    c.debugGrantPillar("sameTolNear");
    r.ok(c.placePillar("sameTolNear", 0), "family: first tolerance pillar places");
    c.debugGrantPillar("sameTolRoyal");
    r.ok(!c.placePillar("sameTolRoyal", 0), "family: a SECOND tolerance pillar on the same column is rejected");
    r.ok(c.placePillar("sameTolRoyal", 1), "family: another column still takes it");
    c.debugGrantPillar("prime");
    r.ok(c.placePillar("prime", 0), "family: a non-family pillar displaces normally");
    c.unplacePillar(0);
    c.debugGrantPillar("sameTolSum10");
    r.ok(c.placePillar("sameTolSum10", 0), "family: after pickup the column takes a tolerance pillar again");
    // The buy-and-place overwrite path honors the guard too.
    c.addCoins(1000);
    r.ok(!c.buyPillar("sameTolSuit", 1), "family: buyPillar overwrite onto a tolerance column is rejected");
  }

  /* ---- R3 composition conditions --------------------------------------- */
  {
    // Empty Ranks: only ranks 5 and 9 exist → 11 zero-copy ranks.
    const def = PillarTypes.get("zeroRanksBury");
    const e = game(["zeroRanksBury", null, null], { comp: [compCard(5, "♥"), compCard(5, "♦"), compCard(9, "♥"), compCard(9, "♣")] });
    const before = e.getBoard().piles[0].cards.length;
    const deckBefore = e.getDeck().remaining();
    landCorrect(e, 0, e.getBoard().top(0).value === 9 ? 6 : 9, "♣");
    const buried = e.getBoard().piles[0].cards.length - before - 1;   // minus the landed card
    r.eq(buried, 11, "Empty Ranks buries 1 per zero-copy rank (11 of 13)");
    r.eq(deckBefore - e.getDeck().remaining(), buried + 1, "Empty Ranks buries come out of the deck");
    r.ok(num(def, "price", 0) > 0, "Empty Ranks def readable (tunables live)");
    // Empty full deck → inert (never a 13-card mega-bury).
    const e2 = game(["zeroRanksBury", null, null], { comp: [] });
    const b2 = e2.getBoard().piles[0].cards.length;
    landCorrect(e2, 0, e2.getBoard().top(0).value === 4 ? 7 : 4, "♣");
    r.eq(e2.getBoard().piles[0].cards.length - b2, 1, "Empty Ranks: an empty full deck buries nothing");
  }
  {
    // Crazy Eights: 8s the most-copied rank → col 0 piles start at SIZE 8.
    const comp = [compCard(8, "♥"), compCard(8, "♦"), compCard(8, "♣"), compCard(5, "♥"), compCard(9, "♥")];
    const e = game(["eightStart", null, null], { comp });
    r.ok([0, 1, 2].every(i => e.getBoard().pileSize(i) === 8), "Crazy Eights: the column's piles start at pile size 8");
    r.eq(e.getBoard().pileSize(3), 1, "Crazy Eights: other columns stay size 1");
    // Ties break to the LOWEST rank: 8s tied with 9s → still fires.
    const tie = [compCard(8, "♥"), compCard(8, "♦"), compCard(9, "♥"), compCard(9, "♦"), compCard(5, "♠")];
    const eT = game(["eightStart", null, null], { comp: tie });
    r.eq(eT.getBoard().pileSize(0), 8, "Crazy Eights: a most-copied tie breaks to the lowest rank (8)");
    // 7s dominate → no fire.
    const no = [compCard(7, "♥"), compCard(7, "♦"), compCard(7, "♣"), compCard(8, "♥")];
    const eN = game(["eightStart", null, null], { comp: no });
    r.eq(eN.getBoard().pileSize(0), 1, "Crazy Eights: 8s not most-copied → no size bonus");
  }
  {
    // Royal Sanctuary: no 2s in the full deck → a royal landing is safe on any call.
    const noTwos = [compCard(5, "♥"), compCard(6, "♦"), compCard(9, "♣")];
    const e = game(["royalSanctuary", null, null], { comp: noTwos });
    rigTop(e, 0, 5, "♥");
    landWrong(e, 0, 13, "♦");   // K over a 5 — a wrong "lower"
    r.ok(e.getBoard().isActive(0), "Royal Sanctuary: a royal is safe with no 2s in the full deck");
    const withTwos = noTwos.concat([compCard(2, "♠")]);
    const e2 = game(["royalSanctuary", null, null], { comp: withTwos });
    rigTop(e2, 0, 5, "♥");
    landWrong(e2, 0, 13, "♦");
    r.ok(!e2.getBoard().isActive(0), "Royal Sanctuary: a 2 anywhere in the full deck turns it off");
    // Non-royals are not sheltered.
    const e3 = game(["royalSanctuary", null, null], { comp: noTwos });
    rigTop(e3, 0, 5, "♥");
    landWrong(e3, 0, 10, "♦");
    r.ok(!e3.getBoard().isActive(0), "Royal Sanctuary: a non-royal landing still dies");
  }
  {
    // Void Tribute: the shop-rolled suit absent from the full deck → ♣ buries.
    const bc = num(PillarTypes.get("absentSuitClubBury"), "buryCount", 2);
    const noSpades = [compCard(5, "♥"), compCard(6, "♥"), compCard(9, "♦")];
    const e = game(["absentSuitClubBury", null, null], { comp: noSpades, pillarRolls: [{ roll: "♠", roll2: null }, null, null] });
    const before = e.getBoard().piles[0].cards.length;
    landCorrect(e, 0, e.getBoard().top(0).value === 4 ? 7 : 4, "♣");
    r.eq(e.getBoard().piles[0].cards.length - before, 1 + bc, "Void Tribute: zero of the rolled suit → the ♣ landing buries buryCount");
    const withSpade = noSpades.concat([compCard(3, "♠")]);
    const e2 = game(["absentSuitClubBury", null, null], { comp: withSpade, pillarRolls: [{ roll: "♠", roll2: null }, null, null] });
    const b2 = e2.getBoard().piles[0].cards.length;
    landCorrect(e2, 0, e2.getBoard().top(0).value === 4 ? 7 : 4, "♣");
    r.eq(e2.getBoard().piles[0].cards.length - b2, 1, "Void Tribute: one copy of the rolled suit turns it off");
  }
  {
    // Majority Rule: ≥50% of the full deck is the rolled suit → that suit safe.
    const rolls = [{ roll: "♥", roll2: null }, null, null];
    const majority = [compCard(5, "♥"), compCard(6, "♥"), compCard(9, "♥"), compCard(4, "♣"), compCard(7, "♣")];   // 3/5
    const e = game(["suitMajoritySafe", null, null], { comp: majority, pillarRolls: rolls });
    rigTop(e, 0, 9, "♣");
    landWrong(e, 0, 4, "♥");   // a wrong-direction ♥ landing
    r.ok(e.getBoard().isActive(0), "Majority Rule: the majority suit lands safe (3/5)");
    const half = [compCard(5, "♥"), compCard(6, "♥"), compCard(4, "♣"), compCard(7, "♣")];   // exactly 50%
    const eH = game(["suitMajoritySafe", null, null], { comp: half, pillarRolls: rolls });
    rigTop(eH, 0, 9, "♣");
    landWrong(eH, 0, 4, "♥");
    r.ok(eH.getBoard().isActive(0), "Majority Rule: exactly half still counts (≥50%)");
    const minority = [compCard(5, "♥"), compCard(6, "♣"), compCard(4, "♣"), compCard(7, "♣")];   // 1/4
    const eM = game(["suitMajoritySafe", null, null], { comp: minority, pillarRolls: rolls });
    rigTop(eM, 0, 9, "♣");
    landWrong(eM, 0, 4, "♥");
    r.ok(!eM.getBoard().isActive(0), "Majority Rule: below half → no safety");
  }
  {
    // Diamond Echo: +1 pile size per duplicate of the landed rank (copies past 1).
    const comp = [compCard(9, "♥"), compCard(9, "♦"), compCard(9, "♣"), compCard(5, "♥")];
    const e = game(["diamondDupeSize", null, null], { comp });
    rigTop(e, 0, 4, "♠");
    const s0 = e.getBoard().pileSize(0);
    landCorrect(e, 0, 9, "♦");
    r.eq(e.getBoard().pileSize(0) - s0, 1 + 2, "Diamond Echo: three 9s in the deck → +2 size on a 9♦ landing");
    const e2 = game(["diamondDupeSize", null, null], { comp });
    rigTop(e2, 0, 4, "♠");
    const s1 = e2.getBoard().pileSize(0);
    landCorrect(e2, 0, 5, "♦");   // a singleton rank → no duplicates
    r.eq(e2.getBoard().pileSize(0) - s1, 1, "Diamond Echo: a singleton rank adds nothing");
  }

  /* ---- shields (rankShield / suitShieldDaily) --------------------------- */
  {
    // RANK SHIELD (dynamic, v6.78): at Start Run the shield reads the FULL
    // deck and protects its most common rank; the incumbent (pillarRolls)
    // keeps the shield on a tie. A standard 52 ties every rank at 4 copies,
    // so the injected incumbent 9 holds.
    const e = game(["rankShield", null, null], { pillarRolls: [{ roll: 9, roll2: null }, null, null] });
    r.eq(e.getRun().rankShieldRank, 9, "Rank Shield: a full tie keeps the incumbent");
    rigTop(e, 0, 5, "♥");
    landWrong(e, 0, 9, "♦");   // the protected rank — safe on any call
    r.ok(e.getBoard().isActive(0), "Rank Shield: the protected (most common) rank lands safe");
    const e2 = game(["rankShield", null, null], { pillarRolls: [{ roll: 9, roll2: null }, null, null] });
    rigTop(e2, 0, 5, "♥");
    landWrong(e2, 0, 10, "♦");
    r.ok(!e2.getBoard().isActive(0), "Rank Shield: any other rank still dies");
    // STRICT SURPASS: a composition where 7s dominate replaces the incumbent.
    const comp = [compCard(7, "♥"), compCard(7, "♦"), compCard(7, "♣"), compCard(9, "♠")];
    const e3 = game(["rankShield", null, null], { comp, pillarRolls: [{ roll: 9, roll2: null }, null, null] });
    r.eq(e3.getRun().rankShieldRank, 7, "Rank Shield: strictly surpassed → the new leader takes the shield");
    rigTop(e3, 0, 5, "♥");
    landWrong(e3, 0, 7, "♦");
    r.ok(e3.getBoard().isActive(0), "Rank Shield: the new leader lands safe");
    // The campaign adopts the pick as the next incumbent.
    const c = CampaignState.create();
    c.adoptRankShieldPick(7);
    const blob = JSON.parse(JSON.stringify(c.serialize()));
    const c2 = CampaignState.create();
    r.ok(c2.restore(blob), "Rank Shield: the incumbent save restores");
    r.ok(c2.getShopRoll("rankShield") && c2.getShopRoll("rankShield").roll === 7, "Rank Shield: the incumbent survives save/restore");
  }
  {
    const e = game(["suitShield", null, null]);
    const suit = e.getRun().suitShieldSuits[0];
    r.ok(["♥", "♦", "♣", "♠"].includes(suit), "Daily Suit: a suit is rolled at deal start and rides the run state");
    rigTop(e, 0, 5, "♣");
    const other = ["♥", "♦", "♣", "♠"].find(s => s !== suit);
    landWrong(e, 0, 9, suit);
    r.ok(e.getBoard().isActive(0), "Daily Suit: the rolled suit lands safe");
    const e2 = game(["suitShield", null, null]);
    const suit2 = e2.getRun().suitShieldSuits[0];
    const off = ["♥", "♦", "♣", "♠"].find(s => s !== suit2);
    rigTop(e2, 0, 5, suit2);
    landWrong(e2, 0, 9, off);
    r.ok(!e2.getBoard().isActive(0), "Daily Suit: a non-rolled suit still dies");
    // Redeal re-rolls: a fresh engine start (new seed) rolls again into a valid suit.
    e.start(123456789);
    e.startRun(["suitShield", null, null], [null, null, null], undefined, null);
    r.ok(["♥", "♦", "♣", "♠"].includes(e.getRun().suitShieldSuits[0]), "Daily Suit: a redeal re-rolls the suit");
  }

  /* ---- live pillars: Eight Ball / Curse Harvest / Club Thin ------------ */
  {
    const e = game(["eightPeek", null, null]);
    r.ok(!e.getRun().revealNextActive, "Eight Ball: no peek before an 8 lands");
    landCorrect(e, 0, 8, "♠");
    r.ok(e.getRun().revealNextActive === true, "Eight Ball: an 8 landing peeks the next card");
    const e2 = game(["eightPeek", null, null]);
    landCorrect(e2, 0, 9, "♠");
    r.ok(!e2.getRun().revealNextActive, "Eight Ball: a non-8 does not peek");
  }
  {
    const dig = num(PillarTypes.get("curseHarvest"), "digCount", 1);
    const e = game(["curseHarvest", null, null]);
    const top = e.getBoard().top(0).value;
    const real = drawAs(e, top === 7 ? 9 : 7, "♠");
    real.stickers.push({ type: "leech" });   // a CURSED sticker (items.js cursed: true)
    const before = e.getBoard().piles[0].cards.length;
    e.guess(0, (top === 7 ? 9 : 7) > top ? "higher" : "lower");
    r.eq(e.getBoard().piles[0].cards.length - before, 1 + dig, "Curse Harvest: a cursed landing buries digCount");
    r.ok(e.getRun().revealNextActive === true, "Curse Harvest: …then peeks the next card");
    const e2 = game(["curseHarvest", null, null]);
    const b2 = e2.getBoard().piles[0].cards.length;
    landCorrect(e2, 0, e2.getBoard().top(0).value === 6 ? 8 : 6, "♠");
    r.eq(e2.getBoard().piles[0].cards.length - b2, 1, "Curse Harvest: a clean card triggers nothing");
  }
  {
    const def = PillarTypes.get("clubThin");
    const per = num(def, "per", 25), dig = num(def, "digCount", 1);
    const e = game(["clubThin", null, null]);
    const expected = Math.floor(e.getDeck().remaining() / per) * dig;   // 42 left after the deal
    const before = e.getBoard().piles[0].cards.length;
    landCorrect(e, 0, e.getBoard().top(0).value === 4 ? 7 : 4, "♣");
    r.eq(e.getBoard().piles[0].cards.length - before, 1 + expected, "Club Thin buries floor(remaining/per) × digCount");
  }

  /* ---- Pauper family: purse gating (live, exclusive ceiling) ------------ */
  {
    const pay = num(PillarTypes.get("pauperHeart"), "value", 3);
    const purse = { n: 9 };
    const e = game(["pauperHeart", null, null], { purse });
    const b0 = e.getRun().bonusCoins;
    landCorrect(e, 0, e.getBoard().top(0).value === 4 ? 7 : 4, "♥");
    r.eq(e.getRun().bonusCoins - b0, pay, "Pauper's Heart pays under 10 coins");
    purse.n = 10;
    const b1 = e.getRun().bonusCoins;
    landCorrect(e, 0, e.getBoard().top(0).value === 4 ? 7 : 4, "♥");
    r.eq(e.getRun().bonusCoins - b1, 0, "Pauper's Heart sleeps AT 10 coins (exclusive ceiling)");
  }
  {
    const purse = { n: 0 };
    const e = game(["pauperClub", null, null], { purse });
    const before = e.getBoard().piles[0].cards.length;
    landCorrect(e, 0, e.getBoard().top(0).value === 4 ? 7 : 4, "♣");
    r.eq(e.getBoard().piles[0].cards.length - before, 1 + num(PillarTypes.get("pauperClub"), "digCount", 1), "Pauper's Club buries while broke");
    purse.n = 25;
    const b2 = e.getBoard().piles[0].cards.length;
    landCorrect(e, 0, e.getBoard().top(0).value === 4 ? 7 : 4, "♣");
    r.eq(e.getBoard().piles[0].cards.length - b2, 1, "Pauper's Club sleeps at/above the ceiling");
  }
  {
    const purse = { n: 3 };
    const e = game(["pauperSpade", null, null], { purse });
    landCorrect(e, 0, e.getBoard().top(0).value === 4 ? 7 : 4, "♠");
    r.ok(e.getRun().tellPiles.has(0), "Pauper's Spade arms a tell while broke");
    r.ok(e.pileHint(0) !== null, "Pauper's Spade's tell reads the real next card");
    const e2 = game(["pauperSpade", null, null], { purse: { n: 10 } });
    landCorrect(e2, 0, e2.getBoard().top(0).value === 4 ? 7 : 4, "♠");
    r.ok(!e2.getRun().tellPiles.has(0), "Pauper's Spade sleeps at the ceiling");
  }
  {
    // Pauper's Diamond: a ♦ landing ANYWHERE counts value (2) toward pile size.
    const val = num(PillarTypes.get("pauperDiamond"), "value", 2);
    const purse = { n: 5 };
    const e = game(["pauperDiamond", null, null], { purse });
    const s0 = e.getBoard().pileSize(5);   // col 1 — board-wide, not just its column
    landCorrect(e, 5, e.getBoard().top(5).value === 4 ? 7 : 4, "♦");
    r.eq(e.getBoard().pileSize(5) - s0, val, "Pauper's Diamond: a ♦ landing board-wide counts +" + val + " while broke");
    purse.n = 40;
    const s1 = e.getBoard().pileSize(5);
    landCorrect(e, 5, e.getBoard().top(5).value === 4 ? 7 : 4, "♦");
    r.eq(e.getBoard().pileSize(5) - s1, 1, "Pauper's Diamond: at/above the ceiling a ♦ counts +1 again");
  }
  {
    // Diamond Lifeline: only while one of ITS column's piles is size 1.
    const val = num(PillarTypes.get("sizeOneDiamonds"), "value", 2);
    const e = game(["sizeOneDiamonds", null, null]);
    const s0 = e.getBoard().pileSize(6);   // col 1 landing — board-wide
    landCorrect(e, 6, e.getBoard().top(6).value === 4 ? 7 : 4, "♦");
    r.eq(e.getBoard().pileSize(6) - s0, val, "Diamond Lifeline: a ♦ counts +" + val + " while its column holds a size-1 pile");
    const e2 = game(["sizeOneDiamonds", null, null]);
    for (const i of [0, 1, 2]) e2.getBoard().addSizeBonus(i, 1);   // lift col 0 off size 1
    const s1 = e2.getBoard().pileSize(6);
    landCorrect(e2, 6, e2.getBoard().top(6).value === 4 ? 7 : 4, "♦");
    r.eq(e2.getBoard().pileSize(6) - s1, 1, "Diamond Lifeline: no size-1 pile in its column → a ♦ counts +1");
  }

  /* ---- Rank Flood (same-power) ------------------------------------------ */
  {
    const e = game([null, null, null], { samePower: "rankFlood" });
    let flood = null;
    e.onEvent((t, p) => { if (t === "same-power") flood = p; });
    e.debug.forceSame(0);
    const v = e.getBoard().top(0).value;
    const b = e.getBoard();
    let allMatch = true;
    for (let i = 0; i < b.size; i++) if (b.isActive(i) && b.top(i).value !== v) allMatch = false;
    r.ok(allMatch, "Rank Flood: a correct Same sets every alive pile's top to the called rank");
    r.ok(flood && Array.isArray(flood.valueApplied) && flood.valueApplied.length > 0, "Rank Flood: the re-ranks ride valueApplied (durable write-back)");
    // Joker drawn → the ranked side (the pile's top) dictates the flood.
    const e2 = game([null, null, null], { samePower: "rankFlood" });
    const topV = e2.getBoard().top(1).value;
    e2.getDeck()._setNextCard(jokerCard(9001));
    e2.guess(1, "same");   // a Joker is never wrong — a full correct Same
    let m2 = true;
    for (let i = 0; i < e2.getBoard().size; i++) {
      const t = e2.getBoard().top(i);
      if (e2.getBoard().isActive(i) && !t.joker && t.value !== topV) m2 = false;
    }
    r.ok(m2, "Rank Flood: a Joker on the drawn side floods by the ranked card");
    // Joker-on-Joker → Aces.
    const e3 = game([null, null, null], { samePower: "rankFlood" });
    const p0 = e3.getBoard().piles[0];
    p0.cards[p0.cards.length - 1] = jokerCard(9002);
    e3.getDeck()._setNextCard(jokerCard(9003));
    e3.guess(0, "same");
    let m3 = true;
    for (let i = 0; i < e3.getBoard().size; i++) {
      const t = e3.getBoard().top(i);
      if (e3.getBoard().isActive(i) && !t.joker && t.value !== 14) m3 = false;
    }
    r.ok(m3, "Rank Flood: Joker-on-Joker floods Aces");
  }

  /* ---- R2: shop-rolled values — roll, ride, lock, persist -------------- */
  const findSlot = (c, pred) => {
    c.addCoins(1000000);
    if (!c.getStoreOffer()) c.openStore();
    for (let tries = 0; tries < 6000; tries++) {
      const offer = c.getStoreOffer();
      for (let i = 0; i < offer.slots.length; i++) {
        const s = offer.slots[i];
        if (!s || (s.kind !== "pillar" && s.kind !== "base")) continue;
        const def = (s.kind === "pillar" ? PillarTypes : BaseTypes).get(s.id);
        if (def && def.shopRoll && (!pred || pred(s, def))) return { slot: i, s, def };
      }
      c.rerollStore();
    }
    return null;
  };
  {
    // RANK SHIELD left the shopRoll system in v6.78 (its rank is dynamic,
    // per deal). The registry pins it, and a suit-roll item (Void Tribute)
    // exercises the generic roll→ride→lock→persist path instead.
    r.ok(!PillarTypes.get("rankShield").shopRoll, "shop-roll: Rank Shield no longer rolls at the shop");
    const c = CampaignState.create();
    const hit = findSlot(c, (s, def) => s.kind === "pillar" && def.id === "absentSuitClubBury");
    r.ok(!!hit, "shop-roll: a Void Tribute eventually shows on a shelf");
    if (hit) {
      r.ok(typeof hit.s.shopRolled === "string", "shop-roll: the suit is rolled at OFFER time and rides the slot");
      r.ok(c.getShopRoll("absentSuitClubBury") && c.getShopRoll("absentSuitClubBury").roll === hit.s.shopRolled, "shop-roll: the value locks into the campaign map");
      const roll = hit.s.shopRolled;
      const again = findSlot(c, (s, def) => s.kind === "pillar" && def.id === "absentSuitClubBury");
      r.ok(again && again.s.shopRolled === roll, "shop-roll: the lock holds all climb (no re-roll on later shelves)");
      const blob = JSON.parse(JSON.stringify(c.serialize()));
      const c2 = CampaignState.create();
      r.ok(c2.restore(blob), "shop-roll: the save restores");
      r.ok(c2.getShopRoll("absentSuitClubBury") && c2.getShopRoll("absentSuitClubBury").roll === roll, "shop-roll: the locked value survives save/restore");
      const price = c.priceOfMixed(hit.slot);
      const coinsBefore = c.getCoins();
      const res = c.buyMixedSlot(hit.slot, Math.random);
      r.ok(res.ok && c.getCoins() === coinsBefore - price, "shop-roll: the purchase charges the shelf price");
      r.ok(c.placePillar("absentSuitClubBury", 2), "shop-roll: the bought pillar places");
      const colRolls = c.getColumnPillarRolls();
      r.ok(colRolls[2] && colRolls[2].roll === roll, "shop-roll: the rolled value transfers to the equipped item");
    }
  }
  {
    // Transmute rolls ONE knob now (v6.78): the suit. The rank is the live
    // most common at buy time.
    const c = CampaignState.create();
    const hit = findSlot(c, (s, def) => s.kind === "base" && def.id === "transmute");
    r.ok(!!hit && typeof hit.s.shopRolled === "string" && hit.s.shopRolled2 == null, "Transmute: only the suit rolls at offer time");
  }

  /* ---- on-purchase effects (Rank Purge / Transmute) ---------------------- */
  {
    const c = CampaignState.create();
    const hit = findSlot(c, (s, def) => s.kind === "pillar" && def.id === "purgeRank");
    r.ok(!!hit, "Rank Purge: appears on a shelf with its rolled rank");
    const rank = hit.s.shopRolled;
    const before = c.getRunDeck().filter(x => x.currentRank === rank).length;
    r.ok(before > 0, "Rank Purge: the fresh deck holds cards of the rolled rank");
    const removalsBefore = c.removalPrice();   // ladder position proxy
    const res = c.buyMixedSlot(hit.slot, Math.random);
    r.ok(res.ok && res.purgedCount === before, "Rank Purge: every card of the rolled rank leaves the deck at buy time");
    r.eq(c.getRunDeck().filter(x => x.currentRank === rank).length, 0, "Rank Purge: none remain");
    r.eq(c.removalPrice(), removalsBefore, "Rank Purge: the Removal ladder is untouched (the purchase price covers it)");
    // Mid-store save/restore keeps the purge (and the lock).
    const blob = JSON.parse(JSON.stringify(c.serialize()));
    const c2 = CampaignState.create();
    c2.restore(blob);
    r.eq(c2.getRunDeck().filter(x => x.currentRank === rank).length, 0, "Rank Purge: the purge survives a mid-store save/restore");
    r.ok(c2.getShopRoll("purgeRank") && c2.getShopRoll("purgeRank").roll === rank, "Rank Purge: the roll survives too");
  }
  {
    const c = CampaignState.create();
    const hit = findSlot(c, (s, def) => s.kind === "base" && def.id === "transmute");
    const suit = hit.s.shopRolled;
    // v6.78: the target rank is the LIVE most common (ties → lowest) at the
    // instant of purchase — compute the same way the engine does.
    const counts = {};
    for (const x of c.getRunDeck()) if (!x.joker && !x.blank) counts[x.currentRank] = (counts[x.currentRank] || 0) + 1;
    let rank = null;
    for (let v = 2; v <= 14; v++) if ((counts[v] || 0) > (rank == null ? 0 : counts[rank])) rank = v;
    const blob0 = JSON.parse(JSON.stringify(c.serialize()));
    const res = c.buyMixedSlot(hit.slot, Math.random);
    r.ok(res.ok && res.transmuted && res.transmuted.rank === rank && res.transmuted.suit === suit, "Transmute: fires at buy time on the LIVE most common rank + the rolled suit");
    r.ok(c.getRunDeck().filter(x => x.currentRank === rank).every(x => x.suit === suit), "Transmute: every card of the most common rank is now the rolled suit");
    // Restore of the PRE-buy save replays the identical recolor (the deck —
    // and so the most-common read — is part of the save).
    const c2 = CampaignState.create();
    c2.restore(blob0);
    const res2 = c2.buyMixedSlot(hit.slot, Math.random);
    r.ok(res2.ok && res2.transmuted && res2.transmuted.rank === rank, "Transmute: a restored buy targets the same rank");
  }

  /* ---- Flat Purge / Purge Coupon pricing -------------------------------- */
  {
    const rm = ItemData.store.removal;
    const c = CampaignState.create();
    c.addCoins(1000);
    r.eq(c.removalPrice(), rm.price, "Flat Purge suite: the ladder starts at the base price");
    c.buyRemoval(c.getRunDeck()[0].id);
    c.buyRemoval(c.getRunDeck()[0].id);
    r.eq(c.removalPrice(), rm.price + 2 * rm.priceStep, "the Purge ladder climbs per removal");
    // Purge Coupon: −value per activation, floored at min, permanent for the climb.
    const coupon = BaseTypes.get("purgeDiscount");
    c.addPurgeDiscount(coupon.value);
    r.eq(c.removalPrice(), rm.price + 2 * rm.priceStep - coupon.value, "Purge Coupon: the activation cut applies to the ladder");
    c.addPurgeDiscount(coupon.value * 10);   // far past the floor
    r.eq(c.removalPrice(), coupon.min, "Purge Coupon: the price floors at the coupon's min");
    // Persistence.
    const blob = JSON.parse(JSON.stringify(c.serialize()));
    const c2 = CampaignState.create();
    c2.restore(blob);
    r.eq(c2.removalPrice(), coupon.min, "Purge Coupon: the cut survives save/restore");
    // Flat Purge OVERRIDES everything while equipped.
    const c3 = CampaignState.create();
    c3.addCoins(1000);
    c3.buyRemoval(c3.getRunDeck()[0].id);
    c3.addPurgeDiscount(1);
    const flat = PillarTypes.get("purgeFlatFive");
    c3.debugGrantPillar("purgeFlatFive");
    c3.placePillar("purgeFlatFive", 0);
    r.eq(c3.removalPrice(), num(flat, "value", 5), "Flat Purge: the Purge price is always the pillar's value, ladder and coupon ignored");
  }

  /* ---- On the House (firstFree) ------------------------------------------ */
  {
    const c = CampaignState.create();
    c.spendCoins(c.getCoins());   // drain to 0
    c.openStore();
    r.ok(!c.canReroll(), "On the House: a broke shelf can't restock without the pillar");
    const c2 = CampaignState.create();
    c2.spendCoins(c2.getCoins());
    c2.debugGrantPillar("firstFree");
    c2.placePillar("firstFree", 0);
    c2.openStore();
    r.ok(c2.getStoreOffer().freeReroll === true && c2.storeRerollCost() === 0, "On the House: the first restock of the store is free");
    r.ok(c2.rerollStore(), "On the House: the free restock works with 0 coins");
    r.ok(!c2.canReroll(), "On the House: the SECOND restock is back on the ladder");
    // The freebie flag rides the (persisted) offer.
    const c3 = CampaignState.create();
    c3.spendCoins(c3.getCoins());
    c3.debugGrantPillar("firstFree");
    c3.placePillar("firstFree", 0);
    c3.openStore();
    const blob = JSON.parse(JSON.stringify(c3.serialize()));
    const c4 = CampaignState.create();
    c4.restore(blob);
    r.ok(c4.storeRerollCost() === 0 && c4.rerollStore(), "On the House: the free restock survives save/restore");
  }

  /* ---- Base activations --------------------------------------------------- */
  {
    // Purge Coupon (engine side): always activatable while charged, hands the
    // cut to the campaign via the result.
    const coupon = BaseTypes.get("purgeDiscount");
    const e = game(null, { bases: ["purgeDiscount", null, null] });
    r.ok(e.baseAvailable(0), "Purge Coupon: activatable while charged");
    const res = e.baseActivate(0);
    r.ok(res && res.purgeDiscount === coupon.value && res.purgeFloor === coupon.min, "Purge Coupon: the activation reports value + floor for the campaign");
    r.ok(!e.baseAvailable(0), "Purge Coupon: spent for the deal");
  }
  {
    // Transmute is NEVER available in a deal.
    const e = game(null, { bases: ["transmute", null, null] });
    r.ok(!e.baseAvailable(0), "Transmute: never available in-deal (on-purchase only)");
    r.eq(e.baseActivate(0), null, "Transmute: baseActivate refuses in-deal");
  }
  {
    // Sacrifice: purge the chosen pile's top + the pile dies.
    const e = game(null, { bases: ["sacrifice", null, null] });
    r.ok(e.baseAvailable(0), "Sacrifice: available with an alive pile");
    r.eq(e.baseActivate(0), null, "Sacrifice: a target pile is required");
    const topId = e.getBoard().top(1).id;
    const res = e.baseActivate(0, 1);
    r.ok(res && res.purgedCardId === topId, "Sacrifice: the chosen pile's top card is marked for purge");
    r.ok(!e.getBoard().isActive(1), "Sacrifice: the pile dies");
    r.ok(!e.baseAvailable(0), "Sacrifice: spent for the deal");
    // …and the campaign-side purge path (what the base-fired handler runs).
    const c = CampaignState.create();
    const victim = c.getRunDeck()[0];
    const n0 = c.getRunDeck().length;
    r.ok(c.removeDeckCard(victim.id) && c.getRunDeck().length === n0 - 1, "Sacrifice: removeDeckCard purges permanently");
  }
  {
    // Devil's Deal: doubles the deal bonus, curses a top in the column.
    const e = game(null, { bases: ["devilsDeal", null, null] });
    e.getRun().bonusCoins = 6;   // stand-in for bonuses earned this deal
    const res = e.baseActivate(0, 1);   // optional target honored
    r.ok(res && res.doubled === 6 && e.getRun().bonusCoins === 12, "Devil's Deal: the deal's bonus tally doubles");
    r.ok(res.curseApplied && res.curseApplied.pileIndex === 1, "Devil's Deal: the curse lands on the chosen top");
    const ct = StickerTypes.get(res.curseApplied.typeId);
    r.ok(ct && ct.cursed === true, "Devil's Deal: the applied sticker is a real curse");
    r.ok(e.getBoard().top(1).stickers.some(s => s.type === res.curseApplied.typeId), "Devil's Deal: the curse rides the live card");
    // No target → a seeded in-column pick curses some top (v6.76: the Deal
    // picks, never the player — like Kamikaze's random pile).
    const e2 = game(null, { bases: ["devilsDeal", null, null] });
    const res2 = e2.baseActivate(0);
    r.ok(res2 && res2.curseApplied && [0, 1, 2].includes(res2.curseApplied.pileIndex), "Devil's Deal: untargeted → a seeded in-column pick");
  }
  {
    // Cleanse: strips every curse off the column's tops.
    const e = game(null, { bases: ["cleanseColumn", null, null] });
    r.ok(!e.baseAvailable(0), "Cleanse: nothing to cleanse → unavailable");
    e.getBoard().top(0).stickers.push({ type: "leech" });
    e.getBoard().top(0).stickers.push({ type: "mute" });
    e.getBoard().top(1).stickers.push({ type: "trapdoor" });
    e.getBoard().top(4).stickers.push({ type: "leech" });   // col 1 — NOT this column
    r.ok(e.baseAvailable(0), "Cleanse: available with cursed tops in the column");
    const res = e.baseActivate(0);
    const removedTotal = res && res.cursesRemoved ? res.cursesRemoved.reduce((a, x) => a + x.count, 0) : 0;
    r.ok(res && res.cursesRemoved.length === 3 && removedTotal === 3, "Cleanse: every cursed sticker on the column's tops is stripped (2 cards, 3 curses)");
    r.eq(e.getBoard().top(0).stickers.length, 0, "Cleanse: pile 1's top is clean");
    r.eq(e.getBoard().top(1).stickers.length, 0, "Cleanse: pile 2's top is clean");
    r.eq(e.getBoard().top(4).stickers.length, 1, "Cleanse: other columns keep their curses");
    r.ok(!e.baseAvailable(0), "Cleanse: spent");
    // The campaign-side strip the handler runs:
    const c = CampaignState.create();
    const victimId = c.getRunDeck()[0].id;
    c.inflictSticker(victimId, "leech");
    const live1 = c.getRunDeck().find(x => x.id === victimId);
    r.ok(live1 && live1.stickers.some(s => s.type === "leech"), "Cleanse suite: inflictSticker curses a deck card");
    r.eq(c.removeStickerInstances(victimId, "leech", 1), 1, "Cleanse suite: the curse strips off the persistent card");
    const live2 = c.getRunDeck().find(x => x.id === victimId);
    r.ok(live2 && !live2.stickers.some(s => s.type === "leech"), "Cleanse suite: …for good");
  }
  {
    // Chorus: every top in the column becomes the full deck's most-copied rank
    // (ties → lowest).
    const comp = [compCard(7, "♥"), compCard(7, "♦"), compCard(7, "♣"), compCard(9, "♥"), compCard(9, "♦")];
    const e = game(null, { bases: ["chorus", null, null], comp });
    const res = e.baseActivate(0);
    r.ok(res && res.sourceValue === 7, "Chorus: the most-copied rank is the target");
    r.ok([0, 1, 2].every(i => e.getBoard().top(i).value === 7), "Chorus: every top in the column re-ranks");
    r.ok(res.valueApplied && res.valueApplied.length > 0, "Chorus: re-ranks ride valueApplied (durable)");
    const tie = [compCard(12, "♥"), compCard(12, "♦"), compCard(5, "♥"), compCard(5, "♦")];
    const e2 = game(null, { bases: ["chorus", null, null], comp: tie });
    const res2 = e2.baseActivate(0);
    r.ok(res2 && res2.sourceValue === 5, "Chorus: a tie breaks to the lowest rank");
    const e3 = game(null, { bases: ["chorus", null, null], comp: [] });
    r.ok(e3.baseActivate(0) && !e3.getRun().bonusEvents["Chorus"], "Chorus: an empty full deck is a no-op fire");
  }
  {
    // Diamond Boost (v6.78: column-wide, no target pick): +value size to
    // EVERY alive ♦-topped pile in the column on one activation.
    const val = num(BaseTypes.get("diamondBoost"), "value", 3);
    const e = game(null, { bases: ["diamondBoost", null, null] });
    for (const i of [0, 1, 2]) rigTop(e, i, 5, "♠");
    r.ok(!e.baseAvailable(0), "Diamond Boost: no ♦ top in the column → unavailable");
    rigTop(e, 1, 5, "♦");
    r.ok(e.baseAvailable(0), "Diamond Boost: a ♦ top enables it");
    rigTop(e, 2, 8, "♦");
    const s1 = e.getBoard().pileSize(1), s2 = e.getBoard().pileSize(2), s0 = e.getBoard().pileSize(0);
    const res = e.baseActivate(0);
    r.ok(res && e.getBoard().pileSize(1) - s1 === val, "Diamond Boost: +value pile size to a ♦ pile");
    r.ok(e.getBoard().pileSize(2) - s2 === val, "Diamond Boost: …and to EVERY other ♦ pile in the column");
    r.eq(e.getBoard().pileSize(0), s0, "Diamond Boost: the ♠ pile is untouched");
    r.ok(res.boostedPiles && res.boostedPiles.length === 2, "Diamond Boost: the result names the boosted piles");
  }

  /* ---- R5 source-contract pins (telemetry chokepoints) ------------------- */
  {
    // Source pins (stklag/seeds idiom): the harness evaluates the game script;
    // read index.html directly for the wiring contracts.
    const src = readFileSync(new URL("../index.html", import.meta.url), "utf8");
    r.ok(src.includes('recT("pillar", pillar.id, pillar.label, { saves: 1 })'), "R5: tolerance/shield saves go through recT");
    r.ok(src.includes("rollCursedStickerType"), "R5: Devil's Deal uses the shared weighted curse roll");
    r.ok(src.includes("setPurseHook") && src.includes("setCompositionHook"), "R3/hooks: the engine exposes the live purse + composition hooks");
  }

  return r.summary();
}
