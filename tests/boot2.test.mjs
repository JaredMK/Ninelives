// BOOT2 — JarHead Labs boot splash + pre-init flash removal. All presentation
// / boot wiring / native-config — no tunables — so these are structural checks
// in the uifix1.test.mjs style: loadGame() proves the reworked script still
// evaluates, and source-shape checks pin the invariants the splash relies on.
// Timing knobs are READ from the source and asserted against sane bands (and
// against each other), never pinned to exact values.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { inflateSync } from "node:zlib";
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
/** The NativeApp shim <script> block (head; feature-detected). */
function shimScript(html) {
  const blocks = html.match(/<script>([\s\S]*?)<\/script>/g) || [];
  return blocks
    .map((b) => b.replace(/^<script>/, "").replace(/<\/script>$/, ""))
    .find((c) => c.includes("const NativeApp")) || "";
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
  const r = makeRunner("boot2.test.mjs");
  const html = fullHtml();
  const src = gameScript(html);
  const shim = shimScript(html);

  // The script (with the splash dismissal wiring in the boot callback) still
  // evaluates and exposes the engine modules under the stubbed DOM.
  const g = loadGame();
  r.ok(!!(g.GameEngine && g.CampaignState), "game script evaluates with the BOOT2 wiring in place");

  // "<body>" appears in prose inside CSS comments too — anchor on the real
  // tag, which is the only occurrence at a line start.
  const bodyAt = html.indexOf("\n<body>") + 1;

  // --- R1) #bootSplash: first in <body>, inline-only, critical CSS in head ---
  {
    const body = html.slice(bodyAt);
    const firstEl = body.replace(/<!--[\s\S]*?-->/g, "").match(/<(?!body)[a-z][^>]*>/i);
    r.ok(!!firstEl && firstEl[0].includes('id="bootSplash"'), "#bootSplash is the FIRST element inside <body> (first painted frame is the splash)");
    const splash = body.match(/<div id="bootSplash"[\s\S]*?<\/div>\s*<\/div>/);
    r.ok(!!splash, "#bootSplash markup found");
    const s = splash ? splash[0] : "";
    r.ok(/<svg [^>]*viewBox/.test(s), "the JarHead mark is an inline <svg>");
    r.ok(!/\bsrc=/.test(s), "splash has NO src= references (inline-only — offline bundle + first-parse paint)");
    r.ok(!s.includes('<rect width="1024"'), "the logo's background rect is dropped (container paints the cream)");
    // The mark keeps the logo's parts: jar lid+body, face, liquid, bubbles, floaters.
    for (const part of ["bootJarInner", "#20b5c6", "#7b4fc9", "#f5941d", "ellipse"]) {
      r.ok(s.includes(part), "splash mark keeps logo part: " + part);
    }
    r.ok(/class="boot-wordmark">JarHead Labs</.test(s), 'wordmark "JarHead Labs" present as text');
    // Critical CSS: an inline head <style> BEFORE the heavy game stylesheet.
    const head = html.slice(0, bodyAt);
    const cssAt = head.indexOf("#bootSplash {");
    const heavyAt = head.indexOf("THEME / TOKENS");
    r.ok(cssAt !== -1 && heavyAt !== -1 && cssAt < heavyAt, "splash CSS sits in <head> before the heavy game CSS");
    const css = head.slice(cssAt, head.indexOf("</style>", cssAt));
    r.ok(css.includes("position: fixed") && css.includes("inset: 0"), "splash is fixed inset-0 (covers safe areas with viewport-fit=cover)");
    r.ok(css.includes("background: #f6f3ec"), "splash background is the JarHead cream #f6f3ec");
    r.ok(css.includes("color: #20313a"), "wordmark ink is the logo ink #20313a");
    r.ok(/-apple-system|system-ui/.test(css), "wordmark uses a system font stack (no web-font wait)");
    const z = css.match(/z-index:\s*(\d+)/);
    r.ok(!!z && Number(z[1]) > 2000, "splash z-index sits above every game overlay (max 2000 in the main CSS)");
    r.ok(!/spinner|animation/.test(css), "no spinner (flat brand hold only)");
  }

  // --- R2/R3) Dismissal: min-hold + fade + DOM removal, tied to init ---------
  {
    const hold = src.match(/BOOT_SPLASH_HOLD_MS = (\d+)/);
    const fade = src.match(/BOOT_SPLASH_FADE_MS = (\d+)/);
    r.ok(!!hold && Number(hold[1]) >= 500 && Number(hold[1]) <= 2000,
      "minimum hold is a sane brand beat (500–2000ms band, not pinned)");
    r.ok(!!fade && Number(fade[1]) >= 200 && Number(fade[1]) <= 800,
      "fade duration is a sane transition (200–800ms band, not pinned)");
    // The JS removal timer and the CSS opacity transition are the SAME number.
    const cssFade = html.match(/#bootSplash \{[\s\S]*?transition: opacity (\d+)ms/);
    r.ok(!!cssFade && !!fade && cssFade[1] === fade[1],
      "CSS transition duration matches BOOT_SPLASH_FADE_MS (fade and removal can't drift)");
    const d = fnBody(src, "dismissBootSplash");
    r.ok(d.length > 0, "dismissBootSplash found");
    r.ok(d.includes("__bootSplashAt"), "hold counts from the splash first-paint stamp (__bootSplashAt)");
    r.ok(/Math\.max\(0, BOOT_SPLASH_HOLD_MS/.test(d), "slow init (> hold) fades immediately (wait clamps to 0)");
    r.ok(/classList\.add\("boot-fade"\)/.test(d), "fade is the CSS class (opacity transition + pointer-events:none)");
    r.ok(/splash\.remove\(\)/.test(d), "splash is REMOVED from the DOM after the fade (never lingers over input)");
    r.ok(/#bootSplash\.boot-fade \{[^}]*pointer-events: none/.test(html),
      "fading splash stops intercepting input immediately");
    // The stamp: a head rAF (first rendered frame), BEFORE the font links so a
    // slow fonts CDN can never stylesheet-block it into stretching the hold.
    const head = html.slice(0, bodyAt);
    const stampAt = head.indexOf("window.__bootSplashAt = performance.now()");
    const fontsAt = head.indexOf("fonts.googleapis.com/css2");
    r.ok(stampAt !== -1 && /requestAnimationFrame\(function \(\) \{ window\.__bootSplashAt/.test(head),
      "first-paint stamp is a head rAF (stamps the first rendered frame)");
    r.ok(fontsAt !== -1 && stampAt < fontsAt, "stamp script sits before the font <link>s (can't be stylesheet-blocked)");
    // R3: wired into the boot callback around init — try/FINALLY (error still
    // propagates uncaught to the console; splash comes down either way).
    r.ok(/NativeApp\.boot\(\(\) => \{[\s\S]*?try \{ UIRenderer\.init\(\); \}\s*finally \{ dismissBootSplash\(\); \}/.test(src),
      "dismissal is wired into the boot callback via try/finally around UIRenderer.init (no blind timer, no swallowed error)");
    r.ok(!/catch\s*\(\s*\w*\s*\)\s*\{\s*\}\s*finally \{ dismissBootSplash/.test(src),
      "no empty catch around init (a throw reaches the console)");
  }

  // --- R4) Native handoff: config + shim hide() gated on native --------------
  {
    const cfg = JSON.parse(readFileSync(join(HERE, "..", "app", "capacitor.config.json"), "utf8"));
    r.eq(cfg.plugins.SplashScreen.launchAutoHide, false, "capacitor.config.json: launchAutoHide is false (shim owns the hide)");
    r.eq(cfg.plugins.SplashScreen.backgroundColor.toLowerCase(), "#f6f3ec", "capacitor.config.json: native splash backdrop is #f6f3ec");
    r.ok(!("launchShowDuration" in cfg.plugins.SplashScreen), "launchShowDuration dropped (meaningless with launchAutoHide:false)");
    const boot = fnBody(shim, "boot");
    r.ok(boot.length > 0, "NativeApp.boot found in the head shim");
    const gateAt = boot.indexOf("if (!native) { start(); return; }");
    const hideAt = boot.indexOf('plugin("SplashScreen")');
    r.ok(gateAt !== -1 && hideAt !== -1 && gateAt < hideAt,
      "SplashScreen.hide sits AFTER the web early-return (native-gated; inert on Pages)");
    r.ok(/requestAnimationFrame\(\(\) => requestAnimationFrame\(\(\) => \{ SS\.hide\(\)/.test(boot),
      "native splash hides only after the HTML splash has painted (double rAF = one committed frame)");
  }

  // --- R5) The three splash PNGs: 2732×2732 flat solid #f6f3ec ---------------
  {
    const dir = join(HERE, "..", "app", "ios", "App", "App", "Assets.xcassets", "Splash.imageset");
    for (const name of ["splash-2732x2732.png", "splash-2732x2732-1.png", "splash-2732x2732-2.png"]) {
      const b = readFileSync(join(dir, name));
      r.ok(b.readUInt32BE(0) === 0x89504e47, name + ": PNG signature");
      r.ok(b.readUInt32BE(16) === 2732 && b.readUInt32BE(20) === 2732, name + ": 2732x2732");
      // Decode the first scanline (filter 0 + RGB) and check the corner pixel.
      const idatAt = b.indexOf(Buffer.from("IDAT", "ascii"));
      const idatLen = b.readUInt32BE(idatAt - 4);
      const raw = inflateSync(b.subarray(idatAt + 4, idatAt + 4 + idatLen));
      r.ok(raw[0] === 0 && raw[1] === 0xf6 && raw[2] === 0xf3 && raw[3] === 0xec,
        name + ": corner pixel decodes to #f6f3ec (flat solid, no art)");
    }
  }

  // --- R7) build-www audits: the splash adds no loose/external references ----
  {
    // Mirror the build script's loose-asset audit against the live html…
    // (whitelist must match build-www.mjs exactly: the three data files + fonts/)
    r.ok(!/src="(?!data:|https?:|items\.js|difficulty\.js|tutorial\.js|fonts\/)[^"]+"/.test(
      html.replace(/<script async src="https:\/\/www\.googletagmanager[^>]*><\/script>/, "")),
      "no loose relative src anywhere (build-www loose-asset audit shape)");
    // …and prove its must-patch anchors survived the head insert.
    r.ok(/<script async src="https:\/\/www\.googletagmanager\.com\/gtag\/js/.test(html), "gtag loader anchor intact for build-www");
    r.ok(/<link rel="preconnect" href="https:\/\/fonts\.googleapis\.com" \/>/.test(html), "fonts preconnect anchor intact for build-www");
  }

  return r.summary();
}
