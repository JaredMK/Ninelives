// SEED1 — shareable run seeds + the exhibition rule.
//
// A run's whole content derives from its 32-bit runSeed, keyed by STABLE
// identifiers (node id, reroll/reshuffle index, action counter) — never by
// Math.random call order. These tests pin the RULES:
//   • SeedCode: a u32 ↔ 7-char base32 code, strict decode (length/chars/overflow).
//   • Two campaigns built from the SAME entered seed (+ deck + tier) produce the
//     identical map, mystery outcomes, store offers, pack contents and deal
//     substreams — and alt-deck start rolls (suits, Smith stickers, Lammy prefill).
//   • Visit ORDER is irrelevant: store A's offer is identical whether or not
//     store B was opened first (the offer keys to the node, not the sequence).
//   • The seeded pregen path builds with the entered seed (no silent swap).
//   • EXHIBITION: a player-entered seed flags the run (isExhibition) — it
//     checkpoints normally (runSeed + exhibition survive serialize→restore) but
//     every progression credit gates on the flag (structural pins on the
//     onRunEnd / runPlayed / Telem call sites — the app-scope flow the Node
//     harness can't drive directly).
// Values are never pinned (a data retune must not break the suite) — only
// EQUALITY between two same-seed runs, and the codec's own contract.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadGame, makeRunner } from "./_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

function gameSource() {
  const html = readFileSync(join(HERE, "..", "index.html"), "utf8");
  const blocks = html.match(/<script>([\s\S]*?)<\/script>/g) || [];
  return blocks
    .map((b) => b.replace(/^<script>/, "").replace(/<\/script>$/, ""))
    .find((c) => c.includes("const GameEngine")) || "";
}

/** A seeded campaign pair (same seed/deck/tier), freshly reset. */
function seededPair(seed, deck = "pink", tier = "regular") {
  const g = loadGame();
  const a = g.CampaignState.create();
  a.setDeck(deck); a.setTier(tier); a.setSeedOverride(seed); a.reset();
  const b = g.CampaignState.create();
  b.setDeck(deck); b.setTier(tier); b.setSeedOverride(seed); b.reset();
  return { g, a, b };
}

/** Structural map signature: ids, types, adds, pack counts, suits, mystery flags. */
function mapSig(c) {
  return JSON.stringify(c.getMap().nodes.map(n =>
    [n.id, n.type, n.add || 0, n.packCount || 0, n.suit || "", !!n.mystery, n.piles || 0]));
}

/** Offer signature WITHOUT minted card ids (nextCardId legitimately differs once
    another roll has minted) — content equality only. */
function offerSig(offer) {
  return JSON.stringify((offer.slots || []).map(s => !s ? null : [
    s.kind, s.id,
    s.card ? [s.card.suit, s.card.currentRank, !!s.card.joker, !!s.card.blank,
      (s.card.stickers || []).map(x => x.type)] : 0,
  ])) + "|" + offer.rerollCost;
}

/** Granted-card signature (suit/rank/flags/stickers — not ids). */
function cardsSig(cards) {
  return JSON.stringify(cards.map(c => [c.suit, c.currentRank, !!c.joker, !!c.blank,
    (c.stickers || []).map(x => x.type)]));
}

export function run() {
  const r = makeRunner("seeds.test.mjs");
  const { SeedCode, CampaignState } = loadGame();

  // ── SeedCode: round-trip + strict decode ────────────────────────────────
  {
    const seeds = [0, 1, 42, 12345, 0xDEADBEEF, 0xFFFFFFFF, 0x80000000];
    let allRound = true;
    for (const s of seeds) {
      const code = SeedCode.encode(s);
      if (code.length !== 7 || SeedCode.decode(code) !== (s >>> 0)) allRound = false;
    }
    r.ok(allRound, "encode→decode round-trips across the u32 range (incl. 0 and 0xFFFFFFFF)");
    r.eq(SeedCode.encode(0), "AAAAAAA", "seed 0 encodes as the alphabet's zero char ×7");
    r.eq(SeedCode.decode("AAAAAAA"), 0, "…and decodes back");
    r.eq(SeedCode.decode(SeedCode.encode(12345).toLowerCase()), 12345, "decode is case-insensitive");
    r.eq(SeedCode.decode("  " + SeedCode.encode(12345) + " "), 12345, "decode trims whitespace");
    r.eq(SeedCode.decode("AAAAAA"), null, "rejects a short code");
    r.eq(SeedCode.decode("AAAAAAAA"), null, "rejects a long code");
    r.eq(SeedCode.decode("AAAA0AA"), null, "rejects a char outside the alphabet (0)");
    r.eq(SeedCode.decode("AAAAOAA"), null, "rejects a char outside the alphabet (O)");
    r.eq(SeedCode.decode("AAAAIAA"), null, "rejects a char outside the alphabet (I)");
    r.eq(SeedCode.decode("ZZZZZZZ"), null, "rejects a 35-bit value that overflows u32");
    r.eq(SeedCode.decode(""), null, "rejects empty");
    r.eq(SeedCode.decode(null), null, "rejects non-strings");
  }

  // ── Same seed → identical map + mystery outcomes ────────────────────────
  {
    const { a, b } = seededPair(12345);
    r.eq(a.getRunSeed(), 12345, "the entered seed becomes the run seed");
    r.ok(a.isExhibition() && b.isExhibition(), "a player-entered seed flags the run exhibition");
    r.eq(mapSig(a), mapSig(b), "same seed → identical map (ids/types/adds/packs/suits)");
    const allMyst = a.getMap().nodes.every(n => a.rollMysteryEvent(n.id) === b.rollMysteryEvent(n.id));
    r.ok(allMyst, "same seed → identical mystery outcome per node");
    const dealNode = a.getMap().nodes.find(n => n.type === "deal" || n.type === "boss");
    const draw = (c) => { const rng = c.runRng("deal", dealNode.id, 0); return Math.floor(rng() * 0x100000000) >>> 0; };
    r.ok(draw(a) === draw(b), "same seed → identical deal seed for the same node");
    const again = a.runRng("deal", dealNode.id, 0);
    const first = again(), second = a.runRng("deal", dealNode.id, 1)();
    r.ok(first !== second, "…and a reshuffle (index 1) steps to a different board");
  }

  // ── Store offers key to the NODE, not visit order ───────────────────────
  {
    const { a, b } = seededPair(12345);
    const stores = a.getMap().nodes.filter(n => n.type === "store");
    r.ok(stores.length >= 2, "the map has at least two store nodes to order against");
    const [sA, sB] = stores;
    // Campaign A: open store A directly. Campaign B: open store B FIRST, then A.
    const offerA1 = a.openStore(a.runRng("store", sA.id));
    b.openStore(b.runRng("store", sB.id));
    const offerA2 = b.openStore(b.runRng("store", sA.id));
    r.eq(offerSig(offerA1), offerSig(offerA2), "store A's offer is unchanged when store B was visited first");
    // Rerolls continue the same deterministic sequence on both (keyed via nodePos).
    // Snapshot the original shelf's signature FIRST — the offer object is live
    // (rerollStore mutates it in place).
    const sigBefore = offerSig(a.getStoreOffer());
    a.moveToNode(sA.id); b.moveToNode(sA.id);
    a.addCoins(1000); b.addCoins(1000);
    r.ok(a.rerollStore() && b.rerollStore(), "a reroll is affordable after funding");
    r.eq(offerSig(a.getStoreOffer()), offerSig(b.getStoreOffer()), "same seed → identical rerolled offer for the same node");
    r.ok(sigBefore !== offerSig(a.getStoreOffer()), "…and the reroll actually changes the shelf");
  }

  // ── Sealed map packs: identical contents for the same node ──────────────
  {
    const { a, b } = seededPair(12345);
    const sealed = a.getMap().nodes.find(n => n.type === "pack" && (n.packCount || 3) !== 2);
    r.ok(!!sealed, "the map has a sealed (3+) pack node");
    if (sealed) {
      const bNode = b.getNode(sealed.id);
      const cardsA = a.resolvePack(sealed);
      const cardsB = b.resolvePack(bNode);
      r.eq(cardsA.length, cardsB.length, "same pack node → same card count");
      r.eq(cardsSig(cardsA), cardsSig(cardsB), "same pack node → identical contents");
    }
    // A store pack buy keys to (node, slot) — same draw on both campaigns.
    const cardA = a.revealPack("smallCardPack", a.runRng("storepack", 7, 2));
    const cardB = b.revealPack("smallCardPack", b.runRng("storepack", 7, 2));
    r.ok(Array.isArray(cardA) && cardA.length === cardB.length
      && cardsSig(cardA) === cardsSig(cardB), "store pack contents key to (store node, slot)");
  }

  // ── Alt-deck start rolls key to the seed ────────────────────────────────
  {
    const { a: m1, b: m2 } = seededPair(777, "mamma");
    r.eq(JSON.stringify(m1.serialize().ownedIds), JSON.stringify(m2.serialize().ownedIds),
      "mamma: same seed → identical alt-suit start deck");
    const { a: s1, b: s2 } = seededPair(777, "smith");
    const stick = (c) => JSON.stringify(c.serialize().baseDeck
      .filter(x => x.stickers.length).map(x => [x.id, x.stickers.map(t => t.type)]));
    r.eq(stick(s1), stick(s2), "smith: same seed → identical start stickers");
    const { a: l1, b: l2 } = seededPair(777, "lammy");
    r.eq(JSON.stringify(l1.serialize().columnPillars), JSON.stringify(l2.serialize().columnPillars),
      "lammy: same seed → identical pillar prefill");
    r.eq(JSON.stringify(l1.serialize().columnBases), JSON.stringify(l2.serialize().columnBases),
      "lammy: same seed → identical base prefill");
    // Different seeds → different start rolls (at least one of map/deck differs).
    const g = loadGame();
    const d1 = g.CampaignState.create(); d1.setDeck("mamma"); d1.setTier("regular"); d1.setSeedOverride(1); d1.reset();
    const d2 = g.CampaignState.create(); d2.setDeck("mamma"); d2.setTier("regular"); d2.setSeedOverride(2); d2.reset();
    r.ok(mapSig(d1) !== mapSig(d2)
      || JSON.stringify(d1.serialize().ownedIds) !== JSON.stringify(d2.serialize().ownedIds),
      "different seeds → a different run");
  }

  // ── Seeded pregen: builds with the ENTERED seed, never swaps ────────────
  {
    const { a } = seededPair(12345);
    const g = loadGame();
    const p = g.CampaignState.create();
    p.setDeck("pink"); p.setTier("regular");
    r.ok(p.pregenerateRun("pink", "regular", 12345), "a seeded pregen starts");
    p._pregenDrain();   // the harness has no idle callbacks — drive the chunks
    p.setSeedOverride(12345); p.reset();
    r.eq(p.getRunSeed(), 12345, "Start on a seeded pregen keeps the entered seed");
    r.eq(mapSig(p), mapSig(a), "…and the map matches a synchronously built same-seed run");
    // A seedless pregen entry never leaks into a seeded run (distinct keys).
    const q = g.CampaignState.create();
    q.setDeck("pink"); q.setTier("regular");
    q.pregenerateRun("pink", "regular"); q._pregenDrain();
    q.setSeedOverride(12345); q.reset();
    r.eq(q.getRunSeed(), 12345, "a seedless pregen can't hijack a seeded Start");
    r.eq(mapSig(q), mapSig(a), "…the seeded run still builds from the entered seed");
  }

  // ── Save/restore: runSeed + exhibition + actionCounter ──────────────────
  {
    const { g, a } = seededPair(12345);
    a.actRng(); a.actRng();   // move the action stream
    const wire = JSON.parse(JSON.stringify(a.serialize()));
    const c = g.CampaignState.create();
    r.ok(c.restore(wire), "a seeded save restores");
    r.eq(c.getRunSeed(), 12345, "…keeping the run seed");
    r.ok(c.isExhibition(), "…keeping the exhibition flag");
    r.ok(c.serialize().actionCounter === wire.actionCounter && wire.actionCounter >= 2,
      "…keeping the action-stream position");
    // Legacy saves (no seed fields) restore as NORMAL banked runs.
    delete wire.exhibition; delete wire.actionCounter;
    const d = g.CampaignState.create();
    r.ok(d.restore(wire), "a pre-SEED1 save restores");
    r.ok(!d.isExhibition(), "…defaulting to a normal (non-exhibition) run");
    r.eq(d.serialize().actionCounter, 0, "…defaulting the action stream to 0");
    // A restored exhibition run regenerates the identical map.
    const { a: fresh } = seededPair(12345);
    r.eq(mapSig(c), mapSig(fresh), "a restored seeded run's map is identical to a fresh one");
  }

  // ── Seed override is one-shot; normal runs stay unflagged ───────────────
  {
    const g = loadGame();
    const c = g.CampaignState.create();
    c.setDeck("pink"); c.setTier("regular");
    r.ok(!c.isExhibition(), "a fresh (seedless) campaign is not exhibition");
    c.setSeedOverride(999); c.reset();
    r.ok(c.isExhibition() && c.getRunSeed() === 999, "the override lands on the next run");
    c.reset();   // consumed — a later reset mints fresh
    r.ok(!c.isExhibition(), "…and is consumed once (the next run is normal again)");
  }

  // ── EXHIBITION gates (structural): every progression credit is guarded ──
  // The gate SITES live in the app-scope flow (onRunEnd, the first-guess
  // runPlayed, store telemetry) the Node harness can't drive — pin the guards
  // at source level (the stklag2 idiom): each Stats/DeckUnlocks/Telem credit
  // must sit behind the exhibition flag.
  {
    const src = gameSource();
    r.ok(src.includes("if (!exhibition) Stats.addDeal("), "onRunEnd: lifetime deal tally gated");
    r.ok(src.includes("if (!exhibition) Stats.runCleared("), "onRunEnd: run-cleared stat gated");
    r.ok(src.includes("!exhibition) Stats.endlessReached("), "onRunEnd: endless-depth stat gated");
    r.ok(src.includes("if (!exhibition) Stats.addCardsFlipped(campaign.unbankedCardsFlipped())"),
      "onRunEnd: endless-death flip tally gated");
    // The whole win-bank block (markRunWon → recordDeckWin → DeckUnlocks) sits
    // under one exhibition guard.
    const bankGuard = src.indexOf("if (!exhibition) {\n      campaign.markRunWon();");
    r.ok(bankGuard !== -1, "onRunEnd: the win-bank block (markRunWon / recordDeckWin / DeckUnlocks) is gated");
    r.ok(bankGuard !== -1 && src.indexOf("Stats.recordDeckWin(", bankGuard) !== -1,
      "…recordDeckWin inside the gated block");
    r.ok(bankGuard !== -1 && src.indexOf("DeckUnlocks.recordWin(", bankGuard) !== -1,
      "…DeckUnlocks.recordWin inside the gated block");
    r.ok(src.includes("if (!(campaign.isExhibition && campaign.isExhibition())) Stats.runPlayed();"),
      "first-guess runPlayed gated");
    // Every Telem.purchase call site is exhibition-guarded (playtest data stays clean).
    const purchases = src.match(/Telem\.purchase\(/g) || [];
    const guarded = src.match(/if \(!campaign\.isExhibition\(\)\) \{[^}]*Telem\.purchase\(/g) || [];
    r.ok(purchases.length > 0 && purchases.length === guarded.length,
      "all " + purchases.length + " Telem.purchase sites gated");
  }

  // ── UI pins (source-contract — the app scope isn't reachable from Node) ──
  // The stklag2 idiom: pin the wiring, never the pixels. Behaviorally eval the
  // two pure-ish helpers (runSeedShareStr / copySeed) by extracting their
  // function text and feeding stubs — everything else is a structural pin.
  {
    const src = gameSource();
    const html = readFileSync(join(HERE, "..", "index.html"), "utf8");
    /** Full text of a top-level `function name(...) { ... }` (brace-matched). */
    const fnFull = (name) => {
      const at = src.indexOf("function " + name + "(");
      if (at === -1) return "";
      const open = src.indexOf("{", at);
      let depth = 0;
      for (let i = open; i < src.length; i++) {
        if (src[i] === "{") depth++;
        else if (src[i] === "}" && --depth === 0) return src.slice(at, i + 1);
      }
      return "";
    };

    // Deck-select entry: one shared control OUTSIDE the swipe carousel.
    r.ok(html.includes('id="dsSeedToggle"') && html.includes("Have a seed?"),
      "deck select carries the 'Have a seed?' toggle");
    const inputTag = (html.match(/<input[^>]*id="dsSeedInput"[^>]*>/) || [""])[0];
    r.ok(!!inputTag, "…with a seed code input");
    r.ok(/maxlength="7"/.test(inputTag), "…capped at 7 characters");
    r.ok(/autocapitalize="off"/.test(inputTag) && /autocorrect="off"/.test(inputTag)
      && /spellcheck="false"/.test(inputTag) && /inputmode=/.test(inputTag),
      "…phone-friendly (no autocapitalize/autocorrect/spellcheck)");
    r.ok(html.indexOf('id="dsDots"') !== -1 && html.indexOf('id="dsSeed"') > html.indexOf('id="dsDots"'),
      "…the control sits below the carousel/dots (never inside the swipe track)");
    const attach = fnFull("attachInput");
    r.ok(attach.includes('dsSeedToggle.addEventListener("click"')
      && attach.includes('dsSeedInput.addEventListener("input"'),
      "…its listeners attach ONCE at boot (persistent elements, not per-render)");
    r.ok(attach.includes("schedulePregen();") && attach.includes("updateSeedNote();"),
      "…typing re-validates and re-kicks the browsing pregen");

    // Validation + Start + pregen threading.
    const noteFn = fnFull("updateSeedNote");
    r.ok(noteFn.includes("Seeded run — progression disabled"), "a valid code shows the exhibition label");
    r.ok(noteFn.includes("dsEnteredSeed()") && fnFull("dsEnteredSeed").includes("SeedCode.decode"),
      "…validation rides SeedCode.decode via dsEnteredSeed (no parallel alphabet)");
    r.ok(src.includes("startCampaign(dsEnteredSeed())"),
      "Start passes the decoded seed (undefined/invalid = a normal run)");
    r.ok(src.includes("pregenerateRun(sel.deck, sel.tier, dsEnteredSeed())"),
      "the browsing pregen re-keys on the entered seed (deck/tier/seed changes share one path)");
    r.ok(fnFull("showDeckSelect").includes("resetSeedEntry()"),
      "the control resets on every deck-select entry");

    // Pause-menu seed row (campaign only).
    r.ok(html.includes('id="gameMenuSeed"'), "the pause menu has a seed-row container above the buttons");
    const menuFn = fnFull("showGameMenu");
    r.ok(menuFn.includes("runSeedShareStr()") && menuFn.includes("!zenMode"),
      "showGameMenu renders the seed row for campaign runs only (Zen hides it)");
    r.ok(menuFn.includes("isExhibition()") && menuFn.includes("seed-tag"),
      "…with the exhibition tag when the run's seed was player-entered");
    r.ok(menuFn.includes("escHtml(SeedCode.encode(campaign.getRunSeed()))"),
      "…rendering the live SeedCode through escHtml");
    r.ok(attach.includes('gameMenuSeed.addEventListener("click"') && attach.includes("copySeed(share, el.gameMenuSeed)"),
      "…tap-to-copy wired at boot");

    // Win/loss overlay seed section.
    const ovFn = fnFull("showOverlay");
    r.ok(ovFn.includes("opts.seed") && ovFn.includes('classList.toggle("hidden", !opts.seed)'),
      "showOverlay renders opts.seed and hides the section without it");
    r.ok(ovFn.includes("escHtml(opts.seed)"), "…escaped on render");
    r.ok(fnFull("showPinkyHome").includes("seed: runSeedShareStr()"),
      "the victory screen passes the share seed");
    r.ok(fnFull("showCampaignFailed").includes("seed: runSeedShareStr()"),
      "the loss screen passes the share seed");
    r.ok(attach.includes('overlaySeed.addEventListener("click"')
      && attach.includes('overlaySeed.addEventListener("pointerdown"'),
      "…overlay row copies on tap and swallows pointerdown (no peek interference)");

    // Debug panel seed line.
    r.ok(html.includes('id="debugSeed"'), "the debug panel carries a seed line");
    const dbgFn = fnFull("refreshDebug");
    r.ok(dbgFn.includes("debugSeed") && dbgFn.includes("runSeedShareStr()") && dbgFn.includes('"—"'),
      "refreshDebug shows the share string (— when no campaign run is active)");

    // Share-string format — behavioral (extract + eval with stubs).
    {
      const shareSrc = fnFull("runSeedShareStr");
      r.ok(shareSrc.length > 0, "runSeedShareStr exists");
      const mk = new Function("campaign", "zenMode", "DECKS", "DifficultyData", "SeedCode",
        "return " + shareSrc + ";");
      const share = mk(
        { getRunSeed: () => 12345, getDeckId: () => "pink", getTier: () => "regular" },
        false,
        [{ id: "pink", name: "Pinky" }],
        { tier: () => ({ label: "Regular" }) },
        SeedCode);
      r.eq(share(), "PINKY-REGULAR-" + SeedCode.encode(12345),
        "share string = DECK-TIER-CODE (deck + tier labels uppercased, SeedCode of the run seed)");
      const smith = mk(
        { getRunSeed: () => 12345, getDeckId: () => "smith", getTier: () => "master" },
        false,
        [{ id: "smith", name: "Mr. Smith" }],
        { tier: () => ({ label: "Master" }) },
        SeedCode);
      r.eq(smith(), "MRSMITH-MASTER-" + SeedCode.encode(12345),
        "…labels squash to A–Z0–9 (no spaces/punctuation in the code string)");
      const zen = mk({ getRunSeed: () => 1, getDeckId: () => "pink", getTier: () => "regular" },
        true, [{ id: "pink", name: "Pinky" }], { tier: () => ({ label: "Regular" }) }, SeedCode);
      r.eq(zen(), null, "…null in Zen (no run seed by design)");
    }

    // copySeed — behavioral: clipboard API path + textarea/execCommand fallback.
    {
      const copySrc = fnFull("copySeed");
      r.ok(copySrc.includes("navigator.clipboard.writeText"), "copySeed prefers the async clipboard API");
      r.ok(copySrc.includes('execCommand("copy")') && copySrc.includes('createElement("textarea")'),
        "…with a hidden-textarea execCommand fallback");
      const mk = new Function("navigator", "document", "setTimeout", "clearTimeout",
        "let copyFlashTimer = 0;\n" + copySrc + "\nreturn copySeed;");
      const elmStub = () => ({
        classes: [],
        classList: { add(c) { this.owner.classes.push(c); }, remove() {} },
        querySelector: () => null,
      });
      // Fallback path: no clipboard API → textarea + execCommand("copy").
      let execed = null; const ta = { value: "", style: {}, setAttribute() {}, select() {}, remove() {} };
      const docStub = {
        createElement: (tag) => { docStub.tag = tag; return ta; },
        body: { appendChild(x) { docStub.appended = x; } },
        execCommand: (cmd) => { execed = cmd; return true; },
      };
      const copyLegacy = mk({}, docStub, () => 1, () => {});
      const elm1 = elmStub(); elm1.classList.owner = elm1;
      copyLegacy("PINKY-REGULAR-AAAAAAA", elm1);
      r.ok(docStub.tag === "textarea" && docStub.appended === ta
        && ta.value === "PINKY-REGULAR-AAAAAAA" && execed === "copy",
        "no clipboard API → the fallback copies the exact string via execCommand");
      r.ok(elm1.classes.indexOf("copied") !== -1, "…and the tapped element flashes 'copied'");
      // Clipboard path: writeText resolves → no textarea, flash still fires.
      let wrote = null;
      const copyModern = mk(
        { clipboard: { writeText: (s) => { wrote = s; return { then: (ok) => ok() }; } } },
        docStub, () => 1, () => {});
      const elm2 = elmStub(); elm2.classList.owner = elm2;
      copyModern("PINKY-REGULAR-AAAAAAA", elm2);
      r.ok(wrote === "PINKY-REGULAR-AAAAAAA" && elm2.classes.indexOf("copied") !== -1,
        "clipboard API path writes the string and flashes");
    }
  }

  return r.summary();
}
