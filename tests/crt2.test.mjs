// CRT2 — CRT CASINO chunk 2: the progression map restyle (strictly aesthetic).
// Structural checks in the uifix1/smooth1 style: loadGame() proves the script
// still evaluates, and source-shape checks pin the invariants the restyle
// relies on — the §5 dashed web-line spec, the palette-token discipline, the
// baked-tile (no gradients-as-texture / no per-node filter) rules, and the
// unchanged spotlight/pulse MECHANISMS the perf work depends on. No tunables
// or pixel geometry are pinned beyond what older suites already pin.
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
  const r = makeRunner("crt2.test.mjs");
  const html = fullHtml();
  const src = gameScript(html);

  // The game still evaluates with the map restyle in place.
  const g = loadGame();
  r.ok(!!(g.GameEngine && g.CampaignState && g.RunMap), "game script evaluates with the CRT map restyle");

  // --- Map plane: one flat felt well, baked tiles only ----------------------
  {
    const map = cssRule(html, ".overlay.map");
    r.ok(map.includes("background: var(--felt-deep)"), ".overlay.map is the flat deep-felt screen well");
    const depth = cssRule(html, ".map-depth");
    r.ok(!depth.includes("gradient"), ".map-depth carries no atmosphere gradients (flattened to the felt)");
    const bg = cssRule(html, ".map-bg");
    r.ok(bg.includes("data:image/png") && bg.includes("data:image/gif"),
      ".map-bg is retiled with baked data-URI tiles (dither + speck)");
    r.ok(bg.includes("image-rendering: pixelated"), ".map-bg tiles render on the pixel grid");
    r.ok(!bg.includes("feTurbulence") && !bg.includes("--lost-paths") && !bg.includes("radial-gradient"),
      ".map-bg has no turbulence-filter grain / tangle texture / gradient dots (§10)");
    r.ok(bg.includes("translateY(var(--parbg") && bg.includes("will-change: transform"),
      "the one-plane parallax mechanism is untouched (compositor-only translate)");
    // Both tile periods must divide the JS 480px scroll wrap or the seam shows.
    r.ok(bg.includes("/ 96px 96px") && bg.includes("/ 4px 4px") && src.includes("% 480"),
      "tile periods (96px / 4px) divide the 480px parallax wrap");
  }

  // --- §5 web lines: dashed pixel edges, lit path = phosphor ----------------
  {
    const edge = cssRule(html, ".map-edge");
    r.ok(edge.includes("stroke-dasharray") && edge.includes("stroke: var(--net)")
      && edge.includes("stroke-linecap: butt"),
      ".map-edge is a dashed pixel line in the low-contrast felt tone (--net)");
    const done = cssRule(html, ".map-edge.done");
    r.ok(done.includes("stroke: var(--phosphor)"), "the travelled path is lit phosphor");
    r.ok(!done.includes("filter") && !done.includes("drop-shadow"),
      "the lit path carries no glow filter (§5 .webline.lit: box-shadow none)");
    // Cascade: .active must come BEFORE .done so a travelled edge keeps phosphor
    // even while it also leaves the current node.
    const ai = html.indexOf("\n  .map-edge.active {"), di = html.indexOf("\n  .map-edge.done {");
    r.ok(ai !== -1 && di !== -1 && ai < di, ".map-edge.active is declared before .done (done wins both)");
    r.ok(cssRule(html, ".map-dot.done").includes("var(--phosphor)"), "signal dots on the lit path go phosphor");
    // Signal dots are pixel squares now (rects, not circles) — but fossilSvg's
    // circles are a different component and stay.
    const rpm = fnBody(src, "renderProgressionMap");
    r.ok(rpm.includes("<rect") && !rpm.includes("<circle"),
      "edgeSvg draws square pixel signal dots (no circles in the map render)");
  }

  // --- Node plaques: palette + hard shadows + square corners ----------------
  {
    const piles = cssRule(html, ".pm-node .mn-piles");
    r.ok(piles.includes("var(--gold)") && piles.includes("var(--px) solid var(--ink)")
      && piles.includes("2px 2px 0 0 var(--shadow)") && piles.includes("border-radius: 0"),
      "the deal reward chip is a gold pixel plaque (ink border, hard shadow, square)");
    const badge = cssRule(html, ".mn-pack .mpk-badge");
    r.ok(badge.includes("var(--gold)") && badge.includes("border-radius: 0"),
      "the pack +N badge shares the gold plaque idiom");
    // Pack card backs are OPTICAL DITHERS (baked tiles), never flat intermediates.
    r.ok(cssRule(html, ".mn-pack .mpk-card").includes("data:image/gif")
      && !cssRule(html, ".mn-pack .mpk-card").includes("linear-gradient"),
      "pack card backs use baked dither tiles (no gradient skins)");
    for (const deck of ["mamma", "smith", "lammy"])
      r.ok(cssRule(html, ".mdeck-" + deck + " .mn-pack .mpk-card").includes("data:image/gif"),
        "the " + deck + " pack skin is a dither tile too");
    // Per-node drop-shadow filters are gone (paint diet on a 200+ node surface).
    for (const sel of [".mn-synapse", ".mn-shop", ".mn-pack", ".mn-pack2", ".node-card"])
      r.ok(!cssRule(html, sel).includes("filter"), sel + " carries no per-node filter");
    // Boss: gold pixel crown, no radial glow ring (glow is phosphor-only).
    const crown = cssRule(html, ".t-boss .mn-synapse.big::before");
    r.ok(crown.includes("data:image/svg") && !crown.includes("radial-gradient"),
      "the boss crown is a baked SVG tile (the warm radial ring is retired)");
    // Mystery: pinned selectors kept (mystery-ui) and retinted to the palette.
    r.ok(cssRule(html, ".mn-myst").includes("var(--ink)")
      && cssRule(html, ".mn-myst").includes("var(--gold)"),
      "the mystery ? is the ink-faced gold-framed card back");
    r.ok(cssRule(html, ".mn-myst.open").includes("var(--phosphor)"),
      "an open mystery lights phosphor (the one sanctioned glow)");
  }

  // --- States: distinct at a glance, mechanisms untouched -------------------
  {
    const legal = cssRule(html, ".pm-node.s-legal::after");
    r.ok(legal.includes("var(--gold)") && legal.includes("animation: pmPulseFade"),
      "reachable = gold ring on the same compositor crossfade (pause-list contract)");
    r.ok(!/0 0 \d+px/.test(legal.replace(/0 0 0 /g, "")),
      "the legal ring has no blurred shadow component (solid ring only)");
    const here = cssRule(html, ".pm-node.s-here::after");
    r.ok(here.includes("var(--phosphor)") && here.includes("var(--glow)")
      && here.includes("animation: pmPulseFade"),
      "current = phosphor ring + THE glow, same crossfade mechanism");
    r.ok(cssRule(html, ".pm-node.s-done::after").includes("var(--phosphor)"),
      "cleared ✓ chip reads phosphor");
    // The old per-suit here-ring hues are gone with the rest of the rose palette.
    r.ok(!html.includes("#c8506e") && !html.includes("#F79ABC"),
      "the rose map palette (suit tints, trail pink) is fully purged");
  }

  // --- Spotlight: same 2-layer mechanism, ink dim + neutral lift ------------
  {
    r.ok(cssRule(html, ".map-dim").includes("rgba(16, 16, 14"),
      "the map dim is ink-based");
    const spot = cssRule(html, ".map-spot::before");
    r.ok(spot.includes("rgba(236, 228, 207") && !spot.includes("255, 240, 200"),
      "the spot is a neutral cream lift (the warm glow is gone)");
    // Mechanism pins: the spotlight still rides the avatar's coordinates and
    // travel tween (no new layers, no reads).
    r.ok(fnBody(src, "positionAvatarAt").includes("mapSpotEl.style.left"),
      "positionAvatarAt still seats the spot at the avatar's map coords");
    r.ok(fnBody(src, "avatarTravelTo").includes("mapSpotEl.animate(glide"),
      "the spot still rides the identical travel tween");
  }

  // --- Avatar frame + map chrome --------------------------------------------
  {
    const body = cssRule(html, ".av-body");
    r.ok(body.includes("var(--spr-ov), var(--spr)")
      && body.includes("image-rendering: pixelated")
      && body.includes("border-radius: 0"),
      "the avatar body is the chunk-5 pixel sprite canvas (overlay + frame layers, crisp)");
    r.ok(body.includes("animation: avBob"), "the idle bob (pause-list member) survives");
    r.ok(cssRule(html, ".av-badge").includes("border-radius: 0"), "the deck-count badge is a square chip");
    r.ok(cssRule(html, ".map-store-btn").includes("border-radius: 0")
      && cssRule(html, ".map-store-btn:active").includes("translate(2px, 2px)"),
      "the Store button is a §4 pixel button (press sinks one step)");
    const key = cssRule(html, ".map-key-panel");
    r.ok(key.includes("border-radius: 0") && key.includes("4px 4px 0 0 var(--shadow)"),
      "the map key panel is a square hard-shadow panel");
    r.ok(cssRule(html, ".map-key-btn").includes("border-radius: 0"), "the map ? button squares off");
  }

  // --- Fossil detail / mystery modal shell ----------------------------------
  {
    r.ok(cssRule(html, ".fossil-detail").includes("rgba(16, 16, 14"),
      "the fossil/mystery backdrop scrim is ink-based");
    const panel = cssRule(html, ".fd-panel");
    r.ok(panel.includes("var(--felt-mid)") && panel.includes("border-radius: 0")
      && panel.includes("4px 4px 0 0 var(--shadow)"),
      ".fd-panel is the standard pixel panel");
    r.ok(cssRule(html, ".fd-title").includes("var(--font-display)"),
      "the popup title moves to the display face");
    const go = cssRule(html, ".mystery-event .me-go");
    r.ok(go.includes("var(--phosphor)") && go.includes("var(--ink)") && go.includes("border-radius: 0"),
      "mystery Continue is the phosphor CTA");
    // One-shot mea keyframes may flash, but must REST clean: no persistent
    // gold glow / red filter once fill:both lands.
    const joker = html.match(/@keyframes meaJokerIn \{[\s\S]*?\n  \}/);
    r.ok(!!joker && !/100%[^}]*0 0 \d+px rgba\(224/.test(joker[0]),
      "meaJokerIn rests without the gold glow");
    const ambush = html.match(/@keyframes meaAmbushShake \{[\s\S]*?\n  \}/);
    r.ok(!!ambush && /100%[^}]*filter: none/.test(ambush[0]),
      "meaAmbushShake rests filter-free");
  }

  // --- Fog veil + egg -------------------------------------------------------
  {
    const veil = cssRule(html, ".map-lockveil");
    r.ok(!veil.includes("linear-gradient") && veil.includes("border-bottom: var(--px) solid var(--ink)"),
      "the lock veil is a solid fog with a hard ink line (no gradient fade)");
    r.ok(cssRule(html, ".map-lockveil::after").includes("data:image/gif"),
      "…dissolving through a baked dither strip");
    r.ok(!veil.includes("animation") && !crownHasAnimation(html),
      "no new continuous animations rode in with the retile");
  }

  // --- No behavior drift: the render/travel/scroll plumbing is byte-familiar -
  {
    for (const name of ["routeEdgeControl", "buildMapLayout", "cullMapNodes", "resolveMapNode"])
      r.ok(src.includes("function " + name + "("), name + " untouched by the restyle");
    r.ok(src.includes('el.mapBg.style.setProperty("--parbg"'),
      "the scroll-driven parallax write is unchanged");
  }

  return r.summary();
}

function crownHasAnimation(html) {
  const at = html.indexOf("\n  .t-boss .mn-synapse.big::before {");
  if (at === -1) return false;
  const close = html.indexOf("}", at);
  return html.slice(at, close).includes("animation");
}
