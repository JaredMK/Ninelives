# AGENTS.md — Ninelives

Mobile-first, single-file web card game. No frameworks, no build step, no
dependencies — open `index.html` in a browser. iOS wrapper lives in `app/`
(Capacitor).

## Layout

- `index.html` — the entire game: all logic in one inline `<script>`, all
  styles in one `<style>`. ~27k lines; navigate it via the module map in
  `README.md` and grep, never by scrolling.
- `items.js` — `NINELIVES_ITEMS`: every shop item (stickers, pillars, bases,
  same-powers, packs) + store config.
- `difficulty.js` — `NINELIVES_DIFFICULTY`: tier bands, joker caps, zen config.
- `tutorial.js` — `NINELIVES_TUTORIAL`: all first-run tutorial copy.
- `tests/` — Node test suite, no browser needed (see Testing).

## Convention 1: data files are the source of truth

`items.js`, `difficulty.js` (and `tutorial.js` for copy) are the ONLY
hand-editable homes for item and difficulty data. Game logic reads from them
and NEVER hardcodes a value that lives there:

- Effect knobs (coin values, bury counts, thresholds, chances, prices,
  descriptions) are read via `ItemData` / `itemNum(def, key, fallback)` or the
  item def fields. Tuning a number means editing `items.js`, never logic.
- Difficulty bands, joker caps, endless step, zen suit/pile counts are read
  live from `DifficultyData`. Tuning difficulty means editing `difficulty.js`.
- UI text for items comes from the registry `description` — never re-type
  effect text into UI code. Live counters/badges must derive their numbers
  from the item def too (a counter that hardcodes a number desyncs the moment
  someone retunes the item).
- Item `id`s are stable keys: saves, offers and tests bind to them. Never
  rename an `id`; rename the player-facing `label` instead.
- Malformed data must fail loudly at load (the validators do this) — never
  swallow a bad entry silently.
- If a genuinely NEW tunable appears, put it in the data file with a comment
  naming what it does; do not bury it in `index.html`.

## Convention 2: performance invariants

The game targets phones. Four invariants, all currently enforced — keep them:

1. **No per-frame layout reads.** rAF callbacks do pure math and write
   `transform` only. `getBoundingClientRect`/`offset*`/`getComputedStyle` are
   read once and cached (`pileGeomCache`, `fitEnvCache`), invalidated on real
   layout changes (build/resize), never per frame.
2. **One animation clock.** A single drift rAF drives board motion; tweens are
   short-lived self-terminating rAFs. No `setInterval` anywhere; no
   re-arming `setTimeout` chains except the guarded blink/autopilot timers.
   Don't add a second ticker — hook into the existing one.
3. **No accumulating listeners/DOM across screens.** Input is attached ONCE at
   boot (`attachInput`) to persistent containers via event delegation. Screen
   re-renders rebuild into those containers (`innerHTML = ""` then fill);
   per-element listeners are attached at creation and die with the element.
   Never `addEventListener` inside a render/show function that runs per visit.
4. **Board pauses behind overlays.** `boardVisible()` gates the drift loop and
   motion classes; every screen show/hide path calls `updateBoardMotion()`.
   Any new overlay must hook into this — no animation or input may run under
   an open overlay.

## Convention 3: UX

- **Hold-for-help everywhere.** Every meaningful interactive element (store
  tiles, pillars, bases, stickers, HUD chips, map nodes, cards) shows its help
  on press-and-hold. New UI elements need a hold-help path; copy comes from
  the registry description, never hand-written duplicates.
- **Bottom prompt bar for all confirmations.** Confirmations (buy, sell,
  remove, destructive choices) go through the shared bottom prompt bar
  (`showActionBar` on `#actionPrompt`) — never browser `confirm()`/`alert()`,
  never a new one-off dialog idiom.
- **One-screen store.** The store is a single fixed screen with one unified
  shelf; no tabs, no paging. Sub-flows open as overlays above it and return
  to the same screen.
- **Phone-first.** Touch/pointer input first (swipe to guess, hold to peek,
  no hover-dependent UI), safe-area insets on every fixed element, layouts
  must fit ~390px-wide phones (fluid `clamp()`/vw/svh + `fitBoard`, not media
  queries). Desktop affordances (`title=`, keyboard) are optional extras,
  never the only path.

## Convention 4: tests gate every commit

```sh
node tests/all.mjs   # must be 100% green before ANY commit
```

- `_harness.mjs` extracts the game `<script>` from `index.html` and evaluates
  it with a stubbed DOM — engine modules are testable in Node BECAUSE they
  never touch the DOM. Keep engine modules (`DeckManager`, `BoardState`,
  `GameEngine`, `CampaignState`, `RunMap`, `Economy`, registries) DOM-free.
- Each `*.test.mjs` exports `run() -> { pass, fail, fails }`; register new
  suites in `tests/all.mjs`.
- Tests pin RULES and behavior, never tunable numbers — read expected values
  from `ItemData`/`DifficultyData` so a data retune doesn't break the suite.

## Workflow

The multi-agent pipeline (spec/meta/reviewer/security/UX subagents) is
RETIRED. Kimi's own reasoning, Plan mode, the conventions checklist, and the
test gate provide the safety instead.

### 1. Prompt refinement — ALWAYS, for every user request

Before doing anything, restate the request as a refined spec: what you
understand the user wants, the concrete changes you'll make, ambiguities
resolved (state your assumption) or asked (only if genuinely blocking), and
anything the request touches that the user may not have considered (affected
systems, conventions, edge cases). Keep it brief — a tight spec, not an
essay; one or two lines for trivial changes. Then PROCEED — don't wait for
approval unless you asked a blocking question.

### 2. Execution by size

- **Trivial** (copy, data values, one-liners): refine → do it directly →
  test → ship.
- **Features / reworks / multi-file changes**: refine → enter Plan mode →
  present the plan for the user's approval → implement only after approval →
  test → ship.

No separate reviewer/meta/security/UX agents. Before shipping, self-review
the diff against every convention in this file: data files as source of
truth, the four perf invariants, the UX conventions, engine DOM-freedom.
That checklist replaces the retired reviewer agents.

### 3. Ship ritual (unchanged)

`node tests/all.mjs` 100% green → bump `APP_VERSION` on behavior changes →
commit → push → the Pages workflow deploys → report what changed, closing
with the line `Latest: vX.YZ`.

## Also

- Storage keys use the `ninelives.*` prefix only (the native bridge mirrors
  just that prefix to Capacitor Preferences).
- All user-facing strings rendered into HTML go through `escHtml`.
- Debug: `?debug` URL param (or triple-tap the title) opens the debug panel.
- Deploy: `.github/workflows/pages.yml` publishes to GitHub Pages on push to
  the live branch — the root site always rebuilds from the live branch.
