// TUT4 — tutorial clarity/accuracy rework + How to Play manual + the
// "Replay tutorial" button. The bubble/gate choreography and DOM anchoring
// are UI-side, so this suite covers what can be verified DOM-free: the
// tutorial.js copy edits (tie rule, top-card comparison, home goal), the
// mapCardNode anchor no longer falling back to Pinky, the seed-18 map
// structurally carrying a card node for that anchor, the manual's new
// claims, and the Replay button's one-shot arm + save-safety confirm wiring.
// Registry/seed-driven: the pinned seed and map come from live data.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadGame, makeRunner } from "./_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

function gameScript() {
  const html = readFileSync(join(HERE, "..", "index.html"), "utf8");
  const blocks = html.match(/<script>([\s\S]*?)<\/script>/g) || [];
  return blocks
    .map((b) => b.replace(/^<script>/, "").replace(/<\/script>$/, ""))
    .find((c) => c.includes("const GameEngine")) || "";
}
function tutorialSrc(src) {
  const a = src.indexOf("const Tutorial = (() => {");
  if (a === -1) return "";
  const b = src.indexOf("})();", a);
  return b === -1 ? "" : src.slice(a, b);
}

export function run() {
  const r = makeRunner("tut4.test.mjs");
  const g = loadGame();
  const { RunMap, CampaignState, TutorialData } = g;
  const src = gameScript();
  const tut = tutorialSrc(src);
  const html = readFileSync(join(HERE, "..", "index.html"), "utf8");
  const G = TutorialData.groups;

  // ---- D1: tutorial copy teaches the M-rules the naive gate needs ----------
  {
    // M1 — a guess is Higher/Lower/Same vs the pile's TOP card.
    r.ok(/top card/i.test(G.deal[1].text),
      "deal[1] names the pile's TOP card as the comparison target (M1)");
    // M2 — a tie kills a directional (Higher/Lower) guess. Taught at the Same
    // shield bubble (which rings #hudSame), so ties are never 'close enough'.
    r.ok(/tie/i.test(G.deal[3].text) && G.deal[3].anchor === "sameShield",
      "deal[3] teaches that a TIE kills a Higher/Lower guess (M2), on the Same-shield anchor");
    // M2 — a wrong guess kills the pile; M3 — survive the whole deck to win.
    r.ok(/dies/i.test(G.deal[2].text) && /whole deck/i.test(G.deal[2].text),
      "deal[2] teaches wrong→pile dies (M2) and survive the whole deck to win (M3)");
    // M4 — coins = surviving piles × smallest pile.
    r.ok(G.coins[0].text.includes("surviving piles × smallest pile"),
      "coins[0] teaches the payout formula (M4)");
    // M5 — the run is a climb up a map to Pinky's home (mama at the top).
    r.ok(/mama/i.test(G.map1[0].text) && /win the run/i.test(G.map1[0].text),
      "map1[0] frames the climb to mama at the top as the win condition (M5)");
    // M6 — the deck grows as you climb (card nodes) → harder deals.
    r.ok(/grow/i.test(G.map1[1].text) && /deck/i.test(G.map1[1].text),
      "map1[1] teaches that card nodes grow the deck → harder deals (M6)");
  }

  // ---- D1: mapCardNode anchor never rings Pinky ----------------------------
  {
    // The resolver dropped its `|| $(".map-avatar")` fallback: with no card
    // node it now centers (arrowless), never rings PINKY under card-node copy.
    r.ok(/mapCardNode:\s+\(\) => \$\("\.pm-node\.t-pickup, \.pm-node\.t-pack"\),/.test(tut),
      "mapCardNode resolves to a pickup/pack node with NO avatar fallback");
    r.ok(!/mapCardNode[\s\S]{0,80}map-avatar/.test(tut),
      "mapCardNode no longer falls back to the map avatar (Pinky)");
    // A2: on the pinned seed the map STRUCTURALLY carries a card/pack node low
    // on the trail, so the anchor resolves to a real card node (not null).
    const t = CampaignState.create();
    t.setTutorialRun(true);
    t.reset();
    r.eq(t.serialize().runSeed, TutorialData.seed, "the tutorial run rides the pinned seed");
    const map = t.getMap();
    const cardNodes = map.nodes.filter(n => n.type === "pickup" || n.type === "pack");
    r.ok(cardNodes.length > 0, "the pinned seed's map has card/pack nodes for mapCardNode to ring");
    const lowRow = Math.min.apply(null, cardNodes.map(n => n.row));
    r.ok(lowRow <= 3, "a card/pack node sits low on the trail (row " + lowRow + "), near the opening render");
    // Strict guided chain still opens (closed environment preserved).
    r.ok(RunMap.tutorialPathStrict(map), "the pinned seed still opens with the strict guided chain");
  }

  // ---- D1: bubble counts unchanged (no re-architecture) --------------------
  {
    const expect = { pinky: 1, map1: 3, deal: 5, coins: 2, toStore: 1,
      shopC: 2, shopD: 1, shopE: 1, shopF: 3, stickerPicker: 1, toPickup: 1, grew: 2 };
    for (const k in expect)
      r.eq(G[k].length, expect[k], "group '" + k + "' keeps its step count (" + expect[k] + ")");
    r.eq(TutorialData.problems.length, 0, "tutorial.js still validates with zero problems");
  }

  // ---- D4: Replay tutorial — one-shot arm, pref untouched ------------------
  {
    r.ok(/function shouldRun\(\) \{ return replayArmed \|\| SaveStore\.getPref\(PREF\) !== "1"; \}/.test(tut),
      "shouldRun() is overridden by the one-shot replayArmed flag");
    r.ok(/armReplay\(\) \{ replayArmed = true; \}/.test(tut),
      "the module exposes armReplay() to set the one-shot flag");
    // The one-shot is consumed as the replay campaign arms — never stamps the pref.
    const onNew = tut.slice(tut.indexOf("onNewCampaign()"), tut.indexOf("onDeckSelect()"));
    r.ok(onNew.includes("active = shouldRun();") && onNew.includes("replayArmed = false;"),
      "onNewCampaign consumes the one-shot after reading shouldRun (exactly one replay)");
    const stamps = (tut.match(/SaveStore\.setPref\(PREF, "1"\)/g) || []).length;
    r.eq(stamps, 1, "still exactly one pref stamp site — replay never touches tutorial2 stamping");
    r.ok(!/replayArmed[\s\S]{0,40}setPref/.test(tut), "arming a replay stamps nothing");
  }

  // ---- D4: manual Replay button + bottom-bar save-safety confirm -----------
  {
    r.ok(html.includes('id="wtReplay"') && html.includes("Replay tutorial"),
      "the manual carries a labelled 'Replay tutorial' button");
    r.ok(html.includes('class="wt-replay"') && !/wt-replay[^>]*primary/.test(html),
      "the Replay button is a secondary control (not the primary Next/Got it)");
    r.ok(html.includes("Replaying the tutorial starts a fresh run and ends your current campaign. Continue?"),
      "the exact save-safety confirm question is present");
    // Destructive check: a Continue save OR a live deal → confirm; zen is exempt.
    r.ok(/replayWouldDestroy = \(\) => \{[\s\S]*?zenMode[\s\S]*?saved\.campaign[\s\S]*?!!engine/.test(html),
      "replayWouldDestroy consults a Continue save + a live engine, and exempts Zen");
    // beginReplay arms the tour and routes through deck select like a first-timer;
    // it does NOT call startCampaign directly (clearSave stays deferred to Start).
    const begin = html.slice(html.indexOf("const beginReplay"), html.indexOf("replay.addEventListener"));
    r.ok(begin.includes("Tutorial.armReplay()") && begin.includes("showDeckSelect("),
      "beginReplay arms the one-shot tour and routes through deck select");
    r.ok(!begin.includes("startCampaign(") && !begin.includes("clearSave("),
      "beginReplay never starts a campaign or clears the save itself (deferred to Start Run)");
    // Cancel just hides the confirm — save intact, no campaign.
    r.ok(/confirmNo\.addEventListener\("click", e => \{[^}]*confirm\.classList\.add\("hidden"\)/.test(html),
      "Cancel hides the confirm bar and starts nothing (save intact)");
    r.ok(/confirmYes\.addEventListener\("click", e => \{[^}]*beginReplay\(\)/.test(html),
      "Continue proceeds via beginReplay");
  }

  // ---- D3: How to Play manual states the current game ----------------------
  {
    const body = html.slice(html.indexOf("function showManual"), html.indexOf("function closeManual"));
    r.ok(/tie[\s\S]{0,40}kills/i.test(body) || /kills[\s\S]{0,40}Higher or Lower/i.test(body),
      "manual states ties kill a directional (Higher/Lower) guess");
    r.ok(/Aces are high/.test(body), "manual states Aces are high");
    r.ok(/surviving piles × the cards in your smallest pile/.test(body),
      "manual states the coin formula");
    r.ok(/Mama's home/.test(body) && /climb/i.test(body),
      "manual describes the map climb to Mama's home");
    r.ok(/grow your deck/i.test(body) && /run ends/i.test(body),
      "manual states card/pack nodes grow the deck and losing a deal ends the run");
    // The seven store classes, aligned to the STOREHELP1 legend + PACKS1.
    for (const cls of ["Sticker", "Pillar", "Base", "Card", "Pack", "Same-Power", "Removal"])
      r.ok(body.includes("<b>" + cls + "</b>"), "manual lists the store class: " + cls);
    r.ok(/keep 1–2/.test(body), "manual's Pack line matches PACKS1 keep-1–2 (non-contradicting)");
    r.ok(/Jokers/.test(body) && /safe/i.test(body), "manual states jokers are safe on any call");
    r.ok(/Zen/.test(body) && /practice/i.test(body), "manual states Zen is consequence-free practice");
    r.ok(/Regular, Master, Legendary/.test(body), "manual notes the difficulty tiers exist");
  }

  return r.summary();
}
