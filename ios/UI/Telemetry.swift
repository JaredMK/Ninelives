import UIKit
import GameCore
#if TELEMETRY
import TelemetryDeck
#endif

/// THE TELEMETRY BRIDGE (v6.92) — the app-side half of the remote sink.
///
/// TelemetryCore (GameCore) owns the queue, the envelope, and the opt-out;
/// THIS file owns everything platform: the TelemetryDeck SDK, the session
/// lifecycle (start on launch/foreground, end + flush on background), the
/// TestFlight default, and the first-run milestone stamps. The whole layer
/// sits behind the TELEMETRY build flag — without it `start()` is a no-op,
/// no transport is ever injected, and TelemetryCore's sharing check stays
/// at its permanently-false default, so nothing even queues.
///
/// The schema is TELEMETRY.md at the repo root — extend the vocabulary
/// there first.
enum Telemetry {

    /// The player's switch (Settings → "SHARE ANONYMOUS GAMEPLAY DATA").
    /// Unset means the CHANNEL default: ON for TestFlight + DEBUG builds,
    /// OFF for the App Store. Reads UserDefaults directly (the SaveStore
    /// pref namespace) so it survives the campaign instance being rebuilt.
    static let prefKey = "ninelives.pref.telemetryShare"

    static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    static var sharingEnabled: Bool {
        switch UserDefaults.standard.string(forKey: prefKey) {
        case "1": return true
        case "0": return false
        default:
            #if DEBUG
            return true
            #else
            return isTestFlight
            #endif
        }
    }

    static func setSharing(_ on: Bool) {
        UserDefaults.standard.set(on ? "1" : "0", forKey: prefKey)
        if !on { TelemetryCore.shared.flush() }   // nothing new queues after this
    }

    // MARK: - Boot

    private static var sessionStart: Date?
    private static var runStart: Date?
    private(set) static var dealsThisRun = 0
    private static var lastPhaseSeen = 0

    /// Called once from didFinishLaunching. Everything hangs off this.
    static func start() {
        #if TELEMETRY
        TelemetryDeck.initialize(config: .init(appID: "8FC986B9-0F2C-44AA-8ED2-F95676B952FE"))
        let core = TelemetryCore.shared
        core.sharingEnabled = { sharingEnabled }
        core.transport = { batch in
            // The SDK owns its own retry queue and drops silently on
            // failure — exactly the contract the core wants from us.
            for s in batch {
                TelemetryDeck.signal(s.name, parameters: s.params.merging(
                    ["build": BuildStamp.version]) { a, _ in a })
            }
        }
        if UserDefaults.standard.object(forKey: "ninelives.tm.installedAt") == nil {
            UserDefaults.standard.set(Date().timeIntervalSince1970,
                                      forKey: "ninelives.tm.installedAt")
        }
        sessionBegan()
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                       object: nil, queue: .main) { _ in sessionEnded() }
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification,
                       object: nil, queue: .main) { _ in sessionBegan() }
        #endif
    }

    // MARK: - Session (per-session duration, distinct from run_end's)

    private static func sessionBegan() {
        guard sessionStart == nil else { return }
        sessionStart = Date()
        TelemetryCore.shared.record("session_start")
        TelemetryCore.shared.flush()
    }

    private static func sessionEnded() {
        guard let began = sessionStart else { return }
        sessionStart = nil
        TelemetryCore.shared.record("session_end",
            ["seconds": String(Int(Date().timeIntervalSince(began)))])
        TelemetryCore.shared.flush()
    }

    // MARK: - Mode + run lifecycle

    static func climbStarted(campaign: CampaignState, deck: String, tier: String, seed: UInt32) {
        let core = TelemetryCore.shared
        // Starting a new climb over a live one IS the abandon (quitting to
        // the menu is navigational — Continue resumes the run).
        if core.context.runId != nil { runEnded(campaign: campaign, outcome: "abandon") }
        _ = core.beginRun(mode: "climb", deck: deck, tier: tier, seed: seed)
        runStart = Date()
        dealsThisRun = 0
        lastPhaseSeen = 0
        core.record("mode_start", ["picked_mode": "climb"])
        core.record("run_start")
        deckSnapshot(campaign, stage: 0)
        if firstTime("climb"),
           let t = UserDefaults.standard.object(forKey: "ninelives.tm.installedAt") as? Double {
            core.record("milestone_time_to_first_climb",
                        ["seconds": String(Int(Date().timeIntervalSince1970 - t))])
        }
    }

    static func zenStarted(campaign: CampaignState, diff: String) {
        let core = TelemetryCore.shared
        core.context.mode = "zen"
        core.context.deck = campaign.deckId
        core.record("mode_start", ["picked_mode": "zen", "zen_diff": diff])
    }

    static func zenEnded() {
        let core = TelemetryCore.shared
        if core.context.runId == nil {   // never clobber a live climb envelope
            core.context.mode = nil
            core.context.deck = nil
        }
        core.flush()
    }

    static func enteredEndless(campaign: CampaignState) {
        // The climb was WON and closed at Pinky's; endless is its own run.
        let core = TelemetryCore.shared
        _ = core.beginRun(mode: "endless", deck: campaign.deckId,
                          tier: campaign.difficultyTier, seed: campaign.runSeed)
        runStart = Date()
        dealsThisRun = 0
        core.record("mode_start", ["picked_mode": "endless"])
        core.record("run_start")
    }

    static func runEnded(campaign: CampaignState, outcome: String) {
        let core = TelemetryCore.shared
        guard core.context.runId != nil else { return }
        var p: [String: String] = [
            "outcome": outcome,
            "stage_reached": String(campaign.phaseIndex + 1),
            "score": String(campaign.getRunScore()),
            "deals_played": String(dealsThisRun),
        ]
        if let began = runStart {
            p["seconds"] = String(Int(Date().timeIntervalSince(began)))
        }
        core.record("run_end", p)
        core.endRun()
        core.flush()
        runStart = nil
    }

    // MARK: - Deals + stages

    static func dealEnded(campaign: CampaignState, won: Bool, pilesAlive: Int,
                          stage: Int, nodeId: Int?, nodeType: String?) {
        dealsThisRun += 1
        var p: [String: String] = [
            "won": won ? "1" : "0",
            "deal_number": String(dealsThisRun),
            "stage": String(stage),
            "piles_alive": String(pilesAlive),
            "deck_size": String(campaign.deckSize()),
        ]
        if let nodeId { p["node_id"] = String(nodeId) }
        if let nodeType { p["node_type"] = nodeType }
        TelemetryCore.shared.record("deal_end", p)
        if !won, firstTime("death") {
            TelemetryCore.shared.record("milestone_first_death")
        }
        // Stage rollover → the composition snapshot.
        if campaign.phaseIndex != lastPhaseSeen {
            lastPhaseSeen = campaign.phaseIndex
            deckSnapshot(campaign, stage: campaign.phaseIndex)
        }
    }

    /// suit counts · rank histogram · size · sticker/curse counts.
    static func deckSnapshot(_ campaign: CampaignState, stage: Int) {
        let deck = campaign.getRunDeck().filter { !$0.joker && !$0.blank }
        var suits: [String: Int] = [:]
        var ranks: [Int: Int] = [:]
        var stickers = 0, curses = 0
        for c in deck {
            suits[c.suit, default: 0] += 1
            ranks[c.currentRank, default: 0] += 1
            for s in c.stickers {
                if GameData.shared.stickerTypes.get(s.type)?.cursed == true { curses += 1 }
                else { stickers += 1 }
            }
        }
        TelemetryCore.shared.record("deck_snapshot", [
            "stage": String(stage),
            "deck_size": String(campaign.deckSize()),
            "suits": ["♠", "♥", "♦", "♣"].map { "\($0)\(suits[$0] ?? 0)" }.joined(separator: "|"),
            "ranks": (2...14).map { "\($0):\(ranks[$0] ?? 0)" }.joined(separator: "|"),
            "sticker_count": String(stickers),
            "curse_count": String(curses),
        ])
    }

    static func loadout(_ campaign: CampaignState) {
        TelemetryCore.shared.record("loadout", [
            "pillars": campaign.columnPillars.map { $0 ?? "-" }.joined(separator: ","),
            "bases": campaign.columnBases.map { $0 ?? "-" }.joined(separator: ","),
            "same_power": campaign.getSamePower() ?? "-",
        ])
    }

    // MARK: - Milestones

    /// Once per install, stamped in UserDefaults.
    static func firstTime(_ key: String) -> Bool {
        let k = "ninelives.tm.first.\(key)"
        guard !UserDefaults.standard.bool(forKey: k) else { return false }
        UserDefaults.standard.set(true, forKey: k)
        return true
    }
}
