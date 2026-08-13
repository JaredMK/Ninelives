import XCTest
@testable import GameCore

/// GAME CENTER POLICY — everything except GameKit itself: the identifier
/// scheme, the submission gating, and the offline queue, run against a mock
/// submitter (the GameKit half is isolated behind ScoreSubmitting).
///
/// v6.47: ONE board per deck+tier — the score is one continuous run total
/// (endless continues the climb), so the campaign/endless board split and its
/// 4-segment ids are gone. The new ids are 3-segment and fresh, never reusing
/// an abandoned board name.
final class LeaderboardTests: XCTestCase {

    /// A submitter the tests can script: offline, flaky, or counting.
    final class MockSubmitter: ScoreSubmitting {
        var isAuthenticated = true
        var accept = true
        var submissions: [(score: Int, board: String)] = []
        func submit(score: Int, leaderboardID: String, completion: @escaping (Bool) -> Void) {
            submissions.append((score, leaderboardID))
            completion(accept)
        }
    }

    // MARK: - The identifier scheme

    func testIdentifiersDeriveFromFrozenTokensNotLabels() {
        XCTAssertEqual(LeaderboardID.identifier(deck: "pink", tier: "legendary"),
                       "sss.pinky.straight")
        XCTAssertEqual(LeaderboardID.identifier(deck: "mamma", tier: "regular"),
                       "sss.mamma.jokers")
        XCTAssertNil(LeaderboardID.identifier(deck: "nope", tier: "regular"),
                     "an unknown deck must never produce a guessed board id")
        XCTAssertNil(LeaderboardID.identifier(deck: "pink", tier: "master"))
        // The full scheme: 4 decks × 2 tiers, all distinct, none carrying the
        // retired .campaign/.endless mode segment.
        let all = LeaderboardID.allIdentifiers
        XCTAssertEqual(all.count, 8)
        XCTAssertEqual(Set(all).count, 8)
        for id in all {
            XCTAssertTrue(id.hasPrefix("sss."), id)
            XCTAssertEqual(id.split(separator: ".").count, 3, "\(id): one board per deck+tier")
        }
    }

    // MARK: - Gating

    func testExhibitionRunsNeverSubmitOrQueue() {
        let mock = MockSubmitter()
        let lb = Leaderboards(store: MemoryStore(), submitter: mock)
        lb.reportRunEnd(deck: "pink", tier: "legendary", exhibition: true, score: 999)
        XCTAssertTrue(mock.submissions.isEmpty, "a seeded run reached Game Center")
        XCTAssertTrue(lb.pending().isEmpty, "…or the queue")
    }

    func testOnlyEnabledBoardsReceive() {
        let mock = MockSubmitter()
        let lb = Leaderboards(store: MemoryStore(), submitter: mock)
        // Pinky on JOKERS is a valid id but not an enabled board yet.
        lb.reportRunEnd(deck: "pink", tier: "regular", exhibition: false, score: 50)
        XCTAssertTrue(mock.submissions.isEmpty)
        // Pinky on STRAIGHT is live: the continuous total goes to ITS board.
        lb.reportRunEnd(deck: "pink", tier: "legendary", exhibition: false, score: 50)
        XCTAssertEqual(mock.submissions.count, 1)
        XCTAssertEqual(mock.submissions[0].board, "sss.pinky.straight")
        XCTAssertEqual(mock.submissions[0].score, 50)
    }

    func testBankThenDeathSubmitsTwiceGrowingSameBoard() {
        // The boss bank sends the running total; the endless death sends the
        // final one. Both go to the ONE board — Game Center keeps the best,
        // so the early send can only ever protect, never lower.
        let mock = MockSubmitter()
        let lb = Leaderboards(store: MemoryStore(), submitter: mock)
        lb.reportRunEnd(deck: "pink", tier: "legendary", exhibition: false, score: 120)
        lb.reportRunEnd(deck: "pink", tier: "legendary", exhibition: false, score: 185)
        XCTAssertEqual(mock.submissions.map(\.board),
                       ["sss.pinky.straight", "sss.pinky.straight"])
        XCTAssertEqual(mock.submissions.map(\.score), [120, 185])
        XCTAssertTrue(lb.pending().isEmpty)
    }

    // MARK: - The offline queue

    func testOfflineScoresQueueDurablyAndFlushOnceOnAuthentication() {
        let store = MemoryStore()
        let mock = MockSubmitter()
        mock.isAuthenticated = false            // offline / signed out
        let lb = Leaderboards(store: store, submitter: mock)
        lb.reportRunEnd(deck: "pink", tier: "legendary", exhibition: false, score: 77)
        XCTAssertTrue(mock.submissions.isEmpty, "nothing sends while signed out")
        XCTAssertEqual(lb.pending().count, 1, "…but the score is safely queued")
        // A relaunch (fresh policy object over the same store) keeps it.
        let lb2 = Leaderboards(store: store, submitter: mock)
        XCTAssertEqual(lb2.pending().count, 1, "the queue is durable")
        // Authentication arrives → one flush → one send → empty queue.
        mock.isAuthenticated = true
        lb2.flush()
        XCTAssertEqual(mock.submissions.count, 1)
        XCTAssertEqual(mock.submissions[0].score, 77)
        XCTAssertTrue(lb2.pending().isEmpty, "a confirmed send dequeues")
        // A second flush finds nothing — no double submission, ever.
        lb2.flush()
        XCTAssertEqual(mock.submissions.count, 1)
    }

    func testARejectedSubmissionStaysQueuedForRetry() {
        let store = MemoryStore()
        let mock = MockSubmitter()
        mock.accept = false                     // the network eats it
        let lb = Leaderboards(store: store, submitter: mock)
        lb.reportRunEnd(deck: "pink", tier: "legendary", exhibition: false, score: 12)
        XCTAssertEqual(mock.submissions.count, 1, "it tried")
        XCTAssertEqual(lb.pending().count, 1, "…and kept the score for later")
        mock.accept = true
        lb.flush()
        XCTAssertEqual(mock.submissions.count, 2)
        XCTAssertTrue(lb.pending().isEmpty)
    }

    func testNoSubmitterMeansSilenceNotErrors() {
        let lb = Leaderboards(store: MemoryStore(), submitter: nil)
        lb.reportRunEnd(deck: "pink", tier: "legendary", exhibition: false, score: 40)
        XCTAssertEqual(lb.pending().count, 1, "the score waits for a submitter to exist")
        lb.flush()   // must simply no-op
        XCTAssertEqual(lb.pending().count, 1)
    }

    // MARK: - The one-score stats migration (v6.47)

    func testOldSplitBestsFoldIntoOneKeepingTheHigher() {
        let store = MemoryStore()
        // A pre-v6.47 stats blob: separate climb and endless records, with
        // the endless one higher on one combo and lower on the other.
        JSONStore.write(store, Stats.key, [
            "bestCampaignScore": .number(140),
            "bestEndlessScore": .number(220),
            "deckTierBest": .object(["pink.regular": .number(140),
                                     "pink.legendary": .number(90)]),
            "deckTierBestEndless": .object(["pink.regular": .number(220),
                                            "pink.legendary": .number(40)]),
        ])
        let s = Stats(store: store).get()
        XCTAssertEqual(s.bestCampaignScore, 220, "the global best keeps the higher record")
        XCTAssertEqual(s.deckTierBest["pink.regular"], 220)
        XCTAssertEqual(s.deckTierBest["pink.legendary"], 90,
                       "a lower endless best never drags a combo's record down")
        // Round-trip: the re-encoded blob carries ONE best per combo and no
        // endless keys at all.
        let stats = Stats(store: store)
        stats.put(s)
        let blob = JSONStore.read(store, Stats.key)!
        XCTAssertNil(blob["deckTierBestEndless"])
        XCTAssertNil(blob["bestEndlessScore"])
        XCTAssertEqual(Int(blob["deckTierBest"]?["pink.regular"]?.asNumber ?? 0), 220)
    }
}
