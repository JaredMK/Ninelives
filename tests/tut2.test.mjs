// TUT2 — Zen-first guided first-run tutorial. The bubble choreography is
// UI-side, so this suite covers what is verifiable DOM-free: the Tutorial
// module's shape (versioned pref, single stamp site in end(), the Zen deal
// start/end hooks, the replay one-shot), the campaign-unlock gate plumbing
// (campaignUnlocked / zenGamesPlayed / maybeUnlockCampaign / migrateCampaign-
// Unlock + their call sites), the tutorial.js data file (structure, fail-loud
// validation), the retirement of the whole guided-campaign machinery
// (pinned seed, map predicates, store gate, forced buys — absence pins), and
// the one surviving engine contract: a campaign map is byte-identical
// generateRun(saved seed) regeneration.
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
  const { RunMap, CampaignState, TutorialData } = g;
  const src = gameScript();
  const html = readFileSync(join(HERE, "..", "index.html"), "utf8");
  const tut = tutorialSrc(src);
  r.ok(tut.length > 200, "Tutorial module source located");

  // --- module shape: versioned pref + a single stamp site -------------------
  {
    r.ok(tut.includes('const PREF = "tutorial2"'), "completion lives on the versioned tutorial2 pref key");
    r.ok(!/getPref\("tutorial"\)/.test(src), "the OLD 'tutorial' pref is never read anywhere");
    const stamps = (tut.match(/SaveStore\.setPref\(PREF, "1"\)/g) || []).length;
    r.eq(stamps, 1, "exactly one stamp site (end() — complete, skip, and graceful bow-out all funnel there)");
    const endBody = tut.slice(tut.indexOf("function end()"), tut.indexOf("return {"));
    r.ok(endBody.includes('SaveStore.setPref(PREF, "1")'), "…the stamp lives in end()");
    // Zen-safe: the module never touches map, store, or campaign state.
    for (const bad of ["renderProgressionMap", "tut-gate", "tut-allow", "addCoins",
                       "startCampaign", "showDeckSelect", "RunMap."])
      r.ok(!tut.includes(bad), "the Tutorial module never references " + bad + " (Zen-only tour)");
  }

  // --- the Zen deal hooks ----------------------------------------------------
  {
    r.ok(/function shouldRun\(\) \{ return replayArmed \|\| SaveStore\.getPref\(PREF\) !== "1"; \}/.test(tut),
      "shouldRun() is overridden by the one-shot replayArmed flag");
    r.ok(/armReplay\(\) \{ replayArmed = true; \}/.test(tut), "the module exposes armReplay()");
    const onStart = tut.slice(tut.indexOf("onZenDealStart()"), tut.indexOf("onZenDealEnd()"));
    r.ok(onStart.includes("if (!shouldRun()) return;"), "onZenDealStart fires only when the tour should run");
    r.ok(onStart.includes("replayArmed = false;"), "…and consumes the replay one-shot (exactly one replay)");
    r.ok(onStart.includes('group("deal")'), "onZenDealStart fires the deal group");
    // v6.51 interactive tour: completing ALL 13 guided-deal steps earns the
    // deal-end beat (advance() stamps finalCompleted when the "deal" group
    // exhausts); every completion path ends stamped via end().
    r.ok(tut.includes('currentGroup === "deal"') && /finalCompleted = true/.test(tut),
      "completing the deal group earns the deal-end beat (advance stamps finalCompleted)");
    const onEnd = tut.slice(tut.indexOf("onZenDealEnd()"), tut.indexOf("onGuessResolved()"));
    r.ok(onEnd.includes("if (!guidedDeal) return;"), "onZenDealEnd is a no-op outside the guided deal");
    r.ok(onEnd.includes("if (!earned || campaignUnlocked()) return;"),
      "the zenEnd beat requires a completed tour AND a still-locked campaign (a veteran's replay skips it)");
    r.ok(onEnd.includes('group("zenEnd")'), "the zenEnd bubble tears the layer down on dismissal");
    r.ok(!/replayArmed[\s\S]{0,40}setPref/.test(tut), "arming a replay stamps nothing");
  }

  // --- call-site wiring ------------------------------------------------------
  {
    r.ok(src.includes("if (zenMode) Tutorial.onZenDealStart();"),
      "the dealt handler starts the tour on Zen deals only (never the campaign)");
    r.ok(src.includes("Tutorial.onGuessResolved(payload.correct);"),
      "resolved guesses feed the tour (milestone waits / guess-gated steps)");
    r.ok(tut.includes('feed("guess",') && tut.includes('evt === "guess"'),
      "…the module counts resolved guesses toward its waits (the old step-aside is retired)");
    const zenEnd = fnBody(src, "onZenEnd");
    r.ok(zenEnd.includes("Tutorial.onZenDealEnd(result);") && zenEnd.includes("maybeUnlockCampaign();"),
      "onZenEnd runs the tour's end beat and the unlock check");
    r.ok(fnBody(src, "zenQuitToMenu").includes("maybeUnlockCampaign();"),
      "leaving Zen to the menu re-checks the unlock (mid-game exit after a counted game)");
    const quit = fnBody(src, "quitToMenu");
    r.ok(quit.includes("zenMode") && quit.includes("maybeUnlockCampaign();"),
      "the pause-menu quit does the same on the Zen branch");
    r.ok(src.includes("migrateCampaignUnlock(saved);"),
      "boot migrates existing players past the gate");
    r.ok(src.includes("Tutorial.armReplay();"), "the manual's Replay arms the one-shot");
    r.ok(fnBody(src, "zenTeardown").includes("Tutorial.suspend();"),
      "leaving Zen suspends the tour WITHOUT stamping (no bubble lingers over the menu)");
    r.ok(tut.includes("suspend() {") && !/suspend\(\) \{[\s\S]{0,120}setPref/.test(tut),
      "suspend() exists and never stamps the pref (an unfinished tour re-offers itself)");
  }

  // --- the campaign-unlock gate ---------------------------------------------
  {
    r.ok(src.includes('const CAMPAIGN_UNLOCK_PREF = "campaignUnlocked";'),
      "the unlock lives on its own pref (ninelives.pref.campaignUnlocked)");
    r.ok(/function campaignUnlocked\(\) \{ return SaveStore\.getPref\(CAMPAIGN_UNLOCK_PREF\) === "1"; \}/.test(src),
      "campaignUnlocked() reads that pref");
    const games = fnBody(src, "zenGamesPlayed");
    r.ok(games.includes("DifficultyData.zenIds") && games.includes("ZenStats.get(id).games"),
      "zenGamesPlayed sums COUNTED games (first-guess rule) across every Zen difficulty");
    const maybe = fnBody(src, "maybeUnlockCampaign");
    r.ok(maybe.includes('getPref("tutorial2") !== "1"') && maybe.includes("zenGamesPlayed() > 0"),
      "the unlock needs BOTH: tutorial done (skip counts) AND ≥1 counted Zen game");
    const migrate = fnBody(src, "migrateCampaignUnlock");
    r.ok(migrate.includes("saved.campaign") && migrate.includes('getPref("tutorial2")')
      && migrate.includes("Stats.get().gamesPlayed") && migrate.includes("zenGamesPlayed()"),
      "the migration grandfathers: campaign save, done tutorial, counted campaign runs, counted Zen games");
    const menu = fnBody(src, "showMainMenu");
    r.ok(menu.includes("if (campaignUnlocked())"), "the Climb/New Climb button is gated on campaignUnlocked()");
    r.ok(!menu.includes("menu-note"), "no pointer note (v5.57: removed — Zen is the obvious primary CTA while locked)");
    r.ok(!menu.includes("campaignUnlocked()) return"), "…but the menu itself still renders (Zen is the whole menu)");
  }

  // --- the guided-campaign machinery is GONE (absence pins) ------------------
  {
    for (const gone of ["pickTutorialRun", "setTutorialRun", "isTutorialRun", "tutorialMapRetries",
                        "TutorialData.seed", "tutorialPathOk", "tutorialPathStrict", "tutorialChainFrom",
                        "tutorialStrictFrom", "TUTORIAL_CHAIN", "mysteryMasked", "onStoreRerolled",
                        "guidedRerollPending", "tut-gate-store", "tut-allow", "tut-dim", "tut-grant",
                        "tut-deck-ring", "seedStoreOffer", "onMapRender", "onNewCampaign"])
      r.ok(!src.includes(gone), "retired machinery stays gone: " + gone);
    r.ok(typeof RunMap.tutorialPathOk === "undefined" && typeof RunMap.tutorialPathStrict === "undefined",
      "RunMap exports no tutorial predicates");
    const c = CampaignState.create();
    r.ok(typeof c.setTutorialRun === "undefined" && typeof c.isTutorialRun === "undefined",
      "CampaignState exposes no tutorial-run flag");
    r.ok(!("tutorialMapRetries" in RunMap.GEN_CONFIG), "GEN_CONFIG carries no tutorial retry budget");
  }

  // --- the surviving engine contract: seed → map determinism -----------------
  {
    const c = CampaignState.create();
    c.reset();
    const snap = c.serialize();
    const regen = RunMap.generateRun(snap.runSeed, snap.stageEntryDecks, { postBossJokerStages: [0, 1], genVersion: snap.genV });
    const mapSig = (m) => m.nodes.map(n => [n.id, n.type, n.row, n.piles || 0, n.mystery ? 1 : 0,
      (n.next || []).join(".")].join(":")).join("|");
    r.eq(mapSig(c.getMap()), mapSig(regen),
      "a campaign map IS generateRun(saved seed) — byte-identical regeneration, unchanged");
    r.ok(!("tutorialRun" in snap), "no tutorial flag is ever persisted in the save");
  }

  // --- tutorial.js data: shape + fail-loud validation ------------------------
  {
    r.eq(TutorialData.stepCounts.deal, 13, "the deal group is exactly 13 steps (v6.51 interactive tour)");
    r.eq(TutorialData.stepCounts.zenEnd, 1, "the zenEnd group is exactly 1 step");
    r.eq(Object.keys(TutorialData.stepCounts).length, 2, "…and those are the ONLY groups");
    r.eq(TutorialData.problems.length, 0, "the live tutorial.js validates with zero problems");
    r.ok(/document\.write\('<script src="tutorial\.js\?t='/.test(html),
      "tutorial.js loads via the same cache-busted document.write as items.js/difficulty.js");
    r.ok(src.includes("tutorial.js did not load — NINELIVES_TUTORIAL is undefined"),
      "a missing tutorial.js THROWS naming the file (loader contract)");
    const tdSrc = tutorialDataSrc(src);
    r.ok(tdSrc.length > 200, "TutorialData module source located");
    const evalTD = (data) => {
      const errors = [];
      const fakeConsole = { error: (m) => errors.push(String(m)) };
      const td = new Function("NINELIVES_TUTORIAL", "console", tdSrc + "\n;return TutorialData;")(data, fakeConsole);
      return { errors, td };
    };
    const clone = () => JSON.parse(JSON.stringify({ groups: TutorialData.groups }));
    r.eq(evalTD(clone()).errors.length, 0, "validator: the live data passes clean standalone");
    let threw = false;
    try { evalTD(undefined); } catch (e) { threw = /tutorial\.js/.test(String(e && e.message)); }
    r.ok(threw, "validator: a missing NINELIVES_TUTORIAL global throws naming tutorial.js");
    let threwNull = false;
    try { evalTD(null); } catch (e) { threwNull = /tutorial\.js/.test(String(e && e.message)); }
    r.ok(threwNull, "validator: a null NINELIVES_TUTORIAL throws the same friendly error");
    const noGroup = clone(); delete noGroup.groups.deal;
    r.ok(evalTD(noGroup).errors.some(m => m.includes("groups.deal")),
      "validator: a missing group console.errors naming it");
    const shortGroup = clone(); shortGroup.groups.deal.pop();
    r.ok(evalTD(shortGroup).errors.some(m => m.includes("groups.deal")),
      "validator: a missing step console.errors naming its group");
    const badPh = clone(); badPh.groups.deal[0].text = "Hello {bogus}!";
    r.ok(evalTD(badPh).errors.some(m => m.includes("{bogus}")),
      "validator: ANY placeholder console.errors naming it (this flow supports none)");
  }

  // --- graceful bow-out + anchor audit ---------------------------------------
  {
    r.ok(tut.includes("TutorialData.eachStep((d, label)") && tut.includes("unknown anchor key"),
      "Tutorial audits every tutorial.js anchor key against its registry at startup");
    r.ok(tut.includes("points at unknown anchor") && tut.includes("is missing/invalid — ending the tour"),
      "a runtime missing/invalid step or anchor is named…");
    r.ok(/if \(!built\) \{ end\(\); return; \}/.test(tut),
      "…and group() bows the tour out via end() on bad data (never a soft-lock)");
    const anchorKeys = (tut.match(/^\s{6}(\w+):\s+\(\) =>/gm) || []).map(m => m.trim().split(":")[0]);
    r.eq(anchorKeys.length, 8, "the anchor registry is exactly the 8 Zen anchors (v6.51: +dealPileFirst/dealRailUp/pileCount)");
    const used = new Set();
    Object.values(TutorialData.groups).forEach(list => list.forEach(s => s.anchor != null && used.add(s.anchor)));
    for (const k of used)
      r.ok(anchorKeys.includes(k), "tutorial.js anchor key '" + k + "' resolves in the registry");
    r.ok(/escHtml\(text\)\.replace\(\/\\\*/.test(tut),
      "renderMarkup escapes the writer copy before applying markup (injection-proof)");
  }

  return r.summary();
}
