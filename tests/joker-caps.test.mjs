// JOKER CAPS PER DIFFICULTY (difficulty.js `jokerCap` + `guaranteedMapJoker`),
// HELD-COUNT logic: the cap counts Jokers currently held (deck + pack tray +
// the untaken guaranteed node); at cap, Jokers stop appearing at every roll
// site (map packs, store card packs), and removing a held Joker REOPENS
// availability. Map +1 nodes never roll random Jokers.
//
// JOKER3 — difficulty.js `fixedJokers` REPLACES a tier's rules for the decks
// it lists (today only Pinky on Regular): a fixed scheme — exactly TWO Jokers
// per run, one forced corridor +1 CARD node directly after the stage-1 boss
// and one after the stage-2 boss (both visible, never a mystery, never in a
// pack), and NO other Joker source at all. Decks the data does not list keep
// Regular's roaming guaranteed node + jokerCap (tested on Mamma below).
// STARTJOKERS (MYST2) — difficulty.js `startJokers` additionally MINTS Jokers
// into the deck at run start; they count as held from node one. (Two-tier
// model: Regular "Jokers" has them, Legendary "Straight" has none anywhere —
// the Master tier is retired.)
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadGame, makeRunner } from "./_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const DIFFICULTY = join(HERE, "..", "difficulty.js");

/** A difficulty.js source with the live data mutated (scheme probes — the
    same pattern as tests/zen1.test.mjs's validation probes). */
function difficultySourceWith(mutate) {
  const d = JSON.parse(JSON.stringify(
    new Function(readFileSync(DIFFICULTY, "utf8") + "\n;return NINELIVES_DIFFICULTY;")()));
  mutate(d);
  return '"use strict";\nconst NINELIVES_DIFFICULTY = ' + JSON.stringify(d) + ";";
}

export function run() {
  const { CampaignState, DifficultyData } = loadGame();
  const r = makeRunner("joker-caps.test.mjs");
  const START_J = DifficultyData.startJokers("pink", "regular");   // Pinky Regular's starting Jokers
  const TIERS = {};   // read live from the registry via the campaign API
  for (const tier of ["regular", "legendary"]) {
    const c = CampaignState.create();
    c.setTier(tier);
    c.reset();
    TIERS[tier] = c.jokerBudget().cap;
  }
  r.ok(Number.isInteger(TIERS.regular) && TIERS.regular >= 0, "regular jokerCap reads live from difficulty.js (" + TIERS.regular + ")");
  r.ok(TIERS.regular >= TIERS.legendary,
    "caps tighten with difficulty (" + TIERS.regular + " ≥ " + TIERS.legendary + ")");

  const jokerNodes = (c) => c.getMap().nodes.filter(n => n.type === "pickup")
    .filter(n => { const card = c.nodeCard(n); return card && card.joker; });

  // --- PINKY REGULAR (JOKER3): exactly two FIXED post-boss Jokers ---------
  {
    const c = CampaignState.create();   // default deck = pink
    c.setTier("regular");
    c.reset();
    // Pinky opens a Regular run on the STANDARD 13 cards — no gifted Joker.
    // Its two Jokers are EARNED at the fixed corridor nodes below, which
    // reserve their cap slots from node one (a visible promise).
    r.eq(START_J, 0, "pinky regular is no longer gifted a starting Joker");
    r.eq(c.deckSize(), 13, "…the run opens on the standard 13 cards");
    r.eq(c.getRunDeck().filter(x => x.joker).length, 0,
      "…holding no Jokers at all on node one");
    r.eq(c.jokerBudget().committed, 2,
      "…only the two fixed-node reservations count as held (2/" + c.jokerBudget().cap + ")");
    const map = c.getMap();
    const fixed = map.nodes.filter(n => n.jokerNode).sort((a, b) => a.phase - b.phase);
    r.eq(fixed.length, 2, "pinky regular: exactly TWO fixed Joker nodes on the map");
    r.ok(fixed.every(n => n.type === "pickup" && !n.mystery && !c.nodeHidden(n.id)),
      "…both are visible standalone +1 CARD nodes (never a mystery, never a pack)");
    r.eq(fixed[0].phase, 0, "…the first belongs to stage 1");
    r.eq(fixed[1].phase, 1, "…the second belongs to stage 2");
    r.ok(map.byId[map.phases[0].bossId].next.indexOf(fixed[0].id) !== -1,
      "…the stage-1 boss leads DIRECTLY to the first Joker node");
    r.ok(map.byId[map.phases[1].bossId].next.indexOf(fixed[1].id) !== -1,
      "…the stage-2 boss leads DIRECTLY to the second Joker node");
    r.eq(fixed[0].next.slice().sort((a, b) => a - b).join(","),
      map.phases[1].row0.slice().sort((a, b) => a - b).join(","),
      "…the first Joker node fans out to the stage-2 openings");
    r.eq(fixed[1].next.slice().sort((a, b) => a - b).join(","),
      map.phases[2].row0.slice().sort((a, b) => a - b).join(","),
      "…the second Joker node fans out to the stage-3 openings");
    r.ok(fixed.every(n => { const cd = c.nodeCard(n); return cd && cd.joker; }),
      "…both locked to a face-up Joker card");
    r.eq(jokerNodes(c).length, 2, "…and NO other map node carries a Joker");
    // NO other source, even at zero held Jokers:
    r.ok(!c.jokerBudget().allowed, "pinky regular: random Joker availability is OFF from the very start");
    const seq = (vals) => { let i = 0; return () => (i < vals.length ? vals[i++] : 0.5); };
    r.ok(!c.genPackCard(seq([0.001, 0.1])).joker, "…a store-pack Joker roll mints a normal card instead");
    r.ok(!!c.genPackCard(seq([0.001, 0.9])).blank, "…while Blanks keep their own half unchanged");
    r.ok(!c.genStoreCard(seq([0.001])).joker, "…the store card slot never rolls a Joker");
    const packNode = map.nodes.find(n => n.type === "pack");
    let packJokers = 0;
    for (let i = 0; i < 20 && packNode; i++) packJokers += c.resolvePack({ ...packNode, packCount: 3 }).filter(x => x && x.joker).length;
    r.eq(packJokers, 0, "…map packs never mint Jokers (60 slots probed)");
    // Taking both fixed nodes grants exactly two real Jokers…
    const g0 = c.resolvePickup(fixed[0]); c.markNodeCleared(fixed[0].id);
    const g1 = c.resolvePickup(fixed[1]); c.markNodeCleared(fixed[1].id);
    r.ok(!!(g0 && g0.joker && g1 && g1.joker), "taking the two nodes grants two real Jokers");
    r.eq(c.getRunDeck().filter(x => x.joker).length, 2,
      "…the deck then holds exactly the 2 EARNED corridor Jokers — none gifted");
    // …and Removal never reopens a random source (the scheme is absolute).
    c.getRunDeck().filter(x => x.joker).forEach(j => c.removeDeckCard(j.id));
    r.ok(!c.jokerBudget().allowed, "…removing them does NOT reopen random Jokers");
    r.ok(!c.genPackCard(seq([0.001, 0.1])).joker, "…store packs stay Joker-free after removal");
  }

  // --- NON-PINKY regular (Mamma): the roaming guaranteed node lives on -----
  {
    let exact = true, badPhase = 0, hiddenJoker = 0, corridor = 0;
    for (let s = 0; s < 12; s++) {
      const c = CampaignState.create();
      c.setDeck("mamma");
      c.setTier("regular");
      c.reset();
      const nodes = jokerNodes(c);
      if (nodes.length !== 1) exact = false;
      corridor += c.getMap().nodes.filter(n => n.jokerNode).length;
      for (const n of nodes) {
        if (!(n.phase >= 0 && n.phase <= 2)) badPhase++;
        if (n.mystery || c.nodeHidden(n.id)) hiddenJoker++;
      }
    }
    r.ok(exact, "mamma regular: EXACTLY one roaming guaranteed Joker node per fresh run (12 runs)");
    r.eq(badPhase, 0, "…always inside stages 1-3");
    r.eq(hiddenJoker, 0, "…and never hidden behind a ? mystery node");
    r.eq(corridor, 0, "…and no fixed post-boss corridor nodes (Pinky-only scheme)");
  }

  // --- legendary: no standalone Joker nodes at all (the Master tier is
  //     retired — regular keeps its guaranteed node(s)) ----------------------
  for (const tier of ["legendary"]) {
    let nodes = 0;
    for (let s = 0; s < 8; s++) {
      const c = CampaignState.create();
      c.setTier(tier);
      c.reset();
      nodes += jokerNodes(c).length;
    }
    r.eq(nodes, 0, tier + ": no standalone Joker node ever generates (8 runs)");
  }

  // --- held-count gating + REOPEN on removal (non-Pinky regular) ----------
  {
    const cap = TIERS.regular;
    const c = CampaignState.create();
    c.setDeck("mamma");   // Pinky Regular uses the fixed scheme (tested above)
    c.setTier("regular");
    c.reset();
    r.eq(c.jokerBudget().committed, 1, "regular: the untaken guaranteed node reserves one held slot");
    r.ok(c.jokerBudget().allowed, "…slots still open (" + 1 + "/" + cap + ")");
    // take the guaranteed node → the reservation becomes a held deck Joker
    const jn = jokerNodes(c)[0];
    const granted = c.resolvePickup(jn);
    c.markNodeCleared(jn.id);
    r.ok(granted && granted.joker, "taking the node grants a real Joker");
    r.eq(c.jokerBudget().committed, 1, "…count carries over (reserved → held, no double count)");
    // fill every remaining slot via forced map-pack Jokers (test hook bypasses the gate)
    c._setMapSpecialRoll(() => true);
    const packNode = c.getMap().nodes.find(n => n.type === "pack");
    let minted = 0;
    for (let i = 0; i < cap - 1; i++)
      minted += c.resolvePack({ ...packNode, packCount: 1 }).filter(x => x && x.joker).length;
    c._setMapSpecialRoll(null);
    r.eq(minted, cap - 1, "Jokers keep minting up to the cap (" + cap + ")");
    r.eq(c.jokerBudget().committed, cap, "…holding exactly the cap now");
    r.ok(!c.jokerBudget().allowed, "at cap: Jokers stop appearing");
    const seq = (vals) => { let i = 0; return () => (i < vals.length ? vals[i++] : 0.5); };
    r.ok(!c.genPackCard(seq([0.001, 0.1])).joker, "…store-pack joker rolls fall through to normal cards");
    let packJokers = 0;
    for (let i = 0; i < 20; i++) packJokers += c.resolvePack({ ...packNode, packCount: 3 }).filter(x => x && x.joker).length;
    r.eq(packJokers, 0, "…map packs stop minting Jokers (60 slots probed)");
    // REMOVAL reopens availability
    const heldJoker = c.getRunDeck().find(x => x.joker);
    r.ok(!!heldJoker && c.removeDeckCard(heldJoker.id), "a held Joker can be Removed");
    r.ok(c.jokerBudget().allowed, "removing one REOPENS Joker availability");
    r.ok(c.genPackCard(seq([0.001, 0.1])).joker, "…and store packs may mint one again");
  }

  // --- legendary (cap 0): no Jokers anywhere -------------------------------
  if (TIERS.legendary === 0) {
    const c = CampaignState.create();
    c.setTier("legendary");
    c.reset();
    r.ok(!c.jokerBudget().allowed, "legendary: the budget is exhausted from the start");
    const seq = (vals) => { let i = 0; return () => (i < vals.length ? vals[i++] : 0.5); };
    r.ok(!c.genPackCard(seq([0.001, 0.1])).joker, "legendary: a store-pack joker roll mints a normal card instead");
    r.ok(!!c.genPackCard(seq([0.001, 0.9])).blank, "…while Blanks keep their own half unchanged");
    const packNode = c.getMap().nodes.find(n => n.type === "pack");
    let packJokers = 0;
    for (let i = 0; i < 20 && packNode; i++) packJokers += c.resolvePack({ ...packNode, packCount: 3 }).filter(x => x && x.joker).length;
    r.eq(packJokers, 0, "legendary: map packs never mint Jokers (60 slots probed)");
  }

  // --- the scheme is DATA-DRIVEN: mutating difficulty.js changes it --------
  {
    // The live accessor reads the tier's fixedJokers straight from the data.
    const { DifficultyData } = loadGame();
    const liveStages = DifficultyData.tier("regular").fixedJokers.pink;
    r.eq(JSON.stringify(DifficultyData.fixedJokerStages("pink", "regular")), JSON.stringify(liveStages),
      "fixedJokerStages(pink, regular) returns the data's stage array");
    // DELETE the override → Pinky Regular falls back to the roaming scheme:
    // no fixed corridor nodes, exactly one roaming guaranteed Joker, and
    // random Joker availability back ON (cap permitting).
    {
      const { CampaignState } = loadGame({ difficultySource: difficultySourceWith(d => { delete d.tiers.regular.fixedJokers; }) });
      const c = CampaignState.create();   // default deck = pink
      c.setTier("regular");
      c.reset();
      r.eq(c.getMap().nodes.filter(n => n.jokerNode).length, 0,
        "fixedJokers deleted: pinky regular generates NO fixed corridor nodes");
      r.eq(jokerNodes(c).length, 1, "…and gets the roaming guaranteed Joker node instead");
      r.ok(c.jokerBudget().allowed, "…and random Joker availability is back ON");
    }
    // ADD another deck → that deck takes the fixed scheme on that tier:
    {
      const { CampaignState } = loadGame({ difficultySource: difficultySourceWith(d => {
        d.tiers.regular.fixedJokers.mamma = d.tiers.regular.fixedJokers.pink.slice();
      }) });
      const c = CampaignState.create();
      c.setDeck("mamma");
      c.setTier("regular");
      c.reset();
      const fixed = c.getMap().nodes.filter(n => n.jokerNode).sort((a, b) => a.phase - b.phase);
      r.eq(fixed.length, liveStages.length, "mamma added to fixedJokers: mamma regular gets the fixed nodes too");
      r.eq(JSON.stringify(fixed.map(n => n.phase)), JSON.stringify(liveStages),
        "…at exactly the data's stage indices");
      r.ok(!c.jokerBudget().allowed, "…and her random Joker availability turns OFF");
    }
  }

  return r.summary();
}
