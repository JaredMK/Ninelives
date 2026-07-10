// Pack-card replacement, end to end (the chain behind the pre-run "Replace"
// confirm): replaceDeckCard removes the target identity from the campaign deck,
// inserts the held pack card (with its stickers), the board top is mirrored to
// the new card, the pack leaves the tray, and the whole thing persists through
// serialize/restore. Mirrors UIRenderer.doReplace() step for step.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const { CampaignState, GameEngine, DeckManager } = loadGame();
  const r = makeRunner("pack-replace.test.mjs");

  // Deterministic pack card with a known sticker, so we can assert it rides.
  function stickeredPackCard(c) {
    // genPackCard rolls stickers by chance; force one deterministically instead.
    const card = c.genPackCard(() => 0.5);
    if (!card.stickers.some(s => s.type === "tieSafe")) card.stickers.push({ type: "tieSafe" });
    return card;
  }

  // --- Full chain: confirm -> swap executes end to end -------------------
  {
    const c = CampaignState.create();
    // A fresh deck is the 52 identities PLUS any duplicates map generation
    // minted for over-drafted +1 nodes — a swap must keep the size it found.
    const baseLen = c.getCards().length;
    const pack = stickeredPackCard(c);
    c.addPackCard(pack);
    r.eq(c.packTrayCount(), 1, "pack card is held in the tray");

    // Build the run exactly like startRun(): engine off getRunDeck(), deal.
    const engine = GameEngine.create(c.getRunDeck(), 9, { cols: [3, 3, 3] });
    engine.start(12345);
    const boardTop = engine.getBoard().top(0);     // the dealt card on pile 0
    const dealtId = boardTop.id;
    r.ok(c.getCards().some(x => x.id === dealtId), "dealt card's id exists in the campaign deck (lookup will hit)");

    // === the operation doReplace() performs on confirm ===
    const packCard = c.replaceDeckCard(dealtId, 0);
    r.ok(packCard && packCard.id === pack.id, "replaceDeckCard returns the held pack card (not null)");
    // mirror onto the live board card, as doReplace does
    Object.assign(boardTop, DeckManager.toCard(packCard));

    // 1) old identity removed from the campaign deck (its stickers gone)
    r.ok(!c.getCards().some(x => x.id === dealtId), "old card removed from the campaign deck");
    // 2) pack card inserted, deck size unchanged, stickers intact on it
    r.eq(c.getCards().length, baseLen, "deck size unchanged by the swap");
    const inserted = c.getCards().find(x => x.id === pack.id);
    r.ok(inserted, "pack card inserted into the campaign deck");
    r.ok(inserted.stickers.some(s => s.type === "tieSafe"), "pack card keeps its sticker(s) in the deck");
    // 3) board top now shows the pack card (so the pile visibly + mechanically swaps)
    r.eq(boardTop.id, pack.id, "board top is now the pack card (board reflects the swap)");
    r.eq(engine.getBoard().top(0).id, pack.id, "engine board top is the pack card (same live object)");
    r.ok(boardTop.tieSafe, "board top carries the pack card's Tie-Safe flag (toCard projected it)");
    // 4) pack card removed from the tray on success
    r.eq(c.packTrayCount(), 0, "pack card left the tray after the swap");
    // 4b) the OWNED set follows the swap so the deck VIEW matches the COUNT (#1):
    // deckSize() (ownedIds) and getRunDeck() (baseDeck ∩ ownedIds) must agree, and
    // the inserted card must be visible while the old one is gone.
    r.eq(c.getRunDeck().length, c.deckSize(), "deck view (getRunDeck) matches the count (deckSize) after a swap");
    r.ok(c.getRunDeck().some(x => x.id === pack.id), "swapped-in card appears in the deck view");
    r.ok(!c.getRunDeck().some(x => x.id === dealtId), "swapped-out card is gone from the deck view");

    // 5) persisted: a serialize/restore round-trip keeps the replacement
    const wire = JSON.parse(JSON.stringify(c.serialize()));
    const c2 = CampaignState.create();
    r.ok(c2.restore(wire), "restore accepts the post-swap snapshot");
    r.ok(!c2.getCards().some(x => x.id === dealtId), "old card stays gone after save/restore");
    const inserted2 = c2.getCards().find(x => x.id === pack.id);
    r.ok(inserted2 && inserted2.stickers.some(s => s.type === "tieSafe"),
      "pack card (with stickers) persists across save/restore");
    r.eq(c2.packTrayCount(), 0, "tray stays empty after save/restore");
  }

  // --- Guard: a bad target id can't silently 'succeed' ------------------
  {
    const c = CampaignState.create();
    const baseLen = c.getCards().length;   // 52 identities + any map-minted duplicates
    c.addPackCard(c.genPackCard(() => 0.3));
    r.eq(c.replaceDeckCard(99999, 0), null, "unknown dealt id returns null (no swap)");
    r.eq(c.packTrayCount(), 1, "a failed lookup leaves the tray untouched");
    r.eq(c.replaceDeckCard(c.getCards()[0].id, 7), null, "out-of-range tray index returns null");
    r.eq(c.getCards().length, baseLen, "a failed replace doesn't change the deck size");
  }

  return r.summary();
}
