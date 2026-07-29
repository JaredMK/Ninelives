// ECON1 SCORE — the piles × smallest product, promoted from coins to score.
//
// Rules pinned here (values derive from the modules, never hardcoded):
//   • Every CLEARED deal folds its breakdown product into campaign.runScore
//     (win only — a lost deal scores nothing, exactly as it never paid).
//   • markRunWon (the ♠ boss) banks the split: campaign score FREEZES at
//     scoreBanked; everything scored after is the endless score.
//   • Accessors: pre-boss the campaign score IS the running total and the
//     endless score is 0; post-boss campaign = banked, endless = run − banked.
//   • runScore/scoreBanked persist additive (pre-ECON1 saves restore as 0).
//   • Stats bests are Math.max folds, exhibition-gated at the call sites
//     exactly like Stats.runCleared (source-contract pins, the seeds idiom).
//   • The mystery coinBonus cache rides earnCoins accounting (balance AND
//     totalCoinsEarned); coinLoss stays balance-only and floors at 0.
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

function memStorage() {
  const data = {};
  return {
    getItem: (k) => (k in data ? data[k] : null),
    setItem: (k, v) => { data[k] = String(v); },
    removeItem: (k) => { delete data[k]; },
  };
}

function fullHtml() {
  return readFileSync(join(HERE, "..", "index.html"), "utf8");
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
  const g = loadGame();
  const { CampaignState, Stats } = g;
  const r = makeRunner("score.test.mjs");

  // --- Per-clear fold + the banked split (CampaignState unit) -------------
  {
    const c = CampaignState.create();
    c.reset();
    r.eq(c.getRunScore(), 0, "a fresh campaign scores 0");
    r.eq(c.getCampaignScore(), 0, "…campaign score 0");
    r.eq(c.getEndlessScore(), 0, "…endless score 0");
    c.addRunScore(12);   // deal 1 clear: product 12
    c.addRunScore(8);    // deal 2 clear: product 8
    r.eq(c.getRunScore(), 20, "each clear folds its product into runScore");
    r.eq(c.getCampaignScore(), 20, "pre-boss the campaign score IS the running total");
    r.eq(c.getEndlessScore(), 0, "pre-boss the endless score is 0 (nothing banked yet)");
    c.addRunScore(-5);
    r.eq(c.getRunScore(), 20, "a negative fold is clamped (score never drops mid-campaign)");
    c.markRunWon();      // the ♠ boss falls — the score banks HERE
    r.eq(c.getCampaignScore(), 20, "the campaign score freezes at the banked value");
    r.eq(c.getEndlessScore(), 0, "…endless score still 0 at the moment of banking");
    c.addRunScore(6);    // endless deal 1
    c.addRunScore(14);   // endless deal 2
    r.eq(c.getRunScore(), 40, "runScore keeps accumulating into endless");
    r.eq(c.getCampaignScore(), 20, "post-boss the campaign score never moves again");
    r.eq(c.getEndlessScore(), 20, "post-boss the endless score = run − banked");
  }

  // --- reset() wipes the score (a loss / New Campaign funnels here) -------
  {
    const c = CampaignState.create();
    c.reset();
    c.addRunScore(30);
    c.markRunWon();
    c.addRunScore(10);
    c.reset();
    r.eq(c.getRunScore(), 0, "reset wipes runScore");
    r.eq(c.getCampaignScore(), 0, "reset wipes the banked campaign score");
    r.eq(c.getEndlessScore(), 0, "reset wipes the endless score");
  }

  // --- Serialize / restore: additive, defensive reads ---------------------
  {
    const c = CampaignState.create();
    c.reset();
    c.addRunScore(25);
    c.markRunWon();
    c.addRunScore(7);
    const blob = JSON.parse(JSON.stringify(c.serialize()));
    r.eq(typeof blob.runScore, "number", "serialize carries runScore");
    r.eq(typeof blob.scoreBanked, "number", "serialize carries scoreBanked");
    const c2 = CampaignState.create();
    c2.restore(blob);
    r.eq(c2.getRunScore(), 32, "restore brings runScore back");
    r.eq(c2.getCampaignScore(), 25, "restore brings the banked campaign score back");
    r.eq(c2.getEndlessScore(), 7, "restore brings the endless score back");
    // Pre-ECON1 save: no score fields at all → zeros, no crash.
    const old = JSON.parse(JSON.stringify(c.serialize()));
    delete old.runScore; delete old.scoreBanked;
    const c3 = CampaignState.create();
    c3.restore(old);
    r.eq(c3.getRunScore(), 0, "a pre-ECON1 save restores runScore as 0");
    r.eq(c3.getEndlessScore(), 0, "…and endless score as 0");
  }

  // --- Lifetime bests: Math.max folds (storage-stubbed Stats) -------------
  {
    const g2 = loadGame({ localStorage: memStorage() });
    const S = g2.Stats;
    r.eq(S.get().bestCampaignScore, 0, "bestCampaignScore starts at 0");
    r.eq(S.get().bestEndlessScore, 0, "bestEndlessScore starts at 0");
    S.recordCampaignScore(40);
    S.recordCampaignScore(25);
    r.eq(S.get().bestCampaignScore, 40, "campaign best keeps the max (lower fold ignored)");
    S.recordCampaignScore(55);
    r.eq(S.get().bestCampaignScore, 55, "campaign best rises on a new max");
    S.recordEndlessScore(12);
    S.recordEndlessScore(8);
    r.eq(S.get().bestEndlessScore, 12, "endless best keeps the max");
    S.recordEndlessScore(undefined);
    r.eq(S.get().bestEndlessScore, 12, "a garbage fold can't corrupt the best");
    // A pre-ECON1 stats blob (fields absent) merges in as zeros.
    const st = memStorage();
    st.setItem("ninelives.stats.v1", JSON.stringify({ gamesPlayed: 3 }));
    const g3 = loadGame({ localStorage: st });
    r.eq(g3.Stats.get().bestCampaignScore, 0, "old stats blob: bestCampaignScore merges as 0");
    r.eq(g3.Stats.get().bestEndlessScore, 0, "old stats blob: bestEndlessScore merges as 0");
  }

  // --- Mystery coinBonus rides earnCoins; coinLoss stays balance-only -----
  {
    const c = CampaignState.create();
    c.reset();
    const earned0 = c.totalCoinsEarned, coins0 = c.getCoins();
    const d = c.applyMysteryEvent("coinBonus", 11);
    r.ok(d && d.key === "coinBonus" && d.amount > 0, "coinBonus returns its amount descriptor");
    r.eq(c.getCoins(), coins0 + d.amount, "coinBonus adds the amount to the balance");
    r.eq(c.totalCoinsEarned, earned0 + d.amount, "coinBonus now counts in totalCoinsEarned (earnCoins routing)");
    const earned1 = c.totalCoinsEarned, coins1 = c.getCoins();
    const l = c.applyMysteryEvent("coinLoss", 12);
    r.ok(l && l.key === "coinLoss", "coinLoss returns its descriptor");
    r.eq(c.getCoins(), coins1 - l.amount, "coinLoss subtracts from the balance");
    r.eq(c.totalCoinsEarned, earned1, "coinLoss does NOT touch totalCoinsEarned");
    // …and it floors at 0 on an empty purse.
    const broke = CampaignState.create();
    broke.reset();
    const l2 = broke.applyMysteryEvent("coinLoss", 13);
    r.eq(broke.getCoins(), 0, "coinLoss on 0 coins floors at 0 (never negative)");
    r.ok(l2.amount === 0, "…the floored loss reports amount 0");
  }

  // --- Source-contract pins (the app-scope flow the harness can't drive) --
  {
    const src = gameSource();    // The per-clear fold sits in onRunEnd's WIN path, right after earnCoins —
    // the loss path returns long before it, so a lost deal scores nothing.
    r.ok(src.includes("if (payout.total > 0) campaign.earnCoins(payout.total);\n")
      && src.includes("campaign.addRunScore(payout.product);"),
      "onRunEnd: the score fold rides the win path (a loss never reaches it)");
    const foldAt = src.indexOf("campaign.addRunScore(payout.product);");
    const lossReturn = src.indexOf("queueItemUnlockPops(ItemUnlocks.checkNewUnlocks(), () => showCampaignFailed(payload.run));");
    r.ok(lossReturn !== -1 && foldAt > lossReturn,
      "…the fold sits AFTER the loss path's return (win-only scoring)");
    // The post-win reconciliation is against the FLAT base now, not the product.
    r.ok(src.includes("run.bonusCoins = payout.total - payout.flat;"),
      "onRunEnd: the bonus tracker reconciles total − flat (ambush bounty survives whole)");
    // Exhibition gating: every best-fold call site sits behind the flag,
    // exactly like Stats.runCleared (sibling to seeds.test.mjs's pins).
    r.ok(src.includes("if (!exhibition) Stats.runCleared("), "runCleared still gated (sanity)");
    const bankGuard = src.indexOf("if (!exhibition) {\n      campaign.markRunWon();");
    r.ok(bankGuard !== -1 && src.indexOf("Stats.recordCampaignScore(", bankGuard) !== -1
      && src.indexOf("Stats.recordCampaignScore(", bankGuard) < src.indexOf("Stats.recordDeckWin(", bankGuard),
      "onRunEnd: the campaign-best fold rides inside the gated win-bank block");
    r.ok(src.includes("if (!exhibition && campaign.runWonBanked && campaign.runWonBanked())\n      Stats.recordEndlessScore(campaign.getEndlessScore());"),
      "onRunEnd: the endless-clear best fold is exhibition-gated");
    r.ok(src.includes("if (!exhibition) Stats.recordEndlessScore(campaign.getEndlessScore());"),
      "onRunEnd: the endless-death best fold is exhibition-gated");
  }

  // --- UI pins (Stage B): every score/reward display derives, never hardcodes
  {
    const src = gameSource();
    const html = fullHtml();

    // MAP: the deal/boss node badge is the FLAT coin reward chip, computed at
    // render via Economy.dealFlat (the same formula the payout uses) — the
    // 1-3 difficulty pips are gone, and bosses carry the chip too.
    const badge = fnBody(src, "dealBadge");
    r.ok(badge.length > 0, "dealBadge exists");
    r.ok(badge.includes("Economy.dealFlat("), "the map chip's amount comes from Economy.dealFlat (knob-derived, never hardcoded)");
    r.ok(badge.includes("RunMap.difficultyScore("), "…with the node's stage-relative difficulty score as the rating");
    r.ok(badge.includes("mn-reward"), "the chip renders the mn-reward reward badge");
    r.ok(!badge.includes('if (big) return ""'), "bosses get a reward chip too (big no longer returns empty)");
    r.ok(!badge.includes('class="on"') && !src.includes("mn-diff"),
      "the difficulty-pip badge (mn-diff) is fully retired");
    r.ok(html.includes(".mn-piles.mn-reward"), "the mn-reward chip style exists");
    // The chip's only legend: harder nodes and bosses pay more (knob-derived).
    const g4 = loadGame();
    r.ok(g4.Economy.dealFlat(2, 3, false) > g4.Economy.dealFlat(2, 1, false),
      "a harder deal pays more than an easy one at the same stage");
    r.ok(g4.Economy.dealFlat(2, 3, true) > g4.Economy.dealFlat(2, 3, false),
      "a boss pays more than a hard deal at the same stage");

    // MAP labels + key: deals/bosses name the reward.
    const label = fnBody(src, "mapNodeLabel");
    r.ok(/Deal — reward /.test(label) && label.includes("harder pays more"),
      "mapNodeLabel names the deal reward (difficulty kept as context)");
    r.ok(/BOSS — full deck · reward /.test(label), "mapNodeLabel names the boss reward");
    r.ok(src.includes("the chip shows its coin reward — harder deals pay more"),
      "the map key's deal row teaches the reward chip");

    // HUD: the score chip sits in the .hud bar; updateStageRun flips it to the
    // endless score once the win is banked.
    r.ok(html.includes('id="hudScoreChip"') && html.includes('id="hudScoreLab"') && html.includes('id="hudScore"'),
      "the HUD score chip markup exists");
    const usr = fnBody(src, "updateStageRun");
    r.ok(usr.includes("getCampaignScore()") && usr.includes("getEndlessScore()"),
      "updateStageRun writes the campaign/endless score");
    r.ok(usr.includes('"Endless"'), "…labelled Endless once banked");
    r.ok(html.includes("body.zen-mode #hudScoreChip"), "Zen hides the score chip (no campaign)");

    // DEAL STATUS row: Reward (flat, fixed at deal start) · Score (live
    // piles × smallest projection). DEAL_STATUS_HELP stays the single source.
    r.ok(html.includes('id="dealReward"') && html.includes('id="dealScore"'),
      "the deal-status row carries the Reward · Score numbers");
    r.ok(!html.includes('id="aliveCount"') && !html.includes('id="bonusCoins"'),
      "…the old Piles × Smallest + Bonus ids are retired");
    const rh = fnBody(src, "renderHud");
    r.ok(rh.includes("el.dealReward") && rh.includes("el.dealScore"),
      "renderHud writes both deal-status numbers");
    r.ok(rh.includes("board.aliveCount()") && rh.includes("board.minAliveCards()"),
      "…the score projection reads the same board accessors Economy does");
    r.ok(/dealFlatReward = ambushDeal \? 0/.test(src) && src.includes("let dealFlatReward = 0;"),
      "the deal's flat reward is captured at deal start (0 for an ambush)");
    r.ok(src.includes('const DEAL_STATUS_HELP = "Reward:'),
      "DEAL_STATUS_HELP explains the flat reward + the score (single source)");

    // SUMMARY tally: Deal reward shows the FLAT amount with stage/rating
    // context; Score earned shows the product; the coin total excludes it.
    const cbh = fnBody(src, "coinBreakdownHtml");
    r.ok(cbh.includes('mainLine("Deal reward", b.flat)'), "the summary's Deal reward is the flat amount");
    r.ok(cbh.includes('"Stage " + b.stage') && cbh.includes('b.rating + "/3"'),
      "…with the stage · rating context");
    r.ok(cbh.includes("Score earned") && cbh.includes("b.product"),
      "…and a Score earned line carries the product");
    r.ok(cbh.includes("no flat reward"), "…an ambush flags its missing flat base");

    // END SUMMARY: score + best tiles (endless split post-boss); an
    // exhibition run shows its score but makes NO best claim.
    const es = fnBody(src, "endStats");
    r.ok(es.includes("bestCampaignScore") && es.includes("bestEndlessScore"),
      "endStats reads both lifetime bests");
    r.ok(es.includes("exhibition"), "endStats carries the exhibition flag");
    const est = fnBody(src, "endScoreTilesHtml");
    r.ok(est.includes('"Score"') && est.includes('"Endless best"'),
      "the summary renders score + best tiles (endless split included)");
    r.ok(est.includes("not recorded"), "…exhibition bests render as not-recorded (no best claim)");
    r.ok(html.includes('id="endScoreTiles"'), "the end-summary score tiles container exists");

    // STATS screen: both bests have tiles.
    const ss = fnBody(src, "showStats");
    r.ok(ss.includes("Best campaign score") && ss.includes("Best endless score"),
      "the stats screen has tiles for both score bests");
  }

  return r.summary();
}
