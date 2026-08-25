import XCTest
@testable import GameCore

/// THE TRACE RUNNER — builds an engine from a scenario's INPUT keys and
/// drives the scripted deal. Shared by the replay test below (which compares
/// each step against the golden baseline) and by `GoldenRecorder` (which
/// captures each step INTO the baseline), so the two can never drift apart.
enum TraceRunner {

    /// The same scripted choice the original exporter used — pure arithmetic
    /// on the step index plus a read of the pile's visible top card. This is
    /// part of the baseline's identity: changing it re-scripts every trace.
    static func scriptedChoice(step: Int, alive: [Int], board: BoardState) -> (pile: Int, call: Guess) {
        let pile = alive[(step * 7 + 3) % alive.count]
        let v = board.top(pile)?.value ?? 8
        let call: Guess = step % 5 == 4 ? .same : (v <= 8 ? .higher : .lower)
        return (pile, call)
    }

    /// Build the engine from the scenario's inputs and play it out.
    /// `onSnapshot` fires once BEFORE the first step (pile/call nil — the
    /// as-dealt board) and once after every executed step.
    @discardableResult
    static func run(_ sc: JSONValue,
                    onSnapshot: (_ step: Int, _ pile: Int?, _ call: Guess?, _ eng: GameEngine) -> Void)
        -> GameEngine {
        let seed = UInt32(truncatingIfNeeded: sc["seed"]?.asInt ?? 0)
        let piles = sc["piles"]?.asInt ?? 9
        let maxSteps = sc["steps"]?.asInt ?? 0
        let cols = sc["cols"]?.intArray
        let pillars = sc["pillars"]?.asArray?.map { $0.asString }
        let bases = sc["bases"]?.asArray?.map { $0.asString }
        let samePower = sc["samePower"]?.asString
        let noStickers = sc["noStickers"]?.asBool ?? false
        let sameCharge = sc["sameCharge"]?.asBool ?? false
        let baseAt = sc["baseAt"]?.asInt
        let baseTarget = sc["baseTarget"]?.asInt

        // The deck specs with this scenario's sticker plan.
        var specs = DeckManager.buildStandardDeck()
        for pair in sc["stickers"]?.asArray ?? [] {
            guard let cardId = pair[0]?.asInt, let typeId = pair[1]?.asString,
                  let i = specs.firstIndex(where: { $0.id == cardId }) else { continue }
            specs[i].stickers.append(StickerRecord(type: typeId))
        }

        let eng = GameEngine(deckSpecs: specs, pileCount: piles,
                             runConfig: RunConfig(cols: cols?.isEmpty == false ? cols : nil,
                                                  sameCharge: sameCharge,
                                                  samePower: samePower,
                                                  noStickers: noStickers))
        eng.start(seedOverride: seed)
        eng.startRun(pillars: pillars, bases: bases, samePower: .some(samePower))

        onSnapshot(-1, nil, nil, eng)

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
            onSnapshot(step, choice.pile, choice.call, eng)
        }
        return eng
    }
}

/// EVERY observable field one recorded trace step carries. The recorder
/// writes exactly this dictionary; the replay recomputes it and demands
/// equality — one list, no drift.
enum TraceSnapshot {
    static func fields(_ eng: GameEngine) -> [String: JSONValue] {
        let board = eng.board!, deck = eng.deck!, run = eng.run!
        var out: [String: JSONValue] = [:]
        out["status"] = .string(eng.status)
        out["remaining"] = .num(deck.remaining())
        out["drawn"] = .num(deck.drawn())
        out["alive"] = .num(board.aliveCount())
        out["dead"] = .array(board.piles.map { .bool($0.dead) })
        out["sizes"] = .ints(board.piles.map { $0.cards.count })
        out["weighted"] = .ints((0..<board.size).map { board.pileSize($0) })
        out["tops"] = .array(board.piles.map { p -> JSONValue in
            guard let t = p.cards.last else { return .null }
            return .string(t.joker ? "★" : t.label + t.suit)
        })
        out["topStickers"] = .array(board.piles.map { .strings(($0.cards.last?.stickers ?? []).map(\.type)) })
        out["minAlive"] = .num(board.minAliveCards())
        out["trueMinAlive"] = .num(board.trueMinAliveCards())
        out["extraCoinUnits"] = .num(board.extraCoinUnits())
        out["bonusCoins"] = .num(run.bonusCoins)
        out["bonusEvents"] = .array(run.bonusEvents.pairs.map { .array([.string($0.label), .num($0.amount)]) })
        out["sameCharge"] = .bool(eng.sameCharge)
        out["correct"] = .num(run.correctGuesses)
        out["total"] = .num(run.totalGuesses)
        out["revealNext"] = .bool(run.revealNextActive)
        out["kamikazeReveal"] = .num(run.kamikazeRevealLeft)
        out["tellDrawsLeft"] = .num(run.tellDrawsLeft)
        out["tellPiles"] = .ints(run.tellPiles.sorted())
        out["colStreak"] = .maybeInts(run.colStreak)
        out["pendingTributes"] = .num(run.pendingTributes.count)
        out["pendingActions"] = .num(run.pendingActions.count)
        out["reviveUsed"] = .maybeBools(run.reviveUsed)
        out["secondWindUsed"] = .maybeBools(run.secondWindUsed)
        out["basesUsed"] = .maybeBools(run.basesUsed)
        out["suitBountyHits"] = .maybeInts(run.suitBountyHits)
        out["denseBuryUsed"] = .maybeInts(run.denseBuryUsed)
        out["cardsDrawn"] = .num(run.cardsDrawn)
        out["compoundUpdates"] = .array(run.compoundUpdates.sorted { $0.key < $1.key }
            .map { .ints([$0.key, $0.value]) })
        out["snowballUpdates"] = .array(run.snowballUpdates.sorted { $0.key < $1.key }
            .map { .ints([$0.key, $0.value]) })
        return out
    }

    /// The per-deal Base randomizer rolled during `start()`.
    static func baseRandom(_ eng: GameEngine) -> JSONValue {
        guard let br = eng.run.baseRandom else { return .null }
        return .object(["value": .num(br.value), "suit": .maybeString(br.suit)])
    }

    /// Terminal state + the end-of-deal Pillar payout.
    static func final(_ eng: GameEngine) -> JSONValue {
        let pp = eng.pillarPayout()
        return .object([
            "status": .string(eng.status),
            "result": .maybeString(eng.run.result),
            "pillarPayout": .object([
                "bonus": .num(pp.bonus),
                "lines": .array(pp.lines.map { l in
                    .object(["label": .string(l.label), "detail": .string(l.detail),
                             "amount": .num(l.amount), "col": .maybeNum(l.col)])
                }),
            ]),
        ])
    }
}

/// ENGINE TRACE TESTS — replays the deterministic deals recorded in the
/// GOLDEN BASELINE (captured from GameCore itself by `GoldenRecorder`; see
/// GoldenSupport.swift) and asserts the engine still matches step for step.
///
/// This covers what unit tests can't reach cheaply: effect ORDER, the exact
/// number and sequence of rng draws inside a turn, and the full save-priority
/// chain (Guard → Second Wind → Same Charge → death). One wrong comparison or
/// a single misplaced `rng()` diverges a pile size or coin tally within a few
/// steps, and the failure message points at the exact step and field.
final class EngineTraceTests: XCTestCase {

    static let traces: [JSONValue] = {
        let bundle = Bundle(for: EngineTraceTests.self)
        guard let url = bundle.url(forResource: "engine-traces", withExtension: "json") else {
            fatalError("engine-traces.json is not in the test bundle — run `make golden`")
        }
        let data = try! Data(contentsOf: url)
        let root = try! JSONDecoder().decode([String: JSONValue].self, from: data)
        return root["scenarios"]?.asArray ?? []
    }()

    func testAllScenariosMatchGolden() {
        var scenariosChecked = 0, stepsChecked = 0
        for sc in Self.traces {
            let name = sc["name"]?.asString ?? "?"
            let stepList = sc["trace"]?.asArray ?? []
            var idx = 0

            let eng = TraceRunner.run(sc) { step, pile, call, eng in
                guard let want = stepList[safe: idx] else {
                    XCTFail("\(name): engine ran step \(step) but the golden trace ended at \(stepList.count) steps")
                    idx += 1
                    return
                }
                let label = "\(name) step \(step)"
                if step >= 0 {
                    XCTAssertEqual(pile, want["pile"]?.asInt, "\(label): chose a different pile")
                    XCTAssertEqual(call?.rawValue, want["call"]?.asString, "\(label): chose a different call")
                    stepsChecked += 1
                }
                self.compareSnapshot(eng, want, label: label)
                idx += 1
            }
            XCTAssertEqual(idx, stepList.count,
                           "\(name): golden recorded \(stepList.count) steps, engine produced \(idx)")

            if let wantRandom = sc["baseRandom"] {
                XCTAssertEqual(TraceSnapshot.baseRandom(eng), wantRandom, "\(name): baseRandom")
            }
            if let final = sc["final"] {
                XCTAssertEqual(TraceSnapshot.final(eng), final, "\(name): final state + pillar payout")
            }
            scenariosChecked += 1
        }
        XCTAssertGreaterThan(scenariosChecked, 100, "expected the full scenario sweep")
        XCTAssertGreaterThan(stepsChecked, 1500, "expected a deep step sweep")
    }

    /// Compare the live snapshot against a recorded step, field by field, so
    /// a mismatch names the exact field instead of "objects differ".
    private func compareSnapshot(_ eng: GameEngine, _ want: JSONValue, label: String,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let got = TraceSnapshot.fields(eng)
        for (key, gotValue) in got.sorted(by: { $0.key < $1.key }) {
            let wantValue = want[key] ?? .null
            XCTAssertEqual(gotValue, wantValue, "\(label): \(key)", file: file, line: line)
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { i >= 0 && i < count ? self[i] : nil }
}
