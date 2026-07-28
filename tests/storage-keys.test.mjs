// Storage-key migration: Stats and Telem predated the ninelives.* prefix
// ("mnesis.stats.v1" / "mnesis.telem.v1") — the prefix the native bridge
// exclusively mirrors to Capacitor Preferences, so under the old keys those
// stores never left webview storage on iOS. On load, each store moves the old
// blob onto its ninelives.* key exactly once, then drops the old key.
import { loadGame, makeRunner } from "./_harness.mjs";

/** Minimal in-memory localStorage (same shape as the harness stub). */
function memStorage(init = {}) {
  const data = { ...init };
  return {
    getItem: (k) => (k in data ? data[k] : null),
    setItem: (k, v) => { data[k] = String(v); },
    removeItem: (k) => { delete data[k]; },
    key: (i) => Object.keys(data)[i] ?? null,
    get length() { return Object.keys(data).length; },
  };
}

export function run() {
  const r = makeRunner("storage-keys.test.mjs");

  // ---- old-only blobs migrate onto the ninelives.* keys, old keys dropped --
  {
    const statsBlob = JSON.stringify({ gamesPlayed: 7, campaignsWon: 2, deckTierWins: { "pink.regular": true } });
    const telemBlob = JSON.stringify({ v: 1, since: 123, art: { heavy: { klass: "sticker", triggers: 4 } } });
    const storage = memStorage({ "mnesis.stats.v1": statsBlob, "mnesis.telem.v1": telemBlob });
    const g = loadGame({ localStorage: storage });
    r.eq(storage.getItem("ninelives.stats.v1"), statsBlob, "Stats blob moved onto ninelives.stats.v1");
    r.eq(storage.getItem("ninelives.telem.v1"), telemBlob, "Telem blob moved onto ninelives.telem.v1");
    r.eq(storage.getItem("mnesis.stats.v1"), null, "old Stats key removed after migration");
    r.eq(storage.getItem("mnesis.telem.v1"), null, "old Telem key removed after migration");
    r.eq(g.Stats.get().gamesPlayed, 7, "migrated Stats values are readable");
    r.ok(g.Stats.get().deckTierWins["pink.regular"], "migrated deckTierWins survive (deck unlocks rebuild from them)");
  }

  // ---- a NEWER ninelives.* blob is never clobbered by a stale old key ------
  {
    const storage = memStorage({
      "mnesis.stats.v1": JSON.stringify({ gamesPlayed: 99 }),
      "ninelives.stats.v1": JSON.stringify({ gamesPlayed: 3 }),
    });
    const g = loadGame({ localStorage: storage });
    r.eq(g.Stats.get().gamesPlayed, 3, "existing ninelives.* blob wins over the stale old key");
    r.eq(storage.getItem("mnesis.stats.v1"), null, "stale old key still removed");
  }

  // ---- no old keys → migration fabricates nothing --------------------------
  {
    const storage = memStorage();
    loadGame({ localStorage: storage });
    r.eq(storage.getItem("ninelives.stats.v1"), null, "no old Stats key → no blob written at load");
    r.eq(storage.getItem("ninelives.telem.v1"), null, "no old Telem key → no blob written at load");
  }

  return r.summary();
}
