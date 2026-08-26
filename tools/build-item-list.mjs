#!/usr/bin/env node
/* ===========================================================================
   BUILD ITEM-LIST.HTML — the human-readable reference for every item in the
   game, generated FROM the item data so it can never drift.

       node tools/build-item-list.mjs        # writes item-list.html

   SOURCE OF TRUTH: `items.js` at the repo root — the hand-editable home for
   every item (AGENTS.md Convention 1). It is read directly (evaluated in a
   throwaway VM context), NOT via the exported ios/Resources/items.json, so
   the report is current the moment items.js is saved, with no `make data`
   step in between. The build version is lifted from BuildStamp in
   ios/UI/MenuScreens.swift so the title always names the build it describes.

   OUTPUT: a single self-contained HTML file — every byte of data is inlined
   at generation time, so it opens straight off the filesystem (file://)
   with no server and no fetch.

   IT ALSO LINTS. Four checks, rendered as tags on the offending row and
   collected in a summary box at the top:
     EMPTY     — missing/blank/placeholder help text.
     UNWIRED   — the text carries a {rank}/{suit}/{color} token but the item
                 has no substitution path, so players read generic filler.
                 The paths mirror CampaignState.itemDescription exactly (see
                 SUBSTITUTION below); a mismatch here means one of the two
                 drifted.
     "ROLLED"  — the retired v6.78 wording ("rolled rank/suit"). Player copy
                 names the actual value now; this should stay at zero.
     TEMPLATE  — informational, not an error: a token WITH a wired path,
                 substituted live before the player sees it.
   =========================================================================== */

import fs from "node:fs";
import path from "node:path";
import url from "node:url";
import vm from "node:vm";

const ROOT = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), "..");
const OUT = path.join(ROOT, "item-list.html");

// ── Load the data ──────────────────────────────────────────────────────────
const itemsSrc = fs.readFileSync(path.join(ROOT, "items.js"), "utf8");
// A `const` declaration is not a property of the VM context, so evaluate the
// file and then the bare identifier — the completion value IS the registry.
const ITEMS = vm.runInNewContext(itemsSrc + "\nNINELIVES_ITEMS");

// The build stamp, straight from the app's one version source.
const stampSrc = fs.readFileSync(path.join(ROOT, "ios/UI/MenuScreens.swift"), "utf8");
const VERSION = (stampSrc.match(/static let version = "([^"]+)"/) || [, "unknown"])[1];

// Is the game's exported copy in step with items.js? Purely informational —
// the report reads items.js either way, but a stale export means the running
// app does not yet show what is documented here.
let exportNote = "";
try {
  const jsMtime = fs.statSync(path.join(ROOT, "items.js")).mtimeMs;
  const jsonMtime = fs.statSync(path.join(ROOT, "ios/Resources/items.json")).mtimeMs;
  if (jsMtime > jsonMtime + 1000) {
    exportNote = "items.js is NEWER than ios/Resources/items.json — run <code>cd ios &amp;&amp; make data</code> "
      + "so the app ships what this page documents.";
  }
} catch { /* the export is optional for this report */ }

// ── SUBSTITUTION: which template tokens each item can actually fill ────────
// Mirrors CampaignState.itemDescription (iOS). Keep the two in step: if a new
// live-substituted effect appears there, add it here or this page will call
// it UNWIRED.
const RANK_LIVE_EFFECTS = new Set(["transmute", "rankShield"]);   // composition-driven, per display
const RANK_VARIANT_EFFECTS = new Set(["rankBury", "rankCoin"]);   // climb-locked pillarRankVariants
const SUIT_VARIANT_IDS = new Set(["linkBury"]);                   // samePowerVariant (suit)

function wiredTokens(item) {
  const wired = new Set();
  if (item.shopRoll === "rank" || item.shopRoll2 === "rank") wired.add("rank");
  if (item.shopRoll === "suit" || item.shopRoll2 === "suit") wired.add("suit");
  if (RANK_LIVE_EFFECTS.has(item.effect)) wired.add("rank");
  if (RANK_VARIANT_EFFECTS.has(item.effect)) wired.add("rank");
  if (SUIT_VARIANT_IDS.has(item.id)) { wired.add("suit"); wired.add("color"); }
  return wired;
}

function lint(item) {
  const flags = [];
  const desc = String(item.description ?? "").trim();
  if (!desc) flags.push({ tag: "EMPTY", kind: "err", why: "no help text" });
  else if (/\b(TODO|TBD|placeholder|lorem|xxx)\b/i.test(desc))
    flags.push({ tag: "EMPTY", kind: "err", why: "placeholder help text" });
  if (/\broll(ed|s|ing)?\b/i.test(desc))
    flags.push({ tag: '"ROLLED"', kind: "err", why: "retired v6.78 wording — name the real value" });
  const tokens = [...desc.matchAll(/\{(rank|suit|color)\}/g)].map((m) => m[1]);
  if (tokens.length) {
    const wired = wiredTokens(item);
    const unwired = [...new Set(tokens)].filter((t) => !wired.has(t));
    if (unwired.length)
      flags.push({ tag: "UNWIRED", kind: "err", why: `{${unwired.join("}, {")}} has no substitution path` });
    const ok = [...new Set(tokens)].filter((t) => wired.has(t));
    if (ok.length)
      flags.push({ tag: "TEMPLATE", kind: "info", why: `{${ok.join("}, {")}} substituted live` });
  }
  return flags;
}

// ── Classes, in the order the page presents them ──────────────────────────
const CLASSES = [
  { key: "sticker", title: "Stickers", note: "Card-bound imprints. A sticker rides one card for the rest of the climb — WHICH card is the decision.", items: ITEMS.stickers.filter((s) => !s.cursed) },
  { key: "pillar", title: "Pillars", note: "Column modifiers bound to the top of a board column — passive, all deal, every pile in that column.", items: ITEMS.pillars },
  { key: "base", title: "Bases", note: "Column artifacts bound to the bottom. Active: they charge each deal and fire once when tapped.", items: ITEMS.bases },
  { key: "samepower", title: "Same-Powers", note: "Exactly one is equipped; a correct Same triggers it.", items: ITEMS.samePowers },
  { key: "curse", title: "Cursed Stickers", note: "Never sold and never chosen — inflicted by the mystery node, the Old Joker's bargains and the bad door. Price 0.", items: ITEMS.stickers.filter((s) => s.cursed) },
  { key: "pack", title: "Packs", note: "Buy to reveal N random items and keep some.", items: ITEMS.packs },
];

// ── Helpers ────────────────────────────────────────────────────────────────
const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
const RARITY_ORDER = { common: 0, uncommon: 1, rare: 2 };

function unlockCell(item) {
  const u = item.unlock;
  if (!u) return '<span class="start">starting</span>';
  return `<span class="gate">${esc(u.type)}</span> <code>${esc(u.stat)}</code> ≥ ${esc(u.count)}`;
}

function priceCell(item) {
  if (item.kind === "card" || item.kind === "sticker") {
    // packs carry size/keep alongside price
    if (item.size != null) return `${esc(item.price)} <span class="dim">(${esc(item.size)}→keep ${esc(item.keep)})</span>`;
  }
  return item.price === 0 ? '<span class="dim">—</span>' : esc(item.price);
}

function suitChip(item) {
  if (!Array.isArray(item.suits) || !item.suits.length) return "";
  return ` <span class="suits" title="may only be applied to these suits">${esc(item.suits.join(""))}</span>`;
}

// ── Build ──────────────────────────────────────────────────────────────────
const allFlagged = [];
let body = "";

// Summary — the shape of the pool at a glance.
let summary = `<table class="summary"><tr><th>Class</th><th class="num">Total</th>`
  + `<th class="num">common</th><th class="num">uncommon</th><th class="num">rare</th>`
  + `<th class="num">starting</th><th class="num">gated</th></tr>`;
let grand = 0;
for (const cls of CLASSES) {
  const n = cls.items.length;
  grand += n;
  const by = (t) => cls.items.filter((i) => i.tier === t).length;
  const starting = cls.items.filter((i) => !i.unlock).length;
  summary += `<tr><td><a href="#${cls.key}">${esc(cls.title)}</a></td><td class="num">${n}</td>`
    + `<td class="num">${by("common")}</td><td class="num">${by("uncommon")}</td><td class="num">${by("rare")}</td>`
    + `<td class="num">${starting}</td><td class="num">${n - starting}</td></tr>`;
}
summary += `<tr class="total"><td>All items</td><td class="num">${grand}</td>`
  + `<td class="num" colspan="4"></td><td class="num"></td></tr></table>`;

for (const cls of CLASSES) {
  const rows = [...cls.items].sort((a, b) => {
    const r = (RARITY_ORDER[a.tier] ?? 9) - (RARITY_ORDER[b.tier] ?? 9);
    if (r) return r;
    return String(a.label).localeCompare(String(b.label));
  });
  body += `<h2 id="${cls.key}">${esc(cls.title)} <span class="note">(${rows.length})</span></h2>`;
  body += `<p class="note">${cls.note} Sorted by rarity, then name.</p>`;
  body += `<table><tr><th>Item</th><th>Rarity</th><th class="num">Cost</th><th>Unlock</th><th>In-game help text</th><th>Lint</th></tr>`;
  for (const item of rows) {
    const flags = lint(item);
    if (flags.some((f) => f.kind === "err" || f.tag === "TEMPLATE"))
      allFlagged.push({ cls: cls.title, item, flags });
    const tags = flags.map((f) => `<span class="tag ${f.kind}" title="${esc(f.why)}">${esc(f.tag)}</span>`).join(" ");
    const desc = String(item.description ?? "").trim();
    body += `<tr id="i-${esc(item.id)}">`
      + `<td><b>${esc(item.label)}</b>${suitChip(item)}<br><span class="id">${esc(item.id)}</span></td>`
      + `<td class="${esc(item.tier || "")}">${esc(item.tier || "—")}</td>`
      + `<td class="num">${priceCell(item)}</td>`
      + `<td class="unlock">${unlockCell(item)}</td>`
      + `<td>${desc ? esc(desc) : '<span class="missing">(none)</span>'}</td>`
      + `<td>${tags}</td></tr>`;
  }
  body += `</table>`;
}

// The lint summary box.
const errs = allFlagged.filter((f) => f.flags.some((x) => x.kind === "err"));
const infos = allFlagged.filter((f) => f.flags.every((x) => x.kind === "info"));
let lintBox = `<div class="lintbox"><h3>Lint — ${errs.length} problem${errs.length === 1 ? "" : "s"}, ${infos.length} informational</h3>`;
if (!errs.length) lintBox += `<p class="ok">✔ No empty help text, no unwired template tokens, no retired "rolled" wording.</p>`;
else {
  lintBox += `<ul>`;
  for (const f of errs)
    for (const x of f.flags.filter((x) => x.kind === "err"))
      lintBox += `<li><span class="tag err">${esc(x.tag)}</span> <a href="#i-${esc(f.item.id)}">${esc(f.item.label)}</a> <span class="id">${esc(f.item.id)}</span> — ${esc(x.why)}</li>`;
  lintBox += `</ul>`;
}
if (infos.length) {
  lintBox += `<p class="note"><b>Templates (expected):</b> these carry a token that is filled in before the player
    reads it — the shop's rolled value, the climb-locked variant, or a live deck reading.</p><ul class="dim">`;
  for (const f of infos)
    lintBox += `<li><a href="#i-${esc(f.item.id)}">${esc(f.item.label)}</a> <span class="id">${esc(f.item.id)}</span> — ${esc(f.flags[0].why)}</li>`;
  lintBox += `</ul>`;
}
lintBox += `</div>`;

const generatedAt = new Date().toISOString().replace("T", " ").slice(0, 16);
const html = `<!doctype html><html><head><meta charset="utf-8">
<title>Ninelives — Item List (${esc(VERSION)})</title>
<style>
body{background:#101410;color:#e8e4d5;font:15px/1.5 ui-monospace,Menlo,monospace;max-width:1180px;margin:24px auto;padding:0 16px}
h1{color:#ffd23f;font-size:22px;margin-bottom:2px}
h2{color:#4ef08a;font-size:18px;margin:32px 0 6px;border-bottom:1px solid #2c3a2c;padding-bottom:4px}
h3{color:#ffd23f;font-size:15px;margin:0 0 8px}
a{color:#8ecae6}
table{border-collapse:collapse;width:100%;margin:6px 0 14px}
td,th{border:1px solid #2c3a2c;padding:5px 8px;text-align:left;vertical-align:top}
th{color:#ffd23f;background:#18201a;position:sticky;top:0}
.num{text-align:right;white-space:nowrap}
.id{color:#5a6b5a;font-size:12px}
.dim{color:#8a9a8a}
.common{color:#e8e4d5}.uncommon{color:#8ecae6}.rare{color:#ffd23f}
.note{color:#8a9a8a;font-size:13px}
code{color:#4ef08a}
.start{color:#4ef08a}
.gate{color:#8a9a8a;font-size:12px}
.unlock{font-size:13px;white-space:nowrap}
.suits{color:#ffd23f;font-size:13px}
.missing{color:#ff6b6b;font-style:italic}
.tag{display:inline-block;padding:1px 5px;border-radius:2px;font-size:11px;font-weight:bold;white-space:nowrap}
.tag.err{background:#5c1f22;color:#ff8b8b;border:1px solid #ff6b6b}
.tag.info{background:#4a3c14;color:#ffd23f;border:1px solid #a8862c}
.lintbox{border:1px solid #2c3a2c;background:#151b15;padding:10px 14px;margin:14px 0 6px}
.lintbox ul{margin:4px 0 8px;padding-left:20px}
.ok{color:#4ef08a;margin:4px 0}
.summary td,.summary th{padding:4px 10px}
.summary tr.total td{color:#ffd23f;font-weight:bold;border-top:2px solid #2c3a2c}
.stale{border:1px solid #a8862c;background:#4a3c14;color:#ffd23f;padding:8px 12px;margin:10px 0}
</style></head><body>
<h1>NINELIVES — every item (${esc(VERSION)})</h1>
<p class="note">Generated from <code>items.js</code> — the hand-editable source of truth — by
<code>node tools/build-item-list.mjs</code> on ${esc(generatedAt)}. Every value below (name, rarity, cost,
unlock gate, help text) is read straight from the data, so this page cannot drift from the game.
Re-run the command after any items.js edit. Help text is the EXACT string the store, collection and
hold-help show.</p>
${exportNote ? `<div class="stale">⚠ ${exportNote}</div>` : ""}
${summary}
${lintBox}
${body}
<p class="note">Store config (shelf slots, class weights, the Purge slot, the Mystery Same-Power slot and the
single-card slot) lives in <code>items.js</code> under <code>store</code> and is deliberately not itemised here —
those are shelf mechanics, not items.</p>
</body></html>
`;

fs.writeFileSync(OUT, html);
console.log(`item-list.html written — ${grand} items across ${CLASSES.length} classes (${VERSION})`);
for (const cls of CLASSES) console.log(`  ${String(cls.items.length).padStart(3)}  ${cls.title}`);
console.log(errs.length ? `  LINT: ${errs.length} problem(s)` : "  LINT: clean");
if (exportNote) console.log("  NOTE: ios/Resources/items.json is older than items.js — run `cd ios && make data`");
