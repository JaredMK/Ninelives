// JOKER CAPS PER DIFFICULTY (difficulty.js `jokerCap` + `guaranteedMapJoker`),
// HELD-COUNT logic: the cap counts Jokers currently held (deck + pack tray +
// the untaken guaranteed node); at cap, Jokers stop appearing at every roll
// site (map packs, store card packs), and removing a held Joker REOPENS
// availability. Map +1 nodes never roll random Jokers — the only standalone
// Joker node is Regular's single guaranteed one (visible, stages 1-3, never
// a mystery). Legendary: no Jokers anywhere.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { CampaignState } = loadGame();
  const r = makeRunner("joker-caps.test.mjs");
  const TIERS = {};   // read live from the registry via the campaign API
  for (const tier of ["regular", "master", "legendary"]) {
    const c = CampaignState.create();
    c.setTier(tier);
    c.reset();
    TIERS[tier] = c.jokerBudget().cap;
  }
  r.ok(Number.isInteger(TIERS.regular) && TIERS.regular >= 0, "regular jokerCap reads live from difficulty.js (" + TIERS.regular + ")");
  r.ok(TIERS.regular >= TIERS.master && TIERS.master >= TIERS.legendary,
    "caps tighten with difficulty (" + TIERS.regular + " ≥ " + TIERS.master + " ≥ " + TIERS.legendary + ")");

  const jokerNodes = (c) => c.getMap().nodes.filter(n => n.type === "pickup")
    .filter(n => { const card = c.nodeCard(n); return card && card.joker; });

  // --- regular: EXACTLY ONE guaranteed node, stages 1-3, visible ----------
  {
    let exact = true, badPhase = 0, hiddenJoker = 0;
    for (let s = 0; s < 12; s++) {
      const c = CampaignState.create();
      c.setTier("regular");
      c.reset();
      const nodes = jokerNodes(c);
      if (nodes.length !== 1) exact = false;
      for (const n of nodes) {
        if (!(n.phase >= 0 && n.phase <= 2)) badPhase++;
        if (n.mystery || c.nodeHidden(n.id)) hiddenJoker++;
      }
    }
    r.ok(exact, "regular: EXACTLY one standalone Joker node per fresh run (12 runs)");
    r.eq(badPhase, 0, "…always inside stages 1-3");
    r.eq(hiddenJoker, 0, "…and never hidden behind a ? mystery node");
  }

  // --- master / legendary: no standalone Joker nodes at all ----------------
  for (const tier of ["master", "legendary"]) {
    let nodes = 0;
    for (let s = 0; s < 8; s++) {
      const c = CampaignState.create();
      c.setTier(tier);
      c.reset();
      nodes += jokerNodes(c).length;
    }
    r.eq(nodes, 0, tier + ": no standalone Joker node ever generates (8 runs)");
  }

  // --- held-count gating + REOPEN on removal (regular, cap 2) -------------
  if (TIERS.regular === 2) {
    const c = CampaignState.create();
    c.setTier("regular");
    c.reset();
    r.eq(c.jokerBudget().committed, 1, "regular: the untaken guaranteed node reserves one held slot");
    r.ok(c.jokerBudget().allowed, "…one slot still open");
    // take the guaranteed node → the reservation becomes a held deck Joker
    const jn = jokerNodes(c)[0];
    const granted = c.resolvePickup(jn);
    c.markNodeCleared(jn.id);
    r.ok(granted && granted.joker, "taking the node grants a real Joker");
    r.eq(c.jokerBudget().committed, 1, "…count carries over (reserved → held, no double count)");
    // fill the second slot via a forced map-pack Joker (test hook bypasses the gate)
    c._setMapSpecialRoll(() => true);
    const packNode = c.getMap().nodes.find(n => n.type === "pack");
    const minted = c.resolvePack({ ...packNode, packCount: 1 }).filter(x => x && x.joker);
    c._setMapSpecialRoll(null);
    r.eq(minted.length, 1, "a second Joker can still be minted below the cap");
    r.ok(!c.jokerBudget().allowed, "holding 2: Jokers stop appearing");
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

  // --- master (cap 1): one held blocks everything ---------------------------
  if (TIERS.master === 1) {
    const c = CampaignState.create();
    c.setTier("master");
    c.reset();
    r.ok(c.jokerBudget().allowed, "master: no guarantee — the single slot starts open");
    c._setMapSpecialRoll(() => true);
    const packNode = c.getMap().nodes.find(n => n.type === "pack");
    c.resolvePack({ ...packNode, packCount: 1 });
    c._setMapSpecialRoll(null);
    r.ok(!c.jokerBudget().allowed, "master: holding 1 exhausts the cap");
    const seq = (vals) => { let i = 0; return () => (i < vals.length ? vals[i++] : 0.5); };
    r.ok(!c.genPackCard(seq([0.001, 0.1])).joker, "…store packs stop minting Jokers");
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

  return r.summary();
}
