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

- **v5.18 (Kimi, THERMAL4)** — the COMPOSITOR is convicted end-to-end; READ
  THIS BEFORE ADDING SHADOWS/FILTERS OR TRUSTING A CLEAN JS PROFILE:
  - Evidence: a Web Inspector timeline recorded from the Xcode app (debug
    builds are inspectable via Safari → Develop → iPhone — the ONLY way to
    see this; in-game capture can't). 104s session: 21.6s inside `composite`
    records vs <4s combined for style+layout+paint; long frames were either
    1-2.4s composite spikes or 550-800ms frames with ~zero recorded work
    (main thread idle-waiting on the compositor); CPU never exceeded 80%;
    memory flat ~85-89MB (no leak). Per-frame composite mean hit 50ms in the
    worst 10s bucket = texture eviction/re-upload THRASH at the
    backing-store cliff. Mobile Safari was clean in the same game state —
    iOS gives third-party app webviews lower memory priority, so the shell
    purges/re-rasters where Safari doesn't. All previous in-game dumps (UA
    without the Safari token) were from the in-app webview.
  - Fix: **background flattens under any open deck-modal** —
    `body:has(.deck-modal:not(.hidden)) body > :not(.deck-modal)` (+ ` *`)
    kills `box-shadow`/`filter` (!important) outside the modal subtree. The
    0.7 scrim hides the flat look; freed raster = less eviction pressure,
    and any forced re-raster is cheap. Same self-syncing :has() gate as the
    pause contract; the action bar's chrome flattening over a modal is an
    accepted cosmetic trade.
  - `#tissue .blob` (blur(46px) + infinite hazeDrift) joined the modal-open
    pause list. NOTE: `#tissue` blobs and `.map-bg` hold large always-on
    layers (will-change: transform) — if thrash persists on-device, they
    are the next raster-footprint candidates.
  - Diagnostic playbook for the next episode: Xcode-run the app, Safari →
    Develop → iPhone → the app webview → Timelines (CPU + Rendering Frames
    + Memory) → record around the lag. Composite-dominated long frames =
    layer pressure; empty long frames = compositor wait; JS records =
    actual code (never the case so far).

- **v5.17 (Kimi, THERMAL3)** — the huge-deck picker failure is LAYER-MEMORY
  exhaustion, not speed; READ THIS BEFORE TOUCHING PICKER TILE STYLING:
  - User-observed mechanism (matches every dump): taps "land" seconds late
    while scrolling stays alive, sounds fire but the UI doesn't repaint, and
    afterwards icons/deck art turn TRANSPARENT = iOS discarding layer
    contents under backing-store memory pressure. Ambient capture the same
    session: 7841 frames, mean 16.7ms, janky 0 — throughput was never the
    issue; the per-tile RASTER at 82-87-card pickers is.
  - Fix: **XL-lite mode** — `SA_XLITE_DECK` (40, const by APPLY_FIRST_BATCH)
    gates `sa-xlite` on `#saCards` (toggled in renderStickerApplyCards):
    `.mini-card` loses the 18px-blur box-shadow + border, `.sa-disabled`
    loses its per-card grayscale FILTER (opacity alone). Same layout, same
    info, same gameplay — flat paint. Keep new picker tile styling flat at
    any size; if you add a per-tile effect, it must be opacity/transform.
  - journeyCtx/dump now carry `dom <N>` (document node count) so future
    dumps can confirm the pressure correlation.
  - NOTE: a full picker/gameplay rewrite was considered and rejected — the
    dumps prove logic is fast (<50ms) and ambient is clean; the failure is
    resource footprint, which rewrites don't address.

- **v5.16 (Kimi, THERMAL2)** — last always-on filter loop killed + stall
  attribution; READ THIS BEFORE TRUSTING A "CLEAN" DESKTOP PROFILE:
  - The v5.15 on-device dump proved the game runs clean everywhere EXCEPT
    picker sessions (ambient: 2946 frames, mean 16.9ms) — yet picker sessions
    still hit 2.5-3.4s single-frame stalls and one 20s ~6fps session, with
    ALL wrapped JS <50ms. Attribution is now baked into the capture:
    journeyCtx stamps `kind` (sticker/removal/remove/swap/strip) + `under`
    (map/store/board via body.on-map / storeOverlay.hidden), the dump prints
    them per mark, and the ambient worst-5 entries carry `[screen]`.
    `showActionBar` + `renderDeckStrip` (the two heavy unwrapped paths around
    select/close) are now wrapped as `ui:actionBar` / `deck:renderStrip`.
  - `deckPeekGlow` (an infinite drop-shadow FILTER animation on the HUD deck
    chip, visible above bottom-sheet modals) is converted to the
    opacity-crossfade pattern (`deckPeekFade` on `::after`, static base
    glow). Filter OR box-shadow animation for always-on FX is banned
    game-wide — no exceptions remain in the stylesheet.
  - The `:has(.deck-modal:not(.hidden))` pause list gained
    `.deck-stack.revealed`, `.map-avatar .av-body/.av-face`,
    `.ds-deckchar .dc-face`.

- **v5.15 (Kimi, THERMAL1)** — box-shadow animation is BANNED game-wide for
  always-on FX; READ THIS BEFORE ADDING ANY ANIMATION:
  - Animating `box-shadow` repaints the element EVERY FRAME (paint-level
    power draw = device heat = the iOS throttling behind the on-device
    multi-second stalls). The last two offenders are converted:
    `sameChargePulse` → `sameChargeFade` (`.hud .hud-same.charged::after`
    glow layer), `pillarActivatable` → `pillarActiveFade`
    (`.cph-banner.activatable::before` ring) — both opacity crossfades, same
    look/rhythm, compositor-only, following the map-pulse precedent (~5531).
    New always-on animations must animate transform/opacity ONLY (one-shot
    entrance tweens may still ease whatever they need).
  - Blanket `will-change: opacity` removed from the pm-node pulse pseudos —
    pre-promotion holds GPU memory; opacity animations composite on demand.
  - The Perf module gained an AMBIENT gap sampler (`ambientGap`, beside
    `frameGap`): armed by `setOn(true)`, paused by `pickerOpened`, resumed by
    `pickerClosed`, stopped by `setOn(false)`; measures every screen into a
    600-frame window + a worst-5 list; `dump()` prints an
    `-- ambient (all screens) --` section. Same debug-only measurement
    contract (no DOM, no storage, zero cost when off). `Perf.ambient` /
    `Perf.ambientStats()` exposed for tests.

- **v5.14 (Kimi, PERFFIX2)** — full-viewport backdrop blur BANNED; READ THIS
  BEFORE ADDING ANY backdrop-filter:
  - The flat-A/B on-device capture convicted `.deck-modal`'s
    `backdrop-filter: blur(4px)`: blur-ON produced 2.9s and 15s main-thread
    freezes at a 72-card picker (taps queued and all fired at unfreeze — the
    user's "clicked through all the buttons at once" symptom); blur-OFF was
    clean at the same deck sizes. The blur is removed permanently; the scrim
    (`rgba(48,36,32,0.7)`) stays. **Never put backdrop-filter on a
    full-viewport element** — small-area blurs (chips, bars) elsewhere in the
    stylesheet are fine and stay.
  - The `perf-flat` debug toggle is RETIRED (markup, el ref, wiring, CSS, the
    `flat` journeyCtx stamp — all gone). Its A/B did its job.
  - The v5.13 `:has()` pause contract STAYS (background animators pause under
    any open deck-modal) — still saves GPU/battery under modals and reduces
    session heat; the saFlash/saRemove filter-free keyframes and
    `.sa-lite .dcs-ic` flattening stay too.
  - One unexplained outlier remains from the flat-ON capture: a single 8.2s
    stall right after a pack reveal (`#packReveal` kept its blur even in flat
    mode — same class of bug, now covered by the global removal). If a freeze
    ever recurs on-device, look at the pack-reveal → picker handoff first.

- **v5.13 (Kimi, PERFFIX)** — on-device-indicted render-cost fixes; READ THIS
  BEFORE ADDING ALWAYS-ON ANIMATIONS OR PICKER FX:
  - **The `body:has(.deck-modal:not(.hidden))` pause contract** (CSS block by
    the picker styles): while ANY deck-modal is open, the background animators
    (`.pm-node.s-legal/.s-here::after`, `.map-avatar`, `.hud .hud-same.charged`,
    `.cph-banner.activatable`, `.ds-deckchar .dc-pupil`) get
    `animation-play-state: paused`. Reason: the deck-modal's full-viewport
    `backdrop-filter: blur` re-blurs whatever changes behind it — on-device
    (iPhone 18.7, deck 32-46): 17-34ms mean frame gap + 300-600ms tap frames
    while all picker JS was <50ms. ANY NEW always-on animation that can sit
    behind a deck-modal MUST be added to this list. `:has()` keeps it
    self-syncing across every open/close path — do not replace it with a JS
    hook (stranded-state risk).
  - **Filter keyframes are banned in picker FX**: `saFlash`/`saRemove` are
    transform/opacity only (animating `filter` forced per-frame software
    repaints of a blurred region — the 200-390ms apply frames). New card FX
    must animate transform/opacity only.
  - `.sa-lite .dcs-ic { filter: none }` — the picker grid is vinyl-flat; the
    board keeps its shadows.
  - `body.perf-flat` (debug A/B) now ONLY kills the deck-modal backdrop blur —
    its icon-shadow/animation/map-pulse rules were deleted when they became
    permanent. If an on-device re-capture (flat off) shows a clean baseline,
    the blur is exonerated; if not, the blur goes next.
  - `journeyCtx()` stamps `flat` into every picker mark; the dump header
    hides ring slack (`Math.min(entries.length, PERF_CAP)`).

- **v5.12 (Kimi, PERFCAP)** — on-device perf capture + flat-picker A/B; READ
  THIS BEFORE TOUCHING THE Perf MODULE OR PICKER CSS:
  - The `Perf` IIFE (end of the game script) is now ring-CAPPED
    (`PERF_CAP 400` + `PERF_SLACK 64` batch splice, the `pushLog` pattern) —
    never push to `entries` directly, go through `pushEntry`.
  - Journey capture: `Perf.mark(stage, ctx)` / `markAfterPaint` (single
    boolean check when off; `picker:*` stages auto-attach deck size, sticker
    count, frame-gap stats). `Perf.dump()` builds the paste-friendly report;
    the debug "📋 copy perf report" button dumps via `copySeed` (memory-only
    — NEVER route capture through localStorage; the Capacitor shim posts a
    native message per `ninelives.*` setItem).
  - Frame-gap sampler (`frameGap` IIFE): armed by `Perf.pickerOpened(kind)`,
    SELF-TERMINATES on the first frame `#stickerApplyModal` has `.hidden`
    (covers every close path — do not add per-close disarm calls), cancelled
    by `pickerClosed()`/`setOn(false)`. WKWebView never fires longtask, so
    this sampler is the on-device jank/thermal proxy. It is measurement-only
    and dies with the modal — NOT a second animation clock.
  - Wrap block after the Perf module reassigns top-level function
    DECLARATIONS only; `DeckInspector.renderCompositionInto` is a method —
    wrapped by property reassignment instead. `tests/stkrb1.test.mjs`
    re-evaluates picker internals with a no-op Perf stub — new in-body
    `Perf.mark` calls must keep that stub shape working.
  - `body.perf-flat` (debug "flat picker (A/B)" checkbox) strips the
    suspected iOS-compositor-expensive CSS from `#stickerApplyModal` only:
    backdrop-filter (both prefixes), `.dcs-ic` drop-shadows, saFlash/saRemove
    filter animations (swapped to opacity-only saFlashFlat/saRemoveFlat
    keyframes — base animations untouched), and the map-node pmPulseFade
    pulses. All rules scoped to the class; absent = zero effect.

- **v5.11 (Kimi, ECON1)** — reward economy rework; READ THIS BEFORE
  TOUCHING PAYOUTS, THE Economy MODULE, OR SAVE STATS:
  - Deal coin reward is FLAT: `Economy.dealFlat(stage, rating, isBoss)` =
    `dealBase + stage×(1+rating)` (boss: rating 3 + bossBonus), knobs in
    items.js `economy { dealBase: 1, bossBonus: 1 }` — the dealBase 1 is
    what makes stage-1 easy pay 3. Stage = node phase+1 (endless keeps
    counting). The old piles×smallest PRODUCT no longer feeds coins;
    item-driven bonuses (Payout stickers, pillar payouts, run.bonusCoins)
    pay on top unchanged. Ambush pays NO flat base (bounty only).
    Post-win reconciliation: `run.bonusCoins = total − flat`.
  - `breakdown()` still returns product fields — they're the SCORE now:
    `runScore` folds product per clear (win only); `scoreBanked` stamps at
    the ♠ boss (mirrors cardsFlippedBanked); `getCampaignScore()`/
    `getEndlessScore()` accessors. Stats bests `bestCampaignScore`/
    `bestEndlessScore`, Math.max folds, EXHIBITION-GATED like runCleared.
  - Mystery coinBonus now tallies totalCoinsEarned (was bypassed).
  - UI: map deal/boss nodes show the REWARD chip (dealBadge, knob-derived,
    pips gone); HUD `#hudScoreChip` (Score pre-boss / Endless after);
    #dealStatus shows "Reward +N · Score M" (dealFlatReward module var
    captured in startRun, mirrors onRunEnd's derivation); endStats score
    tiles render "— · not recorded" for exhibition.
  - Economy sanity (measured on genV3 maps): route income ≈ 22/37/52 per
    stage (~111/run vs ~130-200 before) — mildly starved early by design;
    price retuning is Jared's call in items.js.

- **v5.10 (Kimi + concurrent, STKPERF1/STKRB1)** — sticker-apply perf pass;
  READ THIS BEFORE TOUCHING THE SAVE PATH, Stats, OR THE PICKER GRID:
  - **Fossil sidecar**: `runFossils` NO LONGER rides the campaign blob — it
    persists in `ninelives.fossils.v1`, written only when a fossil changes
    (`fossilsDirty` flag; the write rides the SAME two-stage
    armSaveWrite/flushCampaignSave mechanism, no new timer). Restore adopts
    inline fossils from old saves; clearSave clears the sidecar too. Blob
    at a 50-card fixture: 45.0 KB → 7.2 KB per deferred write.
  - **Stats writes are coalesced** (STKRB1): bump/bumpAll dirty-mark in
    memory (get() reads the warm cache, never storage); the trailing write
    + `Stats.flush()` fires from `flushCampaignSave` — the single
    durability chokepoint (transitions/pagehide). Never add a synchronous
    Stats write to a tap path.
  - **Picker grid**: mount is rAF-CHUNKED per open (finish synchronously on
    confirm); eligibility sync is O(N) classList-only; confirms do targeted
    single-card updates; chip paint is flatter INSIDE the picker grid only.
    content-visibility windowing remains banned (the iOS blank-cards stall,
    comment ~4627).
  - Step 0 profiling verdict (agent-37): picker/apply JS was already
    sub-millisecond at 50 cards; remaining felt latency = designed
    animation holds (850/720ms, contract-preserved) + device paint. If jank
    persists on-device, get a Safari timeline before more surgery.

- **v5.09 (Kimi + concurrent, MYST3)** — mystery is a FIRST-CLASS node type;
  READ THIS BEFORE TOUCHING THE GENERATOR, MAP ARRIVAL, OR nodeHidden:
  - genV is now 3 (`RUN_GEN_VERSION`, ~13017). At genV≥3 `rollType(rng,
    genV)` rolls `["mystery", GEN_CONFIG.mysteryTypeWeight]` (25/125 ≈ 20%)
    INSIDE the type table — mysteries carve out of deals/packs/pickups
    naturally, repairs see final types, and convergence IMPROVED (34.6 vs
    50.3 avg attempts/stage). `setType` has a mystery branch (deletes
    add/packCount/suit/mixed/piles). The genV<3 cosmetic mask roll in
    makeRunStepper stays byte-exact for old saves.
  - `nodeHidden` is TYPE-based (`n.type === "mystery"`) — the `mystery`
    flag exists only on genV<3 regenerated maps. Any new code testing
    hidden-ness must use nodeHidden, never `n.mystery`.
  - Arrival: the seeded event IS the node's entire content (no underlying
    dispatch). `completeMystery(id)` (markNodeCleared + persist +
    showProgressionMap) is the SINGLE exit for every continuation —
    passive, pickers, store hook, ambush aftermath, impossible outcome, and
    finishResolveNode's explicit mystery branch (a REVEALED mystery re-tap
    completes, never re-rolls — exactly-once rides on the persisted reveal
    + applied-before-modal flush).
  - Migration: two-phase restore conversion (persisted `mystMigrated`,
    gated runGenVersion<3) — unvisited masked nodes convert to type mystery
    in place (deal fields + nodeCards/packCards locks scrubbed); first
    restore exempts revealed (visited) nodes, re-migration converts them.
    NO genV<3 overlay arrival path remains. Edge case: an old run's ENDLESS
    extension generates genV-2 stages whose mask flags are inert (nodes
    render revealed, no events) — known, accepted.
  - Rendering: `mapNodeInner` mystery case ("?", `.open` while revealed-
    not-cleared); cleared = spent/faded state; debug peek (`pm-myst-out`)
    unchanged; hold-help/label/key carry Mystery copy.
  - NOTE: a second agent worked concurrently on this change in the same
    tree (also committed 86aa8f3). The merged state was verified coherent
    and suite-certified — review diffs before assuming sole authorship.

- **v5.08 (Kimi, UNLOCK1)** — item-unlock framework (ships with NOTHING
  locked); READ THIS BEFORE ADDING unlock FIELDS OR TOUCHING ROLL POOLS:
  - items.js items may carry `unlock: {type:"milestone"|"behavior", stat,
    count}` (documented in the items.js header with the 15 stat names +
    a commented example). Validators fail loud on malformed shapes.
  - `ItemUnlocks` module (~15440, DOM-free): `statValue(name)` maps the 15
    public stat names to Stats fields (10 NEW additive Stats.DEF fields:
    bossesBeaten, cardsBuried, samesCalled, correctSames, jokersPlayed,
    stickersApplied, pillarsPlaced, basesPlaced, removalsUsed, pilesLost;
    the rest alias existing fields). `isUnlocked` derives LIVE from Stats —
    stats only grow, so derivation is stable; the persisted
    `ninelives.itemunlocks.v1` known-set exists ONLY to detect NEW unlocks
    for toasts (first load initializes it silently = retroactive).
  - EVERY new Stats increment gates on `!campaign.isExhibition()` at the
    call site (SEED1 parity). New engine emit: `"pile-killed"` (BoardState
    kill sites) — debug loseNow deliberately does NOT emit.
  - Gating is PRE-FILTER, never in-loop reroll: `StickerTypes.grantable()`
    filters locked (covers ~9 roll sites); `rollUnifiedSlots` pre-filters
    each class pool with `w: 0` for an empty class (the `card` pattern);
    Lammy preEquip filters + null-pads to COLUMN_SLOTS. UNGATED by design:
    the cursed-sticker bane pool and debug grants. Any NEW random-item path
    must draw from grantable()/the filtered pools or locks leak.
  - Toasts: `ItemUnlocks.checkNewUnlocks()` is called ONLY at deal end and
    run end (never mid-guess) — it STAMPS the known-set, so never call it
    without a screen to show the pops on. The pop queue chains inside
    `maybeShowUnlockCelebration`. Death/win screens render
    `ItemUnlocks.nearestLocked(2)` progress bars via a showOverlay section.
  - Collection screen: main-menu button, `.menu-screen` full page, boot-
    attached delegated hold-help (500ms store idiom), cursed stickers route
    through stickerChip (dcs-cursed).
  - The ship-state pins in tests/unlocks.test.mjs are written to SURVIVE
    the user adding real unlock fields (they read the registry
    dynamically) — keep them that way.

- **v5.07 (Kimi, SEED1)** — shareable run seeds + full-stream determinism;
  READ THIS BEFORE TOUCHING ANY RNG CALL SITE OR THE SAVE FORMAT:
  - `SeedCode` (~7219): 7-char base-31 codes (alphabet
    `ABCDEFGHJKMNPQRSTUVWXYZ23456789` — 31 chars, NOT base-32; 31^7 > 2^32,
    bijective, decode rejects overflow). Share string format:
    `DECK-TIER-CODE` via `runSeedShareStr()`.
  - `CampaignState.runRng(...keys)` is THE substream helper. Every content
    RNG in a run derives from runSeed keyed by stable ids: start rolls
    ("start"), store offer ("store", nodePos), reroll ("store", nodePos,
    rerollIndex), store packs ("storepack", nodePos, slot), sealed packs
    ("pack", nodeId), grant stickers ("grant", nodeId), deal seeds
    ("deal"|"ambush", nodeId, reshuffleIndex), player-choice randoms
    ("act", actionCounter++). `Math.random` survives ONLY as the default
    param for id-less QA/test paths. NEVER add a bare Math.random to a
    campaign content path — key it.
  - Deal-seed identity: `reshuffleIndex` module var beside `redealCost`,
    incremented by `doReshuffle`, persisted in the save blob
    (`blob.reshuffleIndex`); resume still replays the persisted deal seed —
    keying only replaces the Math.random MINT.
  - `pregenerateRun(dId, tId, seedOverride)` / `runGenKey` thread seeds;
    seeded pregen keys are distinct from seedless (neither can hijack the
    other). `startCampaign(seedU32)` → `setSeedOverride` (one-shot).
  - **Exhibition runs** (player-entered seed): `campaign.isExhibition()`,
    persisted in the save. They checkpoint normally but bank NOTHING — gates
    at Stats.runPlayed/addDeal/addCardsFlipped/campaignEnded/runCleared/
    endlessReached, the whole win-bank block (markRunWon/recordDeckWin/
    DeckUnlocks), and all Telem.purchase sites. `track()` analytics are
    deliberately ungated.
  - Save format gained `exhibition` + `actionCounter` (additive, defensive
    reads; pre-v5.07 saves default false/0).
  - Native share sheet intentionally absent — needs @capacitor/share +
    Xcode rebuild; clipboard copy (`copySeed`) ships instead.

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
