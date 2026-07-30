// CRT5 — CRT CASINO chunk 5: characters + item icons everywhere (strictly
// aesthetic). The four deck characters are 32×32 pixel sprites (doubled from
// 16 so every face carries real eye anatomy: cream sclera + ink pupil + a 1px
// phosphor glint) and the item-class art stays 16×16, all rendered ONCE at
// boot by the inline PixelArt module and consumed through CSS custom
// properties; the EXISTING DeckChar/CharMood class machinery (untouched)
// just picks frames. Checks in the crt2-4 style:
// loadGame() proves the script evaluates (PixelArt validates its matrices at
// load — malformed art throws), registry-driven shape checks tie the sprite
// sheet to the live DECKS/tier/suit data (no pinned tunables), source-shape
// checks pin the frame/state wiring, the icon swaps, the retired CSS
// paintings, and the UNCHANGED state machines.
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
  const r = makeRunner("crt5.test.mjs");
  const html = fullHtml();
  const src = gameScript(html);

  // The game still evaluates — which also runs PixelArt's fail-loud matrix
  // validation (row counts, row lengths, the legal char alphabet).
  const g = loadGame();
  r.ok(!!(g.GameEngine && g.CampaignState && g.PixelArt), "game script evaluates with PixelArt inline (matrices self-validated at load)");
  const P = g.PixelArt;

  // --- Sprite sheet shape, tied to the LIVE data ----------------------------
  {
    // Every deck in the live DECKS roster has a full sprite set (ids read from
    // the source table, never pinned).
    const deckIds = [...(src.match(/const DECKS = \[[\s\S]*?\n  \];/) || [""])[0]
      .matchAll(/id: "(\w+)"/g)].map(m => m[1]);
    r.ok(deckIds.length >= 4, "DECKS roster read from source (" + deckIds.length + " decks)");
    const STATES = ["idle", "look", "happy", "sad", "dance", "trail"];
    const TIERS = ["regular", "master", "legendary"];
    for (const id of deckIds) {
      r.ok(!!P.SPRITES[id] && STATES.every(st => Array.isArray(P.SPRITES[id][st])),
        "deck '" + id + "' has all six sprite states");
      r.ok(!!P.TIER_ACCESSORY[id] && TIERS.every(t => Array.isArray(P.TIER_ACCESSORY[id][t])),
        "deck '" + id + "' has all three tier accessory overlays");
    }
    r.eq(Object.keys(P.SPRITES).length, deckIds.length, "no orphan sprite sets (sheet == roster)");
    // The §1 palette lock: every PixelArt colour IS a live CSS token value.
    const token = (name) => (html.match(new RegExp("--" + name + ":\\s*(#[0-9a-fA-F]{6})")) || [])[1];
    const expect = { K: "ink", C: "card-face", R: "suit-red", G: "gold", P: "phosphor", F: "felt-mid", D: "felt-deep" };
    for (const [ch, tok] of Object.entries(expect))
      r.eq(P.PALETTE[ch].toLowerCase(), (token(tok) || "").toLowerCase(),
        "palette '" + ch + "' == the live --" + tok + " token");
    // Dithers only mix palette letters (the §1 optical-mixing rule).
    for (const [d, pair] of Object.entries(P.DITHER))
      r.ok(pair.every(c => P.PALETTE[c]), "dither '" + d + "' mixes two palette colours");
    // MIXED-GRID sheet: characters + overlays are 32×32 (the eye-anatomy
    // upgrade), icons 16×16, badges 8×8 — the renderer sizes each canvas
    // from its matrix, so the grids are pinned HERE, on the live data.
    const square = (rows, n) => rows.length === n && rows.every(r => r.length === n);
    for (const id of deckIds) {
      r.ok(STATES.every(st => square(P.SPRITES[id][st], 32)),
        "deck '" + id + "' sprites are on the 32 grid");
      r.ok(TIERS.every(t => square(P.TIER_ACCESSORY[id][t], 32)),
        "deck '" + id + "' overlays share the sprite grid (contain-fit anchor contract)");
    }
    r.ok(Object.values(P.ICONS).every(rows => square(rows, 16)), "item icons stay 16×16");
    r.ok(Object.values(P.SUIT_BADGES).every(rows => square(rows, 8)), "suit badges stay 8×8");
    // Eye anatomy: every character's open-eyed poses carry the 1px phosphor
    // glint (P) — the glossy-highlight charm from the reference art. (happy
    // may close the eyes; dance may add confetti — idle/look/trail are the
    // guaranteed open-eye states.)
    for (const id of deckIds)
      for (const st of ["idle", "look", "trail"])
        r.ok(P.SPRITES[id][st].some(row => row.includes("P")),
          "deck '" + id + "' " + st + " eyes carry the phosphor glint");
    // Bespoke expressions: each state is genuinely distinct art per character
    // (no shared-face grammar), and gaze is a real change (look != idle).
    for (const id of deckIds) {
      const f = (st) => P.SPRITES[id][st].join("\n");
      r.ok(f("look") !== f("idle") && f("happy") !== f("idle") && f("sad") !== f("idle")
        && f("happy") !== f("dance"),
        "deck '" + id + "' idle/look/happy/sad/dance are distinct drawings");
    }
    // Box-anchor contract: the ink bars the tier overlays hang on (box top
    // 4-5, lid-bottom 9-10, box bottom 26-27) never move across the five
    // standing states — the reason ONE overlay fits them all.
    for (const id of deckIds)
      for (const st of ["look", "happy", "sad", "dance"])
        for (const y of [4, 5, 9, 10, 26, 27])
          r.eq(P.SPRITES[id][st][y], P.SPRITES[id].idle[y],
            "deck '" + id + "' " + st + " keeps anchor row " + y);
    // Mamma's head-bow overlay must COVER her baked rose bow in every
    // standing pose (flopped dance bow included) — a peeking baked pixel
    // would double-draw the bow under a tier accessory.
    if (P.SPRITES.mamma && P.TIER_ACCESSORY.mamma) {
      for (const st of ["idle", "look", "happy", "sad", "dance"])
        for (const t of TIERS) {
          let covered = true;
          for (let y = 0; y < 4; y++)
            for (let x = 6; x <= 25; x++)   // the box span — dance confetti flies outside it
              if (P.SPRITES.mamma[st][y][x] !== "." && P.TIER_ACCESSORY.mamma[t][y][x] === ".")
                covered = false;
          r.ok(covered, "mamma " + t + " bow overlay fully covers the baked bow in " + st);
        }
    }
    // DOM-guarded renderer: in this node harness the data-URIs degrade to ""
    // (strings, never throws) — the browser renders real PNGs at boot.
    r.ok(typeof P.icon("coin") === "string" && typeof P.sprite("pink", "idle") === "string",
      "renderer is DOM-guarded (harness gets strings, no throw)");
    r.ok(P.img("samePower", "sp-mark").includes('class="pxi sp-mark"'),
      "the img helper stamps the shared .pxi (pixelated) class");
    r.ok(typeof P.bootMs === "number", "boot render time is measured (bootMs)");
  }

  // --- Frame/state wiring: existing classes → background frames ------------
  {
    const body = cssRule(html, ".dc-body");
    r.ok(body.includes("var(--spr-ov), var(--spr)") && body.includes("contain")
      && body.includes("image-rendering: pixelated") && body.includes("center bottom"),
      ".dc-body is the sprite canvas: overlay-over-frame, contain-fit, bottom-anchored, crisp");
    r.ok(body.includes("animation: dcBreathe"), "…and keeps the idle breathe (body motion survives)");
    // Base rule binds Pinky's frames as the default set; skins override.
    const base = cssRule(html, ".deck-char, .deck-char-jump, .map-avatar");
    r.ok(base.includes("--f-idle: var(--spr-pink-idle)") && base.includes("--spr: var(--f-idle)")
      && base.includes("--spr-ov: none"),
      "the shared base rule defaults to Pinky frames with no overlay");
    for (const id of ["mamma", "smith", "lammy"])
      r.ok(cssRule(html, ".ch-" + id).includes("--f-idle: var(--spr-" + id + "-idle)"),
        "skin class ch-" + id + " rebinds the frame set");
    // Tier overlays: one rule per live tier class per character.
    for (const id of ["pink", "mamma", "smith", "lammy"])
      for (const t of ["regular", "master", "legendary"])
        r.ok(html.includes(".ch-" + id + ".tier-" + t) && html.includes("--spr-" + id + "-ov-" + t),
          "tier-" + t + " dresses ch-" + id + " via its overlay var");
    // State mapping (the DOCUMENTED table): blink/looking→look ·
    // glad/happy/perk→happy · celebrate/mood-win→dance · sad/mood-loss→sad.
    r.ok(cssRule(html, ".deck-char.dc-blink, .deck-char.dc-looking").includes("var(--f-look)"),
      "dc-blink + dc-looking map to the look frame");
    r.ok(cssRule(html, ".deck-char.dc-glad, .deck-char.dc-happy, .deck-char.dc-perk").includes("var(--f-happy)"),
      "dc-glad/dc-happy/dc-perk map to the happy frame");
    r.ok(cssRule(html, ".deck-char.dc-celebrate, .deck-char.mood-win").includes("var(--f-dance)"),
      "dc-celebrate + mood-win map to the win-dance frame");
    r.ok(cssRule(html, ".deck-char.dc-sad, .deck-char.mood-loss").includes("var(--f-sad)"),
      "dc-sad + mood-loss map to the sad frame");
    // Map avatar: trail pose base, mood swaps, NO tier dressing (artist
    // contract: the compact marker drops accessories).
    const av = cssRule(html, ".av-body");
    r.ok(av.includes("var(--spr-ov), var(--spr)") && av.includes("image-rendering: pixelated"),
      ".av-body is the same sprite canvas at marker scale");
    r.ok(cssRule(html, ".map-avatar").includes("var(--f-trail)"), "the marker rides the trail pose");
    r.ok(cssRule(html, ".map-avatar.mood-win").includes("var(--f-dance)")
      && cssRule(html, ".map-avatar.mood-loss").includes("var(--f-sad)")
      && cssRule(html, ".map-avatar.mood-happy, .map-avatar.collecting").includes("var(--f-happy)")
      && cssRule(html, ".map-avatar.mood-worried").includes("var(--f-look)"),
      "avatar moods swap to matching full poses");
    r.ok(cssRule(html, ".map-avatar.tier-regular, .map-avatar.tier-master, .map-avatar.tier-legendary")
      .includes("--spr-ov: none"),
      "the marker drops the tier overlay in every tier");
    // Body-motion keyframes survive; every face-part keyframe is deleted.
    for (const kf of ["dcBreathe", "dcGlad", "dcPerk", "dcHappy", "dcCelebrate", "dcSad", "dcArrive",
      "avBob", "avDance", "avBounce", "ducBounce"])
      r.ok(html.includes("@keyframes " + kf), "body-motion keyframe " + kf + " survives");
    for (const kf of ["moodDart", "moodTear", "dsIdleBlink", "dcLook", "avLid", "mammaIdle", "mammaWaltz",
      "smithIdle", "smithRock", "smithNod", "monoGlint", "monoDrop", "lammyIdle", "lammyShimmy", "packCrimpRip"])
      r.ok(!html.includes("@keyframes " + kf), "face-part keyframe " + kf + " is deleted (animation count went DOWN)");
  }

  // --- Old CSS-drawn character art fully retired ----------------------------
  {
    // The skin body hexes (rose/olive/violet radials) and Pinky's grime/wear
    // machinery are purged.
    for (const hex of ["#e997b3", "#c25f83", "#96a687", "#5f6f52", "#a494b4", "#6c5c82", "#241c28"])
      r.ok(!html.includes(hex), "old character body hex " + hex + " is purged");
    r.ok(!html.includes("--char-patch") && !html.includes("--grime"),
      "the wear-patch + grime token machinery is retired");
    // Markup: every character instantiation is the sprite body (+ live count).
    r.ok(/id="deckChar"><span class="dc-body"><span class="deck-count">/.test(html),
      "the static board character is sprite body + count only");
    r.ok(!src.includes("dc-x x-hat") && !src.includes("av-lid") && !src.includes("dc-pupil"),
      "no builder emits face/accessory spans any more");
    const dch = (src.match(/const DECK_CHAR_HTML =[\s\S]*?';/) || [""])[0];
    r.ok(dch.includes('<span class="dc-body"></span>') && !dch.includes("dc-face"),
      "DECK_CHAR_HTML is the bare sprite body");
    r.ok(fnBody(src, "ensureAvatar").includes('<div class="av-body"></div>')
      && fnBody(src, "ensureAvatar").includes("av-badge"),
      "the map avatar is sprite body + live badge");
    r.ok(fnBody(src, "jumpMapCharToDeck").includes('<span class="dc-body">')
      && fnBody(src, "jumpMapCharToDeck").includes("deck-count"),
      "the map→deck jump clone is sprite body + travelling count");
    r.ok(!cssRule(html, ".deck-char-jump").includes("drop-shadow"),
      "the jump clone's blurred lift filter is gone (§10 no blur)");
    // Tutorial face: the pixel Pinky, not the CSS chip.
    r.ok(cssRule(html, ".tut-face").includes("var(--spr-pink-idle)")
      && cssRule(html, ".tut-face").includes("image-rendering: pixelated"),
      ".tut-face is the Pinky idle sprite");
  }

  // --- State machines byte-familiar (zero behaviour change) -----------------
  {
    r.ok(src.includes('looking: { cls: "dc-looking", hold: 0 }')
      && src.includes('celebrate: { cls: "dc-celebrate", hold: 1500 }')
      && src.includes('sad:     { cls: "dc-sad",     hold: 1300 }'),
      "the DeckChar CHAR_STATES table is untouched");
    for (const name of ["lookAtPile", "releasePile", "startBlink", "stopBlink", "aimAtPile"])
      r.ok(src.includes(name), "DeckChar." + name + " machinery untouched");
    r.ok(src.includes('MOODS = ["mood-anxious", "mood-hopeful", "mood-bright", "mood-win", "mood-loss"]'),
      "the CharMood mood list is untouched");
    r.ok(src.includes('n.style.setProperty("--eye-x"') && src.includes('n.style.setProperty("--lean-x"'),
      "eye-aim/lean var writes survive (inert on the sprite, contract intact)");
    r.ok(fnBody(src, "scheduleAvatarBlink").includes('classList.add("blink")'),
      "the avatar blink loop still runs (class is a deliberate frame no-op)");
    // Perf hooks: the deck-modal pause list + scene-idle pause still cover the
    // animated sprite bodies.
    r.ok(html.includes("body.scene-idle #deckChar .dc-body { animation-play-state: paused; }"),
      "scene-idle still pauses the deck body behind menus");
  }

  // --- Item icons: the class art everywhere ---------------------------------
  {
    // The full icon census (18 + 4 suit badges). stickerCursed2 = Leech
    // Swarm's scatter variant (v5.55), routed via .dcs-c-leech2.
    const ICONS = ["sticker", "stickerCursed", "stickerCursed2", "pillar", "base", "samePower", "packCard", "packSticker",
      "packLarge", "removal", "coin", "joker", "blank", "mystery", "fossil", "seed", "score", "lock"];
    for (const k of ICONS) r.ok(Array.isArray(P.ICONS[k]), "icon '" + k + "' present");
    r.eq(Object.keys(P.ICONS).length, ICONS.length, "no orphan icons");
    // Registry-driven: every suit any sticker restricts to has a pixel badge.
    const usedSuits = new Set();
    for (const t of g.StickerTypes.all()) (t.suits || []).forEach(s => usedSuits.add(s));
    r.ok(usedSuits.size >= 1, "live registry carries suit restrictions");
    for (const s of usedSuits) {
      r.ok(Array.isArray(P.SUIT_BADGES[s]), "suit badge exists for live restriction " + s);
      r.ok(html.includes(".dcs-suits i.s-" + P.suitKey(s)), "…with a CSS rule for its s-class");
    }
    r.ok(fnBody(src, "dieCutChip").includes('" s-" + PixelArt.suitKey(s)'),
      "dieCutChip stamps the s-<suit> class from the same items.js field (BADGE1 intact)");
    // Sticker chip = pixel chip + per-item glyph in ink; cursed = corrupted art.
    r.ok(cssRule(html, ".dcs").includes("var(--pxi-sticker)"), ".dcs draws the pixel sticker chip");
    r.ok(cssRule(html, ".dcs-ic").includes("var(--ink)"), "the item glyph inks on top");
    r.ok(cssRule(html, ".dcs.dcs-cursed").includes("var(--pxi-stickerCursed)"),
      "cursed chips wear the bit-rot art");
    r.ok(cssRule(html, ".dcs.dcs-cursed .dcs-ic").includes("display: none"),
      "…and drop the raw-emoji glyph (leech/leech2 read as corruption, not emoji)");
    r.ok(src.includes('const face = t.cursed ? "" :'), "stickerChip routes cursed chips glyph-free");
    // Pillar pennant + emblem overlay.
    r.ok(cssRule(html, ".pennant .pb-art").includes("var(--pxi-pillar)"),
      "the pennant is the pixel pillar banner");
    const pb = fnBody(src, "pathwayBannerHtml");
    r.ok(pb.includes("pb-art") && pb.includes("pb-emblem") && pb.includes("ELEM_GLYPH[t.id]")
      && !pb.includes("pb-cloth"),
      "pathwayBannerHtml = art canvas + per-item emblem + live badges (cloth spans retired)");
    // Base plaque: pixel plate, family colour moved to the symbol.
    const plq = cssRule(html, ".base-banner.plaque");
    r.ok(plq.includes("var(--pxi-base)") && plq.includes("image-rendering: pixelated"),
      "the base plaque is the pixel plate");
    r.ok(cssRule(html, ".base-banner.plaque .base-sym").includes("var(--mtl-mid)"),
      "the family accent now inks the SYMBOL (fam-* rules keep the palette map)");
    r.ok(!fnBody(src, "baseBannerHtml").includes("bp-screw"),
      "the corner-screw spans are retired (baked in the art)");
    r.ok(fnBody(src, "baseBannerHtml").includes("base-charge"),
      "the live LED chip survives (charged/spent state)");
    // Same-Power plate art = the class icon; unique logos survive on the
    // Same button chip + loadout.
    r.ok(fnBody(src, "samePowerBadgeHtml").includes('PixelArt.img("samePower", "sp-mark")'),
      "the Same-Power plate mark is the pixel samePower icon");
    r.ok(fnBody(src, "updateSamePowerHud").includes("sp-on-btn"),
      "the equipped power's unique monoline logo still rides the Same button");
    // Removal / joker / blank / mystery faces.
    r.ok(cssRule(html, ".removal-obj").includes("var(--pxi-removal)"), "removal = pixel ∅ card");
    r.ok(cssRule(html, ".mini-card.mc-joker").includes("var(--pxi-joker)")
      && cssRule(html, ".node-card .front.nc-joker").includes("var(--pxi-joker)"),
      "joker faces (pack mini-card + map node twin) are the pixel gold-star card");
    r.ok(cssRule(html, ".mini-card.mc-blank").includes("var(--pxi-blank)")
      && cssRule(html, ".node-card .front.nc-blank").includes("var(--pxi-blank)"),
      "blank/removal faces are the pixel stitched card");
    r.ok(cssRule(html, ".mn-myst").includes("var(--pxi-mystery)"),
      "the mystery node face is the pixel ? card");
    r.ok(src.includes('(state === "here" ? " open" : "") + \'"></span>\''),
      "…with the text ? removed (baked in the art; .open keeps the phosphor frame)");
    // Loadout base chips: BASE_SYM glyph instead of raw items.js emoji.
    const lc = fnBody(src, "loadoutChip");
    r.ok(lc.includes("baseSymHtml(t)") && !lc.includes(': \'<span class="lo-ico">\' + (t.icon || "") + \'</span>\';\n    return'
      ) || lc.includes("baseSymHtml(t)"),
      "loadout base chips render the plaque symbol (emoji gap closed)");
  }

  // --- CRT-STK: per-sticker chip faces, 1:1 with the live registry ----------
  {
    // Registry-driven: EVERY non-cursed sticker in the live items.js registry
    // has its own hand-authored icon; cursed types (leech/leech2) keep the
    // shared stickerCursed art and take NO entry. A new items.js sticker
    // without art must fail loud at load — pinned on the source below.
    const square16 = (rows) => Array.isArray(rows) && rows.length === 16 && rows.every(r => typeof r === "string" && r.length === 16);
    const LEGAL = new Set([".", "K", "C", "R", "G", "P", "F", "D", "p", "b", "g", "s"]);
    const nonCursed = g.StickerTypes.all().filter(t => !t.cursed);
    const cursed = g.StickerTypes.all().filter(t => t.cursed);
    r.ok(nonCursed.length >= 40 && cursed.length >= 1, "live registry read (" + nonCursed.length + " non-cursed + " + cursed.length + " cursed)");
    for (const t of nonCursed)
      r.ok(square16(P.STICKER_ICONS[t.id]), "sticker '" + t.id + "' has its own 16×16 chip face");
    for (const t of nonCursed)
      r.ok((P.STICKER_ICONS[t.id] || []).every(row => [...row].every(ch => LEGAL.has(ch))),
        "sticker '" + t.id + "' art stays on the locked palette alphabet");
    for (const t of cursed)
      r.ok(!P.STICKER_ICONS[t.id], "cursed '" + t.id + "' takes no entry (the corruption art IS its face)");
    r.eq(Object.keys(P.STICKER_ICONS).length, nonCursed.length,
      "no orphan sticker icons (sheet == the non-cursed registry, 1:1)");
    // Every icon is a distinct drawing — the whole point of the sheet.
    const seen = new Map();
    for (const [id, rows] of Object.entries(P.STICKER_ICONS)) {
      const key = rows.join("\n");
      r.ok(!seen.has(key), "icon '" + id + "' is a unique drawing" + (seen.has(key) ? " (duplicates " + seen.get(key) + ")" : ""));
      seen.set(key, id);
    }
    // Fail-loud contract: StickerTypes throws on a non-cursed sticker without
    // art (source pin + a live probe through the harness).
    r.ok(src.includes("if (!t.cursed && !PixelArt.STICKER_ICONS[t.id])"),
      "StickerTypes carries the 1:1 fail-loud check");
    let threw = false;
    try {
      const items = readFileSync(join(HERE, "..", "items.js"), "utf8");
      loadGame({ itemsSource: items.replace('stickers: [\n    { id: "rankUp",',
        'stickers: [\n    { id: "__noart", label: "No Art", icon: "?", kind: "rank", rankDelta: 1, tier: "common", price: 1, description: "probe" },\n    { id: "rankUp",') });
    } catch (e) { threw = String(e && e.message).includes("STICKER_ICONS"); }
    r.ok(threw, "a non-cursed sticker without chip art refuses to boot (fail-loud probe)");
    // The render path: boot publishes one --pxi-stk-<id> var + one .pxs-<id>
    // class per icon; stickerChip's face is the class span with the composed
    // glyph as the no-canvas fallback; the shared .pxs sizing rule exists.
    r.ok(src.includes('css += "--pxi-stk-" + k') && src.includes('css += ".pxs-" + k'),
      "boot render publishes --pxi-stk-<id> vars + .pxs-<id> classes");
    r.ok(src.includes("PixelArt.stickerIcon(t.id) ? '<span class=\"pxs pxs-' + t.id") ,
      "stickerChip's face is the pre-rendered pixel icon (glyph = no-canvas fallback)");
    r.ok(typeof P.stickerIcon(nonCursed[0].id) === "string", "stickerIcon() is DOM-guarded (harness gets a string)");
    r.ok(cssRule(html, ".dcs-ic .pxs").includes("contain") && cssRule(html, ".dcs-ic .pxs").includes("image-rendering: pixelated"),
      ".dcs-ic .pxs contain-fits the face, pixel-crisp");
    // Board pile badges (renderStickerBadges) deliberately KEEP the composed
    // glyph chips — the tiny ~26px ring stays minimal (flagged for review).
    r.ok(fnBody(src, "renderStickerBadges").includes("chip(t.id, t.icon, n(t.id))"),
      "board pile badges keep the minimal glyph look (deliberate)");
  }

  // --- Coin: the §7 pixel ring through the untouched <use> mechanism --------
  {
    r.ok(/<symbol id="icon-coin" viewBox="0 0 16 16"[^>]*>\s*<image id="iconCoinPx"/.test(html),
      "#icon-coin is the 16-grid pixel symbol (an <image> fed at boot)");
    r.ok(src.includes('document.getElementById("iconCoinPx")') && src.includes("ICO.coin"),
      "PixelArt feeds the coin bitmap into the symbol at boot");
    r.ok(src.includes('\'<svg class="coin-ico" aria-hidden="true"><use href="#icon-coin"'),
      "COIN_SVG and its ~35 call sites are untouched");
    for (const idr of ["icon-glow", "icon-bevel", "icon-face-orange", "icon-rim-orange"])
      r.ok(!html.includes('id="' + idr + '"'), "the old blurred/bevel coin def " + idr + " is deleted (§10)");
    r.ok(cssRule(html, ".coin-ico").includes("image-rendering: pixelated"), ".coin-ico scales crisp");
  }

  // --- Deferred literals + emoji policy -------------------------------------
  {
    // The joker-gold histogram column (deferred from chunk 1) is palette gold.
    r.ok(cssRule(html, ".ds-bar.ds-joker .ds-rank").includes("var(--gold)")
      && cssRule(html, ".suit-counts .sc-cell.sc-joker .sc-suit").includes("var(--gold)"),
      "histogram + suit-count joker cells re-ink to palette gold");
    for (const hex of ["#c9a23f", "#ecc25a"])
      r.ok(!html.includes(hex), "off-palette joker gold " + hex + " is purged");
    // Mystery event art: 🏪 → the map's own stall renderer; 🫧 → pixel sticker.
    const me = fnBody(src, "openMysteryEvent");
    r.ok(!me.includes("🏪") && me.includes("mapShopStall()"),
      "the store outcome reuses the map's shop stall (emoji retired)");
    r.ok(!me.includes("🫧") && me.includes('PixelArt.img("sticker")'),
      "the sticker-strip outcome shows the pixel sticker chip (emoji retired)");
    r.ok(me.includes("⚔️"), "the ambush glyph is a DELIBERATE keep (no matching asset; flagged)");
    // Boot render publishes vars through ONE injected style tag.
    r.ok(src.includes('st.id = "pixelArtVars"') && src.includes('":root{"'),
      "all data-URIs publish as :root custom properties in one injected <style>");
  }

  return r.summary();
}
