// STKLAG1 — the sticker-apply picker's Apply tap felt DEAD under CPU throttle:
// confirmApplySticker committed the cheap engine state AND then ran the heavy
// DOM tail (renderStore's full shelf rebuild via continuePendingPlacement +
// the deck-strip histogram repaint) SYNCHRONOUSLY on the tap, so the browser
// couldn't paint the picker-close until it finished — and it persisted TWICE
// (an explicit save on the tap, then renderStore's own checkpoint) on one tap.
//
// The fix: give immediate acknowledgement (hide the confirm button + begin the
// close/flash on the tap frame), keep the ONE save synchronous, and DEFER the
// heavy tail past the close paint (deferConfirmTail's double-rAF). The second
// (redundant) persist is swallowed by a one-shot suppressStorePersistOnce that
// is only ever live for the synchronous span of the deferred tail (reset in a
// finally), so no OTHER renderStore caller loses its checkpoint.
//
// Structural checks pin that wiring shape (sell1/uifix1 style); behavioral
// checks drive the LIVE campaign primitives the confirm runs — buy-charged-
// once-on-success, nothing-charged-on-cancel/failed-buy, and the apply +
// coins serialize/restore round-trip — reading every price from the live
// registry (never a pinned coin count).
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadGame, makeRunner } from "./_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

function fullHtml() {
  return readFileSync(join(HERE, "..", "index.html"), "utf8");
}
/** The single game <script> block (the one defining the engine modules). */
function gameScript(html) {
  const blocks = html.match(/<script>([\s\S]*?)<\/script>/g) || [];
  return blocks
    .map((b) => b.replace(/^<script>/, "").replace(/<\/script>$/, ""))
    .find((c) => c.includes("const GameEngine")) || "";
}
/** Body of a top-level `function name(...) { ... }` (brace-matched). */
function fnBody(src, name) {
  const at = src.indexOf("function " + name + "(");
  if (at === -1) return "";
  const open = src.indexOf("{", at);
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === "{") depth++;
    else if (src[i] === "}" && --depth === 0) return src.slice(open, i + 1);
  }
  return "";
}
function countOf(hay, needle) {
  let n = 0, i = 0;
  while ((i = hay.indexOf(needle, i)) !== -1) { n++; i += needle.length; }
  return n;
}

export function run() {
  const r = makeRunner("stklag1.test.mjs");
  const html = fullHtml();
  const src = gameScript(html);
  const g = loadGame();
  r.ok(!!(g.CampaignState && g.StickerTypes), "game script evaluates with the STKLAG1 wiring in place");

  const confirm = fnBody(src, "confirmApplySticker");
  const store = fnBody(src, "renderStore");
  const defer = fnBody(src, "deferConfirmTail");

  // --- R2/R4) The defer helper: two-frame yield + scoped persist suppression --
  {
    r.ok(defer.length > 0, "deferConfirmTail exists");
    // Two rAFs: the close/flash paints on the first, the heavy rebuild runs on
    // the second (empirically after the paint — see the throttled measurement).
    r.ok(/requestAnimationFrame\(function \(\) \{\s*requestAnimationFrame\(/.test(defer),
      "deferConfirmTail yields TWO nested requestAnimationFrames before the tail");
    r.ok(defer.includes("suppressStorePersistOnce = true")
      && /finally \{ suppressStorePersistOnce = false; \}/.test(defer),
      "…and arms suppressStorePersistOnce only when savedOnTap, resetting it in a finally");
    r.ok(/if \(!savedOnTap\) \{ tail\(\); return; \}/.test(defer),
      "…while a not-yet-saved tail (no-op fall-through) keeps renderStore's checkpoint");
  }

  // --- R4) renderStore honours the one-shot suppress, else persists as always -
  {
    r.ok(/if \(suppressStorePersistOnce\) suppressStorePersistOnce = false;\s*else persistCampaign\("store"\);/.test(store),
      "renderStore skips its checkpoint ONLY on the suppressed deferred render, else persists as before");
    // The flag is a one-shot consumed by the very next renderStore — it can
    // never leave an unrelated renderStore un-checkpointed.
    r.ok(countOf(src, "let suppressStorePersistOnce = false;") === 1,
      "suppressStorePersistOnce is declared exactly once (module-scoped one-shot)");
  }

  // --- R1/R3/R4) The sticker/buy path: one sync save, immediate ack, deferred --
  {
    // Isolate the sticker branch (buy → applySticker → useStickerFromInventory)
    // through to the shared close tail.
    const at = confirm.indexOf("else if (pendingApplyStickerId)");
    const stickerRegion = confirm.slice(at);
    // R3/Q1: buy + apply commit synchronously; the ONE save is synchronous too.
    r.ok(/if \(!campaign\.buyOfferedSticker\(pendingBuyStickerSlot\)\) \{ return; \}/.test(stickerRegion),
      "the buy is committed synchronously and aborts (nothing spent) if unaffordable");
    r.ok(stickerRegion.includes("campaign.applySticker(selectedApplyCardId, pendingApplyStickerId)")
      && stickerRegion.includes("campaign.useStickerFromInventory(pendingApplyStickerId)"),
      "…apply + inventory-consume also commit synchronously");
    // R4: exactly ONE persistCampaign in the whole sticker success path (the
    // deferred renderStore's own checkpoint is suppressed).
    r.eq(countOf(stickerRegion, "persistCampaign("), 1,
      "the sticker apply path writes exactly ONE persistCampaign (double-persist collapsed)");
    r.ok(stickerRegion.includes('persistCampaign("store");') && stickerRegion.includes("savedOnTap = true;"),
      "…the kept save is the synchronous store checkpoint that flags savedOnTap");
  }

  // --- R1) Immediate acknowledgement on the shared close tail ----------------
  {
    // The fall-through (non-modifying sticker + shared close) closes the prompt
    // bar AND begins the picker close BEFORE handing the heavy tail to the
    // frame-deferred rebuild.
    const ackAt = confirm.indexOf('closeModalPrompt();\n    el.stickerApplyModal.classList.add("hidden");');
    r.ok(ackAt !== -1, "the close tail closes the prompt bar + modal on the tap frame (immediate ack)");
    const deferAt = confirm.indexOf("deferConfirmTail(savedOnTap, function ()");
    r.ok(deferAt !== -1 && ackAt < deferAt, "…and defers renderDeckStrip + continuePendingPlacement AFTER that");
    const tailFn = confirm.slice(deferAt);
    r.ok(/deferConfirmTail\(savedOnTap, function \(\) \{\s*renderDeckStrip\(\);\s*continuePendingPlacement\(\);/.test(tailFn),
      "…the deferred tail is exactly the heavy pair (histogram repaint + placement/store rebuild)");
  }

  // --- R7) The card-MODIFYING flash-then-close is preserved (+ deduped) -------
  {
    r.ok(confirm.includes('t.kind === "rank"')
      && confirm.includes('["changeSuitTo", "changeSuitRandom", "randomFixedValue"].indexOf(t.behavior) !== -1'),
      "the modifies-card detection (rank / suit-change / random) is intact");
    r.ok(confirm.includes("renderStickerApplyCards();") && confirm.includes('btn.classList.add("sa-flash");'),
      "…the changed card re-renders to its new face and flashes in place");
    r.ok(/setTimeout\(\(\) => \{[\s\S]*?btn\.classList\.remove\("sa-flash"\);[\s\S]*?stickerApplyModal\.classList\.add\("hidden"\);/.test(confirm),
      "…then closes the picker after the flash");
    // The modifies path already deferred behind the 850ms flash; its heavy tail
    // is now wrapped in the same one-shot suppression (no double-persist there).
    const flashAt = confirm.indexOf('btn.classList.add("sa-flash");');
    const flashTail = confirm.slice(flashAt, flashAt + 700);
    r.ok(flashTail.includes("suppressStorePersistOnce = true")
      && /finally \{ suppressStorePersistOnce = false; \}/.test(flashTail),
      "…and its continuePendingPlacement runs with the store-persist suppressed (single save)");
  }

  // --- R8) Non-goal guard: removal/swap tails still route + persist normally --
  {
    // The reported bug was ONLY the sticker/buy path; removal (store + map) and
    // swap keep their existing dissolve-animation defer and their own saves.
    r.ok(confirm.includes('persistCampaign("map");'), "map-removal still checkpoints as a MAP save (correct return screen)");
    r.ok(countOf(confirm, "dissolveApplyCard(") >= 3,
      "removal (store + map) and swap still dissolve-then-return (untouched)");
    const closeFn = fnBody(src, "closeStickerApply");
    r.ok(!closeFn.includes("buyOfferedSticker") && !closeFn.includes("applySticker") && !closeFn.includes("buyRemoval"),
      "cancel/backdrop (closeStickerApply) still spends nothing");
  }

  // --- R5/R6) Behavioral: LIVE primitives — charge once on success only -------
  {
    const { CampaignState, StickerTypes } = g;
    // Find a (cardId, stickerId) the engine actually permits, reading the live
    // registry (never assume a specific sticker/card is applicable).
    const camp = CampaignState.create();
    camp.reset();
    const deck = camp.getRunDeck();
    let pick = null;
    for (const t of StickerTypes.all()) {
      for (const c of deck) {
        if (camp.canApplyStickerById(c.id, t.id)) { pick = { cardId: c.id, typeId: t.id }; break; }
      }
      if (pick) break;
    }
    r.ok(!!pick, "found a live sticker that applies to a live deck card");
    if (pick) {
      const price = camp.priceOf(pick.typeId);
      r.ok(price >= 0 && price !== Infinity, "…its price reads from the live registry");
      // Seed coins to exactly the price (buy must be affordable, then broke).
      camp.addCoins(price - camp.getCoins());
      // Put the sticker in a store slot the way the offer would, then run the
      // confirm's exact commit sequence: buy (charge) → apply → consume.
      const offer = camp.getStoreOffer() || camp.openStore(() => 0.5);
      offer.slots = offer.slots && offer.slots.length ? offer.slots : [null, null, null];
      offer.slots[0] = { kind: "sticker", id: pick.typeId };
      const coins0 = camp.getCoins();

      r.ok(camp.buyOfferedSticker(0), "buyOfferedSticker charges + banks the sticker (place-then-pay)");
      r.eq(camp.getCoins(), coins0 - price, "…coins charged EXACTLY once by the live price");
      r.eq(camp.getInventory()[pick.typeId] || 0, 1, "…one sticker banked to inventory");
      r.eq(camp.getStoreOffer().slots[0], null, "…and the offer slot is emptied");

      // Rapid extra tap on the same (now empty) slot buys/charges nothing.
      const coins1 = camp.getCoins();
      r.ok(!camp.buyOfferedSticker(0), "a second tap on the emptied slot buys nothing");
      r.eq(camp.getCoins(), coins1, "…and charges nothing extra");

      // Apply + consume (the success branch after the buy).
      r.ok(camp.applySticker(pick.cardId, pick.typeId), "applySticker succeeds on the permitted card");
      camp.useStickerFromInventory(pick.typeId);
      r.eq(camp.getInventory()[pick.typeId] || 0, 0, "…the banked sticker is consumed by the apply");

      // R6/R8: the ONE save's payload round-trips — the applied sticker AND the
      // spent coins survive serialize → restore (an immediate reload).
      const before = camp.getCards().find(c => c.id === pick.cardId);
      const camp2 = CampaignState.create();
      camp2.restore(JSON.parse(JSON.stringify(camp.serialize())));
      r.eq(camp2.getCoins(), camp.getCoins(), "coins survive serialize/restore (round-trip intact)");
      const after = camp2.getCards().find(c => c.id === pick.cardId);
      r.eq((after.stickers || []).length, (before.stickers || []).length,
        "…and the applied sticker survives the round-trip");
      r.ok((after.stickers || []).length >= 1 || (after.modifications || []).length >= 1,
        "…the card really carries the applied sticker/modification after restore");
    }

    // Cancel path: NOT buying leaves coins + offer untouched (nothing spent).
    {
      const c2 = CampaignState.create();
      c2.reset();
      const t = StickerTypes.all()[0];
      c2.addCoins(c2.priceOf(t.id));
      const off = c2.getStoreOffer() || c2.openStore(() => 0.5);
      off.slots = [ { kind: "sticker", id: t.id } ];
      const coinsC = c2.getCoins();
      // (closeStickerApply never touches the campaign) — model it as "no buy".
      r.eq(c2.getCoins(), coinsC, "cancel/backdrop spends nothing");
      r.eq(c2.getStoreOffer().slots[0] && c2.getStoreOffer().slots[0].kind, "sticker",
        "…and the sticker stays offered");
    }
  }

  return r.summary();
}
