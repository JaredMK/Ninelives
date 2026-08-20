// The "Same" mechanic — Same-Power slot + BOARD-WIDE targeting.
// A correct Same triggers the ONE equipped Same-Power (the only artifact a Same
// triggers). As of v5.66 every Same-Power acts on ALL ALIVE PILES (a revive
// takes any dead pile) — link adjacency no longer scopes them; the called pile
// is still reported as the hub and linkHeavy still pays it an extra bonus.
// engine.setLinks remains (the UI's synapse network) but no power reads it.
// This suite covers the registry, the CampaignState equip slot + persistence,
// the engine plumbing, and the flagship power (Burrow).
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, CampaignState, SamePowerTypes, ItemData } = loadGame();
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
    // The roster grew to nine in the 127-item overhaul (linkTell / linkSticker /
    // linkPurge joined the original six) — read it live, pin the ORIGINALS by id.
    const ids = ["linkBury", "linkRevive", "linkCoins", "linkShuffle", "samePeek", "linkHeavy"];
    r.eq(SamePowerTypes.all().length, ItemData.samePowers.length, "registry count == items.js samePowers");
    r.ok(ids.every(id => !!SamePowerTypes.get(id)), "the original six by id");
    r.ok(SamePowerTypes.all().every(t => t.description && t.icon && typeof t.price === "number" && t.tier),
      "every Same-Power has a description + icon + price + tier");
    // v6.65 help-text pass: Same-Power descriptions dropped the Trigger/Effect
    // preamble — the trigger is always "you made a correct Same", so the text
    // is the plain single-line effect now.
    r.ok(SamePowerTypes.all().every(t => t.description && !/Trigger:/.test(t.description) && !t.description.includes("\n")),
      "every Same-Power uses the plain single-line effect description");
    r.ok(SamePowerTypes.all().every(t => t.tier === "rare"), "every Same-Power is Rare");
    r.ok(SamePowerTypes.all().every(t => t.price > 0 && t.price <= 10), "every Same-Power price is in the 1–10 cap band");
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
    r.eq(evt.targets.length, 10, "targets are EVERY alive pile (v5.66 — links no longer scope powers)");
    r.eq(buried, 10, "buried 1 under each of the 10 alive piles");
    r.eq(b.pileSize(1), s1 + 1, "a linked pile grew by 1");
    r.eq(b.pileSize(2), s2 + 1, "…so did the other one");
    r.eq(b.pileSize(5), s5 + 1, "…and an UNLINKED pile grew too (board-wide)");
  }

  // --- Burrow skips DEAD piles (acts on every ALIVE pile) ----------------
  {
    const e = mk({ samePower: "linkBury" });
    const b = e.getBoard();
    b.kill(2);                       // pile 2 is linked but dead
    e.setLinks({ 0: [1, 2], 1: [0], 2: [0] });
    const s1 = b.pileSize(1);
    let evt = null;
    e.onEvent((t, p) => { if (t === "same-power") evt = p; });
    sameOn(e, 0, 7);
    r.ok(evt.targets.length === 9 && !evt.targets.includes(2),
      "every ALIVE pile is a Burrow target; the dead one is skipped");
    r.eq(b.pileSize(1), s1 + 1, "an alive pile grew");
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

  // --- Rekindle: revive a directly-linked DEAD pile, keeping its size ----
  {
    const e = mk({ samePower: "linkRevive" });
    const b = e.getBoard();
    // Give pile 4 some buried cards, then kill it; link it to hub pile 0.
    b.piles[4].cards = [{ value: 3, suit: "♠", label: "3", stickers: [] },
                        { value: 9, suit: "♥", label: "9", stickers: [] },
                        { value: 5, suit: "♦", label: "5", stickers: [] }];
    b.kill(4);
    r.ok(!b.isActive(4), "pile 4 starts dead");
    const sizeWhenDead = b.pileSize(4);
    e.setLinks({ 0: [1, 4], 1: [0], 4: [0] });   // pile 4 (dead) is directly linked to hub 0
    let evt = null;
    e.onEvent((t, p) => { if (t === "same-power") evt = p; });
    sameOn(e, 0, 7);
    r.ok(b.isActive(4), "Rekindle revived the directly-linked dead pile");
    r.eq(b.pileSize(4), sizeWhenDead, "the revived pile kept its size (all buried cards intact)");
    r.eq(JSON.stringify(evt.targets), JSON.stringify([4]), "the event names the revived pile");
  }

  // --- Rekindle revives the LARGEST dead pile ANYWHERE on the board -------
  {
    const e = mk({ samePower: "linkRevive" });
    const b = e.getBoard();
    const fill = (i, n) => { b.piles[i].cards = Array.from({ length: n }, () => ({ value: 4, suit: "♠", label: "4", stickers: [] })); };
    fill(1, 2); b.kill(1);          // 2 cards
    fill(4, 5); b.kill(4);          // 5 cards
    fill(8, 9); b.kill(8);          // 9 cards — UNLINKED but the LARGEST, so it wins now
    e.setLinks({ 0: [1, 4], 1: [0], 4: [0] });
    sameOn(e, 0, 7);
    r.ok(b.isActive(8), "the largest dead pile board-wide was revived (v5.66: links don't scope it)");
    r.ok(!b.isActive(1) && !b.isActive(4), "…and only ONE pile is revived");
  }

  // --- Dividend: +value coins for EVERY ALIVE pile (board-wide) ----------
  {
    const e = mk({ samePower: "linkCoins" });
    const b = e.getBoard();
    e.setLinks({ 0: [1, 2], 1: [0], 2: [0], 5: [] });   // 2 links; pile 5 not linked
    const before = e.getRun().bonusCoins;
    let evt = null;
    e.onEvent((t, p) => { if (t === "same-power") evt = p; });
    sameOn(e, 0, 7);
    // Registry-driven: value × ALIVE piles board-wide (v5.66). NOTE this used
    // to read "5 × 2 linked = 10" and still totalled 10 by coincidence when the
    // rule changed to 1 × 10 alive — pinned against the knob now, not a literal.
    const perPile = SamePowerTypes.get("linkCoins").value;
    const alive = b.aliveCount();
    r.eq(e.getRun().bonusCoins - before, perPile * alive,
      "Dividend paid " + perPile + " × " + alive + " ALIVE piles");
    r.eq(evt.amount, perPile * alive, "the event reports the coins paid");
    r.eq(evt.targets.length, alive, "the event names every ALIVE pile (not just links)");
  }

  // --- Link Shuffler: shuffles every ALIVE pile board-wide ---------------
  {
    const e = mk({ samePower: "linkShuffle" });
    const b = e.getBoard();
    e.setLinks({ 0: [1, 2], 1: [0], 2: [0], 5: [] });
    let evt = null;
    e.onEvent((t, p) => { if (t === "same-power") evt = p; });
    sameOn(e, 0, 7);
    r.ok(evt && evt.power === "linkShuffle", "a same-power event fired naming Link Shuffler");
    r.eq(evt.targets.length, b.aliveCount(), "shuffled EVERY alive pile (v5.66)");
  }

  // --- Same Peeker: peeks the next upcoming card -------------------------
  {
    const e = mk({ samePower: "samePeek" });
    e.setLinks({ 0: [1] });
    r.ok(!e.getRun().revealNextActive, "no peek before the Same");
    sameOn(e, 0, 7);
    r.ok(e.getRun().revealNextActive, "Same Peeker peeks the next card on a correct Same");
  }

  // --- Same Heavy: +value to EVERY alive pile, +hubValue extra on the hub
  {
    const def = SamePowerTypes.get("linkHeavy");
    const linkGain = def.value, hubGain = def.hubValue;   // registry knobs, never pinned
    r.ok(typeof hubGain === "number" && hubGain > 0, "linkHeavy ships a hubValue knob (" + hubGain + ")");
    const e = mk({ samePower: "linkHeavy" });
    const b = e.getBoard();
    e.setLinks({ 0: [1, 2], 1: [0], 2: [0], 5: [] });
    const s0 = b.pileSize(0), s1 = b.pileSize(1), s2 = b.pileSize(2), s5 = b.pileSize(5);
    sameOn(e, 0, 7);
    // the correct Same also LANDS the drawn card on pile 0 (+1 real card), and
    // the hub is itself an alive pile, so it takes value AND hubValue (v5.66).
    r.eq(b.pileSize(0), s0 + 1 + linkGain + hubGain,
      "the CALLED pile gained +" + linkGain + " (board-wide) plus its +" + hubGain + " hub bonus");
    r.eq(b.pileSize(1), s1 + linkGain, "a linked pile gained +" + linkGain + " size");
    r.eq(b.pileSize(2), s2 + linkGain, "…so did the other one");
    r.eq(b.pileSize(5), s5 + linkGain, "…and an UNLINKED pile gained it too (board-wide)");
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
