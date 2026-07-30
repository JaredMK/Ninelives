// CRT4 — CRT CASINO chunk 4: menus, deck select, collection, run summary +
// the remaining popup/toast family (strictly aesthetic). Structural checks in
// the crt2/crt3 style: loadGame() proves the script still evaluates, and
// source-shape checks pin what the restyle relies on — the §4 pixel-button
// roles on every menu surface, the phosphor wordmark/marquee treatment, ink
// scrims everywhere (no colour washes, no blur), the palette recolours (zen
// bars, static toast, coin values gold), the texture law (baked dither tiles
// only — lost-paths + feTurbulence fully purged), the boot-splash palette
// handoff, and the UNCHANGED mechanisms (menu builders, confirm flows, the
// zen histogram state machine, crt-flicker hooks). No tunables pinned.
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
/** First CSS rule body for a selector written exactly at line start ("  sel {"). */
function cssRule(html, selector) {
  const at = html.indexOf("\n  " + selector + " {");
  if (at === -1) return "";
  const open = html.indexOf("{", at);
  const close = html.indexOf("}", open);
  return close === -1 ? "" : html.slice(open, close + 1);
}

export function run() {
  const r = makeRunner("crt4.test.mjs");
  const html = fullHtml();
  const src = gameScript(html);

  // The game still evaluates with the menu restyle in place.
  const g = loadGame();
  r.ok(!!(g.GameEngine && g.CampaignState && g.DifficultyData), "game script evaluates with the CRT menu restyle");

  // --- Texture law: baked tiles only, the old textures are PURGED ----------
  {
    r.ok(!html.includes("<feTurbulence") && !html.includes("%3CfeTurbulence"),
      "no LIVE feTurbulence element remains (baked tiles are the one texture; the word survives only in comments)");
    r.ok(!html.includes("--lost-paths:") && !html.includes("var(--lost-paths)")
      && !html.includes("--felt-grain:") && !html.includes("var(--felt-grain)"),
      "the lost-paths tangle + felt-grain noise tokens are retired (no definition, no use)");
    r.ok(/--felt-tile:\s*url\('data:image\/gif/.test(html), "--felt-tile is a baked data-URI dither");
    const menu = cssRule(html, ".menu-screen");
    r.ok(menu.includes("background: var(--felt-deep)") && !menu.includes("radial-gradient"),
      ".menu-screen is a flat deep-felt table (no gradient stack)");
    r.ok(menu.includes("env(safe-area-inset-top") && menu.includes("env(safe-area-inset-bottom"),
      "…and keeps the uifix1 safe-area fold");
    r.ok(cssRule(html, ".menu-screen::before").includes("var(--felt-tile)"),
      "the felt-nap tile rides the ::before layer");
    r.ok(cssRule(html, "#tissue::before").includes("var(--felt-tile)"),
      "#tissue wears the same baked weave (feTurbulence grain replaced)");
    r.ok(!html.includes("@keyframes menuGlow"),
      "the breathing menu glow (blur + infinite animation) is deleted — standing-animation count went DOWN");
  }

  // --- Main menu: §4 buttons, phosphor wordmark ----------------------------
  {
    const item = cssRule(html, ".menu-item");
    r.ok(item.includes("var(--felt-mid)") && item.includes("var(--px) solid var(--ink)")
      && item.includes("4px 4px 0 0 var(--shadow)") && item.includes("border-radius: 0"),
      ".menu-item is the §4 pixel button");
    r.ok(!item.includes("linear-gradient") && !item.includes("inset 0 1px"),
      "…gradients + bevel highlights retired");
    r.ok(cssRule(html, ".menu-item:active").includes("translate(2px, 2px)"), "…and sinks when pressed");
    r.ok(cssRule(html, ".menu-item.primary").includes("var(--phosphor)")
      && cssRule(html, ".menu-item.primary").includes("var(--glow)"),
      "the primary menu action is the phosphor CTA (the one glow)");
    r.ok(cssRule(html, ".menu-item.danger").includes("var(--suit-red)"),
      "Reset progress wears the §4 danger face");
    const mtc = cssRule(html, ".menu-title .mt-c");
    r.ok(mtc.includes("var(--phosphor)") && mtc.includes("var(--glow)"),
      "the wordmark's last word is phosphor with THE glow");
    r.ok(cssRule(html, ".menu-title .mt-a, .menu-title .mt-b").includes("var(--card-face)"),
      "the leading words are aged cream");
    r.ok(!/\.menu-title \.mt-[abc] \{[^}]*rotate\(/.test(html), "the hand-tilted word rotations are gone (square pixel grid)");
    r.ok(/class="menu-logo" src="data:image\/svg\+xml,[^"]*%23d9a441/.test(html)
      && /class="menu-logo" src="data:image\/svg\+xml,[^"]*%234ef08a/.test(html)
      && !html.includes("%23c0436c") && !html.includes("%238e2f4e"),
      "the synapse-equals logo (menu + HUD Same twin) re-inks gold + phosphor (rose purged), still data-URI SVGs (uifix1)");
    r.ok(!cssRule(html, ".menu-logo").includes("drop-shadow("), "the logo's blurred lift filter is gone (§10 no blur)");
  }

  // --- Deck select: marquee title, tier chips, locked "?" silhouette -------
  {
    const title = cssRule(html, ".ds-title");
    r.ok(title.includes("var(--font-display)") && title.includes("var(--phosphor)") && title.includes("var(--glow)"),
      ".ds-title (deck/zen/collection screens) is the phosphor display marquee");
    r.ok(!/\n  \.ds-title \{[^}]*\}[\s\S]*\n  \.ds-title \{/.test(html),
      "…and no later felt-pass override re-inks it");
    const tier = cssRule(html, ".ds-tier");
    r.ok(tier.includes("var(--felt-mid)") && tier.includes("var(--px) solid var(--ink)") && tier.includes("border-radius: 0"),
      "difficulty tier chips are pixel chips");
    r.ok(cssRule(html, ".ds-tier.sel").includes("var(--phosphor)"),
      "the picked tier lights phosphor (the selection colour everywhere)");
    r.ok(!cssRule(html, ".ds-tier.locked").includes("filter"), "locked tiers dim by opacity only");
    r.ok(cssRule(html, ".ds-panel.locked .ds-deckchar .deck-char").includes("brightness(0)"),
      "a locked deck flattens to the ink silhouette (on the INNER character, so overlays escape)");
    const q = cssRule(html, ".ds-panel.locked .ds-deckchar::after");
    r.ok(q.includes('content: "?"') && q.includes("var(--font-display)"),
      "…under a display-face \"?\" (the mystery treatment, not an emoji padlock)");
    const seed = cssRule(html, ".ds-seed-input");
    r.ok(seed.includes("var(--felt-deep)") && seed.includes("var(--gold)") && seed.includes("border-radius: 0"),
      "the seed input is a recessed felt well with gold code text");
    r.ok(cssRule(html, ".ds-seed-input:focus").includes("var(--phosphor)"),
      "…whose focus ring is phosphor (static)");
    r.ok(cssRule(html, ".ds-seed-note.err").includes("var(--suit-red)"),
      "an invalid code reads as the danger chip");
    r.ok(cssRule(html, ".ds-seed-note.ok").includes("var(--gold)"), "a valid code notes in gold");
  }

  // --- Zen select ----------------------------------------------------------
  {
    const e = cssRule(html, ".zs-entry");
    r.ok(e.includes("var(--felt-mid)") && e.includes("var(--px) solid var(--ink)")
      && e.includes("4px 4px 0 0 var(--shadow)"), ".zs-entry rows are pixel panels");
    r.ok(cssRule(html, ".zs-entry.selected").includes("var(--phosphor)"), "the pick lights phosphor");
    r.ok(!cssRule(html, ".zs-entry.locked").includes("grayscale"), "locked rows dim by opacity only");
    r.ok(cssRule(html, ".zs-start.ready").includes("var(--phosphor)")
      && cssRule(html, ".zs-start.ready").includes("var(--glow)"),
      "Start goes phosphor CTA once a difficulty is picked");
    r.ok(cssRule(html, ".zs-start").includes("var(--felt-mid)"), "…from the §4 disabled state");
  }

  // --- Collection + unlock plumbing ---------------------------------------
  {
    const tile = cssRule(html, ".col-tile");
    r.ok(tile.includes("var(--felt-mid)") && tile.includes("var(--px) solid var(--ink)") && tile.includes("border-radius: 0"),
      "collection tiles are pixel panels");
    r.ok(cssRule(html, ".col-head").includes("var(--gold)"), "class headers take the gold sub-header voice");
    // The unlocks-suite flatten literals must survive verbatim.
    r.ok(html.includes("#colList .pack-foil { filter: none; }")
      && html.includes("#colList .dcs { box-shadow: none; }")
      && html.includes("#colList .dcs-gloss { display: none; }"),
      "the v5.23 collection raster-flatten literals survive");
    r.ok(html.includes("body:has(#collectionScreen:not(.hidden)) .card-info { z-index: 1500; }"),
      "the collection detail z-lift literal survives");
    r.ok(cssRule(html, ".ulk-fill").includes("var(--phosphor)"), "unlock progress fills phosphor");
    r.ok(cssRule(html, ".ulk-bar").includes("var(--felt-deep)") && cssRule(html, ".ulk-bar").includes("border-radius: 0"),
      "…in a squared recessed track");
  }

  // --- Sheets (stats / manual / pause / telemetry frames) ------------------
  {
    r.ok(cssRule(html, ".sheet-overlay").includes("rgba(16, 16, 14"),
      "sheet scrim is INK (no warm wash, no blur)");
    const p = cssRule(html, ".sheet-panel");
    r.ok(p.includes("var(--felt-mid)") && p.includes("var(--px) solid var(--ink)")
      && p.includes("border-radius: 0") && !p.includes("linear-gradient") && !p.includes("box-shadow"),
      ".sheet-panel is a squared felt panel (gradient + blurred lift shadow gone)");
    r.ok(cssRule(html, ".sheet-head").includes("var(--phosphor)")
      && cssRule(html, ".sheet-head").includes("var(--font-display)"),
      "sheet titles are phosphor display marquee");
    r.ok(cssRule(html, ".sheet-reset").includes("var(--suit-red)"), "Reset stats wears the danger face");
  }

  // --- Stats + THE zen histogram recolour ----------------------------------
  {
    const t = cssRule(html, ".stat-tile");
    r.ok(t.includes("var(--felt-deep)") && t.includes("var(--px) solid var(--ink)"),
      "stat tiles are recessed felt wells");
    r.ok(cssRule(html, ".stat-tile .sv").includes("var(--phosphor)")
      && cssRule(html, ".stat-tile .sv").includes("var(--glow)"),
      "the values are phosphor readouts");
    r.ok(cssRule(html, ".zf-opt.selected").includes("var(--phosphor)")
      && cssRule(html, ".zf-opt.selected").includes("var(--ink)"),
      "the live scope filter chip is phosphor with ink text");
    r.ok(html.includes(".zv-win .zv-bar { background: var(--phosphor); }"),
      "zen WIN bars are flat phosphor");
    r.ok(html.includes(".zv-loss .zv-bar { background: var(--suit-red); }"),
      "zen LOSS bars are flat suit-red");
    // The zen6 CSS state machine survives byte-for-byte (spot the exact pins).
    r.ok(html.includes(".zh-wins .zv-bar { height: var(--hw); }")
      && html.includes(".zh-wins .zc-wagg,  .zh-wins .zc-ldist")
      && html.includes(".zh-drillwrap.zh-drilled .zh-back { display: inline-flex; }"),
      "the pinned zen6 expand/contract literals are untouched");
  }

  // --- Phase overlay: ink scrim, win/lose frames, palette values -----------
  {
    const ov = cssRule(html, ".overlay");
    r.ok(ov.includes("rgba(16, 16, 14") && !ov.includes("backdrop-filter:"),
      ".overlay backdrop is the ink scrim, blur-free");
    r.ok(!html.includes("var(--lost-paths)"), "no overlay texture layer remains");
    r.ok(cssRule(html, ".overlay.win").includes("inset 0 0 0 4px var(--phosphor)"),
      "a WON deal frames the screen phosphor (celebration bezel)");
    r.ok(cssRule(html, ".overlay.lose").includes("inset 0 0 0 4px var(--suit-red)"),
      "a LOST deal frames it suit-red on the ink");
    r.ok(cssRule(html, ".loss-fossils").includes("--net: var(--suit-red)"),
      "the death screen's bouncing fossils retint suit-red via the scoped token");
    r.ok(fnBody(src, "fossilSvg").includes('var(--net)'), "…which fossilSvg still inks with");
    r.ok(!html.includes('"Baloo 2", var(--font-display)'), "the deal-cleared Baloo literal is retired");
    // (The dead pre-itemized .ocoins-* rows were deleted in the chunk-6 sweep —
    // the LIVE .dc-* breakdown lines carry the gold read.)
    r.ok(!html.includes(".ocoins-row"), "the dead .ocoins-* payout rows are swept");
    r.ok(cssRule(html, ".dc-val").includes("var(--gold)"),
      "coin values on the payout screens read GOLD (§1)");
    r.ok(cssRule(html, ".run-stat").includes("var(--felt-mid)")
      && cssRule(html, ".run-stat").includes("var(--px) solid var(--ink)"),
      "summary tiles are pixel plaques");
    r.ok(cssRule(html, ".run-stat-value").includes("var(--phosphor)"), "…with phosphor readouts");
    r.ok(cssRule(html, ".play-btn.play-btn-2").includes("var(--felt-mid)"),
      "the secondary overlay action is the §4 plain pixel button");
    r.ok(cssRule(html, ".ov-seed").includes("var(--gold)") && cssRule(html, ".ov-seed").includes("border-radius: 0"),
      "the share-seed row is the squared gold-dashed chip");
    // CRT flicker still fires exactly on deal resolution (chunk-1 hook).
    const so = fnBody(src, "showOverlay");
    r.ok(so.includes('opts.kind === "win" || opts.kind === "lose"') && so.includes("crtFlicker()"),
      "showOverlay still fires the one-shot CRT flicker on win/lose only");
  }

  // --- Unlock pops ---------------------------------------------------------
  {
    r.ok(cssRule(html, ".deck-unlock-pop").includes("rgba(16, 16, 14"),
      "the unlock pop scrim is ink");
    r.ok(cssRule(html, ".duc-spark").includes("var(--phosphor)")
      && cssRule(html, ".duc-spark").includes("var(--glow)"),
      "sparkles are phosphor — the only glow");
    const lock = cssRule(html, ".duc-lock");
    r.ok(lock.includes("font-size: 0") && lock.includes("data:image/svg+xml")
      && lock.includes("image-rendering: pixelated"),
      "the padlock is a pixel sprite (emoji glyph zeroed — emoji ignore the palette)");
    r.ok(cssRule(html, ".duc-charwrap .deck-char").includes("brightness(0)"),
      "deck pop: the silhouette filter sits on the character, not the wrap");
    r.ok(html.includes(".iuc-objwrap > :not(.duc-lock):not(.duc-spark)"),
      "item pop: silhouette targets the object children, so the padlock/sparks escape");
    // Reveal-timing behaviour stays pinned by unlocks.test.mjs; spot the markup.
    r.ok(fnBody(src, "showItemUnlockPop").includes("duc-spark s1"), "the pop markup still carries the sparkle spans");
  }

  // --- Toast + prompt-bar roles + nav chrome -------------------------------
  {
    r.ok(cssRule(html, ".static-toast.safe").includes("var(--phosphor)"),
      "static SAFE toast = phosphor on deep felt");
    r.ok(cssRule(html, ".static-toast.boom").includes("var(--suit-red)"),
      "static DESTROYED toast = the danger face");
    r.ok(cssRule(html, ".static-toast").includes("border-radius: 0")
      && cssRule(html, ".static-toast").includes("2px 2px 0 0 var(--shadow)"),
      "…both squared with the hard shadow");
    const ap = cssRule(html, ".ap-btn");
    r.ok(ap.includes("var(--felt-mid)") && ap.includes("var(--px) solid var(--ink)"),
      "prompt-bar buttons are §4 pixel buttons");
    r.ok(cssRule(html, ".ap-btn.primary").includes("var(--phosphor)")
      && cssRule(html, ".ap-btn.danger").includes("var(--suit-red)")
      && cssRule(html, ".ap-btn.gold").includes("var(--gold)"),
      "…with the full role set: phosphor commit / red destroy / gold cost");
    r.ok(html.includes("body.menu-confirm .play-controls { z-index: 1500; }")
      && html.includes("body.modal-prompt .play-controls { z-index: 95; }"),
      "the confirm z-lifts are untouched (confirmbar contract)");
    r.ok(cssRule(html, ".nav-btn").includes("border-radius: 0")
      && cssRule(html, ".nav-btn").includes("var(--px) solid var(--ink)"),
      "corner nav buttons squared into the pixel chrome");
  }

  // --- Debug FRAME only ----------------------------------------------------
  {
    r.ok(cssRule(html, ".debug-overlay").includes("rgba(16, 16, 14"), "debug scrim is ink");
    const dp = cssRule(html, ".debug-panel");
    r.ok(dp.includes("var(--px) dashed var(--ink)") && dp.includes("border-radius: 0")
      && dp.includes("var(--card-face)"),
      "debug panel FRAME squared (dashed ink = dev-tool marker); internals exempt");
    r.ok(cssRule(html, ".debug-toggle").includes("var(--felt-mid)")
      && cssRule(html, ".debug-toggle").includes("border-radius: 0"),
      "the 🐞 toggle joins the pixel chrome");
  }

  // --- Boot splash + native handoff (palette side; boot2 owns the wiring) --
  {
    // The old cream/ink brand hexes survive ONLY inside the kept jar art —
    // the splash CSS itself is fully on the palette now.
    const splashCss = html.slice(html.indexOf("#bootSplash {"), html.indexOf("</style>"));
    r.ok(!splashCss.includes("#f6f3ec") && !splashCss.includes("#20313a"),
      "splash CSS carries no off-palette brand hexes (they remain only in the jar SVG)");
    const cfg = JSON.parse(readFileSync(join(HERE, "..", "app", "capacitor.config.json"), "utf8"));
    const feltDeep = (html.match(/--felt-deep:\s*(#[0-9a-fA-F]{6})/) || [])[1];
    r.eq(cfg.plugins.SplashScreen.backgroundColor.toLowerCase(), feltDeep, "native splash = --felt-deep");
    r.ok(html.includes('SB.setStyle({ style: "DARK" })'),
      "status-bar text goes light for the dark felt shell (presentation-only shim line)");
    r.ok(/class="boot-wordmark">JarHead Labs</.test(html), "the JarHead Labs branding is kept");
  }

  // --- THERMAL: no new blur / backdrop-filter / standing animations --------
  {
    const styleBlock = html.slice(html.indexOf("THEME / TOKENS"), html.indexOf("</style>", html.indexOf("THEME / TOKENS")));
    // The chunk-6 sweep deleted the last (dead .store-coins) pair — the sheet
    // now carries ZERO backdrop-filter declarations, and none may ever return.
    r.eq((styleBlock.match(/backdrop-filter:/g) || []).length, 0,
      "zero backdrop-filter declarations in the sheet (the dead .store-coins pair is swept; the bans hold)");
    r.ok(!cssRule(html, ".menu-screen::before").includes("blur("),
      "the felt-nap layer is unblurred (the old glow's blur(16px) is gone)");
    r.ok(!cssRule(html, ".menu-screen::before").includes("animation"),
      "…and static — the menus idle with zero standing animations of their own");
  }

  // --- Mechanisms byte-familiar (zero behaviour change) --------------------
  {
    for (const name of ["showMainMenu", "buildMenu", "showDeckSelect", "showZenSelect",
      "renderCollection", "showStats", "renderZenSection", "zenSectionInner", "zenSetDrill",
      "showManual", "showGameMenu", "showOverlay", "showMenuConfirm", "showActionBar",
      "startLossFossils", "maybeShowUnlockCelebration", "showItemUnlockPop", "resetAllProgress"])
      r.ok(src.includes("function " + name + "("), name + " untouched by the restyle");
    const reset = fnBody(src, "showMainMenu");
    r.ok(reset.includes('label: "Reset progress"') && reset.includes("showMenuConfirm"),
      "Reset progress still double-confirms through the shared prompt bar");
    r.ok(fnBody(src, "showMenuConfirm").includes('classList.add("menu-confirm")'),
      "menu confirms still ride the body.menu-confirm z-lift");
  }

  return r.summary();
}
