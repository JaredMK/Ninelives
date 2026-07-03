// Bases — the active, once-per-deal artifact class bound to the BOTTOM of a
// column. The engine is DOM-free, so we drive baseActivate() directly and assert
// on board/deck/run state. Covers the registry, the CampaignState buy→place
// lifecycle + persistence, the store offer, the per-deal charged/spent lifecycle,
// every effect, and the Refresh-Bases no-loop rule.
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
  const card = (value, suit) => ({ value, suit, label: String(value), stickers: [], red: suit === "♥" || suit === "♦" });

  // --- registry ----------------------------------------------------------
  {
    r.eq(BaseTypes.all().length, 15, "all 15 Bases registered");
    r.ok(!!BaseTypes.get("kamikaze"), "Kamikaze is a Base");
    r.eq(BaseTypes.get("kamikaze").kind, "active", "Bases are the 'active' kind");
    r.eq(BaseTypes.get("kamikaze").target, "pile", "Kamikaze is a target Base");
    r.ok(!BaseTypes.get("shuffleColumn").target, "Upheaval is a whole-column Base");
    // Only Club Dig (♣), Landslide (♣) and Heart Tax (♥) carry a suit now.
    r.eq(BaseTypes.get("clubDig").suit, "♣", "Club Dig is suit-gated on ♣");
    r.eq(BaseTypes.get("buryAll").suit, "♣", "Landslide is suit-gated on ♣");
    r.eq(BaseTypes.get("tax").suit, "♥", "Heart Tax is suit-gated on ♥");
    r.ok(!BaseTypes.get("heartDig") && !BaseTypes.get("diamondDig") && !BaseTypes.get("spadeDig"), "Heart/Diamond/Spade Dig were removed");
    r.ok(!BaseTypes.get("suitTally") && !BaseTypes.get("copyToInventory") && !BaseTypes.get("randomStickerAll"), "Suit Tally / Replica / Sticker Storm were removed");
    r.eq(BaseTypes.all().filter(b => b.suit).length, 3, "exactly Club Dig + Landslide + Heart Tax carry a suit");
    r.eq(BaseTypes.get("demolish").target, "pillar", "Demolish targets a Pillar");
    r.ok(!!BaseTypes.get("spadePeek") && !!BaseTypes.get("setSuit") && !!BaseTypes.get("heartDemolish"), "new bases Spade Peeker / Suit Setter / Heart Demolish registered");
    r.eq(BaseTypes.get("setValue").price, 12, "Cast repriced to 12");
    r.eq(BaseTypes.get("demolish").price, 25, "Demolish repriced to 25");
    r.eq(BaseTypes.get("randomSticker").price, 5, "Wild Sticker repriced to 5");
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

  // --- store offer can include Bases (in the mixed slots) ---------------
  {
    const c = CampaignState.create();
    c.addCoins(100);
    const offer = c.openStore(() => 0.0);   // rng 0 → every mixed slot rolls a Base
    r.eq(offer.mixed.length, 3, "store offers three mixed slots");
    r.ok(offer.mixed.every(s => s && s.kind === "base"), "with rng=0 the mixed slots are all Bases");
    const id = offer.mixed[0].id;
    const res = c.buyMixedSlot(0, () => 0.0);
    r.ok(res.ok && res.kind === "base", "buy an offered Base into inventory");
    r.eq(offer.mixed[0], null, "the bought slot empties");
    r.eq(c.baseInventoryCount(id), 1, "the offered Base lands in inventory");
  }

  // --- charged/spent lifecycle ------------------------------------------
  {
    const e = game(["randomSticker", null, null]);
    r.eq(e.getRun().basesUsed[0], false, "Base is charged at deal start");
    r.ok(e.baseAvailable(0), "a charged Base in active play is available");
    r.ok(!e.baseAvailable(1), "an empty column has no Base");
    e.baseActivate(0);
    r.eq(e.getRun().basesUsed[0], true, "activating spends the Base");
    r.ok(!e.baseAvailable(0), "a spent Base is unavailable (once per deal)");
  }

  // --- effect: Upheaval (shuffle the column; cost = 1 coin per shuffled pile) --
  {
    const e = game(["shuffleColumn", null, null]);
    const b = e.getBoard();
    for (const i of [0, 1, 2]) { b.piles[i].cards = [card(3, "♠"), card(4, "♠"), card(5, "♠")]; }
    const deckBefore = e.getDeck().remaining();
    const coinsBefore = e.getRun().bonusCoins;
    const res = e.baseActivate(0);
    r.eq(res.shuffled, 3, "all 3 alive piles in the column are shuffled");
    r.eq(e.getDeck().remaining(), deckBefore, "no cards returned to the deck (cost is coins now)");
    r.eq(e.getRun().bonusCoins - coinsBefore, -3, "lost 1 coin per shuffled pile (−3)");
  }

  // --- effect: Phoenix (revive — keep the KILLER card; buried cards → deck) --
  {
    const e = game(["revive", null, null]);
    const b = e.getBoard();
    b.piles[1].cards = [card(3, "♠"), card(4, "♥"), card(9, "♦")]; b.kill(1);   // 9♦ = killer (top)
    const before = e.getDeck().remaining();
    const res = e.baseActivate(0);
    r.eq(res.index, 1, "the only dead pile in the column is revived");
    r.ok(b.isActive(1), "the pile is alive again");
    r.eq(b.piles[1].cards.length, 1, "the revived pile has exactly ONE card (never empty)");
    r.eq(b.top(1).value, 9, "the KILLER card is kept as the pile card (value)");
    r.eq(b.top(1).suit, "♦", "the KILLER card is kept as the pile card (suit)");
    r.eq(e.getDeck().remaining(), before + 2, "only the 2 buried cards returned to the deck (killer kept)");
    const e3 = game(["revive", null, null]);
    r.ok(!e3.baseAvailable(0), "Revive is unavailable with no dead pile in its column");
  }

  // --- effect: Random Sticker (RANDOM pile in the column, no choice) -----
  {
    const e = game(["randomSticker", null, null]);
    const b = e.getBoard();
    const res = e.baseActivate(0);   // no target argument — it picks for you
    r.ok(res && res.stickerApplied, "a sticker is applied to a random pile card");
    r.ok([0, 1, 2].includes(res.index), "the random target is a pile in the Base's column");
    r.eq(b.top(res.index).stickers.length, 1, "the targeted pile card now carries one sticker");
  }

  // --- effect: Ballast (balance only the ♦ piles in the column) ----------
  {
    const e = game(["evenOut", null, null]);
    const b = e.getBoard();
    b.piles[0].cards = [card(2, "♦"), card(3, "♦"), card(4, "♦"), card(5, "♦")];   // ♦ pile, size 4
    b.piles[1].cards = [card(6, "♦")];                                             // ♦ pile, size 1
    b.piles[2].cards = [card(7, "♠"), card(8, "♠"), card(9, "♠")];                 // NON-♦ pile — untouched
    e.baseActivate(0);
    r.eq(b.pileSize(2), 3, "the non-♦ pile is left completely untouched");
    r.ok(Math.abs(b.pileSize(0) - b.pileSize(1)) <= 1, "the two ♦ piles end within 1 card of each other");
  }

  // --- effect: Landslide (bury 2 under each ♣-top pile, −3 coins per card) --
  {
    const e = game(["buryAll", null, null]);
    const b = e.getBoard();
    b.piles[0].cards = [card(2, "♣")];
    b.piles[1].cards = [card(3, "♣")];
    b.piles[2].cards = [card(4, "♥")];   // non-♣ → skipped
    const before = e.getDeck().remaining();
    const coinsBefore = e.getRun().bonusCoins;
    const res = e.baseActivate(0);
    r.eq(res.buried, 4, "buried 2 under each of the 2 ♣ piles (4 cards)");
    r.eq(e.getDeck().remaining(), before - 4, "four cards left the deck");
    r.eq(e.getRun().bonusCoins - coinsBefore, -12, "lost 3 coins per card buried (−12)");
    r.eq(b.piles[2].cards.length, 1, "the non-♣ pile is untouched");
  }

  // --- effect: Cast (copy the bottom pile's RANK onto the column's tops) --
  {
    const e = game(["setValue", null, null]);
    const b = e.getBoard();
    b.piles[0].cards = [card(5, "♠")];
    b.piles[1].cards = [card(9, "♥")];
    b.piles[2].cards = [card(3, "♦")];   // bottom pile of col 0 → rank 3 is the source
    const res = e.baseActivate(0);
    r.eq(res.sourceValue, 3, "the source rank is the bottom pile's rank (3)");
    r.ok([0, 1, 2].every(i => b.top(i).value === 3), "every top card in the column becomes rank 3");
    r.ok(res.valueApplied.length >= 1, "the changed cards are recorded for run-level persistence");
    r.ok(res.valueApplied.every(v => v.value === 3), "each recorded change carries the copied rank");
  }

  // --- effect: Suit Setter (copy the bottom pile's SUIT onto the tops) ---
  {
    const e = game([null, "setSuit", null]);   // col 1 = piles 3-6
    const b = e.getBoard();
    b.piles[3].cards = [card(5, "♠")];
    b.piles[4].cards = [card(9, "♥")];
    b.piles[5].cards = [card(3, "♦")];
    b.piles[6].cards = [card(2, "♣")];   // bottom pile of col 1 → ♣ is the source suit
    const res = e.baseActivate(1);
    r.eq(res.sourceSuit, "♣", "the source suit is the bottom pile's suit (♣)");
    r.ok([3, 4, 5, 6].every(i => b.top(i).suit === "♣"), "every top card in the column becomes ♣");
    r.ok(res.suitApplied.every(s => s.suit === "♣"), "each recorded change carries the copied suit");
  }

  // --- effect: Sticker Harvest (bury 2 per sticker, then peel them) ------
  {
    const e = game(["stickerHarvest", null, null]);
    const b = e.getBoard();
    b.piles[0].cards = [card(7, "♠")];
    b.top(0).stickers = [{ type: "anchor" }, { type: "tieSafe" }];
    b.top(0).tieSafe = true;
    const before = e.getDeck().remaining();
    const res = e.baseActivate(0, 0);
    r.eq(res.harvested, 2, "harvested both stickers");
    r.eq(res.buried, 4, "reported 4 buried (2 per sticker)");
    r.eq(b.piles[0].cards.length, 1 + 4, "four cards buried under the pile (two per sticker)");
    r.eq(e.getDeck().remaining(), before - 4, "four cards left the deck");
    r.eq(b.top(0).stickers.length, 0, "every counted sticker peeled off the pile card");
    r.ok(!b.top(0).tieSafe, "the projected sticker flag is cleared too");
  }

  // --- effect: Club Dig (bury 1 under each ♣-top pile) -------------------
  {
    const e = game(["clubDig", null, null]);
    const b = e.getBoard();
    b.piles[0].cards = [card(5, "♣")];
    b.piles[1].cards = [card(6, "♣")];
    b.piles[2].cards = [card(7, "♠")];   // non-♣ → skipped
    const before = e.getDeck().remaining();
    const res = e.baseActivate(0);
    r.eq(res.buried, 2, "buried 1 under each of the 2 ♣ piles");
    r.eq(e.getDeck().remaining(), before - 2, "two cards left the deck");
    r.eq(b.piles[2].cards.length, 1, "the non-♣ pile is untouched");
  }

  // --- effect: Kamikaze (kill a ♠-top pile, then peek 3) ----------------
  {
    const e = game(["kamikaze", null, null]);
    const b = e.getBoard();
    b.piles[0].cards = [card(5, "♥")];   // not ♠ → not a legal target
    b.piles[1].cards = [card(6, "♠")];   // ♠ → legal
    r.ok(e.baseActivate(0, 0) === null, "Kamikaze refuses a non-♠ target");
    r.ok(b.isActive(0), "the non-♠ pile survives the refused sacrifice");
    const res = e.baseActivate(0, 1);
    r.ok(res && !b.isActive(1), "Kamikaze kills the chosen ♠ pile");
    r.eq((res.cards || []).length, 3, "and peeks the next 3 upcoming cards");
  }

  // --- effect: Spade Peeker (peek X = # of ♠-top piles in the column) ---
  {
    const e = game(["spadePeek", null, null]);
    const b = e.getBoard();
    b.piles[0].cards = [card(5, "♠")];
    b.piles[1].cards = [card(6, "♠")];
    b.piles[2].cards = [card(7, "♥")];
    const res = e.baseActivate(0);
    r.eq(res.peekCount, 2, "peeks the next 2 cards (2 ♠ piles)");
  }

  // --- effect: Heart Demolish (destroy ♥-top piles, +7 each) ------------
  {
    const e = game(["heartDemolish", null, null]);
    const b = e.getBoard();
    b.piles[0].cards = [card(5, "♥")];
    b.piles[1].cards = [card(6, "♥")];
    b.piles[2].cards = [card(7, "♠")];
    const before = e.getRun().bonusCoins;
    const res = e.baseActivate(0);
    r.ok(!b.isActive(0) && !b.isActive(1), "both ♥ piles are destroyed");
    r.ok(b.isActive(2), "the non-♥ pile survives");
    r.eq(e.getRun().bonusCoins - before, 14, "gained +7 per destroyed pile (+14)");
  }

  // --- effect: Heart Tax (+1 per ♥ in the column, top + buried) ----------
  {
    const e = game(["tax", null, null]);
    const b = e.getBoard();
    b.piles[0].cards = [card(5, "♥"), card(3, "♥")];   // 2 hearts (top + buried)
    b.piles[1].cards = [card(6, "♥")];                 // 1 heart
    b.piles[2].cards = [card(7, "♠")];                 // 0 hearts
    const res = e.baseActivate(0);
    r.eq(res.gained, 3, "tallied all 3 ♥ cards in the column (buried counts)");
    r.eq(e.getRun().bonusCoins, 3, "the coins were credited");
  }

  // --- effect: Refresh Bases (re-arm spent non-Refresh Bases) ------------
  {
    const e = game(["refreshBases", "kamikaze", "randomSticker"]);
    const b = e.getBoard();
    b.top(5).suit = "♠";              // give the Kamikaze target a ♠ top
    e.baseActivate(1, 5);            // spend Kamikaze (col 1) on the ♠ pile
    e.baseActivate(2);              // spend Wild Sticker (col 2)
    r.ok(e.getRun().basesUsed[1] && e.getRun().basesUsed[2], "both other Bases are spent");
    const res = e.baseActivate(0);
    r.ok(res.refreshed.includes(1) && res.refreshed.includes(2), "both spent Bases re-armed");
    r.eq(e.getRun().basesUsed[1], false, "Kamikaze re-armed");
    r.eq(e.getRun().basesUsed[2], false, "Wild Sticker re-armed");
    r.ok(e.getRun().basesUsed[0], "Refresh Bases itself is spent");
  }

  // --- Refresh Bases NEVER re-arms another Refresh Bases (no infinite loop) -
  {
    const e = game(["refreshBases", "refreshBases", "kamikaze"]);
    const b = e.getBoard();
    b.top(7).suit = "♠"; b.top(8).suit = "♠";   // ♠ Kamikaze targets in col 2
    e.baseActivate(2, 7);   // spend Kamikaze (col 2)
    e.baseActivate(1);      // col 1 Refresh re-arms Kamikaze, spends itself
    r.eq(e.getRun().basesUsed[1], true, "col 1 Refresh Bases is now spent");
    e.baseActivate(2, 8);   // spend Kamikaze again so col 0 has something to refresh
    const res = e.baseActivate(0);
    r.ok(!res.refreshed.includes(1), "Refresh Bases is NOT in the refreshed set");
    r.eq(e.getRun().basesUsed[1], true, "the other Refresh Bases stays spent (no loop)");
    r.eq(e.getRun().basesUsed[2], false, "the non-Refresh Base was re-armed");
  }

  return r.summary();
}
