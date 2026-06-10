// Bases — the active, once-per-deal artifact class bound to the BOTTOM of a
// column. The engine is DOM-free, so we drive baseActivate() directly and assert
// on board/deck/run state. Covers the registry, the CampaignState buy→place
// lifecycle + persistence, the store offer, the per-deal charged/spent lifecycle,
// every one of the 13 effects, and the Refresh-Bases no-loop rule.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, CampaignState, BaseTypes } = loadGame();
  const r = makeRunner("bases.test.mjs");

  const deck = () => DeckManager.buildStandardDeck();
  // col 0 = piles 0-2, col 1 = piles 3-6, col 2 = piles 7-9.
  const COLS = [3, 4, 3];
  /** A started run with the given column→Base binding. */
  const game = (bases) => {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start();
    e.startRun([null, null, null], bases);
    return e;
  };
  const card = (value, suit) => ({ value, suit, label: String(value), stickers: [] });

  // --- registry ----------------------------------------------------------
  {
    r.eq(BaseTypes.all().length, 13, "all 13 Bases registered");
    r.ok(!!BaseTypes.get("kamikaze"), "Kamikaze is a Base now");
    r.eq(BaseTypes.get("kamikaze").kind, "active", "Bases are the 'active' kind");
    r.eq(BaseTypes.get("kamikaze").target, "pile", "Kamikaze is a target Base");
    r.ok(!BaseTypes.get("shuffleColumn").target, "Shuffle Column is a whole-column Base");
    r.ok(BaseTypes.all().every(b => !b.suit), "no Base is suit-gated");
    r.ok(BaseTypes.all().every(b => typeof b.price === "number" && b.description), "every Base has a price + description");
  }

  // --- CampaignState buy → place lifecycle + persistence -----------------
  {
    const c = CampaignState.create();
    c.addCoins(100);
    r.eq(c.getColumnBases().length, 3, "three Base column slots");
    r.ok(c.buyBaseToInventory("kamikaze"), "buy a Base into inventory");
    r.eq(c.baseInventoryCount("kamikaze"), 1, "inventory holds the bought Base");
    r.ok(c.placeBase("kamikaze", 1), "place the Base on column 1");
    r.eq(c.columnBase(1), "kamikaze", "column 1 now holds Kamikaze");
    r.eq(c.baseInventoryCount("kamikaze"), 0, "placing consumes it from inventory");
    r.eq(c.baseCount(), 1, "one column holds a Base");
    // non-destructive swap: placing onto an occupied column returns the old one.
    c.buyBaseToInventory("evenOut");
    c.placeBase("evenOut", 1);
    r.eq(c.columnBase(1), "evenOut", "swap places the new Base");
    r.eq(c.baseInventoryCount("kamikaze"), 1, "the displaced Base returns to inventory");
    // pick back up
    r.eq(c.unplaceBase(1), "evenOut", "unplace returns the Base id");
    r.eq(c.columnBase(1), null, "column 1 cleared");

    // persistence round-trip
    c.placeBase("kamikaze", 0);
    const snap = JSON.parse(JSON.stringify(c.serialize()));
    const c2 = CampaignState.create();
    r.ok(c2.restore(snap), "restore a snapshot carrying Bases");
    r.eq(c2.columnBase(0), "kamikaze", "columnBases survive a save/restore round-trip");

    // affordability + reset
    const c3 = CampaignState.create();
    r.ok(!c3.buyBaseToInventory("kamikaze"), "can't buy a Base with no coins");
    c3.addCoins(100); c3.buyBaseToInventory("kamikaze"); c3.placeBase("kamikaze", 2);
    c3.reset();
    r.eq(c3.columnBase(2), null, "reset clears the Base binding");
    r.eq(c3.baseInventoryCount("kamikaze"), 0, "reset clears the Base inventory");
  }

  // --- store offer includes Bases ---------------------------------------
  {
    const c = CampaignState.create();
    c.addCoins(100);
    const offer = c.openStore(() => 0.0);
    r.ok(Array.isArray(offer.bases) && offer.bases.length === 3, "store offers three Base slots");
    const id = offer.bases[0];
    r.ok(c.buyOfferedBase(0), "buy an offered Base into inventory");
    r.eq(offer.bases[0], null, "the bought slot empties");
    r.eq(c.baseInventoryCount(id), 1, "the offered Base lands in inventory");
  }

  // --- charged/spent lifecycle ------------------------------------------
  {
    const e = game(["buryLargest", null, null]);
    r.eq(e.getRun().basesUsed[0], false, "Base is charged at deal start");
    r.ok(e.baseAvailable(0), "a charged Base in active play is available");
    r.ok(!e.baseAvailable(1), "an empty column has no Base");
    e.baseActivate(0);
    r.eq(e.getRun().basesUsed[0], true, "activating spends the Base");
    r.ok(!e.baseAvailable(0), "a spent Base is unavailable (once per deal)");
    // baseRandom rolled for the deal
    const br = e.baseRandom();
    r.ok(br && br.value >= 2 && br.value <= 14, "Set Value's value is rolled (2..Ace)");
    r.ok(br && br.suit, "Suit Tally's suit is rolled and present this deal");
  }

  // --- effect: Shuffle Column (return one buried card per pile to deck) --
  {
    const e = game(["shuffleColumn", null, null]);
    const b = e.getBoard();
    for (const i of [0, 1, 2]) { b.piles[i].cards = [card(3, "♠"), card(4, "♠"), card(5, "♠")]; }
    const before = e.getDeck().remaining();
    const res = e.baseActivate(0);
    r.eq(res.returned, 3, "one buried card returned from each of the 3 piles");
    r.eq(e.getDeck().remaining(), before + 3, "the deck grew by the returned cards");
  }

  // --- effect: Revive (random dead pile in column; buried cards → deck) --
  {
    const e = game(["revive", null, null]);
    const b = e.getBoard();
    b.piles[1].cards = [card(3, "♠"), card(4, "♠"), card(5, "♠")]; b.kill(1);   // dead, 3 buried
    const before = e.getDeck().remaining();
    const res = e.baseActivate(0);
    r.eq(res.index, 1, "the only dead pile in the column is revived");
    r.ok(b.isActive(1), "the pile is alive again");
    r.eq(b.piles[1].cards.length, 1, "it comes back with a single fresh pile card");
    r.eq(e.getDeck().remaining(), before + 3 - 1, "its 3 buried cards returned, one fresh card drawn");
    // No dead pile in the column → can't activate.
    const e2 = game(["revive", null, null]);
    r.ok(!e2.baseAvailable(0), "Revive is unavailable with no dead pile in its column");
  }

  // --- effect: Random Sticker (chosen pile) + wrong-column rejection -----
  {
    const e = game(["randomSticker", null, null]);
    const b = e.getBoard();
    b.piles[0].cards = [card(7, "♠")];
    r.eq(e.baseActivate(0, 3), null, "can't target a pile outside the Base's column");
    r.eq(e.getRun().basesUsed[0], false, "a rejected activation does not spend the Base");
    const res = e.baseActivate(0, 0);
    r.ok(res && res.stickerApplied, "a sticker is applied to the chosen pile card");
    r.eq(b.top(0).stickers.length, 1, "the pile card now carries one sticker");
  }

  // --- effect: Random Sticker All (all piles in column, −1 coin each) ----
  {
    const e = game(["randomStickerAll", null, null]);
    const b = e.getBoard();
    for (const i of [0, 1, 2]) b.piles[i].cards = [card(7, "♠")];
    const res = e.baseActivate(0);
    r.eq(res.stickersApplied.length, 3, "a sticker applied to each of the 3 pile cards");
    r.ok([0, 1, 2].every(i => b.top(i).stickers.length === 1), "every pile card gained a sticker");
    r.eq(e.getRun().bonusCoins, -3, "lost 1 coin per sticker applied");
  }

  // --- effect: Even Out (balance buried cards across the column) ---------
  {
    const e = game(["evenOut", null, null]);
    const b = e.getBoard();
    b.piles[0].cards = [card(2, "♠")];
    b.piles[1].cards = [card(2, "♠")];
    b.piles[2].cards = [card(2, "♠"), card(3, "♠"), card(4, "♠"), card(5, "♠"), card(6, "♠"), card(7, "♠"), card(8, "♠")];
    e.baseActivate(0);
    const sizes = [0, 1, 2].map(i => b.pileSize(i));
    r.ok(Math.max(...sizes) - Math.min(...sizes) <= 1, "piles end within 1 card of each other");
  }

  // --- effect: Bury Largest (one deck card under the biggest pile) -------
  {
    const e = game(["buryLargest", null, null]);
    const b = e.getBoard();
    b.piles[0].cards = [card(2, "♠")];
    b.piles[1].cards = [card(2, "♠")];
    b.piles[2].cards = [card(2, "♠"), card(3, "♠"), card(4, "♠"), card(5, "♠")];   // largest
    const before = e.getDeck().remaining();
    const res = e.baseActivate(0);
    r.eq(res.index, 2, "the largest pile is chosen");
    r.eq(b.piles[2].cards.length, 5, "one card buried under it");
    r.eq(e.getDeck().remaining(), before - 1, "one card left the deck");
  }

  // --- effect: Bury All (one card under each alive pile, −5 coins each) --
  {
    const e = game(["buryAll", null, null]);
    const b = e.getBoard();
    for (const i of [0, 1, 2]) b.piles[i].cards = [card(2, "♠")];
    const before = e.getDeck().remaining();
    const res = e.baseActivate(0);
    r.eq(res.buried, 3, "buried under all 3 alive piles");
    r.eq(e.getDeck().remaining(), before - 3, "three cards left the deck");
    r.eq(e.getRun().bonusCoins, -15, "lost 5 coins per pile buried under");
  }

  // --- effect: Set Value (every pile card in the column → rolled value) --
  {
    const e = game(["setValue", null, null]);
    e.getRun().baseRandom.value = 9;   // pin the rolled value
    const b = e.getBoard();
    for (const i of [0, 1, 2]) b.piles[i].cards = [card(3, "♠")];
    e.baseActivate(0);
    r.ok([0, 1, 2].every(i => b.top(i).value === 9), "all pile cards set to the rolled value");
  }

  // --- effect: Sticker Harvest (bury per sticker, then strip them) -------
  {
    const e = game(["stickerHarvest", null, null]);
    const b = e.getBoard();
    b.piles[0].cards = [card(7, "♠")];
    b.top(0).stickers = [{ type: "anchor" }, { type: "tieSafe" }];
    b.top(0).tieSafe = true;
    const before = e.getDeck().remaining();
    const res = e.baseActivate(0, 0);
    r.eq(res.harvested, 2, "harvested both stickers");
    r.eq(b.piles[0].cards.length, 1 + 2, "two cards buried under the pile (one per sticker)");
    r.eq(e.getDeck().remaining(), before - 2, "two cards left the deck");
    r.eq(b.top(0).stickers.length, 0, "every sticker removed from the pile card");
    r.ok(!b.top(0).tieSafe, "the projected sticker flag is cleared too");
  }

  // --- effect: Suit Tally (coins = Σ rolled-suit card values; faces = 10) -
  {
    const e = game(["suitTally", null, null]);
    e.getRun().baseRandom.suit = "♠";
    const b = e.getBoard();
    b.piles[0].cards = [card(5, "♠")];
    b.piles[1].cards = [card(12, "♠")];   // Queen → counts as 10
    b.piles[2].cards = [card(9, "♥")];    // wrong suit → ignored
    const res = e.baseActivate(0);
    r.eq(res.gained, 15, "tallied 5 + 10 (Queen as 10), ♥ ignored");
    r.eq(e.getRun().bonusCoins, 15, "the coins were credited");
  }

  // --- effect: Copy to Inventory (engine names the card; UI duplicates) --
  {
    const e = game(["copyToInventory", null, null]);
    const b = e.getBoard();
    b.kill(1); b.kill(2);          // only pile 0 alive in column 0 → deterministic pick
    const res = e.baseActivate(0);
    r.eq(res.index, 0, "a pile card in the column is chosen");
    r.eq(res.copyCardId, b.top(0).id, "the event names the exact card to copy");
    r.ok(e.getRun().basesUsed[0], "the Base is spent");
  }

  // --- effect: Refresh Bases (re-arm spent non-Refresh Bases) ------------
  {
    const e = game(["refreshBases", "kamikaze", "buryLargest"]);
    e.baseActivate(1, 5);   // spend Kamikaze (col 1)
    e.baseActivate(2);      // spend Bury Largest (col 2)
    r.ok(e.getRun().basesUsed[1] && e.getRun().basesUsed[2], "both other Bases are spent");
    const res = e.baseActivate(0);
    r.ok(res.refreshed.includes(1) && res.refreshed.includes(2), "both spent Bases re-armed");
    r.eq(e.getRun().basesUsed[1], false, "Kamikaze re-armed");
    r.eq(e.getRun().basesUsed[2], false, "Bury Largest re-armed");
    r.ok(e.getRun().basesUsed[0], "Refresh Bases itself is spent");
  }

  // --- Refresh Bases NEVER re-arms another Refresh Bases (no infinite loop) -
  {
    const e = game(["refreshBases", "refreshBases", "kamikaze"]);
    e.baseActivate(2, 5);   // spend Kamikaze (col 2)
    e.baseActivate(1);      // col 1 Refresh re-arms Kamikaze, spends itself
    r.eq(e.getRun().basesUsed[1], true, "col 1 Refresh Bases is now spent");
    e.baseActivate(2, 6);   // spend Kamikaze again so col 0 has something to refresh
    const res = e.baseActivate(0);
    r.ok(!res.refreshed.includes(1), "Refresh Bases is NOT in the refreshed set");
    r.eq(e.getRun().basesUsed[1], true, "the other Refresh Bases stays spent (no loop)");
    r.eq(e.getRun().basesUsed[2], false, "the non-Refresh Base was re-armed");
  }

  return r.summary();
}
