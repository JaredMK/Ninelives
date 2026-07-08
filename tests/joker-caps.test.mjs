// JOKER CAPS PER DIFFICULTY (difficulty.js `jokerCap`): Regular caps Jokers
// at its registry value (2), Master lower (1), Legendary none (0). Once a
// run's budget is spoken for (owned + locked-on-map + tray), Jokers stop
// appearing at EVERY roll site (map cards, map packs, store packs). Tiers
// with a cap ≥ 1 guarantee one Joker as a standalone map card.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { CampaignState } = loadGame();
  const r = makeRunner("joker-caps.test.mjs");
  const CAPS = {};   // read live from the registry via the campaign API
  for (const tier of ["regular", "master", "legendary"]) {
    const c = CampaignState.create();
    c.setTier(tier);
    c.reset();
    CAPS[tier] = c.jokerBudget().cap;
  }
  r.ok(Number.isInteger(CAPS.regular) && CAPS.regular >= 0, "regular jokerCap reads live from difficulty.js (" + CAPS.regular + ")");
  r.ok(CAPS.regular >= CAPS.master && CAPS.master >= CAPS.legendary,
    "caps tighten with difficulty (" + CAPS.regular + " ≥ " + CAPS.master + " ≥ " + CAPS.legendary + ")");

  // --- guarantee: cap ≥ 1 tiers always lock ONE standalone map Joker --------
  for (const tier of ["regular", "master"]) {
    if (CAPS[tier] < 1) continue;
    let always = true, count0 = 0;
    for (let s = 0; s < 12; s++) {
      const c = CampaignState.create();
      c.setTier(tier);
      c.reset();
      const m = c.getMap();
      const jokers = m.nodes.filter(n => n.type === "pickup")
        .filter(n => { const card = c.nodeCard(n); return card && card.joker; });
      if (!jokers.length) always = false;
      if (jokers.length > CAPS[tier]) count0++;
    }
    r.ok(always, tier + ": every fresh run locks at least one standalone map Joker");
    r.eq(count0, 0, tier + ": the map never promises more Jokers than the cap (" + CAPS[tier] + ")");
  }

  // --- legendary (cap 0): no Jokers anywhere ------------------------------
  if (CAPS.legendary === 0) {
    let mapJokers = 0, everAllowed = false;
    for (let s = 0; s < 12; s++) {
      const c = CampaignState.create();
      c.setTier("legendary");
      c.reset();
      mapJokers += c.getMap().nodes.filter(n => { const card = c.nodeCard(n); return card && card.joker; }).length;
      if (c.jokerBudget().allowed) everAllowed = true;
    }
    r.ok(!everAllowed, "legendary: the budget is exhausted from the start");
    r.eq(mapJokers, 0, "legendary: no map card ever locks a Joker across 12 runs");
    // store packs: force the special branch — the joker half must fall through
    // to a NORMAL card while the Blank half is untouched.
    const c = CampaignState.create();
    c.setTier("legendary");
    c.reset();
    const seq = (vals) => { let i = 0; return () => (i < vals.length ? vals[i++] : 0.5); };
    const jokerTry = c.genPackCard(seq([0.001, 0.1]));   // special hit → joker half
    r.ok(!jokerTry.joker, "legendary: a store-pack joker roll mints a normal card instead");
    const blankTry = c.genPackCard(seq([0.001, 0.9]));   // special hit → blank half
    r.ok(!!blankTry.blank, "…while Blanks keep their own half unchanged");
  }

  // --- the cap binds at every LIVE roll site once the budget is spent ------
  {
    const c = CampaignState.create();
    c.setTier("master");   // cap 1 (registry) — the guaranteed map Joker spends it
    c.reset();
    const b0 = c.jokerBudget();
    r.eq(b0.committed, Math.min(1, CAPS.master), "master: the guaranteed map Joker is counted as committed");
    if (CAPS.master === 1) {
      r.ok(!b0.allowed, "master: budget spent by the guarantee — no more Jokers may roll");
      const seq = (vals) => { let i = 0; return () => (i < vals.length ? vals[i++] : 0.5); };
      const packCard = c.genPackCard(seq([0.001, 0.1]));
      r.ok(!packCard.joker, "master at cap: store packs stop minting Jokers");
      // map pack slots use the production roll too — resolve a pack node many
      // times; no slot may mint a Joker while the budget is spent.
      const packNode = c.getMap().nodes.find(n => n.type === "pack");
      let minted = 0;
      for (let i = 0; i < 30 && packNode; i++) {
        const cards = c.resolvePack({ ...packNode, packCount: 3 });
        minted += cards.filter(x => x && x.joker).length;
      }
      r.eq(minted, 0, "master at cap: map packs stop minting Jokers (90 slots probed)");
    }
  }

  // --- taking the promised Joker keeps the total inside the cap ------------
  {
    const c = CampaignState.create();
    c.setTier("regular");
    c.reset();
    const jNode = c.getMap().nodes.find(n => n.type === "pickup" && (x => x && x.joker)(c.nodeCard(n)));
    r.ok(!!jNode, "regular: found the guaranteed Joker node");
    const before = c.jokerBudget().committed;
    const card = c.resolvePickup(jNode);
    c.markNodeCleared(jNode.id);
    r.ok(card && card.joker, "taking it grants a real minted Joker into the deck");
    r.eq(c.jokerBudget().committed, before, "…and the budget count carries over (locked → owned, not double-counted)");
    r.ok(c.jokerBudget().committed <= c.jokerBudget().cap, "the run never exceeds its cap");
  }

  return r.summary();
}
