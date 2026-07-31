# Shoulda Said Same — iOS (Phase 1: engine + data)

A native Swift port of the web game's engine. **Phase 1 renders nothing** —
`Rendering/` and `UI/` are deliberate empty stubs; SpriteKit lands in Phase 2.

The web build (`../index.html` + `../items.js` / `../difficulty.js` /
`../tutorial.js`) is the reference implementation and stays untouched.

## Build and test

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). The `.xcodeproj` is generated, not committed.

```sh
cd ios
make                 # generate the project, build GameCore, run the tests
make test            # just the tests
make verify-launch   # build the app, launch it in the simulator, print its boot receipt
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
| `Rendering/`, `UI/` | Empty Phase 2 stubs. |
| `App/` | A bare host app: it validates the data, smoke-runs the engine, shows a blank screen. |
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
