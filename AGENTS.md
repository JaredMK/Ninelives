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
  never a new one-off dialog idiom. Picker/detail modals' *confirm step*
  rides the bar too (`body.modal-prompt` lifts it over the deck-modals);
  `#storeDetail`/`#packReveal` are detail/picker views (the store idiom),
  not one-off confirms.
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

### 3. Version + push protocol

- **One version source.** The build version lives ONLY in `APP_VERSION`
  (index.html, `"vX.YZ · one-line footer note"`). The footer (`build vX.YZ`)
  and the console log read it there — never hardcode the version anywhere
  else.
- **Bump on behavior.** Every commit that changes game behavior or UI bumps
  the version by 0.01 and rewrites the footer note to describe the change.
  Docs/test-only/no-behavior refactors don't need a bump.
- **Sync first.** If the working tree holds someone else's uncommitted or
  unpushed work, or the remote has commits you lack: `git pull --rebase`
  (`--autostash` for foreign WIP — never commit what isn't yours) BEFORE
  committing. Never force-push. Take the next version number AFTER syncing —
  two agents must never claim the same version.
- **Ship.** After any completed task: commit → push to `neural-redesign` →
  confirm the Pages deploy triggers (`gh run list`) → report: the new
  version, the commit hash, and "live once deploy is green — verify the
  footer shows vX.YZ".
- **iOS.** The Capacitor app in dev mode (`server.url` in
  `app/capacitor.config.json`) loads the deployed `/neural/` URL — web
  deploys reach it on kill + reopen, no rebuild. Native-shell changes
  (plugins, capacitor config, icons, the Xcode project) require an Xcode
  rebuild — flag that loudly in the report whenever a change needs it.
- **Always-report rule.** End every task report with the version line:
  `Latest: vX.YZ (commit abc1234) — deployed to GitHub Pages` (or
  `requires Xcode rebuild`).

## Handoff notes — structural changes the other agent should know

*(Newest first. Add an entry here when a change alters shared structure —
generator, save format, caches — so the next session starts from reality.)*

- **v5.06 (Kimi, MYST2)** — mystery-node refinement + Pinky Regular joker
  economy; READ THIS BEFORE TOUCHING MYSTERY OUTCOMES, JOKER ECONOMY, OR RUN
  START:
  - items.js `mystery.weights` final table (boons 62 / banes 34): coinBonus
    15 · cards 12 · stickerPack 10 · freeRemoval 8 · stickerStrip 7 · joker 5
    · store 5 ‖ cursedSticker 14 · coinLoss 12 · ambush 8. `cardPack` and
    `cursedCard` are GONE (knobs `cursedCardTribute`/`cursedCardRankRange`
    deleted); `cardGrantRange: [1,3]` added. New outcome cases live in
    `CampaignState.applyMysteryEvent`.
  - **Cursed cards are retired.** `mintCursedCard`, the engine innate-curse
    toll in `maybeStickerTribute` (the `tributeCoin` sticker branch STAYS —
    leech/leech2 untouched), and all cursed-card UI are removed. `restore()`
    strips `cursed: true` cards from baseDeck + ownedIds on load (no refund).
    A stray `cursed` flag in a mid-deal checkpoint is inert.
  - **Joker outcome gate is HELD-vs-CAP** (`jokersHeld() < jokerCapFor()`),
    NOT `jokersAllowed()` — the fixed-scheme blanket-false would bar Pinky
    Regular, an authorized source. At cap the roll deterministically folds to
    coinBonus; Legendary (cap 0) can never roll it.
  - **Store outcome** rides a one-shot `mysteryStoreContinue` hook: armed in
    `continueMysteryEvent`, invoked from the store Done handler after
    `persistCampaign("map")`, cleared on use and at the top of
    `showProgressionMap`. Refresh during the detour = store skipped, node
    dispatches on return.
  - **difficulty.js gained `startJokers: { pink: 1 }`** on Regular (cap now
    4). `DifficultyData.startJokers(deckId, tierId)` accessor; `startNewRun`
    mints them BEFORE `genRunMap()`. **Pregen threading:** `runStartSize(dId,
    tId)` (next to `runGenKey`) = GEN_CONFIG.startDeckSize + startJokers —
    `pregenerateRun`'s entry ladder AND startNewRun both derive from it;
    change one side without the other and every Start press cache-misses into
    a multi-second synchronous build.
  - Debug peek: hidden "?" nodes render `<span class="pm-myst-out">` from the
    pure `rollMysteryEvent(n.id)`, hidden by CSS unless `body.debug-access`.
  - Cursed stickers (leech/leech2) render with `dcs-cursed` + the violet
    `#7a4fd0` face in `stickerChip` AND the board badge path (`faceOf`/
    `clsOf`/`edgeOf`) — any new chip-rendering path must route cursed types
    the same way.
  - Outcome animations are pure CSS keyframes on `.me-art mea-<key>` +
    `MYSTERY_SOUND` map at modal open; `prefers-reduced-motion` kills them.

- **v5.05 (Kimi, MYST1)** — mystery "?" nodes are now real event gambles;
  READ THIS BEFORE TOUCHING THE MAP ARRIVAL FLOW OR STICKER POOLS:
  - The "?" mask is UNCHANGED (cosmetic `n.mystery` roll; no generator/genV
    change). Arrival at a hidden node now runs `runMysteryEvent` (after
    `playMysteryReveal`, before `finishResolveNode`'s type dispatch): a
    seeded roll (`campaign.rollMysteryEvent(nodeId)` — deterministic per
    (runSeed, nodeId), weights in `items.js` `mystery`) whose outcome
    resolves ON TOP of the underlying node, which then still dispatches
    normally. Exactly-once rides on the persisted `revealedNodes`; the
    event flushes a "map" save before any picker/deal.
  - `items.js` gained a `mystery` section (weights, coinRangeByStage,
    ambush {cards,piles,bounty}, cursedCardTribute, cursedCardRankRange)
    and CURSED stickers (`cursed: true`, e.g. leech/leech2, behavior
    `tributeCoin`). Cursed entries are excluded from every grant pool via
    `StickerTypes.grantable()` — any NEW random-sticker path must use it
    (or filter `cursed`) or curses leak into stores/packs.
  - Cards can now carry `cursed: true` (minted by `mintCursedCard`,
    nextCardId++ like mintJokerId). Restore's spread-copy carries the flag
    for free; the engine levies the innate toll in `maybeStickerTribute`
    (the Bury 2 shape: negative addBonus + sticker-coins emit + Telem).
    `duplicateCard` intentionally does NOT propagate `cursed` to copies.
  - Save format: `dealSubset` gained optional `forced`/`cards`/`ambush`
    fields (additive — old saves lack them, old readers ignore them).
    Ambush deals ride the standard "run" checkpoint; post-ambush-win
    deliberately skips the "map" checkpoint so a refresh replays the
    ambush instead of stranding the un-dispatched node. Module vars:
    `ambushDeal`, `pendingAmbushNodeId`, `placementSavePhase` (typeof-
    guarded write-time phase override in campaignSaveBlob — STKLAG2's
    function-extraction harness depends on the guard).

- **v5.03 (Kimi, STKLAG3/4)** — sticker-apply perf + save-write timing:
  - The coalesced campaign save is now TWO-STAGE: `persistCampaign` arms
    `armSaveWrite()` — a 300ms trailing setTimeout that hands the actual
    serialize+write to `requestIdleCallback` (bounded 1500ms, setTimeout
    fallback) so it never lands inside a tap animation. `flushCampaignSave()`
    is still the synchronous durability write at transitions/pagehide.
    `tests/stklag2.test.mjs` pins the mechanism (fake timers + fake rIC).
  - New read-only CampaignState accessors: `getCardById(id)` (one live card,
    replaces `getCards().find(...)`) and `getRunDeckLive()` (live owned-card
    refs, replaces `getRunDeck()` in render-only paths). Both return LIVE
    objects — never mutate them; mutations go through the mutator methods.
  - `Telem.scheduleFlush()` debounces purchase-path telemetry writes;
    `Telem.flush()` stays synchronous at transitions/pagehide.

- **v5.02 (Claude, MAPGEN1)** — map generation reworked for speed; READ THIS
  BEFORE TOUCHING RunMap OR THE PREGEN PATH:
  - `RunMap.makeRunStepper(seed, entries, opts)` builds one stage per
    `step()`; sync `generateRun` now just drains it (bit-identical output).
    Deck-select pregen builds one stage per idle slice and caches per
    `runGenKey` in a multi-slot Map (`pregenCache`) — consumption DELETES the
    entry because run maps are mutated in play (never reuse a consumed map).
  - The SAVE FORMAT gained `genV` (generator version). New runs stamp 2;
    restores default absent→1 and regenerate through the EXACT legacy path —
    this is the save-compat gate. Never remove it, and thread the RUN's own
    `runGenVersion` (not the global default) into any new `generateRun` call
    site (extendEndless/maybeExtendMap already do).
  - genV≥2 only: a deterministic derived-seed ladder retries a stage that
    exhausts all attempts (fixes rare broken Legendary maps).
  - `tryBuildStage` repair loops now maintain incremental per-route sums via
    `noteChange` — ANY new mutation of a node's `type`/`add`/`packCount`
    between index arming and the final validation read MUST go through
    `noteChange` or the sums desync (reviewed exhaustively at ship time;
    keep it that way). Master/Legendary generation is ~10× faster; do not
    reintroduce full route re-walks in repairs.
  - Bit-compat vs v5.01 was verified on 678 seed×tier×entry tuples (zero
    diffs, genV1 and genV2). If you change generator OUTPUT intentionally,
    bump the genV scheme and gate it the same way.
  - Debug entry (context for the debug panel): the 🐞 toggle is hidden
    unless `body.debug-access` — enabled by `?debug` or 7 quick taps on the
    build footer (the title triple-tap needs an element not on the play
    screen). The debug event log is a capped ring buffer (`pushLog`,
    `LOG_CAP`) rendering only the newest 50 — unbounded log rendering was a
    measured store-lag cause (v4.94); don't regress it.

## Also

- Storage keys use the `ninelives.*` prefix only (the native bridge mirrors
  just that prefix to Capacitor Preferences).
- All user-facing strings rendered into HTML go through `escHtml`.
- Debug: `?debug` URL param (or triple-tap the title) opens the debug panel.
- Deploy: `.github/workflows/pages.yml` publishes to GitHub Pages on push to
  the live branch — the root site always rebuilds from the live branch.
