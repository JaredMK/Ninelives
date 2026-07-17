// PACKS2 — the pack-keep PLACEMENT WALK: after buying a card pack (or a single
// card) and picking the cards, the player is walked through placing EACH kept
// card, one swap-picker at a time, and returns to the shelf only when the pack
// tray is empty. Each step can SWAP (replaceDeckCard) or SKIP (discardPackCard,
// no refund) so the player takes 0/1/2. This is the DOM-free proof of the walk's
// engine contract — the primitives the UI's advancePackKeepWalk/skipCurrentPack
// Keep drive. Counts are read LIVE off the registry / tray (never a hardcoded 2).
import { loadGame, makeRunner } from "./_harness.mjs";

function rngFrom(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function run() {
  const { CampaignState, PackTypes } = loadGame();
  const r = makeRunner("packs2.test.mjs");

  // Mirror confirmPackPick's card branch: keep the FIRST `keep` revealed cards
  // into the tray (the walk then places whatever's in the tray).
  const keepInto = (c, revealed, keep) => revealed.slice(0, keep).map(card => (c.addPackCard(card), card));

  // Mirror advancePackKeepWalk / skipCurrentPackKeep exactly: place the tray one
  // card at a time from the FRONT (the tray compacts, so the walk always sits at
  // index 0). `decide(step,total,c)` returns {action:"swap",dealtId} or
  // {action:"skip"}. Returns the number of steps — which MUST equal the tray size
  // the walk began with (it returns to the store only when the tray is empty).
  function walkPackKeep(c, decide) {
    let steps = 0;
    const total = c.packTrayCount();
    // The walk continues WHILE the tray is non-empty — this is the "return to the
    // store only when the tray is empty" contract, driven off the live count.
    while (c.packTrayCount() > 0) {
      const d = decide(steps, total, c) || { action: "skip" };
      if (d.action === "swap") {
        const ok = c.replaceDeckCard(d.dealtId, 0);
        r.ok(ok, "walk step " + steps + ": swap consumed the front tray card (replaceDeckCard)");
      } else {
        const ok = c.discardPackCard(0);
        r.ok(ok, "walk step " + steps + ": skip declined the front tray card (discardPackCard)");
      }
      steps++;
      if (steps > total + 2) { r.ok(false, "walk terminated (no runaway)"); break; }   // safety
    }
    return steps;
  }

  // --- Keep-2 pack enqueues 2 placements; SWAP BOTH -----------------------
  {
    const c = CampaignState.create();
    const keep = PackTypes.get("cardPack").keep;             // LIVE — never hardcoded
    r.ok(keep >= 2, "large card pack keep is >1 (got " + keep + ")");
    const deckLen = c.getCards().length;
    const revealed = c.revealPack("cardPack", rngFrom(101));
    const kept = keepInto(c, revealed, keep);
    r.eq(c.packTrayCount(), keep, "picking " + keep + " cards enqueues " + keep + " placements in the tray");

    // Walk: swap every kept card onto a distinct in-play deck card.
    const targets = c.getCards().filter(x => !x.joker).slice(0, keep).map(x => x.id);
    let i = 0;
    const steps = walkPackKeep(c, () => ({ action: "swap", dealtId: targets[i++] }));
    r.eq(steps, keep, "the walk ran exactly " + keep + " placement steps (one per kept card)");
    r.eq(c.packTrayCount(), 0, "tray empty after the walk — only now does it return to the store");
    // Deck stays 52 (each swap removes one, adds one); both kept ids are in the deck.
    r.eq(c.getCards().length, deckLen, "deck size unchanged by 2 swaps (each keeps it 52)");
    const ids = new Set(c.getCards().map(x => x.id));
    r.ok(kept.filter(k => !k.blank).every(k => ids.has(k.id)), "both swapped-in cards are now deck cards");
    r.ok(targets.every(t => !ids.has(t)), "both replaced cards are gone from the deck");
  }

  // --- Keep-2 pack; SWAP first, SKIP second → exactly 1 replacement --------
  {
    const c = CampaignState.create();
    const keep = PackTypes.get("cardPack").keep;
    const deckLen = c.getCards().length;
    const kept = keepInto(c, c.revealPack("cardPack", rngFrom(202)), keep);
    const target = c.getCards().find(x => !x.joker).id;
    const steps = walkPackKeep(c, (step) => step === 0 ? { action: "swap", dealtId: target } : { action: "skip" });
    r.eq(steps, keep, "walk still steps once per kept card even when some are skipped");
    r.eq(c.packTrayCount(), 0, "tray empty (the skipped card was discarded, not stranded)");
    r.eq(c.getCards().length, deckLen, "one swap keeps the deck at 52 (the skip changed nothing)");
    const ids = new Set(c.getCards().map(x => x.id));
    r.ok(!ids.has(target), "the swapped-out card is gone");
    r.ok(kept[0].blank || ids.has(kept[0].id), "the FIRST kept card was swapped in");
    r.ok(!ids.has(kept[1].id), "the SECOND (skipped) kept card never entered the deck");
  }

  // --- Keep-2 pack; SKIP BOTH → deck + coins unchanged, only purchase spent
  {
    const c = CampaignState.create();
    c.addCoins(500);
    // Buy a CARD pack from a real store slot so the ONLY spend is the pack price.
    let bought = null, price = 0;
    for (let i = 0; i < 600 && !bought; i++) {
      const offer = c.openStore();
      const slot = offer.slots.findIndex(s => s && s.kind === "pack" && (PackTypes.get(s.id) || {}).kind === "card");
      if (slot === -1) continue;
      price = PackTypes.get(offer.slots[slot].id).price;
      const coinsBefore = c.getCoins();
      const res = c.buyMixedSlot(slot, rngFrom(303));
      if (res.ok && res.kind === "pack") { bought = res; r.eq(c.getCoins(), coinsBefore - price, "buying the pack charged exactly its price"); }
    }
    r.ok(bought, "found + bought a card pack from the shelf");
    const keep = bought.reveal.keep;
    const deckLen = c.getCards().length;
    const coinsAfterBuy = c.getCoins();
    keepInto(c, bought.reveal.items, keep);
    r.eq(c.packTrayCount(), keep, "kept " + keep + " cards into the tray");
    // Skip EVERY card: take 0.
    const steps = walkPackKeep(c, () => ({ action: "skip" }));
    r.eq(steps, keep, "the walk still visits every kept card before returning to the store");
    r.eq(c.packTrayCount(), 0, "tray empty after skipping all — nothing stranded");
    r.eq(c.getCards().length, deckLen, "skip-both leaves the deck exactly as it was");
    r.eq(c.getCoins(), coinsAfterBuy, "skip-both spends NO extra coins — no refund of the purchase, no new charge");
  }

  // --- Single-card buy degenerates to a ONE-card walk (swap or skip) -------
  {
    // Swap path.
    const c = CampaignState.create();
    const deckLen = c.getCards().length;
    const card = c.genPackCard(rngFrom(404));
    c.addPackCard(card);   // mirrors buyMixedSlot's card branch (one card into the tray)
    r.eq(c.packTrayCount(), 1, "a single bought card enqueues one placement");
    const target = c.getCards().find(x => !x.joker).id;
    const steps = walkPackKeep(c, () => ({ action: "swap", dealtId: target }));
    r.eq(steps, 1, "single-card walk runs exactly one step");
    r.eq(c.packTrayCount(), 0, "tray empty after the one placement");
    r.eq(c.getCards().length, deckLen, "the swap kept the deck at 52");
    r.ok(card.blank || c.getCards().some(x => x.id === card.id), "the bought card entered the deck");
  }
  {
    // Skip path: a single bought card can be declined too (consistent Skip).
    const c = CampaignState.create();
    const deckLen = c.getCards().length;
    c.addPackCard(c.genPackCard(rngFrom(505)));
    const steps = walkPackKeep(c, () => ({ action: "skip" }));
    r.eq(steps, 1, "single-card SKIP walk runs one step");
    r.eq(c.packTrayCount(), 0, "the declined single card left the tray (not stranded)");
    r.eq(c.getCards().length, deckLen, "declining a single bought card changes nothing in the deck");
  }

  // --- Mid-walk persistence: after resolving the first card, the tray state
  //     (the remaining card) round-trips so a refresh keeps it placeable -----
  {
    const c = CampaignState.create();
    const keep = PackTypes.get("cardPack").keep;
    keepInto(c, c.revealPack("cardPack", rngFrom(606)), keep);
    // Resolve ONE card (swap), then serialize MID-walk (tray still holds keep-1).
    const target = c.getCards().find(x => !x.joker).id;
    c.replaceDeckCard(target, 0);
    r.eq(c.packTrayCount(), keep - 1, "one card resolved — the rest still wait in the tray");
    const snap = JSON.parse(JSON.stringify(c.serialize()));
    r.eq(snap.packTray.length, keep - 1, "a mid-walk snapshot carries the still-unplaced tray card(s)");
    const c2 = CampaignState.create();
    r.ok(c2.restore(snap), "restore accepts the mid-walk snapshot");
    r.eq(c2.packTrayCount(), keep - 1, "the remaining kept card survives a refresh (still placeable, GO TO MAP stays gated)");
    // …and it's still a legal swap target after the refresh.
    const t2 = c2.getCards().find(x => !x.joker).id;
    r.ok(c2.replaceDeckCard(t2, 0), "the restored tray card can still be swapped in after the refresh");
    r.eq(c2.packTrayCount(), keep - 2 < 0 ? 0 : keep - 2, "resolving it empties the tray");
  }

  return r.summary();
}
