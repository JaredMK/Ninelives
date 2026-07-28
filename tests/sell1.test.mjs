// SELL1 — sell EQUIPPED pillars/bases/Same-Power from the store's loadout
// reference. The confirm rides the bottom prompt bar (never a modal), lifted
// over the store overlay via body.store-selling (a z-index lift on the
// control row, only while the confirm is pending);
// the sale reuses the setup-window SELL_VALUE/sellValueOf prices and the
// destroy-on-sell rule (buy-replace precedent). Structural checks pin the
// wiring shape (uifix1/zen1 style); behavioral checks drive the exact
// primitive sequence the confirm runs against LIVE registry items — every
// price is read from the live SELL_VALUE table, never a pinned 1/2/3.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadGame, makeRunner } from "./_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

function fullHtml() {
  return readFileSync(join(HERE, "..", "index.html"), "utf8");
}
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
/** The LIVE sell-price table + tier fallback, evaluated from the game script
    (SELL_VALUE is a rule of the setup sell flow, not an items.js tunable —
    reading it live keeps this suite pin-free if the table is ever rebalanced). */
function liveSellValue(src) {
  const m = src.match(/const SELL_VALUE = \{[^}]*\};/);
  if (!m) throw new Error("SELL_VALUE table not found in the game script");
  return new Function(m[0] + "\nreturn (t) => SELL_VALUE[t && t.tier] || 1;")();
}

export function run() {
  const r = makeRunner("sell1.test.mjs");
  const html = fullHtml();
  const src = gameScript(html);
  const g = loadGame();
  r.ok(!!(g.CampaignState && g.PillarTypes && g.BaseTypes && g.SamePowerTypes),
    "game script evaluates with the SELL1 wiring in place");
  const sellValueOf = liveSellValue(src);

  // --- R1) The detail panel carries an equipped-only Sell button -------------
  {
    r.ok(/<button[^>]*id="sdSell"[^>]*>/.test(html), "#sdSell button exists in the detail panel");
    const tag = html.match(/<button[^>]*id="sdSell"[^>]*>/)[0];
    r.ok(/class="[^"]*\bhidden\b[^"]*"/.test(tag), "#sdSell starts hidden (offer details never show it)");
    r.ok(/type="button"/.test(tag), "#sdSell is type=button (no implicit submit)");
    r.ok(/sdSell: document\.getElementById\("sdSell"\)/.test(src), "el.sdSell is registered in the element map");
    // No stylesheet rule ever backed .hidden on these buttons — the equipped
    // view's sdBuy hide was a silent no-op (a stale offer Buy stayed VISIBLE),
    // and the default-hidden Sell would render on offer details without it.
    r.ok(/\.sd-buy\.hidden \{ display: none; \}/.test(html),
      ".sd-buy.hidden actually hides (backs sdBuy's equipped-view hide + sdSell's offer-view hide)");
    // The equipped detail prices the action via sellValueOf (never a literal)
    // and shows the button only when the slot is identifiable.
    const eq = fnBody(src, "openEquippedDetail");
    r.ok(eq.includes('el.sdSell.innerHTML = "Sell for " + COIN_SVG + " " + sellValueOf(t)'),
      "openEquippedDetail labels Sell via sellValueOf(t) (tier price, no literal)");
    r.ok(/el\.sdSell\.classList\.toggle\("hidden", !sellable\)/.test(eq),
      "…and shows it only for a sellable target (samepower, or a pillar/base with its column)");
    r.ok(/kind === "samepower" \|\| \(Number\.isInteger\(col\) && col >= 0\)/.test(eq),
      "…where sellable = Same-Power or an integer column");
  }

  // --- R1) Pillar/base chips carry their column; the tap handler passes it ---
  {
    const chip = fnBody(src, "loadoutChip");
    r.ok(/data-lo-col=/.test(chip), "loadoutChip emits data-lo-col");
    r.ok(/col != null \? ' data-lo-col="' \+ col/.test(chip), "…only when a column is given (Same-Power has none)");
    const lo = fnBody(src, "renderStoreLoadout");
    r.ok(/loadoutChip\("pillar", pillars\[c\], c\)/.test(lo), "renderStoreLoadout passes the column to pillar chips");
    r.ok(/loadoutChip\("base", bases\[c\], c\)/.test(lo), "…and to base chips");
    r.ok(!/loadoutChip\("samepower", sp, /.test(lo), "…but not to the Same-Power chip");
    r.ok(/openEquippedDetail\(chip\.dataset\.loKind, chip\.dataset\.loId,\s*\n?\s*chip\.dataset\.loCol != null \? Number\(chip\.dataset\.loCol\) : null\)/.test(src),
      "the loadout tap handler forwards data-lo-col into openEquippedDetail");
  }

  // --- R2) Sell wiring shape: close the detail, then prompt-bar confirm ------
  {
    const at = src.indexOf('el.sdSell.addEventListener("click"');
    r.ok(at !== -1, "el.sdSell has a click handler");
    const handler = src.slice(at, at + 400);
    r.ok(handler.indexOf("closeStoreDetail()") !== -1
      && handler.indexOf("requestStoreSell(") !== -1
      && handler.indexOf("closeStoreDetail()") < handler.indexOf("requestStoreSell("),
      "the handler closes the detail BEFORE requesting the sell confirm");
    const req = fnBody(src, "requestStoreSell");
    r.ok(req.includes("showActionBar("), "requestStoreSell confirms via the bottom prompt bar");
    r.ok(req.includes("dismiss: closeStoreSellConfirm"), "…with outside-tap = Cancel (opts.dismiss)");
    r.ok(req.includes('help: "It won\'t return to your inventory."'),
      "…and the destroy-on-sell help line (matches the setup sell confirm)");
    r.ok(req.includes("sellValueOf(t)"), "…priced via sellValueOf (SELL_VALUE reuse, no literals)");
    r.ok(!req.includes("confirm-overlay") && !/\.showModal|window\.confirm/.test(req),
      "…and never a screen-blocking modal");
  }

  // --- R3) z-raise body class: added on request, removed on every exit -------
  {
    const req = fnBody(src, "requestStoreSell");
    const close = fnBody(src, "closeStoreSellConfirm");
    const confirm = fnBody(src, "confirmStoreSell");
    r.ok(req.includes('document.body.classList.add("store-selling")'),
      "requestStoreSell raises the prompt bar via body.store-selling");
    r.ok(close.includes('document.body.classList.remove("store-selling")'),
      "cancel/dismiss (closeStoreSellConfirm) drops the class");
    r.ok(confirm.includes('document.body.classList.remove("store-selling")'),
      "confirm drops the class too");
    // The lift must clear the store overlay: read BOTH z-indexes live from the
    // stylesheet and compare (never pin the values).
    const sellZ = html.match(/body\.store-selling \.play-controls \{[^}]*z-index:\s*(\d+)/);
    const overlayZ = html.match(/\n\s*\.overlay \{[^}]*z-index:\s*(\d+)/s);
    r.ok(!!sellZ, "body.store-selling .play-controls sets a z-index");
    r.ok(!!overlayZ, "(control) the .overlay base z-index is readable");
    r.ok(sellZ && overlayZ && Number(sellZ[1]) > Number(overlayZ[1]),
      `the lifted control row clears the store overlay (${sellZ && sellZ[1]} > ${overlayZ && overlayZ[1]})`);
  }

  // --- R5) The NEW confirm is store-scoped: overlay + slot-still-holds-id ----
  {
    const confirm = fnBody(src, "confirmStoreSell");
    r.ok(confirm.includes("!storeVisible()"), "confirmStoreSell no-ops unless the store is visible");
    r.ok(confirm.includes("campaign.columnPillar(p.col) === p.id"),
      "…and re-checks the pillar slot still holds the confirmed id");
    r.ok(confirm.includes("campaign.columnBase(p.col) === p.id"),
      "…and the base slot likewise");
    r.ok(confirm.includes("campaign.getSamePower() === p.id"),
      "…and the equipped Same-Power likewise");
    r.ok(!confirm.includes("canApplyStickers"),
      "…without the setup confirm's engine.canApplyStickers() guard (false in the store)");
    // Pure campaign state: the run/engine is only touched for the action log.
    r.ok(!/engine\.(?!logAction)/.test(confirm), "…and touches the engine only to logAction");
    r.ok(/logAction\("Store: sold "/.test(confirm) && confirm.includes('" from column " + (p.col + 1)'),
      "…logging the sale with its column");
    r.ok(confirm.includes("campaign.addCoins(p.value)"), "the sale credits the confirmed tier value");
    r.ok(confirm.includes("renderStore()") && confirm.includes('persistCampaign("store")'),
      "…then re-renders + checkpoints the store");
    // R6: destroy-on-sell — the confirm never routes through the
    // return-to-inventory primitives.
    r.ok(!confirm.includes("unplacePillar") && !confirm.includes("unplaceBase"),
      "the confirm never returns a pillar/base to inventory");
    r.ok(confirm.includes("campaign.unequipSamePower()")
      && confirm.includes("campaign.discardSamePowerFromInventory(p.id)"),
      "a sold Same-Power is unequipped AND discarded (buy-replace precedent)");
  }

  // --- R7) Stale-offer hardening in the equipped detail ----------------------
  {
    const eq = fnBody(src, "openEquippedDetail");
    r.ok(eq.includes('el.sdBuy.innerHTML = "Buy"'),
      "openEquippedDetail resets the hidden Buy's label (no stale 'Place sticker · N')");
    r.ok(eq.includes("delete el.sdBuy.dataset.kind"), "…and clears its stale dataset.kind");
    const close = fnBody(src, "closeStoreDetail");
    r.ok(close.includes('el.sdSell.classList.add("hidden")'), "closeStoreDetail re-hides Sell for the next offer");
    r.ok(close.includes("sdEquipped = null"), "…and clears the equipped-target state");
    const open = fnBody(src, "openStoreDetail");
    r.ok(open.includes('el.sdSell.classList.add("hidden")'),
      "openStoreDetail hides Sell in every offer branch (defensive ordering)");
  }

  // --- NON-GOAL guard: the tutorial store gate is retired (Zen-first tour) ---
  {
    r.ok(!html.includes("tut-gate-store"),
      "the guided-store gate CSS is gone — the Zen-first tour never enters the store");
  }

  // --- R4/R6/R8) Behavioral: the confirmed primitive sequence, per kind ------
  // Drive the EXACT sequence confirmStoreSell runs against live registry items
  // of every tier present, asserting the live SELL_VALUE credit, the emptied
  // slot, no inventory return, and the serialize/restore round-trip (R8).
  {
    const { CampaignState, PillarTypes, BaseTypes, SamePowerTypes } = g;
    const oneOfEachTier = (reg) => {
      const seen = {};
      for (const t of reg.all()) if (!seen[t.tier]) seen[t.tier] = t;
      return Object.values(seen);
    };
    // Pillars + bases: place into column 0 via the raw setters, then sell.
    for (const [kind, reg, set, getSlot, remove, inv] of [
      ["pillar", PillarTypes, "setColumnPillar", "columnPillar", "removeColumnPillar", "getPillarInventory"],
      ["base", BaseTypes, "setColumnBase", "columnBase", "removeColumnBase", "getBaseInventory"],
    ]) {
      for (const t of oneOfEachTier(reg)) {
        const camp = CampaignState.create();
        camp.reset();
        r.ok(camp[set](0, t.id), `${kind} ${t.id} (${t.tier}) placed on column 0`);
        const coins0 = camp.getCoins();
        const invBefore = camp[inv]()[t.id] || 0;
        // The confirm's guard + removal in one expression (mirrors the source).
        const ok = camp[getSlot](0) === t.id && camp[remove](0) === t.id;
        r.ok(ok, `…the slot-still-holds-id guard passes and the removal returns the id`);
        camp.addCoins(sellValueOf(t));
        r.eq(camp.getCoins() - coins0, sellValueOf(t),
          `…coins credited by the LIVE ${t.tier} sell value`);
        r.eq(camp[getSlot](0), null, "…the slot is now empty");
        r.eq(camp[inv]()[t.id] || 0, invBefore, "…and it never returned to inventory (destroyed)");
        // A second confirm on the same (now stale) target must no-op: the
        // guard fails, so no removal and no credit.
        r.ok(!(camp[getSlot](0) === t.id), "…a stale re-confirm fails the guard (no double credit)");
        // R8: refresh mid-store — the empty slot + credited coins round-trip.
        const camp2 = CampaignState.create();
        camp2.restore(JSON.parse(JSON.stringify(camp.serialize())));
        r.eq(camp2[getSlot](0), null, "…the empty slot survives serialize/restore");
        r.eq(camp2.getCoins(), camp.getCoins(), "…and so do the credited coins");
      }
    }
    // Same-Power: equip, then the sell-and-destroy pair.
    for (const t of oneOfEachTier(SamePowerTypes)) {
      const camp = CampaignState.create();
      camp.reset();
      r.ok(camp.debugGrantSamePower(t.id) && camp.equipSamePower(t.id),
        `samepower ${t.id} (${t.tier}) equipped`);
      const coins0 = camp.getCoins();
      let ok = false;
      if (camp.getSamePower() === t.id) {
        camp.unequipSamePower();
        ok = camp.discardSamePowerFromInventory(t.id);
      }
      r.ok(ok, "…the guarded unequip + discard sequence succeeds");
      camp.addCoins(sellValueOf(t));
      r.eq(camp.getCoins() - coins0, sellValueOf(t), `…coins credited by the LIVE ${t.tier} sell value`);
      r.eq(camp.getSamePower(), null, "…the Same slot is now empty");
      r.eq(camp.getSamePowerInventory()[t.id] || 0, 0, "…and the power is in NO inventory (destroyed)");
      const camp2 = CampaignState.create();
      camp2.restore(JSON.parse(JSON.stringify(camp.serialize())));
      r.ok(camp2.getSamePower() === null && camp2.getCoins() === camp.getCoins(),
        "…empty Same slot + credited coins survive serialize/restore");
    }
    // R9: buying into the just-emptied slot carries NO replace-sell credit —
    // the buy-replace credit hinges on the occupant read confirmBuyAndPlace
    // performs, which is null after the sale.
    {
      const camp = CampaignState.create();
      camp.reset();
      r.eq(camp.columnPillar(0), null, "an emptied column reads null (no phantom occupant)");
      const buyBody = fnBody(src, "confirmBuyAndPlace");
      r.ok(/if \(oldId\) \{/.test(buyBody), "confirmBuyAndPlace credits a replace-sell ONLY for a real occupant");
    }
  }

  return r.summary();
}
