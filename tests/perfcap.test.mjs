// PERFCAP — on-device perf capture for the sticker-apply picker lag that only
// reproduces on the real iPhone (desktop profiling is clean).
//
// Part 1 extends the (debug-only) Perf module: (a) the entries ring is now
// CAPPED (PERF_CAP + PERF_SLACK batch splice, the pushLog LOG_CAP pattern) so
// a long capture can't grow without bound; (b) journey marks (Perf.mark /
// markAfterPaint) with an auto-attached context snapshot (deck size, applied
// sticker count, frame-gap stats) across the picker journey — open → first
// paint → grid first batch / stream drain → selection paint → apply done →
// closed; (c) a FRAME-GAP SAMPLER (WKWebView never fires "longtask") — an
// armed-only-while-the-picker-is-open rAF loop measuring per-frame gaps into
// a rolling window (max / mean / >100ms "janky" count), self-terminating on
// the modal's hidden class so EVERY close path disarms it (NOT a second game
// clock — it dies with the modal); (d) Perf.dump(), a paste-friendly text
// report copied by a new debug-panel button via copySeed.
//
// Part 2 is RETIRED (PERFFIX2, v5.14): the debug "flat picker (A/B)" toggle
// A/B'd the deck-modal backdrop blur on-device, and the blur was convicted —
// blur-on produced 2.9-15 SECOND main-thread freezes at a 72-card picker
// (taps queueing and firing all at once), blur-off was clean. The blur is
// permanently removed from .deck-modal and the toggle is gone. The other
// PERFFIX fixes stay: background animators pause under any open deck-modal
// (body:has(.deck-modal:not(.hidden)) + animation-play-state), the
// saFlash/saRemove keyframes are filter-free, and the picker chip-icon
// drop-shadow is off in the .sa-lite scope.
//
// Everything is debug-gated: with capture OFF each wrapper/mark is a single
// boolean check and no rAF is requested. This suite pins the mechanism
// behaviorally (through the real Perf module, reached via window.__perf) and
// the picker/DEBUG wiring structurally (the stubbed DOM can't drive the
// picker UI).
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

export function run() {
  const r = makeRunner("perfcap.test.mjs");
  const html = fullHtml();
  const src = gameScript(html);
  const sink = { log() {}, info() {}, warn() {}, error() {} };   // swallow [perf] console lines

  // --- Behavioral: Perf reachable + ring cap --------------------------------
  {
    const g = loadGame({ console: sink });
    const Perf = g.Perf;
    r.ok(!!Perf, "Perf is reachable in the harness (via window.__perf)");
    r.ok(typeof Perf.PERF_CAP === "number" && Perf.PERF_CAP > 0
      && typeof Perf.PERF_SLACK === "number" && Perf.PERF_SLACK > 0,
      "PERF_CAP / PERF_SLACK are exposed for tests");
    Perf.setOn(true);
    const N = Perf.PERF_CAP + Perf.PERF_SLACK + 120;
    for (let i = 0; i < N; i++) Perf.time("t" + (i % 7), () => i);
    r.ok(Perf.entries.length <= Perf.PERF_CAP + Perf.PERF_SLACK,
      `ring stays capped after ${N} timings (${Perf.entries.length} <= CAP+SLACK)`);
    r.ok(Perf.entries.length >= Perf.PERF_CAP,
      "…and keeps the newest entries (trims in slack batches, not per append)");
    Perf.setOn(false);
  }

  // --- Behavioral: capture OFF — passthrough, no entries, no sampler rAF ----
  {
    let rafCount = 0;
    const g = loadGame({ console: sink, requestAnimationFrame: () => { rafCount++; return 0; } });
    const Perf = g.Perf;
    const rafAtLoad = rafCount;   // the game's own boot may schedule rAFs
    const before = Perf.entries.length;
    const v = Perf.time("offpath", () => 42);
    r.eq(v, 42, "capture off: a wrapped call passes its return value straight through");
    r.eq(Perf.entries.length, before, "…and records no entry");
    Perf.mark("picker:open");
    Perf.markAfterPaint("picker:selectPaint");
    r.eq(Perf.entries.length, before, "…and mark/markAfterPaint are no-ops");
    r.eq(rafCount, rafAtLoad, "…and request NO rAF (no sampler, no paint mark)");
    Perf.pickerOpened("sticker");
    r.eq(rafCount, rafAtLoad, "…pickerOpened with capture off arms no sampler rAF");
    r.ok(!Perf.sampling, "…the sampler stays inactive");
    Perf.setOn(false);
  }

  // --- Behavioral: capture ON — session marks, sampler arm/disarm, context --
  {
    let rafCount = 0;
    const g = loadGame({ console: sink, requestAnimationFrame: () => { rafCount++; return 0; } });
    const Perf = g.Perf;
    const rafAtLoad = rafCount;
    Perf.setOn(true);
    r.eq(rafCount, rafAtLoad + 1, "capture on arms the ambient gap sampler (one rAF)");
    r.ok(Perf.ambient, "…the ambient sampler reports active");
    Perf.pickerOpened("sticker");
    r.eq(rafCount, rafAtLoad + 2, "pickerOpened swaps ambient for the picker sampler (one new rAF)");
    r.ok(Perf.sampling, "…the picker sampler reports active");
    r.ok(!Perf.ambient, "…and the ambient sampler pauses while the picker is open");
    Perf.mark("picker:firstPaint");
    Perf.mark("picker:gridFirstBatch");
    Perf.time("picker:selectCard", () => {});
    Perf.pickerClosed();
    r.ok(!Perf.sampling, "pickerClosed disarms the picker sampler");
    r.ok(Perf.ambient, "…and the ambient sampler resumes");
    const open = Perf.entries.find(e => e.mark && e.stage === "picker:open");
    r.ok(!!open, "a picker:open journey mark was recorded");
    r.ok(open && open.ctx && "gapMax" in open.ctx && "gapMean" in open.ctx && "janky" in open.ctx,
      "…picker marks auto-attach the frame-gap context");
    const closed = Perf.entries.find(e => e.mark && e.stage === "picker:closed");
    r.ok(closed && closed.ctx && typeof closed.ctx.openMs === "number",
      "picker:closed carries the session length (openMs)");
    // A second open while capture is still on re-arms cleanly.
    Perf.pickerOpened("remove");
    r.eq(rafCount, rafAtLoad + 4, "a fresh picker open re-arms cleanly (ambient resume + session arm)");
    Perf.pickerClosed();
    Perf.setOn(false);
    r.ok(!Perf.sampling && !Perf.ambient, "setOn(false) disarms both samplers");
  }

  // --- Behavioral: dump() ----------------------------------------------------
  {
    const g = loadGame({ console: sink });
    const Perf = g.Perf;
    Perf.setOn(true);
    Perf.pickerOpened("sticker");
    Perf.mark("picker:firstPaint");
    Perf.mark("picker:gridFirstBatch");
    Perf.time("picker:selectCard", () => {});
    Perf.pickerClosed();
    const d = Perf.dump();
    r.ok(typeof d === "string" && d.length > 0, "dump() returns a string");
    r.ok(d.includes("ua:") && d.includes("capture:"), "…with the UA + capture header");
    r.ok(d.includes("picker:open") && d.includes("picker:firstPaint") && d.includes("picker:closed"),
      "…listing the journey marks in order");
    r.ok(d.includes("-- journeys --") && d.includes("-- timings"),
      "…with the journeys and timings sections");
    r.ok(d.includes("-- ambient (all screens) --"),
      "…with the ambient all-screens gap section (THERMAL1)");
    const m = d.match(/entries (\d+)\/(\d+)/);
    r.ok(!!m && +m[1] <= +m[2], "the header entry count never exceeds PERF_CAP (slack is hidden)");
    Perf.setOn(false);
  }

  // --- Structural: the ring + sampler mechanism ------------------------------
  {
    r.ok(/PERF_CAP = \d+, PERF_SLACK = \d+/.test(src), "PERF_CAP/PERF_SLACK constants declared");
    r.ok(src.includes("entries.splice(0, entries.length - PERF_CAP)"),
      "the ring trims back to PERF_CAP in slack batches (pushLog pattern)");
    r.ok(src.includes('el.stickerApplyModal.classList.contains("hidden")'),
      "the sampler self-terminates on the modal's hidden class (covers every close path)");
    r.ok(!/setInterval/.test(src.slice(src.indexOf("const Perf = "), src.indexOf("window.__perf"))),
      "no setInterval inside the Perf module (one-animation-clock invariant)");
  }

  // --- Structural: the wrap block covers the picker journey ------------------
  {
    const wrapBlock = src.slice(src.indexOf("const wrap = (name, fn)"), src.indexOf("return { init };"));
    r.ok(wrapBlock.includes('openStickerApply = wrapOpen("sticker:openPicker", "sticker", openStickerApply)'),
      "openStickerApply rides the open-picker wrapper");
    for (const [fn, kind] of [["openStoreRemoval", "removal"], ["openCardRemove", "remove"],
                              ["openCardSwap", "swap"], ["openMapStickerStrip", "strip"]]) {
      r.ok(wrapBlock.includes(fn + " = wrapOpen(") && wrapBlock.includes('"' + kind + '"'),
        fn + " rides the open-picker wrapper (kind " + kind + ")");
    }
    for (const line of ['selectApplyCard = wrap("picker:selectCard"',
                        'updateApplyCardInPlace = wrap("picker:updateCardInPlace"',
                        'dissolveApplyCard = wrap("picker:dissolveCard"',
                        'drainApplyGrid = wrap("picker:drainGrid"',
                        'deferConfirmTail = wrap("picker:deferConfirmTail"']) {
      r.ok(wrapBlock.includes(line), "wrap block: " + line.split(" = ")[0] + " wrapped");
    }
    r.ok(wrapBlock.includes("Perf.pickerClosed()") && wrapBlock.includes('Perf.time("picker:close"'),
      "closeStickerApply is wrapped and ends the picker session");
    r.ok(wrapBlock.includes("DeckInspector.renderCompositionInto = wrap("),
      "DeckInspector.renderCompositionInto wrapped via property reassignment (not a declaration)");
    r.ok(wrapBlock.includes('Perf.mark("picker:firstPaint")'),
      "the open wrapper schedules the first-paint mark");
  }

  // --- Structural: journey marks live at the real sub-stage sites ------------
  {
    r.ok(src.includes('Perf.mark("picker:gridFirstBatch")'), "grid first-batch mark after replaceChildren");
    r.ok(src.includes('Perf.mark("picker:gridStreamed")'), "grid stream-drained mark in the rAF chunk stream");
    r.ok(src.includes('Perf.mark("picker:gridDrained")'), "grid drained mark in drainApplyGrid");
    r.ok(src.includes('Perf.markAfterPaint("picker:selectPaint")'), "selection-paint mark after refreshApplySelection");
    r.ok(src.includes('Perf.mark("picker:applyDone")'), "apply-done mark after the apply mutation + save");
  }

  // --- Structural: debug panel markup + wiring (the button) ------------------
  {
    r.ok(html.includes('id="debugPerfCopy"'), "copy-perf-report button markup sits in the debug panel");
    r.ok(src.includes('document.getElementById("debugPerfCopy")'), "the button is in the el refs");
    r.ok(src.includes("copySeed(Perf.dump(), el.debugPerfCopy)"),
      "the button copies Perf.dump() through copySeed (WKWebView clipboard fallback)");
    // perf-flat is RETIRED (PERFFIX2): the A/B convicted the blur, the blur is
    // gone from .deck-modal, and the toggle has no job left.
    r.ok(!html.includes("debugPerfFlat") && !html.includes("perf-flat"),
      "the perf-flat A/B toggle is fully retired (markup, refs, wiring, CSS)");
  }

  // --- Structural: full-viewport backdrop blur is BANNED (PERFFIX2) ----------
  {
    const modal = html.match(/\.deck-modal \{[\s\S]*?\n  \}/);
    const body = modal ? modal[0].replace(/\/\*[\s\S]*?\*\//g, "") : "";   // strip the explanatory comment
    r.ok(!!modal && !body.includes("backdrop-filter"),
      ".deck-modal carries NO backdrop-filter (the on-device 2.9-15s freeze cause)");
  }

  // --- Structural: PERFFIX permanent fixes -----------------------------------
  {
    // Background animators pause whenever ANY deck-modal covers them (:has(),
    // self-syncing across every open/close path — no JS hook, no stranded state).
    const pauses = html.match(/body:has\(\.deck-modal:not\(\.hidden\)\)[^{]*\{[^}]*animation-play-state: paused/g) || [];
    r.ok(pauses.length > 0, "PERFFIX: deck-modal-open pause rules exist (animation-play-state: paused)");
    const paused = pauses.join("\n");
    for (const sel of [".pm-node.s-legal::after", ".pm-node.s-here::after", ".map-avatar",
                       ".map-avatar .av-body", ".map-avatar .av-face",
                       ".hud .hud-same.charged", ".cph-banner.activatable",
                       ".deck-stack.revealed", ".ds-deckchar .dc-face", ".ds-deckchar .dc-pupil"])
      r.ok(paused.includes(sel), "PERFFIX: pause list covers " + sel);
    // Confirm-window keyframes must never animate `filter` (per-frame software
    // repaint of the card region — the measured 200-390ms apply frames).
    const flash = html.match(/@keyframes saFlash \{[\s\S]*?\n  \}/);
    const remove = html.match(/@keyframes saRemove \{[\s\S]*?\n  \}/);
    r.ok(!!flash && !flash[0].includes("filter"), "saFlash keyframes are filter-free");
    r.ok(!!remove && !remove[0].includes("filter"), "saRemove keyframes are filter-free");
    // The picker grid is vinyl-flattened — no filter survives on its chips.
    r.ok(html.includes(".sa-lite .dcs-ic { filter: none; }"),
      "the picker chip-icon drop-shadow is permanently off (.sa-lite scope)");
  }

  // --- Structural: THERMAL1 — box-shadow pulses are compositor crossfades ----
  {
    r.ok(!html.includes("@keyframes sameChargePulse") && !html.includes("@keyframes pillarActivatable"),
      "the box-shadow-pulsing keyframes are gone (paint-per-frame is banned for always-on FX)");
    const charge = html.match(/@keyframes sameChargeFade \{[^}]*\}/);
    const pillar = html.match(/@keyframes pillarActiveFade \{[^}]*\}/);
    r.ok(!!charge && charge[0].includes("opacity") && !charge[0].includes("box-shadow"),
      "sameChargeFade is an opacity crossfade");
    r.ok(!!pillar && pillar[0].includes("opacity") && !pillar[0].includes("box-shadow"),
      "pillarActiveFade is an opacity crossfade");
    r.ok(/\.hud \.hud-same\.charged::after \{[^}]*pointer-events: none;[^}]*animation: sameChargeFade/.test(html),
      "the HUD Same charge glow rides a ::after layer with the crossfade");
    r.ok(/\.cph-banner\.activatable::before \{[^}]*pointer-events: none;[^}]*animation: pillarActiveFade/.test(html),
      "the pillar activatable ring rides a ::before layer with the crossfade");
    r.ok(html.includes(".hud .hud-same.charged::after { animation: none; content: none; }")
      && html.includes(".cph-banner.activatable::before { animation: none; content: none; }"),
      "reduced-motion kills both crossfades");
    r.ok(!/\.pm-node\.s-(legal|here)::after[^}]*will-change/.test(html),
      "no blanket will-change on the map pulse pseudo-layers");
  }

  // --- Structural: THERMAL2 — last filter loop killed + stall attribution ----
  {
    r.ok(!html.includes("@keyframes deckPeekGlow"),
      "the deck-peek drop-shadow filter loop is gone (filter animation banned for always-on FX)");
    const peek = html.match(/@keyframes deckPeekFade \{[^}]*\}/);
    r.ok(!!peek && peek[0].includes("opacity") && !peek[0].includes("filter") && !peek[0].includes("box-shadow"),
      "deckPeekFade is an opacity crossfade");
    r.ok(/\.deck-stack\.revealed::after \{[^}]*pointer-events: none;[^}]*animation: deckPeekFade/.test(html),
      "the peek glow rides a ::after halo layer with the crossfade");
    // Stall attribution: journey context carries the picker kind + the screen
    // underneath, the ambient worst-list carries the screen, and the two
    // previously unwrapped heavy paths around select/close are timed.
    r.ok(src.includes("kind: pickerSession ? pickerSession.kind : null") && src.includes("under: currentUnder()"),
      "journey context stamps the picker kind + the screen underneath");
    r.ok(src.includes('bits.push("over " + e.ctx.under)'),
      "the dump prints the screen underneath each picker mark");
    r.ok(src.includes('wrap("ui:actionBar", showActionBar)') && src.includes('wrap("deck:renderStrip", renderDeckStrip)'),
      "showActionBar + renderDeckStrip are wrapped (the unwrapped gap around the stalls)");
  }

  // --- Structural: THERMAL3 — XL-lite picker at big decks --------------------
  {
    // On-device mechanism (user-observed + dump-correlated): at 80+ card decks
    // the full-styled picker grid exhausts iOS layer backing store — icons and
    // deck art turn TRANSPARENT and taps queue for seconds while tiles
    // re-rasterize. XL-lite drops the per-tile raster (18px-blur shadow,
    // border, per-card grayscale filter) at SA_XLITE_DECK+ cards.
    r.ok(/const SA_XLITE_DECK = \d+;/.test(src), "SA_XLITE_DECK threshold declared by the picker internals");
    r.ok(src.includes('el.saCards.classList.toggle("sa-xlite", cards.length >= SA_XLITE_DECK)'),
      "renderStickerApplyCards toggles sa-xlite by deck size");
    r.ok(/\.sa-xlite \.mini-card \{ box-shadow: none; border: none; \}/.test(html),
      "xl-lite tiles drop the 18px-blur shadow + border");
    r.ok(/\.sa-xlite \.sa-card\.sa-disabled \{ filter: none; \}/.test(html),
      "xl-lite disabled cards dim without a per-card grayscale filter layer");
    r.ok(src.includes('document.getElementsByTagName("*").length') && src.includes('bits.push("dom " + e.ctx.dom)'),
      "journey context + dump carry the DOM node count (layer-pressure correlation)");
  }

  // --- Structural: THERMAL4 — background flattens under deck-modals ----------
  {
    // The Xcode-app Web Inspector recording convicted the compositor: 21.6s of
    // 104s in composite records (style+layout+paint < 4s combined), 550-800ms
    // frames with ~zero recorded work, 1-2.4s composite spikes — per-frame
    // texture eviction/re-upload thrash at the backing-store cliff. The fix:
    // no box-shadow / no filter outside the modal subtree while any deck-modal
    // is open (frees the big textures; the 0.7 scrim hides the flat look).
    const gate = "body:has(.deck-modal:not(.hidden)) body > :not(.deck-modal)";
    r.ok(html.includes(gate + ",") && html.includes(gate + " * {"),
      "THERMAL4: background-flatten rules exist under the deck-modal :has() gate (container + descendants)");
    const flatBlock = html.slice(html.indexOf(gate + ","));
    const decl = flatBlock.slice(0, flatBlock.indexOf("}"));
    r.ok(decl.includes("box-shadow: none !important"), "…background box-shadows are killed while a deck-modal is open");
    r.ok(decl.includes("filter: none !important"), "…background filters are killed while a deck-modal is open");
    r.ok(!/body:has\(\.deck-modal:not\(\.hidden\)\) \.deck-modal/.test(html),
      "…the modal subtree itself is NOT flattened");
    // The ambient haze layer (THERMAL5: ONE radial-gradient layer now, still an
    // infinite drift) joins the pause list.
    const pauses = html.match(/body:has\(\.deck-modal:not\(\.hidden\)\)[^{]*\{[^}]*animation-play-state: paused/g) || [];
    r.ok(pauses.join("\n").includes("#tissue .haze"),
      "…#tissue .haze pauses under deck-modals (pause-list contract)");
  }

  return r.summary();
}
