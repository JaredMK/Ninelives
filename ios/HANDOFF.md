# HANDOFF → Kimi agent: finish the CRT CASINO look on the native iOS port

You are taking over a native iOS port (Swift, SpriteKit + UIKit — no web views) of the
HTML game **Shoulda Said Same** (`/Users/jaredkrosser/Documents/Ninelives/index.html`,
~33k lines, single file). Work on branch `ios-port`, working dir
`/Users/jaredkrosser/Documents/Ninelives/ios`. The engine, campaign flow, all screens,
sound, haptics, tests, and an exact-art extraction are DONE and committed (through
`efdac82`). What remains is the **atmosphere layer** — the thing that makes it read as
an old-school casino CRT game instead of "flat green with a fingerprint" — plus a final
polish sweep. The web build is the reference. **Port, don't redesign.** When in doubt,
open `index.html` and copy the numbers.

## The visual law
`/Users/jaredkrosser/Documents/Ninelives/styleguide.html` (branch neural-redesign; same
tokens live in `index.html` :root). Locked 8-color palette: feltDeep `#142820`, feltMid
`#1e3a2c`, cardFace `#ece4cf`, suitRed `#c22f45`, ink `#10100e`, gold `#d9a441`,
phosphor `#4ef08a`, shadow `#000`. VT323 body / Press Start 2P display. Hard offset
shadows, square corners, glow is phosphor-only, dither for intermediate hues, **no blur,
no filters, no per-frame work anywhere** — every texture is baked once.

## KNOWN DEFECTS TO FIX (root causes already diagnosed — start here)

1. **The "fingerprint" vignette.** `Rendering/CRTOverlay.swift` (SpriteKit) and
   `UI/CRTKit.swift` → `CRTOverlayUIView.bake` (UIKit) draw the corner vignette as 22
   discrete concentric ellipse rings with stepped alpha. On a flat dark screen the hard
   ring edges read as a fingerprint/onion pattern — visible in every screenshot. The web
   spec (`#crtOverlay`, index.html ~line 6125) is ONE SMOOTH gradient:
   `radial-gradient(ellipse 140% 105% at 50% 45%, transparent 62%, rgba(0,0,0,0.28) 100%)`
   over 2px-period scanlines `rgba(0,0,0,0.13)`. Rebake both overlays using
   `CGContext.drawRadialGradient` (scale the context to get the 140%×105% ellipse —
   e.g. draw a circle gradient under an affine scale), transparent until 62%, easing to
   0.28 black at the edge. Keep: baked once per size, cached, zero per-frame work, the
   one-shot 240ms steps(4) flicker. Kill every ring.

2. **Missing `#tissue` backdrop — screens are flat green.** The web paints, BEHIND every
   screen (index.html ~line 5262): two felt-mid whispers
   `radial-gradient(circle at 28% 22%, rgba(30,58,44,0.5), transparent 46%)` +
   `radial-gradient(circle at 78% 72%, rgba(30,58,44,0.5), transparent 48%)` over
   `radial-gradient(ellipse at 50% 45%, felt-2, felt 55%, felt-3)` (all felt tokens are
   the deep/mid felt family under CRT CASINO). Build a `TissueView` (UIKit,
   `UIImageView` with a baked image; and an SKSpriteNode variant or reuse the image in
   `DealScene`) and install it as the BOTTOM layer of: GameFlowController's root view,
   MenuScreenBase, MapViewController (under the scroll), StoreViewController, and the
   deal scene (under the board). Bake once per size, smooth gradients, no animation.

3. **Missing felt-nap dither tile on menus/store.** Web `.menu-screen::before`
   (~line 1970): the 2×2 feltMid⊕feltDeep checker (`--felt-tile`) tiled at 4px,
   `image-rendering: pixelated`, over the tissue. The map already has this
   (`MapArt.backgroundTile()`) — reuse that exact tile as a `UIColor(patternImage:)`
   layer (alpha as needed) on MenuScreenBase, StoreViewController, sheets' panel
   backgrounds if the web shows nap there (check), and the deal board's felt. After
   1–3, a menu screenshot must show: nap texture + soft center-light falloff + smooth
   corner vignette + scanlines — the casino table under a CRT, not flat green.

4. **Sweep every remaining surface against the web with fresh eyes.** After the
   atmosphere stack lands, re-capture all surfaces and diff against
   `scratchpad web refs` (see Evidence below). Known secondary gaps to check: HUD
   suit-tracker active-suit scale (web scales the active suit 1.28), the map "?" key
   button styling, StoreDetailView + CardPicker + PackReveal + DeckInspect (these were
   NOT restyled in the last pass — hold them to the same law: shell? panels? exact art?
   check the web), PromptBar vs the web's bottom prompt bar, victory/death overlay
   layout vs web `#overlay` markup, Zen HUD. Fix what differs; justify anything
   deliberately different in the final report.

5. **Improve within the law, not beyond it.** "Improved game" means: 60fps on device,
   crisp pixel-grid rendering (integer scales, `.nearest` filtering everywhere art is
   scaled), correct safe-area behavior, tactile press states, the web's animation
   timings honored (AnimQueue causality, 420ms map hop, 240ms flicker). It does NOT
   mean new visual ideas, new colors, new effects, or blur/filters. The web build is
   the ceiling and the floor.

## Repo map (ios/)
- `GameCore/` — pure Swift engine + campaign (NO UIKit/SpriteKit imports — keep it that
  way). 235 XCTests incl. web-parity fixture replays: `make test`.
- `Rendering/` — SpriteKit board: `DealScene`, `CardNode`, `PileNode`, `DeckPanel`,
  `Chrome`, `CRT.swift` (palette/fonts), `CRTOverlay`, `PixelTexture` (bake helpers),
  `MapArt`, `ItemArt`, `ArtBundle` (loads `Assets/PixelArt/*` — 103 EXACT PNGs
  extracted from the web's baked CSS vars: characters + tier overlays + all pxi-* item
  icons — always prefer these over drawing).
- `UI/` — UIKit shell: `GameFlowController` (campaign spine), `MapViewController`,
  `StoreViewController`, `MenuScreens.swift`, `TopShellView` (persistent HUD+histogram
  shell on map/store), `Sheets.swift` (pause/how-to/stats bottom sheets), `CRTKit`
  (PixelPanelView/PixelButtonView/CRTOverlayUIView), `DealViewController/DealController`,
  `PhaseOverlayView` (cleared/death/victory/mystery), `PromptBar`, `FlowAutopilot`.
- `UITests/` — `TutorialUITests` (real-touch tutorial regression), `ScreenshotUITests`
  (taps through every menu surface, attaches screenshots).
- `project.yml` — XcodeGen. After adding/removing files: `xcodegen generate`.

## Build / run / verify (exact commands)
- Build: `xcodegen generate && xcodebuild -project ShouldaSaidSame.xcodeproj -scheme
  ShouldaSaidSame -destination 'id=32A65310-8939-4F16-B8CB-ED5180FF50B7' build`
  (iPhone 16 Pro sim; `xcrun simctl list devices available` if the id changed).
- Unit tests: `make test` (must stay 235/235).
- UI tests: append `-only-testing:ShouldaSaidSameUITests/TutorialUITests test` (and
  `ScreenshotUITests`) to the xcodebuild line. Extract screenshots:
  `xcrun xcresulttool export attachments --path walk.xcresult --output-path out/`.
- Screenshot harness (launch args): `-resetAll 1 -skipGate 1` (fresh, campaign open),
  `-autoDeal 1 -piles 6 -seed 4242 -deck pink -items 1` (deal board),
  `-autoMap 1 -autoTravel 2 -seed 909` (map mid-climb),
  `-autoStore 1 -coins 30 -seed 909` (store),
  `-showOverlay cleared|dead|victory|mystery` (end-of-deal overlays),
  `-autoCampaign N` (autopilot plays N campaigns end-to-end, writes
  campaign-receipt.json in the app container — run once before finishing to prove no
  regressions in flow).
  Capture: `xcrun simctl launch <SIM> com.ninelives.shouldasaidsame <args>` then
  `xcrun simctl io <SIM> screenshot out.png`.
  ⚠️ zsh does NOT word-split unquoted `$var` — pass launch args as literal words, never
  via a shell variable, or every arg arrives as one string and is silently ignored.
- Web reference captures (390×844) already exist:
  `/private/tmp/claude-501/-Users-jaredkrosser-Documents-Ninelives-ios/58cbefea-4755-4394-80de-9f4df83ceced/scratchpad/web/*.jpg`
  and current native captures in `../native2/`, composed strips in `../pairs/`. If that
  tmp dir is gone, re-capture the web at 390×844 from `index.html` in a browser.

## Hard-won lessons (do not re-learn these)
- `cancelsTouchesInView`: any gesture recognizer on a container view CANCELS UIKit
  button touches inside it. Twice bitten (tutorial bubbles, sheet scrim). Always gate
  recognizers with `gestureRecognizer(_:shouldReceive:)` → `touch.view === <container>`.
- Views baked before first layout have zero width — rebake in `layoutSubviews` when the
  width changes (`TopShellView.bakeBand` shows the pattern).
- `PixelButtonView` with an empty title has an empty accessibility label — set
  `accessibilityLabel` explicitly for compound buttons or the UI tests can't find them.
- GameCore stays pure; `Array.subscript(safe:)` app-side lives in CRTKit.
- macOS has no `timeout`; don't chain `sleep` in foreground bash.

## Definition of done
1. The fingerprint is gone: menu/map/store/deal screenshots show smooth vignette +
   scanlines + felt nap + tissue light — side-by-side with the web refs they read as
   the same game. Include before/after strips per surface.
2. Full-surface diff table (surface → differed → why → fix), with deliberate
   differences called out and justified.
3. `make test` 235/235; TutorialUITests + ScreenshotUITests green; one
   `-autoCampaign 3` autopilot run completes with a receipt and no crash.
4. 60fps held on the deal board (no new per-frame work; every new texture baked+cached).
5. Committed on `ios-port` in reviewable chunks with real command output for every
   claim. Report at the end; don't stop for approval between chunks.
