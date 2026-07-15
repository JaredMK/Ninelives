// TUT2/TUT3 — guided first-run tutorial. The bubble/gate choreography is
// UI-side, so this suite covers the ENGINE pieces (the guided-map predicates
// — windowed AND strict — the pinned-seed selection, non-tutorial
// determinism, the display-only mystery mask), the tutorial.js data file
// (structure, fail-loud validation, copy anchors, placeholders) plus
// structural source checks pinning the wiring the tour relies on (versioned
// pref, stamp-on-complete-only, registry-driven ids and prices, the
// render/store hooks). Registry-driven throughout: item prices, tunables and
// the pinned seed are read live from items.js / tutorial.js / GEN_CONFIG,
// never (re-)pinned here.
import { existsSync, readFileSync } from "node:fs";
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

/** Body of the TutorialData IIFE (const TutorialData = (() => { ... })();) —
    evaluated standalone against broken clones for the fail-loud checks. */
function tutorialDataSrc(src) {
  const a = src.indexOf("const TutorialData = (() => {");
  if (a === -1) return "";
  const b = src.indexOf("\n})();", a);
  return b === -1 ? "" : src.slice(a, b + 6);
}

export function run() {
  const r = makeRunner("tut2.test.mjs");
  const g = loadGame();
  const { RunMap, CampaignState, StickerTypes, PillarTypes, TutorialData } = g;
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

  // --- STRICT predicate (TUT3): zero-hop chain, pass corridors free --------
  r.ok(typeof RunMap.tutorialPathStrict === "function" && typeof RunMap.tutorialStrictFrom === "function",
    "RunMap exports tutorialPathStrict / tutorialStrictFrom");
  {
    // ACCEPT: deal → store → pickup → deal, each a DIRECT successor.
    const adj = synthMap([
      { id: 1, type: "deal", row: 0, next: [2] },
      { id: 2, type: "store", row: 1, next: [3] },
      { id: 3, type: "pickup", row: 2, next: [4] },
      { id: 4, type: "deal", row: 3, next: [] },
    ]);
    r.ok(RunMap.tutorialPathStrict(adj), "STRICT accepts deal→store→pickup→deal all adjacent");
    r.ok(RunMap.tutorialStrictFrom(adj, 1), "…and tutorialStrictFrom agrees on the opening node");

    // ACCEPT: pass corridors are FREE glides, not hops (the marker slides
    // through without a tap) — a pass between every pair still counts strict.
    const viaPass = synthMap([
      { id: 1, type: "deal", row: 0, next: [10] },
      { id: 10, type: "pass", row: 1, next: [2] },
      { id: 2, type: "store", row: 2, next: [11] },
      { id: 11, type: "pass", row: 3, next: [3] },
      { id: 3, type: "pickup", row: 4, next: [12] },
      { id: 12, type: "pass", row: 5, next: [4] },
      { id: 4, type: "boss", row: 6, next: [] },
    ]);
    r.ok(RunMap.tutorialPathStrict(viaPass), "STRICT accepts pass corridors between every leg (boss as the battle)");

    // REJECT: one intermediate TAP anywhere breaks strictness — a pack
    // between deal and store here satisfies the windowed predicate but must
    // fail the strict one (the pin's no-hop-note contract).
    const oneHop = synthMap([
      { id: 1, type: "deal", row: 0, next: [5] },
      { id: 5, type: "pack", row: 1, next: [2] },
      { id: 2, type: "store", row: 2, next: [3] },
      { id: 3, type: "pickup", row: 3, next: [4] },
      { id: 4, type: "deal", row: 4, next: [] },
    ]);
    r.ok(RunMap.tutorialPathOk(oneHop) && !RunMap.tutorialPathStrict(oneHop),
      "STRICT rejects an intermediate pack hop the windowed predicate accepts");

    // REJECT: pickup not directly after the store / battle not directly
    // after the pickup.
    const farPickup = synthMap([
      { id: 1, type: "deal", row: 0, next: [2] },
      { id: 2, type: "store", row: 1, next: [5] },
      { id: 5, type: "deal", row: 2, next: [3] },
      { id: 3, type: "pickup", row: 3, next: [4] },
      { id: 4, type: "deal", row: 4, next: [] },
    ]);
    r.ok(!RunMap.tutorialPathStrict(farPickup), "STRICT rejects a pickup one deal past the store");
    const farBattle = synthMap([
      { id: 1, type: "deal", row: 0, next: [2] },
      { id: 2, type: "store", row: 1, next: [3] },
      { id: 3, type: "pickup", row: 2, next: [5] },
      { id: 5, type: "pack", row: 3, next: [4] },
      { id: 4, type: "deal", row: 4, next: [] },
    ]);
    r.ok(!RunMap.tutorialPathStrict(farBattle), "STRICT rejects a battle one pack past the pickup");
    r.ok(!RunMap.tutorialPathStrict(null) && !RunMap.tutorialPathStrict({}), "strict predicate is null-safe");
  }

  // --- PINNED SEED (tutorial.js) still qualifies under the live generator ---
  {
    r.ok(typeof TutorialData.seed === "number" && isFinite(TutorialData.seed),
      "tutorial.js pins a numeric tutorial map seed (currently " + TutorialData.seed + ")");
    const e0 = RunMap.GEN_CONFIG.startDeckSize, prc = RunMap.GEN_CONFIG.predictedRouteCards;
    const entries = [e0, e0 + prc, e0 + 2 * prc];
    // Pink/Regular is the only first-run combo — the exact inputs the live
    // pickTutorialRun feeds the generator.
    const map = RunMap.generateRun(TutorialData.seed, entries, { postBossJokerStages: [0, 1] });
    r.ok(RunMap.tutorialPathStrict(map),
      "pinned seed " + TutorialData.seed + " opens with a STRICT guided chain under the live generator"
      + " + difficulty.js — a generator/difficulty change staled it: RE-PIN THE TUTORIAL SEED in tutorial.js");
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

    // CLOSED ENVIRONMENT: a fresh tutorial run adopts the PINNED seed (its
    // pin is valid — asserted above), so every player's first map is the
    // same one, satisfying the strict chain; repeat runs are identical.
    r.eq(tsnap.runSeed, TutorialData.seed,
      "a fresh tutorial run rides the pinned tutorial.js seed (runSeed == pin)");
    r.ok(RunMap.tutorialPathStrict(t.getMap()), "…and its live map opens with the strict chain");
    const t2 = CampaignState.create();
    t2.setTutorialRun(true);
    t2.reset();
    r.eq(mapSig(t2.getMap()), mapSig(t.getMap()),
      "two fresh tutorial runs share the identical pinned map");

    // DYNAMIC FALLBACK stays wired for a stale pin: pinned-first with a
    // named console.error, then bounded retries preferring strict → loose →
    // the last roll (structural — the pin can't be broken from here).
    const pick = src.slice(src.indexOf("function pickTutorialRun"), src.indexOf("function pregenerateRun"));
    r.ok(pick.includes("const pinned = TutorialData.seed") && pick.indexOf("TutorialData.seed") < pick.indexOf("tutorialMapRetries"),
      "pickTutorialRun tries the PINNED tutorial.js seed before any rolled one");
    r.ok(pick.includes("re-pin it") && pick.includes("console.error"),
      "a stale pin fails loud (console.error naming the seed) before falling back");
    r.ok(pick.includes("RunMap.tutorialPathStrict(map)") && pick.includes("RunMap.tutorialPathOk(map)")
      && pick.includes("return loose || last;"),
      "the retry loop prefers strict, then the windowed chain, then the last roll");
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
    // (bounded by tileSel — the next declaration after grantShortfall)
    const grantFn = tut.slice(tut.indexOf("function grantShortfall"), tut.indexOf("function tileSel"));
    r.ok(grantFn.includes("Sound.coin()") && grantFn.includes("tut-grant"),
      "a teaching grant plays Sound.coin and pulses both coin counters");
    r.eq((tut.match(/\{ granted \}/g) || []).length, 3,
      "all three granted steps (sticker / reroll / pillar) flag their bubble for the {grant} clause");
    r.ok(TutorialData.groups.shopC[0].text.includes("{grant}")
      && TutorialData.groups.shopD[0].text.includes("{grant}")
      && TutorialData.groups.shopE[0].text.includes("{grant}"),
      "tutorial.js carries the {grant} placeholder on all three granted bubbles");
    // The forced sticker bubble reads its label + payout LIVE from items.js:
    // {stickerLabel}/{stickerPayout} placeholders in the data, resolved at
    // show time from the registry and ESCAPED.
    r.ok(TutorialData.groups.shopC[1].text.includes("{stickerLabel}")
      && TutorialData.groups.shopC[1].text.includes("{stickerPayout}"),
      "the sticker bubble's name/payout are live placeholders in tutorial.js");
    r.ok(/escHtml\(k === "stickerLabel" \? t\.label : t\.description\)/.test(tut),
      "…resolved from the registry at show time, escaped (stepHtml)");
    r.ok(TutorialData.groups.grew[0].text.includes("{deckSize}"),
      "the deck-grew bubble reads the live deck size via {deckSize}");
    // Writer markup is injection-proof: the raw text is escaped FIRST, and
    // only then transformed (*bold* → <b>, newline → <br>).
    r.ok(/escHtml\(text\)\.replace\(\/\\\*/.test(tut),
      "renderMarkup escapes the writer copy before applying markup");
    // Keyboard hardening: pointer-events CSS can't stop Enter-key clicks, so a
    // capture-phase guard swallows any store activation outside the gate.
    const guard = tut.slice(tut.indexOf("function ensureGateGuard"), tut.indexOf("function setStoreGate"));
    r.ok(guard.includes('document.addEventListener("click"') && guard.includes("stopImmediatePropagation"),
      "a capture-phase click guard backs the store gate (keyboard activation covered)");
    // The coins-location bubble anchors the SUMMARY's own balance row — the
    // overlay covers the HUD bar, so #hudDopamine would ring an occluded
    // node. The anchor now lives in the registry under summaryBalance.
    r.ok(TutorialData.groups.coins[1].anchor === "summaryBalance"
      && /summaryBalance:\s+\(\) => \$\("\.dc-balance"\)/.test(tut)
      && !tut.includes("#hudDopamine\")"),
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

  // --- tutorial.js is the ONE copy source of truth ---------------------------
  {
    // The old tutorial.txt is gone — nothing may still reference it.
    r.ok(!existsSync(join(HERE, "..", "tutorial.txt")), "tutorial.txt is deleted (tutorial.js replaced it)");
    r.ok(!src.includes("tutorial.txt"), "the game script never mentions tutorial.txt");
    const html = readFileSync(join(HERE, "..", "index.html"), "utf8");
    r.ok(/document\.write\('<script src="tutorial\.js\?t='/.test(html),
      "tutorial.js loads via the same cache-busted document.write as items.js/difficulty.js");
    // The live data validated clean and the writer notes moved into its header.
    r.eq(TutorialData.problems.length, 0, "the live tutorial.js validates with zero problems");
    const raw = readFileSync(join(HERE, "..", "tutorial.js"), "utf8");
    for (const note of ["Skip tips", "tutorial2", "GATES", "PINNED SEED", "*asterisks*"])
      r.ok(raw.includes(note), "tutorial.js header carries the '" + note + "' writer note");
    // Copy spot-checks on stable phrases — the DATA carries the words now;
    // the game script carries none of them (edit tutorial.js alone to reword).
    const G = TutorialData.groups;
    const phrases = [
      [G.map1[2].text, "glowing node"], [G.coins[0].text, "surviving piles × smallest pile"],
      [G.coins[1].text, "rides the top bar"], [G.shopC[1].text, "ride it for the whole run"],
      [G.shopD[0].text, "re-rolls the whole shelf"], [G.shopE[0].text, "every pile in its column survives"],
      [TutorialData.grant, "on the house"],
    ];
    for (const [text, phrase] of phrases) {
      r.ok(text.includes(phrase), "tutorial.js carries the copy phrase: '" + phrase + "'");
      r.ok(!tut.includes(phrase), "…and the Tutorial module does NOT (copy lives in data only): '" + phrase + "'");
    }
    // Button labels preserved as writer data (default "Next" when omitted).
    r.eq(G.pinky[0].button, "Let's go", "pinky keeps its 'Let's go' button in the data");
    r.eq(G.grew[1].button, "Go", "the battle bubble keeps its 'Go' button");
    r.ok(G.map1[0].button == null && tut.includes('s.next || "Next"'),
      "an omitted button falls back to 'Next' at show time");
    // Hop notes + the sticker-picker nudge moved to data too.
    for (const k of ["deal", "store", "pack", "pickup"])
      r.ok(TutorialData.hops[k] && TutorialData.hops[k].text.length > 0, "tutorial.js carries the '" + k + "' hop note");
    r.ok(tut.includes('flash(TutorialData.hops[key], "hops." + key)'),
      "genericHop reads its copy from tutorial.js hops");
  }

  // --- fail-loud tutorial.js loading + validation ----------------------------
  {
    r.ok(src.includes("tutorial.js did not load — NINELIVES_TUTORIAL is undefined"),
      "a missing tutorial.js THROWS naming the file (loader contract)");
    // Evaluate the real TutorialData validator standalone against broken
    // clones — the console.error must NAME the offender, and the module must
    // keep booting (no throw) so the game never bricks on a copy typo.
    const tdSrc = tutorialDataSrc(src);
    r.ok(tdSrc.length > 200, "TutorialData module source located");
    const evalTD = (data) => {
      const errors = [];
      const fakeConsole = { error: (m) => errors.push(String(m)) };
      const td = new Function("NINELIVES_TUTORIAL", "console", tdSrc + "\n;return TutorialData;")(data, fakeConsole);
      return { errors, td };
    };
    // Broken-clone fixtures start from the already-loaded live data.
    const clone = () => JSON.parse(JSON.stringify({ seed: TutorialData.seed, grant: TutorialData.grant,
      hops: TutorialData.hops, groups: TutorialData.groups }));
    {
      const good = evalTD(clone());
      r.eq(good.errors.length, 0, "validator: the live data passes clean standalone");
      let threw = false;
      try { evalTD(undefined); } catch (e) { threw = /tutorial\.js/.test(String(e && e.message)); }
      r.ok(threw, "validator: a missing NINELIVES_TUTORIAL global throws naming tutorial.js");
      let threwNull = false;
      try { evalTD(null); } catch (e) { threwNull = /tutorial\.js/.test(String(e && e.message)); }
      r.ok(threwNull, "validator: a null NINELIVES_TUTORIAL throws the same friendly error");
      const noGroup = clone(); delete noGroup.groups.deal;
      const g1 = evalTD(noGroup);
      r.ok(g1.errors.some(m => m.includes("groups.deal")), "validator: a missing group console.errors naming it");
      const shortGroup = clone(); shortGroup.groups.coins.pop();
      r.ok(evalTD(shortGroup).errors.some(m => m.includes("groups.coins")),
        "validator: a missing step console.errors naming its group");
      const badPh = clone(); badPh.groups.pinky[0].text = "Hello {bogus}!";
      r.ok(evalTD(badPh).errors.some(m => m.includes("{bogus}")),
        "validator: an unknown placeholder console.errors naming it");
      const noSeed = clone(); noSeed.seed = "thirty-two";
      r.ok(evalTD(noSeed).errors.some(m => m.includes("seed")),
        "validator: a non-numeric pinned seed console.errors");
    }
    // Unknown ANCHOR keys are audited at Tutorial startup against the in-code
    // registry, and again per-show; either path names the key, and a runtime
    // miss bows the tour out through end() (stamp — never a soft-lock).
    r.ok(tut.includes("TutorialData.eachStep((d, label)") && tut.includes("unknown anchor key"),
      "Tutorial audits every tutorial.js anchor key against its registry at startup");
    r.ok(tut.includes("points at unknown anchor") && tut.includes("is missing/invalid — ending the tour"),
      "a runtime missing/invalid step or anchor is named…");
    r.ok(/if \(!steps\) \{ end\(\); return; \}/.test(tut) && /if \(!s\) \{ end\(\); return; \}/.test(tut),
      "…and both group() and flash() bow the tour out via end() on bad data");
    // Every anchor key used by the live data resolves in the registry.
    const anchorKeys = (tut.match(/^\s{6}(\w+):\s+\(\) =>/gm) || []).map(m => m.trim().split(":")[0]);
    r.ok(anchorKeys.length >= 15, "anchor registry located (" + anchorKeys.length + " keys)");
    const used = new Set();
    Object.values(TutorialData.groups).forEach(list => list.forEach(s => s.anchor != null && used.add(s.anchor)));
    Object.values(TutorialData.hops).forEach(s => s.anchor != null && used.add(s.anchor));
    for (const k of used)
      r.ok(anchorKeys.includes(k), "tutorial.js anchor key '" + k + "' resolves in the registry");
  }

  // --- desync guard: leg intros only when the gate IS the goal (TUT3 R4) -----
  {
    // ("onMap() {" — the bare name is a substring of renderProgressionMap())
    const onMap = tut.slice(tut.indexOf("onMap() {"), tut.indexOf("onMapNodeResolved()"));
    r.ok(onMap.includes('target.type === "store" && !fired.toStore'),
      "toStore's goal copy only shows when the gated node IS a store");
    r.ok(onMap.includes('target.type === "pickup" && !fired.toPickup'),
      "toPickup's 'grab the +1 card' only shows when the gated node IS a pickup (never rings a deal)");
    r.ok(onMap.includes('(target.type === "deal" || target.type === "boss") && !fired.grew'),
      "grew's battle copy only shows when the gated node IS a deal/boss");
    r.ok((onMap.match(/genericHop\(obj, target\)/g) || []).length === 3,
      "every other first-or-later render of a leg gets the type-matched hop note instead");
    // gateTargetFor prefers the strict-chain opening for deal0 (TUT3 R3).
    const gate = tut.slice(tut.indexOf("function gateTargetFor"), tut.indexOf("function genericHop"));
    r.ok(gate.indexOf("RunMap.tutorialStrictFrom(map, n.id)") !== -1
      && gate.indexOf("tutorialStrictFrom") < gate.indexOf("tutorialChainFrom"),
      "gateTargetFor's deal0 branch prefers the strict-chain opening deal, then chain, then any");
  }

  return r.summary();
}
