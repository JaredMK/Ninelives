// The "Same" mechanic — Same-Power slot + direct-link targeting framework.
// A correct Same triggers the ONE equipped Same-Power (the only artifact a Same
// triggers). Every Same-Power acts on the piles DIRECTLY linked (synapse network)
// to the pile the Same was called on — the hub's direct link-neighbours only, not
// the transitive network. The UI pushes the link adjacency in via engine.setLinks
// (mirroring exactly the links the player sees); tests set it directly. This suite
// covers the registry, the CampaignState equip slot + persistence, the engine
// link plumbing, and the flagship power (Burrow — bury under each linked pile).
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, CampaignState, SamePowerTypes } = loadGame();
  const r = makeRunner("same-power.test.mjs");

  const deck = () => DeckManager.buildStandardDeck();
  const COLS = [3, 4, 3];   // col 0 = piles 0-2, col 1 = piles 3-6, col 2 = piles 7-9
  const mk = (cfg) => {
    const e = GameEngine.create(deck(), 10, Object.assign({ cols: COLS }, cfg || {}));
    e.start(); e.startRun([null, null, null], [null, null, null]);
    return e;
  };
  /** Drive a guaranteed-correct Same on pile `i` (pin top, force a tie, guess
      "same"). The Same banks a charge AND triggers the equipped Same-Power. */
  const sameOn = (e, i, val) => {
    const b = e.getBoard();
    b.top(i).value = (val == null ? 7 : val); b.top(i).label = String(b.top(i).value);
    e.debug.setNextCard(b.top(i).value);   // a tie
    e.guess(i, "same");
  };

  // --- registry ----------------------------------------------------------
  {
    const ids = ["linkBury", "linkRevive", "linkCoins"];
    r.eq(SamePowerTypes.all().length, 3, "three starter Same-Powers registered");
    r.ok(ids.every(id => !!SamePowerTypes.get(id)), "all three by id");
    r.ok(SamePowerTypes.all().every(t => t.description && t.icon && typeof t.price === "number" && t.tier),
      "every Same-Power has a description + icon + price + tier");
    r.ok(SamePowerTypes.all().every(t => /Trigger:.*\n.*Effect:/s.test(t.description)),
      "every Same-Power uses the Trigger/Effect description format");
    r.eq(SamePowerTypes.get("linkBury").tier, "uncommon", "Burrow is uncommon (flagship/accessible)");
    r.eq(SamePowerTypes.get("linkRevive").tier, "rare", "Rekindle is rare (revive is strong)");
  }

  // --- CampaignState: buy → equip → swap → unequip → persistence ---------
  {
    const c = CampaignState.create();
    r.eq(c.getSamePower(), null, "fresh campaign: nothing equipped");
    r.ok(!c.buySamePowerToInventory("linkBury"), "can't buy with no coins");
    c.addCoins(100);
    r.ok(c.buySamePowerToInventory("linkBury"), "buy Burrow into inventory");
    r.eq(c.samePowerInventoryCount("linkBury"), 1, "inventory holds the bought power");
    r.ok(c.equipSamePower("linkBury"), "equip Burrow into the slot");
    r.eq(c.getSamePower(), "linkBury", "Burrow is equipped");
    r.eq(c.samePowerInventoryCount("linkBury"), 0, "equipping consumed it from inventory");
    // Non-destructive swap: equipping a second returns the first to inventory.
    c.buySamePowerToInventory("linkCoins");
    r.ok(c.equipSamePower("linkCoins"), "equip Dividend (swap)");
    r.eq(c.getSamePower(), "linkCoins", "Dividend now equipped");
    r.eq(c.samePowerInventoryCount("linkBury"), 1, "the displaced power returned to inventory");
    // Unequip back to inventory.
    r.eq(c.unequipSamePower(), "linkCoins", "unequip returns the id");
    r.eq(c.getSamePower(), null, "slot cleared");
    r.eq(c.samePowerInventoryCount("linkCoins"), 1, "unequipped power is back in inventory");
    // Persistence round-trip.
    c.equipSamePower("linkBury");
    const wire = JSON.parse(JSON.stringify(c.serialize()));
    const c2 = CampaignState.create();
    c2.restore(wire);
    r.eq(c2.getSamePower(), "linkBury", "equipped power survives serialize/restore");
    r.eq(c2.samePowerInventoryCount("linkCoins"), 1, "inventory survives serialize/restore");
    // Reset clears both.
    c.reset();
    r.eq(c.getSamePower(), null, "reset clears the equipped power");
    r.eq(c.samePowerInventoryCount("linkBury"), 0, "reset clears the inventory");
  }

  // --- engine: setLinks / getLinks / samePower seeding ------------------
  {
    const e = mk({ samePower: "linkBury" });
    r.eq(e.samePower(), "linkBury", "engine seeds the equipped power from runConfig");
    e.setLinks({ 0: [1, 4], 1: [0] });
    r.eq(JSON.stringify(e.getLinks()[0]), JSON.stringify([1, 4]), "setLinks/getLinks round-trips the adjacency");
    const e2 = mk();
    r.eq(e2.samePower(), null, "no power → samePower() is null");
    r.eq(JSON.stringify(e2.getLinks()), "{}", "links default empty");
  }

  // --- flagship: Burrow buries under each ALIVE directly-linked pile -----
  {
    const e = mk({ samePower: "linkBury" });
    const b = e.getBoard();
    // Hub = pile 0, directly linked to piles 1 and 2 (alive). Pile 5 is NOT in
    // pile 0's adjacency (so it must be untouched — direct links only).
    e.setLinks({ 0: [1, 2], 1: [0], 2: [0], 5: [] });
    const s1 = b.pileSize(1), s2 = b.pileSize(2), s5 = b.pileSize(5);
    let evt = null, buried = 0;
    e.onEvent((t, p) => {
      if (t === "same-power") evt = p;
      if (t === "buried" && p.source === "Burrow") buried += p.count;
    });
    sameOn(e, 0, 7);
    r.ok(e.sameCharge(), "the correct Same still banked a charge (Layer 1 holds)");
    r.ok(evt && evt.power === "linkBury", "a same-power event fired naming Burrow");
    r.eq(JSON.stringify(evt.targets.slice().sort()), JSON.stringify([1, 2]), "targets are exactly the hub's direct links");
    r.eq(buried, 2, "buried 1 under each of the 2 linked piles");
    r.eq(b.pileSize(1), s1 + 1, "linked pile 1 grew by 1");
    r.eq(b.pileSize(2), s2 + 1, "linked pile 2 grew by 1");
    r.eq(b.pileSize(5), s5, "a NON-linked pile is untouched (direct links only)");
  }

  // --- Burrow skips DEAD linked piles (acts on alive links only) ---------
  {
    const e = mk({ samePower: "linkBury" });
    const b = e.getBoard();
    b.kill(2);                       // pile 2 is linked but dead
    e.setLinks({ 0: [1, 2], 1: [0], 2: [0] });
    const s1 = b.pileSize(1);
    let evt = null;
    e.onEvent((t, p) => { if (t === "same-power") evt = p; });
    sameOn(e, 0, 7);
    r.eq(JSON.stringify(evt.targets), JSON.stringify([1]), "only the ALIVE linked pile is a Burrow target");
    r.eq(b.pileSize(1), s1 + 1, "the alive linked pile grew");
  }

  // --- a Same with NOTHING equipped just banks (no power, no event) ------
  {
    const e = mk();   // no samePower
    e.setLinks({ 0: [1, 2] });
    let fired = false;
    e.onEvent((t) => { if (t === "same-power") fired = true; });
    sameOn(e, 0, 7);
    r.ok(e.sameCharge(), "the Same banked a charge");
    r.ok(!fired, "no Same-Power equipped → no power fires (Same still does its two things, power is a no-op)");
  }

  // --- the power fires ONLY on a correct Same, not other correct guesses --
  {
    const e = mk({ samePower: "linkBury" });
    const b = e.getBoard();
    e.setLinks({ 0: [1, 2], 1: [0], 2: [0] });
    const s1 = b.pileSize(1);
    let fired = false;
    e.onEvent((t) => { if (t === "same-power") fired = true; });
    b.top(0).value = 5; e.debug.setNextCard(9);
    e.guess(0, "higher");            // correct, but NOT a Same
    r.ok(!fired, "a non-Same correct guess does NOT trigger the Same-Power");
    r.eq(b.pileSize(1), s1, "linked pile untouched by a non-Same guess");
  }

  return r.summary();
}
