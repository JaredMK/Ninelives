// TUT4 — Zen-first tutorial copy + How to Play manual + the "Replay tutorial"
// button. The bubble choreography and DOM anchoring are UI-side, so this
// suite covers what can be verified DOM-free: the tutorial.js copy (core
// mechanics ONLY — no campaign concepts), the group shape (deal: 6, zenEnd:
// 1), the manual's claims, and the Replay button's one-shot arm + its
// non-destructive reroute into Zen (the old save-safety confirm is gone —
// Zen never touches the campaign save).
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
  const { TutorialData } = g;
  const src = gameScript();
  const tut = tutorialSrc(src);
  const html = readFileSync(join(HERE, "..", "index.html"), "utf8");
  const G = TutorialData.groups;

  // ---- group shape ----------------------------------------------------------
  {
    r.eq(G.deal.length, 6, "the guided deal teaches in exactly 6 bubbles (v5.60: Ace-high cut)");
    r.eq(G.zenEnd.length, 1, "the deal-end beat is a single bubble");
    r.eq(Object.keys(G).length, 2, "…and those are the ONLY groups (no campaign tour remains)");
    r.eq(TutorialData.problems.length, 0, "tutorial.js validates with zero problems");
  }

  // ---- the deal copy teaches the core mechanics (M-rules) -------------------
  {
    // M0 — the goal: keep piles alive.
    r.ok(/survive/i.test(G.deal[0].text) && G.deal[0].anchor === "dealBoard",
      "deal[0] frames survival as the goal, on the board anchor");
    // M1 — a guess is Higher/Lower/Same vs the pile's TOP card; swipe input.
    r.ok(/top card/i.test(G.deal[1].text) && /swipe/i.test(G.deal[1].text),
      "deal[1] names the pile's TOP card as the comparison target and teaches the swipe (M1)");
    // M2/M3 — wrong kills the pile; beat the whole deck to win.
    r.ok(/dies/i.test(G.deal[2].text) && /whole deck/i.test(G.deal[2].text),
      "deal[2] teaches wrong→pile dies (M2) and beat the whole deck (M3)");
    // M4 — call Same on an expected equal card; a correct Same charges the
    // shield. (v5.59: the "a tie kills a Higher/Lower guess" clause was cut
    // from this step by player request — the mechanic is now taught in play
    // by the shoulda-said-same nudge, not by the tutorial.)
    r.ok(/\*Same\*/.test(G.deal[3].text) && /equal card/i.test(G.deal[3].text)
      && /\*shield\*/.test(G.deal[3].text) && G.deal[3].anchor === "sameShield",
      "deal[3] teaches calling Same on an equal card + the shield charge (M4), on the Same-shield anchor");
    // M5 (Ace-high / 2-low) was CUT from the tour by player request in v5.60 —
    // those edges are learned in play (the deck strip + a bad guess). The tour
    // is now 6 steps; the histogram bubble moved up to deal[4].
    // M6 — the deck strip reads what's left, with its hold/tap affordances.
    r.ok(/what's left in the deck/i.test(G.deal[4].text) && G.deal[4].anchor === "dealHistogram",
      "deal[4] teaches the deck strip (M6), on the histogram-band anchor");
    r.ok(/hold on a number/i.test(G.deal[4].text) && /tap on the deck/i.test(G.deal[4].text),
      "…including the hold-a-number and tap-the-deck affordances");
    // The send-off.
    r.eq(G.deal[5].button, "Go", "the last deal bubble's button is 'Go'");
    r.ok(/Your turn/i.test(G.deal[5].text), "the last deal bubble hands over: 'Your turn'");
    // The deal-end beat is a short sign-off (v5.60, player copy) — it no
    // longer narrates the climb/menu; free Zen play simply continues.
    r.ok(/good luck/i.test(G.zenEnd[0].text), "zenEnd signs off ('Good luck!')");
    r.ok(G.zenEnd[0].button === "Let's play", "…on the 'Let's play' button");
  }

  // ---- NO campaign concepts in the teaching phase ---------------------------
  {
    for (const [i, s] of G.deal.entries()) {
      for (const word of ["store", "shop", "coin", "sticker", "pillar", "map", "campaign", "deck character"])
        r.ok(!s.text.toLowerCase().includes(word),
          "deal[" + i + "] carries no campaign concept: '" + word + "'");
    }
    // Anchors are all deal-screen elements — nothing from the map or store.
    for (const s of G.deal)
      r.ok(s.anchor == null || ["dealBoard", "dealPile", "dealDeckChar", "sameShield", "dealHistogram"].includes(s.anchor),
        "every deal anchor is a play-screen element (saw: " + s.anchor + ")");
  }

  // ---- Replay tutorial — one-shot arm, non-destructive Zen reroute ----------
  {
    r.ok(html.includes('id="wtReplay"') && html.includes("Replay tutorial"),
      "the manual carries a labelled 'Replay tutorial' button");
    r.ok(html.includes('class="wt-replay"') && !/wt-replay[^>]*primary/.test(html),
      "the Replay button is a secondary control (not the primary Next/Got it)");
    const begin = html.slice(html.indexOf("const beginReplay"), html.indexOf("replay.addEventListener"));
    r.ok(begin.includes("Tutorial.armReplay()"), "beginReplay arms the one-shot tour");
    r.ok(begin.includes("showZenSelect("), "beginReplay routes into ZEN (the tour lives in a Zen deal now)");
    r.ok(!begin.includes("startCampaign(") && !begin.includes("clearSave(") && !begin.includes("showDeckSelect("),
      "beginReplay never starts a campaign, clears a save, or touches deck select");
    // The old save-safety confirm is retired: replay can destroy nothing.
    r.ok(!html.includes("replayWouldDestroy") && !html.includes("wtConfirm"),
      "no destructive-replay confirm remains (Zen never touches the campaign save)");
    r.ok(!html.includes("Replaying the tutorial starts a fresh run"),
      "the old 'starts a fresh run' confirm copy is gone");
    r.ok(/replay\.addEventListener\("click", e => \{ e\.stopPropagation\(\); Sound\.tap\(\); beginReplay\(\); \}\)/.test(html),
      "the Replay button calls beginReplay directly (no confirm branch)");
  }

  // ---- How to Play manual states the current game ---------------------------
  {
    const body = html.slice(html.indexOf("function showManual"), html.indexOf("function closeManual"));
    r.ok(/tie[\s\S]{0,40}kills/i.test(body) || /kills[\s\S]{0,40}Higher or Lower/i.test(body),
      "manual states ties kill a directional (Higher/Lower) guess");
    r.ok(/Aces are high/.test(body), "manual states Aces are high");
    r.ok(/flat amount set by the/.test(body) && /harder deals pay more/.test(body),
      "manual states the coin reward is flat by stage & difficulty");
    r.ok(/Surviving piles × the cards in your smallest pile/.test(body) && /now your <b>score<\/b>/.test(body),
      "manual states piles × smallest is now the SCORE (personal bests, not coins)");
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
