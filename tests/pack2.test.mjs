// PACK2 — REVEALED +2 map packs: a pack node worth exactly 2 cards commits
// BOTH exact cards at map generation (the +1-node shown == granted contract)
// and shows them face-up; sealed "+N hidden" packs remain only for 3+ stops.
//   R1 generation-time commit (deterministic per (runSeed, node.id, slot))
//   R2 specials: a slot may lock a Blank, NEVER a random Joker; 3+ unchanged
//   R3 reservation: committed pack cards are spoken for run-wide
//   R5 resolution grants EXACTLY the committed pair (no fresh roll)
//   R6 packCards persists (additive key); legacy saves re-commit stably
//   R7 type/route accounting untouched; debug jump grants the committed pair
//   R4/R8 rendering + map key (source-shape checks — the map is DOM-only)
// Registry-driven: pack sizes come from the LIVE RunMap.GEN_CONFIG.packWeights
// (never pinned); tier ids come from the LIVE difficulty.js table.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadGame, makeRunner } from "./_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

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
  const r = makeRunner("pack2.test.mjs");
  const { CampaignState, RunMap } = loadGame();

  // LIVE registries — never pin the tunables themselves.
  const packWeights = RunMap.GEN_CONFIG.packWeights;
  const rolls2 = packWeights.some((w) => w[0] === 2);   // can generation even mint +2 packs?
  const tierIds = Object.keys(
    new Function(readFileSync(join(HERE, "..", "difficulty.js"), "utf8") + ";return NINELIVES_DIFFICULTY.tiers;")()
  );
  r.ok(tierIds.length >= 1, "difficulty.js tier table read live (" + tierIds.join(", ") + ")");

  const twoPacks = (c) => c.getMap().nodes.filter((n) => n.type === "pack" && n.packCount === 2);
  const bigPacks = (c) => c.getMap().nodes.filter((n) => n.type === "pack" && (n.packCount || 3) >= 3);

  // ---- R1/R2/R3: generation-time commit across decks × tiers ---------------
  if (rolls2) {
    const combos = [["pink", 0], ["mamma", 1], ["smith", tierIds.length - 1], ["lammy", 0]];
    let seen2 = 0, seen3 = 0, badPair = 0, badSuit = 0, sealedCommitted = 0, dupIds = 0, ownedClash = 0, altSlots = 0;
    const altSuitsSeen = new Set();
    for (const [deck, ti] of combos) {
      const c = CampaignState.create();
      c.setDeck(deck); c.setTier(tierIds[ti % tierIds.length]);
      c._setMapSpecialRoll(() => null);   // normal-card contract (specials below)
      c.reset();
      const wire = c.serialize();
      const alt = c.deckRules().altSuits;
      const claimed = new Set(wire.ownedIds);
      const addClaim = (id) => { if (typeof id !== "number") return; if (claimed.has(id)) dupIds++; claimed.add(id); };
      for (const k in wire.nodeCards) addClaim(wire.nodeCards[k]);
      for (const n of twoPacks(c)) {
        seen2++;
        const pair = wire.packCards[n.id];
        const cards = c.packNodeCards(n);
        if (!Array.isArray(pair) || pair.length !== 2 || !cards || cards.length !== 2) { badPair++; continue; }
        pair.forEach((id) => { if (wire.ownedIds.indexOf(id) !== -1) ownedClash++; addClaim(id); });
        for (const card of cards) {
          if (alt) { altSlots++; altSuitsSeen.add(card.suit); }
          else if (typeof n.phase === "number" && n.phase < c.phasesTotal() && card.suit !== n.suit) badSuit++;
        }
      }
      for (const n of bigPacks(c)) { seen3++; if (wire.packCards[n.id] != null) sealedCommitted++; }
      // Re-reads are pure: the committed pair never re-rolls on a second look.
      r.eq(JSON.stringify(c.serialize().packCards), JSON.stringify(wire.packCards),
        deck + ": a second read returns the identical committed pairs");
    }
    r.ok(seen2 > 0, "the sweep met +2 packs to check (" + seen2 + " across " + combos.length + " campaigns)");
    r.eq(badPair, 0, "every +2 pack committed exactly 2 display cards at generation");
    r.eq(sealedCommitted, 0, "no 3+ pack ever commits (stays sealed; " + seen3 + " checked)");
    r.eq(badSuit, 0, "stage-suit rule: committed cards match the pack node's suit (non-alt decks)");
    r.eq(dupIds, 0, "no card id is committed to two nodes (pickups + packs disjoint)");
    r.eq(ownedClash, 0, "no committed pack card is already owned");
    r.ok(altSlots === 0 || altSuitsSeen.size >= (altSlots >= 24 ? 4 : 2),
      "alt-suit decks roll pack slots across suits (" + [...altSuitsSeen].join("") + " over " + altSlots + " slots)");
  } else {
    r.ok(true, "packWeights has no +2 entry — revealed-pack generation checks skipped (registry-driven)");
  }

  // ---- R5: resolving grants EXACTLY the committed pair ---------------------
  if (rolls2) {
    let c = null, pk = null;
    for (let i = 0; i < 8 && !pk; i++) {
      c = CampaignState.create();
      c._setMapSpecialRoll(() => null);
      c.reset();
      pk = twoPacks(c)[0] || null;
    }
    r.ok(!!pk, "found a +2 pack within the reset sweep");
    if (pk) {
      const committed = c.serialize().packCards[pk.id].slice();
      const before = c.deckSize();
      const cards = c.resolvePack(pk);
      r.eq(cards.length, 2, "resolving the revealed pack returns its 2 cards");
      r.ok(cards.every((card, i) => card.id === committed[i]),
        "the granted cards are EXACTLY the committed (displayed) pair, in slot order");
      r.eq(c.deckSize(), before + 2, "the deck grew by exactly the two shown cards");
      r.ok(committed.every((id) => c.getRunDeck().some((x) => x.id === id)), "both committed cards joined the run deck");
      // A cleared pack keeps its committed faces (display parity with pickups).
      c.markNodeCleared(pk.id);
      const wire = JSON.parse(JSON.stringify(c.serialize()));
      const c2 = CampaignState.create();
      r.ok(c2.restore(wire), "a save with a resolved 2-pack restores");
      const shown = c2.packNodeCards(pk);
      r.ok(shown && shown.length === 2 && shown.every((x, i) => x.id === committed[i]),
        "the CLEARED pack still displays its granted pair after restore");

      // R3: no other grant source can hand out a still-displayed card.
      const c3 = CampaignState.create();
      c3._setMapSpecialRoll(() => null);
      c3.reset();
      const w3 = c3.serialize();
      const reserved = new Set();
      for (const k in w3.packCards) w3.packCards[k].forEach((id) => { if (typeof id === "number") reserved.add(id); });
      r.ok(reserved.size > 0, "reservation sweep has committed pack cards to protect (" + reserved.size + ")");
      let leaks = 0;
      const suits = ["♦", "♣", "♠", "♥"];
      for (let i = 0; i < 8; i++)
        for (const card of c3.resolvePack({ type: "pack", packCount: 4, suit: suits[i % 4] }))
          if (!card.blank && reserved.has(card.id)) leaks++;
      for (let i = 0; i < 6; i++) {
        const card = c3.resolvePickup({ id: 970000 + i, type: "pickup", suit: suits[i % 4] });
        if (card && !card.blank && !card.joker && reserved.has(card.id)) leaks++;
      }
      r.eq(leaks, 0, "no pack/pickup roll ever grants a card a revealed 2-pack displays");
    }
  }

  // ---- R6: serialize/restore round-trip + legacy re-commit ------------------
  if (rolls2) {
    let c = null;
    for (let i = 0; i < 8; i++) {   // PRODUCTION special rule (no hook) — legacy re-commit must match it
      c = CampaignState.create();
      if (twoPacks(c).length) break;
      c.startNewRun();
    }
    const wire = JSON.parse(JSON.stringify(c.serialize()));
    r.ok(Object.keys(wire.packCards).length > 0, "packCards persists in the save blob");
    const c2 = CampaignState.create();
    r.ok(c2.restore(wire), "the save restores");
    r.eq(JSON.stringify(c2.serialize().packCards), JSON.stringify(wire.packCards),
      "packCards round-trips exactly (restore == save)");
    // LEGACY save (key absent): un-cleared 2-packs re-commit DETERMINISTICALLY
    // in the restore lock pass (two restores of the same blob agree — the
    // pairs may differ from the pre-upgrade generation, since the restored
    // baseDeck already holds any minted duplicates and the pools shifted; a
    // pre-PACK2 client never displayed pack contents, so nothing shown is
    // betrayed) and stay stable across a second save/load cycle.
    const legacy = JSON.parse(JSON.stringify(wire));
    delete legacy.packCards;
    const c3 = CampaignState.create();
    r.ok(c3.restore(legacy), "a legacy save (no packCards key) restores");
    const p3 = c3.serialize().packCards;
    r.ok(Object.keys(wire.packCards).every((k) => Array.isArray(p3[k]) && p3[k].length === 2),
      "every un-cleared 2-pack re-committed a 2-slot pair on legacy restore");
    const c3b = CampaignState.create();
    r.ok(c3b.restore(JSON.parse(JSON.stringify(legacy))), "the same legacy blob restores again");
    r.eq(JSON.stringify(c3b.serialize().packCards), JSON.stringify(p3),
      "legacy re-commit is DETERMINISTIC (two restores of one blob agree)");
    const c4 = CampaignState.create();
    r.ok(c4.restore(JSON.parse(JSON.stringify(c3.serialize()))), "…and a second save/load cycle restores");
    r.eq(JSON.stringify(c4.serialize().packCards), JSON.stringify(p3),
      "…with the identical pairs (stable across cycles — the key now persists)");
    // LEGACY + CLEARED: an already-granted 2-pack can't be reconstructed — it
    // is skipped (no phantom reservation), everything else still commits.
    const someId = Number(Object.keys(wire.packCards)[0]);
    const legacy2 = JSON.parse(JSON.stringify(wire));
    delete legacy2.packCards;
    legacy2.clearedNodes = (legacy2.clearedNodes || []).concat([someId]);
    const c5 = CampaignState.create();
    r.ok(c5.restore(legacy2), "a legacy save with a CLEARED 2-pack restores");
    const p5 = c5.serialize().packCards;
    r.ok(p5[someId] == null, "the cleared legacy 2-pack is NOT re-committed (its grant is gone)");
    r.ok(Object.keys(wire.packCards).filter((k) => Number(k) !== someId).every((k) => Array.isArray(p5[k]) && p5[k].length === 2),
      "…while every other 2-pack still re-commits its pair");
  }

  // ---- R2: specials — a slot can lock a Blank, NEVER a Joker ----------------
  if (rolls2) {
    let cB = null, hasPack = false;
    for (let i = 0; i < 8 && !hasPack; i++) {
      cB = CampaignState.create();
      cB._setMapSpecialRoll(() => false);   // every special roll → Blank
      cB.reset();
      hasPack = twoPacks(cB).length > 0;
    }
    r.ok(hasPack, "found a +2 pack for the Blank-lock sweep");
    if (hasPack) {
      const wire = cB.serialize();
      const allB = Object.keys(wire.packCards).every((k) => wire.packCards[k].every((id) => id === "B"));
      r.ok(allB, 'with the roll pinned to Blank, every committed slot locks the "B" sentinel');
      const pk = twoPacks(cB)[0];
      const shown = cB.packNodeCards(pk);
      r.ok(shown.every((x) => x.blank), "…displayed as ∅ Removal faces");
      const before = cB.deckSize();
      const cards = cB.resolvePack(pk);
      r.ok(cards.length === 2 && cards.every((x) => x.blank), "resolving returns both Blank markers");
      r.eq(cB.deckSize(), before, "a committed Blank adds NOTHING to the deck (a removal, never owned)");
      r.ok(!cB.getRunDeck().some((x) => x.blank), "no Blank ever enters the run deck");
    }
    // Joker: even with the TEST hook pinned to the Joker outcome, a 2-pack
    // slot never locks one (the +1-node allowJoker=false rule) — it falls
    // through to a normal card, while 3+ packs still roll Jokers at resolution.
    const cJ = CampaignState.create();
    cJ._setMapSpecialRoll(() => true);
    cJ.reset();
    const wireJ = cJ.serialize();
    const noJ = Object.keys(wireJ.packCards).every((k) => wireJ.packCards[k].every((id) => typeof id === "number"));
    r.ok(noJ, "with the roll pinned to Joker, 2-pack slots STILL lock only normal cards (never \"J\")");
    const jCards = cJ.resolvePack({ type: "pack", packCount: 3, suit: "♦" });
    r.ok(jCards.length === 3 && jCards.every((x) => x.joker), "3+ packs keep their resolution-time Joker odds (hook pinned)");
    cJ._setMapSpecialRoll(() => false);
    const bCards = cJ.resolvePack({ type: "pack", packCount: 3, suit: "♦" });
    r.ok(bCards.every((x) => x.blank), "…and Blank odds (byte-identical sealed-pack behavior)");
  }

  // ---- R7: endless extension commits (cached base pairs untouched) ---------
  if (rolls2) {
    const c = CampaignState.create();
    c._setMapSpecialRoll(() => null);
    c.reset();
    const basePairs = JSON.stringify(c.serialize().packCards);
    c.startEndless();   // regenerates the run with an extra stage on top
    const after = c.serialize().packCards;
    r.eq(JSON.stringify(Object.fromEntries(Object.entries(after).filter(([k]) => JSON.parse(basePairs)[k] != null))), basePairs,
      "same-seed regeneration (endless extend) keeps every base-stage pair identical (cached)");
    const endless2 = twoPacks(c).filter((n) => typeof n.phase === "number" && n.phase >= c.phasesTotal());
    r.ok(endless2.every((n) => Array.isArray(after[n.id]) && after[n.id].length === 2),
      "every ENDLESS-stage +2 pack commits its pair at stage extension (" + endless2.length + " found)");
  }

  // ---- R7: debug jump grants the committed pair -----------------------------
  if (rolls2) {
    let c = null, pk = null, target = null;
    for (let i = 0; i < 10 && !target; i++) {
      c = CampaignState.create();
      c._setMapSpecialRoll(() => null);
      c.reset();
      const m = c.getMap();
      for (const n of twoPacks(c)) {
        const rowNodes = m.nodes.filter((x) => x.row === n.row);
        const draft = rowNodes.find((x) => x.type === "pickup" || x.type === "pack");
        const above = m.nodes.find((x) => x.row === n.row + 1);
        if (draft && draft.id === n.id && above) { pk = n; target = above; break; }
      }
    }
    r.ok(!!target, "found a jumpable row whose draft grant is a +2 pack");
    if (target) {
      const pair = c.serialize().packCards[pk.id].filter((id) => typeof id === "number");
      r.ok(c.debugJumpToNode(target.id), "debug jump crosses the pack's row");
      r.ok(pair.every((id) => c.getRunDeck().some((x) => x.id === id)),
        "the jump granted the pack's COMMITTED cards (shown == granted, even on a jump)");
    }
  }

  // ---- R4/R8: rendering + map key (source-shape — map markup is DOM-only) ---
  {
    const src = gameScript(readFileSync(join(HERE, "..", "index.html"), "utf8"));
    const inner = fnBody(src, "mapNodeInner");
    r.ok(inner.includes("packNodeCards") && inner.includes("mn-pack2"),
      "mapNodeInner renders a committed pack as the mn-pack2 face-up pair");
    r.ok(/nodeCardHtml\(pair\[0\]\) \+ nodeCardHtml\(pair\[1\]\)/.test(inner),
      "…both faces reuse the EXACT single-card markup (nodeCardHtml)");
    r.ok(inner.includes("mapPackStack(n)"), "…and 3+/uncommitted packs keep the sealed stack");
    r.ok(!/mpk-badge/.test(fnBody(src, "mapNodeInner")), "the revealed pair carries no +N badge (badge lives only in mapPackStack)");
    const html = readFileSync(join(HERE, "..", "index.html"), "utf8");
    r.ok(/\.mn-pack2 \{/.test(html) && /\.mn-pack2 \.node-card/.test(html), ".mn-pack2 CSS fans the pair in the node footprint");
    const label = fnBody(src, "mapNodeLabel");
    r.ok(label.includes('"2 cards — "') && label.includes("Removal"),
      "mapNodeLabel names the two committed cards (Blank slot reads Removal)");
    // MYSTERY hiding is upstream of mapNodeInner: the "?" swap still gates it
    // (MYST2: the hidden branch also carries the debug-only .pm-myst-out peek
    // tag — mapNodeInner must stay exclusively in the revealed branch).
    const hideSwap = /\(hidden\s*\?([\s\S]{0,400}?):\s*mapNodeInner\(n, suit, state\)/.exec(src);
    r.ok(!!hideSwap && hideSwap[1].includes('<span class="mn-myst">?</span>')
      && hideSwap[1].includes("pm-myst-out") && hideSwap[1].indexOf("mapNodeInner") === -1,
      'an un-arrived mystery still hides the pair behind "?" (reveal re-renders the faces)');
    const fin = fnBody(src, "finishResolveNode");
    const revealedAt = fin.indexOf("packNodeCards(node)");
    const modalAt = fin.indexOf("openMapPackReveal(");
    r.ok(revealedAt !== -1 && modalAt !== -1 && revealedAt < modalAt,
      "finishResolveNode branches on the committed pair BEFORE the sealed reveal modal");
    const branch = fin.slice(revealedAt, modalAt);
    for (const call of ["flashDeckGain(", "Sound.mapAdd()", "avatarCollect(", "openMapBlankRemove(", "return;"]) {
      r.ok(branch.includes(call), "revealed-pack arrival keeps the +1 pickup convention: " + call);
    }
    const key = fnBody(src, "renderMapKey");
    r.ok(/type === "pack" && \(n\.packCount \|\| 3\) >= 3/.test(key),
      "the map-key Pack exemplar is a genuine SEALED pack (packCount >= 3), never a revealed 2-pack");
    r.eq((key.match(/mapKeyRow\(/g) || []).length, 7, "the legend stays exactly 7 rows");
    r.ok(/hidden cards \(packs of 3\+/.test(key), "the Pack row sub-copy says hidden packs are 3+");
  }

  return r.summary();
}
