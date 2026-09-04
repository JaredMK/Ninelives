import XCTest
@testable import GameCore

/// PROBABILITY FEED (v6.57) — every item %-roll in the deal engine REPORTS its
/// outcome: a structured `.rollResult` event (hit AND miss) the UI renders as
/// a roll indicator, and a "rolled, missed" logbook line on a miss (a hit's
/// own ⚡ fire line already follows). A roll whose precondition fails (e.g.
/// Saboteur with nothing left to destroy) must NOT report — only real draws.
///
/// Rolls covered: Saboteur + Malfunction (curses), Static + Flypaper +
/// Second Wind (pillars), Gambler (scoring pillar, end-of-deal flip) and
/// Long Odds (linkPurge Same-Power).
final class ProbabilityFeedTests: XCTestCase {
    private let data = GameData.shared

    /// Attach the collector, run `action`, return the rolls it produced.
    private func rolls(_ e: GameEngine, during action: () -> Void) -> [RollResult] {
        var out: [RollResult] = []
        e.on { if case .rollResult(let r) = $0 { out.append(r) } }
        action()
        return out
    }
    private func logLines(_ e: GameEngine) -> [String] {
        e.run.log.flatMap { [$0.title] + $0.lines }
    }
    private func chanceOf(_ id: String, _ key: String = "chance", _ fallback: Double) -> Double {
        data.pillarTypes.get(id)?.num(key, fallback)
            ?? data.stickerTypes.get(id)?.num(key, fallback)
            ?? data.samePowerTypes.get(id)?.num(key, fallback)
            ?? fallback
    }

    // MARK: - Saboteur (cursed sticker, chance to destroy the column's Base/Pillar)

    /// Correct landing of a saboteur carrier in a column that HAS a Pillar and
    /// a Base; the roll is the first post-draw rng consumer on this path.
    private func saboteurEngine() -> GameEngine {
        IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                  deckOrder: [IV.spec(50, 9, "♥", ["saboteur"]), IV.spec(51, 3)],
                  pillars: ["columnGuardian", nil, nil], bases: ["shuffleColumn", nil, nil])
    }

    func testSaboteurHitAndMissBothReport() {
        let chance = chanceOf("saboteur", "chance", 0.1)
        var sawHit = false, sawMiss = false
        for s: UInt32 in 1...400 where !(sawHit && sawMiss) {
            let e = saboteurEngine()
            let rs = rolls(e) { e.rng.state = s; e.guess(0, .higher) }   // 9 on 5 → correct
            let destroyed = e.run.pillars?[0] == nil || e.run.bases?[0] == nil
            XCTAssertEqual(rs.count, 1, "exactly one roll this landing")
            XCTAssertEqual(rs.first?.id, "saboteur")
            XCTAssertEqual(rs.first?.klass, "sticker")
            XCTAssertEqual(rs.first?.chance ?? -1, chance, accuracy: 0.0001)
            XCTAssertEqual(rs.first?.index, 0); XCTAssertEqual(rs.first?.col, 0)
            XCTAssertEqual(rs.first?.hit, destroyed, "the report must match the outcome")
            if destroyed {
                sawHit = true
                XCTAssertTrue(logLines(e).contains { $0.contains("⚡") && $0.contains("destroyed") })
            } else {
                sawMiss = true
                XCTAssertTrue(logLines(e).contains {
                    $0.contains("Saboteur") && $0.contains("rolled, missed")
                }, "the miss must log — got:\n\(logLines(e).joined(separator: "\n"))")
            }
        }
        XCTAssertTrue(sawHit && sawMiss, "seed sweep must reach both outcomes")
    }

    /// No Pillar/Base left in the column → the roll never happens, nothing reports.
    func testSaboteurWithoutTargetsRollsNothing() {
        let e = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                          deckOrder: [IV.spec(50, 9, "♥", ["saboteur"]), IV.spec(51, 3)])
        let rs = rolls(e) { e.guess(0, .higher) }
        XCTAssertTrue(rs.isEmpty, "no targets → no roll → no report")
        XCTAssertFalse(logLines(e).contains { $0.contains("rolled, missed") })
    }

    // MARK: - Malfunction (cursed sticker, chance a correct guess kills anyway)

    private func malfunctionEngine() -> GameEngine {
        // v6.99: the curse rides the CARRIER (the drawn card).
        IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6), IV.spec(3, 6)],
                  deckOrder: [IV.spec(50, 9, "♥", ["malfunction"]), IV.spec(51, 3)])
    }

    func testMalfunctionHitAndMissBothReport() {
        var sawHit = false, sawMiss = false
        for s: UInt32 in 1...400 where !(sawHit && sawMiss) {
            let e = malfunctionEngine()
            let rs = rolls(e) { e.rng.state = s; e.guess(0, .higher) }   // 9 on 5 → correct
            let blew = !e.board.isActive(0)
            XCTAssertEqual(rs.count, 1)
            XCTAssertEqual(rs.first?.id, "malfunction")
            XCTAssertEqual(rs.first?.hit, blew)
            if blew {
                sawHit = true
                XCTAssertTrue(logLines(e).contains { $0.contains("Malfunction") && $0.contains("kill") })
            } else {
                sawMiss = true
                XCTAssertTrue(logLines(e).contains {
                    $0.contains("Malfunction") && $0.contains("rolled, missed") })
            }
        }
        XCTAssertTrue(sawHit && sawMiss, "seed sweep must reach both outcomes")
    }

    // MARK: - Static (pillar: ♠ landing rolls for a peek)

    private func staticEngine() -> GameEngine {
        IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                  deckOrder: [IV.spec(50, 9, "♠"), IV.spec(51, 3)],
                  pillars: ["static", nil, nil])
    }

    func testStaticHitAndMissBothReport() {
        var sawHit = false, sawMiss = false
        for s: UInt32 in 1...100 where !(sawHit && sawMiss) {
            let e = staticEngine()
            let rs = rolls(e) { e.rng.state = s; e.guess(0, .higher) }   // 9♠ on 5 → correct
            XCTAssertEqual(rs.count, 1)
            XCTAssertEqual(rs.first?.id, "static")
            XCTAssertEqual(rs.first?.klass, "pillar")
            XCTAssertEqual(rs.first?.hit, e.run.revealNextActive,
                           "the report must match the peek")
            if e.run.revealNextActive { sawHit = true } else {
                sawMiss = true
                XCTAssertTrue(logLines(e).contains {
                    $0.contains("Static") && $0.contains("rolled, missed") })
            }
        }
        XCTAssertTrue(sawHit && sawMiss, "a 50/50 must show both inside 100 states")
    }

    /// A NON-♠ correct landing in a Static column never rolls — no report.
    func testStaticSkipsTheRollOffSuit() {
        let e = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                          deckOrder: [IV.spec(50, 9, "♥"), IV.spec(51, 3)],
                          pillars: ["static", nil, nil])
        let rs = rolls(e) { e.guess(0, .higher) }
        XCTAssertTrue(rs.isEmpty, "no ♠ landing → no roll → no report")
    }

    // MARK: - Flypaper (pillar: small chance the landing picks up a sticker)

    func testFlypaperHitAndMissBothReport() {
        let chance = chanceOf("flypaper", "chance", 0.05)
        var sawHit = false, sawMiss = false
        for s: UInt32 in 1...600 where !(sawHit && sawMiss) {
            let e = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                              deckOrder: [IV.spec(50, 9, "♥"), IV.spec(51, 3)],
                              pillars: ["flypaper", nil, nil])
            let rs = rolls(e) { e.rng.state = s; e.guess(0, .higher) }
            XCTAssertEqual(rs.count, 1)
            XCTAssertEqual(rs.first?.id, "flypaper")
            XCTAssertEqual(rs.first?.chance ?? -1, chance, accuracy: 0.0001)
            let stuck = !(e.board.top(0)?.stickers.isEmpty ?? true)
            XCTAssertEqual(rs.first?.hit, stuck)
            if stuck { sawHit = true } else {
                sawMiss = true
                XCTAssertTrue(logLines(e).contains {
                    $0.contains("Flypaper") && $0.contains("rolled, missed") })
            }
        }
        XCTAssertTrue(sawHit && sawMiss, "the 5% roll must show both inside 600 states")
    }

    // MARK: - Second Wind (pillar: saveChance roll per dying pile)

    private func windEngine() -> GameEngine {
        IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                  deckOrder: [IV.spec(50, 9, "♥"), IV.spec(51, 3), IV.spec(52, 4),
                              IV.spec(53, 7), IV.spec(54, 8)],
                  pillars: ["secondWind", nil, nil])
    }

    func testSecondWindHitAndMissBothReport() {
        let chance = data.pillarTypes.get("secondWind")?.num("saveChance", 0.25) ?? 0.25
        var sawHit = false, sawMiss = false
        for s: UInt32 in 1...300 where !(sawHit && sawMiss) {
            let e = windEngine()
            var misses: [Int] = []
            e.on { if case .secondWindMiss(_, let col) = $0 { misses.append(col) } }
            let rs = rolls(e) { e.rng.state = s; e.guess(0, .lower) }   // 9 on 5, lower → wrong → the save roll runs
            XCTAssertEqual(rs.count, 1)
            XCTAssertEqual(rs.first?.id, "secondWind")
            XCTAssertEqual(rs.first?.chance ?? -1, chance, accuracy: 0.0001)
            XCTAssertEqual(rs.first?.hit, e.board.isActive(0))
            if e.board.isActive(0) {
                sawHit = true
            } else {
                sawMiss = true
                XCTAssertEqual(misses, [0], "the .secondWindMiss event still fires")
                XCTAssertTrue(logLines(e).contains {
                    $0.contains("Second Wind") && $0.contains("rolled, missed") })
            }
        }
        XCTAssertTrue(sawHit && sawMiss, "the 25% roll must show both inside 300 states")
    }

    // MARK: - Gambler (scoring pillar: the end-of-deal flip, rolled ONCE at Start Run)

    /// A Gambler engine built by hand so the roll listener attaches BEFORE
    /// startRun (IV.engine runs startRun internally).
    private func gamblerEngine(_ seed: UInt32, cols: [Int] = [1, 1, 1],
                               pillars: [String?] = ["gambler", nil, nil]) -> GameEngine {
        let e = GameEngine(deckSpecs: DeckManager.buildStandardDeck(), pileCount: cols.reduce(0, +),
                           runConfig: RunConfig(cols: cols))
        e.start(seedOverride: seed)
        e.startRun(pillars: pillars, bases: Array(repeating: nil, count: cols.count),
                   samePower: .some(nil))
        return e
    }

    /// The flip rolls ONCE per Gambler column AT START RUN (a fixed,
    /// replay-visible point), reports through rollChance, and memoizes on the
    /// run; the payout line reads the memo.
    func testGamblerFlipRollsOnceAtStartRun() {
        let def = data.pillarTypes.get("gambler")!
        var sawWin = false, sawLoss = false
        for s: UInt32 in 1...100 where !(sawWin && sawLoss) {
            let e = GameEngine(deckSpecs: DeckManager.buildStandardDeck(), pileCount: 3,
                               runConfig: RunConfig(cols: [1, 1, 1]))
            e.start(seedOverride: s)
            let rs = rolls(e) {
                e.startRun(pillars: ["gambler", nil, nil], bases: [nil, nil, nil], samePower: .some(nil))
            }
            XCTAssertEqual(rs.count, 1, "exactly one flip per Gambler column, at Start Run")
            XCTAssertEqual(rs.first?.id, "gambler")
            XCTAssertEqual(rs.first?.klass, "pillar")
            XCTAssertEqual(rs.first?.col, 0)
            XCTAssertEqual(rs.first?.chance ?? -1, def.num("chance", 0.5), accuracy: 0.0001)
            XCTAssertEqual(e.run.gamblerFlips?[0], rs.first?.hit, "the memo IS the roll")
            let line = e.computePillarPayout().lines.first { $0.effect == "gambler" }
            XCTAssertNotNil(line, "the flip always reports a line (no ♥ gate anymore)")
            XCTAssertEqual(line?.amount, rs.first?.hit == true ? def.value : 0,
                           "the payout reads the memo")
            if rs.first?.hit == true { sawWin = true } else {
                sawLoss = true
                XCTAssertTrue(logLines(e).contains {
                    $0.contains("Gambler") && $0.contains("rolled, missed") })
            }
        }
        XCTAssertTrue(sawWin && sawLoss, "the 50/50 flip must show both inside 100 seeds")
    }

    /// Every payout READ is pure: three reads (the HUD projection cadence)
    /// return the identical line and consume NO rng — a projection can never
    /// disagree with the deal end again.
    func testGamblerPayoutReadsNeverReroll() {
        let e = gamblerEngine(4242)
        let rngState = e.rng.state
        let first = e.computePillarPayout()
        let second = e.computePillarPayout()
        let third = e.computePillarPayout()
        let lineOf = { (pp: PillarPayout) in pp.lines.first { $0.effect == "gambler" } }
        XCTAssertEqual(lineOf(first)?.amount, lineOf(second)?.amount)
        XCTAssertEqual(lineOf(second)?.amount, lineOf(third)?.amount)
        XCTAssertEqual(lineOf(first)?.detail, lineOf(third)?.detail)
        XCTAssertEqual(first.bonus, third.bonus)
        XCTAssertEqual(e.rng.state, rngState, "a payout read must NOT consume the action-stream rng")
    }

    /// Two Gambler columns roll INDEPENDENTLY at Start Run (two memos, two
    /// reports), and both payout lines read their own memo.
    func testGamblerTwoColumnsFlipIndependently() {
        let e = GameEngine(deckSpecs: DeckManager.buildStandardDeck(), pileCount: 3,
                           runConfig: RunConfig(cols: [1, 1, 1]))
        e.start(seedOverride: 99)
        let rs = rolls(e) {
            e.startRun(pillars: ["gambler", "gambler", nil], bases: [nil, nil, nil],
                       samePower: .some(nil))
        }
        XCTAssertEqual(rs.count, 2, "one flip per Gambler column")
        XCTAssertEqual(rs.map(\.col), [0, 1])
        XCTAssertEqual(e.run.gamblerFlips?.count, 2)
        let lines = e.computePillarPayout().lines.filter { $0.effect == "gambler" }
        XCTAssertEqual(lines.count, 2)
        for line in lines {
            XCTAssertEqual(line.amount, e.run.gamblerFlips?[line.col ?? -1] == true
                           ? data.pillarTypes.get("gambler")!.value : 0)
        }
    }

    /// The memo round-trips the mid-deal snapshot: a restored deal pays what
    /// the parked deal projected — even when the memo differs from what the
    /// twin's own Start Run rolled (tamper-proven).
    func testGamblerMemoSurvivesSnapshotRoundTrip() {
        let a = gamblerEngine(777)
        let aRun = a.run!   // a class: sidesteps run's private(set) for the dict write
        let aFlip = aRun.gamblerFlips?[0] ?? false
        aRun.gamblerFlips?[0] = !aFlip   // tamper: force the memo OFF-seed
        let projected = a.computePillarPayout().lines.first { $0.effect == "gambler" }?.amount
        let b = gamblerEngine(777)        // same seed → its own Start Run rolls the PRE-tamper value
        XCTAssertNotEqual(b.run.gamblerFlips?[0], a.run.gamblerFlips?[0],
                          "setup: the tamper must differ from the twin's own roll")
        XCTAssertTrue(b.restoreSnapshot(a.snapshot()), "the mid-deal blob must restore")
        XCTAssertEqual(b.run.gamblerFlips?[0], a.run.gamblerFlips?[0],
                       "the memo rides the blob")
        let rngState = b.rng.state
        let restored = b.computePillarPayout().lines.first { $0.effect == "gambler" }?.amount
        XCTAssertEqual(restored, projected, "the restored deal pays the projected flip")
        XCTAssertEqual(b.rng.state, rngState, "…without re-rolling")
    }

    // MARK: - Long Odds (linkPurge Same-Power)

    func testLinkPurgeHitAndMissBothReport() {
        let chance = chanceOf("linkPurge", "chance", 0.25)
        var sawHit = false, sawMiss = false
        for s: UInt32 in 1...300 where !(sawHit && sawMiss) {
            let e = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                              deckOrder: [IV.spec(50, 9), IV.spec(51, 3), IV.spec(52, 4)],
                              samePower: "linkPurge")
            let before = e.deck.remaining()
            let rs = rolls(e) { e.rng.state = s; e.debugFireSamePower(0) }
            XCTAssertEqual(rs.count, 1)
            XCTAssertEqual(rs.first?.id, "linkPurge")
            XCTAssertEqual(rs.first?.klass, "samePower")
            XCTAssertEqual(rs.first?.chance ?? -1, chance, accuracy: 0.0001)
            XCTAssertEqual(rs.first?.hit, e.deck.remaining() == before - 1)
            if e.deck.remaining() == before - 1 { sawHit = true } else {
                sawMiss = true
                XCTAssertTrue(logLines(e).contains {
                    $0.contains("Long Odds") && $0.contains("rolled, missed") })
            }
        }
        XCTAssertTrue(sawHit && sawMiss, "the 25% roll must show both inside 300 states")
    }

    // MARK: - Ordering: the roll reports BEFORE the effect's own events

    func testRollResultPrecedesTheEffectEvents() {
        // Find a Static HIT state, then assert .rollResult lands before the
        // pillar's own .pillarFired pulse.
        var state: UInt32?
        for s: UInt32 in 1...100 {
            let e = staticEngine()
            e.rng.state = s
            e.guess(0, .higher)
            if e.run.revealNextActive { state = s; break }
        }
        guard let s = state else { return XCTFail("no static hit in 1...100") }
        let e = staticEngine()
        var order: [String] = []
        e.on { ev in
            if case .rollResult(let r) = ev { order.append("roll:\(r.id):\(r.hit)") }
            if case .pillarFired(_, let effect, _, _, _) = ev { order.append("fired:\(effect)") }
        }
        e.rng.state = s
        e.guess(0, .higher)
        XCTAssertEqual(order.first, "roll:static:true", "the roll reports first")
        XCTAssertTrue(order.contains("fired:static"), "the effect follows the roll")
    }
}
