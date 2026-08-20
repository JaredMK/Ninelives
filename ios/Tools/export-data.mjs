#!/usr/bin/env node
/* ============================================================================
   export-data.mjs — the DATA BRIDGE from the web build to the iOS build.

   The three JS data files at the repo root stay the single hand-editable
   source of truth (AGENTS.md convention 1). This script evaluates them exactly
   as the browser does and writes a byte-faithful JSON mirror into
   ios/Resources/, which the GameCore framework bundles and Codable-decodes.

   Run it after ANY edit to items.js / difficulty.js / tutorial.js:

       node ios/Tools/export-data.mjs

   It writes:
       ios/Resources/items.json
       ios/Resources/difficulty.json
       ios/Resources/tutorial.json
       ios/Resources/meta.json        (ITEM_UNLOCK_STATS + DECK_RULES, lifted
                                       out of index.html so Swift never
                                       hardcodes them either)

   Ordering is preserved: JSON.stringify walks arrays and object keys in
   insertion order, and the Swift side decodes arrays positionally, so registry
   order (which drives store rolls and `ids`) survives the crossing exactly.
============================================================================ */
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, "..", "..");
const OUT = join(HERE, "..", "Resources");

/** Evaluate one `const NINELIVES_X = {...}` data file and hand back the value. */
function loadDataFile(file, globalName) {
  const src = readFileSync(join(REPO, file), "utf8");
  const ctx = vm.createContext({});
  vm.runInContext(src + "\n;globalThis.__out = " + globalName + ";", ctx, { filename: file });
  const out = ctx.__out;
  if (out === undefined || out === null) throw new Error(`${file}: ${globalName} is not defined`);
  return out;
}

/** Pull a top-level `const NAME = <literal>;` out of index.html by evaluating it. */
function liftFromIndex(name) {
  const html = readFileSync(join(REPO, "index.html"), "utf8");
  const head = new RegExp("^const " + name + " = ", "m").exec(html);
  if (!head) throw new Error(`index.html: could not find \`const ${name}\``);
  const start = head.index + head[0].length;
  const open = html[start];
  if (open !== "[" && open !== "{") throw new Error(`index.html: \`${name}\` is not an array/object literal`);
  // The literal ends at the FIRST closing bracket of the same kind sitting at
  // column 0 (index.html indents every nested line), so nested literals and any
  // brackets inside comments/strings below are never mistaken for the end.
  const close = open === "[" ? "\n];" : "\n};";
  const end = html.indexOf(close, start);
  if (end === -1) throw new Error(`index.html: \`${name}\` literal is unterminated`);
  const literal = html.slice(start, end + close.length - 1);
  const ctx = vm.createContext({});
  vm.runInContext("globalThis.__out = " + literal, ctx, { filename: `index.html:${name}` });
  return ctx.__out;
}

mkdirSync(OUT, { recursive: true });

const items = loadDataFile("items.js", "NINELIVES_ITEMS");
const difficulty = loadDataFile("difficulty.js", "NINELIVES_DIFFICULTY");
const tutorial = loadDataFile("tutorial.js", "NINELIVES_TUTORIAL");
/* NATIVE-ONLY UNLOCK STATS — counters the Swift port tracks that the web
   build never bumps (the same pattern as NATIVE_ONLY_* in export-traces.mjs).
   Appended to the lifted list so items.js may key unlocks off them without
   touching index.html. */
const NATIVE_ONLY_UNLOCK_STATS = ["ambushesWon", "earlyLosses"];

/* NATIVE DECK IDENTITY (v6.67) — the character overhaul renames Mr. Smith →
   Mr. Garden and Lammy → Rocko, adds Slyrex, and re-cuts the rules per deck.
   The web build keeps its own legacy roster, so the remap happens HERE at the
   crossing (the NATIVE_ONLY_* pattern), never in index.html. Rule changes vs
   the lifted web rules:
   - garden (was smith): "as Pinky, except every card carries a random
     sticker" — priceMult back to 1 (the 2× shop was Smith's identity, not
     Garden's), stickerEverything on, and NO Pillars/Bases (can't equip them,
     stores never offer them).
   - rocko (was lammy): unchanged rules (noStickers + preEquip), and preEquip
     now also grants a random Same-Power (CampaignState reads the same flag).
   - slyrex (new): as Pinky, with a fixed-rank start: six 2s, six Aces, one 8
     (startRanks, rank value → count; A = 14). */
function nativeDeckRules(lifted) {
  const out = {
    pink: lifted.pink,
    mamma: lifted.mamma,
    slyrex: { ...lifted.pink, startRanks: { 2: 6, 14: 6, 8: 1 } },
    garden: { ...lifted.smith, priceMult: 1, startStickers: false,
              stickerEverything: true, noPillarsBases: true },
    rocko: lifted.lammy,
  };
  return out;
}

const meta = {
  // Deduped: index.html has since absorbed the native-only names into its own
  // list (they must be there for the web-side items.js validator), so the
  // append would otherwise write them twice into meta.json.
  itemUnlockStats: [...new Set([...liftFromIndex("ITEM_UNLOCK_STATS"), ...NATIVE_ONLY_UNLOCK_STATS])],
  deckRules: nativeDeckRules(liftFromIndex("DECK_RULES")),
};

/* JSON has no NaN/Infinity — JSON.stringify silently turns them into null, which
   would drop a knob instead of failing loudly. Catch it HERE, at the crossing,
   so a bad hand-edit still fails loud (items.js's own validator does the same
   check on the web side). */
function assertFinite(value, path) {
  if (typeof value === "number") {
    if (!Number.isFinite(value)) throw new Error(`non-finite number at ${path} (${value}) — fix the data file`);
    return;
  }
  if (Array.isArray(value)) { value.forEach((v, i) => assertFinite(v, `${path}[${i}]`)); return; }
  if (value && typeof value === "object") { for (const k of Object.keys(value)) assertFinite(value[k], `${path}.${k}`); }
}

const write = (name, value) => {
  assertFinite(value, name.replace(/\.json$/, ""));
  const json = JSON.stringify(value, null, 2) + "\n";
  writeFileSync(join(OUT, name), json, "utf8");
  console.log(`  ${name.padEnd(16)} ${json.length.toString().padStart(7)} bytes`);
};

console.log("export-data.mjs → ios/Resources/");
write("items.json", items);
write("difficulty.json", difficulty);
write("tutorial.json", tutorial);
write("meta.json", meta);

// A quick sanity echo so a bad export is obvious in the terminal.
console.log(
  `  items: ${items.stickers.length} stickers, ${items.pillars.length} pillars, ` +
  `${items.bases.length} bases, ${items.samePowers.length} same-powers, ${items.packs.length} packs`
);
console.log(`  difficulty: tiers ${Object.keys(items ? difficulty.tiers : {}).join("/")}; zen ${Object.keys(difficulty.zen).join("/")}`);
console.log(`  meta: ${meta.itemUnlockStats.length} unlock stats, decks ${Object.keys(meta.deckRules).join("/")}`);
