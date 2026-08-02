# Web reference captures — Ninelives / Shoulda Said Same

Reference screenshots of the web build for the native-iOS parity audit.
Captured from `http://localhost:8931/index.html` (static server at repo root),
build **v5.74** (footer). 40 PNGs, all 1206×2622 px (402×874 pt @3x, iPhone-class
viewport, mobile + touch emulation).

Driver scripts (re-runnable): `/tmp/sss-refcap/` — `lib.mjs` (shared helpers),
`batchA.mjs`, `batchB2.mjs`, `batchC.mjs`, `patch-boss.mjs`, `batchD2.mjs`,
`batchE.mjs`, `batchE1.mjs`, `batchE2.mjs`, `batchE3.mjs`.
Run with `node <script>.mjs` from `/tmp/sss-refcap` (Playwright; launches the
cached "Google Chrome for Testing" binary — see `EXE` in `lib.mjs`).

## Method notes

- **Fresh-player shots** use a clean browser context (no localStorage).
- **Veteran shots** seed localStorage before load (`newPage({seed})` in lib.mjs):
  `ninelives.pref.campaignUnlocked=1`, `ninelives.pref.tutorial2=1`,
  `ninelives.pref.firstClimbDone=1` (the first-climb gate blocks all item
  unlocks until set), and a partial `ninelives.stats.v1` JSON (defensive merge)
  with veteran numbers (gamesPlayed, campaignsWon, pilesLost, …).
- **Campaign/board shots** boot with `?debug`. The debug PANEL is never visible
  in any capture (all panel interactions go through JS clicks, panel closed
  before each shot). Tiny QA affordances (🐞 / ▶ buttons at the bottom-left
  edge) are visible in some deal/map shots — they only exist in `?debug` mode
  and are not part of the player UI.
- Deterministic pile kills (deal-mid/late, death): debug "force next rank" to a
  rank ≠ pile top, select pile, guess Same → pile dies. Verified via dead-pile
  count in the DOM before each screenshot.

## Files

### Menu / meta
- `menu-fresh.png` — first-launch menu, fresh gate: Zen primary, no Climb entry (no prefs).
- `menu-continue.png` — veteran menu with an in-progress climb: CONTINUE primary + NEW CLIMB (reloaded after the deal checkpoint wrote `ninelives.save.v1`).
- `settings.png` — settings sheet, opened from the fresh menu.
- `stats.png` — Stats screen with the seeded veteran numbers above.
- `howto-1.png`, `howto-2.png` — How to Play slides 1–2 (8 slides exist; 1–2 captured per contract).
- `collection.png` — Collection grid, fresh player: locked silhouettes.
- `collection-detail.png` — Collection item detail (tap a `.col-tile`), pager 1/33.
- `zen-select.png` — Zen mode difficulty select.

### Tutorial
- `tutorial-01.png` … `tutorial-06.png` — the 6 deal-tutorial bubbles, in order
  (fresh → Zen → first `.zs-entry` → `#zsStart`, then shot + tap `.tut-next`).
  Quirk noted: since v5.60 the flow has one step fewer than the flag logic
  expects, so the `tutorial2` pref stays unstamped after the final "Go" — the
  tutorial re-offers on next Zen start. Possible game bug, captured as-is.

### Campaign map
- `deckselect.png` — deck/tier select: Pinky, Regular, START CLIMB.
- `map-top.png` / `map-mid.png` / `map-bottom.png` — progression map scrolled
  (`#mapScroll.scrollTop`, clamped to reached stages).
- `map-boss.png` — map centered on the final (♠) boss node (debug jump).
- `map-mystery.png` — revealed "?" mystery node with label + marker.
- `mystery-modal.png` — mystery event modal ("Cache +7 coins").

### Store
- `store-shelf.png` — one-screen store shelf (first-visit legend auto-opens;
  closed via `#storeHelpBtn` before the shot).
- `store-detail.png` — item detail view (pillar/base).
- `store-column-chooser.png` — column chooser inside the detail (`.sd-col` tap
  required before BUY enables).
- `store-pack-reveal.png` — pack reveal overlay.
- `picker-sticker.png` — sticker-apply picker (post-buy).
- `picker-swap.png` — pack swap walk ("Swap in X").
- `picker-removal.png` — removal picker.
- `prompt-bar.png` — bottom confirm bar: "Add Change to ♦ to 2♥? [BACK][BUY & APPLY]".

### Deal board
- `deal-early.png` — fresh 5-pile deal (REWARD +3 · SCORE 5X1).
- `deal-mid.png` — 3 piles killed, 2 alive (SCORE 2X1; dead piles dissolved).
- `deal-late.png` — 4 piles killed, 1 alive (SCORE 1X1).
- `pause.png` — in-deal menu sheet, incl. the SEED share line.
- `deal-fan.png` — rail fan toggle on.
- `deal-help.png` — hold-for-help on a pile (peek bar: "Card 10♥ / No stickers").
- `deal-summary.png` — DEAL CLEARED summary (SCORE +4, CONTINUE) via debug win.

### Run endings
- `death.png` — GAME OVER screen ("Shoulda said lower", REACHED ♦ PHASE 1/3,
  SEED line, stat tiles, MAIN MENU) via debug lose.
- `victory.png` — "Pinky is home" campaign victory screen (stat tiles, SEED
  share line, CONTINUE — ENDLESS MODE / GO TO MAIN MENU). Reached by debug-jump
  to the final boss → debug win → CONTINUE → stepping onto the home node.
- `unlock-toast.png` — item-unlock pop at climb termination: "NEW STICKER
  UNLOCKED — Random Rank — EARNED: PLAY 4 CLIMBS". Seeded `gamesPlayed: 3` +
  one counted climb crosses the gate (4); pops fire only at run end (v5.47
  removed the per-deal checkpoint), so it rides the death flow.

## Not captured

Nothing outstanding — every contract filename is present. Known caveats only:

- The 🐞/▶ debug affordances noted above appear in `?debug` captures.
- `unlock-toast.png` shows the pop over the dimmed death overlay (pops chain
  ahead of end screens by design).
