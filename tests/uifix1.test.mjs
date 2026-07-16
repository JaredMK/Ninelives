// UIFIX1 — iPhone playtest batch: inlined logo (offline app bundle), safe-area
// padding on the fullscreen menus, deck-select corner Back, Start-Run latency
// (pregen debounce skip + instant map first paint), and the map "?" key.
// All presentation / build tooling / scheduling — no tunables — so these are
// structural checks in the smooth1.test.mjs style: loadGame() proves the
// reworked script still evaluates, and source-shape checks pin the invariants
// each fix relies on (no pixel values or tunable copies are pinned).
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
  const r = makeRunner("uifix1.test.mjs");
  const html = fullHtml();
  const src = gameScript(html);

  // The script (with the map-key + startCampaign rework) still evaluates and
  // exposes the engine modules under the stubbed DOM.
  const g = loadGame();
  r.ok(!!(g.GameEngine && g.CampaignState), "game script evaluates with the UIFIX1 wiring in place");

  // --- R1) Logo inlined — no relative icon asset can reach the app bundle ---
  {
    r.ok(!/src="icons\//.test(html), 'index.html has no src="icons/…" reference (offline bundle 404 → broken-image "?")');
    // Both former usages carry the inlined mark: the menu logo and the HUD Same chip.
    r.ok(/class="menu-logo" src="data:image\/svg\+xml,/.test(html), "menu logo is a data-URI inline SVG");
    r.ok(/id="hudSame"[^>]*><img src="data:image\/svg\+xml,/.test(html), "HUD Same chip logo is a data-URI inline SVG");
    // The build script fails loudly if a relative asset src ever returns.
    const build = readFileSync(join(HERE, "..", "app", "scripts", "build-www.mjs"), "utf8");
    r.ok(/src="\(\?!data:\|https\?:/.test(build) && build.includes("throw new Error"),
      "build-www.mjs audits for loose relative src assets and throws");
  }

  // --- R2) Fullscreen menus fold the safe-area insets into their padding ----
  {
    const menuRule = html.match(/\.menu-screen \{[\s\S]*?\n  \}/);
    r.ok(!!menuRule, ".menu-screen rule found");
    const m = menuRule ? menuRule[0] : "";
    r.ok(m.includes("env(safe-area-inset-top") && m.includes("env(safe-area-inset-bottom"),
      ".menu-screen padding folds in the top+bottom safe-area insets (unconditional — env() is 0 on the web)");
    const dsRule = html.match(/#deckSelect \{[\s\S]*?\}/);
    r.ok(!!dsRule && dsRule[0].includes("env(safe-area-inset-top"),
      "#deckSelect padding override keeps the safe-area fold");
  }

  // --- R3) Deck-select Back = circular top-left corner-nav button -----------
  {
    const back = html.match(/<button class="([^"]*)" id="dsBack"[^>]*>/);
    r.ok(!!back, "#dsBack button exists");
    const cls = back ? back[1] : "";
    r.ok(cls.includes("nav-btn"), "#dsBack uses the corner-nav convention (.nav-btn)");
    r.ok(!!back && back[0].includes('aria-label="Back"'), "#dsBack carries an accessible label (icon-only button)");
    r.ok(/\.ds-back-btn \{[^}]*safe-area-inset-left/.test(html), ".ds-back-btn is anchored to the safe-area top-left");
    r.ok(!/class="ds-back"/.test(html), "the old bottom text-pill Back is gone");
    // The click handler survives the markup move (hide + return path intact).
    r.ok(/el\.dsBack\.addEventListener\("click", \(\) => \{ hideDeckSelect\(\); if \(deckSelectReturn\) deckSelectReturn\(\); \}\)/.test(src),
      "#dsBack still routes through hideDeckSelect + deckSelectReturn");
  }

  // --- R4a) Deck-select ENTRY pregen skips the browsing debounce ------------
  {
    const show = fnBody(src, "showDeckSelect");
    r.ok(show.includes("schedulePregen(true)"), "showDeckSelect schedules the entry pregen immediately");
    const sched = fnBody(src, "schedulePregen");
    r.ok(/if \(immediate\) fire\(\);/.test(sched), "schedulePregen(immediate) bypasses the debounce timer");
    r.ok(/setTimeout\(fire, 350\)/.test(sched), "browsing-churn calls keep the settle debounce");
    r.ok(sched.includes("requestIdleCallback"), "generation still lands via requestIdleCallback (idle time)");
  }

  // --- R4b) Start tap paints the map shell BEFORE the heavy reset+render ----
  {
    const start = fnBody(src, "startCampaign");
    const showIdx = start.indexOf('el.mapOverlay.classList.remove("hidden")');
    const heavyIdx = start.indexOf("campaign.reset()");
    r.ok(showIdx !== -1 && heavyIdx !== -1 && showIdx < heavyIdx,
      "startCampaign shows the map overlay before campaign.reset (instant tap response)");
    r.ok(start.includes("requestAnimationFrame"),
      "the heavy half (reset + node render) is deferred past the first paint");
    r.ok(start.indexOf("requestAnimationFrame") < heavyIdx, "…and campaign.reset sits inside the deferred block");
    r.ok(start.includes("showProgressionMap(startRun)"), "the deferred block still routes through showProgressionMap(startRun)");
  }

  // --- R5) Map key: "?" nav button + legend built from the LIVE node markup --
  {
    r.ok(/<button class="nav-btn map-key-btn" id="mapKeyBtn"/.test(html), "map key button exists with .nav-btn styling");
    r.ok(/aria-label="Map key"/.test(html), "map key button carries an accessible label");
    r.ok(/id="mapKeyPanel"/.test(html), "map key legend panel exists");
    r.ok(/\.map-key-btn \{[^}]*safe-area-inset-right/.test(html), "the key is anchored to the safe-area top-right");
    // It now reads as a MAP control: its top drops below the .hud bar by riding
    // the MEASURED shell height (var(--shell-h)), not the viewport-top nav line.
    r.ok(/\.map-key-btn \{[^}]*top:\s*calc\(var\(--shell-h/.test(html), "the key drops below the HUD (top rides the measured shell height)");
    r.ok(/\.map-key-panel \{[^}]*top:\s*calc\(var\(--shell-h/.test(html), "the legend panel follows the key down below the HUD");
    r.ok(/body\.on-map \.map-key-btn/.test(html), "the key is shown on the MAP only (gated on body.on-map)");
    const key = fnBody(src, "renderMapKey");
    r.ok(key.length > 0, "renderMapKey found");
    // Every row reuses the live node-markup functions — the key can't drift.
    for (const fn of ["mapDealCluster(deal, false)", "mapDealCluster(boss, true)", "mapShopStall()", "mapPackStack(pack)", "nodeCardHtml(card)", "mn-myst", 'mapNodeInner({ type: "home" })']) {
      r.ok(key.includes(fn), "legend row built from live markup: " + fn);
    }
    r.eq((key.match(/mapKeyRow\(/g) || []).length, 7, "legend has exactly 7 entries (pass dots omitted)");
    // Open/close wiring: toggle on the button, × close, tap-outside close.
    r.ok(/el\.mapKeyBtn\.addEventListener\("click"/.test(src), "key button toggles the legend");
    r.ok(/\.closest\("\.mk-close"\)/.test(src), "the legend's × closes it");
    r.ok(/document\.addEventListener\("pointerdown",[\s\S]{0,400}?closeMapKey\(\);\n    \}, true\)/.test(src),
      "a capture-phase outside tap closes the legend (never a blocking mode)");
    // Leaving the map (both exits) drops the panel.
    r.ok(fnBody(src, "hideProgressionMap").includes("closeMapKey()"), "hideProgressionMap closes the key");
    r.ok(fnBody(src, "showStore").includes("closeMapKey()"), "the map→store path closes the key too");
  }

  return r.summary();
}
