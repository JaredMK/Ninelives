// STKPERF1 — the fossil sidecar (delta persistence for the display-only
// progression-map fossils) + the two-card pack-swap placement-walk cache pin.
//
// Step 0 profiling (see the STKPERF1 plan) measured the campaign save blob at
// 30.6 KB per deferred write on a 50-card late-run deck, ~47% of it
// `runFossils` — display-only map fossils that change ~once per deal but rode
// EVERY coalesced save write (and every iOS Preferences mirror). The fix:
// fossils persist in their OWN key (ninelives.fossils.v1, the SaveStore
// idiom), written ONLY when a fossil was recorded since the last write, via
// the SAME two-stage save flush the campaign blob uses (no timer of its own).
// The campaign blob drops the field; restore() still ADOPTS an old save's
// inline payload (one-time migration into the sidecar); clearSave() clears
// the sidecar with the campaign.
//
// (STKRB1 — concurrent work — owns the Stats write coalescing and the picker
// grid batching/targeted-update; stkrb1.test.mjs pins those. This suite pins
// only the sidecar + the walk-specific cache invariants.)
//
// Covered: (a) structural — serialize() excludes fossils, the sidecar store +
// key, the dirty-gated write hooked into writeCampaignSaveNow, the clearSave
// pairing, the boot-restore wiring; (b) behavioral — the extracted save layer
// (stklag2 idiom: fake timers + counting stores + a real CampaignState)
// proves the sidecar lands exactly once per fossil CHANGE through both the
// trailing idle write and the transition flush, never when clean, and can't
// resurrect after clearSave; (c) the campaign-side API (record/adopt/merge/
// malformed/reset); (d) the placement-walk cache pin — the two-card pack
// swap's SECOND card rides the warm applyCardNodes sig cache: the walk never
// clears the cache, re-attaches no listeners, reads no layout.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadGame, makeRunner } from "./_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

function fullHtml() {
  return readFileSync(join(HERE, "..", "index.html"), "utf8");
}
function gameScript(html) {
  const blocks = html.match(/<script>([\s\S]*?)<\/script>/g) || [];
  return blocks
    .map((b) => b.replace(/^<script>/, "").replace(/<\/script>$/, ""))
    .find((c) => c.includes("const GameEngine")) || "";
}
/** Brace-matched body of the function whose declaration starts at `sig`. */
function bodyAt(src, sig) {
  const at = src.indexOf(sig);
  if (at === -1) return "";
  const open = src.indexOf("{", at);
  let depth = 0;
  for (let i = open; i < src.length; i++) {
    if (src[i] === "{") depth++;
    else if (src[i] === "}" && --depth === 0) return src.slice(open, i + 1);
  }
  return "";
}
function fnBody(src, name) { return bodyAt(src, "function " + name + "("); }
function countOf(hay, needle) {
  let n = 0, i = 0;
  while ((i = hay.indexOf(needle, i)) !== -1) { n++; i += needle.length; }
  return n;
}

const FOSSIL = { alive: 3, total: 9, nodes: [{ x: 1, y: 2 }, { x: 3, y: 4 }], edges: [[0, 1]] };

export function run() {
  const r = makeRunner("stkperf1.test.mjs");
  const html = fullHtml();
  const src = gameScript(html);
  const g = loadGame();
  const { CampaignState } = g;
  r.ok(!!CampaignState, "game script evaluates with the STKPERF1 wiring in place");

  const writeNow = fnBody(src, "writeCampaignSaveNow");
  const fossilFn = fnBody(src, "writeFossilSidecarNow");
  const clear = fnBody(src, "clearSave");
  const persist = fnBody(src, "persistCampaign");
  const flush = fnBody(src, "flushCampaignSave");
  const arm = fnBody(src, "armSaveWrite");
  const blobFn = fnBody(src, "campaignSaveBlob");
  const serialize = bodyAt(src, "serialize() {\n        return {\n          schema: 2,");

  // ── Structural: the sidecar wiring ---------------------------------------
  {
    r.ok(src.includes('const KEY = "ninelives.fossils.v1";'),
      "the fossil sidecar store exists under ninelives.fossils.v1 (the mirrored prefix)");
    r.ok(serialize.length > 0 && !serialize.includes("runFossils:"),
      "CampaignState.serialize() no longer emits runFossils (the blob shrinks by their payload)");
    r.ok(fossilFn.includes("hasUnsavedFossils") && fossilFn.includes("serializeFossils()")
      && fossilFn.includes("markFossilsSaved()") && fossilFn.includes("zenMode"),
      "writeFossilSidecarNow is dirty-gated + zen-guarded and stamps the write");
    r.ok(writeNow.includes("writeFossilSidecarNow();"),
      "the sidecar write rides writeCampaignSaveNow (trailing idle write AND every flush)");
    r.ok(writeNow.indexOf("writeFossilSidecarNow();") < writeNow.indexOf("pendingSavePhase === null"),
      "…fired BEFORE the no-pending early return (a fossil flush needs no pending campaign save)");
    r.ok(clear.includes("FossilStore.clear()") && clear.includes("markFossilsSaved"),
      "clearSave clears the sidecar + drops the dirty flag (a wiped campaign keeps no fossils)");
    r.ok(!fossilFn.includes("setTimeout") && !fossilFn.includes("setInterval")
      && !src.includes("armFossilWrite"),
      "the sidecar has NO timer of its own (it rides the existing save mechanism)");
    // The boot restore path: old-save inline fossils adopted → populate the
    // sidecar; otherwise read the sidecar.
    r.ok(src.includes("if (campaign.hasUnsavedFossils()) writeFossilSidecarNow();")
      && src.includes("campaign.restoreFossils(FossilStore.load())"),
      "boot restore populates the sidecar from an adopted old save, else reads it");
  }

  // ── Behavioral: the save layer over fake timers + counting stores ---------
  // (stklag2 idiom: extract the real functions, drive them in isolation.)
  function buildSaver(campaign) {
    const parts = [
      "let pendingSavePhase = null;",
      "let saveCoalesceTimer = null;",
      "const SAVE_COALESCE_MS = 300;",
      "function campaignSaveBlob(phase) " + blobFn,
      "function writeFossilSidecarNow() " + fossilFn,
      "function writeCampaignSaveNow() " + writeNow,
      "function armSaveWrite() " + arm,
      "function persistCampaign(phase) " + persist,
      "function flushCampaignSave() " + flush,
      "function clearSave() " + clear,
      "return { persistCampaign, flushCampaignSave, clearSave, writeFossilSidecarNow };",
    ].join("\n");
    let timers = [], nextId = 1;
    const setT = (fn) => { const id = nextId++; timers.push({ id, fn }); return id; };
    const clrT = (id) => { timers = timers.filter((t) => t.id !== id); };
    const fire = () => { const t = timers; timers = []; t.forEach((x) => x.fn()); };
    const store = { saves: 0, clears: 0, last: null, save(b) { this.saves++; this.last = b; }, clear() { this.clears++; } };
    const fossils = { saves: 0, clears: 0, last: null, save(l) { this.saves++; this.last = l; }, clear() { this.clears++; } };
    const factory = new Function(
      "SaveStore", "FossilStore", "setTimeout", "clearTimeout", "requestIdleCallback",
      "campaign", "selectedDeckId", "engine", "redealCost", "appliedThisPhase", "currentDealSubset", "zenMode",
      parts);
    const api = factory(store, fossils, setT, clrT, setT, campaign, "pink", null, 0, false, null, null);
    return { api, store, fossils, fire };
  }

  {
    const camp = CampaignState.create(); camp.reset();
    camp.recordRunFossil(1, 1, FOSSIL);
    const c = buildSaver(camp);
    c.api.persistCampaign("store");
    r.eq(c.fossils.saves, 0, "a fossil change writes no sidecar synchronously (scheduled)");
    r.eq(c.store.saves, 0, "…nor a campaign blob (the STKLAG2 coalescing is intact)");
    c.fire(); c.fire();   // trailing timer → staged idle write
    r.eq(c.store.saves, 1, "the coalesced campaign write lands (one for the burst)");
    r.eq(c.fossils.saves, 1, "…and the sidecar rides the SAME write — exactly once");
    r.ok(Array.isArray(c.fossils.last) && c.fossils.last.length === 1 && c.fossils.last[0].alive === 3,
      "…carrying the recorded fossil payload");
    r.ok(c.store.last && c.store.last.campaign && !("runFossils" in c.store.last.campaign),
      "…while the campaign blob itself carries NO fossils");
    r.ok(!camp.hasUnsavedFossils(), "…the dirty flag clears with the write");

    // A second persist with NO new fossil: the blob writes, the sidecar doesn't.
    c.api.persistCampaign("store");
    c.fire(); c.fire();
    r.eq(c.store.saves, 2, "a clean persist still writes the campaign blob");
    r.eq(c.fossils.saves, 1, "…but never rewrites a clean sidecar (delta persistence)");

    // The deal-end case: a fossil recorded with NO pending campaign save —
    // the transition flush lands ONLY the sidecar.
    camp.recordRunFossil(1, 2, { ...FOSSIL, alive: 5 });
    c.api.flushCampaignSave();
    r.eq(c.fossils.saves, 2, "a transition flush lands the dirty sidecar with no pending save");
    r.eq(c.store.saves, 2, "…and no phantom campaign write (the pending guard is intact)");
    r.eq(c.fossils.last.length, 2, "…the sidecar holds both fossils");

    // clearSave: sidecar cleared, dirty dropped, nothing resurrects.
    camp.recordRunFossil(1, 3, FOSSIL);
    c.api.clearSave();
    r.eq(c.store.clears, 1, "clearSave clears the campaign store");
    r.eq(c.fossils.clears, 1, "…and the fossil sidecar with it");
    r.ok(!camp.hasUnsavedFossils(), "…dropping the dirty flag");
    c.api.flushCampaignSave();
    r.eq(c.fossils.saves, 2, "…so a later flush can't resurrect a wiped campaign's fossils");
  }

  // ── Behavioral: the campaign-side sidecar API ------------------------------
  {
    const c = CampaignState.create();
    r.ok(!c.hasUnsavedFossils(), "a fresh campaign has no unsaved fossils");
    c.recordRunFossil(1, 1, FOSSIL);
    r.ok(c.hasUnsavedFossils(), "recordRunFossil marks the sidecar dirty");
    const payload = JSON.parse(JSON.stringify(c.serializeFossils()));
    payload[0].nodes.push({ x: 9, y: 9 });
    r.eq(c.getRunFossil(1, 1).nodes.length, 2, "serializeFossils returns an independent copy");
    c.markFossilsSaved();
    r.ok(!c.hasUnsavedFossils(), "markFossilsSaved clears the flag");

    // restoreFossils: valid payload adopts (clean); garbage → []; never throws.
    const d = CampaignState.create();
    d.restoreFossils(JSON.parse(JSON.stringify(c.serializeFossils())));
    r.eq(d.getRunFossils().length, 1, "restoreFossils adopts a sidecar payload");
    r.eq(d.getRunFossil(1, 1).alive, 3, "…with its data intact");
    r.ok(!d.hasUnsavedFossils(), "…and is clean (the sidecar already holds it)");
    let threw = false;
    try { d.restoreFossils(null); d.restoreFossils("junk"); d.restoreFossils([{ stage: "x" }, null]); }
    catch (e) { threw = true; }
    r.ok(!threw && d.getRunFossils().length === 0, "malformed sidecar reads degrade to [] without throwing");

    // Old save (inline runFossils): restore ADOPTS and leaves dirty for the
    // one-time migration write. New save (no field): [] and clean.
    const e = CampaignState.create();
    const wire = JSON.parse(JSON.stringify(c.serialize()));
    r.ok(!("runFossils" in wire), "a new-format snapshot has no inline fossils");
    wire.runFossils = JSON.parse(JSON.stringify(c.serializeFossils()));   // the pre-sidecar field
    r.ok(e.restore(wire), "restore accepts a pre-sidecar save");
    r.eq(e.getRunFossils().length, 1, "…adopting the inline fossils");
    r.ok(e.hasUnsavedFossils(), "…dirty, so boot populates the sidecar (one-time migration)");
    const f = CampaignState.create();
    r.ok(f.restore(JSON.parse(JSON.stringify(c.serialize()))), "restore accepts a new-format save");
    r.eq(f.getRunFossils().length, 0, "…with no inline fossils → []");
    r.ok(!f.hasUnsavedFossils(), "…clean (the sidecar read owns fossils)");

    // reset() wipes fossils AND the flag.
    c.recordRunFossil(2, 1, FOSSIL);
    c.reset();
    r.eq(c.getRunFossils().length, 0, "reset() clears all fossils");
    r.ok(!c.hasUnsavedFossils(), "…and the dirty flag");
  }

  // ── The blob-size pin (the STKPERF1 win, at a 50-card fixture) -------------
  {
    const s0 = JSON.parse(JSON.stringify(CampaignState.create().serialize()));
    // Top up to exactly 50 owned cards, whatever the deck's START size is (it
    // moves when difficulty.js retunes startJokers) — the pin is about blob
    // SIZE at 50 cards, not about which ids those are.
    for (let id = 0; s0.ownedIds.length < 50; id++) s0.ownedIds.push(id);
    const camp = CampaignState.create();
    r.ok(camp.restore(s0) && camp.deckSize() === 50, "built the 50-card fixture");
    for (let st = 1; st <= 6; st++)
      for (let rn = 1; rn <= 3; rn++) {
        const nodes = [], edges = [];
        for (let i = 0; i < 55; i++) nodes.push({ x: (i * 37) % 75 + 0.5, y: (i * 53) % 84 + 0.5 });
        for (let i = 0; i < 54; i++) { edges.push([i, i + 1]); if (i + 7 < 55) edges.push([i, i + 7]); }
        camp.recordRunFossil(st, rn, { alive: 9, total: 13, nodes, edges });
      }
    const blob = JSON.stringify({ schema: 1, phase: "store", deckId: "pink", campaign: camp.serialize() });
    const sidecar = JSON.stringify(camp.serializeFossils());
    r.ok(blob.indexOf('"runFossils"') === -1, "the 50-card blob's JSON carries no fossil payload");
    r.ok(blob.length < sidecar.length,
      "…the whole blob is now SMALLER than the fossil sidecar it used to embed ("
      + (blob.length / 1024).toFixed(1) + " KB vs " + (sidecar.length / 1024).toFixed(1) + " KB)");
  }

  // ── The placement-walk cache pin (the two-card pack swap's SECOND card) ----
  {
    const openSwap = fnBody(src, "openCardSwap");
    const advance = fnBody(src, "advancePackKeepWalk");
    const skip = fnBody(src, "skipCurrentPackKeep");
    const contPlace = fnBody(src, "continuePendingPlacement");
    const render = fnBody(src, "renderStickerApplyCards");
    const walk = [openSwap, advance, skip, contPlace];
    r.ok(walk.every((b) => b.length > 0), "the pack-swap walk functions extract cleanly");
    r.ok(advance.includes("openCardSwap(0)"),
      "the walk's 2nd card opens through the SAME picker (advancePackKeepWalk → openCardSwap)");
    r.ok(walk.every((b) => !b.includes("applyCardNodes.clear()") && !b.includes("applyCardNodes = new Map")),
      "…NOTHING on the walk clears the parsed-node cache (the 2nd card rides it warm)");
    r.ok(render.includes("applyCardNodes.get(c.id)") && render.includes("rec.sig !== sig"),
      "…the sig cache gates every parse (a warm re-open re-parses only sig-changed cards)");
    r.ok(walk.concat([render]).every((b) => !b.includes("addEventListener")),
      "…the walk attaches NO listeners (input is the one boot-time delegation)");
    r.eq(countOf(src, "attachCardHoldHelp(el.saCards"), 1,
      "…the picker grid's hold/tap listener is attached exactly ONCE (boot)");
    const LAYOUT = ["getBoundingClientRect", "offsetHeight", "offsetWidth", "getComputedStyle"];
    r.ok(walk.concat([render]).every((b) => LAYOUT.every((m) => !b.includes(m))),
      "…and the walk reads NO layout (the one conditional scroll lives in the confirm's rAF — STKRB1)");
  }

  // ── Boot end-to-end: old save's inline fossils migrate to the sidecar ------
  {
    const mem = (init = {}) => {
      const data = { ...init };
      return {
        getItem: (k) => (k in data ? data[k] : null),
        setItem: (k, v) => { data[k] = String(v); },
        removeItem: (k) => { delete data[k]; },
      };
    };
    const F = { stage: 1, run: 1, alive: 3, total: 9, nodes: [{ x: 1, y: 2 }], edges: [[0, 1]] };
    const g0 = loadGame({ localStorage: mem() });
    // A PRE-sidecar save: the campaign snapshot + the inline runFossils field.
    const oldWire = JSON.parse(JSON.stringify(g0.CampaignState.create().serialize()));
    oldWire.runFossils = [F];
    const oldBlob = { schema: 1, phase: "map", deckId: "pink", campaign: oldWire };
    const stA = mem({ "ninelives.save.v1": JSON.stringify(oldBlob) });
    loadGame({ localStorage: stA });   // boot restores → adopts → populates the sidecar
    const written = JSON.parse(stA.getItem("ninelives.fossils.v1") || "null");
    r.ok(Array.isArray(written) && written.length === 1 && written[0].alive === 3,
      "boot over an inline-fossil (old) save populates ninelives.fossils.v1");

    // A NEW-format save + an existing sidecar: the sidecar survives verbatim.
    const newBlob = { schema: 1, phase: "map", deckId: "pink", campaign: g0.CampaignState.create().serialize() };
    const stB = mem({ "ninelives.save.v1": JSON.stringify(newBlob), "ninelives.fossils.v1": JSON.stringify([F]) });
    loadGame({ localStorage: stB });
    r.eq(stB.getItem("ninelives.fossils.v1"), JSON.stringify([F]),
      "boot over a new-format save leaves the sidecar untouched");

    // Save with fossils nowhere: boots clean, fabricates nothing.
    const stC = mem({ "ninelives.save.v1": JSON.stringify(newBlob) });
    let threw = false;
    try { loadGame({ localStorage: stC }); } catch (e) { threw = true; }
    r.ok(!threw && stC.getItem("ninelives.fossils.v1") === null,
      "boot with fossils nowhere: no crash, no fabricated sidecar");
  }

  return r.summary();
}
