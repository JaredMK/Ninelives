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
// Part 2 is the debug "flat picker (A/B)" checkbox toggling body.perf-flat,
// whose CSS (scoped to #stickerApplyModal + the map pulses) strips the
// suspected iOS-compositor-expensive styling: backdrop blur, the .dcs-ic
// drop-shadow, the filter-animating saFlash/saRemove keyframes (swapped for
// opacity-only equivalents), and the pmPulseFade node pulses.
//
// Everything is debug-gated: with capture OFF each wrapper/mark is a single
// boolean check and no rAF is requested; with body.perf-flat absent no flat
// rule matches. This suite pins the mechanism behaviorally (through the real
// Perf module, reached via window.__perf) and the picker/DEBUG wiring
// structurally (the stubbed DOM can't drive the picker UI).
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
    Perf.pickerOpened("sticker");
    r.eq(rafCount, rafAtLoad + 1, "capture on: pickerOpened arms the sampler (exactly one rAF)");
    r.ok(Perf.sampling, "…the sampler reports active");
    Perf.mark("picker:firstPaint");
    Perf.mark("picker:gridFirstBatch");
    Perf.time("picker:selectCard", () => {});
    Perf.pickerClosed();
    r.ok(!Perf.sampling, "pickerClosed disarms the sampler");
    const open = Perf.entries.find(e => e.mark && e.stage === "picker:open");
    r.ok(!!open, "a picker:open journey mark was recorded");
    r.ok(open && open.ctx && "gapMax" in open.ctx && "gapMean" in open.ctx && "janky" in open.ctx,
      "…picker marks auto-attach the frame-gap context");
    const closed = Perf.entries.find(e => e.mark && e.stage === "picker:closed");
    r.ok(closed && closed.ctx && typeof closed.ctx.openMs === "number",
      "picker:closed carries the session length (openMs)");
    // A second open while capture is still on re-arms cleanly.
    Perf.pickerOpened("remove");
    r.eq(rafCount, rafAtLoad + 2, "a fresh picker open re-arms the sampler (one new rAF)");
    Perf.pickerClosed();
    Perf.setOn(false);
    r.ok(!Perf.sampling, "setOn(false) leaves the sampler disarmed");
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

  // --- Structural: debug panel markup + wiring (both toggles, the button) ----
  {
    r.ok(html.includes('id="debugPerfFlat"'), "flat-picker checkbox markup sits in the debug panel");
    r.ok(html.includes('id="debugPerfCopy"'), "copy-perf-report button markup sits in the debug panel");
    r.ok(src.includes('document.getElementById("debugPerfFlat")') && src.includes('document.getElementById("debugPerfCopy")'),
      "both controls are in the el refs");
    r.ok(src.includes('document.body.classList.toggle("perf-flat", el.debugPerfFlat.checked)'),
      "the checkbox wiring toggles body.perf-flat only");
    r.ok(src.includes("copySeed(Perf.dump(), el.debugPerfCopy)"),
      "the button copies Perf.dump() through copySeed (WKWebView clipboard fallback)");
  }

  // --- Structural: body.perf-flat CSS is scoped + flat-only ------------------
  {
    r.ok(html.includes("body.perf-flat #stickerApplyModal.deck-modal")
      && /body\.perf-flat #stickerApplyModal\.deck-modal \{[^}]*backdrop-filter: none;\s*-webkit-backdrop-filter: none;/.test(html),
      "flat CSS kills the picker backdrop blur (prefixed + unprefixed)");
    r.ok(html.includes("body.perf-flat #stickerApplyModal .dcs-ic { filter: none; }"),
      "flat CSS kills the sticker-icon drop-shadow inside the picker");
    r.ok(/body\.perf-flat #stickerApplyModal \.sa-card\.sa-flash \.mini-card \{ animation-name: saFlashFlat; \}/.test(html)
      && /body\.perf-flat #stickerApplyModal \.sa-card\.sa-remove \.mini-card \{ animation-name: saRemoveFlat; \}/.test(html),
      "flat CSS swaps saFlash/saRemove for opacity-only keyframes");
    r.ok(html.includes("@keyframes saFlashFlat") && html.includes("@keyframes saRemoveFlat"),
      "…the opacity-only keyframes are defined (base animations untouched)");
    r.ok(html.includes("body.perf-flat .pm-node.s-legal::after")
      && html.includes("body.perf-flat .pm-node.s-here::after"),
      "flat CSS pauses the map-node pulse animations");
    // Every flat rule is gated on body.perf-flat (nothing leaks into normal play):
    // the selectors above all carry the prefix, and the base rules are unmodified.
    r.ok(!/\.perf-flat[^{]*\{[^}]*backdrop-filter: blur/.test(html),
      "no flat rule re-introduces a blur");
  }

  return r.summary();
}
