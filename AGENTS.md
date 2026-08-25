# AGENTS.md — Ninelives

Mobile-first card game. The SHIPPING build is the native Swift app in `ios/`.
The original single-file web build (`index.html`) is a **FROZEN REFERENCE**
as of v6.78 — no longer maintained, never a required mirror (see "The iOS
engine is the source of truth" below). A Capacitor wrapper lives in `app/`.

## Layout

- `index.html` — the entire game: all logic in one inline `<script>`, all
  styles in one `<style>`. ~27k lines; navigate it via the module map in
  `README.md` and grep, never by scrolling.
- `items.js` — `NINELIVES_ITEMS`: every shop item (stickers, pillars, bases,
  same-powers, packs) + store config.
- `difficulty.js` — `NINELIVES_DIFFICULTY`: tier bands, joker caps, zen config.
- `tutorial.js` — `NINELIVES_TUTORIAL`: all first-run tutorial copy.
- `tests/` — Node test suite, no browser needed (see Testing).
- `ios/` — the native port (SpriteKit + UIKit, no web view). `GameCore/` is a
  pure Swift engine and must stay free of UIKit/SpriteKit imports;
  `Rendering/` is the SpriteKit board, `UI/` the UIKit shell.
  See `ios/README.md`; build/test with `make` in `ios/`.

### The iOS engine is the source of truth (v6.79 — the web is CUT OUT)

- `index.html`'s engine is FROZEN at v6.78. **No change needs a web
  counterpart, ever.** Do not edit `index.html` or `tests/*.mjs`; the web
  suite (`node tests/all.mjs`) is no longer a commit gate — it simply
  documents the frozen build.
- The three data files are still shared history and remain THE hand-editable
  data home: `ios/Tools/export-data.mjs` (`make data`) regenerates
  `ios/Resources/*.json` from `items.js` / `difficulty.js` / `tutorial.js`.
  **Edit the `.js` files, never the exported JSON**, then re-export.
- `ios/Fixtures/*.json` is the **GOLDEN BASELINE** — captured from GameCore
  ITSELF by `ios/Tests/GoldenRecorder.swift` (`make golden`), replayed by the
  fixture suites on every `make test`. An INTENTIONAL engine change
  re-records the baseline in the same commit (`make golden`, review the
  diff, `make test` green); an unintentional diff is a caught regression.
  The save blob's key set is pinned EXACTLY by the golden round-trips — a
  new persisted field is a deliberate act made by re-recording.
- NEW gameplay is tested with Swift-native XCTest against GameCore directly
  (rules, boundaries, invariants — see `ios/Fixtures/README.md`); the golden
  layer is the regression net underneath, not a substitute.
- `make test` in `ios/` must be green before any commit.

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

- **Player-facing noun is "climb", never "run" (v5.72).** A campaign attempt is
  a **climb** in every string a player can read — buttons ("Start Climb", "New
  Climb", "START CLIMB"), stats labels ("Climbs played", "Climbs won", the
  "Climbs" section head), unlock hints (`HINTS.runsPlayed` → "Play 3 climbs"),
  help/tutorial copy, deck unlock notes, map tooltips, and the debug logbook.
  **The code keeps `run`**: identifiers (`run`, `runSeed`, `startRun()`,
  `isRunStarted()`, `RunMap`), CSS classes (`.run-stat`, `.run-map`,
  `.stats-runs-head`), telemetry stat keys (`runsPlayed`, `runsWon`) and every
  localStorage key are UNCHANGED — renaming stat keys or storage keys would
  silently wipe player progress. So: `run` in code, "climb" on screen. When you
  add copy, say climb; when you add a field, `run` still matches its neighbours.
  Note "run" as a *verb* stays ("later deals run longer and harder").
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
- **12px font floor.** No text in the game renders below 12px (player
  report: smaller was unreadable). When something no longer fits at 12px,
  give the CONTAINER room (drop tracking, widen, or drop redundant
  decoration — e.g. map node-cards dropped their corner indices, keeping the
  numeral-first centre rank); never shrink back under the floor. Guarded by
  tests/fontfloor.test.mjs.
- **Stable containers.** A container's size must NOT change when its CONTENT
  swaps. Hold-for-help takes over the histogram band by OVERLAYING it (the
  band's children go `visibility:hidden`, never `display:none`) so the band —
  and the board below it — never move; the Collection detail runs at ONE
  fixed height for every item so its ◀ ▶ pager never shifts under the thumb.
  New swap-in-place UI follows the same rule: fixed shell, content scrolls
  inside it, nothing ever exceeds its container.
- **Phone-first.** Touch/pointer input first (swipe to guess, hold to peek,
  no hover-dependent UI), safe-area insets on every fixed element, layouts
  must fit ~390px-wide phones (fluid `clamp()`/vw/svh + `fitBoard`, not media
  queries). Desktop affordances (`title=`, keyboard) are optional extras,
  never the only path.

## Convention 4: tests gate every commit

```sh
cd ios && make test   # must be 100% green before ANY commit
```

*(The web-suite gate `node tests/all.mjs` retired with the v6.79 web freeze —
the notes below describe the frozen web build.)*

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

## Standing rules — hard-won, still binding

*(Distilled from the per-version handoff log. These are RULES, not history:
every line is a constraint that still applies. When a change alters shared
structure — generator, save format, caches, the visual law — update the rule
here rather than appending a new changelog entry. `git log` is the history.)*

### Rendering & performance — the bans

These came from on-device Web Inspector timelines (the app webview, not
Safari: iOS gives third-party webviews lower memory priority, so the shell
purges and re-rasters where Safari never does). Every one is load-bearing.

- **Always-on animations may animate `transform`/`opacity` ONLY.** Animating
  `box-shadow` or `filter` repaints the element every frame — paint-level
  power draw, device heat, then iOS throttling and multi-second stalls.
  One-shot entrance tweens may still ease whatever they need.
- **`backdrop-filter` is BANNED on any full-viewport element**, and `blur()`
  is banned game-wide. Small-area blurs (chips, bars) are fine. A 72-card
  picker behind a full-screen blur produced 2.9s and 15s main-thread freezes.
- **The `body:has(.deck-modal:not(.hidden))` pause contract**: while any
  deck-modal is open, background animators get `animation-play-state: paused`,
  and the background flattens (`box-shadow`/`filter` killed outside the modal
  subtree). ANY new always-on animation that can sit behind a deck-modal MUST
  join that list. Keep the `:has()` selector — it self-syncs across every
  open/close path; a JS hook would strand state.
- **Picker FX are transform/opacity only** and picker tiles stay FLAT at any
  size (`SA_XLITE_DECK` gates `sa-xlite`, dropping tile shadow/border and the
  disabled-card grayscale filter). `content-visibility` windowing in the
  picker grid stays BANNED — it caused the iOS blank-cards stall.
- **Don't pre-promote layers.** No blanket `will-change` — it holds GPU
  memory; opacity animations composite on demand. Standing layer footprint,
  not raster cost, is what hits the backing-store cliff.
- **Diagnosing the next stall**: Xcode-run the app → Safari → Develop →
  iPhone → the app webview → Timelines. Composite-dominated long frames mean
  layer pressure; long frames with ~zero recorded work mean the main thread is
  waiting on the compositor; JS records mean actual code (never the case yet).
  If pressure persists, layer COUNT is the next target (map node pulses,
  character idle parts, board card faces).

### The Perf module

- Ring-CAPPED: never push to `entries` directly, go through `pushEntry`.
- Capture is **memory-only — never route it through localStorage**; the
  Capacitor shim posts a native message per `ninelives.*` setItem.
- The frame-gap sampler self-terminates on the first frame the picker modal is
  hidden (covers every close path — don't add per-close disarm calls). It is
  measurement-only and dies with the modal; it is NOT a second animation clock.
- `tests/stkrb1.test.mjs` re-evaluates picker internals with a no-op Perf stub
  — new in-body `Perf.mark` calls must keep that stub shape working.

### The visual law (CRT CASINO)

`/styleguide.html` is the visual CONTRACT — read it before ANY visual change.

- **Palette lives in `:root` tokens** (`--felt-deep`/`--felt-mid`/
  `--card-face`/`--suit-red`/`--ink`/`--gold`/`--phosphor`/`--shadow`). New UI
  uses tokens, never hex. Only `--phosphor` may glow. Shadows are hard 4px/2px
  offsets, corners are square, texture is baked dither tiles — never
  gradients, never blur.
- **Fonts**: VT323 body + Press Start 2P display (≥11px), self-hosted in
  `app/assets/fonts/`, loaded in BOTH the online link block and offline
  `fonts.css` — build-www pattern-matches that head block; keep both paths.
- `#crtOverlay` is ONE static scanline+vignette layer, topmost and
  pointer-inert. Don't add layers or filters to it.
- The `PixelArt` module renders its matrices ONCE at boot to data-URIs on
  `:root` vars, fail-loud validated. Art changes = edit the matrices.
- **Cursed reads as phosphor bit-rot, NOT violet.** The surviving
  `CURSE_VIOLET`/`STICKER_FACE`/`STICKER_EDGE` constants are pinned on purpose
  as debug chrome / dead underlay — changing that is a spec decision, so
  update the pins with it.
- Suites crt2–crt5 (~420 checks) pin the aesthetic structurally. Update them
  WITH deliberate visual changes; never delete around them. `backdrop-filter`
  and `feTurbulence` are gone game-wide — do not reintroduce either.
- `app/www` is stale build output; `npm run build` in `app/` refreshes it.

### Economy & score

- Deal coin reward is FLAT: `Economy.dealFlat(stage, rating, isBoss)` =
  `dealBase + stage×(1+rating)` (boss: rating 3 + `bossBonus`), knobs in
  items.js `economy`. Stage = node phase+1; endless keeps counting. Ambush
  pays no flat base — its bounty IS the reward.
- The piles×smallest PRODUCT is the **SCORE**, never coins. `runScore` folds
  it per clear; `scoreBanked` stamps at the ♠ boss. Item-driven bonuses
  (Payout stickers, pillar payouts, `run.bonusCoins`) pay coins on top.
- Score bests are EXHIBITION-GATED, like `runCleared`.
- The deal-cleared summary keeps Score in its OWN plaque — the coin list must
  never re-grow a score line (pinned in `score.test.mjs`).

### Item unlocks

- items.js entries may carry `unlock: {type:"milestone"|"behavior", stat,
  count}`; validators fail loud on malformed shapes. `ItemUnlocks.isUnlocked`
  derives LIVE from Stats (stats only grow, so derivation is stable); the
  persisted known-set exists ONLY to detect NEW unlocks for toasts.
- **`quickBury` must stay UNGATED** — since Bury 1/Bury 2 were retired
  (v6.51), it is the cardsBuried ladder's only seed source
  (chicken-and-egg). **Every class keeps ≥2 starting items** or
  the store class roll starves.
- **`checkNewUnlocks()` fires at run termination and Zen end ONLY.** It STAMPS
  the known-set, so calling it without a screen to show the pops on silently
  swallows them — never re-add a mid-run or per-deal call.
- `ItemUnlocks.primeKnown()` runs at boot (otherwise first-session unlocks are
  swallowed by the lazy known-set init) — do not remove.
- Gating is **PRE-FILTER, never in-loop reroll**: `StickerTypes.grantable()`,
  `rollUnifiedSlots`' per-class `w: 0` for an empty class, Lammy's preEquip
  filter. Any NEW random-item path must draw from those or locks leak.
  Deliberately ungated: the cursed-sticker bane pool and debug grants.
- **Same-Powers sell ONLY as the Mystery Same-Power slot** (v6.51). The
  samepower class (weight unchanged in `store.classWeights`) yields
  `{kind:"samepower", mystery:true}` — no concrete id on the shelf, at most
  ONE per shelf (dedupe, like a typeCap), priced from
  `store.mysterySamePower` (never hardcode it). The concrete power is rolled
  at BUY time — one uniform draw over unlocked-AND-unequipped powers keyed
  `runRng("mysterysamepower", nodePos, slot)` — then the player keeps
  (equips) or discards (no refund) from the reveal overlay. Legacy concrete
  same-power slots in old saves stay buyable; the save serializes
  `"mystery":true` only when set, and the parity key-set comparison pins it.
- Every Stats increment gates on `!campaign.isExhibition()` at the call site.

### Seeds & determinism

- `SeedCode` is 7-char **base-31** (`ABCDEFGHJKMNPQRSTUVWXYZ23456789` — not
  base-32; decode rejects overflow). Share string: `DECK-TIER-CODE`.
- **`CampaignState.runRng(...keys)` is THE substream helper.** Every content
  RNG derives from runSeed keyed by stable ids: start rolls, store offers,
  rerolls, store packs, sealed packs, grant stickers, deal seeds,
  player-choice randoms (`"act"`, actionCounter++). `Math.random` survives
  ONLY as the default param for id-less QA/test paths — **never add a bare
  `Math.random` to a campaign content path; key it.**
- **Exhibition runs** (player-entered seed) checkpoint normally but bank
  NOTHING: Stats, the whole win-bank block, deck unlocks, and purchase
  telemetry all gate on it. `track()` analytics are deliberately ungated.
- Deal-seed identity includes `reshuffleIndex`, persisted in the save blob;
  resume replays the persisted deal seed.

### Map generation & mystery nodes

- `RunMap.makeRunStepper` builds one stage per `step()`. Deck-select pregen
  caches per `runGenKey`; **consumption DELETES the cache entry** — run maps
  are mutated in play, so a consumed map must never be reused.
- The save format carries `genV` (generator version) — this is the
  save-compat gate. Never remove it, and thread the RUN's own
  `runGenVersion` (not the global default) into every `generateRun` call site.
- `tryBuildStage` repair loops maintain incremental per-route sums: ANY new
  mutation of a node's `type`/`add`/`packCount` between index arming and the
  final validation read MUST go through `noteChange`, or the sums desync. Do
  not reintroduce full route re-walks in repairs.
- If you change generator OUTPUT intentionally, bump the genV scheme and gate
  it the same way.
- **Mystery is a first-class node type** (genV≥3), rolled inside the type
  table so mysteries carve out of deals/packs/pickups naturally.
  **`nodeHidden` is TYPE-based** — any new hidden-ness test must use
  `nodeHidden`, never `n.mystery` (that flag only exists on genV<3 maps).
- Arrival: the seeded event IS the node's entire content. **`completeMystery(id)`
  is the SINGLE exit** for every continuation — passive, pickers, store hook,
  ambush aftermath, impossible outcome. A revealed mystery re-tap completes,
  never re-rolls.
- Cursed CARDS are retired (restore strips them). Cursed STICKERS remain and
  must route through the shared chip path in any new chip-rendering code.
- The joker mystery outcome gates on **held-vs-cap**, not `jokersAllowed()` —
  the blanket-false would bar Pinky Regular, an authorized source. At cap the
  roll folds deterministically to coinBonus.

### The save path

- **Fossils ride their own sidecar** (`ninelives.fossils.v1`), written only
  when a fossil changes — not the campaign blob. Restore adopts inline fossils
  from old saves; clearSave clears the sidecar too.
- **Stats writes are coalesced**: bump/bumpAll dirty-mark in memory and the
  trailing write rides `flushCampaignSave`, the single durability chokepoint.
  Never add a synchronous Stats write to a tap path.
- The campaign save is TWO-STAGE: `persistCampaign` arms a 300ms trailing
  timer that hands serialize+write to `requestIdleCallback`, so it never lands
  inside a tap animation. `flushCampaignSave()` stays the synchronous write at
  transitions/pagehide.
- `getCardById(id)` and `getRunDeckLive()` return **LIVE objects — never
  mutate them**; mutations go through the mutator methods.
- **v6.76 persisted keys** (the iOS snapshot key-set parity pins these):
  `shopRolls` (climb-locked shop-rolled item values, R2 — see below) and
  `purgePriceCut` (Purge Coupon's accumulated climb-permanent cut) ride
  `campaign.serialize()`; store-offer slots may carry `shopRolled`/
  `shopRolled2`, and the offer carries `freeReroll` (On the House's free
  first restock). Engine run state gained `pillarRolls` (col → {roll,roll2})
  and `suitShieldSuits` (Daily Suit's per-deal roll — web re-derives it from
  the deal seed on resume; the iOS snapshot must round-trip it).
- **Restore accepts removal-shrunk decks** (v6.76 bugfix): the old
  `baseDeck.length < 52` floor rejected EVERY save made after a store Purge
  (a refresh wiped the climb). The floor is now relative
  (`baseDeck.length >= ownedIds.length`); poisoned decks still reach the
  rebuild and throw (the preserved-save path resume1 pins).

### Archetype batch v6.76 — the mechanics contracts

- **Same-tolerance = full Same (R1).** ONE shared resolution in `guess()`
  (`pillar.effect === "sameTolerance"`, `tol` ∈ near/royalPair/sum10/sameSuit)
  flips a would-be-wrong Same to correct; the ordinary correct branch then
  banks the charge + fires the Same-Power + bumps stats. Never branch around
  it. `sameSuit` also makes NON-Same calls safe on a same-suit landing; the
  other three tolerate Same calls only. **One per column, engine-enforced**:
  `placePillar`/`buyPillar` reject a family member onto a column already
  holding one (no in-family swap — pick up first).
- **Shop-rolled values (R2).** Items with `shopRoll:"rank"|"suit"` (+
  `shopRoll2`) roll at OFFER time inside `rollUnifiedSlots` off the seeded
  store stream (one extra draw per roll, in slot order), lock climb-wide in
  the campaign's persisted `shopRolls` map, ride the slot (`shopRolled`/
  `shopRolled2`), and transfer to the equipped item via
  `getColumnPillarRolls()` → `engine.startRun`'s 4th arg (`run.pillarRolls`).
  v6.78: TRANSMUTE rolls only its SUIT (its rank is the live most-common —
  see below) and RANK SHIELD left the shopRoll system entirely (dynamic,
  below); `shopRolls["rankShield"]` now stores the shield's INCUMBENT rank,
  not a shop roll.
- **Rank Shield is DYNAMIC (v6.78).** At Start Run the engine re-reads the
  FULL deck and protects its most common rank, writing the pick into
  `run.shopRolls["rankShield"]` / the rankShield columns' `pillarRolls`
  (the read `landingSave`/the web landing branch already had). TIE RULE:
  the incumbent (the campaign's previous pick, threaded in) keeps the
  shield until STRICTLY surpassed; a tie with no surviving incumbent picks
  among the leaders off the deal's seeded rng (only then is a draw
  consumed). The controller adopts the pick back
  (`campaign.adoptRankShieldPick` / web `adoptRankShieldPick`) so the
  incumbency persists across deals; the iOS plaque + {rank} template show
  the current rank.
- **Transmute targets the LIVE most common rank (v6.78)** — computed at
  buy time (and per display) from the full owned deck, ties → lowest (the
  Chorus rule, `mostCommonRank()` both sides); only the suit shop-rolls.
- **Quick Bury is LANDING-FIRED (v6.78, reversing v6.75):** it buries when
  its CARRIER lands (saved landings included — they land); a card landing
  ON a Quick Bury top fires nothing. **Rank Roots** (id `clubRoots`,
  relabeled) buries under each OTHER pile whose top matches the landing
  card's RANK — the ♣-tops trigger is retired. **Second Sight** (`linkTell`)
  arms a tell on EVERY alive pile for the NEXT DRAW ONLY via the shared
  `tellPiles` window (the X-draws window and the {color} climb roll are
  retired; iOS keeps `sightDrawsLeft` reads alive only so old mid-deal
  saves drain their window). **Diamond Boost** is column-wide (no target
  pick): +value to every alive ♦-topped pile in its column.
- **Endless payouts FREEZE (v6.78):** `Economy.dealFlat` clamps its stage
  term to items.js `economy.stageCap` (3) — endless deals pay phase-3
  rates forever. The clamp lives in dealFlat itself so every reader agrees.
- **Retired items strip on restore (v6.78, the Fibonacci removal):** both
  restore paths drop unknown item ids from inventories, column slots and
  the equipped Same-Power (registry-driven — a future retirement rides the
  same path). Never re-use a retired id.
- **Odds Assist (iOS, v6.78): ALL-BEST + legality.**
  `assistRecommendations()` returns EVERY (pile, call) pair tying the max
  survival probability — no tie-break ladder — and respects guess()'s
  legality gates (no SAME on a muted pile; magnet piles only while a
  Magnet is up). Still histogram-blind to probability modifiers by design.
  The glow is an INSET strip/frame on the card face (never past the card
  edge — stacked piles' glows must not blend).
- **Composition conditions (R3) read the FULL OWNED deck live** through
  engine hooks injected at deal start: `setCompositionHook`
  (`campaign.getRunDeckLive`) and `setPurseHook` (`campaign.getCoins`, the
  Pauper family's live gate — unset = dormant). Bare engine runs fall back to
  the deal deck + Infinite purse. Most-copied-rank ties break to the LOWEST
  rank (`mostCommonRank`); an empty full deck is always inert.
- **Daily Suit re-rolls per deal** from the deal's seeded rng at Start Run
  (a redeal mints a fresh seed → fresh suit; a resume replays → same suit).
- **On-purchase items fire inside `buyMixedSlot`** (Rank Purge purges the
  rolled rank via `purgeRankFromDeck`; Transmute re-suits it via
  `transmuteRankToSuit`) — never in-deal. Mid-deal campaign-side base effects
  persist through the "base-fired" handler (`addPurgeDiscount`,
  `removeDeckCard`, `inflictSticker`, `removeStickerInstances`); durable
  board re-ranks ride `valueApplied` → `campaign.randomizeCard` (Chorus,
  Rank Flood — same contract as Rank Setter).
- **Pricing**: Flat Purge's `value` OVERRIDES the Removal ladder in
  `removalPrice()` (flat, no multiplier/coupon); Purge Coupon cuts are
  climb-permanent, floored at the coupon's `min`. On the House: first
  restock per store (`storeOffer.freeReroll`) and first reshuffle per deal
  (derived from persisted `reshuffleIndex === 0` — no new checkpoint key);
  both freebies still consume their ladder rung.


### Debug

- The 🐞 entry is hidden unless debug access is on (`?debug`, or 7 quick taps
  on the build footer). The debug event log is a capped ring buffer rendering
  only the newest 50 — unbounded log rendering was a measured store-lag cause.
- **iOS: `recT` is the item-fire chokepoint** (v6.55). Every pillar/sticker/
  base/Same-Power/curse that fires must recT — it feeds telemetry AND the
  debug event log (name, effect, and the `fireContext` trigger line set at
  each action entry). A new fire path without recT is invisible on-device.
  **Every %-chance roll goes through `rollChance`** (v6.57): it consumes the
  same single rng draw the inline `rng.next() < chance` made, emits the
  structured `.rollResult` (hit AND miss) for the UI's roll indicators, and
  logs "rolled, missed" on a miss. Never add a bare inline chance roll.
  **Gambler's flip rolls ONCE per column at Start Run** and memoizes on
  `run.gamblerFlips` (web) / `RunState.gamblerFlips` (iOS, snapshot
  round-tripped): every payout read — mid-deal HUD projections included — is
  pure, so a projection can never disagree with the deal end, and no read
  consumes the action-stream rng.
- **iOS: mid-deal player choices use the parked-pending pattern** (v6.55):
  the engine parks (`pendingRipple`/`pendingSecondWind`/`pendingPowerShuffle`
  on RunState, snapshot round-tripped), the UI answers via PromptBar
  (`answer*` methods). Never apply a consent-gated effect inline in the guess
  path. The `*NeedsConsent` flags default false so web-parity fixtures keep
  replaying the auto behavior. A parked Second Wind emits `.secondWindOffer`
  (the drawn killer + recycle count) as the guess's only terminal event and
  defers `evaluateEnd` to `answerSecondWind` — the draw visibly precedes the
  prompt, and the held-out killer can otherwise fake an empty-deck win.
- **Saved landings fire landing stickers** (v6.57): a wrong guess saved by the
  Same-Charge backstop still LANDS the card (it becomes the new top), so its
  beneficial landing stickers fire (`fireSavedLandingStickers`). Curses and
  Trapdoor stay correct-only (the v6.52/53 fatal-landing audit stands), as do
  PILLAR landing effects. Guard returns and Second Wind recycles never land
  the card, so nothing fires there.
## Also

- Storage keys use the `ninelives.*` prefix only (the native bridge mirrors
  just that prefix to Capacitor Preferences).
- All user-facing strings rendered into HTML go through `escHtml`.
- Debug: `?debug` URL param (or triple-tap the title) opens the debug panel.
- Deploy: `.github/workflows/pages.yml` publishes to GitHub Pages on push to
  the live branch — the root site always rebuilds from the live branch.
