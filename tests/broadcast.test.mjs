// Broadcast Pillar — a passive force-multiplier that makes every COLUMN-SCOPED
// Base reach the whole board while it's in play. The engine is DOM-free, so we
// drive baseActivate() directly and assert the effect crossed column borders.
// Confirms: placement column is irrelevant, each Base still fires individually,
// already-board-wide Bases (Tax) are unchanged, and the target restriction on
// single-pile Bases (Sticker Harvest) lifts board-wide.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { GameEngine, DeckManager, PillarTypes } = loadGame();
  const r = makeRunner("broadcast.test.mjs");

  // col 0 = piles 0-2, col 1 = piles 3-6, col 2 = piles 7-9 (board size 10).
  const COLS = [3, 4, 3];
  const deck = () => DeckManager.buildStandardDeck();
  /** A started run binding column→Pillar and column→Base. */
  const game = (pillars, bases) => {
    const e = GameEngine.create(deck(), 10, { cols: COLS });
    e.start();
    e.startRun(pillars, bases);
    return e;
  };
  // `red` mirrors the real deck flag (♥/♦ red, ♠/♣ black) so suit-reading
  // effects like Tax behave as in-game.
  const card = (value, suit) => ({ value, suit, label: String(value), stickers: [], red: suit === "♥" || suit === "♦" });

  // --- registry ----------------------------------------------------------
  {
    const t = PillarTypes.get("broadcast");
    r.ok(!!t, "Broadcast is registered");
    r.eq(t.effect, "broadcast", "Broadcast carries the broadcast effect");
    r.eq(t.tier, "rare", "Broadcast is Rare");
    r.eq(t.price, 18, "Broadcast is priced at 18 (most expensive Pillar)");
    r.ok(t.kind !== "scoring", "Broadcast is a passive modifier, not a scoring Pillar");
    r.ok(t.description && t.icon, "Broadcast has a description + icon");
  }

  // --- broadcastActive() reads the pillar regardless of column -----------
  {
    r.ok(!game([null, null, null], [null, null, null]).broadcastActive(), "no Broadcast → inactive");
    r.ok(game(["broadcast", null, null], [null, null, null]).broadcastActive(), "Broadcast in col 0 → active");
    r.ok(game([null, null, "broadcast"], [null, null, null]).broadcastActive(), "Broadcast in col 2 → active (placement irrelevant)");
  }

  // --- Cast (setValue) goes board-wide; its base sits in a DIFFERENT column
  //     from the Broadcast pillar, proving placement doesn't matter ---------
  {
    const e = game([null, "broadcast", null], ["setValue", null, null]);
    e.getRun().baseRandom.value = 9;                       // pin the rolled value
    const b = e.getBoard();
    for (let i = 0; i < b.size; i++) b.piles[i].cards = [card(3, "♠")];
    e.baseActivate(0);                                     // Cast lives in col 0
    r.ok([0,1,2,3,4,5,6,7,8,9].every(i => b.top(i).value === 9),
      "Broadcast: Cast set EVERY pile on the board to the rolled value");
  }

  // --- Control: without Broadcast, Cast stays inside its own column -------
  {
    const e = game([null, null, null], ["setValue", null, null]);
    e.getRun().baseRandom.value = 9;
    const b = e.getBoard();
    for (let i = 0; i < b.size; i++) b.piles[i].cards = [card(3, "♠")];
    e.baseActivate(0);
    r.ok([0,1,2].every(i => b.top(i).value === 9), "no Broadcast: col-0 piles set");
    r.ok([3,4,5,6,7,8,9].every(i => b.top(i).value === 3), "no Broadcast: other columns untouched");
  }

  // --- Phoenix (reviveBase) precondition + effect widen board-wide --------
  {
    // A dead pile in COLUMN 1; Phoenix Base in COLUMN 0.
    const setup = (pillars) => {
      const e = game(pillars, ["revive", null, null]);
      const b = e.getBoard();
      b.piles[4].cards = [card(3, "♠"), card(9, "♦")]; b.kill(4);   // dead pile in col 1
      return e;
    };
    const noBc = setup([null, null, null]);
    r.ok(!noBc.baseAvailable(0), "no Broadcast: Phoenix can't fire (no dead pile in its own column)");

    const bc = setup(["broadcast", null, null]);
    r.ok(bc.baseAvailable(0), "Broadcast: Phoenix can fire (a pile is dead board-wide)");
    bc.baseActivate(0);
    r.ok(bc.getBoard().isActive(4), "Broadcast: Phoenix revived the dead pile in another column");
  }

  // --- Sticker Harvest target restriction lifts board-wide ---------------
  {
    const setup = (pillars) => {
      const e = game(pillars, ["stickerHarvest", null, null]);
      const b = e.getBoard();
      b.piles[5].cards = [card(7, "♠")];                  // a pile in col 1
      b.top(5).stickers = [{ type: "anchor" }];
      return e;
    };
    // Without Broadcast: a target outside the Base's column is rejected (no spend).
    const noBc = setup([null, null, null]);
    r.eq(noBc.baseActivate(0, 5), null, "no Broadcast: can't harvest a pile outside the column");
    r.ok(noBc.baseAvailable(0), "no Broadcast: the Base is still charged (nothing was spent)");

    // With Broadcast: the same cross-column target is accepted.
    const bc = setup(["broadcast", null, null]);
    const res = bc.baseActivate(0, 5);
    r.ok(res && res.harvested === 1, "Broadcast: harvested a pile in another column");
  }

  // --- already-board-wide Bases (Tax) are unchanged by Broadcast ---------
  {
    const measure = (pillars) => {
      const e = game(pillars, ["tax", null, null]);
      const b = e.getBoard();
      // 4 black pile cards spread across all three columns.
      b.piles[0].cards = [card(5, "♠")];
      b.piles[3].cards = [card(6, "♣")];
      b.piles[7].cards = [card(4, "♠")];
      b.piles[9].cards = [card(2, "♣")];
      for (const i of [1,2,4,5,6,8]) b.piles[i].cards = [card(5, "♥")];   // red — not taxed
      return e.baseActivate(0).gained;
    };
    const plain = measure([null, null, null]);
    r.eq(plain, 4, "Tax counts all 4 black pile cards board-wide");
    r.eq(plain, measure(["broadcast", null, null]),
      "Tax is unchanged by Broadcast (already global)");
  }

  return r.summary();
}
