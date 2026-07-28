// CONFIRMBAR — the two duplicate picker-confirm UIs (#saConfirm sticker-apply,
// #ipConfirm item-place) migrated onto the shared bottom prompt bar
// (showActionBar), completing Convention 3: every confirmation rides the one
// bar. Structural checks only: the markup/refs/listeners for the old confirms
// are gone, both flows arm the bar with the same messages and the same
// confirm targets, the guarded closeModalPrompt can't swallow another flow's
// bar, and the CSS lift puts the bar over the picker modals.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadGame, makeRunner } from "./_harness.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));

function fullHtml() {
  return readFileSync(join(HERE, "..", "index.html"), "utf8");
}
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
  const r = makeRunner("confirmbar.test.mjs");
  const html = fullHtml();
  const src = gameScript(html);
  const g = loadGame();
  r.ok(!!(g.GameEngine && g.CampaignState), "game script evaluates with the confirm-bar migration in place");

  // --- the old duplicate confirms are GONE ----------------------------------
  {
    for (const gone of ["saConfirm", "saConfirmMsg", "saBack", "saApply",
                        "ipConfirm", "ipConfirmMsg", "ipBack", "ipPlace"])
      r.ok(!html.includes(gone), "no trace of the retired confirm UI: " + gone);
    r.ok(!/\.sa-confirm/.test(html), "the .sa-confirm CSS block is gone");
    r.ok(!/\.sa-back|\.sa-apply/.test(html), "the .sa-back/.sa-apply button CSS is gone");
  }

  // --- showActionBar supports trusted code-built markup (opts.html) ----------
  {
    const bar = fnBody(src, "showActionBar");
    r.ok(/else if \(opts\.html\) \{\s*el\.actionPromptText\.innerHTML = text;/.test(bar),
      "opts.html renders code-built markup (bold names / coin icons)");
    r.ok(bar.indexOf("opts.html") > bar.indexOf("opts.help"),
      "…but a help line still takes precedence (escaped desc + markup question)");
    r.ok(/el\.actionPromptText\.textContent = text;/.test(bar),
      "…and the default path stays plain textContent (no injection)");
  }

  // --- closeModalPrompt: the guarded close ------------------------------------
  {
    const close = fnBody(src, "closeModalPrompt");
    r.ok(close.length > 0, "closeModalPrompt exists");
    r.ok(close.includes('document.body.classList.contains("modal-prompt")'),
      "…guarded on body.modal-prompt (same shape as closeRerollConfirm) — never swallows another flow's bar");
    r.ok(close.includes('classList.remove("modal-prompt")') && close.includes("hideActionBar()"),
      "…and drops the lift class + hides the bar when it IS ours");
    r.ok(/body\.modal-prompt \.play-controls \{ z-index: 95; \}/.test(html),
      "the CSS lift puts the bar over the deck-modals (z 80) + card info (z 85)");
    r.ok(fnBody(src, "closeStore").includes("closeModalPrompt();"),
      "closeStore closes any pending picker prompt (no leak across screens)");
    r.ok(fnBody(src, "closeItemPlace").includes("closeModalPrompt();"),
      "closeItemPlace closes its own prompt");
  }

  // --- sticker-apply confirm rides the bar ------------------------------------
  {
    const pick = fnBody(src, "selectApplyCard");
    r.ok(pick.includes('document.body.classList.add("modal-prompt");') && pick.includes("showActionBar(msg,"),
      "selectApplyCard arms the shared bar (lifted) instead of the old in-modal confirm");
    r.ok(pick.includes('onClick: cancelApplyChoice') && pick.includes("onClick: confirmApplySticker"),
      "…Back cancels the choice; the primary button is the unchanged confirmApplySticker");
    r.ok(pick.includes("dismiss: cancelApplyChoice"), "…an outside tap cancels like Back");
    r.ok(pick.includes("html: true"), "…the bold/coin message renders as markup");
    // Same messages as before, per mode.
    r.ok(pick.includes("Permanently REMOVE <b>") && pick.includes("Your deck shrinks by one card."),
      "…remove-mode message preserved");
    r.ok(pick.includes("Replace <b>") && pick.includes("the new card"), "…swap-mode message preserved");
    r.ok(pick.includes("Add <b>") && pick.includes("sa-cost"), "…apply/buy message preserved (cost rides the message)");
    r.ok(pick.includes('applyLabel = buying ? "Buy & Apply" : "Apply";'),
      "…a store buy still names the button Buy & Apply");
    const cancel = fnBody(src, "cancelApplyChoice");
    r.ok(cancel.includes("selectedApplyCardId = null;") && cancel.includes("closeModalPrompt();")
      && cancel.includes("refreshApplySelection();"),
      "cancelApplyChoice clears the selection, closes the bar, refreshes the grid");
  }

  // --- item-place + same-power equip confirms ride the bar --------------------
  {
    const pick = fnBody(src, "selectPlaceColumn");
    r.ok(pick.includes("showActionBar(msg,") && pick.includes('label: "Place"')
      && pick.includes("onClick: confirmItemPlace"),
      "selectPlaceColumn arms the bar: Place → confirmItemPlace (unchanged)");
    r.ok(pick.includes("onClick: cancelPlaceChoice") && pick.includes("dismiss: cancelPlaceChoice"),
      "…Back/outside-tap drops the column choice and keeps picking");
    r.ok(pick.includes("the old one sells for"), "…the replace-sells-old message is preserved");
    const equip = fnBody(src, "openSamePowerEquip");
    r.ok(equip.includes("showActionBar(msg,") && equip.includes('label: "Equip"')
      && equip.includes("onClick: confirmSamePowerEquip"),
      "openSamePowerEquip arms the bar immediately: Equip → confirmSamePowerEquip (unchanged)");
    r.ok(equip.includes("onClick: closeItemPlace") && equip.includes("dismiss: closeItemPlace"),
      "…with no column grid, Back/outside-tap cancels the whole equip (old Back parity)");
    r.ok(fnBody(src, "confirmItemPlace").includes("closeModalPrompt();")
      && fnBody(src, "confirmSamePowerEquip").includes("closeModalPrompt();"),
      "both confirm tails close the bar");
    r.ok(fnBody(src, "cancelPlaceChoice").includes("renderPlaceColumns();"),
      "cancelPlaceChoice re-renders the column grid after deselecting");
  }

  // --- no boot listeners for the deleted buttons ------------------------------
  {
    const ai = fnBody(src, "attachInput");
    r.ok(!/saApply|saBack|ipPlace|ipBack/.test(ai),
      "attachInput wires nothing for the retired confirm buttons (their actions ride the bar)");
  }

  return r.summary();
}
