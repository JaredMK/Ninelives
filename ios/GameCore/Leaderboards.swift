import Foundation

/// GAME CENTER LEADERBOARDS — the platform-free half.
///
/// Everything testable lives HERE: the identifier scheme, the submission
/// gating (exhibition runs never submit; only enabled boards receive), and
/// the offline queue. The GameKit calls live behind `ScoreSubmitting`, whose
/// real implementation sits in the app layer (GameCenterService) — this file
/// never imports GameKit, so the whole policy runs under plain unit tests
/// with a mock.
public enum LeaderboardID {

    /// The board-token maps. FROZEN AT CREATION: leaderboard identifiers are
    /// immutable in App Store Connect, so these tokens deliberately do NOT
    /// track the player-facing labels (which have already been renamed once —
    /// "Normal" → "Jokers"). A future relabel changes nothing here.
    /// v6.67 roster: smith → garden, lammy → rocko, slyrex new. The old
    /// "sss.smith.*"/"sss.lammy.*" identifiers were never created in App
    /// Store Connect, so the renamed decks take FRESH tokens (no orphaned
    /// boards; pinky's live board is untouched).
    public static let deckTokens = ["pink": "pinky", "mamma": "mamma",
                                    "slyrex": "slyrex", "garden": "garden",
                                    "rocko": "rocko"]
    public static let tierTokens = ["regular": "jokers", "legendary": "straight"]

    /// "sss.<deck>.<tier>", e.g. "sss.pinky.straight". ONE board per
    /// deck+tier (v6.47): the score is one continuous run total — endless
    /// continues the climb — so the campaign/endless board split is gone.
    /// The old 4-segment ids ("sss.pinky.straight.campaign"/".endless") are
    /// ABANDONED, never reused: ASC identifiers are immutable, so the new
    /// scheme takes fresh 3-segment ids instead of repurposing a board whose
    /// name promises a different number.
    /// Nil for an unknown deck/tier — never a guessed identifier.
    public static func identifier(deck: String, tier: String) -> String? {
        guard let d = deckTokens[deck], let t = tierTokens[tier] else { return nil }
        return "sss.\(d).\(t)"
    }

    /// Every board the full scheme will ever name (4 decks × 2 tiers = 8) —
    /// the App Store Connect checklist iterates this.
    public static var allIdentifiers: [String] {
        deckTokens.keys.sorted().flatMap { d in
            tierTokens.keys.sorted().compactMap { t in identifier(deck: d, tier: t) }
        }
    }
}

/// The one seam GameKit hides behind. `isAuthenticated` false → every submit
/// no-ops into the queue; the app-layer implementation flips it after the
/// silent launch authentication.
public protocol ScoreSubmitting: AnyObject {
    var isAuthenticated: Bool { get }
    /// Deliver `score` to `leaderboardID`; call back true on confirmed receipt.
    func submit(score: Int, leaderboardID: String, completion: @escaping (Bool) -> Void)
}

/// Submission policy + the offline queue (`ninelives.gc.queue.v1`).
public final class Leaderboards {
    public static let queueKey = "ninelives.gc.queue.v1"

    /// The boards that are LIVE in App Store Connect. Scaling to the other
    /// combinations later is exactly one edit here (plus creating the boards
    /// in ASC) — no code changes anywhere else.
    public static let enabledBoards: Set<String> = [
        "sss.pinky.straight",
    ]

    private let store: KeyValueStore
    /// Nil submitter (no Game Center at all) still queues nothing and never
    /// errors — the game is fully playable without it.
    public weak var submitter: ScoreSubmitting?

    public init(store: KeyValueStore, submitter: ScoreSubmitting? = nil) {
        self.store = store
        self.submitter = submitter
    }

    // MARK: - Run-end reporting (the ONE entry point)

    /// Report the run's CONTINUOUS score. Applies every rule in one place:
    ///  • exhibition (seeded) runs NEVER submit,
    ///  • only enabled boards receive,
    ///  • the score is the run's OWN number — no recomputation.
    /// Called at the ♠-boss bank with the running total AND at the run's
    /// true end with the final one — Game Center keeps the highest, so the
    /// early submit only protects the record if endless never concludes
    /// (app deleted mid-endless, say); it can never lower it.
    /// Unsent scores queue durably and retry; a confirmed send dequeues, so
    /// nothing is lost and nothing sends twice.
    /// Diagnostic tap (v6.61): every policy decision — the skip reasons that
    /// used to be silent, enqueues, and flush deliveries — narrated as plain
    /// lines. The app layer points this at the Game Center diagnostics log;
    /// nil costs nothing and GameCore stays platform-free.
    public static var onEvent: ((String) -> Void)?

    public func reportRunEnd(deck: String, tier: String, exhibition: Bool, score: Int) {
        if exhibition {
            Self.onEvent?("report: SKIPPED (exhibition/seeded run) · \(deck).\(tier) · score \(score)")
            return
        }
        guard score > 0 else {
            Self.onEvent?("report: SKIPPED (score 0) · \(deck).\(tier)")
            return
        }
        guard let id = LeaderboardID.identifier(deck: deck, tier: tier) else {
            Self.onEvent?("report: SKIPPED (unknown deck/tier) · \(deck).\(tier)")
            return
        }
        guard Self.enabledBoards.contains(id) else {
            Self.onEvent?("report: SKIPPED (\(id) not in enabledBoards — board not marked live) · score \(score)")
            return
        }
        Self.onEvent?("report: queueing score \(score) → \(id)")
        enqueue(score: score, board: id)
        flush()
    }

    // MARK: - The queue

    public struct Pending: Equatable {
        public var token: String   // unique per enqueue — the dedupe key
        public var board: String
        public var score: Int
    }

    public func pending() -> [Pending] {
        guard let blob = JSONStore.read(store, Self.queueKey),
              let items = blob["items"]?.asArray else { return [] }
        return items.compactMap { v in
            guard let d = v.asObject, let t = d["token"]?.asString,
                  let b = d["board"]?.asString, let s = d["score"]?.asNumber else { return nil }
            return Pending(token: t, board: b, score: Int(s))
        }
    }

    private func write(_ items: [Pending]) {
        JSONStore.write(store, Self.queueKey, ["items": .array(items.map {
            .object(["token": .string($0.token), "board": .string($0.board),
                     "score": .number(Double($0.score))])
        })])
    }

    private func enqueue(score: Int, board: String) {
        var items = pending()
        items.append(Pending(token: UUID().uuidString, board: board, score: score))
        write(items)
    }

    /// Push everything queued through the submitter. Silent no-op when
    /// unauthenticated/offline — the queue simply waits for the next flush
    /// (launch, authentication, the next run end).
    public func flush() {
        guard let submitter else {
            if !pending().isEmpty { Self.onEvent?("flush: no submitter wired (Game Center absent) · \(pending().count) queued") }
            return
        }
        guard submitter.isAuthenticated else {
            let n = pending().count
            if n > 0 { Self.onEvent?("flush: waiting (not authenticated) · \(n) score(s) stay queued") }
            return
        }
        for item in pending() {
            Self.onEvent?("flush: delivering \(item.score) → \(item.board)")
            submitter.submit(score: item.score, leaderboardID: item.board) { [weak self] ok in
                Self.onEvent?(ok ? "flush: \(item.board) confirmed, dequeued"
                                 : "flush: \(item.board) NOT confirmed, stays queued for retry")
                guard ok, let self else { return }
                // Dequeue by TOKEN — a retry that raced a new enqueue can
                // never drop the newcomer.
                self.write(self.pending().filter { $0.token != item.token })
            }
        }
    }
}
