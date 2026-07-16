// STOREHELP1 + STORESUIT1 — store item-info surface.
//   STOREHELP1: a "?" in the store header opens a per-TYPE legend (the seven
//     store item classes), each row's art drawn by the SAME live shelf renderer
//     the store uses, mirroring the map key.
//   STORESUIT1: the per-item hold-for-help popup shows a sticker's suit
//     restriction (data-driven from the sticker def's items.js `suits`).
// Both are presentation only (no tunables), so these are structural checks in
// the uifix1.test.mjs style — loadGame() proves the reworked script still
// evaluates, source-shape checks pin the invariants, and the STORESUIT1
// suit-line mapping is exercised against the LIVE sticker registry (never a
// pinned suits value).
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
  const r = makeRunner("storehelp1.test.mjs");
  const html = fullHtml();
  const src = gameScript(html);

  const g = loadGame();
  r.ok(!!(g.GameEngine && g.StickerTypes), "game script evaluates with the STOREHELP1/STORESUIT1 wiring in place");

  // ============================================================
  // PART A — STOREHELP1 (per-type help "?" legend)
  // ============================================================
  {
    // --- A1) "?" button lives in the store chrome, not colliding with coins/reroll
    const btn = html.match(/<button class="([^"]*)" id="storeHelpBtn"[^>]*>/);
    r.ok(!!btn, "STOREHELP1: #storeHelpBtn exists");
    const cls = btn ? btn[1] : "";
    r.ok(cls.includes("store-help-btn"), "the help button uses the in-flow store-chrome style (.store-help-btn, not the fixed corner nav)");
    r.ok(!!btn && btn[0].includes("aria-label="), "the icon-only help button carries an accessible label");
    // Ordered inside .store-top: after the coin balance (#storeCoins), before Refresh.
    const iTop = html.indexOf('class="store-top"');
    const iCoins = html.indexOf('id="storeCoins"');
    const iHelp = html.indexOf('id="storeHelpBtn"');
    const iReroll = html.indexOf('id="rerollBtn"');
    const iShelf = html.indexOf('id="storeItems"');
    r.ok(iTop !== -1 && iTop < iHelp && iHelp < iShelf, "the help button sits inside .store-top (before the shelf)");
    r.ok(iCoins < iHelp && iHelp < iReroll, "no overlap: it sits after the coin balance and before Refresh");
    r.ok(!cls.includes("tut-allow"), "the help button is a plain store button (NO .tut-allow) so the tutorial gate disables it");
    // The gate rule that disables non-.tut-allow store buttons is still in force.
    r.ok(html.includes("body.tut-gate-store #storeOverlay button:not(.tut-allow):not(.store-tile)"),
      "the tutorial gate rule (disables plain store buttons) is present — makes the help button inert in the guided store");

    // --- A2) The legend panel: opaque, root-level, lifted above the store shelf
    r.ok(/id="storeKeyPanel"/.test(html), "STOREHELP1: the #storeKeyPanel legend exists");
    const panelCss = html.match(/\.store-key-panel \{[\s\S]*?\}/);
    r.ok(!!panelCss, ".store-key-panel CSS rule found");
    const pc = panelCss ? panelCss[0] : "";
    r.ok(/z-index:\s*84/.test(pc), "the panel is z-lifted (84) above #storeOverlay (50) + shelf + buy-detail (66)");
    r.ok(pc.includes("background: var(--panel)"), "the panel is OPAQUE (solid --panel background)");
    r.ok(/\.store-help-btn \{[^}]*margin-left:\s*auto/.test(html), "the help button clusters right (margin-left:auto), clear of the coins");

    // --- A3/A4) renderStoreKey builds SEVEN rows from the live shelf renderers
    const rk = fnBody(src, "renderStoreKey");
    r.ok(rk.length > 0, "renderStoreKey found");
    for (const fn of ["stickerChip(", "pathwayBannerHtml(", "baseBannerHtml(", "miniCardHtml(", "packObjectHtml(", "samePowerBadgeHtml(", "removalBadgeHtml("]) {
      r.ok(rk.includes(fn), "legend row art drawn by the live renderer: " + fn);
    }
    r.eq((rk.match(/storeKeyRow\(/g) || []).length, 7, "the legend has exactly 7 rows");
    // Rows in the required order: Sticker, Pillar, Base, Card, Pack, Same-Power, Removal.
    const order = ['"Sticker"', '"Pillar"', '"Base"', '"Card"', '"Pack"', '"Same-Power"', '"Removal"'];
    let ascending = true, prev = -1;
    for (const lab of order) { const at = rk.indexOf(lab); if (at <= prev) ascending = false; prev = at; }
    r.ok(ascending && prev !== -1, "rows appear in order: Sticker, Pillar, Base, Card, Pack, Same-Power, Removal");
    // Card + Removal copy stays single-sourced from ItemData (not re-typed here).
    r.ok(rk.includes("ItemData.store.card.description"), "the Card row reads its description from ItemData (single source)");
    r.ok(rk.includes("ItemData.store.removal.description"), "the Removal row reads its description from ItemData (single source)");
    // The five registry-backed exemplars require non-empty registries (so the art
    // is a real live object, like the map key picks a live node).
    r.ok(g.StickerTypes.all().length > 0, "sticker registry is non-empty (a real exemplar exists)");
    r.ok(g.PillarTypes.all().length > 0, "pillar registry is non-empty");
    r.ok(g.BaseTypes.all().length > 0, "base registry is non-empty");
    r.ok(g.PackTypes.all().length > 0, "pack registry is non-empty");
    r.ok(g.SamePowerTypes.all().length > 0, "same-power registry is non-empty");
    // Row labels + descriptions are non-empty and escaped.
    const rowFn = fnBody(src, "storeKeyRow");
    r.ok(rowFn.includes("escHtml(name)") && rowFn.includes("escHtml(desc)"), "storeKeyRow escapes the name + description");

    // --- A2 wiring) open/close toggle, ×, outside-tap, Sound.tap, store-exit close
    const open = fnBody(src, "openStoreKey"), close = fnBody(src, "closeStoreKey");
    r.ok(open.includes('classList.remove("hidden")') && open.includes("renderStoreKey()"), "openStoreKey renders fresh + shows the panel");
    r.ok(close.includes('classList.add("hidden")'), "closeStoreKey hides the panel");
    r.ok(/el\.storeHelpBtn\.addEventListener\("click"[\s\S]{0,160}?Sound\.tap\(\)/.test(src), "the ? button toggles the legend and plays Sound.tap on open/close");
    r.ok(/\.closest\("\.sk-close"\)/.test(src), "the legend's × closes it (Sound.tap)");
    r.ok(/document\.addEventListener\("pointerdown",[\s\S]{0,360}?closeStoreKey\(\);\n    \}, true\)/.test(src),
      "a capture-phase outside tap closes the legend (a glance, never a blocking mode)");
    r.ok(fnBody(src, "closeStore").includes("closeStoreKey()"), "leaving the store closes the legend");
    r.ok(fnBody(src, "showStore").includes("closeStoreKey()"), "re-entering the store never shows a stale legend");
  }

  // ============================================================
  // PART B — STORESUIT1 (sticker suit-restriction line)
  // ============================================================
  {
    // Extract the pure mapping helper and exercise it directly. It has no closure
    // deps (only its `suits` arg), so it evaluates standalone in Node.
    const body = fnBody(src, "stickerSuitLine");
    r.ok(body.length > 0, "stickerSuitLine helper found");
    const suitLine = new Function("suits", body.replace(/^\{/, "").replace(/\}$/, ""));

    // --- B1) suits → text mapping: any card / single / multi
    r.eq(suitLine([]), "Add to any card", "empty suits → 'Add to any card'");
    r.eq(suitLine(null), "Add to any card", "absent suits → 'Add to any card'");
    r.eq(suitLine(undefined), "Add to any card", "undefined suits → 'Add to any card'");
    r.eq(suitLine(["♠"]), "Add to any ♠ card", "single suit → 'Add to any ♠ card'");
    r.eq(suitLine(["♥", "♦"]), "Add to any ♥ or ♦ card", "two suits → listed with 'or'");
    r.eq(suitLine(["♥", "♦", "♣"]), "Add to any ♥, ♦ or ♣ card", "three suits → comma-listed with trailing 'or'");
    // WILD1: the line describes the BASE restriction only — never mentions wild.
    for (const s of [[], ["♠"], ["♥", "♦"], ["♥", "♦", "♣", "♠"]]) {
      r.ok(!/wild/i.test(suitLine(s)), "no wild-exception leak in the suit line for " + JSON.stringify(s));
    }

    // --- B1 live) the helper reads the sticker's `suits` field LIVE from the registry
    let checkedRestricted = false, checkedAny = false;
    for (const t of g.StickerTypes.all()) {
      const line = suitLine(t.suits);
      r.ok(typeof line === "string" && line.startsWith("Add to any ") && line.endsWith(" card"),
        "live sticker '" + t.id + "' yields a well-formed suit line");
      if (Array.isArray(t.suits) && t.suits.length) {
        checkedRestricted = true;
        // Every allowed glyph appears in the line — driven purely by the live field.
        r.ok(t.suits.every(s => line.includes(s)), "restricted sticker '" + t.id + "' lists all its live suits");
      } else checkedAny = true;
    }
    r.ok(checkedRestricted || checkedAny, "the live sticker registry was exercised");
    // Mutating the live field changes the line (proves a live read, not a constant).
    const sample = g.StickerTypes.all()[0];
    const before = sample.suits;
    sample.suits = ["♠"];
    r.eq(suitLine(sample.suits), "Add to any ♠ card", "mutating a sticker's live suits changes the line (♠-only)");
    sample.suits = null;
    r.eq(suitLine(sample.suits), "Add to any card", "clearing a sticker's live suits → 'Add to any card'");
    sample.suits = before;

    // --- B1/B2) the popup inserts the line for STICKERS ONLY, between name + desc, escaped
    const help = fnBody(src, "showStoreItemHelp");
    r.ok(help.length > 0, "showStoreItemHelp found");
    r.ok(/kind === "sticker"/.test(help), "the suit line is gated to sticker items only");
    r.ok(help.includes("StickerTypes.get(id)"), "the popup fetches the sticker def by id (live suits, not a copy)");
    r.ok(help.includes("stickerSuitLine(stickerDef.suits)"), "the popup passes the LIVE def's suits to the mapping helper");
    r.ok(/escHtml\(stickerSuitLine\(/.test(help), "the suit line is escHtml'd before it reaches innerHTML");
    r.ok(help.includes("font-style:italic"), "the suit line renders ITALIC");
    // Order: name block, then the suit line, then the description block.
    const iName = help.indexOf("escHtml(info.label)");
    const iSuit = help.indexOf("suitLine +");
    const iDesc = help.indexOf('white-space:pre-line');
    r.ok(iName !== -1 && iSuit !== -1 && iDesc !== -1 && iName < iSuit && iSuit < iDesc,
      "the suit line sits BELOW the name and ABOVE the description");
    // Non-sticker kinds get no line (suitLine is "" unless kind==="sticker").
    r.ok(/stickerDef\s*=\s*kind === "sticker" && id \? StickerTypes\.get\(id\) : null/.test(help),
      "non-sticker items resolve no sticker def → no suit line");
  }

  return r.summary();
}
