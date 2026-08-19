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

    // MARK: - Diagnostics (v6.61)

    /// Every GameKit interaction, in order — auth outcomes, every submission
    /// attempt INCLUDING the silent no-ops, and the server board audit. Read
    /// in the debug panel's Game Center section; also mirrored to NSLog as
    /// "[GC]" lines for `log stream`/Console capture.
    private(set) static var diagLines: [String] = []
    static func diag(_ line: String) {
        diagLines.append(line)
        if diagLines.count > 300 { diagLines.removeFirst(diagLines.count - 300) }
        NSLog("[GC] %@", line)
    }

    /// One-line auth status for display surfaces.
    var statusLine: String {
        isAuthenticated ? "authenticated · \(GKLocalPlayer.local.alias)"
                        : "NOT authenticated (GKLocalPlayer.isAuthenticated=\(GKLocalPlayer.local.isAuthenticated))"
    }

    /// Authenticate silently at launch. GameKit may hand us a sign-in view
    /// controller exactly once — present it; a decline is remembered by the
    /// system, so there are no repeat nags from us.
    func authenticate(presenting host: UIViewController) {
        Self.diag("auth: starting · bundle \(Bundle.main.bundleIdentifier ?? "?")")
        GKLocalPlayer.local.authenticateHandler = { [weak self, weak host] viewController, error in
            guard let self else { return }
            if let viewController, let host {
                Self.diag("auth: GameKit presented its sign-in sheet (player not signed in yet)")
                host.present(viewController, animated: true)
                return
            }
            if let error { Self.diag("auth: error · \(error.localizedDescription)") }
            self.isAuthenticated = GKLocalPlayer.local.isAuthenticated && error == nil
            Self.diag("auth: \(self.isAuthenticated ? "OK" : "NOT authenticated")"
                      + " · GKLocalPlayer.isAuthenticated=\(GKLocalPlayer.local.isAuthenticated)"
                      + (self.isAuthenticated ? " · player \(GKLocalPlayer.local.alias)" : ""))
            if self.isAuthenticated {
                self.onAuthenticated?()
                // A successful sign-in is the moment the server becomes
                // reachable — run the board audit unprompted so the debug
                // panel always has a fresh answer.
                self.auditBoards()
            }
        }
    }

    /// THE SERVER PROBE: ask Apple which leaderboards exist for THIS app
    /// record. Read 1 (IDs: nil) returns every board attached to the record —
    /// that exposes identifier mismatches (boards created under other ids).
    /// Read 2 asks for the 8 ids the code can name, one verdict per id.
    func auditBoards() {
        guard isAuthenticated else {
            Self.diag("audit: SKIPPED — not authenticated, GameKit reads would fail")
            return
        }
        Self.diag("audit: reading ALL boards on this app record…")
        GKLeaderboard.loadLeaderboards(IDs: nil) { boards, error in
            DispatchQueue.main.async {
                if let error {
                    Self.diag("audit: ALL-boards read FAILED · \(error.localizedDescription)")
                } else if let boards, !boards.isEmpty {
                    Self.diag("audit: app record carries \(boards.count) board(s): "
                              + boards.map(\.baseLeaderboardID).sorted().joined(separator: ", "))
                } else {
                    Self.diag("audit: app record carries NO leaderboards (nothing attached in ASC)")
                }
            }
        }
        let want = LeaderboardID.allIdentifiers
        GKLeaderboard.loadLeaderboards(IDs: want) { boards, error in
            DispatchQueue.main.async {
                let got = Set((boards ?? []).map(\.baseLeaderboardID))
                for id in want { Self.diag("audit: \(id) → \(got.contains(id) ? "EXISTS" : "missing")") }
                if let error { Self.diag("audit: by-id read error · \(error.localizedDescription)") }
            }
        }
    }

    // MARK: - ScoreSubmitting

    func submit(score: Int, leaderboardID: String, completion: @escaping (Bool) -> Void) {
        guard isAuthenticated else {
            Self.diag("submit: SKIPPED (not authenticated) · \(leaderboardID) · score \(score)")
            completion(false); return
        }
        Self.diag("submit: sending \(score) → \(leaderboardID)")
        GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local,
                                  leaderboardIDs: [leaderboardID]) { error in
            if let error {
                Self.diag("submit: FAILED · \(leaderboardID) · \(error.localizedDescription)")
            } else {
                Self.diag("submit: CONFIRMED by server · \(leaderboardID) · score \(score)")
            }
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
