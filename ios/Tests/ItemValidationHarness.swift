import XCTest
@testable import GameCore

/// ITEM VALIDATION — TIER 1 harness (v6.50).
///
/// Force-constructs EXACT game states (board layout, pile contents, deck
/// order, equipped items, charges) rather than playing to reach them, fires
/// one step, and asserts:
///   • the item's claimed outcome (derived from its items.js knobs — the same
///     numbers its help text quotes),
///   • the FRAME: everything the item does NOT claim stays untouched,
///   • save/restore mid-effect: snapshot → twin → identical state.
///
/// Every item in the data file must map to scenarios (the driver fails loud
/// on an unmapped id), so a new item cannot ship unvalidated.
enum IV {

    // MARK: - State forcing

    static func spec(_ id: Int, _ rank: Int, _ suit: String = "♠",
                     _ stickers: [String] = [], joker: Bool = false) -> CardSpec {
        if joker { return .joker(id: id) }
        return CardSpec(id: id, suit: suit, originalRank: rank, currentRank: rank,
                        stickers: stickers.map { StickerRecord(type: $0) })
    }

    /// Build an engine over a FORCED layout. `tops` become single-card pile
    /// tops in order (nil = dead pile with one card); `deckOrder` is the draw
    /// deck, first card = next draw. 3 columns of 1 pile each by default.
    static func engine(tops: [CardSpec?], deckOrder: [CardSpec],
                       cols: [Int]? = nil,
                       pillars: [String?]? = nil, bases: [String?]? = nil,
                       samePower: String? = nil, samePowerVariant: String? = nil,
                       sameCharge: Bool = false,
                       pillarRankVariants: [String: Int] = [:],
                       isBoss: Bool = false, isAmbush: Bool = false,
                       seed: UInt32 = 7) -> GameEngine {
        let n = tops.count
        let layoutCols = cols ?? Array(repeating: 1, count: n)
        let all = tops.compactMap { $0 } + deckOrder
        let e = GameEngine(deckSpecs: all, pileCount: n,
                          runConfig: RunConfig(cols: layoutCols, sameCharge: sameCharge,
                                               samePower: samePower,
                                               samePowerVariant: samePowerVariant,
                                               pillarRankVariants: pillarRankVariants,
                                               isAmbush: isAmbush, isBoss: isBoss))
        e.start(seedOverride: seed)
        let colCount = layoutCols.count
        e.startRun(pillars: pillars ?? Array(repeating: nil, count: colCount),
                   bases: bases ?? Array(repeating: nil, count: colCount),
                   samePower: .some(samePower))
        let live = tops.map { $0.map { DeckManager.toCard($0, data: GameData.shared) } }
        for i in 0..<n {
            if let c = live[i] {
                e.board.piles[i].cards = [c]
                e.board.piles[i].dead = false
            } else {
                e.board.piles[i].cards = [DeckManager.toCard(spec(900 + i, 2), data: GameData.shared)]
                e.board.piles[i].dead = true
            }
            e.board.piles[i].sizeBonus = 0
        }
        e.deck.restoreSnapshot(cards: deckOrder.map { DeckManager.toCard($0, data: GameData.shared) },
                               drawn: n)
        return e
    }

    // MARK: - The frame (what must NOT change)

    struct Frame {
        var bonusCoins: Double
        var sameCharge: Bool
        var deckRemaining: Int
        var pileTopIds: [Int?]
        var pileCounts: [Int]
        var pileDead: [Bool]
        var basesUsed: [Bool]?
        var pillars: [String?]?
        var correctGuesses: Int
        var totalGuesses: Int

        init(_ e: GameEngine) {
            bonusCoins = e.run.bonusCoins
            sameCharge = e.sameCharge
            deckRemaining = e.deck.remaining()
            pileTopIds = (0..<e.board.size).map { e.board.top($0)?.id }
            pileCounts = (0..<e.board.size).map { e.board.piles[$0].cards.count }
            pileDead = (0..<e.board.size).map { e.board.piles[$0].dead }
            basesUsed = e.run.basesUsed
            pillars = e.run.pillars
            correctGuesses = e.run.correctGuesses
            totalGuesses = e.run.totalGuesses
        }
    }

    /// Fields a scenario DECLARES it may change; everything else is asserted
    /// frozen against the pre-fire frame.
    struct Allowed: OptionSet {
        let rawValue: Int
        static let coins = Allowed(rawValue: 1 << 0)       // bonusCoins moves
        static let charge = Allowed(rawValue: 1 << 1)      // sameCharge moves
        static let deck = Allowed(rawValue: 1 << 2)        // deck count moves
        static let board = Allowed(rawValue: 1 << 3)       // pile contents move
        static let deaths = Allowed(rawValue: 1 << 4)      // pile life state moves
        static let bases = Allowed(rawValue: 1 << 5)       // basesUsed moves
        static let pillars = Allowed(rawValue: 1 << 6)     // run.pillars moves
        static let guesses = Allowed(rawValue: 1 << 7)     // a guess was made
        static let all = Allowed(rawValue: ~0)
    }

    static func assertFrame(_ before: Frame, _ e: GameEngine, allowed: Allowed,
                            item: String, scenario: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        let ctx = "\(item)/\(scenario)"
        if !allowed.contains(.coins) {
            XCTAssertEqual(e.run.bonusCoins, before.bonusCoins,
                           "\(ctx): moved bonus coins it never claimed", file: file, line: line)
        }
        if !allowed.contains(.charge) {
            XCTAssertEqual(e.sameCharge, before.sameCharge,
                           "\(ctx): moved the Same Charge it never claimed", file: file, line: line)
        }
        if !allowed.contains(.deck) {
            XCTAssertEqual(e.deck.remaining(), before.deckRemaining,
                           "\(ctx): consumed/returned deck cards it never claimed", file: file, line: line)
        }
        if !allowed.contains(.board) {
            XCTAssertEqual((0..<e.board.size).map { e.board.top($0)?.id }, before.pileTopIds,
                           "\(ctx): moved pile tops it never claimed", file: file, line: line)
            XCTAssertEqual((0..<e.board.size).map { e.board.piles[$0].cards.count }, before.pileCounts,
                           "\(ctx): changed pile contents it never claimed", file: file, line: line)
        }
        if !allowed.contains(.deaths) {
            XCTAssertEqual((0..<e.board.size).map { e.board.piles[$0].dead }, before.pileDead,
                           "\(ctx): killed/revived piles it never claimed", file: file, line: line)
        }
        if !allowed.contains(.bases) {
            XCTAssertEqual(e.run.basesUsed, before.basesUsed,
                           "\(ctx): spent a Base it never claimed", file: file, line: line)
        }
        if !allowed.contains(.pillars) {
            XCTAssertEqual(e.run.pillars, before.pillars,
                           "\(ctx): destroyed a Pillar it never claimed", file: file, line: line)
        }
    }

    /// Mid-effect durability: snapshot the fired engine into a twin built the
    /// same way; the twin must agree on every observable.
    static func assertSnapshotRoundTrip(_ e: GameEngine, rebuild: () -> GameEngine,
                                        item: String, scenario: String,
                                        file: StaticString = #filePath, line: UInt = #line) {
        let ctx = "\(item)/\(scenario)"
        let twin = rebuild()
        guard twin.restoreSnapshot(e.snapshot()) else {
            return XCTFail("\(ctx): the mid-effect snapshot refused to restore", file: file, line: line)
        }
        XCTAssertEqual(twin.deck.snapshotCards().map(\.id), e.deck.snapshotCards().map(\.id),
                       "\(ctx): deck order diverged across save/restore", file: file, line: line)
        XCTAssertEqual((0..<twin.board.size).map { twin.board.top($0)?.id },
                       (0..<e.board.size).map { e.board.top($0)?.id },
                       "\(ctx): pile tops diverged across save/restore", file: file, line: line)
        XCTAssertEqual((0..<twin.board.size).map { twin.board.piles[$0].dead },
                       (0..<e.board.size).map { e.board.piles[$0].dead },
                       "\(ctx): pile deaths diverged", file: file, line: line)
        XCTAssertEqual(twin.run.bonusCoins, e.run.bonusCoins,
                       "\(ctx): bonus tally diverged", file: file, line: line)
        XCTAssertEqual(twin.sameCharge, e.sameCharge,
                       "\(ctx): Same Charge diverged", file: file, line: line)
        XCTAssertEqual(twin.rng.state, e.rng.state,
                       "\(ctx): rng position diverged", file: file, line: line)
        XCTAssertEqual(twin.run.basesUsed, e.run.basesUsed, "\(ctx): base charges diverged",
                       file: file, line: line)
    }

    // MARK: - Scenario

    struct Scenario {
        let name: String
        let allowed: Allowed
        let build: () -> GameEngine
        let fire: (GameEngine) -> Void
        let expect: (GameEngine, Frame, String) -> Void   // (engine, preFrame, ctx)
        /// Skip the snapshot round-trip (scenarios that end the deal — a
        /// finished engine has no mid-effect state to preserve).
        var skipSnapshot: Bool = false

        init(_ name: String, allowed: Allowed,
             build: @escaping () -> GameEngine,
             fire: @escaping (GameEngine) -> Void,
             expect: @escaping (GameEngine, Frame, String) -> Void,
             skipSnapshot: Bool = false) {
            self.name = name; self.allowed = allowed
            self.build = build; self.fire = fire; self.expect = expect
            self.skipSnapshot = skipSnapshot
        }
    }

    /// Run one scenario end to end with all automatic checks.
    static func run(_ s: Scenario, item: String,
                    file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let e = s.build()
        let before = Frame(e)
        s.fire(e)
        let ctx = "\(item)/\(s.name)"
        let failsBefore = currentFailureCount()
        s.expect(e, before, ctx)
        assertFrame(before, e, allowed: s.allowed, item: item, scenario: s.name,
                    file: file, line: line)
        if !s.skipSnapshot, e.status == "playing" {
            assertSnapshotRoundTrip(e, rebuild: s.build, item: item, scenario: s.name,
                                    file: file, line: line)
        }
        return currentFailureCount() == failsBefore
    }

    // Failure counting for the per-item table (XCTest lacks a public counter;
    // the driver tracks per-run deltas via this session-global).
    static var failureTally = 0
    static func currentFailureCount() -> Int { failureTally }
}

/// Tally hook: the driver subclass bumps IV.failureTally on each recorded
/// failure so `IV.run` can report pass/fail per scenario for the table.
class IVCase: XCTestCase {
    override func record(_ issue: XCTIssue) {
        IV.failureTally += 1
        super.record(issue)
    }
}
