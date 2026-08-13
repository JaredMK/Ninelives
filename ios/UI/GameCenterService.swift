import UIKit
import GameKit
import GameCore

/// The GameKit half of the leaderboards — everything Apple, nothing testable.
/// Policy (gating, queueing, IDs) lives in GameCore.Leaderboards; this class
/// only authenticates, ferries queued scores to GKLeaderboard, reads back the
/// local player's best, and presents Apple's own leaderboard sheet.
///
/// THE NO-GAME-CENTER PATH: a player who declines, is signed out, or is
/// offline sees exactly one system sign-in sheet (Apple's, at launch, only
/// when GameKit asks for it) and nothing else, ever. `isAuthenticated` stays
/// false, submissions sit in the durable queue, gameplay never gates on any
/// of this, and no error surfaces anywhere.
final class GameCenterService: NSObject, ScoreSubmitting {

    private(set) var isAuthenticated = false
    /// Fires on successful authentication — the flow flushes the queue then.
    var onAuthenticated: (() -> Void)?

    /// Authenticate silently at launch. GameKit may hand us a sign-in view
    /// controller exactly once — present it; a decline is remembered by the
    /// system, so there are no repeat nags from us.
    func authenticate(presenting host: UIViewController) {
        GKLocalPlayer.local.authenticateHandler = { [weak self, weak host] viewController, error in
            guard let self else { return }
            if let viewController, let host {
                host.present(viewController, animated: true)
                return
            }
            self.isAuthenticated = GKLocalPlayer.local.isAuthenticated && error == nil
            if self.isAuthenticated { self.onAuthenticated?() }
        }
    }

    // MARK: - ScoreSubmitting

    func submit(score: Int, leaderboardID: String, completion: @escaping (Bool) -> Void) {
        guard isAuthenticated else { completion(false); return }
        GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local,
                                  leaderboardIDs: [leaderboardID]) { error in
            completion(error == nil)
        }
    }

    // MARK: - Read-back + the Apple sheet

    /// The local player's (rank, best score) on one board — cheap, async,
    /// nil when unauthenticated or the board is unreachable.
    func loadLocalEntry(leaderboardID: String,
                        completion: @escaping ((rank: Int, score: Int)?) -> Void) {
        guard isAuthenticated else { completion(nil); return }
        GKLeaderboard.loadLeaderboards(IDs: [leaderboardID]) { boards, _ in
            guard let board = boards?.first else { completion(nil); return }
            board.loadEntries(for: [GKLocalPlayer.local], timeScope: .allTime) { local, _, _ in
                DispatchQueue.main.async {
                    completion(local.map { ($0.rank, Int($0.score)) })
                }
            }
        }
    }

    /// Apple's stock leaderboard sheet — deliberately NOT a custom screen.
    func presentLeaderboard(_ leaderboardID: String, from host: UIViewController) {
        let vc = GKGameCenterViewController(leaderboardID: leaderboardID,
                                            playerScope: .global, timeScope: .allTime)
        vc.gameCenterDelegate = self
        host.present(vc, animated: true)
    }
}

extension GameCenterService: GKGameCenterControllerDelegate {
    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }
}
