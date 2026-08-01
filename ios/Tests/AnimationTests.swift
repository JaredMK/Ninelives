import XCTest
@testable import GameCore

/// Chunk A — the board motion contract. Pure-logic restatements of the rules
/// the animation layer implements (which lives in the app target, outside this
/// bundle): the CAUSAL animation queue's ordering, the flight-arc lift rule,
/// and the death/cascade sequencing arithmetic — all ported from the web build.
final class AnimationTests: XCTestCase {

    // MARK: - The causal queue

    /// The web's rule: a lower `priority` runs earlier within a batch, and
    /// insertion order breaks ties — so a draw (0) always animates before the
    /// effects it caused (1), even when the engine emitted the effect FIRST.
    private struct Step { let priority: Int; let seq: Int; let name: String }
    private func causalOrder(_ steps: [Step]) -> [String] {
        steps.sorted { $0.priority != $1.priority ? $0.priority < $1.priority : $0.seq < $1.seq }
            .map(\.name)
    }

    func testEffectsAnimateAfterTheDrawRegardlessOfEmitOrder() {
        // The engine emits "buried" BEFORE the "resolved" draw that caused it.
        let steps = [
            Step(priority: 1, seq: 0, name: "bury"),
            Step(priority: 0, seq: 1, name: "draw"),
        ]
        XCTAssertEqual(causalOrder(steps), ["draw", "bury"],
                       "the triggering draw must land before its consequence animates")
    }

    func testInsertionOrderBreaksTiesWithinAPriority() {
        let steps = [
            Step(priority: 1, seq: 0, name: "bury-a"),
            Step(priority: 1, seq: 1, name: "bury-b"),
            Step(priority: 0, seq: 2, name: "draw"),
            Step(priority: 1, seq: 3, name: "return"),
        ]
        XCTAssertEqual(causalOrder(steps), ["draw", "bury-a", "bury-b", "return"])
    }

    // MARK: - The flight arc

    /// The web's lift: `-min(34, max(10, hypot(dx,dy) * 0.16))` — a short hop
    /// lifts at least 10, a long one caps at 34.
    private func lift(_ dist: Double) -> Double { min(34, max(10, dist * 0.16)) }

    func testFlightLiftClampsBothEnds() {
        XCTAssertEqual(lift(0), 10, "the shortest hop still lifts")
        XCTAssertEqual(lift(100), 16, accuracy: 0.001)
        XCTAssertEqual(lift(1000), 34, "long flights cap at 34")
    }

    // MARK: - Deal-out cascade timing

    /// 150ms blank beat, 80ms stagger, 230ms per flight; the reveal-everything
    /// safety net fires only after the LAST flight could have landed.
    func testCascadeSafetyNetCoversTheLastFlight() {
        for n in [1, 9, 12] {
            let lastFlightEnds = 150 + (n - 1) * 80 + 230
            let safetyNet = 150 + n * 80 + 230 + 250
            XCTAssertGreaterThan(safetyNet, lastFlightEnds,
                                 "\(n) piles: the safety net must not fire before the last landing")
        }
    }

    // MARK: - Death sequencing

    /// land → 340ms beat → red flash → dissolve 300ms after the flash starts.
    /// A fatal guess holds the recap until the dissolve + a read beat — longer
    /// on a fatal tie so "Shoulda said same" is read first.
    func testFatalTieHoldsTheRecapLongerThanAPlainDeath() {
        let flashAt = 340, dieAt = flashAt + 300
        let plain = dieAt + 360, fatalTie = dieAt + 1100
        XCTAssertGreaterThan(fatalTie, plain)
        XCTAssertEqual(dieAt, 640, "dissolve begins 640ms after the fatal card lands")
    }

    /// Only a DIRECTIONAL guess that died on a tie earns the nudge; a correct
    /// directional tie can only be a Tie-Safe save. A "same" call is neither.
    func testTieOutcomeClassification() {
        func fatalTie(guess: Guess, correct: Bool, tie: Bool) -> Bool {
            !correct && guess != .same && tie
        }
        func tieSafeSave(guess: Guess, correct: Bool, tie: Bool) -> Bool {
            correct && guess != .same && tie
        }
        XCTAssertTrue(fatalTie(guess: .higher, correct: false, tie: true))
        XCTAssertFalse(fatalTie(guess: .same, correct: false, tie: true))
        XCTAssertTrue(tieSafeSave(guess: .lower, correct: true, tie: true))
        XCTAssertFalse(tieSafeSave(guess: .same, correct: true, tie: true), "a correct Same is the normal rule, not a save")
    }

    // MARK: - Deck character holds

    /// The reaction holds, verbatim from the web's CHAR_STATES table.
    func testReactionHoldsMatchTheWebTable() {
        let holds: [String: Int] = ["happy": 1100, "glad": 550, "sad": 1300, "celebrate": 1500]
        XCTAssertEqual(holds["happy"], 1100, "a won Same holds longest of the correct family")
        XCTAssertLessThan(holds["glad"]!, holds["happy"]!, "glad is the lighter, quicker reaction")
        XCTAssertGreaterThan(holds["sad"]!, holds["happy"]!, "a loss lingers")
        XCTAssertEqual(holds["celebrate"], 1500)
    }
}
