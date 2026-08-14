// MYST3 — mystery "?" node event UI wiring (source-contract suite in the
// holdhelp.test.mjs style: loadGame() proves the script still evaluates,
// fnBody/regex checks pin the wiring). MYST3 made mystery a FIRST-CLASS node
// type: the seeded event IS the node's entire content — there is no node
// underneath — and completeMystery (markNodeCleared + checkpoint + back to
// the map) is the single exit for EVERY continuation:
//  - the event fires on arrival ONLY when the node was hidden, and is applied +
//    checkpointed (persistCampaign("map") + flush) BEFORE the modal opens;
//  - the #mysteryEvent modal announces the outcome, then each interactive
//    outcome chains to its flow (removal picker / strip picker / placement walk
//    / pack reveal / ambush deal / store detour) — every one ending in
//    completeMystery, never an underlying-node dispatch;
//  - the ambush deal is a FORCED subset configured from items.js (never
//    hardcoded), its bounty rides the run's bonus channel, and a mid-ambush
//    refresh resumes through the standard run checkpoint;
//  - Stage B rendering: mapNodeInner owns the "?" art in every state (hidden /
//    revealed-open / cleared-spent), the t-myst class sticks in every state,
//    hidden nodes carry a debug-only seeded-outcome peek tag, hold-help/title
//    copy reads as a gamble, and the debug map-addr overlay has a NODE_HALF
//    mystery entry;
//  - MYST2 legacy: cursed CARDS are retired (no render branch survives); cursed
//    STICKERS wear the corrupted violet die-cut identity at every chip site;
//    every outcome has a mea-<key> animation variant + its own open sound;
//    the Home tooltip derives the start deck size (13 + startJokers) live.
// RULES/wiring only — every tunable stays in items.js.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadGame, makeRunner } from "./_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const html = readFileSync(join(HERE, "..", "index.html"), "utf8");

/** The single game <script> block (the one defining the engine modules). */
function gameScript(h) {
  const blocks = h.match(/<script>([\s\S]*?)<\/script>/g) || [];
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
  const { ItemData } = loadGame();
  const r = makeRunner("mystery-ui.test.mjs");
  const src = gameScript(html);
  const M = ItemData.mystery;

  // ── the trigger: arrival fires the event only for a hidden node ───────────
  {
    const res = fnBody(src, "resolveMapNode");
    r.ok(res.includes("playMysteryReveal(id, () => runMysteryEvent(node, id))"),
      "a hidden node's arrival routes through runMysteryEvent after the reveal");
    r.ok(/else finishResolveNode\(node, id\);/.test(res),
      "a normal (never-hidden) node still dispatches straight to finishResolveNode");
    // Revisits can't re-roll: nodeHidden flips false at revealNode, and the event
    // lives behind the wasHidden capture (already pinned by mystery-nodes tests).
    r.ok(res.indexOf("const wasHidden") < res.indexOf("campaign.moveToNode(id)"),
      "wasHidden is captured BEFORE the move (a revealed revisit rolls nothing)");
  }

  // ── runMysteryEvent: roll → apply → checkpoint → modal ────────────────────
  {
    const run = fnBody(src, "runMysteryEvent");
    r.ok(run.includes("campaign.rollMysteryEvent(id)") && run.includes("campaign.applyMysteryEvent(key, id)"),
      "the event is rolled and applied through the seeded campaign core");
    const applyAt = run.indexOf("applyMysteryEvent(key, id)");
    const persistAt = run.indexOf('persistCampaign("map")');
    const modalAt = run.indexOf("openMysteryEvent(d,");
    r.ok(applyAt !== -1 && persistAt > applyAt && modalAt > persistAt,
      'persistCampaign("map") lands at resolution, BEFORE the modal (exactly-once)');
    r.ok(run.includes("flushCampaignSave()"),
      "…and the checkpoint is flushed synchronously (a kill on the modal can't lose it)");
    r.ok(run.includes("if (!d) { completeMystery(id); return; }"),
      "an impossible outcome (null descriptor) just completes the mystery — nothing underneath");
    r.ok(fnBody(src, "completeMystery").includes("campaign.markNodeCleared(id)")
      && fnBody(src, "completeMystery").includes('persistCampaign("map")'),
      "completeMystery clears + checkpoints the node (the MYST3 single exit)");
  }

  // ── the #mysteryEvent modal (fossilDetail idiom, Continue-only) ───────────
  {
    r.ok(html.includes('class="fossil-detail mystery-event hidden" id="mysteryEvent"'),
      "the mystery event modal reuses the fossil-detail overlay idiom");
    r.ok(html.includes('id="mysteryEventGo"'), "…with a Continue button (no ✕ dismiss)");
    const open = fnBody(src, "openMysteryEvent");
    r.ok(open.includes("updateBoardMotion()"), "opening the modal pauses the board behind it");
    r.ok(fnBody(src, "closeMysteryEvent").includes("updateBoardMotion()"),
      "closing the modal re-evaluates board motion");
    r.ok(open.includes('classList.toggle("me-bad"'), "the panel tints by outcome polarity (good vs bad)");
    r.ok(open.includes("el.mysteryEventTitle.textContent") && open.includes("el.mysteryEventSub.textContent"),
      "outcome copy renders via textContent (never raw HTML)");
    const confirm = fnBody(src, "confirmMysteryEvent");
    r.ok(confirm.includes("mysteryEventContinue") && confirm.includes("closeMysteryEvent()"),
      "Continue consumes the one-shot continuation and closes");
    const ai = fnBody(src, "attachInput");
    r.ok(ai.includes("attachHoldHelp(el.mysteryEventArt"), "the outcome art holds for help");
    r.ok(fnBody(src, "hideProgressionMap").includes("closeMysteryEvent()"),
      "leaving the map sweeps the modal closed");
  }

  // ── every interactive outcome chains to its flow ──────────────────────────
  {
    const cont = fnBody(src, "continueMysteryEvent");
    r.ok(/d\.key === "freeRemoval"[\s\S]{0,80}openMapBlankRemove\(1,/.test(cont),
      "freeRemoval opens the choose-a-card-to-remove picker, then falls through");
    r.ok(/d\.key === "stickerStrip"[\s\S]{0,80}openMapStickerStrip\(/.test(cont),
      "stickerStrip opens the strip picker, then falls through");
    r.ok(cont.includes('placementSavePhase = "map"'),
      "…and the walk checkpoints the map, not the store (mid-walk refresh safety)");
    const spAt = cont.indexOf('d.key === "stickerPack"');
    const spBlock = cont.slice(spAt, cont.indexOf('d.key === "ambush"'));
    r.ok(spBlock.includes("placementWalk = true") && spBlock.includes("continuePendingPlacement()")
      && spBlock.includes("onPlacementQueueEmpty"),
      "stickerPack surfaces through the inventory → placement walk, then falls through");
    // WINDFALL1: the Windfall popup IS the cards reveal — the follow-up
    // openMapPackReveal double-popup is gone; cards completes like joker.
    r.ok(!cont.includes('d.key === "cards"') && !cont.includes("openMapPackReveal(d.cards"),
      "cards (Windfall) has NO second popup — it falls through to done()");
    r.ok(/d\.key === "ambush"[\s\S]{0,80}startAmbushDeal\(d, id\)/.test(cont),
      "ambush hands off to the forced-deal starter");
    r.ok(cont.includes("const done = () => completeMystery(id);") && /done\(\);\s*\/\/.*cards/.test(cont),
      "passive outcomes (cards / coins / curses) complete the mystery immediately");
  }

  // ── map card-grant reveal wears the Windfall presentation ────────────────
  {
    const open = fnBody(src, "openMapPackReveal");
    r.ok(open.includes("Sound.mapAdd()") && !open.includes("Sound.pack()"),
      "map card grants play the Windfall sting (mapAdd), not the pack tear");
    r.ok(!open.includes("staggerDealIn"),
      "…and the CSS flip stagger replaces the button deal-in");
    r.ok(src.includes('el.packReveal.classList.toggle("pack-show", st.mode === "show" || st.mode === "mystery")'),
      "show mode (and the mystery same-power reveal) stamps pack-show on the overlay");
    r.ok(fnBody(src, "closePackReveal").includes('classList.remove("pack-show")'),
      "…and close sweeps the class off again");
    r.ok(html.includes(".confirm-overlay.pack-show .pack-panel { border-top: 4px solid var(--good); }"),
      "pack-show carries the Windfall good-rim");
    r.ok(html.includes(".confirm-overlay.pack-show .pack-item .mini-card { animation: meaCardFlip"),
      "…and the same meaCardFlip beat as the Windfall popup");
    r.ok(/@media \(prefers-reduced-motion: reduce\) \{\s*\.confirm-overlay\.pack-show/.test(html),
      "…with reduced-motion killing the flip");
  }

  // ── freeRemoval: the removal picker carries the continuation ─────────────
  {
    r.ok(/function openMapBlankRemove\(count, onDone\)/.test(src),
      "openMapBlankRemove takes the mystery continuation");
    const confirm = fnBody(src, "confirmApplySticker");
    r.ok(confirm.includes("pendingMapRemovalDone"),
      "…consumed when the removal confirms");
    r.ok(fnBody(src, "closeStickerApply").includes("pendingMapRemovalDone"),
      "…and also when it's declined (✕ / backdrop) — the mystery completes either way");
  }

  // ── stickerStrip: the strip picker mode ───────────────────────────────────
  {
    const open = fnBody(src, "openMapStickerStrip");
    r.ok(open.includes('cardPickMode = "strip"'), "the strip picker reuses #stickerApplyModal in a strip mode");
    r.ok(open.includes("(c.stickers || []).length > 0"),
      "…opened only when some card carries a sticker (else the event fizzles)");
    // STKRB1: the eligibility rule is now ONE shared helper (grid render +
    // the targeted confirm update both read it).
    r.ok(/applyCardEligible = \(c\) =>\s*cardPickMode === "strip" \? \(c\.stickers \|\| \[\]\)\.length > 0/.test(src),
      "only stickered cards are enabled in the grid (one shared eligibility rule)");
    r.ok(fnBody(src, "renderStickerApplyCards").includes("applyCardEligible(")
      && fnBody(src, "updateApplyCardInPlace").includes("applyCardEligible("),
      "…the grid render AND the targeted confirm update share it");
    const confirm = fnBody(src, "confirmApplySticker");
    r.ok(confirm.includes("campaign.removeRandomStickerFrom(stripId)"),
      "confirm strips ONE random sticker through the campaign core");
    r.ok(confirm.includes('persistCampaign("map")'),
      "…and checkpoints the map on the tap");
    r.ok(confirm.includes("finishMysteryStrip()"),
      "confirm runs the continuation into completeMystery");
    // CLEANSE-FORCED: the strip can no longer be declined — ✕ is hidden in
    // strip mode, the backdrop tap is inert, and closeStickerApply refuses
    // strip mode outright (before any teardown). The only skip is the
    // no-stickers fizzle at open (pinned above).
    r.ok(fnBody(src, "stickerApplyChrome").includes('el.saClose.classList.toggle("hidden", cardPickMode === "strip")'),
      "…the ✕ is hidden in strip mode (no cancel affordance)");
    r.ok(/stickerApplyModal\.addEventListener\("click"[\s\S]{0,220}cardPickMode !== "strip"/.test(src),
      "…the backdrop tap is inert in strip mode");
    const close = fnBody(src, "closeStickerApply");
    const guardAt = close.indexOf('if (cardPickMode === "strip") return;');
    r.ok(guardAt !== -1 && guardAt < close.indexOf("applyGridGen++") && !close.includes("finishMysteryStrip()"),
      "…and the close path refuses strip mode FIRST (no teardown, no decline into completeMystery)");
  }

  // ── ambush: forced subset from items.js, bounty on the bonus channel ──────
  {
    const start = fnBody(src, "startAmbushDeal");
    r.ok(start.includes("d.ambush || ItemData.mystery.ambush"),
      "the ambush deal is configured from the descriptor / items.js (never hardcoded)");
    r.ok(start.includes("cards: cfg.cards") && start.includes("piles: cfg.piles") && start.includes("bounty: cfg.bounty"),
      "…cards/piles/bounty all ride the config");
    r.ok(!new RegExp("cards: " + M.ambush.cards + "[,\\s}]").test(start)
      && !new RegExp("piles: " + M.ambush.piles + "[,\\s}]").test(start),
      "…with no hardcoded mirror of the items.js numbers");
    r.ok(start.includes("hideProgressionMap()") && start.includes("startRun(undefined, undefined, {"),
      "the map drops and the deal rides the standard startRun path");

    const sr = fnBody(src.slice(src.indexOf("function startRun(seedOverride") - 9), "startRun");
    r.ok(sr.includes("subsetOverride && subsetOverride.forced"),
      "startRun recognizes a forced subset (fresh entry / resume)");
    r.ok(sr.includes("currentDealSubset && currentDealSubset.forced"),
      "…and re-forces from the live subset on a reshuffle (no override passed)");
    r.ok(sr.includes("forcedSpec.cards") && sr.includes("forcedSpec.piles"),
      "the forced fresh roll draws from the ambush spec, not the threshold logic");
    r.ok(sr.includes("forced: true") && sr.includes("ambush: forcedSpec.ambush || null"),
      "the forced subset + ambush ctx persist into dealSubset (mid-ambush refresh)");
    r.ok(sr.includes('persistCampaign("run")'),
      "…checkpointed as a run (the standard resume path covers the ambush)");

    const end = fnBody(src, "onRunEnd");
    r.ok(end.includes("run.bonusEvents.Ambush"),
      "a clear awards the bounty as an itemized bonus line (the eventBonus channel)");
    r.ok(end.includes("if (clearedNode && !wasAmbush) campaign.markNodeCleared(clearedNode.id)"),
      "the ambush win does NOT clear the mystery node (completeMystery owns that clear)");
    r.ok(end.includes("const runWon = !wasAmbush &&"),
      "…and can never count as the run-winning boss clear");
    r.ok(end.includes("if (!wasAmbush) persistCampaign(\"map\")"),
      "no map checkpoint after an ambush — a refresh replays the ambush deal");
    r.ok(end.includes("pendingAmbushNodeId = ambushInfo ? ambushInfo.nodeId : null"),
      "…the mystery's completion is queued for the summary's Continue");
    r.ok(end.includes("ambushDeal = null; pendingAmbushNodeId = null; currentDealSubset = null;"),
      "a loss drops the whole ambush context — incl. the forced subset (no stale re-force)");
    r.ok(fnBody(src, "startCampaign").includes("ambushDeal = null; pendingAmbushNodeId = null; currentDealSubset = null;"),
      "a fresh campaign also clears any leftover ambush context (quit mid-ambush)");

    const cc = fnBody(src, "continueCampaign");
    r.ok(cc.includes("pendingAmbushNodeId") && cc.includes("completeMystery(nid)"),
      "Continue after the ambush completes the mystery (the ambush WAS its content)");
    r.ok(!cc.slice(0, cc.indexOf("// After a won deal/boss")).includes("finishResolveNode"),
      "…never dispatching an underlying node (MYST3: there is none)");
  }

  // ── cursed CARDS are retired (MYST2): no render branch survives ──────────
  {
    r.ok(!fnBody(src, "miniCardHtml").includes("cursed"),
      "mini cards no longer render a cursed face (packs, pickers, inspector, pile fan)");
    r.ok(!fnBody(src, "paintFront").includes("cursed"),
      "the board face has no cursed tint branch");
    r.ok(!fnBody(src, "renderStickerBadges").includes("card.cursed"),
      "…and no innate-curse chip in the badge overlay");
    r.ok(!fnBody(src, "renderDeckReveal").includes("cursed"),
      "the Scout deck-reveal face has no cursed branch");
    r.ok(!fnBody(src, "cardPeekHtml").includes("cursed"),
      "hold-for-help has no innate-curse row");
    r.ok(!/mc-cursed|mc-curse|pb-curse|dsf-curse|pk-curse/.test(html),
      "the cursed card CSS/markup hooks are gone");
  }

  // ── debug peek (MYST2): the seeded outcome tag on hidden "?" nodes ───────
  {
    const rpm = fnBody(src, "renderProgressionMap");
    r.ok(rpm.includes("pm-myst-out") && rpm.includes("campaign.rollMysteryEvent(n.id)"),
      "a hidden node renders the seeded-outcome debug tag (rollMysteryEvent is pure)");
    r.ok(rpm.includes('<span class="pm-myst-out">\' + escHtml('),
      "…with its label through escHtml");
    r.ok(/body:not\(\.debug-access\) \.pm-myst-out \{ display:\s*none; \}/.test(html),
      "…CSS-gated to debug access (no re-render on toggle)");
    r.ok(/\.pm-myst-out \{/.test(html), "…and styled as the tiny violet tag under the ?");
  }

  // ── MYST3 Stage B: the "?" is the node's face in EVERY render state ──────
  {
    const inner = fnBody(src, "mapNodeInner");
    r.ok(/n\.type === "mystery"\)\s*return '<span class="mn-myst/.test(inner),
      "mapNodeInner has a first-class mystery case returning the mn-myst \"?\" art");
    r.ok(inner.includes('state === "here" ? " open" : ""'),
      "…a revealed-but-open mystery (arrived, outcome modal up) wears the .open state");
    r.ok(inner.indexOf('n.type === "mystery"') < inner.indexOf("mapPickupInner(n, state)"),
      "…and a mystery NEVER falls through to pickup art");
    const rpm = fnBody(src, "renderProgressionMap");
    r.ok(rpm.includes("t-' + (n.type === \"mystery\" ? \"myst\" : n.type)"),
      "the t-myst class sticks in every state (hidden / revealed / cleared)");
    r.ok(rpm.indexOf("mapNodeInner(n, suit, state)") !== -1
      && rpm.indexOf("pm-myst-out") > rpm.indexOf("mapNodeInner(n, suit, state)"),
      "the \"?\" art comes from mapNodeInner; the hidden branch only appends the peek");
    r.ok(/\.mn-myst\.open \{/.test(html) && /\.mn-myst\.open::after/.test(html),
      "the revealed-open \"?\" is styled (lit frame, solid inner border)");
    r.ok(/\.pm-node\.t-myst\.s-done \.mn-myst \{/.test(html),
      "a cleared mystery renders as a spent, muted-violet \"?\" (on the shared s-done fade)");
    const label = fnBody(src, "mapNodeLabel");
    r.ok(label.includes('n.type === "mystery"') && label.includes("a gamble, good or bad"),
      "mapNodeLabel names a mystery node (hold-help + title single source)");
    const ai = fnBody(src, "attachInput");
    r.ok(ai.includes('isMyst ? "Mystery" : "Map node"'),
      "hold-help titles a mystery node \"Mystery\" in every state (not just hidden)");
    r.ok(/mystery:\s*\[19, 24\]/.test(src),
      "the debug map-addr overlay has a NODE_HALF mystery entry (the mn-myst 38×48 half-box)");
  }

  // ── MYST3 Stage B: the map key's Mystery row resolves against a real node ─
  {
    const key = fnBody(src, "renderMapKey");
    r.ok(key.includes('const myst = live("mystery") || { type: "mystery" };'),
      "the map key's Mystery row resolves against a real first-class mystery node (genV ≥ 3), "
      + "degrading to a bare stand-in on maps with none (legacy genV < 3)");
    r.ok(key.includes('mapNodeInner(myst, null, "far")'),
      "…and draws the \"?\" through mapNodeInner's mystery case (one art source — never the open state)");
  }

  // ── MYST3: no stray legacy-mask references survive ─────────────────────────
  {
    // n.mystery (the genV < 3 cosmetic mask) is legitimate ONLY in: the legacy
    // mask roll (GEN_CONFIG.mysteryChance), the legacy joker unveil
    // (unveilJokerNodes), and the restore migration (mystMigrated). Everywhere
    // else mystery is the first-class TYPE.
    const occ = [...src.matchAll(/\bn\.mystery\b/g)]
      .map(m => src.slice(Math.max(0, m.index - 400), m.index + 60));
    r.ok(occ.length > 0, "the legacy n.mystery mask paths still exist (genV < 3 regen must keep working)");
    r.ok(occ.every(o => /mysteryChance|unveilJokerNodes|mystMigrated|MYST3 migration/.test(o)),
      "no stray n.mystery references outside the legacy regen / joker unveil / migration");
  }

  // ── store outcome (MYST2/MYST3): the detour → Done → completeMystery wiring
  {
    const cont = fnBody(src, "continueMysteryEvent");
    const stAt = cont.indexOf('d.key === "store"');
    const ssAt = cont.indexOf("showStore(false, id)");   // SEED1: the detour offer keys to the mystery node's id
    r.ok(stAt !== -1 && ssAt > stAt && ssAt < cont.indexOf("done();   // cards"),
      "the store outcome opens a full store visit on the spot (fresh=false — a saved offer survives)");
    r.ok(cont.includes("mysteryStoreContinue = () =>"),
      "…and arms the one-shot continuation for when the store closes");
    r.ok(/mysteryStoreContinue = \(\) => \{[\s\S]{0,120}completeMystery\(id\);/.test(cont),
      "…which completes the mystery (Done's type-guard clears only a REAL store node)");
    const ai = fnBody(src, "attachInput");
    const doneAt = ai.indexOf("storeStartBtn.addEventListener");
    const done = ai.slice(doneAt, doneAt + 1000);
    r.ok(done.includes('node.type === "store"'),
      "…Done still clears only a REAL store node (the mystery's clear rides the hook)");
    const persistAt = done.indexOf('persistCampaign("map")');
    r.ok(persistAt !== -1 && persistAt < done.indexOf("mysteryStoreContinue"),
      "…Done checkpoints the map BEFORE consuming the hook");
    r.ok(/= mysteryStoreContinue; mysteryStoreContinue = null;[\s\S]{0,120}mystHook\(\); return;/.test(done),
      "…the hook is one-shot (read + cleared before use)");
    r.ok(done.indexOf("showProgressionMap(startRun)") > done.indexOf("mystHook(); return;"),
      "…a normal store visit still returns to the map when no hook is armed");
    r.ok(fnBody(src, "showProgressionMap").includes("mysteryStoreContinue = null"),
      "reaching the map any other way drops an unconsumed hook (no leak across visits)");
  }

  // ── cursed sticker identity (MYST2): corrupted violet die-cut everywhere ─
  {
    const sc = fnBody(src, "stickerChip");
    r.ok(sc.includes("t.cursed") && sc.includes("dcs-cursed"),
      "stickerChip flags cursed types with the corruption class");
    r.ok(sc.includes("CURSE_VIOLET") && sc.includes("CURSE_EDGE"),
      "…with the curse-violet face + dark edge");
    // v5.70: the board badges no longer re-implement the cursed identity —
    // they render through stickerChip like every other chip surface, so the
    // curse face/edge/class (asserted above) reaches them by construction.
    // Verified live: a board-badge leech chip carries dcs-cursed, its per-id
    // art class, --dcs-face #7a4fd0 and --dcs-edge #46306e.
    const rsb = fnBody(src, "renderStickerBadges");
    r.ok(rsb.includes("stickerChip(id,"),
      "the board pile badges route through stickerChip (one cursed identity, one art source)");
    r.ok(!rsb.includes("dieCutChip("),
      "…and never build a chip directly (that path showed older art than the help popup)");
    r.ok(html.includes('const CURSE_VIOLET = "#7a4fd0"'),
      "the face is the established curse violet #7a4fd0");
    r.ok(/\.dcs\.dcs-cursed \{/.test(html) && /\.dcs\.dcs-cursed \.dcs-gloss/.test(html)
      && /\.dcs\.dcs-cursed \.dcs-ic/.test(html),
      "the corrupted-vinyl CSS exists (dark halo, corruption swirl, desaturated icon)");
  }

  // ── outcome presentation (MYST2): every key → animation variant + sound ──
  {
    const open = fnBody(src, "openMysteryEvent");
    const SOUNDS = {
      coinBonus: "coin", coinLoss: "coinLoss", cards: "mapAdd", joker: "deckUnlock",
      store: "refresh", stickerPack: "sticker", stickerStrip: "sticker",
      freeRemoval: "pack", cursedSticker: "bad", ambush: "deal",
    };
    r.ok(open.includes('"fd-art me-art mea-" + d.key'),
      "the art area carries the outcome's mea-<key> animation variant");
    r.ok(open.includes("MYSTERY_SOUND[d.key]") && open.includes("Sound[sfx]()"),
      "the mapped sound fires at modal open through the Sound module (self-gated on the pref)");
    Object.keys(SOUNDS).forEach(k => {
      r.ok(html.includes(".mea-" + k), k + ": a .me-art animation variant exists");
      r.ok(new RegExp(k + ': "' + SOUNDS[k] + '"').test(src), k + " → Sound." + SOUNDS[k]);
    });
    r.ok(!open.includes("Sound.pack()"), "…replacing the old one-size-fits-all pack sound");
    r.ok(/@media \(prefers-reduced-motion: reduce\) \{\s*\.mystery-event \.me-art/.test(html),
      "the outcome animations die under reduced motion");
    r.ok(open.includes("me-slam") && /\.me-slam \.dcs/.test(html),
      "cursedSticker slams the corrupted chip onto the afflicted mini card");
  }

  // ── Home tooltip (MYST2): derives the start deck size live ───────────────
  {
    const rpm = fnBody(src, "renderProgressionMap");
    r.ok(rpm.includes("RunMap.GEN_CONFIG.startDeckSize")
      && rpm.includes("DifficultyData.startJokers(campaign.getDeckId(), campaign.getTier())"),
      "the Home tooltip derives the start size (startDeckSize + startJokers) live");
    r.ok(!/'13 hearts'/.test(rpm) && !/'13 cards'/.test(rpm), "…never a hardcoded 13");
  }

  // ── copy: the hidden node now reads as a gamble ───────────────────────────
  {
    const GAMBLE = "??? — a gamble, good or bad, revealed when you arrive";
    r.ok(fnBody(src, "attachInput").includes(GAMBLE), "hidden-node hold-help reads as a gamble");
    r.ok(html.includes('title="\' + (hidden ? "' + GAMBLE + '"') || html.split(GAMBLE).length - 1 >= 2,
      "…and the node title attribute carries the same copy");
    r.ok(fnBody(src, "renderMapKey").includes("a gamble, good or bad, revealed when you arrive"),
      "the map key's Mystery row matches");
  }

  return r.summary();
}
