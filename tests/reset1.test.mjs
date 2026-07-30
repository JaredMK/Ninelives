// RESET1 — total progress wipe (main-menu "Reset progress", v5.25).
// Pins the full-reset contract: every ninelives.* store is cleared (campaign
// save + fossils, Stats, ZenStats, ItemUnlocks known-set, Telem, the deck/zen
// unlock ladders, tutorial + campaign-unlock prefs) EXCEPT the sound pref,
// behind a double showMenuConfirm, ending in a reload. The stats-screen reset
// must keep NOT touching the deck/zen ladders (a stats wipe never re-locks).
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { loadGame, makeRunner } from "./_harness.mjs";

const HTML = join(dirname(fileURLToPath(import.meta.url)), "..", "index.html");

function memStorage() {
  const data = {};
  return {
    getItem: (k) => (k in data ? data[k] : null),
    setItem: (k, v) => { data[k] = String(v); },
    removeItem: (k) => { delete data[k]; },
    _data: data,
  };
}
function bodyOf(src, startMark, endMark) {
  const i = src.indexOf(startMark);
  if (i === -1) return "";
  const j = endMark ? src.indexOf(endMark, i + startMark.length) : src.length;
  return src.slice(i, j === -1 ? src.length : j);
}

export function run() {
  const r = makeRunner("reset1.test.mjs");
  const src = readFileSync(HTML, "utf8");

  // ── Behavioral: the ladder stores really wipe (storage stub) ─────────────
  {
    const storage = memStorage();
    const g = loadGame({ localStorage: storage });

    g.DeckUnlocks.recordWin("pink");
    r.ok(g.DeckUnlocks.wonWith("pink"), "DeckUnlocks records a win");
    g.DeckUnlocks.reset();
    r.ok(!g.DeckUnlocks.wonWith("pink"), "DeckUnlocks.reset() wipes the record");
    r.ok(!("ninelives.deckwins.v1" in storage._data), "…and removes the storage key");

    const zenId = g.DifficultyData.zenIds[0];
    g.ZenUnlocks.recordWin(zenId);
    r.ok(g.ZenUnlocks.beaten(zenId), "ZenUnlocks records a win");
    g.ZenUnlocks.reset();
    r.ok(!g.ZenUnlocks.beaten(zenId), "ZenUnlocks.reset() wipes the record");
    r.ok(!("ninelives.zenunlocks.v1" in storage._data), "…and removes the storage key");

    g.Stats.runPlayed();
    r.ok(g.Stats.get().gamesPlayed > 0, "Stats records a played run");
    g.Stats.reset();
    r.eq(g.Stats.get().gamesPlayed, 0, "Stats.reset() zeroes the tallies");

    g.SaveStore.setPref("sound", "0");
    g.SaveStore.setPref("tutorial2", "1");
    g.SaveStore.clearPref("tutorial2");
    r.eq(g.SaveStore.getPref("tutorial2"), null, "SaveStore.clearPref removes the pref");
    r.eq(g.SaveStore.getPref("sound"), "0", "…a sibling pref is untouched");
  }

  // ── Structural: the orchestrator covers every store, sound survives ──────
  {
    const body = bodyOf(src, "function resetAllProgress()", "/* ---- DECK ROSTER");
    r.ok(body.length > 0, "resetAllProgress() exists");
    for (const call of ["clearSave()", "Stats.reset()", "ZenStats.reset()",
                        "ItemUnlocks.reset()", "Telem.reset()", "DeckUnlocks.reset()",
                        "ZenUnlocks.reset()", 'clearPref("tutorial2")',
                        "clearPref(CAMPAIGN_UNLOCK_PREF)"])
      r.ok(body.includes(call), "…the wipe covers " + call);
    r.ok(!body.includes('clearPref("sound")'), "…the SOUND pref deliberately survives");
  }

  // ── Structural: module resets + the menu entry ───────────────────────────
  {
    const deck = bodyOf(src, "const DeckUnlocks = (() => {", "DeckUnlocks.grantRetroactive(Stats.get())");
    r.ok(/reset\(\) \{[^}]*removeItem\(KEY\)/.test(deck), "DeckUnlocks.reset() removes its KEY");
    const zen = bodyOf(src, "const ZenUnlocks = (() => {", "ZenUnlocks.grantRetroactive()");
    r.ok(/reset\(\) \{[^}]*removeItem\(KEY\)/.test(zen), "ZenUnlocks.reset() removes its KEY");
    r.ok(src.includes("clearPref(key) {"), "SaveStore exposes clearPref");

    const menu = bodyOf(src, "function showMainMenu(canContinue)", "function hideMainMenu()");
    r.ok(menu.includes('label: "Reset progress"'), "the main menu has a Reset progress entry");
    r.ok(menu.indexOf('label: "Sound: "') < menu.indexOf('label: "Reset progress"'),
      "…placed after Sound (last)");
    r.ok(menu.includes("Reset ALL progress?") && menu.includes("Really erase everything?"),
      "…gated by a DOUBLE prompt-bar confirm");
    r.ok(menu.includes("resetAllProgress()") && menu.includes("location.reload()"),
      "…the confirm wipes, then reloads so modules re-read empty storage");

    // The stats-screen reset stays narrow: it must NOT adopt the ladder wipes
    // (a stats wipe never re-locks a difficulty or re-locks a deck).
    const statsReset = bodyOf(src, "el.statsReset.addEventListener", "el.manualClose");
    r.ok(statsReset.includes("Stats.reset()") && statsReset.includes("ZenStats.reset()"),
      "the stats-screen reset still zeroes both stat stores");
    r.ok(!statsReset.includes("DeckUnlocks.reset()") && !statsReset.includes("ZenUnlocks.reset()")
      && !statsReset.includes("resetAllProgress()"),
      "…but never touches the unlock ladders (stats wipe ≠ progress wipe)");
  }

  return r.summary();
}
