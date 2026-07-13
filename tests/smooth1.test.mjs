// SMOOTH1 — UI-pause + tap-burst fixes. The changes are UI-side (the engine
// modules are untouched), so these checks are structural: loadGame() proves
// the reworked script still evaluates under the stubbed DOM, and the source
// checks (same style as terminology.test.mjs) pin the INVARIANTS each fix
// relies on — the guard's wiring, the read/write batching shapes, and the
// removed hidden-map render — so a refactor can't silently drop them.
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

export function run() {
  const r = makeRunner("smooth1.test.mjs");
  const src = gameScript();

  // The script (with the new document/window listeners) still evaluates and
  // exposes the engine modules under the stubbed DOM.
  const g = loadGame();
  r.ok(!!(g.GameEngine && g.CampaignState), "game script evaluates with the SMOOTH1 wiring in place");

  // --- 1) Global stale-tap guard --------------------------------------------
  {
    const m = src.match(/const STALE_TAP_MS = (\d+);/);
    r.ok(!!m, "STALE_TAP_MS constant exists");
    const ms = m ? Number(m[1]) : 0;
    r.ok(ms >= 200 && ms <= 600,
      "stale-tap threshold is in the human-plausible band (200-600ms; currently " + ms + ")");
    // Capture-phase click filter on document, keyed on the event's queue delay.
    const guard = src.match(/document\.addEventListener\("click",[\s\S]{0,900}?\}, true\);/);
    r.ok(!!guard, "a capture-phase document click listener is registered");
    const gsrc = guard ? guard[0] : "";
    r.ok(gsrc.includes("performance.now() - e.timeStamp"),
      "guard measures the click's queue delay (now − timeStamp)");
    r.ok(gsrc.includes("STALE_TAP_MS"), "guard compares against STALE_TAP_MS");
    r.ok(gsrc.includes("e.stopImmediatePropagation()") && gsrc.includes("e.preventDefault()"),
      "a stale click is fully swallowed (stopImmediatePropagation + preventDefault, so sibling document capture listeners can't act on it either)");
    r.ok(gsrc.includes("console.log"), "a swallowed tap logs one observability line");
    // Clicks ONLY: the guard must never touch pointer events (drags/holds/swipes).
    r.ok(!/document\.addEventListener\("pointer(down|up|move)",[\s\S]{0,400}?stopPropagation/.test(src),
      "no document-level pointer-event swallowing (gestures untouched)");
  }

  // --- 2) Store open keeps the covered map's last paint ---------------------
  {
    const fin = fnBody(src, "finishResolveNode");
    r.ok(fin.length > 0, "finishResolveNode found");
    const storeBranch = fin.slice(fin.indexOf('node.type === "store"'), fin.indexOf("showStore()"));
    r.ok(storeBranch.length > 0 && !storeBranch.includes("renderProgressionMap"),
      "the store node branch opens the store WITHOUT re-rendering the hidden map");
    r.ok(storeBranch.includes("mapArrive = false"),
      "the one-shot arrival pop is consumed on the store branch (no stray pop after store close)");
    // The map still re-renders where it IS visible: the draft-node branches.
    r.ok((fin.match(/renderProgressionMap\(\)/g) || []).length >= 2,
      "visible-map branches (pickup/pack) still re-render the map");
  }

  // --- 3) Deal-start layout reads are batched/cached -------------------------
  {
    // stableViewportH serves a cached px and only measures the probe when the
    // cache is empty; a real viewport change resets it.
    const svh = fnBody(src, "stableViewportH");
    r.ok(svh.includes("svhCache"), "stableViewportH is cache-backed");
    r.ok(/window\.addEventListener\("resize", \(\) => \{ svhCache = 0; fitEnvCache = null; \}\)/.test(src),
      "resize resets the svh + fit-env caches (re-measured fresh)");
    r.ok(/window\.addEventListener\("orientationchange", \(\) => \{ svhCache = 0; fitEnvCache = null; \}\)/.test(src),
      "rotation resets the svh + fit-env caches");
    // fitBoard: style-constant reads come from fitEnvCache; the write pass is
    // gated on a change vs. the last APPLIED values (fitLast).
    const fit = fnBody(src, "fitBoard");
    r.ok(fit.includes("fitEnvCache"), "fitBoard reads its style constants from the cache");
    r.ok(/if \(!fitLast \|\| fitLast\.w !== w \|\| fitLast\.h !== h \|\| fitLast\.vGap !== vGap\)/.test(fit),
      "fitBoard skips the CSS-var write pass when the computed sizes are unchanged");
    r.ok(fit.indexOf("--pile-w-fit") > fit.indexOf("fitLast.w !== w"),
      "the --pile-w-fit write sits INSIDE the changed-gate");
    // The deal cascade measures every landing rect in ONE batched pass (a
    // single gBCR site, inside the all-piles forEach), not per flight.
    const cas = fnBody(src, "playDealCascade");
    r.eq((cas.match(/getBoundingClientRect/g) || []).length, 1,
      "playDealCascade has exactly one rect-measuring site");
    r.ok(/piles\.forEach\(q => \{ q\.to = q\.cardEl\.getBoundingClientRect\(\); \}\)/.test(cas),
      "…and it measures ALL piles in one batch at the first live step");
  }

  // --- 4) Map-show resume sweep is skip-when-unchanged ----------------------
  {
    const idle = fnBody(src, "setMapAnimsIdle");
    r.ok(idle.includes("if (!mapAnimsPaused) return;"),
      "setMapAnimsIdle(false) skips the getAnimations sweep when nothing was paused");
    r.ok(idle.includes("mapAnimsPaused = true"),
      "the pause sweep records that it ran (arming the resume)");
  }

  return r.summary();
}
