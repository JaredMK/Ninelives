import XCTest
@testable import GameCore

/// ENGINE TRACE TESTS — replays deterministic deals captured from the REAL web
/// GameEngine and asserts the Swift engine matches step for step.
///
/// This covers what unit tests can't reach cheaply: effect ORDER, the exact
/// number and sequence of rng draws inside a turn, and the full save-priority
/// chain (Guard → Second Wind → Same Charge → death). One wrong comparison or a
/// single misplaced `rng()` diverges a pile size or coin tally within a few
/// steps, and the failure message points at the exact step and field.
final class EngineTraceTests: XCTestCase {

    static let traces: [JSONValue] = {
        let bundle = Bundle(for: EngineTraceTests.self)
        guard let url = bundle.url(forResource: "engine-traces", withExtension: "json") else {
            fatalError("engine-traces.json is not in the test bundle — run `node ios/Tools/export-traces.mjs`")
        }
        let data = try! Data(contentsOf: url)
        let root = try! JSONDecoder().decode([String: JSONValue].self, from: data)
        return root["scenarios"]?.asArray ?? []
    }()

    /// The same scripted choice the exporter uses — pure arithmetic on the step
    /// index plus a read of the pile's visible top card.
    private func scriptedChoice(step: Int, alive: [Int], board: BoardState) -> (pile: Int, call: Guess) {
        let pile = alive[(step * 7 + 3) % alive.count]
        let v = board.top(pile)?.value ?? 8
        let call: Guess = step % 5 == 4 ? .same : (v <= 8 ? .higher : .lower)
        return (pile, call)
    }

    func testAllScenariosMatchWeb() {
        var scenariosChecked = 0, stepsChecked = 0
        for sc in Self.traces {
            let name = sc["name"]?.asString ?? "?"
            let seed = UInt32(truncatingIfNeeded: sc["seed"]?.int ?? 0)
            let piles = sc["piles"]?.int ?? 9
            let maxSteps = sc["steps"]?.int ?? 0
            let cols = sc["cols"]?.intArray
            let pillars = sc["pillars"]?.asArray?.map { $0.asString }
            let bases = sc["bases"]?.asArray?.map { $0.asString }
            let samePower = sc["samePower"]?.asString
            let noStickers = sc["noStickers"]?.asBool ?? false
            let sameCharge = sc["sameCharge"]?.asBool ?? false
            let baseAt = sc["baseAt"]?.int
            let baseTarget = sc["baseTarget"]?.int

            // Build the deck specs with this scenario's sticker plan.
            var specs = DeckManager.buildStandardDeck()
            for pair in sc["stickers"]?.asArray ?? [] {
                guard let cardId = pair[0]?.int, let typeId = pair[1]?.asString,
                      let i = specs.firstIndex(where: { $0.id == cardId }) else { continue }
                specs[i].stickers.append(StickerRecord(type: typeId))
            }

            let eng = GameEngine(deckSpecs: specs, pileCount: piles,
                                 runConfig: RunConfig(cols: cols?.isEmpty == false ? cols : nil,
                                                      sameCharge: sameCharge,
                                                      samePower: samePower,
                                                      noStickers: noStickers))
            eng.start(seedOverride: seed)
            // The per-deal Base randomizers roll during start(); check them
            // before startRun so a divergence is caught at its source.
            if let wantRandom = sc["baseRandom"], !wantRandom.isNull {
                XCTAssertEqual(eng.run.baseRandom?.value, wantRandom["value"]?.int, "\(name): baseRandom.value")
                XCTAssertEqual(eng.run.baseRandom?.suit, wantRandom["suit"]?.asString, "\(name): baseRandom.suit")
            }
            eng.startRun(pillars: pillars, bases: bases, samePower: .some(samePower))

            let stepList = sc["trace"]?.asArray ?? []

            var idx = 0
            assertSnapshot(eng, stepList[safe: idx], label: "\(name) step -1")
            idx += 1

            for step in 0..<maxSteps {
                if eng.status != "playing" { break }
                // Fire a Base on the scripted step, if one is armed and legal.
                if let baseAt, step == baseAt, let cols {
                    for c in 0..<cols.count where eng.baseAvailable(c) {
                        let def = eng.baseTypes.get(bases?[safe: c] ?? nil)
                        let pileTarget: Int?
                        if def?.target == "pile" {
                            pileTarget = (0..<eng.board.size).first {
                                !eng.board.piles[$0].dead && eng.run.pileColumns?[$0] == c
                            }
                        } else if def?.target == "pillar" {
                            pileTarget = baseTarget ?? 0
                        } else {
                            pileTarget = baseTarget
                        }
                        _ = eng.baseActivate(col: c, targetIndex: pileTarget)
                        break
                    }
                }
                let alive = (0..<eng.board.size).filter { !eng.board.piles[$0].dead }
                if alive.isEmpty { break }
                let choice = scriptedChoice(step: step, alive: alive, board: eng.board)
                eng.guess(choice.pile, choice.call)
                // Drain queued prompts deterministically (accept on even steps).
                var guardN = 0
                while guardN < 8 {
                    guardN += 1
                    if !eng.run.pendingTributes.isEmpty { eng.answerTribute(step % 2 == 0); continue }
                    if !eng.run.pendingActions.isEmpty { eng.answerAction(step % 2 == 0); continue }
                    break
                }
                guard let want = stepList[safe: idx] else {
                    XCTFail("\(name): Swift ran step \(step) but the web trace ended at \(stepList.count) steps")
                    break
                }
                XCTAssertEqual(choice.pile, want["pile"]?.int, "\(name) step \(step): chose a different pile")
                XCTAssertEqual(choice.call.rawValue, want["call"]?.asString, "\(name) step \(step): chose a different call")
                assertSnapshot(eng, want, label: "\(name) step \(step)")
                idx += 1
                stepsChecked += 1
            }
            XCTAssertEqual(idx, stepList.count, "\(name): recorded \(stepList.count) steps, Swift produced \(idx)")

            // Terminal state + the end-of-deal Pillar payout.
            if let final = sc["final"] {
                XCTAssertEqual(eng.status, final["status"]?.asString, "\(name): final status")
                XCTAssertEqual(eng.run.result, final["result"]?.asString, "\(name): final result")
                if let pp = final["pillarPayout"] {
                    let got = eng.pillarPayout()
                    XCTAssertEqual(got.bonus, pp["bonus"]?.asNumber ?? 0, "\(name): pillar payout bonus")
                    let wantLines = pp["lines"]?.asArray ?? []
                    XCTAssertEqual(got.lines.count, wantLines.count, "\(name): pillar payout line count")
                    for (i, wl) in wantLines.enumerated() where i < got.lines.count {
                        XCTAssertEqual(got.lines[i].label, wl["label"]?.asString, "\(name): payout line \(i) label")
                        XCTAssertEqual(got.lines[i].detail, wl["detail"]?.asString, "\(name): payout line \(i) detail")
                        XCTAssertEqual(got.lines[i].amount, wl["amount"]?.asNumber, "\(name): payout line \(i) amount")
                        XCTAssertEqual(got.lines[i].col, wl["col"]?.int, "\(name): payout line \(i) col")
                    }
                }
            }
            scenariosChecked += 1
        }
        XCTAssertGreaterThan(scenariosChecked, 100, "expected the full scenario sweep")
        XCTAssertGreaterThan(stepsChecked, 1500, "expected a deep step sweep")
    }

    /// Compare every observable field of one recorded step.
    private func assertSnapshot(_ eng: GameEngine, _ want: JSONValue?, label: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        guard let want else { XCTFail("\(label): no recorded snapshot", file: file, line: line); return }
        let board = eng.board!, deck = eng.deck!, run = eng.run!

        func eq<T: Equatable>(_ got: T, _ expected: T?, _ field: String) {
            XCTAssertEqual(got, expected, "\(label): \(field)", file: file, line: line)
        }
        /// Column-scoped run arrays are nil for column-agnostic runs and JSON
        /// `null` in the fixture; compare the two nullable shapes explicitly
        /// (a generic `eq` collapses `nil` and `.some(nil)` into each other).
        func eqNullable<T: Equatable>(_ got: [T]?, _ raw: JSONValue?, _ field: String,
                                      _ decode: (JSONValue) -> [T]) {
            let expected: [T]? = (raw == nil || raw!.isNull) ? nil : decode(raw!)
            switch (got, expected) {
            case (nil, nil): return
            case let (g?, e?): XCTAssertEqual(g, e, "\(label): \(field)", file: file, line: line)
            default:
                XCTFail("\(label): \(field) — swift \(String(describing: got)) vs web \(String(describing: expected))",
                        file: file, line: line)
            }
        }
        eq(eng.status, want["status"]?.asString, "status")
        eq(deck.remaining(), want["remaining"]?.int, "deck.remaining")
        eq(deck.drawn(), want["drawn"]?.int, "deck.drawn")
        eq(board.aliveCount(), want["alive"]?.int, "aliveCount")
        eq(board.piles.map(\.dead), want["dead"]?.asArray?.map { $0.asBool ?? false }, "dead flags")
        eq(board.piles.map { $0.cards.count }, want["sizes"]?.intArray, "pile sizes")
        eq((0..<board.size).map { board.pileSize($0) }, want["weighted"]?.intArray, "weighted sizes")
        eq(board.piles.map { p -> String? in
            guard let t = p.cards.last else { return nil }
            return t.joker ? "★" : t.label + t.suit
        }, want["tops"]?.asArray?.map { $0.asString }, "top cards")
        eq(board.piles.map { ($0.cards.last?.stickers ?? []).map(\.type) },
           want["topStickers"]?.asArray?.map { $0.stringArray }, "top stickers")
        eq(board.minAliveCards(), want["minAlive"]?.int, "minAliveCards")
        eq(board.trueMinAliveCards(), want["trueMinAlive"]?.int, "trueMinAliveCards")
        eq(board.extraCoinUnits(), want["extraCoinUnits"]?.int, "extraCoinUnits")
        eq(run.bonusCoins, want["bonusCoins"]?.asNumber, "bonusCoins")
        eq(run.bonusEvents.pairs.map { [$0.label, jsNum($0.amount)] },
           want["bonusEvents"]?.asArray?.map { [$0[0]?.asString ?? "", jsNum($0[1]?.asNumber ?? 0)] },
           "bonusEvents (ordered)")
        eq(eng.sameCharge, want["sameCharge"]?.asBool, "sameCharge")
        eq(run.correctGuesses, want["correct"]?.int, "correctGuesses")
        eq(run.totalGuesses, want["total"]?.int, "totalGuesses")
        eq(run.revealNextActive, want["revealNext"]?.asBool, "revealNextActive")
        eq(run.kamikazeRevealLeft, want["kamikazeReveal"]?.int, "kamikazeRevealLeft")
        eq(run.tellDrawsLeft, want["tellDrawsLeft"]?.int, "tellDrawsLeft")
        eq(run.tellPiles.sorted(), want["tellPiles"]?.intArray, "tellPiles")
        let bools: (JSONValue) -> [Bool] = { $0.asArray?.map { $0.asBool ?? false } ?? [] }
        let ints: (JSONValue) -> [Int] = { $0.intArray }
        eqNullable(run.colStreak, want["colStreak"], "colStreak", ints)
        eq(run.pendingTributes.count, want["pendingTributes"]?.int, "pendingTributes")
        eq(run.pendingActions.count, want["pendingActions"]?.int, "pendingActions")
        eqNullable(run.reviveUsed, want["reviveUsed"], "reviveUsed", bools)
        eqNullable(run.secondWindUsed, want["secondWindUsed"], "secondWindUsed", bools)
        eqNullable(run.basesUsed, want["basesUsed"], "basesUsed", bools)
        eqNullable(run.suitBountyHits, want["suitBountyHits"], "suitBountyHits", ints)
        eqNullable(run.denseBuryUsed, want["denseBuryUsed"], "denseBuryUsed", ints)
        eq(run.cardsDrawn, want["cardsDrawn"]?.int, "cardsDrawn")
        eq(run.compoundUpdates.sorted { $0.key < $1.key }.map { [$0.key, $0.value] },
           want["compoundUpdates"]?.asArray?.map { $0.intArray }, "compoundUpdates")
        eq(run.snowballUpdates.sorted { $0.key < $1.key }.map { [$0.key, $0.value] },
           want["snowballUpdates"]?.asArray?.map { $0.intArray }, "snowballUpdates")
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { i >= 0 && i < count ? self[i] : nil }
}
