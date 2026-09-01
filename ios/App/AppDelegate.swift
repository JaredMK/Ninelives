import UIKit
import GameCore

/// PHASE 1: the app renders nothing. It boots, loads + validates the three data
/// files exactly as the web build does at boot (fail-loud), logs the result, and
/// shows a bare view. Rendering is Phase 2 — see Rendering/ and UI/.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // BOOT1: millisecond milestones for the launch path, printed on every
        // boot. The launch screen sits on screen for exactly this long plus
        // pre-main, so a regression here is a player-visible regression.
        let bootT0 = CACurrentMediaTime()
        func mark(_ label: String) {
            NSLog("[ShouldaSaidSame] boot +%.0fms %@", (CACurrentMediaTime() - bootT0) * 1000, label)
        }
        // Fail-loud boot validation, mirroring the web build's ItemData /
        // DifficultyData / TutorialData IIFEs running at script load.
        do {
            let data = try GameData.loadBundled()
            mark("data loaded + validated")
            // The Phase 1 smoke exercise (generate a seeded map + deal a board,
            // results discarded) predates the real UI. It rode the launch path
            // for every player boot; now it runs only when the harness asks
            // (`-bootSmoke 1`, used by `make verify-launch`).
            if UserDefaults.standard.bool(forKey: "bootSmoke") {
                let map = RunMap(data: data)
                map.setDifficultyTier("regular")
                let run = map.generateRun(seed: 12345, entryDecks: [13, 26, 39],
                                          opts: RunMap.GenOptions(genVersion: 3))
                let engine = GameEngine(deckSpecs: DeckManager.buildStandardDeck(), pileCount: 9, data: data)
                engine.start(seedOverride: 12345)
                engine.startRun()

                let receipt: [String: Any] = [
                    "ok": true,
                    "stickers": data.items.stickers.count,
                    "pillars": data.items.pillars.count,
                    "bases": data.items.bases.count,
                    "samePowers": data.items.samePowers.count,
                    "packs": data.items.packs.count,
                    "tiers": data.difficulty.tierIds,
                    "mapNodes": run.nodes.count,
                    "mapRows": run.totalRows,
                    "dealtPiles": engine.board.size,
                    "deckRemaining": engine.deck.remaining(),
                ]
                NSLog("[ShouldaSaidSame] GameCore booted: %@", String(describing: receipt))
                Self.writeBootReceipt(receipt)
                mark("boot smoke + receipt")
            }
        } catch {
            // Same contract as the web build: malformed data must not boot.
            NSLog("[ShouldaSaidSame] DATA VALIDATION FAILED:\n%@", String(describing: error))
            Self.writeBootReceipt(["ok": false, "error": String(describing: error)])
            fatalError("Bundled game data failed validation: \(error)")
        }

        // Pre-arm the audio session off-main so the first cue never hitches a frame.
        Sound.shared.warmUp()
        mark("audio warm-up dispatched")
        // COLORFUL CARDS (v6.96): the pref rides UserDefaults like sound's —
        // read it into the CRT flag before anything bakes a suit colour.
        CRT.loadColorfulCardsPref()

        let window = UIWindow(frame: UIScreen.main.bounds)
        // Phase 3: the campaign shell is the app. The Phase 2 debug launcher
        // stays reachable for the perf/screenshot harness via `-launcher 1`
        // (and every -autoDeal/-autoMap/-autoStore arg implies it).
        let d = UserDefaults.standard
        let wantsLauncher = d.bool(forKey: "launcher") || d.bool(forKey: "autoDeal")
            || d.bool(forKey: "autoMap") || d.bool(forKey: "autoStore")
        Telemetry.start()
        window.rootViewController = wantsLauncher ? LauncherViewController() : GameFlowController()
        mark("root controller built")
        window.makeKeyAndVisible()
        self.window = window
        mark("window visible (didFinishLaunching returns)")
        // The FIRST DRAWN FRAME lands after the first CA commit, not here —
        // stamp it one runloop turn + one frame later.
        DispatchQueue.main.async {
            CATransaction.setCompletionBlock { mark("first frame committed") }
        }
        return true
    }

    /// Phase 1 has no UI to inspect, so the launch writes what it did to
    /// `Documents/boot-receipt.json`. `make verify-launch` reads it back out of
    /// the simulator container — a launch that crashed leaves no receipt.
    private static func writeBootReceipt(_ receipt: [String: Any]) {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = try? JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys, .prettyPrinted])
        else { return }
        try? data.write(to: dir.appendingPathComponent("boot-receipt.json"))
    }
}
