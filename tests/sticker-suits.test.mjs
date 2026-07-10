// Suit-based sticker restrictions (items.js `suits` field) + the global
// Joker/Removal sticker exclusion. DOM-free: drive CampaignState (the gate
// behind every picker/purchase path) and GameEngine (Wild Sticker) directly.
// items.js MAY ship stickers with restrictions (a data decision, not pinned
// here) — the behavior tests below add their own at runtime on isolated
// loadGame() instances, exactly like a hand-edit of items.js would.
import { loadGame, makeRunner } from "./_harness.mjs";

export function run() {
  const r = makeRunner("sticker-suits.test.mjs");

  // ---- shipped `suits` fields, where present, are WELL-FORMED -----------
  {
    const { StickerTypes } = loadGame();
    const SUITS = ["♥", "♦", "♣", "♠"];
    const bad = StickerTypes.all().filter(t => t.suits != null
      && !(Array.isArray(t.suits) && t.suits.length > 0 && t.suits.every(s => SUITS.includes(s))));
    r.eq(bad.length, 0, "every shipped `suits` field is a non-empty array of valid suit symbols");
  }

  // ---- canApplySticker: the `suits` field gates by printed suit ---------
  {
    const { CampaignState, StickerTypes } = loadGame();
    const camp = CampaignState.create({ pileCount: 9 });
    const cards = camp.getCards();
    const heart = cards.find(c => c.suit === "♥");
    const spade = cards.find(c => c.suit === "♠");
    // Model the whole lifecycle on this isolated instance regardless of what
    // items.js currently ships for gainCoin: first UNRESTRICTED…
    StickerTypes.get("gainCoin").suits = null;
    r.ok(camp.canApplySticker(heart, "gainCoin") && camp.canApplySticker(spade, "gainCoin"),
      "unrestricted sticker applies to any suit");
    StickerTypes.get("gainCoin").suits = ["♥"];          // ← …then a hand-edit of items.js
    r.ok(camp.canApplySticker(heart, "gainCoin"), "suits:[♥] sticker applies to a ♥ card");
    r.ok(!camp.canApplySticker(spade, "gainCoin"), "suits:[♥] sticker refuses a ♠ card");
    r.ok(!camp.applySticker(spade.id, "gainCoin"), "applySticker refuses the ♠ card");
    r.eq(spade.stickers.length, 0, "nothing attached to the refused card");
    r.ok(camp.applySticker(heart.id, "gainCoin"), "applySticker accepts the ♥ card");
    // getCards() returns snapshots — re-fetch to see the applied sticker.
    r.eq(camp.getCards().find(c => c.id === heart.id).stickers.length, 1, "the ♥ card carries the sticker");
    StickerTypes.get("gainCoin").suits = ["♥", "♦"];     // two-suit form
    const diamond = cards.find(c => c.suit === "♦");
    r.ok(camp.canApplySticker(diamond, "gainCoin"), "suits:[♥,♦] sticker applies to a ♦ card");
    r.ok(!camp.canApplySticker(spade, "gainCoin"), "suits:[♥,♦] sticker still refuses ♠");
  }

  // ---- WILD SUIT: a wild card counts as EVERY suit for eligibility ------
  // (registry-driven: every shipped suit-restricted sticker must accept a
  // Wild Suit card of a suit OUTSIDE its restriction, and the same card
  // without Wild Suit must refuse — the picker greys via this same gate.)
  {
    const { CampaignState, StickerTypes } = loadGame();
    const SUITS = ["♥", "♦", "♣", "♠"];
    const camp = CampaignState.create({ pileCount: 9 });
    // One mid-rank card per suit (dodges rank-boundary gates), made wild;
    // a same-suit twin stays plain as the control.
    const wildBySuit = {}, plainBySuit = {};
    for (const s of SUITS) {
      const w = camp.getCards().find(c => c.suit === s && c.currentRank === 7);
      plainBySuit[s] = camp.getCards().find(c => c.suit === s && c.currentRank === 8);
      r.ok(camp.applySticker(w.id, "wildSuit"), "Wild Suit applies to the " + s + " 7");
      wildBySuit[s] = camp.getCards().find(c => c.id === w.id);   // re-fetch: snapshot now carries the sticker
    }
    const restricted = StickerTypes.all().filter(t =>
      Array.isArray(t.suits) && t.suits.length && t.suits.length < SUITS.length);
    r.ok(restricted.length > 0, "registry ships suit-restricted stickers (" + restricted.length + " found)");
    let wildOk = 0, plainRefused = 0;
    for (const t of restricted) {
      const off = SUITS.find(s => !t.suits.includes(s));   // a suit the sticker normally refuses
      if (camp.canApplySticker(wildBySuit[off], t.id)) wildOk++;
      if (!camp.canApplySticker(plainBySuit[off], t.id)) plainRefused++;
    }
    r.eq(wildOk, restricted.length, "a WILD card accepts every suit-restricted sticker off-suit (" + wildOk + "/" + restricted.length + ")");
    r.eq(plainRefused, restricted.length, "the plain off-suit twin refuses them all (control)");
    // A real apply sticks, not just the can-check:
    const t0 = restricted[0];
    const off0 = SUITS.find(s => !t0.suits.includes(s));
    const before = wildBySuit[off0].stickers.length;
    r.ok(camp.applySticker(wildBySuit[off0].id, t0.id), "applySticker attaches an off-suit " + t0.id + " to the wild card");
    r.eq(camp.getCards().find(c => c.id === wildBySuit[off0].id).stickers.length, before + 1,
      "the off-suit sticker is on the wild card");
  }

  // ---- WILD SUIT ordering: restricted first, wild second ----------------
  // Applying Wild Suit to a card that ALREADY has suit-restricted stickers
  // is always legal (Wild Suit itself is unrestricted); the existing
  // stickers stay, and the card thereafter counts as all suits.
  {
    const { CampaignState, StickerTypes } = loadGame();
    const camp = CampaignState.create({ pileCount: 9 });
    StickerTypes.get("gainCoin").suits = ["♥"];            // runtime hand-edit, isolated instance
    const heart = camp.getCards().find(c => c.suit === "♥" && c.currentRank === 7);
    r.ok(camp.applySticker(heart.id, "gainCoin"), "♥-only sticker applies to the ♥ card (matching suit)");
    r.ok(camp.applySticker(heart.id, "wildSuit"), "Wild Suit still applies over an existing suit-restricted sticker");
    r.eq(camp.getCards().find(c => c.id === heart.id).stickers.length, 2, "both stickers remain on the card");
    StickerTypes.get("gainCoin").suits = ["♠"];            // now restrict AWAY from the printed suit
    r.ok(camp.canApplySticker(camp.getCards().find(c => c.id === heart.id), "gainCoin"),
      "after Wild Suit, a ♠-only sticker is accepted on the printed-♥ card");
  }

  // ---- WILD SUIT (live board shape): Wild Sticker may target a wild top --
  // Live cards carry the .wildSuit flag (toCard / projection) instead of the
  // persistent sticker record — the shared gate must honor that shape too.
  {
    const { GameEngine, DeckManager, StickerTypes } = loadGame();
    for (const t of StickerTypes.all()) t.suits = ["♥"];   // everything ♥-only
    const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
    e.start(); e.startRun([null, null, null], ["randomSticker", null, null]);
    const b = e.getBoard();
    b.top(0).suit = "♠"; b.top(1).suit = "♠"; b.top(2).suit = "♠";
    b.top(1).wildSuit = true;   // the live Wild Suit flag
    r.ok(e.baseAvailable(0), "Wild Sticker is available: the wild ♠ top satisfies ♥-only stickers");
    const res = e.baseActivate(0);
    r.ok(!!(res && res.stickerApplied && res.stickerApplied.pileIndex === 1),
      "Wild Sticker targeted the WILD top (it counts as ♥)");
  }

  // ---- Jokers and Removal cards NEVER take stickers ---------------------
  {
    const { CampaignState, StickerTypes } = loadGame();
    const camp = CampaignState.create({ pileCount: 9 });
    const joker = { id: 9001, joker: true, suit: "★", originalRank: 0, currentRank: 0, modifications: [], stickers: [] };
    const removal = { id: 9002, blank: true, suit: "∅", originalRank: 0, currentRank: 0, modifications: [], stickers: [] };
    const refusedJ = StickerTypes.ids.every(id => !camp.canApplySticker(joker, id));
    const refusedR = StickerTypes.ids.every(id => !camp.canApplySticker(removal, id));
    r.ok(refusedJ, "a Joker refuses EVERY sticker type (" + StickerTypes.ids.length + " checked)");
    r.ok(refusedR, "a Removal card refuses EVERY sticker type");
  }

  // ---- pack-card generation respects a runtime restriction --------------
  {
    const { CampaignState, StickerTypes } = loadGame();
    for (const t of StickerTypes.all()) t.suits = ["♥"];   // restrict EVERYTHING to ♥
    const camp = CampaignState.create({ pileCount: 9 });
    let checked = 0, leaked = 0, heartsStickered = 0;
    let seed = 7;
    const rng = () => { seed = (seed * 1103515245 + 12345) % 2147483648; return seed / 2147483648; };
    for (let k = 0; k < 400; k++) {
      const c = camp.genPackCard(rng);
      if (c.joker || c.blank) { if (c.stickers.length) leaked++; continue; }
      checked++;
      // Eligibility is checked at APPLY time against the printed suit; a
      // Change-Suit sticker may legally land on a ♥ card and then move it to
      // another suit. So a stickered non-♥ card is a LEAK only if its suit was
      // never changed (it was non-♥ when the sticker attached).
      const suitChanged = (c.modifications || []).some(m => m.op === "changeSuit");
      if (c.suit !== "♥" && c.stickers.length && !suitChanged) leaked++;
      if (c.suit === "♥" && c.stickers.length) heartsStickered++;
    }
    r.eq(leaked, 0, "no never-♥ pack card ever minted a ♥-only sticker (" + checked + " cards)");
    r.ok(heartsStickered > 0, "♥ pack cards still mint stickers (" + heartsStickered + " did)");
  }

  // ---- Wild Sticker: Joker/Removal tops are never targets ---------------
  {
    const { GameEngine, DeckManager } = loadGame();
    const game = (bases) => {
      const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
      e.start(); e.startRun([null, null, null], bases);
      return e;
    };
    // All col-0 tops Jokers → the Base is unavailable outright.
    const e1 = game(["randomSticker", null, null]);
    for (const i of [0, 1, 2]) { const t = e1.getBoard().top(i); t.joker = true; t.suit = "★"; }
    r.ok(!e1.baseAvailable(0), "Wild Sticker is UNAVAILABLE when every top in its column is a Joker");
    // One Removal top + normal tops → the pick always lands on a normal top.
    let landedOnSpecial = 0, fired = 0;
    for (let k = 0; k < 12; k++) {
      const e = game(["randomSticker", null, null]);
      const b = e.getBoard();
      b.top(0).blank = true; b.top(0).suit = "∅";
      const res = e.baseActivate(0);
      if (res && res.stickerApplied) {
        fired++;
        if (res.stickerApplied.pileIndex === 0) landedOnSpecial++;
      }
    }
    r.eq(landedOnSpecial, 0, "Wild Sticker never targeted the Removal top (12 activations)");
    r.ok(fired === 12, "Wild Sticker fired on an eligible top every time (" + fired + "/12)");
  }

  // ---- Wild Sticker: `suits` restrictions steer the target pick ---------
  {
    const { GameEngine, DeckManager, StickerTypes } = loadGame();
    for (const t of StickerTypes.all()) t.suits = ["♥"];   // everything ♥-only
    const game = () => {
      const e = GameEngine.create(DeckManager.buildStandardDeck(), 10, { cols: [3, 4, 3] });
      e.start(); e.startRun([null, null, null], ["randomSticker", null, null]);
      return e;
    };
    // Only pile 1 shows a ♥ → it is the only legal target.
    let always1 = true;
    for (let k = 0; k < 8; k++) {
      const e = game();
      const b = e.getBoard();
      b.top(0).suit = "♠"; b.top(1).suit = "♥"; b.top(2).suit = "♣";
      const res = e.baseActivate(0);
      if (!res || !res.stickerApplied || res.stickerApplied.pileIndex !== 1) always1 = false;
    }
    r.ok(always1, "with every sticker ♥-only, Wild Sticker only ever stickers the ♥ top (8 activations)");
    // No ♥ anywhere in the column → the Base is unavailable (never a dead no-op).
    const e2 = game();
    for (const i of [0, 1, 2]) e2.getBoard().top(i).suit = "♠";
    r.ok(!e2.baseAvailable(0), "with every sticker ♥-only and no ♥ top, Wild Sticker is unavailable");
  }

  return r.summary();
}
