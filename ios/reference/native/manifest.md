# Native parity reference captures — v2 (AFTER set)

iPhone 16 Pro simulator (iOS, id 32A65310-8939-4F16-B8CB-ED5180FF50B7), app
`com.ninelives.shouldasaidsame` (Debug-iphonesimulator build). Screens are
1206x2622 px PNGs, captured either via `xcrun simctl io screenshot` on a
simctl-launched app (launch args below) or as XCTAttachments exported from
`ios/UITests/ParityCaptureUITests.swift` xcresult bundles (the harness
renamed them to this contract). This set is the CURRENT contract — captured
after the reference-driven parity pass landed, so it reflects the app's
post-fix state. The pre-pass BEFORE set was not committed (comparison
strips live with the pass report).

Launch-arg reference (all verified in AppDelegate/GameFlowController):
`-resetAll 1` wipes app-domain persistence; `-skipGate 1` skips the boot
gate; `-autoClimb 1 -deck pink -tier <t> -seed N` starts a campaign on the
map; `-autoDeal 1 -piles N -cards N -seed N` launches the deal demo;
`-autoMap 1 -autoTravel N` launches the map demo with auto-travel;
`-autoStore 1 -coins N` launches the store demo; `-showOverlay <kind>`
opens an end screen over the menu; `-demoOverlay help` opens the deal help
sheet; `-debugMap 1` makes every map node tappable; `-autoPlay 1` runs the
scripted player. Seeding stats via `"-ninelives.stats.v1" '{...}'` launch
args works because the NSArgumentDomain shadows the app domain.

## Files

- menu-fresh.png — title menu, no save, GATED state (ZEN first, no CLIMB —
  the web's fresh-boot menu; XCUI `testMenuFreshGated`, real boot gate).
- menu-continue.png — title menu with a climb in progress, CONTINUE button
  (simctl: started a campaign, killed, relaunched without `-resetAll`).
- settings.png — Settings sheet (from menu, `SETTINGS`).
- deckselect.png — deck select carousel (menu → CLIMB).
- zen-select.png — Zen mode select (menu → ZEN).
- tutorial-01.png … tutorial-07.png — the first-run tutorial bubbles,
  step1 through step6-bubble plus step7-tutorial-done (XCUI tap-through on a
  fresh boot).
- howto-1.png / howto-2.png — How To Play sheet pages 1-2 (menu → HOW TO PLAY).
- stats.png — Stats sheet (menu → STATS).
- collection.png — Collection grid (menu → COLLECTION).
- collection-detail.png — Collection detail for a sticker with the
  fixed-height pager and bottom prompt bar (XCUI: COLLECTION → tile tap).
  The detail closes on a SCRIM tap (normalized 0.5, 0.12).
- pause.png — pause sheet over a deal (≡ during `-autoDeal`).
- deal-early.png — fresh 9-pile deal (`-autoDeal -piles 9 -cards 39 -seed 777`).
- deal-mid.png — same seed under the scripted player, 7 of 9 piles alive.
- deal-late.png — same seed, 3 piles alive.
- deal-fan.png — the in-place FAN peek: FAN rail chip lit, pile contents
  fanned on the mid-deal board (there is no separate fan tray).
- deal-help.png — deal help overlay (`-demoOverlay help`).
- deal-summary.png — deal-cleared summary with the SCORE plaque and the
  rewards list (`-showOverlay cleared`).
- victory.png — climb victory screen with the ★ tile grid
  (`-showOverlay victory`).
- death.png — GAME OVER death screen with the seed chip
  (`-showOverlay dead`).
- mystery-modal.png — mystery event modal, Cache +6 outcome
  (`-showOverlay mystery`).
- prompt-bar.png — shared bottom confirm bar: the FIRST step of the
  two-step Settings → RESET PROGRESS confirm.
- map-bottom.png — fresh campaign map at the bottom clamp
  (`-autoClimb -deck pink -tier regular -seed 909`; the autoClimb seed bug
  is fixed — this layout is reproducible).
- map-mid.png — map after auto-travel: glowing avatar on the current node,
  green travelled trail, cleared node badges (deep-0 frame).
- map-top.png — the same climb scrolled to the TOP scroll clamp: the stage
  boss row is the highest reachable content.
- map-boss.png — centred on the crowned boss skull at the top clamp.
  NOTE: map-top.png and map-boss.png are the SAME byte-identical clamp
  frame (deep-5/deep-6 top clamp) — the boss row IS the top of the
  reachable map.
- map-mystery.png — map scrolled slightly, prominent "?" mystery node among
  the route web.
- store-shelf.png — store shelf (`-autoStore -coins 99`; the demo offer is
  RANDOM per launch — nodePos is nil so the store seed is
  `RNG.generateSeed()`, `-seed` does not pin it).
- store-detail.png — store detail view (from the ScreenshotUITests store
  walk).
- store-column-chooser.png — pillar/base detail with "PICK A COLUMN".
- store-pack-reveal.png — pack reveal as a CENTERED PANEL ("SMALL CARD PACK"
  caption, "Pick 1 card to keep", "View cards in play" pip, dim CONFIRM,
  "Skip (take nothing)"), recaptured after the PackReveal rework. Cards
  render at 48pt vs the web's 52pt (baked pixel-art card size constraint) —
  accepted approximation.
- store-detail-sticker.png — sticker detail (Donate): chip art, rarity,
  "PLACE STICKER · ◉ 1 gold" CTA (XCUI `testStoreDetailStills`).
- store-detail-same.png — same-power detail: EQUIPPED→NEW compare panel,
  "Equip X as your Same-Power?", "BUY & EQUIP · ◉ 5 gold" CTA.
- store-detail-pack.png — sticker-pack detail: foil art, "SMALL STICKER
  PACK" caption, COMMON rarity, "BUY · ◉ 5" CTA.
- picker-sticker.png — sticker apply picker (Bonus Coin). Pickers are
  BOTTOM SHEETS over the board with the deck histogram strip.
- picker-swap.png — swap-in picker after buying a card slot ("SWAP IN").
- picker-removal.png — removal picker ("REMOVE A CARD"; always last slot).
- unlock-toast.png — NOT CAPTURED. The unlock pop only fires at a real run
  termination with pending unlocks, and the scripted `-autoPlay` player's
  higher/lower heuristic wins nearly every deal (5 attempts across two
  capture passes, incl. one 18-minute seeded-stats run: stats seeded via
  `"-ninelives.stats.v1" '{"campaignsWon":1,"bestEndless":1}'` +
  `"-ninelives.itemunlocks.v1" '{"known":[]}'` — DITTO and GREEDY over
  threshold, empty known-set — still no loss). Capturing it needs either a
  deliberate-loss debug hook or a manual play session.

## Harness findings (affect reproducibility)

- `-autoClimb` now honors `-seed` (the earlier double-`startNewRun` bug in
  `GameFlowController.startCampaign` is fixed): seeded campaign map layouts
  are reproducible per launch, matching the deal/map/store demo paths.
- Launcher demo modes (`-autoDeal`/`-autoMap`/`-autoStore`) ignore
  `-resetAll` because the real boot never runs; the store test wipes by
  launching the real shell once with `-resetAll` first.
- The store header REFRESH pill is a `PixelButtonView` (not a UIButton) and
  invisible to the XCUI buttons query; tapping it opens the shared prompt
  bar ("Refresh the shelf for ◉N?") which must be confirmed with its
  "REFRESH" action — PromptBar/PixelButtonView accessibilityLabels are
  UPPERCASED, so `app.buttons["Refresh"]` never matches ("REFRESH" does).
  The reroll is two taps, not one.
- Store DETAIL buy labels (StoreDetailView): pillar/base "PICK A COLUMN"
  (or "BUY & PLACE"), samepower "BUY & EQUIP", removal "REMOVE A CARD",
  card "BUY & SWAP IN", sticker "PLACE STICKER", and PACKS fall through to
  the DEFAULT "BUY · ◉N" — every class is distinguished by its buy label,
  and a pack tile is the one with no column/sticker/equal affordances.
- Item-unlock pops fire only at real run TERMINATION (deal loss → pops
  before the death screen; victory → GO TO MAIN MENU → pops) and wait for
  their own CONTINUE tap when no autopilot runs — so a lost deal leaves the
  toast parked for capture. Quit-to-menu / abandon-climb / Zen-end paths do
  NOT pop natively. The pop's own dismiss button is "CONTINUE" — capture
  loops must check for the pop BEFORE tapping any CONTINUE (deal-cleared
  summaries use the same label). Seeding stats via the launch-argument
  domain works: `"-ninelives.stats.v1" '{"campaignsWon":1,"bestEndless":1}'`
  + `"-ninelives.itemunlocks.v1" '{"known":[]}'` puts DITTO (runsWon>=1) and
  GREEDY (endlessStagesReached>=1) over threshold with an empty known-set.
  Getting the scripted `-autoPlay` player to actually LOSE is the hard
  part — its higher/lower heuristic wins most deals; reliable deaths come
  from mystery AMBUSHES (few cards, few piles).
