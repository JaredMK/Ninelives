#!/usr/bin/env node
/* ============================================================================
   export-traces.mjs — GAMEPLAY GROUND TRUTH.

   Drives the REAL web GameEngine through long, fully deterministic deals and
   records the whole observable state after every guess. The Swift engine then
   replays the identical script and must match step for step.

   This is a far stronger check than hand-written unit tests: a single wrong
   comparison, a mis-ordered effect, a dropped rng draw or an off-by-one in the
   save-priority chain shows up as a diverging pile size or coin tally within a
   few steps.

   Scenarios cover: bare deals, columns + every Pillar, every Base, every
   Same-Power, and stickered decks (each sticker exercised on real cards).

       node ios/Tools/export-traces.mjs      # → ios/Fixtures/engine-traces.json
============================================================================ */
import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { loadGame } from "../../tests/_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const OUT = join(HERE, "..", "Fixtures");
mkdirSync(OUT, { recursive: true });

const quiet = { log() {}, warn() {}, error: console.error };
const G = loadGame({ console: quiet });
const { GameEngine, DeckManager, ItemData, StickerTypes, PillarTypes, BaseTypes, SamePowerTypes } = G;

/** The deterministic script: which pile, which call, at each step.
    Pure arithmetic on the step index plus a read of the pile's VISIBLE top card
    — no rng — so both sides walk the identical path. Reading the top makes the
    play survivable (random calls die in ~12 steps and most effects never fire),
    and every 5th call is a SAME so the Same path / Same-Powers get exercised. */
function scriptedChoice(step, aliveIndices, board) {
  const pile = aliveIndices[(step * 7 + 3) % aliveIndices.length];
  const top = board.top(pile);
  const v = top ? top.value : 8;
  const call = step % 5 === 4 ? "same" : v <= 8 ? "higher" : "lower";
  return { pile, call };
}

/** Everything observable after a step — the comparison surface. */
function snapshot(eng, step, choice) {
  const board = eng.getBoard();
  const deck = eng.getDeck();
  const run = eng.getRun();
  return {
    step,
    pile: choice ? choice.pile : null,
    call: choice ? choice.call : null,
    status: eng.getStatus(),
    remaining: deck.remaining(),
    drawn: deck.drawn(),
    alive: board.aliveCount(),
    dead: board.piles.map((p) => !!p.dead),
    sizes: board.piles.map((p) => p.cards.length),
    weighted: board.piles.map((_, i) => board.pileSize(i)),
    tops: board.piles.map((p) => {
      const t = p.cards[p.cards.length - 1];
      return t ? (t.joker ? "★" : t.label + t.suit) : null;
    }),
    topStickers: board.piles.map((p) => {
      const t = p.cards[p.cards.length - 1];
      return t && t.stickers ? t.stickers.map((s) => s.type) : [];
    }),
    minAlive: board.minAliveCards(),
    trueMinAlive: board.trueMinAliveCards(),
    extraCoinUnits: board.extraCoinUnits(),
    bonusCoins: run.bonusCoins,
    bonusEvents: Object.entries(run.bonusEvents).map(([k, v]) => [k, v]),
    sameCharge: eng.sameCharge(),
    correct: run.correctGuesses,
    total: run.totalGuesses,
    revealNext: !!run.revealNextActive,
    kamikazeReveal: run.kamikazeRevealLeft || 0,
    tellDrawsLeft: run.tellDrawsLeft || 0,
    tellPiles: [...(run.tellPiles || [])].sort((a, b) => a - b),
    colStreak: run.colStreak ? run.colStreak.slice() : null,
    pendingTributes: (run.pendingTributes || []).length,
    pendingActions: (run.pendingActions || []).length,
    reviveUsed: run.reviveUsed ? run.reviveUsed.slice() : null,
    secondWindUsed: run.secondWindUsed ? run.secondWindUsed.slice() : null,
    basesUsed: run.basesUsed ? run.basesUsed.slice() : null,
    suitBountyHits: run.suitBountyHits ? run.suitBountyHits.slice() : null,
    denseBuryUsed: run.denseBuryUsed ? run.denseBuryUsed.slice() : null,
    cardsDrawn: run.cardsDrawn,
    compoundUpdates: Object.entries(run.compoundUpdates || {}).map(([k, v]) => [+k, v]).sort((a, b) => a[0] - b[0]),
    snowballUpdates: Object.entries(run.snowballUpdates || {}).map(([k, v]) => [+k, v]).sort((a, b) => a[0] - b[0]),
  };
}

/** Build the deck specs for a scenario, applying its sticker plan. */
function buildSpecs(plan) {
  const specs = DeckManager.buildStandardDeck();
  for (const [cardId, typeId] of plan || []) {
    const c = specs.find((s) => s.id === cardId);
    if (c) c.stickers.push({ type: typeId });
  }
  return specs;
}

function runScenario(sc) {
  const specs = buildSpecs(sc.stickers);
  const eng = GameEngine.create(specs, sc.piles, {
    cols: sc.cols || null,
    sameCharge: !!sc.sameCharge,
    samePower: sc.samePower || null,
    noStickers: !!sc.noStickers,
  });
  eng.start(sc.seed);
  const baseRandom = eng.getRun().baseRandom;
  eng.startRun(sc.pillars || null, sc.bases || null, sc.samePower || null);
  const steps = [snapshot(eng, -1, null)];
  const events = [];
  // Auto-answer any prompts the way the script says, so the deal never stalls.
  for (let step = 0; step < sc.steps; step++) {
    if (eng.getStatus() !== "playing") break;
    // Fire a Base on the scripted step, if one is armed and legal.
    if (sc.baseAt != null && step === sc.baseAt && sc.cols) {
      for (let c = 0; c < sc.cols.length; c++) {
        if (eng.baseAvailable(c)) {
          const target = sc.baseTarget != null ? sc.baseTarget
            : (BaseTypes.get((sc.bases || [])[c]) || {}).target === "pillar" ? 0 : null;
          const pileTarget = (BaseTypes.get((sc.bases || [])[c]) || {}).target === "pile"
            ? eng.getBoard().piles.findIndex((p, i) => !p.dead && eng.getRun().pileColumns[i] === c)
            : target;
          const res = eng.baseActivate(c, pileTarget);
          if (res) events.push({ step, kind: "base", col: c, effect: res.effect, coins: res.coins });
          break;
        }
      }
    }
    const alive = eng.getBoard().piles.map((p, i) => (p.dead ? -1 : i)).filter((i) => i >= 0);
    if (!alive.length) break;
    const choice = scriptedChoice(step, alive, eng.getBoard());
    eng.guess(choice.pile, choice.call);
    // Drain any queued prompts deterministically (accept on even steps).
    let guard = 0;
    while (guard++ < 8) {
      const run = eng.getRun();
      if (run.pendingTributes && run.pendingTributes.length) { eng.answerTribute(step % 2 === 0); continue; }
      if (run.pendingActions && run.pendingActions.length) { eng.answerAction(step % 2 === 0); continue; }
      break;
    }
    steps.push(snapshot(eng, step, choice));
  }
  const final = {
    status: eng.getStatus(),
    result: eng.getRun().result,
    pillarPayout: (() => { const p = eng.pillarPayout();
      return { bonus: p.bonus, lines: p.lines.map((l) => ({ label: l.label, detail: l.detail, amount: l.amount, col: l.col })) }; })(),
  };
  // `steps` stays the scenario's step CAP; the recording rides as `trace`.
  return { ...sc, baseRandom, trace: steps, events, final };
}

/* ── SCENARIOS ─────────────────────────────────────────────────────────── */
const scenarios = [];
const SEEDS = [11, 202, 3003, 40404];

// 1. Bare deals — no columns, no items. The pure guess/tie/ace-high core.
for (const seed of SEEDS) {
  scenarios.push({ name: `bare-${seed}`, seed, piles: 9, steps: 200 });
}
// 2. Same-charge seeded on.
scenarios.push({ name: "samecharge", seed: 777, piles: 6, steps: 200, sameCharge: true });
// 3. Columns, no items — exercises pileColumns / streaks / column payouts.
for (const seed of [11, 3003]) {
  scenarios.push({ name: `cols-${seed}`, seed, piles: 10, cols: [3, 4, 3], steps: 200 });
}
// 4. EVERY Pillar, one per scenario, on the middle column (so Ditto has a
//    neighbour and Echo has something to echo).
for (const p of PillarTypes.all()) {
  scenarios.push({
    name: `pillar-${p.id}`, seed: 5150, piles: 9, cols: [3, 3, 3],
    pillars: [p.id, p.id === "ditto" ? "prime" : null, "echo"], steps: 160,
  });
}
// 5. EVERY Base, fired on step 12.
for (const b of BaseTypes.all()) {
  scenarios.push({
    name: `base-${b.id}`, seed: 6161, piles: 9, cols: [3, 3, 3],
    bases: [b.id, null, null], pillars: [null, "prime", null],
    baseAt: 12, steps: 160,
  });
}
// 6. EVERY Same-Power, with a same-heavy guess script.
for (const sp of SamePowerTypes.all()) {
  scenarios.push({ name: `samepower-${sp.id}`, seed: 7272, piles: 9, cols: [3, 3, 3],
                   samePower: sp.id, steps: 160 });
}
// 7. EVERY sticker, applied across the deck so it actually fires. Each sticker
//    goes onto 6 spread-out card ids so it lands within the trace window.
const stickerCardIds = [0, 7, 14, 21, 28, 35, 42, 49];
for (const s of ItemData.stickers) {
  scenarios.push({
    name: `sticker-${s.id}`, seed: 8383, piles: 9, cols: [3, 3, 3],
    stickers: stickerCardIds
      .filter((id) => {
        const c = DeckManager.buildStandardDeck().find((x) => x.id === id);
        return !s.suits || s.suits.indexOf(c.suit) !== -1;
      })
      .map((id) => [id, s.id]),
    samePower: "linkCoins", steps: 200,
  });
}
// 8. Lammy's noStickers rule with a stickered deck (no effect may sticker).
scenarios.push({
  name: "nostickers", seed: 9494, piles: 9, cols: [3, 3, 3], noStickers: true,
  stickers: stickerCardIds.map((id) => [id, "extraCoin"]),
  bases: ["randomSticker", null, null], baseAt: 5, steps: 160,
});

const out = scenarios.map(runScenario);
const path = join(OUT, "engine-traces.json");
writeFileSync(path, JSON.stringify({ generatedBy: "ios/Tools/export-traces.mjs", scenarios: out }) + "\n", "utf8");
const totalSteps = out.reduce((n, s) => n + s.trace.length, 0);
console.log(`wrote ${path}`);
console.log(`  ${out.length} scenarios, ${totalSteps} recorded steps`);
