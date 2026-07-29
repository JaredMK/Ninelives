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
    carrying the given unlock field source (raw JS text). */
function loadWithProbe(unlockSrc) {
  const probe = '{ id: "__unlockprobe", label: "Probe", icon: "?", kind: "rank", rankDelta: 1,'
    + ' tier: "common", price: 1, description: "probe", unlock: ' + unlockSrc + " },";
  const src = ITEMS_SRC.replace('stickers: [\n    { id: "rankUp",', "stickers: [\n    " + probe + '\n    { id: "rankUp",');
  if (src === ITEMS_SRC) throw new Error("probe anchor not found in items.js");
  return loadGame({ itemsSource: src });
}
const LOCK = (stat, count) => ({ type: "behavior", stat, count });
const BIG = 1e9;   // an unreachable threshold (finite, valid) — always locked

export function run() {
  const r = makeRunner("unlocks.test.mjs");

  // ── SHIP STATE: no entry carries an unlock field → pools are identical ──
  // NOTE FOR THE FIRST REAL GATE: the pins in this section (zero unlock
  // fields, grantable identity, checkNewUnlocks [], nearestLocked 0) pin
  // the NOTHING-LOCKED ship state and are EXPECTED to be rewritten when the
  // first items.js entry gains a real `unlock` — relax them to skip gated
  // defs dynamically rather than deleting them.
  {
    const { ItemData, StickerTypes } = loadGame();
    const groups = ["stickers", "pillars", "bases", "samePowers", "packs"];
    const withUnlock = [];
    for (const g of groups)
      for (const d of ItemData[g]) if (d.unlock != null) withUnlock.push(g + "." + d.id);
    r.eq(withUnlock.length, 0, "SHIP STATE: no items.js entry carries an `unlock` field"
      + (withUnlock.length ? " (" + withUnlock.join(", ") + ")" : ""));
    // With zero gates the unlock filter is the identity: grantable() is exactly
    // the non-cursed pool, in registry order (byte-identical roll pools).
    r.eq(JSON.stringify(StickerTypes.grantable().map(t => t.id)),
      JSON.stringify(StickerTypes.all().filter(t => !t.cursed).map(t => t.id)),
      "…grantable() === the non-cursed pool, in order (the filter is the identity)");
    r.ok(StickerTypes.grantable().length < StickerTypes.all().length,
      "…(sanity: cursed stickers still exist and stay excluded)");
    // items.js header documents the field, the 15 stats and the commented example.
    r.ok(ITEMS_SRC.includes("unlock") && ITEMS_SRC.includes('"milestone"') && ITEMS_SRC.includes('"behavior"'),
      "items.js header documents the unlock field + both types");
    r.ok(ITEMS_SRC.includes('unlock: { type: "behavior", stat: "cardsBuried", count: 15 }'),
      "…with the COMMENTED example row");
    const headerStats = ["dealsSurvived", "runsPlayed", "runsWon", "bossesBeaten",
      "endlessStagesReached", "coinsEarnedLifetime", "cardsBuried", "samesCalled",
      "correctSames", "jokersPlayed", "stickersApplied", "pillarsPlaced",
      "basesPlaced", "removalsUsed", "pilesLost"];
    r.ok(headerStats.every(s => ITEMS_SRC.includes(s)), "…listing all 15 supported stats");
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
      "basesPlaced", "removalsUsed", "pilesLost"];
    r.eq(JSON.stringify(ItemUnlocks.STATS), JSON.stringify(EXPECTED),
      "ItemUnlocks.STATS is exactly the documented 15-name list");
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
    r.ok(EXPECTED.every(n => {
      const h = ItemUnlocks.hintFor({ unlock: LOCK(n, 7) });
      return typeof h === "string" && h.length > 0 && h.indexOf("7") !== -1;
    }), "hintFor derives non-empty copy carrying the count for all 15 stats");
    r.eq(ItemUnlocks.hintFor({ id: "x" }), "", "…and \"\" for a starting item (no gate)");
    r.eq(ItemUnlocks.hintFor({ unlock: LOCK("cardsBuried", 15) }), "Bury 15 cards",
      "…the plan's example phrasing (\"Bury 15 cards\")");
    r.eq(ItemUnlocks.hintFor({ unlock: LOCK("runsWon", 3) }), "Win 3 runs", "…(\"Win 3 runs\")");
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
    const { CampaignState, StickerTypes, PillarTypes, ItemData } = loadGame();
    // grantable(): lock one sticker → excluded, order of the rest preserved.
    const victim = StickerTypes.grantable()[0];
    victim.unlock = LOCK("cardsBuried", BIG);
    r.ok(StickerTypes.grantable().every(t => t.id !== victim.id),
      "a locked sticker leaves grantable()");
    r.eq(JSON.stringify(StickerTypes.grantable().map(t => t.id)),
      JSON.stringify(StickerTypes.all().filter(t => !t.cursed && t.id !== victim.id).map(t => t.id)),
      "…the rest unchanged, in order");
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
    g.Stats.bump("cardsBuried", 50);   // long past the gate before ANY ItemUnlocks call
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
    Stats.reset();
    const a = StickerTypes.grantable()[0]; a.unlock = LOCK("cardsBuried", 10);
    const b = PillarTypes.all()[0];      b.unlock = LOCK("pilesLost", 4);
    Stats.bumpAll({ cardsBuried: 5, pilesLost: 1 });   // fractions .5 vs .25
    const near2 = ItemUnlocks.nearestLocked(2);
    r.eq(near2.length, 2, "nearestLocked(2) returns both locked items");
    r.eq(near2[0].id, a.id, "…closest-first (higher progress fraction wins)");
    r.eq(near2[1].id, b.id, "…then the further one");
    r.eq(near2[0].current, 5, "…carrying the live current count");
    r.eq(near2[0].count, 10, "…and the gate count");
    r.eq(ItemUnlocks.nearestLocked(1).length, 1, "…n caps the list");
    r.eq(ItemUnlocks.nearestLocked(0).length, 0, "…n=0 returns nothing");
    Stats.bump("cardsBuried", 5);   // a unlocks (10/10) — only b stays
    const near1 = ItemUnlocks.nearestLocked(5);
    r.eq(near1.length, 1, "an item that reaches its gate leaves nearestLocked");
    r.eq(near1[0].id, b.id, "…leaving the still-locked one");
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
    const progressBody = bodyOf("function unlockProgressHtml(u)", null);

    // ── The toast queue: exists, reveals, sounds, drains one pop per CONTINUE ──
    r.ok(src.includes("function queueItemUnlockPops(unlocks, onDone)"),
      "UNLOCK1 UI: the item-unlock pop queue exists");
    r.ok(src.includes("const u = queue.shift();") && src.includes("if (!u) { onDone(); return; }"),
      "…it drains one pop at a time, empty queue → onDone straight through (no UI)");
    r.ok(src.includes("function showItemUnlockPop(u, onNext)"),
      "…the single-pop presenter exists");
    const popBody = bodyOf("function showItemUnlockPop(u, onNext)", "function unlockProgressHtml(u)");
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

    // ── checkNewUnlocks: exactly the TWO checkpoints, once per path ──
    r.eq(countOf(src, "ItemUnlocks.checkNewUnlocks()"), 3,
      "checkNewUnlocks has exactly 3 call sites (deal-end loss path, deal-end win path, run end)");
    r.eq(countOf(runEndBody, "ItemUnlocks.checkNewUnlocks()"), 2,
      "…onRunEnd (deal end) holds the two mutually-exclusive branch sites");
    r.ok(runEndBody.includes("queueItemUnlockPops(ItemUnlocks.checkNewUnlocks(), () => showCampaignFailed(payload.run))"),
      "…the loss path queues the pops BEFORE the death overlay");
    r.ok(runEndBody.includes("const freshUnlocks = ItemUnlocks.checkNewUnlocks();")
      && runEndBody.includes("queueItemUnlockPops(freshUnlocks, () => showRunComplete(coins))"),
      "…the win path checks once, then queues the pops ahead of the deal-clear summary");
    r.eq(countOf(celebrBody, "ItemUnlocks.checkNewUnlocks()"), 1,
      "…run end (maybeShowUnlockCelebration) is the one second checkpoint");
    r.ok(celebrBody.indexOf("pendingUnlockCelebration = null") < celebrBody.indexOf("ItemUnlocks.checkNewUnlocks()"),
      "…and it fires AFTER any deck-unlock pop (the pop consumes first)");

    // ── The death/win "nearest unlocks" overlay section ──
    r.ok(html.includes('id="overlayUnlocks"'), "the overlay carries the #overlayUnlocks section");
    r.ok(overlayBody.includes("ups.map(unlockProgressHtml)")
      && overlayBody.includes('el.overlayUnlocks.classList.toggle("hidden", !ups.length)'),
      "…showOverlay renders it from opts.unlocks and hides it when empty/absent");
    r.ok(progressBody.includes("silhouette") && progressBody.includes("ulk-fill")
      && progressBody.includes("hintFor"),
      "…each row: silhouette tile + derived remaining hint + progress bar");
    r.ok(failedBody.includes("unlocks: ItemUnlocks.nearestLocked(2)"),
      "…the death screen passes the section (nearest 2)");
    r.ok(homeBody.includes("unlocks: ItemUnlocks.nearestLocked(2)"),
      "…the win screen passes it too");
    r.eq(loadGame().ItemUnlocks.nearestLocked(2).length, 0,
      "…INERT AT SHIP: no unlock fields → the section can only ever be empty");

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
  }

  return r.summary();
}
