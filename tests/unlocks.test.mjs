// UNLOCK1 (Stage A) — the item-unlock system: schema, stats, gates, module.
//
// An items.js entry may carry `unlock: { type, stat, count }` gating it out of
// every roll pool (sticker grants, store classes, sticker packs, Lammy's
// pre-equip) until the LIFETIME Stats counter `stat` reaches `count`. SHIP
// STATE: no entry carries the field, so every pool is byte-identical to the
// pre-feature game — this suite pins that invariant first, then drives the
// machinery with INJECTED gates (registry defs mutated in-memory — the
// runtime filter reads them live) and mutated items.js sources (the load-time
// validator).
//
// Covered: validator accept/reject of unlock shapes; the 15-stat contract
// (statValue / hintFor cover every name); pool identity at ship state; a
// locked id excluded from grantable() / the store roll / revealPack / Lammy's
// prefill; empty-class w:0 renormalization (no dead slots); reveal-fewer
// degradation on an empty pool; checkNewUnlocks threshold + stamp-once;
// retroactive silent first-load init; nearestLocked ordering; exhibition
// gates on every new increment (behavioral where the harness reaches
// CampaignState, source-contract pins — the stklag2/seeds idiom — for the
// app-scope sites). Rules only, never tunable numbers.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadGame, makeRunner } from "./_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const ITEMS_SRC = readFileSync(join(HERE, "..", "items.js"), "utf8");

function gameSource() {
  const html = readFileSync(join(HERE, "..", "index.html"), "utf8");
  const blocks = html.match(/<script>([\s\S]*?)<\/script>/g) || [];
  return blocks
    .map((b) => b.replace(/^<script>/, "").replace(/<\/script>$/, ""))
    .find((c) => c.includes("const GameEngine")) || "";
}
function memStorage(init = {}) {
  const data = { ...init };
  return {
    getItem: (k) => (k in data ? data[k] : null),
    setItem: (k, v) => { data[k] = String(v); },
    removeItem: (k) => { delete data[k]; },
    _data: data,
  };
}
function countOf(hay, needle) {
  let n = 0, i = 0;
  while ((i = hay.indexOf(needle, i)) !== -1) { n++; i += needle.length; }
  return n;
}
/** Load the game with ONE extra sticker entry appended to the stickers group,
    carrying the given unlock field source (raw JS text). The probe is CURSED:
    a non-cursed sticker without STICKER_ICONS chip art refuses to boot by
    design (the CRT-STK 1:1 fail-loud contract, pinned in crt5) — cursed types
    wear the shared corruption art, so the probe loads and the unlock
    validator is what's under test here. */
function loadWithProbe(unlockSrc) {
  const probe = '{ id: "__unlockprobe", label: "Probe", icon: "?", kind: "rank", rankDelta: 1,'
    + ' tier: "common", price: 1, description: "probe", cursed: true, unlock: ' + unlockSrc + " },";
  const src = ITEMS_SRC.replace('stickers: [\n    { id: "rankUp",', "stickers: [\n    " + probe + '\n    { id: "rankUp",');
  if (src === ITEMS_SRC) throw new Error("probe anchor not found in items.js");
  return loadGame({ itemsSource: src });
}
const LOCK = (stat, count) => ({ type: "behavior", stat, count });
const BIG = 1e9;   // an unreachable threshold (finite, valid) — always locked

export function run() {
  const r = makeRunner("unlocks.test.mjs");

  // ── LIVE PROGRESSION (UNLOCK2, v5.41): the catalog carries real gates ──
  // These pins are REGISTRY-DRIVEN (rules, not tunables): retuning a
  // threshold or moving a gate to a different stat must not break them.
  {
    const { ItemData, StickerTypes, ItemUnlocks } = loadGame({ localStorage: memStorage() });
    const groups = ["stickers", "pillars", "bases", "samePowers", "packs"];
    let gated = 0, started = {};
    for (const g of groups) {
      started[g] = 0;
      for (const d of ItemData[g]) {
        if (d.unlock != null) {
          gated++;
          r.ok(ItemUnlocks.STATS.indexOf(d.unlock.stat) !== -1,
            g + "." + d.id + " gates on a KNOWN stat (" + d.unlock.stat + ")");
        } else started[g]++;
      }
    }
    r.ok(gated > 0, "the progression is LIVE: items carry unlock gates (" + gated + ")");
    for (const g of groups)
      r.ok(started[g] >= 2, g + " keeps >=2 STARTING items (" + started[g]
        + ") — the store class roll never starves at zero stats");
    // The bury chicken-and-egg guard: cardsBuried gates exist, so at least
    // one bury SOURCE must be a starting item or the ladder can never open.
    // v6.51: Bury 1/2 are retired — Quick Bury is the (ungated) seed.
    const burySeed = ItemData.stickers.find(d => d.id === "quickBury");
    r.ok(!ItemData.stickers.some(d => d.id === "oneTribute" || d.id === "twoTribute"),
      "Bury 1 / Bury 2 are retired from items.js");
    r.ok(burySeed && burySeed.unlock == null,
      "Quick Bury stays a starting item — the cardsBuried ladder's seed");
    // The four requested Zen events are all actually used by the design.
    for (const zs of ["zenGamesPlayed", "zenEasyWon", "zenMediumWon", "zenHardWon"]) {
      const users = groups.flatMap(g => ItemData[g].filter(d => d.unlock && d.unlock.stat === zs));
      r.ok(users.length >= 1, "at least one item gates on " + zs + " (" + users.length + ")");
    }
    // PACING CONTRACT (v5.51 — player report: ~30 pops after one climb):
    // under the documented solid-winning-climb growth model, no climb may
    // cross more than 7 gates (the 127-item roster rebunched the early drip
    // from 5 to 7 — retune unlock counts in items.js to tighten it back),
    // and the early drip stays alive (climbs 1-3 each open >=2).
    // Registry-driven: retuning counts inside these bounds is free;
    // re-bunching the ladders past this fails here.
    const GROWTH = { dealsSurvived: 12, runsPlayed: 1, runsWon: 1, bossesBeaten: 3,
      cardsBuried: 12, stickersApplied: 9, pillarsPlaced: 5, basesPlaced: 4,
      removalsUsed: 3, samesCalled: 5, correctSames: 3, jokersPlayed: 2,
      pilesLost: 4, coinsEarnedLifetime: 90 };
    const perClimb = {};
    for (const g of groups) for (const d of ItemData[g]) {
      if (!d.unlock || GROWTH[d.unlock.stat] == null) continue;   // zen/endless: session-paced
      const k = Math.ceil(d.unlock.count / GROWTH[d.unlock.stat]);
      perClimb[k] = (perClimb[k] || 0) + 1;
    }
    for (const k of Object.keys(perClimb))
      r.ok(perClimb[k] <= 7, "winning climb " + k + " crosses <=7 gates (got " + perClimb[k] + ")");
    for (const k of [1, 2, 3])
      r.ok((perClimb[k] || 0) >= 2, "early climb " + k + " still opens >=2 (got " + (perClimb[k] || 0) + ")");
    // THE TUTORIAL IS A ZEN EASY GAME. Nothing may unlock off it: finishing
    // the tour and being handed two items teaches that unlocks are free.
    // Every Zen gate therefore starts at 2+, and the Zen drip begins on the
    // player's own second session.
    const zenFirst = groups.flatMap(g => ItemData[g].filter(d => d.unlock
      && (d.unlock.stat === "zenGamesPlayed" || d.unlock.stat === "zenEasyWon") && d.unlock.count <= 1));
    r.eq(zenFirst.length, 0,
      "nothing unlocks off the tutorial's Zen Easy win (" + zenFirst.map(d => d.id).join(",") + ")");
    const zenAny = groups.flatMap(g => ItemData[g].filter(d => d.unlock
      && d.unlock.stat.startsWith("zen")));
    r.ok(zenAny.length >= 3, "Zen still carries its own drip beyond the tutorial (" + zenAny.length + ")");
    // The unlock filter at zero stats: grantable() === the ungated non-cursed
    // pool, in registry order.
    r.eq(JSON.stringify(StickerTypes.grantable().map(t => t.id)),
      JSON.stringify(StickerTypes.all().filter(t => !t.cursed && ItemUnlocks.isUnlocked(t)).map(t => t.id)),
      "…grantable() === the ungated non-cursed pool, in order");
    r.ok(StickerTypes.grantable().length < StickerTypes.all().length,
      "…(sanity: cursed stickers still exist and stay excluded)");
    // items.js header documents the field, the 15 stats and the commented example.
    r.ok(ITEMS_SRC.includes("unlock") && ITEMS_SRC.includes('"milestone"') && ITEMS_SRC.includes('"behavior"'),
      "items.js header documents the unlock field + both types");
    r.ok(/unlock: \{ type: "(milestone|behavior)", stat: "\w+", count: \d+ \}/.test(ITEMS_SRC),
      "…with real gated rows in the documented shape");
    const headerStats = ["dealsSurvived", "runsPlayed", "runsWon", "bossesBeaten",
      "endlessStagesReached", "coinsEarnedLifetime", "cardsBuried", "samesCalled",
      "correctSames", "jokersPlayed", "stickersApplied", "pillarsPlaced",
      "basesPlaced", "removalsUsed", "pilesLost",
      "zenGamesPlayed", "zenEasyWon", "zenMediumWon", "zenHardWon"];
    r.ok(headerStats.every(s => ITEMS_SRC.includes(s)), "…listing all 19 supported stats");
  }

  // ── VALIDATOR: a well-formed gate loads; every malformed shape fails loud ──
  {
    let ok = true;
    try { loadWithProbe('{ type: "milestone", stat: "runsWon", count: 3 }'); } catch (e) { ok = false; }
    r.ok(ok, "a well-formed unlock gate { type, stat, count } loads");
    ok = true;
    try { loadWithProbe('{ type: "behavior", stat: "cardsBuried", count: 15 }'); } catch (e) { ok = false; }
    r.ok(ok, "…both types load (behavior too)");
    const bad = [
      ['{ type: "weird", stat: "runsWon", count: 3 }', "a type outside milestone|behavior"],
      ['{ type: "milestone", stat: "notAStat", count: 3 }', "a stat outside the 15-name list"],
      ['{ type: "milestone", stat: "runsWon", count: 0 }', "count 0"],
      ['{ type: "milestone", stat: "runsWon", count: -2 }', "a negative count"],
      ['{ type: "milestone", stat: "runsWon", count: NaN }', "a non-finite count"],
      ['{ type: "milestone", stat: "runsWon" }', "a missing count"],
      ['"yes"', "a non-object unlock"],
      ['[{ type: "milestone", stat: "runsWon", count: 3 }]', "an array unlock"],
    ];
    for (const [src, what] of bad) {
      let threw = false;
      try { loadWithProbe(src); } catch (e) { threw = true; }
      r.ok(threw, "validator rejects " + what);
    }
  }

  // ── The 15-stat contract: statValue + hintFor cover every name ──────────
  {
    const storage = memStorage();
    const { ItemUnlocks, Stats } = loadGame({ localStorage: storage });
    const EXPECTED = ["dealsSurvived", "runsPlayed", "runsWon", "bossesBeaten",
      "endlessStagesReached", "coinsEarnedLifetime", "cardsBuried", "samesCalled",
      "correctSames", "jokersPlayed", "stickersApplied", "pillarsPlaced",
      "basesPlaced", "removalsUsed", "pilesLost",
      "zenGamesPlayed", "zenEasyWon", "zenMediumWon", "zenHardWon",
      // UNLOCK3: counters the NATIVE port tracks and this build does not. They
      // are listed so the SHARED items.js validates on both sides; there is no
      // reader for them here, so an item gated on one never unlocks on the web.
      "heartsPlayed", "diamondsPlayed", "clubsPlayed", "spadesPlayed",
      "perfectDeals", "dealsWonRegular", "dealsWonMaster", "dealsWonLegendary",
      "pinkyTipsSeen", "bestCampaignScore", "bestCoinsInClimb",
      // Same native-only treatment for the Phoenix / Escape Hatch gates.
      "earlyLosses", "ambushesWon"];
    r.eq(JSON.stringify(ItemUnlocks.STATS), JSON.stringify(EXPECTED),
      "ItemUnlocks.STATS is exactly the documented 32-name list");
    Stats.reset();
    r.ok(EXPECTED.every(n => typeof ItemUnlocks.statValue(n) === "number"
      && isFinite(ItemUnlocks.statValue(n)) && ItemUnlocks.statValue(n) >= 0),
      "statValue returns a finite number ≥ 0 for all 15 names");
    r.eq(ItemUnlocks.statValue("bogus"), 0, "…and 0 for an unknown name");
    // Aliases read the legacy counters; the new fields read themselves.
    Stats.runPlayed();
    Stats.bump("cardsBuried", 4);
    r.eq(ItemUnlocks.statValue("runsPlayed"), Stats.get().gamesPlayed, "runsPlayed aliases gamesPlayed");
    r.eq(ItemUnlocks.statValue("cardsBuried"), 4, "cardsBuried reads the new additive field");
    r.eq(ItemUnlocks.statValue("coinsEarnedLifetime"), Stats.get().lifetimeDopamine,
      "coinsEarnedLifetime aliases lifetimeDopamine");
    // hintFor derives copy for every stat (never hand-written, never empty);
    // a starting item (no gate) has no hint.
    // Only the stats THIS build reads carry hint copy; the native-only tail
    // (see the UNLOCK3 note above) has no reader and no phrasing here.
    const READABLE = EXPECTED.slice(0, 19);
    r.ok(READABLE.every(n => {
      const h = ItemUnlocks.hintFor({ unlock: LOCK(n, 7) });
      return typeof h === "string" && h.length > 0 && h.indexOf("7") !== -1;
    }), "hintFor derives non-empty copy carrying the count for all 19 readable stats");
    r.eq(ItemUnlocks.hintFor({ id: "x" }), "", "…and \"\" for a starting item (no gate)");
    r.eq(ItemUnlocks.hintFor({ unlock: LOCK("cardsBuried", 15) }), "Bury 15 cards",
      "…the plan's example phrasing (\"Bury 15 cards\")");
    r.eq(ItemUnlocks.hintFor({ unlock: LOCK("runsWon", 3) }), "Win 3 climbs", "…(\"Win 3 climbs\")");
  }

  // ── Stats.bump/bumpAll: only the fixed unlock counters, never negative ────
  {
    const storage = memStorage();
    const { Stats } = loadGame({ localStorage: storage });
    Stats.reset();
    Stats.bump("gamesPlayed", 5);            // a legacy tally — off-limits
    Stats.bump("cardsBuried", -3);           // negative — ignored
    r.eq(Stats.get().gamesPlayed, 0, "bump() refuses fields outside the unlock-counter set");
    r.eq(Stats.get().cardsBuried, 0, "…and non-positive deltas");
    const blob = storage.getItem("ninelives.stats.v1");
    Stats.bumpAll({});                        // an empty batch never writes
    r.eq(storage.getItem("ninelives.stats.v1"), blob, "an all-empty bumpAll batch never touches storage");
    Stats.bumpAll({ cardsBuried: 2, pilesLost: 1, bogus: 9 });
    r.eq(Stats.get().cardsBuried, 2, "bumpAll folds each known field");
    r.eq(Stats.get().pilesLost, 1, "…all of them in one write");
    r.ok(!("bogus" in Stats.get()) || Stats.get().bogus == null, "…skipping unknown fields");
  }

  // ── GATING: an injected locked def leaves every pool ────────────────────
  {
    const { CampaignState, StickerTypes, PillarTypes, ItemData, ItemUnlocks } = loadGame();
    // grantable(): lock one sticker → excluded, order of the rest preserved.
    const victim = StickerTypes.grantable()[0];
    victim.unlock = LOCK("cardsBuried", BIG);
    r.ok(StickerTypes.grantable().every(t => t.id !== victim.id),
      "a locked sticker leaves grantable()");
    r.eq(JSON.stringify(StickerTypes.grantable().map(t => t.id)),
      JSON.stringify(StickerTypes.all().filter(t => !t.cursed && t.id !== victim.id
        && ItemUnlocks.isUnlocked(t)).map(t => t.id)),
      "…the rest of the UNLOCKED pool unchanged, in order");
    // Store roll: lock one pillar → 300 visits never offer it; the class keeps
    // its weight (its pool renormalizes over the remaining pillars).
    const pilVictim = PillarTypes.all()[0];
    pilVictim.unlock = LOCK("runsWon", BIG);
    {
      const c = CampaignState.create();
      c.reset();
      let visits = 0, sawPillar = false, sawVictim = false;
      for (let v = 0; v < 300; v++) {
        const offer = c.openStore();
        visits++;
        for (const s of offer.slots) {
          if (!s || s.kind !== "pillar") continue;
          sawPillar = true;
          if (s.id === pilVictim.id) sawVictim = true;
        }
      }
      r.ok(visits === 300 && sawPillar && !sawVictim,
        "store: a locked pillar is never offered (its class still rolls, pool renormalized)");
    }
    // Empty class → w:0: lock EVERY pillar → no pillar slots, no dead nulls.
    for (const t of PillarTypes.all()) t.unlock = LOCK("runsWon", BIG);
    {
      const c = CampaignState.create();
      c.reset();
      let pillarSlots = 0, rolledSlots = 0, deadSlots = 0, otherClasses = 0;
      for (let v = 0; v < 300; v++) {
        const offer = c.openStore();
        offer.slots.forEach((s, i) => {
          if (i === offer.slots.length - 1 && s && s.kind === "removal") return;   // fixed slot
          rolledSlots++;
          if (!s) { deadSlots++; return; }
          if (s.kind === "pillar") pillarSlots++;
          else otherClasses++;
        });
      }
      r.eq(pillarSlots, 0, "an all-locked class drops to w:0 — never rolled (300 visits)");
      r.eq(deadSlots, 0, "…leaving NO dead null slots (cwTotal renormalizes)");
      r.ok(otherClasses > 0, "…the other classes absorb the weight");
    }
    // revealPack degradation: lock EVERY sticker → a sticker pack reveals nothing.
    {
      const c = CampaignState.create();
      c.reset();
      const pack = ItemData.packs.find(p => p.kind === "sticker");
      r.ok(!!pack, "items.js has a sticker pack to reveal");
      for (const t of StickerTypes.all()) t.unlock = LOCK("cardsBuried", BIG);
      r.eq(c.revealPack(pack.id).length, 0,
        "an empty unlocked sticker pool → the pack reveals FEWER (zero), never a locked id");
      // Exactly ONE sticker unlocked → the pack fills, all copies of it (with
      // replacement — only the EMPTY pool degrades).
      const one = StickerTypes.grantable()[0] || StickerTypes.all().find(t => !t.cursed);
      for (const t of StickerTypes.all()) if (t !== one && !t.cursed) t.unlock = LOCK("cardsBuried", BIG);
      delete one.unlock;
      const items = c.revealPack(pack.id);
      r.eq(items.length, pack.size, "a one-sticker pool still fills the pack (with replacement)");
      r.ok(items.every(id => id === one.id), "…every roll the one unlocked id");
    }
    // Lammy pre-equip: locked items stay out; a short unlocked pool pads nulls.
    // (FRESH game — the w:0 block above locked every pillar on its instance.)
    {
      const g2 = loadGame();
      const c = g2.CampaignState.create();
      c.setDeck("lammy");
      c.setTier("regular");
      const keepP = g2.PillarTypes.all()[0].id;
      for (const t of g2.PillarTypes.all()) if (t.id !== keepP) t.unlock = LOCK("runsWon", BIG);
      c.reset();
      const cols = c.getColumnPillars();
      r.eq(cols.length, g2.CampaignState.COLUMN_SLOTS, "Lammy prefill keeps the COLUMN_SLOTS shape");
      r.ok(cols.every(id => id === null || id === keepP),
        "…only the unlocked Pillar ever prefills (locked ids stay out)");
      r.ok(cols.filter(Boolean).length <= 1 && cols.some(x => x === null),
        "…a short unlocked pool PADS with nulls (the normal empty-slot shape)");
    }
  }

  // ── checkNewUnlocks: threshold crossing, stamp-once, retroactive silence ──
  {
    const storage = memStorage();
    const { ItemUnlocks, StickerTypes, Stats } = loadGame({ localStorage: storage });
    const KEY = "ninelives.itemunlocks.v1";
    const d = StickerTypes.grantable()[0];
    d.unlock = LOCK("cardsBuried", 5);
    Stats.reset();
    // UNLOCK2: boot now PRIMES the known-set at load — before this test's
    // gate existed — so clear it; the next check re-inits with the injected
    // gate in place (modeling a profile that always had it).
    ItemUnlocks.reset();
    ItemUnlocks.markClimbDone();   // v5.60: gates evaluate only after a climb ends (reset clears this too)
    // First load below threshold: silent init stamps the CURRENT derived set
    // (everything else), the locked item stays unknown and locked.
    r.eq(ItemUnlocks.checkNewUnlocks().length, 0, "below threshold: no new unlocks");
    r.ok(storage.getItem(KEY) != null, "…the known-set persisted on first load");
    r.ok(ItemUnlocks.nearestLocked(5).some(x => x.id === d.id), "…the locked item shows as nearest-locked");
    // Cross the threshold → exactly one detection, then stamped forever.
    Stats.bump("cardsBuried", 5);
    const fresh = ItemUnlocks.checkNewUnlocks();
    r.eq(fresh.length, 1, "crossing the threshold detects the item once");
    r.eq(fresh[0].id, d.id, "…with its id");
    r.ok(typeof fresh[0].hint === "string" && fresh[0].hint.length > 0, "…and derived hint copy");
    r.eq(ItemUnlocks.checkNewUnlocks().length, 0, "…stamped — a second check returns nothing");
    r.ok((JSON.parse(storage.getItem(KEY)).known || []).indexOf(d.id) !== -1,
      "…and the stamp persisted under ninelives.itemunlocks.v1");
    // A SECOND game over the same storage remembers the stamp (no re-toast).
    // STKRB1: Stats writes are coalesced — flush() is the durability point a
    // reload reads (the app calls it from flushCampaignSave at transitions /
    // pagehide; the harness's no-op timers never fire the debounce).
    Stats.flush();
    const g2 = loadGame({ localStorage: storage });
    g2.StickerTypes.get(d.id).unlock = LOCK("cardsBuried", 5);
    r.eq(g2.ItemUnlocks.checkNewUnlocks().length, 0, "the stamp survives a reload (no repeat toast)");
  }
  {
    // RETROACTIVE: a veteran already past the threshold on FIRST load gets the
    // full derived set stamped SILENTLY — checkNewUnlocks can never toast it.
    const storage = memStorage();
    const g = loadGame({ localStorage: storage });
    const d = g.StickerTypes.grantable()[0];
    d.unlock = LOCK("cardsBuried", 5);
    g.Stats.reset();
    g.Stats.bump("cardsBuried", 50);   // long past the gate
    // UNLOCK2: boot priming stamped at load (zero stats) — model the
    // veteran's TRUE first load on this build by clearing the known-set so
    // the next call is the first-ever init WITH the big stats present.
    g.ItemUnlocks.reset();
    g.ItemUnlocks.markClimbDone();   // v5.60
    r.eq(g.ItemUnlocks.checkNewUnlocks().length, 0,
      "first load past the threshold: retroactive silent init — zero toasts");
    r.ok((JSON.parse(storage.getItem("ninelives.itemunlocks.v1")).known || []).indexOf(d.id) !== -1,
      "…the derived set (incl. the gated item) stamped quietly");
    r.ok(g.ItemUnlocks.isUnlocked(d), "…the item IS unlocked (gating is derived live, not known-set)");
    // Ship state: no gates → nothing can ever surface.
    const g3 = loadGame({ localStorage: memStorage() });
    r.eq(g3.ItemUnlocks.checkNewUnlocks().length, 0, "with zero unlock fields checkNewUnlocks only ever returns []");
  }

  // ── nearestLocked: closest-to-unlocking first, n respected ──────────────
  {
    const storage = memStorage();
    const { ItemUnlocks, StickerTypes, PillarTypes, Stats } = loadGame({ localStorage: storage });
    ItemUnlocks.markClimbDone();   // v5.60
    Stats.reset();
    // UNLOCK2: the live catalog now carries real gates, so nearestLocked is
    // never empty — assert ORDERING on injected markers with progress
    // fractions ABOVE every real zero-stat gate (0.5 and 0.25 beat 0/…).
    const a = StickerTypes.grantable()[0]; a.unlock = LOCK("cardsBuried", 10);
    const b = PillarTypes.all()[0];      b.unlock = LOCK("pilesLost", 4);
    Stats.bumpAll({ cardsBuried: 5, pilesLost: 1 });   // fractions .5 vs .25
    const nearAll = ItemUnlocks.nearestLocked(200);
    const posA = nearAll.findIndex(u => u.id === a.id);
    const posB = nearAll.findIndex(u => u.id === b.id);
    r.ok(posA !== -1 && posB !== -1, "nearestLocked includes both injected locked items");
    r.ok(posA < posB, "…closest-first (higher progress fraction wins)");
    // Real gates on the SAME stats sit behind the markers only if their
    // fraction is lower; every other zero-progress gate must rank below A.
    r.ok(posA < nearAll.findIndex(u => u.current === 0),
      "…zero-progress real gates rank below the .5-progress marker");
    r.eq(nearAll[posA].current, 5, "…carrying the live current count");
    r.eq(nearAll[posA].count, 10, "…and the gate count");
    r.eq(ItemUnlocks.nearestLocked(1).length, 1, "…n caps the list");
    r.eq(ItemUnlocks.nearestLocked(0).length, 0, "…n=0 returns nothing");
    Stats.bump("cardsBuried", 5);   // a unlocks (10/10) — b stays
    const nearAfter = ItemUnlocks.nearestLocked(200);
    r.ok(nearAfter.every(u => u.id !== a.id), "an item that reaches its gate leaves nearestLocked");
    r.ok(nearAfter.some(u => u.id === b.id), "…the still-locked marker remains");
  }

  // ── Exhibition gates: CampaignState-internal increments (behavioral) ────
  {
    const storage = memStorage();
    const g = loadGame({ localStorage: storage });
    const { CampaignState, Stats } = g;
    Stats.reset();
    // NORMAL run: applySticker / removeDeckCard bump their counters.
    const c = CampaignState.create();
    c.reset();
    const card = c.getRunDeck().find(x => !x.joker && !x.blank);
    r.ok(c.applySticker(card.id, "tieSafe"), "normal run: a player sticker applies");
    r.eq(Stats.get().stickersApplied, 1, "…stickersApplied increments");
    const victim = c.getRunDeck().find(x => !x.joker && !x.blank && x.id !== card.id);
    r.ok(c.removeDeckCard(victim.id), "normal run: a card removes");
    r.eq(Stats.get().removalsUsed, 1, "…removalsUsed increments");
    // EXHIBITION run (player-entered seed): the same flows bank NOTHING.
    const x = CampaignState.create();
    x.setSeedOverride(7);
    x.reset();
    r.ok(x.isExhibition(), "a player-entered seed flags the run exhibition");
    const xcard = x.getRunDeck().find(cd => !cd.joker && !cd.blank);
    r.ok(x.applySticker(xcard.id, "tieSafe"), "exhibition: the sticker still APPLIES (play is unchanged)");
    r.eq(Stats.get().stickersApplied, 1, "…but stickersApplied does NOT move");
    const xvictim = x.getRunDeck().find(cd => !cd.joker && !cd.blank && cd.id !== xcard.id);
    r.ok(x.removeDeckCard(xvictim.id), "exhibition: the removal still works");
    r.eq(Stats.get().removalsUsed, 1, "…but removalsUsed does NOT move");
    // Lammy prefill: normal run banks the prefill counts; exhibition doesn't.
    const lam = CampaignState.create();
    lam.setDeck("lammy"); lam.setTier("regular"); lam.reset();
    const pCount = lam.getColumnPillars().filter(Boolean).length;
    const bCount = lam.getColumnBases().filter(Boolean).length;
    r.ok(pCount > 0 && bCount > 0, "Lammy pre-equips pillars + bases at run start");
    r.eq(Stats.get().pillarsPlaced, pCount, "…the prefill counts as placements (pillars)");
    r.eq(Stats.get().basesPlaced, bCount, "…(bases)");
    const xlam = CampaignState.create();
    xlam.setDeck("lammy"); xlam.setTier("regular"); xlam.setSeedOverride(7); xlam.reset();
    r.ok(xlam.isExhibition() && xlam.getColumnPillars().filter(Boolean).length > 0,
      "exhibition Lammy still pre-equips");
    r.eq(Stats.get().pillarsPlaced, pCount, "…but the exhibition prefill banks nothing");
    r.eq(Stats.get().basesPlaced, bCount, "…(bases neither)");
  }

  // ── Exhibition gates + emits: app-side sites (source-contract pins) ──────
  // The UI event switch / onRunEnd aren't harness-reachable — pin the wiring
  // (stklag2/seeds idiom): every increment sits behind the exhibition/zen gate.
  {
    const src = gameSource();
    r.ok(src.includes('if (!zenMode && !(campaign.isExhibition && campaign.isExhibition())) Stats.bump("cardsBuried", payload.count || 0);'),
      'the "buried" listener bumps cardsBuried gated (zen + exhibition)');
    r.ok(src.includes('if (!zenMode && !(campaign.isExhibition && campaign.isExhibition())) Stats.bump("pilesLost");'),
      'the "pile-killed" listener bumps pilesLost gated');
    r.ok(src.includes('if (!exhibition && clearedNode && !wasAmbush && clearedNode.type === "boss") Stats.bump("bossesBeaten");'),
      "the boss-clear bump is gated (exhibition) and ambush-aware");
    r.ok(src.includes("if (!exhibition) Stats.addLostDealCoins((payload.run && payload.run.bonusCoins) || 0);"),
      "the lost-deal coin fold is gated (exhibition)");
    r.ok(src.includes("deltas.samesCalled = 1") && src.includes("deltas.correctSames = 1")
      && src.includes("deltas.jokersPlayed = 1"),
      "the resolved-draw handler folds sames/correct-sames/jokers");
    r.ok(src.includes("Stats.bumpAll(deltas);"),
      "…in ONE batched write");
    // coinsEarnedLifetime: the fold rides the LOSS path ONLY — a won deal's
    // coins already ride Stats.runCleared's payout fold (no double count).
    r.eq(countOf(src, "addLostDealCoins("), 2,
      "addLostDealCoins has exactly ONE call site (the loss path; the other hit is its definition)");
    // The engine emits pile-killed at every IN-PLAY pile death (kamikaze, the
    // suit-kill pillar, the fatal guess) — and the debug loseNow() sweep does
    // NOT emit (QA can't pad the stat).
    r.eq(countOf(src, 'emit("pile-killed"'), 3, "the engine emits pile-killed at the 3 in-play kill sites");
    const loseAt = src.indexOf("loseNow()");
    const loseBody = loseAt === -1 ? "" : src.slice(loseAt, src.indexOf("\n      },", loseAt));
    r.ok(loseBody.length > 0 && !loseBody.includes("pile-killed"),
      "the debug loseNow() sweep deliberately does NOT emit pile-killed");
    // Every CampaignState-internal bump site gates on the exhibition flag.
    r.ok(src.includes('if (applied && !exhibition) Stats.bump("stickersApplied");'),
      "applySticker's bump gated");
    r.ok(src.includes('if (!exhibition) Stats.bump("removalsUsed");'), "removeDeckCard's bump gated");
    r.ok(src.includes('if (!exhibition) Stats.bump("pillarsPlaced");'), "placePillar's bump gated");
    r.ok(src.includes('if (!exhibition) Stats.bump("basesPlaced");'), "placeBase's bump gated");
    // UNGATED by design: the cursed bane pool + the debug grants (documented).
    const cursedAt = src.indexOf('ItemData.stickers.filter(t => t.cursed === true)');
    r.ok(cursedAt !== -1 && src.slice(Math.max(0, cursedAt - 300), cursedAt).includes("UNGATED by design"),
      "the cursed bane pool documents its UNGATED-by-design status");
    const dbgAt = src.indexOf("function buildDebugGrants()");
    r.ok(dbgAt !== -1 && src.slice(Math.max(0, dbgAt - 400), dbgAt).includes("UNGATED by design"),
      "the debug grants document their UNGATED-by-design status");
  }

  // ── Stage B UI pins (source-contract idiom — the app scope isn't harness-
  //    reachable, so the wiring is pinned on the source; stklag2/seeds idiom) ──
  {
    const src = gameSource();
    const html = readFileSync(join(HERE, "..", "index.html"), "utf8");
    const bodyOf = (startMark, endMark) => {
      const a = src.indexOf(startMark);
      if (a === -1) return "";
      const b = endMark ? src.indexOf(endMark, a) : src.length;
      return src.slice(a, b === -1 ? src.length : b);
    };
    const runEndBody = bodyOf("function onRunEnd(result, payload)", "function continueCampaign()");
    const celebrBody = bodyOf("function maybeShowUnlockCelebration(onDone)", "function itemKindOf(def)");
    const failedBody = bodyOf("function showCampaignFailed(run)", "function showPinkyHome()");
    const homeBody = bodyOf("function showPinkyHome()", "function enterEndlessMode()");
    const overlayBody = bodyOf("function showOverlay(opts)", "function setScreenNav(");
    const menuBody = bodyOf("function showMainMenu(canContinue)", "function hideMainMenu()");
    const colBody = bodyOf("const COLLECTION_GROUPS = [", "function startZen(diffId)");

    // ── The toast queue: exists, reveals, sounds, drains one pop per CONTINUE ──
    r.ok(src.includes("function queueItemUnlockPops(unlocks, onDone)"),
      "UNLOCK1 UI: the item-unlock pop queue exists");
    r.ok(src.includes("const u = queue.shift();")
      && src.includes("if (!u) { if (rest) showItemUnlockSummaryPop(rest, onDone); else onDone(); return; }"),
      "…it drains one pop at a time; empty queue → summary tail or onDone straight through");
    r.ok(src.includes("function showItemUnlockPop(u, onNext)"),
      "…the single-pop presenter exists");
    const popBody = bodyOf("function showItemUnlockPop(u, onNext)", "function queueItemUnlockPops");
    r.ok(popBody.includes('"deck-unlock-pop item-unlock-pop"') && popBody.includes("iuc-objwrap"),
      "…each pop rides the deck-unlock idiom (silhouette object wrap)");
    r.ok(popBody.includes("prefersReduce() ? 80 : 800") && popBody.includes('wrap.classList.add("revealed")'),
      "…the reveal flips after ~800ms (80ms under reduced motion)");
    r.ok(popBody.includes("Sound.deckUnlock()") && popBody.includes("duc-spark s1"),
      "…with the ta-daa + sparkles");
    r.ok(popBody.includes("escHtml(u.hint)") && popBody.includes("KIND_LABEL[kind]"),
      "…name + class label + the derived hint (escHtml'd, never hand-written)");
    r.ok(popBody.includes("wrap.remove();") && popBody.includes("onNext();"),
      "…CONTINUE removes the pop and drains the next one");

    // ── checkNewUnlocks: exactly the known checkpoints, once per path ──
    r.eq(countOf(src, "ItemUnlocks.checkNewUnlocks()"), 4,
      "checkNewUnlocks has exactly 4 call sites (run-loss, run-termination, Zen end, the debug unlock-all's silent stamp — UNLOCK3)");
    // UNLOCK3: pops NEVER fire at a mid-run deal end — the deal-summary path
    // must not call checkNewUnlocks at all (a call there would stamp the
    // known-set and swallow the run-end pops).
    const dealSummaryZone = src.slice(src.indexOf("const showDealSummary"), src.indexOf("const showDealSummary") + 400);
    r.ok(!dealSummaryZone.includes("checkNewUnlocks"),
      "the deal-end summary path never checks/stamps unlocks (they surface at run termination)");
    // UNLOCK2 boot-priming: the known-set baseline is pinned BEFORE any play,
    // so a fresh profile's FIRST session pops its crossings (the lazy init at
    // a game-end checkpoint used to swallow them).
    r.ok(src.includes("ItemUnlocks.primeKnown()"),
      "the known-set is primed at boot (fresh profiles pop first-session unlocks)");
    // FIRST-CLIMB GATE (v5.60): nothing gated unlocks until a CLIMB run ends —
    // the tutorial Zen round must never hand out items.
    r.ok(src.includes('const CLIMB_PREF = "firstClimbDone";'), "the first-climb pref exists");
    const iu = bodyOf("function isUnlocked(def)", "/** Every item def across");
    r.ok(iu.includes("if (!climbDone()) return false;"),
      "…isUnlocked keeps GATED items shut until the first climb ends");
    r.ok(bodyOf("function climbDone()", "function markClimbDone()").includes("if (!ok()) return true;"),
      "…and FAILS OPEN with no storage (private mode / harness never locks everything)");
    // Stamped at BOTH campaign terminations, never by the Zen checkpoint.
    r.ok(countOf(src, "ItemUnlocks.markClimbDone()") >= 3,
      "…armed at run termination (win/stop + loss) and by the debug unlock-all");
    const zenTail = src.slice(src.indexOf("const show = () => queueItemUnlockPops"), src.indexOf("const show = () => queueItemUnlockPops") + 300);
    r.ok(!zenTail.includes("markClimbDone"),
      "…the ZEN end checkpoint never arms it (a Zen round is not a climb)");
    // CEREMONY CAP (v5.51): at most MAX_SOLO_POPS solo pops; the tail
    // collapses into ONE summary pop — a big climb is never a long click-through.
    r.ok(src.includes("const MAX_SOLO_POPS = 3;"), "the solo-pop cap exists (3)");
    const qip = bodyOf("function queueItemUnlockPops(unlocks, onDone)", "function showItemUnlockSummaryPop");
    r.ok(qip.includes("queue.splice(MAX_SOLO_POPS)") && qip.includes("showItemUnlockSummaryPop(rest, onDone)"),
      "…overflow splices into the summary pop");
    r.ok(qip.includes("MAX_SOLO_POPS + 1"),
      "…a single overflow item still pops solo (no \"1 more\" summary)");
    const sump = bodyOf("function showItemUnlockSummaryPop(unlocks, onNext)", "/* The death/win overlay");
    r.ok(sump.includes("more items unlocked") && sump.includes("duc-continue"),
      "the summary pop lists the count with ONE continue");
    r.eq(countOf(runEndBody, "ItemUnlocks.checkNewUnlocks()"), 1,
      "…onRunEnd holds ONLY the loss (run-over) site — deal wins never check (UNLOCK3)");
    r.ok(runEndBody.includes("queueItemUnlockPops(ItemUnlocks.checkNewUnlocks(), () => showCampaignFailed(payload.run))"),
      "…the loss path queues the pops BEFORE the death overlay (a loss ENDS the run)");
    r.ok(runEndBody.includes("const showDealSummary = () => showRunComplete(coins);"),
      "…the deal-clear summary shows with NO unlock check — crossings wait for run termination");
    r.eq(countOf(celebrBody, "ItemUnlocks.checkNewUnlocks()"), 1,
      "…run end (maybeShowUnlockCelebration) is the one second checkpoint");
    r.ok(celebrBody.indexOf("pendingUnlockCelebration = null") < celebrBody.indexOf("ItemUnlocks.checkNewUnlocks()"),
      "…and it fires AFTER any deck-unlock pop (the pop consumes first)");

    // ── The death/win "almost there" rows are RETIRED (v5.64, player
    // request: the summary was too busy). nearestLocked() itself stays —
    // it is still the Collection's ordering helper and a tested unit.
    r.ok(!html.includes('id="overlayUnlocks"'), "the #overlayUnlocks section is gone");
    r.ok(!src.includes("unlockProgressHtml"), "…and its row builder with it");
    r.ok(!failedBody.includes("nearestLocked") && !homeBody.includes("nearestLocked"),
      "…neither end screen passes an unlock list any more");
    r.eq(loadGame({ localStorage: memStorage() }).ItemUnlocks.nearestLocked(2).length, 2,
      "…LIVE as of UNLOCK2: real gates exist, so the almost-there section has rows at zero stats");

    // ── The Collection screen ──
    r.ok(html.includes('id="collectionScreen"') && html.includes('id="colList"') && html.includes('id="colBack"'),
      "the Collection screen markup exists (screen + scroll list + corner Back)");
    r.ok(menuBody.includes('label: "Collection"'),
      "the main menu builds a Collection button");
    r.ok(menuBody.indexOf('label: "Stats"') !== -1
      && menuBody.indexOf('label: "Stats"') < menuBody.indexOf('label: "Collection"'),
      "…placed after Stats");
    r.ok(["stickers", "pillars", "bases", "samePowers", "packs"]
      .every(g => colBody.includes('group: "' + g + '"')),
      "…the screen renders all five classes from the registries");
    r.ok(colBody.includes("ItemUnlocks.isUnlocked(def)") && colBody.includes("escHtml(def.label)"),
      "…unlocked tiles render full art + name (escHtml'd)");
    r.ok(colBody.includes("col-tile locked") && colBody.includes("silhouette")
      && colBody.includes("ItemUnlocks.hintFor(def)") && colBody.includes("ulk-fill"),
      "…locked tiles render silhouette + derived hint + progress bar");
    r.ok(["stickerChip(", "pathwayBannerHtml(", "baseBannerHtml(", "packObjectHtml(", "samePowerBadgeHtml("]
      .every(f => src.includes(f)),
      "…tiles use the store's class renderers (stickerChip keeps the cursed identity)");
    r.ok(src.includes("attachStoreHoldHelp(el.colList") && src.includes('".col-tile[data-id]"'),
      "…hold-help is delegated ONCE at boot on the persistent list (unlocked tiles only)");
    r.ok(colBody.includes("setScreenNav(false, false, false)") && colBody.includes("updateBoardMotion()"),
      "…the screen pauses board motion behind it (the zenSelect pattern)");
    r.ok(src.includes("up(el.collectionScreen)"),
      "…boardVisible() counts it as a covering screen");
    // v5.23 raster flatten: ~102 filter/shadow-heavy tiles in one scroll column
    // hit iOS deferred raster (blank rows until scrolled past) — the list kills
    // per-tile filters + heavy shadows (locked silhouettes keep theirs).
    for (const sel of ["#colList .dcs-ic", "#colList .pennant .pb-cloth",
                       "#colList .base-banner.plaque .base-sym .ico", "#colList .pack-foil"])
      r.ok(html.includes(sel), "…collection flatten covers " + sel);
    const flatRule = html.match(/#colList \.pack-foil \{ filter: none; \}/);
    r.ok(!!flatRule, "…the four filter-heavy art layers go filter-less inside the list");
    r.ok(html.includes("#colList .dcs { box-shadow: none; }")
      && html.includes("#colList .dcs-gloss { display: none; }"),
      "…chips drop shadow + gloss inside the list");
    r.ok(!html.includes("#colList .silhouette"),
      "…locked silhouettes KEEP their defining brightness filter");
    // v5.24 tap detail: an unlocked tile tap opens the shared help popup with
    // lifetime usage lines from Telem (only nonzero counts render).
    r.ok(src.includes("itemSummary(id) {"),
      "…Telem exposes itemSummary(id) (bought / triggered / deals-active)");
    const detBody = bodyOf("function showCollectionItemDetail(kind, id)", "function attachStoreHoldHelp");
    r.ok(detBody.includes("itemHelpHtml(kind, id)") && detBody.includes("Telem.itemSummary(id)")
      && detBody.includes("Times bought: ") && detBody.includes("Effects triggered: ")
      && detBody.includes("Deals active: "),
      "…the detail popup = registry help + conditional usage lines");
    r.ok(html.includes("body:has(#collectionScreen:not(.hidden)) .card-info { z-index: 1500; }"),
      "…the popup is lifted above the z-1400 Collection screen");
    r.ok(src.includes('e.target.closest(".col-tile[data-id]")')
      && src.includes("showCollectionItemDetail(tile.dataset.kind, tile.dataset.id)")
      && src.includes("if (storeHoldSuppress) { storeHoldSuppress = false; return; }"),
      "…the tap is delegated ONCE at boot, hold-suppressed, unlocked tiles only");
    // v5.37 detail upgrade: the item's own art + ◀ ▶ paging without closing.
    r.ok(detBody.includes("unlockObjectHtml(kind, def)"),
      "…the detail shows the item's art via the SAME renderer its tile uses");
    r.ok(detBody.includes("data-col-page") && detBody.includes("collectionPageList()"),
      "…and emits the pager over the grid-order unlocked list (this caller only)");
    r.ok(detBody.includes('idx === 0 ? " disabled"') && detBody.includes('idx === list.length - 1 ? " disabled"'),
      "…arrows clamp at the ends (disabled, no wrap)");
    const cpl = bodyOf("function collectionPageList()", "function collectionRegistryFor");
    r.ok(cpl.includes("COLLECTION_GROUPS.forEach") && cpl.includes("ItemUnlocks.isUnlocked(def)"),
      "…the paging list is COLLECTION_GROUPS × items.js order, unlocked only");
    r.ok(src.includes('e.target.closest("[data-col-page]")'),
      "…arrow taps ride the boot-time delegated #cardInfo handler (invariant 3)");
  }

  return r.summary();
}
