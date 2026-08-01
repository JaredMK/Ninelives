# Shoulda Said Same — iOS

A native Swift port of the web game. The web build (`../index.html` +
`../items.js` / `../difficulty.js` / `../tutorial.js`) is the reference
implementation and stays untouched.

- **Phase 1 — engine + data.** `GameCore/` + `Data/`, verified against the real
  web engine by committed fixtures.
- **Phase 2 — the DEAL BOARD.** `Rendering/` + `UI/`: a SpriteKit board you can
  actually play, reached through a temporary debug launcher.
- **Phase 3 — menus, map, store.** Not built.

The visual contract is `../styleguide.html` (CRT CASINO). If a surface here
disagrees with that page, this surface is wrong.

## Build and test

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). The `.xcodeproj` is generated, not committed.

```sh
cd ios
make                 # generate the project, build GameCore, run the tests
make test            # just the tests
make verify-launch   # build the app, launch it in the simulator, print its boot receipt
make perf            # play a scripted 12-pile deal, print its frame timings
make device-run      # build + install + launch on a connected iPhone (see below)
```

The raw commands, if you prefer them:

```sh
xcodegen generate --spec project.yml
xcodebuild build -project ShouldaSaidSame.xcodeproj -scheme GameCore \
  -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test  -project ShouldaSaidSame.xcodeproj -scheme GameCore \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

> **Simulator name.** There is no iPhone 15 runtime on this machine. `iPhone 17`
> (iOS 26.4) is unambiguous and is what the Makefile defaults to. `iPhone 16`
> exists too but is listed under two architectures, so it needs disambiguating:
> `-destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5,arch=arm64'`.
> Override with `make test SIM='iPhone 16 Pro'`.

**Why XcodeGen.** `project.yml` is the whole project definition in 90 readable
lines — reviewable in a diff, regenerated identically on any machine, and it
keeps merge conflicts out of `project.pbxproj`. Tuist would have worked too;
XcodeGen was chosen because it needs no manifest compilation step.

**Signing** is off (`CODE_SIGNING_ALLOWED=NO`) — everything here runs in the
simulator. Add a team in Xcode when you want to run on a device.

## Layout

| Path | Contents |
| --- | --- |
| `GameCore/` | The engine. **Pure Swift — zero UIKit/SpriteKit/SwiftUI imports** (enforced by a test). |
| `Data/` | Codable structs + fail-loud validators over the bundled JSON. |
| `Resources/` | `items.json`, `difficulty.json`, `tutorial.json`, `meta.json` — generated, see below. |
| `Rendering/` | The SpriteKit board: palette, baked textures, cards, piles, the connection web, chrome, the CRT layer. Imports SpriteKit; never touches game rules. |
| `UI/` | View controllers + gestures + the GameCore wiring, and the temporary debug launcher. |
| `Assets/Fonts/` | VT323 + Press Start 2P as `.ttf`, unwrapped from the web's `.woff2`. |
| `App/` | The host app. Validates the data at boot, then shows the launcher. |
| `Tests/` | XCTest suite. |
| `Fixtures/` | Ground truth captured from the **real web engine** (committed). |
| `Tools/` | The Node exporters that produce `Resources/` and `Fixtures/`. |

### Modules

| Swift | Web counterpart |
| --- | --- |
| `RNG.swift` | `makeRng` (mulberry32) + the seed-derivation helpers |
| `SeedCode.swift` | `SeedCode` — the shareable 7-char run seed |
| `Cards.swift` | card shapes + `stickerCardEligible` / `cardMatchesSuit` / `cardIsWildSuit` |
| `DeckManager.swift` | `DeckManager` + `DeckStats` |
| `Economy.swift` | `Economy` |
| `RunMapTypes/Validation/RunMap/RunMapRun.swift` | `RunMap` (generation, validation, stacking, authoring seam) |
| `BoardState.swift` | `BoardState` |
| `RunState.swift` | the engine's `run` object + its event surface |
| `GameEngine*.swift` | `GameEngine` (core, sticker/Pillar effects, Bases + Same-Powers) |
| `CampaignState*.swift`, `CampaignSupport.swift` | `CampaignState` + the store roll |
| `Persistence.swift`, `ItemUnlocks.swift` | `SaveStore` / `Stats` / `ZenStats` / `DeckUnlocks` / `ZenUnlocks` / `ItemUnlocks` |

`GameCore` builds with `-O` even in Debug: map generation runs up to 240
build-and-validate attempts per stage, and the suite generates hundreds of maps.
Unoptimized the suite takes ~9 minutes; optimized it takes ~1. Testability stays
on, so `@testable import GameCore` still works.

## Editing the data files (the workflow)

`items.js`, `difficulty.js` and `tutorial.js` at the repo root remain **the only
hand-editable home** for item and difficulty data — exactly as `AGENTS.md`
requires. iOS does not fork them; it mirrors them.

```
items.js ─┐
difficulty.js ─┼─► node Tools/export-data.mjs ─► ios/Resources/*.json ─► GameCore bundle
tutorial.js ─┘
```

So the loop is:

1. Edit `items.js` / `difficulty.js` / `tutorial.js` at the repo root.
2. `cd ios && make data` (or `node Tools/export-data.mjs`).
3. Rebuild. `make test`.

The exporter also lifts `ITEM_UNLOCK_STATS` and `DECK_RULES` out of `index.html`
into `meta.json`, so Swift never hardcodes those either. Non-finite numbers fail
the export loudly rather than silently becoming `null`.

**Validation is fail-loud and names the offender**, matching the web:
`[items.js] stickers 'quickBury': `tier` must be one of common|uncommon|rare`.
`ItemData` / `DifficultyData` throw; `TutorialData` only records problems (the
game must never brick on a copy typo), same as the web.

Anything numeric that isn't a typed field stays reachable through
`ItemDef.num(_:_:)` — the twin of `itemNum(def, key, fallback)`. It never treats
`0` as missing.

## Seed compatibility

**Same seed + deck + tier produces the same map, stores, packs and draws on web
and iOS.** This is enforced, not asserted:

`Tools/export-fixtures.mjs`, `export-traces.mjs` and `export-campaign.mjs` load
the **real web engine** through `../tests/_harness.mjs` — the same loader the
5,049-test web suite uses — and record its output into `Fixtures/`. The XCTest
suite replays each one and compares.

Re-capture after a web-engine change:

```sh
make fixtures && make test
```

A diff in `Fixtures/` is the signal that the two implementations have parted
ways.

## Tests

```sh
make test
```

216 tests. The fixture-backed ones are the load-bearing part; the hand-written
ones pin rules the fixtures can't express (fail-loud validation, boundary
conditions, invariants across many seeds). Tests read tunables live from the data
files, so a retune in `items.js` never breaks the suite — only a rule change does.


---

## Phase 2 — the deal board

### Running it

The app opens a **debug launcher** (deck / tier / piles / cards / items / seed →
START DEAL). It is scaffolding for Phase 2 only and gets deleted in Phase 3.

Every option is also a launch argument, so a deal can be started without taps:

```sh
xcrun simctl launch <UDID> com.ninelives.shouldasaidsame \
  -autoDeal 1 -piles 12 -cards 52 -seed 4242 -items 1 -fps 1
```

| Argument | Meaning |
| --- | --- |
| `-autoDeal 1` | start a deal immediately |
| `-autoPlay 1` | play it with the deterministic script the engine traces use |
| `-piles N` | 1–12 |
| `-cards N` | 13–52 — a real climb's deck grows, so dial the depth you want |
| `-deck / -tier` | `pink\|mamma\|smith\|lammy`, `regular\|master\|legendary` |
| `-items 1` | bind a Pillar per column, a Base, and a Same-Power |
| `-fps 1` | draw the live frame-time readout |
| `-demoOverlay fan\|help\|swipe` | open an overlay for a screenshot |

A finished deal writes `Documents/deal-receipt.json` — result, guesses, and the
run's frame timings. `make perf` runs one and prints it.

### Input

Ported from the web's swipe rules so the feel carries over, with native
recognizers instead of pointer bookkeeping:

| Gesture | Result |
| --- | --- |
| tap a pile | select it |
| swipe up / down | Higher / Lower |
| swipe sideways (either way) | Same |
| release inside the 26pt dead-zone | cancel, pile stays selected |
| hold a pile (350ms) | its card help, in the deck band |
| FAN, then tap a pile | that pile's full face-up fan |

`DRAG_THRESH 26`, `TAP_SLOP 8`, `INFO_HOLD_MS 350` — the same constants as
`index.html`. `RenderingTests` pins the direction mapping against the web rule.

### Perf

The port exists partly to escape the browser's per-frame costs, so the rules are
strict and mechanical:

- **Everything is baked.** Text, panels, card faces, the CRT layer and the web's
  dashed edges are rendered to textures once and cached; frames only blit
  sprites. `Rendering/` uses no `SKEffectNode`, no `CIFilter`, and no
  `SKShapeNode` on the hot path.
- **The phosphor glow is baked into the glyph texture**, not applied per frame.
- **The CRT overlay is ONE static sprite.** The only thing that ever animates on
  it is the one-shot 240ms flicker at deal end.
- **Layout runs on size changes only** — never per frame.
- `SKView.ignoresSiblingOrder` is on, so **every node states its own
  zPosition**; equal zPositions draw in arbitrary order.

Measured on the iPhone 17 simulator (iOS 26.4), scripted 12-pile / 52-card deal:

| | frames | mean | worst | fps | over 16.7ms |
| --- | --- | --- | --- | --- | --- |
| 12 piles, seed 909 | 679 | 16.68ms | 23.08ms | 60.0 | 1 |
| 12 piles, seed 31337 | 628 | 16.68ms | 27.39ms | 59.9 | 1 |
| 9 piles, seed 4242 | 603 | 16.68ms | 22.60ms | 60.0 | 1 |

The single over-budget frame each run is the first deal-out frame, where the
card textures bake. Everything after is flat 60.

---

## Running on a real iPhone

Simulator builds are unsigned; a device needs YOUR Apple ID. One-time setup:

1. **Xcode ▸ Settings ▸ Accounts ▸ + ▸ Apple ID** — sign in. A free account
   works; apps just expire after 7 days.
2. Find your Team ID: same panel, **Manage Certificates**, or
   developer.apple.com/account ▸ Membership details.
3. Write it into an untracked local override:

   ```sh
   echo 'DEVELOPMENT_TEAM = ABCDE12345' > ios/Local.xcconfig
   ```

4. Plug the phone in, unlock it, tap **Trust This Computer**.
5. `cd ios && make device-run`

First run only: the phone will refuse to open the app until you approve the
certificate at **Settings ▸ General ▸ VPN & Device Management ▸ Developer App ▸
Trust**.

### Or entirely in Xcode

```sh
cd ios && xcodegen generate --spec project.yml && open ShouldaSaidSame.xcodeproj
```

Select the **ShouldaSaidSame** scheme, pick your iPhone in the device menu, and
press ▶. If it complains about signing, open the target's **Signing &
Capabilities** tab and choose your team there — that writes the same setting
`Local.xcconfig` holds.

> `PRODUCT_BUNDLE_IDENTIFIER` is `com.ninelives.shouldasaidsame`. A free Apple
> account can't reuse an identifier another account has registered — if
> provisioning fails, change it to something of your own
> (`com.<you>.shouldasaidsame`) in `project.yml` and regenerate.
