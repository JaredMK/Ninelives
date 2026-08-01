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
        // Fail-loud boot validation, mirroring the web build's ItemData /
        // DifficultyData / TutorialData IIFEs running at script load.
        do {
            let data = try GameData.loadBundled()
            // A smoke exercise of the engine at boot: generate a seeded map and
            // deal a board. Phase 1 renders nothing, so this is the only way a
            // launch proves GameCore actually runs on device.
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
        } catch {
            // Same contract as the web build: malformed data must not boot.
            NSLog("[ShouldaSaidSame] DATA VALIDATION FAILED:\n%@", String(describing: error))
            Self.writeBootReceipt(["ok": false, "error": String(describing: error)])
            fatalError("Bundled game data failed validation: \(error)")
        }

        // Pre-arm the audio session off-main so the first cue never hitches a frame.
        Sound.shared.warmUp()

        let window = UIWindow(frame: UIScreen.main.bounds)
        // Phase 3: the campaign shell is the app. The Phase 2 debug launcher
        // stays reachable for the perf/screenshot harness via `-launcher 1`
        // (and every -autoDeal/-autoMap/-autoStore arg implies it).
        let d = UserDefaults.standard
        let wantsLauncher = d.bool(forKey: "launcher") || d.bool(forKey: "autoDeal")
            || d.bool(forKey: "autoMap") || d.bool(forKey: "autoStore")
        window.rootViewController = wantsLauncher ? LauncherViewController() : GameFlowController()
        window.makeKeyAndVisible()
        self.window = window
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
