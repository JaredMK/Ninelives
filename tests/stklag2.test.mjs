// STKLAG2 — the campaign save was written SYNCHRONOUSLY on every store click.
// On the Capacitor build NativeApp's setItem write-through mirrors every
// ninelives.* write across the JS↔native Preferences bridge carrying the whole
// blob; renderStore() persists on every click (and one click fans out to
// several renderStore calls), so rapid late-game clicks queued whole-blob
// bridge writes — 5-10s stalls that GREW with deck size. (Pure-JS serialize is
// ~2ms; the cost is the native mirror, once per write.)
//
// The fix: persistCampaign() no longer writes on the tap — it SCHEDULES a single
// trailing (debounced) write, so a click's many persists AND several rapid
// clicks collapse to ONE SaveStore.save (one native mirror). Durability is
// preserved by flushCampaignSave() — a synchronous write NOW — called at every
// screen transition (map/store entry, run start/end) and on pagehide/
// visibilitychange-hidden, so a kill/refresh can't lose a completed purchase.
// clearSave() cancels any pending write so a queued save can't resurrect a wiped
// campaign. Only the campaign save is coalesced; other ninelives.* keys are
// untouched (the Storage write-through monkey-patch is not changed).
//
// This suite (a) EXTRACTS the coalescer functions from source and drives them
// with fake timers + a counting SaveStore to prove a burst of N persists writes
// 0 saves and lands exactly ONE on the trailing timer; (b) proves
// flushCampaignSave writes synchronously and a no-pending flush is inert;
// (c) proves clearSave cancels a queued write; (d) proves a coalesced blob
// serialize→restore is byte-identical on a large state; plus structural checks
// that the pagehide/visibilitychange handler and the transition flushes are
// wired, and that STKLAG1's single-persist/suppress invariants still hold.
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
/** Brace-matched body of the function whose declaration starts at `sig`
    (a distinctive `function name(` or `function name(firstArg` prefix — some
    names appear twice, e.g. two startRun/init, so we anchor on the signature). */
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
/** Body of a top-level `function name(...) { ... }` (brace-matched, first hit). */
function fnBody(src, name) { return bodyAt(src, "function " + name + "("); }
function countOf(hay, needle) {
  let n = 0, i = 0;
  while ((i = hay.indexOf(needle, i)) !== -1) { n++; i += needle.length; }
  return n;
}

export function run() {
  const r = makeRunner("stklag2.test.mjs");
  const html = fullHtml();
  const src = gameScript(html);
  const g = loadGame();
  const { CampaignState, StickerTypes } = g;
  r.ok(!!(CampaignState && StickerTypes), "game script evaluates with the STKLAG2 wiring in place");

  const persist = fnBody(src, "persistCampaign");
  const flush = fnBody(src, "flushCampaignSave");
  const writeNow = fnBody(src, "writeCampaignSaveNow");
  const blobFn = fnBody(src, "campaignSaveBlob");
  const clear = fnBody(src, "clearSave");
  // Two `init` (DeckInspector's init(opts) and UIRenderer's); anchor the latter.
  const init = bodyAt(src, "function init() {");

  // --- Structural: persistCampaign schedules, does NOT write on the tap -------
  {
    r.ok(persist.length > 0 && flush.length > 0 && writeNow.length > 0,
      "persistCampaign / flushCampaignSave / writeCampaignSaveNow all exist");
    r.ok(persist.includes("setTimeout(writeCampaignSaveNow") && persist.includes("pendingSavePhase = phase"),
      "persistCampaign SCHEDULES a trailing write (setTimeout) keeping the latest phase");
    r.ok(!persist.includes("SaveStore.save"),
      "…and no longer calls SaveStore.save on the tap (write moved off the per-click path)");
    r.ok(persist.includes("clearTimeout(saveCoalesceTimer)"),
      "…re-arming the debounce collapses a burst into one write");
    // The one synchronous write lives in writeCampaignSaveNow, guarded so a
    // no-pending flush never writes (can't resurrect a cleared campaign).
    r.ok(writeNow.includes("SaveStore.save(campaignSaveBlob(phase))"),
      "writeCampaignSaveNow performs the single real SaveStore.save");
    r.ok(/pendingSavePhase === null[\s\S]*return/.test(writeNow),
      "…and is a no-op when nothing is pending");
    r.ok(flush.includes("writeCampaignSaveNow()"),
      "flushCampaignSave writes synchronously via writeCampaignSaveNow");
  }

  // --- Structural: clearSave cancels any pending coalesced write -------------
  {
    r.ok(clear.includes("clearTimeout(saveCoalesceTimer)") && clear.includes("pendingSavePhase = null")
      && clear.includes("SaveStore.clear()"),
      "clearSave cancels the pending write AND clears the store (no resurrection)");
  }

  // --- Structural: campaignSaveBlob keeps the run-phase resume fields ---------
  {
    r.ok(blobFn.includes('phase === "run"') && blobFn.includes("blob.runSeed")
      && blobFn.includes("blob.dealSubset") && blobFn.includes("return blob"),
      "campaignSaveBlob still checkpoints the run seed + subset (resume fields intact)");
  }

  // --- Structural: pagehide + visibilitychange-hidden flush, registered once --
  {
    r.ok(/addEventListener\("pagehide",[\s\S]*?flushCampaignSave\(\)/.test(init),
      "init registers a pagehide handler that flushes the campaign save");
    r.ok(/addEventListener\("visibilitychange"[\s\S]*?document\.visibilityState === "hidden"[\s\S]*?flushCampaignSave\(\)/.test(init),
      "…and a visibilitychange handler that flushes when the document goes hidden");
    r.eq(countOf(init, "flushCampaignSave()"), 2,
      "…both handlers flush, registered exactly once in init");
  }

  // --- Structural: durability flush at the screen transitions ----------------
  {
    // Two `startRun` (the setup-phase one and the deal one); anchor the deal one.
    const startRun = bodyAt(src, "function startRun(seedOverride");
    const onRunEnd = fnBody(src, "onRunEnd");
    const showMap = fnBody(src, "showProgressionMap");
    const showStore = fnBody(src, "showStore");
    r.ok(/persistCampaign\("run"\);\s*flushCampaignSave\(\);/.test(startRun),
      "startRun flushes right after the run-start checkpoint (run start durable)");
    r.ok(onRunEnd.includes("flushCampaignSave()"), "onRunEnd flushes (run end durable)");
    r.ok(showMap.includes("flushCampaignSave()"), "showProgressionMap flushes on entry (store→map GO TO MAP lands)");
    r.ok(showStore.includes("flushCampaignSave()"), "showStore flushes on entry (previous screen's save lands)");
  }

  // --- Structural: STKLAG1 invariants preserved ------------------------------
  {
    const store = fnBody(src, "renderStore");
    r.ok(/if \(suppressStorePersistOnce\) suppressStorePersistOnce = false;\s*else persistCampaign\("store"\);/.test(store),
      "renderStore's suppress-else-persist checkpoint is unchanged (STKLAG1)");
    r.eq(countOf(src, "let suppressStorePersistOnce = false;"), 1,
      "suppressStorePersistOnce is still the single module-scoped one-shot");
    const confirm = fnBody(src, "confirmApplySticker");
    const at = confirm.indexOf("else if (pendingApplyStickerId)");
    r.eq(countOf(confirm.slice(at), "persistCampaign("), 1,
      "the sticker apply path still calls persistCampaign exactly once (STKLAG1)");
  }

  // --- Behavioral: extract the coalescer + drive it with fake timers ---------
  // Build the real coalescer in isolation (its module-scoped lets + the five
  // functions) over a counting SaveStore + fake timers + a real CampaignState.
  function buildCoalescer(campaign) {
    const parts = [
      "let pendingSavePhase = null;",
      "let saveCoalesceTimer = null;",
      "const SAVE_COALESCE_MS = 300;",
      "function campaignSaveBlob(phase) " + blobFn,
      "function writeCampaignSaveNow() " + writeNow,
      "function persistCampaign(phase) " + persist,
      "function flushCampaignSave() " + flush,
      "function clearSave() " + clear,
      "return { persistCampaign, flushCampaignSave, clearSave,"
      + " _pending: () => pendingSavePhase, _armed: () => saveCoalesceTimer !== null };",
    ].join("\n");
    let timers = [], nextId = 1;
    const setT = (fn) => { const id = nextId++; timers.push({ id, fn }); return id; };
    const clrT = (id) => { timers = timers.filter((t) => t.id !== id); };
    const fire = () => { const t = timers; timers = []; t.forEach((x) => x.fn()); };
    const store = {
      saves: 0, clears: 0, last: null,
      save(b) { this.saves++; this.last = b; },
      clear() { this.clears++; },
    };
    const factory = new Function(
      "SaveStore", "setTimeout", "clearTimeout",
      "campaign", "selectedDeckId", "engine", "redealCost", "appliedThisPhase", "currentDealSubset", "zenMode",
      parts);
    const api = factory(store, setT, clrT, campaign, "pink", null, 0, false, null, null);
    return { api, store, fire, pending: () => timers.length };
  }

  // (a) A burst of N persists writes 0 saves synchronously; the trailing timer
  //     lands exactly ONE — independent of how many persists (or renders) fired.
  {
    const camp = CampaignState.create(); camp.reset();
    const c = buildCoalescer(camp);
    for (let i = 0; i < 8; i++) c.api.persistCampaign("store");
    r.eq(c.store.saves, 0, "8 persistCampaign calls write 0 saves immediately (scheduled, not written)");
    r.ok(c.api._armed(), "…a single trailing timer is armed");
    r.eq(c.pending(), 1, "…exactly one timer pending for the whole burst (debounce collapsed it)");
    r.eq(c.api._pending(), "store", "…keeping the latest requested phase");
    c.fire();
    r.eq(c.store.saves, 1, "…firing the debounce lands EXACTLY ONE save for the burst");
    r.ok(!c.api._armed() && c.api._pending() === null, "…and clears the timer/pending after the write");
  }

  // (b) flushCampaignSave writes synchronously NOW; a no-pending flush is inert.
  {
    const camp = CampaignState.create(); camp.reset();
    const c = buildCoalescer(camp);
    c.api.persistCampaign("store");
    r.eq(c.store.saves, 0, "schedule alone does not write");
    c.api.flushCampaignSave();
    r.eq(c.store.saves, 1, "flushCampaignSave writes synchronously NOW");
    r.ok(!c.api._armed(), "…and disarms the pending timer (no later double write)");
    c.fire();
    r.eq(c.store.saves, 1, "…the now-dead timer writes nothing");
    c.api.flushCampaignSave();
    r.eq(c.store.saves, 1, "a flush with nothing pending is a no-op (never resurrects)");
  }

  // (c) clearSave cancels a queued write so it can't resurrect a wiped campaign.
  {
    const camp = CampaignState.create(); camp.reset();
    const c = buildCoalescer(camp);
    c.api.persistCampaign("store");
    c.api.clearSave();
    r.eq(c.store.clears, 1, "clearSave clears the store");
    r.ok(!c.api._armed() && c.api._pending() === null, "…and cancels the pending coalesced write");
    c.fire();
    r.eq(c.store.saves, 0, "…so a queued timer can't resurrect the cleared campaign");
  }

  // (d) A coalesced blob serialize→restore is byte-identical on a large state.
  {
    const camp = CampaignState.create(); camp.reset();
    camp.addCoins(500);
    // Apply several live-registry stickers to grow the state (a "large" deck).
    const deck = camp.getRunDeck();
    let applied = 0;
    for (const t of StickerTypes.all()) {
      for (const cd of deck) {
        if (camp.canApplyStickerById(cd.id, t.id)) { if (camp.applySticker(cd.id, t.id)) applied++; break; }
      }
      if (applied >= 3) break;
    }
    r.ok(applied >= 1, "built a non-trivial state (applied live stickers)");
    const c = buildCoalescer(camp);
    c.api.persistCampaign("store");
    c.api.flushCampaignSave();
    const blob = c.store.last;
    r.ok(blob && blob.schema === 1 && blob.phase === "store" && blob.deckId === "pink",
      "the coalesced blob carries schema/phase/deckId");
    const camp2 = CampaignState.create();
    r.ok(camp2.restore(JSON.parse(JSON.stringify(blob.campaign))), "the coalesced blob restores");
    r.eq(JSON.stringify(camp2.serialize()), JSON.stringify(camp.serialize()),
      "serialize→restore→serialize is byte-identical for the large state (save integrity)");
  }

  return r.summary();
}
