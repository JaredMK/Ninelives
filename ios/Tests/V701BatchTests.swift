import XCTest
@testable import GameCore

/// v7.01 BATCH — the event feed (item 12), the hybrid metas' campaign
/// branches (2, 3), and the most-held Queen rule change. (The in-deal legs,
/// Streak Coin, Empty Purse and Spade Peeker validate through the Tier-1
/// scenario suites.)
final class V701BatchTests: XCTestCase {
    let data = GameData.shared

    private func campaign() -> CampaignState {
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setSeedOverride(4242); c.reset()
        return c
    }

    // MARK: - Item 12: the event feed model

    func testFeedMessagesCoverEveryEffectFamily() {
        // One line per covered recT shape — the mapping IS the feature.
        let cases: [(klass: String, id: String, label: String,
                     values: [String: Double], expect: String)] = [
            ("pillar", "rankShield", "Rank Shield", ["saves": 1], "Pile saved by Rank Shield"),
            ("sticker", "tell", "Tell", ["converted": 1], "Tell became a curse"),
            ("pillar", "underdog", "Underdog", ["buried": 3], "Buried 3 by Underdog"),
            ("pillar", "envy", "Envy", ["coins": 2], "+2◉ from Envy"),
            ("base", "spadePeek", "Spade Peeker", ["peeks": 2], "Peek from Spade Peeker"),
            ("pillar", "mostHeldRankTell", "Most-Held Tell", ["tells": 1], "Tell from Most-Held Tell"),
            ("pillar", "flypaper", "Flypaper", ["applied": 1], "Sticker added by Flypaper"),
            ("sticker", "rechargeSameShield", "Recharge Shield", ["fires": 1],
             "Same Shield charged by Recharge Shield"),
            ("pillar", "stickerCurseWard", "Curse Ward", ["warded": 1],
             "Conversion blocked by Curse Ward"),
            ("pillar", "twoWard", "Bouncer", ["cleansed": 1], "Curse removed by Bouncer"),
            ("base", "cleanseColumn", "Cleanse", ["peeled": 2], "Curses removed by Cleanse"),
            ("samePower", "linkPurge", "Long Odds", ["purged": 1], "Card purged by Long Odds"),
            ("sticker", "malfunction", "Malfunction", ["kills": 1], "Pile destroyed by Malfunction"),
            ("pillar", "royalCourt", "Shuffler", ["shuffled": 2], "Shuffled by Shuffler"),
        ]
        for c in cases {
            XCTAssertEqual(EventFeed.message(klass: c.klass, id: c.id, label: c.label,
                                             values: c.values),
                           c.expect, "\(c.id): the feed line")
        }
        // A pure MISS (no payoff keys, no fires) is not feed-worthy.
        XCTAssertNil(EventFeed.message(klass: "pillar", id: "secondWind", label: "Second Wind",
                                       values: [:]),
                     "an empty impact dict yields no line")
    }

    func testFeedLogToggleScrollbackAndCoalescing() {
        let log = EventFeedLog()
        // DISABLED: nothing records at all — the debug toggle's contract.
        log.enabled = false
        log.post(klass: "pillar", id: "envy", label: "Envy", values: ["coins": 2])
        XCTAssertTrue(log.lines.isEmpty, "disabled — nothing recorded")
        XCTAssertTrue(log.drainPending().isEmpty)
        // ENABLED: lines record, pending drains once (the one-card-per-burst
        // coalescing source), the scrollback keeps everything.
        log.enabled = true
        log.post(klass: "pillar", id: "envy", label: "Envy", values: ["coins": 2])
        log.post(klass: "sticker", id: "tell", label: "Tell", values: ["converted": 1])
        let batch = log.drainPending()
        XCTAssertEqual(batch, ["+2◉ from Envy", "Tell became a curse"],
                       "one landing's burst drains as ONE batch")
        XCTAssertTrue(log.drainPending().isEmpty, "…and only once")
        XCTAssertEqual(log.lines.count, 2, "the scrollback holds the deal's events")
        // A non-feed-worthy entry records nothing.
        log.post(klass: "pillar", id: "x", label: "X", values: [:])
        XCTAssertEqual(log.lines.count, 2)
        // A new deal resets the scrollback.
        log.reset()
        XCTAssertTrue(log.lines.isEmpty)
    }

    func testFeedLogCapsItsScrollback() {
        let log = EventFeedLog()
        log.enabled = true
        for i in 0..<80 {
            log.post(klass: "pillar", id: "envy", label: "P\(i)", values: ["coins": 1])
        }
        XCTAssertEqual(log.lines.count, 60, "the scrollback caps at 60")
        XCTAssertEqual(log.lines.first, "+1◉ from P20", "…dropping the oldest")
    }

    // MARK: - Items 2 + 3: the hybrid metas' campaign branches

    func testQueenBranchUsesTheSharedMostHeldRule() {
        let c = campaign()
        XCTAssertFalse(c.queensAreStrictlyMostCommon(), "a fresh deck has no leader at Q")
        // Six extra Queens: the clear leader.
        for i in 0..<6 {
            c.baseDeck.append(CardSpec(id: 9400 + i, suit: "♥", originalRank: 12, currentRank: 12))
            c.ownedIds.append(9400 + i)
        }
        XCTAssertTrue(c.queensAreStrictlyMostCommon())
        // v7.01: a tie with a HIGHER rank still counts (ties → lowest, and
        // 12 < 13) — the old strictly-most-common rule said no here.
        let qCount = c.getRunDeck().filter { $0.currentRank == 12 }.count
        let kings = c.getRunDeck().filter { $0.currentRank == 13 }.count
        for i in 0..<max(0, qCount - kings) {
            c.baseDeck.append(CardSpec(id: 9500 + i, suit: "♣", originalRank: 13, currentRank: 13))
            c.ownedIds.append(9500 + i)
        }
        XCTAssertTrue(c.queensAreStrictlyMostCommon(),
                      "a King tie breaks to the LOWER rank — the Queens (v7.01)")
        // …but a tie with a LOWER rank still hands the title down.
        let fives = c.getRunDeck().filter { $0.currentRank == 5 }.count
        let qNow = c.getRunDeck().filter { $0.currentRank == 12 }.count
        for i in 0..<max(0, qNow - fives) {
            c.baseDeck.append(CardSpec(id: 9600 + i, suit: "♦", originalRank: 5, currentRank: 5))
            c.ownedIds.append(9600 + i)
        }
        XCTAssertFalse(c.queensAreStrictlyMostCommon(),
                       "a tie with the 5s belongs to the 5s")
    }

    func testBouncerCertaintyAndChanceReadLive() {
        let c = campaign()
        c.pillarInventory["twoWard", default: 0] += 1
        c.setColumnPillar(col: 0, typeId: "twoWard")
        XCTAssertEqual(data.pillarTypes.get("twoWard")?.num("chance", 0), 0.5,
                       "the ward chance moved to 50% (v7.01)")
        XCTAssertEqual(data.pillarTypes.get("queenFinder")?.num("chance", 0), 0.5,
                       "…and the finder's to 50%")
        // The 100% branch: purge every 2 → certainty at every node.
        _ = c.purgeRankFromDeck(2)
        XCTAssertTrue((0..<50).allSatisfy { c.twoWardNegates($0) },
                      "no 2s in the deck — the bounce is certain")
    }
}
