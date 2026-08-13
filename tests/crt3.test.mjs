// CRT3 — CRT CASINO chunk 3: the store + all its popups (strictly aesthetic).
// Structural checks in the crt2 style: loadGame() proves the script still
// evaluates, and source-shape checks pin what the restyle relies on — the §4
// button roles (gold BUY / phosphor CONFIRM / red danger), the pixel-plaque
// shelf with its registry-driven rarity strip, the baked-dither pack foils
// sharing the map's chunk-2 deck tiles, the palette purge of the old rose /
// paper / violet store hues, and the UNCHANGED mechanisms (prompt-bar lifts,
// picker flat modes, store:show wrap). No tunables are pinned — tier classes
// and deck ids are read live from the registries/JS.
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
  const r = makeRunner("crt3.test.mjs");
  const html = fullHtml();
  const src = gameScript(html);

  // The game still evaluates with the store restyle in place.
  const g = loadGame();
  r.ok(!!(g.GameEngine && g.CampaignState && g.StickerTypes), "game script evaluates with the CRT store restyle");

  // --- Store shell: one flat felt well, one screen -------------------------
  {
    const store = cssRule(html, ".overlay.store");
    r.ok(store.includes("background: var(--felt-deep)"), ".overlay.store is the flat deep-felt screen well");
    r.ok(!store.includes("radial-gradient"), "the warm lamplight radial is retired (§1: no gradients-as-texture)");
    // Chunk-6 sweep: the ::before content:none belts left with the generic
    // .overlay::before tangle they guarded against — nothing paints a pseudo
    // texture behind the shop (or the map) any more.
    r.ok(!/\.overlay(\.store|\.map)?::before\s*\{/.test(html),
      "no overlay ::before tangle exists — the shop/map content:none belts are swept with it");
    r.ok(store.includes("overflow: hidden"), "the one-screen no-scroll shop layout is untouched");
  }

  // --- Shelf tiles: pixel plaques + registry-driven rarity strip -----------
  {
    const tile = cssRule(html, ".store-tile");
    r.ok(tile.includes("var(--felt-mid)") && tile.includes("var(--px) solid var(--ink)")
      && tile.includes("4px 4px 0 0 var(--shadow)"),
      ".store-tile is a pixel plaque (felt-mid face, ink border, hard shadow)");
    r.ok(cssRule(html, ".store-tile:active").includes("translate(2px, 2px)"),
      "pressing a tile sinks it one pixel step (§4)");
    // Rarity fills the WHOLE plaque (the 4px top strip is retired — it read as
    // an affordability light, not as rarity): palette-mapped tier accents on
    // the border + a wash of the same hue on the face, stamped from the LIVE
    // def. The native port mirrors it (StoreTileView blends at 0.22).
    r.ok(!/\.store-tile(\.srt-\w+)?::before\s*\{/.test(html),
      "the 4px rarity strip pseudo is gone — rarity colours the whole window");
    const uncommon = cssRule(html, ".store-tile.srt-uncommon");
    r.ok(uncommon.includes("border-color: var(--gold)"), "uncommon border = gold");
    r.ok(uncommon.includes("color-mix") && uncommon.includes("var(--gold)")
      && uncommon.includes("var(--felt-mid)"),
      "uncommon face is a gold wash over the felt (no retyped hex)");
    const rare = cssRule(html, ".store-tile.srt-rare");
    r.ok(rare.includes("border-color: var(--phosphor)"), "rare border = phosphor");
    r.ok(rare.includes("color-mix") && rare.includes("var(--phosphor)")
      && rare.includes("var(--felt-mid)"),
      "rare face is a phosphor wash over the felt (no retyped hex)");
    r.ok(cssRule(html, ".store-tile.srt-common").includes("var(--ink)"),
      "common stays the quiet ink-bordered plaque");
    const ot = fnBody(src, "offerTile");
    r.ok(ot.includes('srt-" + t.tier'), "offerTile stamps srt-<tier> from the live registry def (no hardcoded tiers)");
    // Every registry tier value has a plaque rule (registry-driven, not pinned).
    const tiers = new Set();
    for (const reg of [g.StickerTypes, g.PillarTypes, g.BaseTypes, g.PackTypes, g.SamePowerTypes])
      for (const t of reg.all()) if (t.tier) tiers.add(t.tier);
    r.ok(tiers.size >= 2, "registries carry at least two live tier values");
    for (const tier of tiers)
      r.ok(html.includes(".store-tile.srt-" + tier + " "),
        "live tier '" + tier + "' has a shelf plaque rule");
    // Price reads gold-on-ink; the soft radial contact shadow is gone.
    const price = cssRule(html, ".store-tile .ti-price");
    r.ok(price.includes("var(--gold)") && price.includes("var(--ink)") && price.includes("border-radius: 0"),
      "the price chip is gold on ink, squared");
    r.ok(!html.includes(".store-tile .ti-obj::after"),
      "the blurred radial contact-shadow ellipse is deleted (§10: no blur)");
    r.ok(cssRule(html, ".store-tile .ti-obj").includes("transform: none"),
      "the shelf merchandise tilt is cancelled on the pixel grid (offerTile markup unchanged)");
    r.ok(!cssRule(html, ".store-tile.tile-stickerlock").includes("filter"),
      "the Lammy sticker-lock dims by opacity only (grayscale filter retired)");
  }

  // --- Store chrome: reroll (gold), help "?", key panel --------------------
  {
    const rr = cssRule(html, ".store-reroll");
    r.ok(rr.includes("var(--felt-deep)") && rr.includes("var(--gold)") && rr.includes("border-radius: 0"),
      "Refresh is the §4 gold button (it spends coins)");
    r.ok(cssRule(html, ".store-reroll:active").includes("translate(2px, 2px)"), "…and sinks when pressed");
    r.ok(cssRule(html, ".store-reroll:disabled").includes("var(--felt-mid)"), "…and goes felt-mid when unaffordable");
    const help = cssRule(html, ".store-help-btn");
    // v5.44: the "?" moved to the RIGHT of Refresh; the right-cluster
    // auto-margin now lives on .store-reroll (storehelp1 pins the order).
    r.ok(cssRule(html, ".store-reroll").includes("margin-left: auto"),
      "the Refresh+? pair keeps the right-cluster layout (auto-margin on Refresh)");
    r.ok(help.includes("border-radius: 0") && help.includes("var(--px) solid var(--ink)"),
      "the ? squares off into the pixel chrome");
    const key = cssRule(html, ".store-key-panel");
    r.ok(/z-index:\s*84/.test(key) && key.includes("background: var(--panel)"),
      "the key panel keeps its pinned z-84 + opaque --panel (storehelp1 contract)");
    r.ok(key.includes("border-radius: 0") && key.includes("4px 4px 0 0 var(--shadow)"),
      "…on the standard pixel panel");
  }

  // --- Loadout reference ----------------------------------------------------
  {
    const lo = cssRule(html, ".store-loadout");
    r.ok(lo.includes("var(--felt-mid)") && lo.includes("var(--px) solid var(--ink)")
      && lo.includes("4px 4px 0 0 var(--shadow)"), ".store-loadout is a pixel panel");
    const chip = cssRule(html, ".lo-chip");
    r.ok(chip.includes("var(--felt-deep)") && chip.includes("border-radius: 0"),
      "equipped chips are recessed felt slabs");
    r.ok(cssRule(html, ".lo-chip.pillar").includes("var(--gold)"), "pillar chip identity = gold");
    r.ok(cssRule(html, ".lo-chip.samepower").includes("var(--phosphor)"), "Same-Power chip identity = phosphor");
    r.ok(cssRule(html, ".lo-empty").includes("dashed"), "empty slots stay dashed placeholders");
  }

  // --- Same-Power badge plate (logo art itself = chunk 5) ------------------
  {
    const b = cssRule(html, ".sp-badge");
    r.ok(b.includes("var(--felt-deep)") && b.includes("var(--px) solid var(--ink)")
      && b.includes("2px 2px 0 0 var(--shadow)") && b.includes("border-radius: 0"),
      ".sp-badge is a deep-felt pixel plate");
    r.ok(cssRule(html, ".sp-badge-ico .sp-mark").includes("var(--phosphor)"),
      "the power's logo inks phosphor (electric artifact)");
    // The rose plate palette is fully purged from the stylesheet.
    for (const hex of ["#FCF4F7", "#F1DCE6", "#C84A78"])
      r.ok(!html.includes(hex), "rose store hue " + hex + " is purged");
  }

  // --- Removal object -------------------------------------------------------
  {
    // Chunk 5 (sprite mode): the object is the pixel removal card (∅ baked in).
    const ro = cssRule(html, ".removal-obj");
    r.ok(ro.includes("var(--pxi-removal)") && ro.includes("image-rendering: pixelated"),
      ".removal-obj is the pixel removal card");
    r.ok(!html.includes('<span class="ro-sym">'), "the text ∅ symbol span is retired (baked in the art)");
    r.ok(!html.includes("#efeaf2") && !html.includes("#e2dbe8"), "the stitched-grey lilac palette is purged");
  }

  // --- Store detail: pixel panel, tier ladder, gold BUY / red SELL ----------
  {
    r.ok(cssRule(html, ".store-detail").includes("rgba(16, 16, 14"),
      "the detail backdrop is an ink scrim (no blur, chunk-2 idiom)");
    const panel = cssRule(html, ".sd-panel");
    r.ok(panel.includes("var(--felt-mid)") && panel.includes("var(--px) solid var(--ink)")
      && panel.includes("4px 4px 0 0 var(--shadow)"),
      ".sd-panel is the standard pixel panel (no more bare text on the scrim)");
    r.ok(!panel.includes("backdrop-filter"), "…and carries no backdrop blur (THERMAL5)");
    r.ok(cssRule(html, ".sd-name").includes("var(--card-face)")
      && cssRule(html, ".sd-name").includes("var(--font-display)"),
      "the item name is display-face cream (pure white is banned)");
    r.ok(cssRule(html, '.sd-tier[data-tier="uncommon"]').includes("var(--gold)"), "tier label: uncommon = gold");
    r.ok(cssRule(html, '.sd-tier[data-tier="rare"]').includes("var(--phosphor)"), "tier label: rare = phosphor");
    const buy = cssRule(html, ".sh-buy");
    r.ok(buy.includes("var(--felt-deep)") && buy.includes("var(--gold)")
      && buy.includes("4px 4px 0 0 var(--shadow)") && buy.includes("border-radius: 0"),
      "BUY is the §4 gold button");
    r.ok(cssRule(html, ".sh-buy:active").includes("translate(2px, 2px)"), "…that sinks when pressed");
    r.ok(cssRule(html, ".sh-buy:disabled").includes("var(--felt-mid)"), "…and goes felt-mid disabled (no glow)");
    r.ok(html.includes(".sd-buy.hidden { display: none; }"), "the sell1 .sd-buy.hidden literal survives");
    r.ok(cssRule(html, "#sdSell").includes("var(--suit-red)"), "SELL (destroy-for-coins) wears the §4 danger red");
    r.ok(cssRule(html, ".sd-col.sd-col-sel").includes("var(--phosphor)")
      && cssRule(html, ".sd-col.sd-col-sel").includes("var(--sel)"),
      "the picked placement slot lights phosphor");
    r.ok(cssRule(html, ".sdc-side.sdc-new").includes("var(--phosphor)"),
      "the incoming side of the replace comparison is phosphor-framed");
    r.ok(cssRule(html, ".sdc-arrow").includes("var(--gold)")
      && cssRule(html, ".sd-replace-q b").includes("var(--gold)"),
      "comparison arrow + replace-question names read gold (violet purged)");
    r.ok(!html.includes("#cdb9f4") && !html.includes("#7fc4e8") && !html.includes("#e8b964"),
      "the old violet/sky/amber detail hues are purged");
  }

  // --- Pack reveal: phosphor CONFIRM, pixel panel, keep-choice chips --------
  {
    const conf = cssRule(html, ".buy-confirm");
    r.ok(conf.includes("var(--phosphor)") && conf.includes("var(--ink)") && conf.includes("var(--glow)"),
      "pack Confirm is the phosphor CTA (committed action)");
    r.ok(cssRule(html, ".buy-confirm:disabled").includes("var(--felt-mid)"),
      "…felt-mid while the pick is incomplete");
    const pp = cssRule(html, ".pack-panel");
    r.ok(pp.includes("var(--px) solid var(--ink)") && pp.includes("border-radius: 0"),
      ".pack-panel is a pixel panel");
    r.ok(cssRule(html, ".pack-title").includes("var(--font-display)")
      && cssRule(html, ".pack-title").includes("var(--phosphor)"),
      "the reveal headline is display-face phosphor");
    r.ok(cssRule(html, ".pk-sticker").includes("var(--felt-deep)"),
      "revealed sticker chips sit in recessed felt wells");
    r.ok(cssRule(html, ".pack-item.chosen .pk-sticker").includes("border-radius: 0"),
      "keep-choice outline chips squared off");
    // Windfall pack-show presentation pins (mystery-ui contract) survive verbatim.
    r.ok(html.includes(".confirm-overlay.pack-show .pack-panel { border-top: 4px solid var(--good); }"),
      "the pack-show good-rim literal is untouched");
    r.ok(html.includes(".confirm-overlay.pack-show .pack-item .mini-card { animation: meaCardFlip"),
      "the pack-show card-flip literal is untouched");
  }

  // --- Pack foils: chunk-5 pixel foils (crimps/window/contents baked in) ----
  {
    // Sprite mode replaced the CSS crimp/dither/window painting with the
    // PixelArt foil icons; the type still reads at a glance from the art vars.
    const art = cssRule(html, ".pf-art");
    r.ok(art.includes("var(--pxi-packCard)") && art.includes("image-rendering: pixelated"),
      ".pf-art draws the pixel card-pack foil, crisp");
    r.ok(cssRule(html, ".pack-foil.pf-sticker .pf-art").includes("var(--pxi-packSticker)"),
      "sticker packs swap to the felt sticker foil");
    r.ok(cssRule(html, ".pack-foil.pf-large .pf-art").includes("var(--pxi-packLarge)"),
      "keep-2 premium packs wear the brass star foil");
    r.ok(!html.includes('<span class="pf-crimp') && !html.includes('<span class="pf-window'),
      "the CSS-built crimp/window spans are retired from the builder");
    // The premium class is registry-driven (keep >= 2), never an id pin.
    const po = fnBody(src, "packObjectHtml");
    r.ok(po.includes("(t.keep || 0) >= 2") && po.includes("pf-large"),
      "packObjectHtml derives pf-large from the live registry `keep` field");
    r.ok(g.PackTypes.all().some(t => (t.keep || 0) >= 2) && g.PackTypes.all().some(t => (t.keep || 0) < 2),
      "the live registry exercises both foil classes");
    // Tear-open still rides the same class hook (whole-foil animation now).
    r.ok(cssRule(html, ".pack-foil.tearing").includes("packTear"),
      "the tear-open animation survives on the whole foil");
    // The map's per-deck .mn-pack tint mechanism is untouched (deck tint now
    // lives ONLY on the map stacks; the shop foil is class art).
    for (const deck of ["mamma", "smith", "lammy"])
      r.ok(cssRule(html, ".mdeck-" + deck + " .mn-pack .mpk-card").includes("data:image/gif"),
        deck + " map pack-stack keeps its chunk-2 deck-tinted dither tile");
    r.ok(fnBody(src, "showStore").includes('classList.add("mdeck-" + selectedDeck().id)'),
      "showStore stamps the live deck skin on #storeOverlay (mirrors the map stamp)");
  }

  // --- Picker (sticker-apply) flat-mode law: untouched ----------------------
  {
    r.ok(html.includes(".sa-lite .dcs-gloss { display: none; }"), "sa-lite gloss-kill literal survives (STKLAG)");
    r.ok(html.includes(".sa-xlite .mini-card { box-shadow: none; border: none; }"),
      "XL-lite tile flatten literal survives (THERMAL2)");
    r.ok(html.includes(".sa-xlite .sa-card.sa-disabled { filter: none; }"),
      "XL-lite disabled-card filter ban survives");
    r.ok(cssRule(html, ".sa-trash-btn.armed").includes("var(--suit-red)"),
      "the armed Trash (danger) reads suit red");
  }

  // --- Item place + post-deal ----------------------------------------------
  {
    const col = cssRule(html, ".ip-col");
    r.ok(col.includes("var(--felt-deep)") && col.includes("border-radius: 0"),
      ".ip-col is a recessed felt slot");
    r.ok(cssRule(html, ".ip-col.ip-selected").includes("var(--sel)"), "the picked column lights phosphor");
    const pd = cssRule(html, ".pd-panel");
    r.ok(pd.includes("var(--felt-mid)") && pd.includes("var(--px) solid var(--ink)")
      && !pd.includes("linear-gradient"),
      ".pd-panel is a pixel panel (warm paper gradient purged)");
    r.ok(!html.includes("#FBF6F1") && !html.includes("#F1E8DE"), "the paper hues are gone");
    r.ok(cssRule(html, ".pd-title").includes("var(--phosphor)"), "'Spoils' headline is phosphor display");
  }

  // --- Mechanisms: prompt-bar lifts + flows byte-familiar -------------------
  {
    r.ok(html.includes("body.store-confirm .play-controls { z-index: 70; }"),
      "the reroll-confirm z-lift is unchanged");
    r.ok(html.includes("body.store-selling .play-controls"), "the sell-confirm z-lift is unchanged");
    r.ok(fnBody(src, "rerollUI").includes('classList.add("store-confirm")')
      && fnBody(src, "rerollUI").includes("showActionBar("),
      "Refresh still confirms on the shared prompt bar (no modal)");
    for (const name of ["renderStore", "offerTile", "openStoreDetail", "openPackReveal",
      "renderPackReveal", "renderStickerApplyCards", "openStoreKey", "requestStoreSell"])
      r.ok(src.includes("function " + name + "("), name + " untouched by the restyle");
    // Sell keeps its live-priced prompt copy (sell1 contract).
    r.ok(fnBody(src, "openEquippedDetail").includes('"Sell for " + COIN_SVG + " " + sellValueOf(t)'),
      "the Sell label still prices from sellValueOf(t)");
  }

  return r.summary();
}
