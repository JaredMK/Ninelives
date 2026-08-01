import UIKit
import GameCore

/// End-to-end campaign verification: drives the WHOLE shell headlessly —
/// deck select → map travel → deals (odds-scripted) → stores → mysteries →
/// boss → home → endless — through the same public surfaces the player uses,
/// and writes `Documents/campaign-receipt.json` when it stops.
///
/// Enabled by `-autoCampaign <attempts>`; a lost climb starts the next attempt
/// until a win lands or attempts run out.
final class FlowAutopilot {

    private unowned let flow: GameFlowController
    private var timer: Timer?
    private var attempts: Int
    private var campaignsPlayed = 0
    private var dealsPlayed = 0
    private var storeVisits = 0
    private var mysteryKeys: [String] = []
    private var nodesVisited = 0
    private var won = false
    private var enteredEndless = false
    private var deepestPhase = 0
    private var startedAt = Date()
    private var stopped = false

    init(flow: GameFlowController, attempts: Int) {
        self.flow = flow
        self.attempts = attempts
        NSLog("[Autopilot] armed: attempts=%d", attempts)
        let t = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer = t
    }

    private var lastNote = ""
    private func note(_ s: String) {
        guard s != lastNote else { return }
        lastNote = s
        NSLog("[Autopilot] %@", s)
    }

    func noteMystery(_ key: String) { mysteryKeys.append(key) }
    func noteStore() { storeVisits += 1 }
    func noteDeal() { dealsPlayed += 1 }

    private func tick() {
        guard !stopped else { return }
        deepestPhase = max(deepestPhase, flow.campaign.phaseIndex)
        // Give any presented picker/reveal its auto-advance first.
        if let presented = flow.presentedViewController {
            note("presented: \(type(of: presented))")
            if let pack = presented as? PackRevealViewController {
                pack.autopilotAdvance()
                return
            }
            if let picker = presented as? CardPickerViewController {
                picker.autopilotAdvance()
                return
            }
            return
        }
        note("screen: \(flow.currentScreen.map { String(describing: type(of: $0)) } ?? "nil") phase=\(flow.campaign.phaseIndex) pos=\(String(describing: flow.campaign.nodePos))")
        // A phase overlay up → tap its primary button.
        if flow.tapOverlayPrimary() {
            if flow.overlayIsVictory {
                won = true
                if !enteredEndless {
                    // Take the endless branch ONCE to exercise it, then stop.
                    enteredEndless = true
                }
            }
            return
        }
        switch flow.currentScreen {
        case let menu as MainMenuViewController:
            _ = menu
            guard campaignsPlayed < attempts, !won else { finish(); return }
            campaignsPlayed += 1
            note("starting climb #\(campaignsPlayed)")
            let seed = UserDefaults.standard.object(forKey: "seed") != nil
                ? UInt32(truncatingIfNeeded: UserDefaults.standard.integer(forKey: "seed") + campaignsPlayed - 1)
                : nil
            flow.startCampaign(deckId: UserDefaults.standard.string(forKey: "deck") ?? "pink",
                               tier: UserDefaults.standard.string(forKey: "tier") ?? "regular",
                               seedU32: seed)
        case let map as MapViewController:
            // Endless exercised → head home and stop after the first endless map.
            if won && enteredEndless { finish(); return }
            let legal = flow.campaign.legalNextNodes()
            guard let target = legal.randomElement() else {
                // Home with nowhere to go is handled by showMap → victory.
                finish(); return
            }
            nodesVisited += 1
            map.travel(to: target.id)
        case is DealViewController:
            break   // the deal-side script drives itself
        case is StoreViewController:
            break   // storeDone fires from its own auto hook below
        default:
            break
        }
    }

    private func finish() {
        stopped = true
        timer?.invalidate()
        let receipt: [String: Any] = [
            "ok": true,
            "won": won,
            "enteredEndless": enteredEndless,
            "campaignsPlayed": campaignsPlayed,
            "dealsPlayed": dealsPlayed,
            "storeVisits": storeVisits,
            "mysteries": mysteryKeys,
            "nodesVisited": nodesVisited,
            "deepestPhase": deepestPhase,
            "deck": flow.campaign.deckId,
            "tier": flow.campaign.difficultyTier,
            "seedShare": flow.seedShareString(),
            "coins": flow.campaign.getCoins(),
            "deckSize": flow.campaign.deckSize(),
            "clearedNodes": flow.campaign.clearedNodes.count,
            "seconds": Int(Date().timeIntervalSince(startedAt)),
        ]
        NSLog("[Autopilot] finishing: won=%d campaigns=%d deals=%d stores=%d",
              won ? 1 : 0, campaignsPlayed, dealsPlayed, storeVisits)
        do {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let data = try JSONSerialization.data(withJSONObject: receipt,
                                                  options: [.sortedKeys, .prettyPrinted])
            try data.write(to: dir.appendingPathComponent("campaign-receipt.json"))
            NSLog("[Autopilot] receipt written to %@", dir.path)
        } catch {
            NSLog("[Autopilot] RECEIPT WRITE FAILED: %@", String(describing: error))
        }
    }
}

// MARK: - The hooks the autopilot drives through

extension GameFlowController {
    var currentScreen: UIViewController? { children.first }

    /// Fire the current phase overlay's FIRST button (Continue / New climb…).
    /// Returns true when an overlay was up.
    func tapOverlayPrimary() -> Bool {
        guard let o = currentOverlayView() else { return false }
        for case let b as PixelButtonView in o.allButtons() {
            b.onTap?()
            return true
        }
        return true
    }

    var overlayIsVictory: Bool { currentOverlayView()?.isVictory ?? false }
}

extension PhaseOverlayView {
    func allButtons() -> [UIView] {
        func walk(_ v: UIView) -> [UIView] {
            var out: [UIView] = []
            for s in v.subviews {
                if s is PixelButtonView { out.append(s) }
                out.append(contentsOf: walk(s))
            }
            return out
        }
        return walk(self)
    }
    var isVictory: Bool { victoryTag }
}

extension PackRevealViewController {
    /// Auto-advance: pick the first `keep` items, confirm (or Continue).
    func autopilotAdvance() { autopilotConfirm() }
}

extension CardPickerViewController {
    /// Auto-advance: tap the first eligible card, then confirm.
    func autopilotAdvance() { autopilotConfirm() }
}
