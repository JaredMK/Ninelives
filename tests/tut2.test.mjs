// TUT2 — guided first-run tutorial rework. The bubble/gate choreography is
// UI-side, so this suite covers the ENGINE pieces (the guided-map predicate,
// the tutorial-only seed selection, non-tutorial determinism, the display-only
// mystery mask) plus structural source checks pinning the wiring the tour
// relies on (versioned pref, stamp-on-complete-only, registry-driven ids and
// prices, the render/store hooks). Registry-driven throughout: item prices and
// tunables are read live from items.js / GEN_CONFIG, never pinned.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadGame, makeRunner } from "./_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

/** The single game <script> block (the one defining the engine modules). */
function gameScript() {
  const html = readFileSync(join(HERE, "..", "index.html"), "utf8");
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
/** The Tutorial module's source (between its const and the next module). */
function tutorialSrc(src) {
  const a = src.indexOf("const Tutorial = (() => {");
  if (a === -1) return "";
  const b = src.indexOf("})();", a);
  return b === -1 ? "" : src.slice(a, b);
}

/** A tiny synthetic map in the generateRun result shape (nodes/byId/row0). */
function synthMap(nodes) {
  const byId = {};
  nodes.forEach(n => { n.next = n.next || []; byId[n.id] = n; });
  return { nodes, byId, row0: nodes.filter(n => n.row === 0).map(n => n.id), phases: [], totalRows: 8 };
}

export function run() {
  const r = makeRunner("tut2.test.mjs");
  const g = loadGame();
  const { RunMap, CampaignState, StickerTypes, PillarTypes } = g;
  const src = gameScript();
  const tut = tutorialSrc(src);
  r.ok(tut.length > 200, "Tutorial module source located");

  // --- forced-purchase items exist in items.js (fail-loud requirement) -----
  const gain = StickerTypes.get("gainCoin");
  const guard = PillarTypes.get("columnGuardian");
  r.ok(!!gain, "items.js defines the gainCoin sticker (the forced sticker buy)");
  r.ok(!!guard, "items.js defines the columnGuardian pillar (the forced pillar buy)");
  r.ok(gain && Array.isArray(gain.suits) && gain.suits.length === 1 && gain.suits[0] === "♥",
    "gainCoin is ♥-only (the 13-heart start guarantees an eligible target)");
  r.ok(gain && isFinite(gain.price) && gain.price > 0, "gainCoin carries a live price (read from the registry)");
  r.ok(guard && isFinite(guard.price) && guard.price > 0, "columnGuardian carries a live price");
  r.ok(tut.includes('const GAIN_STICKER = "gainCoin"') && tut.includes('const GUARD_PILLAR = "columnGuardian"'),
    "the tour resolves both ids through single consts (no scattered literals)");
  r.ok(tut.includes("StickerTypes.get(GAIN_STICKER)") && tut.includes("PillarTypes.get(GUARD_PILLAR)"),
    "…and validates them against the registries at runtime (tutorialItemsOk)");

  // --- guided-map predicate: exported + synthetic accept/reject ------------
  r.ok(typeof RunMap.tutorialPathOk === "function" && typeof RunMap.tutorialChainFrom === "function",
    "RunMap exports tutorialPathOk / tutorialChainFrom");
  {
    // ACCEPT: row-0 deal → store (+1 row) → pickup (+1 row) → deal above.
    const okMap = synthMap([
      { id: 1, type: "deal", row: 0, next: [2] },
      { id: 2, type: "store", row: 1, next: [3] },
      { id: 3, type: "pickup", row: 2, next: [4] },
      { id: 4, type: "deal", row: 3, next: [] },
    ]);
    r.ok(RunMap.tutorialPathOk(okMap), "predicate ACCEPTS deal→store(+1)→pickup(+1)→deal");
    r.ok(RunMap.tutorialChainFrom(okMap, 1), "…and tutorialChainFrom agrees on the opening node");

    // ACCEPT at the window edges: store 2 rows up, pickup 2 rows after it.
    const edgeMap = synthMap([
      { id: 1, type: "deal", row: 0, next: [2] },
      { id: 2, type: "pack", row: 1, next: [3] },
      { id: 3, type: "store", row: 2, next: [4] },
      { id: 4, type: "deal", row: 3, next: [5] },
      { id: 5, type: "pickup", row: 4, next: [6] },
      { id: 6, type: "boss", row: 5, next: [] },
    ]);
    r.ok(RunMap.tutorialPathOk(edgeMap),
      "predicate ACCEPTS the 2-row windows (store at +2, pickup at +2, boss as the battle)");

    // REJECT: the store sits 3 rows up (outside the window).
    const farStore = synthMap([
      { id: 1, type: "deal", row: 0, next: [2] },
      { id: 2, type: "pack", row: 1, next: [3] },
      { id: 3, type: "deal", row: 2, next: [4] },
      { id: 4, type: "store", row: 3, next: [5] },
      { id: 5, type: "pickup", row: 4, next: [6] },
      { id: 6, type: "deal", row: 5, next: [] },
    ]);
    r.ok(!RunMap.tutorialPathOk(farStore), "predicate REJECTS a store 3 rows above the opening deal");

    // REJECT: no +1 pickup within 2 rows after the store (a pack is NOT a pickup).
    const noPickup = synthMap([
      { id: 1, type: "deal", row: 0, next: [2] },
      { id: 2, type: "store", row: 1, next: [3] },
      { id: 3, type: "pack", row: 2, next: [4] },
      { id: 4, type: "pack", row: 3, next: [5] },
      { id: 5, type: "pickup", row: 4, next: [6] },
      { id: 6, type: "deal", row: 5, next: [] },
    ]);
    r.ok(!RunMap.tutorialPathOk(noPickup), "predicate REJECTS when no pickup lands within 2 rows of the store");

    // REJECT: nothing to battle after the pickup.
    const noBattle = synthMap([
      { id: 1, type: "deal", row: 0, next: [2] },
      { id: 2, type: "store", row: 1, next: [3] },
      { id: 3, type: "pickup", row: 2, next: [] },
    ]);
    r.ok(!RunMap.tutorialPathOk(noBattle), "predicate REJECTS when no deal is reachable after the pickup");

    // REJECT: a non-deal opening never anchors the chain.
    const storeOpen = synthMap([
      { id: 1, type: "store", row: 0, next: [2] },
      { id: 2, type: "pickup", row: 1, next: [3] },
      { id: 3, type: "deal", row: 2, next: [] },
    ]);
    r.ok(!RunMap.tutorialChainFrom(storeOpen, 1), "chainFrom rejects a non-deal opening node");
    r.ok(!RunMap.tutorialPathOk(null) && !RunMap.tutorialPathOk({}), "predicate is null-safe");
  }

  // --- retry budget is a generator tunable ---------------------------------
  r.ok(RunMap.GEN_CONFIG.tutorialMapRetries >= 1,
    "GEN_CONFIG.tutorialMapRetries exists (bounded retry budget; currently "
    + RunMap.GEN_CONFIG.tutorialMapRetries + ")");

  // --- tutorial-only seed selection + non-tutorial determinism -------------
  {
    const c = CampaignState.create();
    r.ok(typeof c.setTutorialRun === "function" && c.isTutorialRun() === false,
      "campaign exposes setTutorialRun/isTutorialRun, defaulting OFF");
    const mapSig = (m) => m.nodes.map(n => [n.id, n.type, n.row, n.piles || 0, n.mystery ? 1 : 0,
      (n.next || []).join(".")].join(":")).join("|");

    // NON-TUTORIAL: the campaign's map IS generateRun(runSeed) — byte-identical
    // regeneration from the persisted seed (the pre-change contract).
    c.reset();
    const snap = c.serialize();
    const regen = RunMap.generateRun(snap.runSeed, snap.stageEntryDecks, { postBossJokerStages: [0, 1] });
    r.eq(mapSig(c.getMap()), mapSig(regen),
      "non-tutorial map == generateRun(saved seed) (same seed → same map, unchanged)");

    // TUTORIAL: the same contract holds for the PICKED seed — selection only
    // chooses WHICH seed is used, never how a seed generates.
    const t = CampaignState.create();
    t.setTutorialRun(true);
    t.reset();
    const tsnap = t.serialize();
    const tregen = RunMap.generateRun(tsnap.runSeed, tsnap.stageEntryDecks, { postBossJokerStages: [0, 1] });
    r.eq(mapSig(t.getMap()), mapSig(tregen),
      "tutorial map == generateRun(picked seed) (selection picks a seed, never mutates a map)");
    r.ok(!("tutorialRun" in tsnap), "the tutorial flag is never persisted in the save");

    // Selection actually works: a small sweep of tutorial runs should satisfy
    // the predicate essentially always (base rate ~2/3, 8 retries → miss odds
    // ≪ 1%); allow one miss so the check can't flake on a legal budget-out.
    let hits = 0;
    const SWEEP = 6;
    for (let i = 0; i < SWEEP; i++) {
      const ti = CampaignState.create();
      ti.setTutorialRun(true);
      ti.reset();
      if (RunMap.tutorialPathOk(ti.getMap())) hits++;
    }
    r.ok(hits >= SWEEP - 1,
      "tutorial runs land on guided-friendly maps (" + hits + "/" + SWEEP + " satisfied the predicate)");
  }

  // --- mystery mask is DISPLAY-LAYER only ----------------------------------
  {
    // Engine truth is untouched: nodeHidden ignores the tutorial flag entirely.
    let exercised = false;
    for (let s = 0; s < 20 && !exercised; s++) {
      const c = CampaignState.create();
      c.setTutorialRun(true);
      c.reset();
      const myst = c.getMap().nodes.find(n => n.mystery && n.type !== "pass");
      if (!myst) continue;
      r.ok(c.nodeHidden(myst.id), "campaign.nodeHidden stays TRUE during a tutorial run (state layer untouched)");
      exercised = true;
    }
    r.ok(exercised, "found a mystery node on a tutorial map to exercise");
    const hiddenFn = src.slice(src.indexOf("nodeHidden(id) {"), src.indexOf("revealNode(id)"));
    r.ok(hiddenFn.length > 0 && !hiddenFn.includes("Tutorial"),
      "campaign.nodeHidden has no Tutorial dependency (mask lives in the renderer)");
    r.ok(src.includes("!Tutorial.mysteryMasked() && campaign.nodeHidden"),
      "the map render consults the mask at its nodeHidden read (display suppression)");
    r.ok(src.includes("wasHidden && !Tutorial.mysteryMasked()"),
      "the arrival flip moment is skipped while masked (the reveal is still recorded)");
    r.ok(fnBody(src, "generateRun").includes("GEN_CONFIG.mysteryChance"),
      "the generation-time mystery roll is untouched");
  }

  // --- pref-key versioning + stamp-on-complete-only -------------------------
  {
    r.ok(tut.includes('const PREF = "tutorial2"'), "completion moved to the versioned tutorial2 pref key");
    r.ok(!/getPref\("tutorial"\)/.test(src), "the OLD 'tutorial' pref is never read anywhere");
    const stamps = (tut.match(/SaveStore\.setPref\(PREF, "1"\)/g) || []).length;
    r.eq(stamps, 1, "exactly one stamp site (end() — complete, skip, and graceful bow-out all funnel there)");
    const deckSel = tut.slice(tut.indexOf("onDeckSelect()"), tut.indexOf("onMapRender()"));
    r.ok(deckSel.length > 0 && !deckSel.includes("setPref"),
      "arming the tour (deck select) stamps NOTHING — a mid-tour loss restarts it");
    const endBody = tut.slice(tut.indexOf("function end()"), tut.indexOf("MAP GUIDANCE"));
    r.ok(endBody.includes('SaveStore.setPref(PREF, "1")'), "…the stamp lives in end()");
    r.ok(/classList\.remove\("tut-gate-store"/.test(endBody) && endBody.includes("renderProgressionMap()"),
      "end() drops the store gate class and re-renders a visible map (glows + '?' faces restored)");
  }

  // --- gating + grant wiring (structural) -----------------------------------
  {
    r.ok(fnBody(src, "renderProgressionMap").includes("Tutorial.onMapRender()"),
      "every map render re-applies the map gate (Tutorial.onMapRender)");
    r.ok(tut.includes('querySelectorAll(".pm-node[data-action=\'node\']")')
      && tut.includes('removeAttribute("data-action")'),
      "the map gate strips data-action from every non-target legal node");
    r.ok(fnBody(src, "renderStore").includes("Tutorial.onStoreRender()"),
      "every store render re-stamps the gate's .tut-allow");
    r.ok(fnBody(src, "showStore").includes("Tutorial.seedStoreOffer()"),
      "the guided shop's fresh offer is seeded before it paints");
    const reroll = fnBody(src, "rerollUI");
    r.ok(reroll.indexOf("Tutorial.onStoreRerolled()") !== -1
      && reroll.indexOf("Tutorial.onStoreRerolled()") < reroll.indexOf("renderStore()"),
      "the taught Refresh seeds the Guardian BEFORE the fresh shelf paints");
    r.ok(fnBody(src, "confirmApplySticker").includes("Tutorial.onStickerApplied(pendingApplyStickerId)"),
      "a confirmed sticker apply notifies the tour (forced buy → Refresh step)");
    r.ok(fnBody(src, "confirmBuyAndPlace").includes("Tutorial.onPillarPlaced(id)")
      && fnBody(src, "confirmItemPlace").includes("Tutorial.onPillarPlaced(id)"),
      "both pillar placement paths notify the tour");
    // Grants: exactly the shortfall, via campaign.addCoins, against LIVE
    // registry prices / the live reroll cost — no local price literals.
    r.ok(tut.includes("campaign.addCoins(short)"),
      "teaching grants go through campaign.addCoins (the proper non-debug path)");
    r.ok(tut.includes("grantShortfall(campaign.priceOf(GAIN_STICKER))")
      && tut.includes("grantShortfall(campaign.storeRerollCost())")
      && tut.includes("grantShortfall(campaign.priceOfPillar(GUARD_PILLAR))"),
      "every grant reads the LIVE price (items.js registry / current reroll cost)");
    r.ok(/const short = price - campaign\.getCoins\(\)/.test(tut),
      "the grant is exactly the shortfall at that moment");
    r.ok(tut.includes("if (!isFinite(short) || short <= 0) return false;"),
      "the grant guards against a non-finite price (registry-edge insurance)");
    // Grants are never silent: coin tick + counter pulse + an on-the-house
    // copy clause appended by every granted step.
    const grantFn = tut.slice(tut.indexOf("function grantShortfall"), tut.indexOf("function grantNote"));
    r.ok(grantFn.includes("Sound.coin()") && grantFn.includes("tut-grant"),
      "a teaching grant plays Sound.coin and pulses both coin counters");
    r.eq((tut.match(/\+ grantNote\(granted\)/g) || []).length, 3,
      "all three granted steps (sticker / reroll / pillar) append the on-the-house clause");
    // The forced sticker bubble reads its label + payout LIVE from items.js.
    r.ok(tut.includes("escHtml(StickerTypes.get(GAIN_STICKER).label)")
      && tut.includes("escHtml(StickerTypes.get(GAIN_STICKER).description)"),
      "the sticker bubble's name/payout come from the registry, escaped");
    // Keyboard hardening: pointer-events CSS can't stop Enter-key clicks, so a
    // capture-phase guard swallows any store activation outside the gate.
    const guard = tut.slice(tut.indexOf("function ensureGateGuard"), tut.indexOf("function setStoreGate"));
    r.ok(guard.includes('document.addEventListener("click"') && guard.includes("stopImmediatePropagation"),
      "a capture-phase click guard backs the store gate (keyboard activation covered)");
    // The coins-location bubble anchors the SUMMARY's own balance row — the
    // overlay covers the HUD bar, so #hudDopamine would ring an occluded node.
    const cleared = tut.slice(tut.indexOf("onDealCleared()"), tut.indexOf("seedStoreOffer()"));
    r.ok(cleared.includes('$(".dc-balance")') && !cleared.includes("#hudDopamine"),
      "the where-coins-live bubble rings the visible .dc-balance row, not the covered HUD");
    // The probe hook arms only with the debug panel (no always-on mutable handle).
    r.ok(src.includes("window.__campaign = () => (debugArmed ? campaign : null)"),
      "window.__campaign is gated behind the session's debug arming");
    // The completion trigger: the guided battle deal's START ends the tour.
    const dealStart = tut.slice(tut.indexOf("onDealStart()"), tut.indexOf("onGuessResolved()"));
    r.ok(/objective\(\) === "battle"\) \{ end\(\); return; \}/.test(dealStart),
      "the battle deal's start completes the tour (stamp + all gating removed)");
  }

  // --- CSS gate rules exist --------------------------------------------------
  {
    const html = readFileSync(join(HERE, "..", "index.html"), "utf8");
    r.ok(html.includes(".pm-node.tut-dim"), "dimmed-inert map node style exists");
    r.ok(html.includes("body.tut-gate-store #storeOverlay button:not(.tut-allow):not(.store-tile)"),
      "store gate CSS makes non-allowed controls inert (tiles excepted — hold-for-help stays alive; the click guard covers them)");
    r.ok(html.includes(".tut-grant { display: inline-block; animation: tutGrant"),
      "the grant pulse animation exists");
  }

  // --- tutorial.txt stays the copy source of truth ---------------------------
  {
    const txt = readFileSync(join(HERE, "..", "tutorial.txt"), "utf8");
    for (const anchor of ["Skip tips", "tutorial2", "Bonus Coin", "Guardian", "GO TO MAP", "Refresh"])
      r.ok(txt.includes(anchor), "tutorial.txt carries the '" + anchor + "' anchor");
    // Bubble copy ↔ file sync spot-checks on stable phrases (not full strings).
    for (const phrase of ["glowing node", "surviving piles × smallest pile", "rides the top bar",
      "ride it for the whole run", "re-rolls the whole shelf", "every pile in its column survives",
      "on the house"])
      r.ok(txt.includes(phrase) && tut.includes(phrase.replace("×", "×")),
        "copy phrase in both tutorial.txt and the bubbles: '" + phrase + "'");
  }

  return r.summary();
}
