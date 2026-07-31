// HOLDHELP — hold-for-help everywhere (#7): the shared showTextHelp /
// attachHoldHelp helpers, holds on the guess buttons (Higher/Lower/Same),
// the HUD chips (Same Charge, Same-Power, stage run, clear reward), and
// progression-map nodes. Presentation only (no tunables, no persisted state),
// so this is a structural check in the help2.test.mjs style: loadGame() proves
// the script still evaluates, source-shape checks pin the new wiring.
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

export function run() {
  const r = makeRunner("holdhelp.test.mjs");
  const html = fullHtml();
  const src = gameScript(html);

  const g = loadGame();
  r.ok(!!(g.GameEngine && g.StickerTypes), "game script evaluates with the HOLDHELP wiring in place");

  // ============================================================
  // PART A — the shared helpers
  // ============================================================
  {
    const sth = fnBody(src, "showTextHelp");
    r.ok(sth.length > 0, "showTextHelp exists");
    r.ok(sth.includes('pk-head'), "showTextHelp renders a pk-head title");
    r.ok(sth.includes('pk-desc'), "showTextHelp renders a pk-desc description");
    r.ok((sth.match(/escHtml\(/g) || []).length >= 2, "showTextHelp escapes BOTH title and description");
    r.ok(sth.includes("el.peekInfo.innerHTML"), "showTextHelp renders into #peekInfo");
    r.ok(sth.includes('el.peekInfo.classList.remove("hidden")'), "showTextHelp shows #peekInfo");
    r.ok(/classList\.toggle\("peek-band", peekInBand\(\)\)/.test(sth), "showTextHelp toggles body.peek-band via peekInBand()");

    const ahh = fnBody(src, "attachHoldHelp");
    r.ok(ahh.length > 0, "attachHoldHelp exists");
    r.ok(ahh.includes('addEventListener("pointerdown"'), "attachHoldHelp arms on pointerdown");
    r.ok(ahh.includes("180"), "attachHoldHelp uses the 180ms hold threshold");
    r.ok(ahh.includes('addEventListener("pointerup"'), "attachHoldHelp releases on pointerup");
    r.ok(ahh.includes('addEventListener("pointercancel"'), "attachHoldHelp releases on pointercancel");
    r.ok(ahh.includes("closePeekInfo"), "attachHoldHelp defaults to closePeekInfo on release");
  }

  // ============================================================
  // PART B — guess buttons: tap guesses, hold explains (Same also
  // carries the equipped power's info)
  // ============================================================
  {
    const ai = fnBody(src, "attachInput");
    r.ok(ai.length > 0, "attachInput exists");
    r.ok(ai.includes("GUESS_HELP"), "the guess-button help copy table (GUESS_HELP) is present");
    for (const dir of ["higher", "lower", "same"]) {
      r.ok(new RegExp(dir + ': \\["').test(ai) || new RegExp(dir + '": \\["').test(ai),
        "GUESS_HELP has a " + dir + " entry");
    }
    r.ok(ai.includes('["higher", el.btnHigher]'), "the hold loop covers btnHigher");
    r.ok(ai.includes('["lower", el.btnLower]'), "the hold loop covers btnLower");
    r.ok(ai.includes('["same", el.btnSame]'), "the hold loop covers btnSame");
    r.ok(/dir === "same" && spId\(\)/.test(ai), "Same with an equipped power opens the power info on hold");
    r.ok(/openSamePowerInfo\(spId\(\)\)/.test(ai), "the Same-power hold still routes to openSamePowerInfo");
    r.ok(/else showTextHelp\(GUESS_HELP\[dir\]\[0\]/.test(ai), "without a power (and for Higher/Lower) the hold shows GUESS_HELP");
    r.ok(/if \(suppressClick\) \{ suppressClick = false; return; \}/.test(ai), "a hold suppresses the release click");
    r.ok(/submitGuess\(dir\)/.test(ai), "a plain tap still submits the guess");
    // The old Same-only hold block is gone (one unified loop, no orphans).
    r.ok(!/spHoldTimer|suppressSameClick|spRelease/.test(src), "the old Same-only hold block is fully replaced");
  }

  // ============================================================
  // PART C — HUD chips hold-for-help
  // ============================================================
  {
    const ai = fnBody(src, "attachInput");
    r.ok(ai.includes("HUD_SAME_HELP"), "the Same-Charge help copy const is present");
    r.ok(ai.includes("DEAL_STATUS_HELP"), "the clear-reward help copy const is present");
    r.ok(ai.includes("el.hudSame.title = HUD_SAME_HELP"), "hudSame's title is set from the const (single source)");
    r.ok(ai.includes("el.dealStatus.title = DEAL_STATUS_HELP"), "dealStatus's title is set from the const (single source)");
    r.ok(ai.includes("attachHoldHelp(el.hudSame"), "hudSame has hold-for-help");
    r.ok(ai.includes("attachHoldHelp(el.hudSamePower"), "hudSamePower has hold-for-help");
    r.ok(/getSamePower\(\)/.test(ai) && ai.includes("openSamePowerInfo(id)"), "the hudSamePower hold opens the equipped power's info");
    r.ok(ai.includes("attachHoldHelp(el.stageRun"), "stageRun has hold-for-help");
    r.ok(ai.includes("attachHoldHelp(el.dealStatus"), "dealStatus has hold-for-help");
    // ECON1: the HUD score chip carries hold-for-help, copy from its own const.
    r.ok(ai.includes("HUD_SCORE_HELP"), "the score-chip help copy const is present");
    r.ok(ai.includes("el.hudScoreChip.title = HUD_SCORE_HELP"), "hudScoreChip's title is set from the const (single source)");
    r.ok(ai.includes("attachHoldHelp(el.hudScoreChip"), "hudScoreChip has hold-for-help");
    // v5.73: the coin balance carries hold-for-help, copy from its own const.
    r.ok(ai.includes("HUD_COINS_HELP"), "the coins help copy const is present");
    r.ok(ai.includes("el.hudDop.title = HUD_COINS_HELP"), "hudDop's title is set from the const (single source)");
    r.ok(ai.includes("attachHoldHelp(el.hudDop"), "the coin balance has hold-for-help");
  }

  // ============================================================
  // PART C2 — the rail's fan toggle + always-reachable guess holds (v5.73)
  // ============================================================
  {
    // The fan toggle has a tap ACTION, so it uses the guess-button pattern:
    // hold shows help and SUPPRESSES the toggle.
    r.ok(src.includes("FAN_BTN_HELP"), "the fan-button help copy const is present");
    r.ok(/fanSuppress = false; return;/.test(src), "a fan hold suppresses the release click (no accidental toggle)");
    r.ok(/showTextHelp\("Fan", FAN_BTN_HELP\)/.test(src), "the fan hold shows the FAN_BTN_HELP copy");
    // guess-disabled keeps the buttons pointer-LIVE so their help is readable
    // with no pile selected (tap-guess is guarded in submitGuess).
    const css = html.slice(0, html.indexOf("</style>"));
    r.ok(!/guess-disabled[^}]*pointer-events:\s*none/.test(css),
      "guess-disabled no longer kills pointer events (holds work unselected)");
    const sg = fnBody(src, "submitGuess");
    r.ok(sg.includes("if (selected === null) return;"), "…because submitGuess still no-ops with no pile selected");
  }

  // ============================================================
  // PART D — progression-map nodes hold-for-help
  // ============================================================
  {
    const ai = fnBody(src, "attachInput");
    r.ok(ai.includes("el.mapTrack.addEventListener(\"click\", onMapNodeTap)"), "the map tap wiring is kept");
    r.ok(/el\.mapTrack\.addEventListener\("pointerdown"/.test(ai), "the map hold arms on a delegated pointerdown");
    r.ok(ai.includes(".pm-node[data-action='node']"), "the hold targets map node buttons");
    r.ok(ai.includes("350"), "the map hold uses the 350ms threshold");
    r.ok(ai.includes("mapNodeLabel(n)"), "the node label comes from mapNodeLabel (the map key's single source)");
    r.ok(ai.includes("campaign.nodeHidden && campaign.nodeHidden(n.id)"), "concealed mystery nodes stay hidden (nodeHidden read directly — no tutorial mask)");
    r.ok(!ai.includes("mysteryMasked"), "the map hold has no tutorial mask dependency (the Zen-first tour never touches the map)");
    r.ok(ai.includes("??? — a gamble, good or bad, revealed when you arrive"), "a concealed node's hold copy reads as a gamble, revealed on arrival");
    r.ok(ai.includes("mapSuppress") && /stopPropagation\(\)/.test(ai), "the release after a map hold cannot travel (capture-phase suppression)");
  }

  return r.summary();
}
