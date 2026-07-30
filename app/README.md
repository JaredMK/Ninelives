# Shoulda Said Same — iOS app (Capacitor wrapper)

The web game at the repo root (`index.html` + `items.js` + `difficulty.js` +
`tutorial.js`, deployed to `https://jaredmk.github.io/Ninelives/neural/`)
stays the **single codebase**. This folder only wraps it: a Capacitor iOS shell, a tiny build
script that assembles an offline copy, and native niceties (real save storage,
haptics, keep-awake) that the game reaches through the feature-detected
`NativeApp` shim in `index.html` — every one of them a no-op on the web.

- **App id:** `com.ninelives.shouldasaidsame` · **Name:** Shoulda Said Same
- **iOS project:** `app/ios/App/App.xcworkspace` (open the *workspace*, not the xcodeproj)

## One-time setup (on your Mac)

1. Install Xcode from the App Store (15+), then open it once so it installs
   its command-line tools.
2. Install Node 18+ and CocoaPods (`sudo gem install cocoapods` — or
   `brew install cocoapods`).
3. In the repo:

   ```bash
   cd app
   npm install
   npm run sync        # builds www/ from the repo-root game + updates the iOS project (runs pod install)
   npm run open        # opens App.xcworkspace in Xcode
   ```

## The two modes

The workflow stays **web-first**: develop the game as always (edit the root
`index.html`, push to `neural-redesign`, Pages deploys), and pick how the app
loads it:

### DEV — remote URL (instant iteration, no rebuild)

The webview loads the deployed GitHub Pages game. Push to `neural-redesign`,
wait for the Pages deploy, relaunch the app — no Xcode rebuild needed.

```bash
npm run mode:dev      # points the app at https://jaredmk.github.io/Ninelives/neural/
npm run sync
# then Run from Xcode once; afterwards every game change only needs a Pages deploy
```

Requires network, obviously. Saves still go to native storage (the shim runs
either way), so switching modes never loses progress.

### RELEASE — bundled assets (offline; the App Store mode)

The webview loads the local copy in `www/`, assembled by `npm run build` from
the repo-root game. **This is the only mode allowed for App Store submission**
— it works in airplane mode.

```bash
npm run mode:release
npm run sync
# then Product ▸ Archive in Xcode for TestFlight/App Store
```

`scripts/build-www.mjs` copies the three game files verbatim and patches
exactly two things, failing loudly if either pattern is missing:

1. the Google Fonts `<link>`s → the bundled `fonts/fonts.css`
   (VT323 + Press Start 2P — latin subsets committed under `assets/fonts/`), and
2. the Google Analytics loader `<script>` → removed (its inline config is a
   documented no-op when gtag never loads).

### Offline audit (release mode)

Everything else the game touches at runtime is inline or relative — audited:

| Resource | Source | Offline? |
|---|---|---|
| `items.js`, `difficulty.js`, `tutorial.js` | relative `<script>` (cache-busting query is fine locally) | ✅ bundled |
| All art (cards, felt grain, characters, map) | inline SVG / data-URIs | ✅ inline |
| All audio | WebAudio-synthesized (no files) | ✅ generated |
| Fonts | **was** fonts.googleapis.com | ✅ bundled by the build (the one real fetch) |
| Analytics (gtag) | googletagmanager.com | ✂️ stripped from the bundle (silent no-op anyway) |
| Saves | localStorage → Capacitor Preferences in-app | ✅ native |

Nothing else in the game fetches from a URL. If a future game change adds
one, the build script's final external-URL scan throws.

## Build & run on your iPhone (first time)

1. Plug in the iPhone. In Xcode's toolbar device picker, choose it (enable
   Developer Mode on the phone if prompted: Settings ▸ Privacy & Security ▸
   Developer Mode ▸ on, then reboot).
2. **Signing:** select the blue `App` project in the sidebar → the `App`
   target → *Signing & Capabilities*:
   - tick **Automatically manage signing**,
   - **Team:** pick your Apple ID team (add it under Xcode ▸ Settings ▸
     Accounts if it's not listed — a free Apple ID works for on-device dev),
   - if the bundle id collides, change it (e.g. append `.dev`) — free teams
     need a unique id.
3. Press **Run** (⌘R). The first install fails to launch with an
   "Untrusted Developer" message — on the phone: **Settings ▸ General ▸ VPN &
   Device Management ▸ your Apple ID ▸ Trust**, then launch again.
4. Free-team builds expire after 7 days — just Run again from Xcode. (A paid
   Developer account, needed for TestFlight/App Store anyway, removes that.)

Icon + launch screen are already wired: the **app icon** is the
equals-synapse logo (`icons/logo.svg`) rendered onto the cream felt as the
1024 icon; the **launch screen** is a flat solid `#f6f3ec` 2732 splash set
(no art — it's just the backdrop). With `launchAutoHide: false` in
`capacitor.config.json` the native splash covers launch **and** the webview
load/fetch; the game's in-page `#bootSplash` (JarHead Labs mason-jar mark,
inlined in `index.html`) takes over the moment the page paints, covers
hydration + init, then fades into the main menu. The shim hides the native
splash only after the HTML splash has painted, and the status bar is styled
dark-on-cream by the shim.

Changing the native side of that handoff (the config or the splash PNGs)
needs one `npm run sync` + an Xcode rebuild; the HTML boot splash is plain
game code, so in DEV (remote-URL) mode it reaches the app with a normal
Pages deploy — no rebuild.

## What behaves differently inside the webview

- **Saves live in native storage.** The shim mirrors every `ninelives.*`
  localStorage write into Capacitor Preferences and hydrates it back before
  the game boots — iOS can evict WKWebView localStorage, native storage it
  cannot. First launch migrates any existing webview localStorage save into
  Preferences once. On the web, localStorage remains the storage, unchanged.
- **Boot is gated on that hydration** (a few ms) — on web, boot stays
  synchronous.
- **Haptics**: light tap on a correct guess, medium on a save (Same Charge /
  Shield / Guard / Second Wind) and on banking a charge, success/error taps
  on win/loss. **Keep-awake** holds the screen on from Start-of-deal to
  win/loss. Both feature-detected; absent on web.
- **Safe areas**: `body.native-app` pads the layout for the notch and home
  indicator and adjusts the fixed-position pieces (Stage·Run badge, sticker
  confirm bar, debug corner tools, full-screen overlays). On Pages the class
  is never set.
- **No document bounce**: pinch/double-tap zoom and pull-to-refresh are
  suppressed in-app; the map keeps its own pan/rubber-band. Long-press
  callout/save-image sheets are suppressed app-wide (game surfaces already
  suppressed them on web — those fixes hold in WKWebView).
- **In dev (remote) mode** the app shows whatever the Pages deploy serves —
  including its hosted fonts and analytics. Release mode is the offline one.

## Day-to-day

| Task | Command |
|---|---|
| Game changed, app in DEV mode | push to `neural-redesign`, wait for Pages, relaunch app |
| Game changed, app in RELEASE mode | `npm run sync`, Run from Xcode |
| Flip modes | `npm run mode:dev` / `npm run mode:release`, then `npm run sync` |
| Ship to App Store | `npm run mode:release && npm run sync`, Xcode ▸ Product ▸ Archive |
