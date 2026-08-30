import XCTest
@testable import GameCore

/// v6.92 TELEMETRY CORE — the transport-agnostic half's contract:
/// queueing/batching, the live opt-out, the envelope's mode split, the
/// unfired-base derivation, and the frame-budget cost at 12 piles.
/// (The transport/lifecycle half is the app-target bridge — behind the
/// TELEMETRY flag, exercised by builds, not unit-testable from here.)
final class TelemetryTests: XCTestCase {

    /// A fresh, isolated core per test — the shared singleton stays out.
    private func core(sharing: Bool = true) -> (TelemetryCore, () -> [[TelemetryCore.Signal]]) {
        let c = TelemetryCore()
        var batches: [[TelemetryCore.Signal]] = []
        c.sharingEnabled = { sharing }
        c.transport = { batches.append($0) }
        return (c, { batches })
    }

    func testEventsQueueAndBatchAtTheThreshold() {
        let (c, batches) = core()
        c.flushThreshold = 5
        for i in 0..<4 { c.record("e\(i)") }
        XCTAssertEqual(c.pendingCount, 4, "under the threshold: queued, not sent")
        XCTAssertTrue(batches().isEmpty)
        c.record("e4")   // the fifth forces the flush
        XCTAssertEqual(c.pendingCount, 0)
        XCTAssertEqual(batches().count, 1)
        XCTAssertEqual(batches()[0].map(\.name), ["e0", "e1", "e2", "e3", "e4"])
        // A manual flush drains whatever is waiting (the background hook).
        c.record("tail")
        c.flush()
        XCTAssertEqual(batches().count, 2)
        XCTAssertEqual(batches()[1].map(\.name), ["tail"])
        c.flush()
        XCTAssertEqual(batches().count, 2, "an empty flush sends nothing")
    }

    func testTheToggleStopsSendsAtTheDoor() {
        var sharing = true
        let c = TelemetryCore()
        var sent = 0
        c.sharingEnabled = { sharing }
        c.transport = { sent += $0.count }
        c.flushThreshold = 2
        c.record("a"); c.record("b")
        XCTAssertEqual(sent, 2, "sharing on: the batch went out")
        sharing = false
        c.record("c"); c.record("d"); c.record("e")
        c.flush()
        XCTAssertEqual(sent, 2, "sharing off: nothing queues, nothing sends")
        XCTAssertEqual(c.pendingCount, 0, "…and nothing lingers to leak later")
        sharing = true
        c.record("f"); c.record("g")
        XCTAssertEqual(sent, 4, "back on: only NEW events flow")
    }

    func testTheEnvelopeDistinguishesClimbFromZen() {
        let (c, batches) = core()
        c.flushThreshold = 100
        // CLIMB: a run id + the full envelope.
        let runId = c.beginRun(mode: "climb", deck: "pink", tier: "regular", seed: 4242)
        c.record("mode_start", ["picked_mode": "climb"])
        // ZEN (after the climb ends): mode without a run id.
        c.endRun()
        c.context.mode = "zen"
        c.record("mode_start", ["picked_mode": "zen"])
        c.flush()
        let signals = batches()[0]
        XCTAssertEqual(signals[0].params["game_mode"], "climb")
        XCTAssertEqual(signals[0].params["run_id"], runId)
        XCTAssertEqual(signals[0].params["deck"], "pink")
        XCTAssertEqual(signals[0].params["tier"], "regular")
        XCTAssertEqual(signals[0].params["seed"], "4242")
        XCTAssertEqual(signals[1].params["game_mode"], "zen")
        XCTAssertEqual(signals[1].params["run_id"], "none",
                       "zen carries NO run id — the spec's menu/Zen-less rule")
    }

    func testUnfiredChargedBasesAreReported() {
        // A real engine: base charged in column 0, another column empty.
        let e = IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 8, "♥"), IV.spec(3, 6, "♣")],
                          deckOrder: [IV.spec(50, 9)], cols: [2, 1],
                          bases: ["shuffleColumn", nil])
        let (c, batches) = core()
        c.flushThreshold = 100
        c.recordUnfiredBases(bases: e.run.bases, used: e.run.basesUsed)
        c.flush()
        XCTAssertEqual(batches()[0].map(\.name), ["base_expired_uncharged"],
                       "a charged, unfired base at deal end reports — once")
        XCTAssertEqual(batches()[0][0].params["base_id"], "shuffleColumn")
        XCTAssertEqual(batches()[0][0].params["column"], "0")
        // Fire it — nothing to report any more.
        _ = e.baseActivate(col: 0)
        let (c2, batches2) = core()
        c2.recordUnfiredBases(bases: e.run.bases, used: e.run.basesUsed)
        c2.flush()
        XCTAssertTrue(batches2().isEmpty, "a FIRED base never reports")
    }

    func testConditionalOutcomeDerivesFromTheRecTForward() {
        let (c, batches) = core()
        c.flushThreshold = 100
        c.recordItemFire(klass: "sticker", id: "suitImmunity", label: "Guard", values: ["saves": 1])
        c.recordItemFire(klass: "sticker", id: "tell", label: "Tell", values: ["converted": 1])
        c.recordItemFire(klass: "base", id: "chorus", label: "Chorus", values: ["fires": 1])
        c.flush()
        let names = batches()[0].map(\.name)
        XCTAssertEqual(names, ["item_fired", "conditional_outcome",
                               "item_fired", "conditional_outcome",
                               "item_fired", "base_fired"])
        let outcomes = batches()[0].filter { $0.name == "conditional_outcome" }
        XCTAssertEqual(outcomes[0].params["outcome"], "fired")
        XCTAssertEqual(outcomes[1].params["outcome"], "converted")
    }

    /// THE PERF NUMBER (TMPERF1): a 12-pile deal's whole telemetry cost is
    /// enqueues off the recT stream. 1000 forwarded fires must stay far
    /// inside one 60Hz frame; sharing OFF must cost near-nothing.
    func testEnqueueCostHoldsTheFrameBudgetAt12Piles() {
        let (c, _) = core()
        c.flushThreshold = .max   // measure pure enqueue, no transport
        _ = c.beginRun(mode: "climb", deck: "pink", tier: "regular", seed: 1)
        for _ in 0..<50 {   // warm-up
            c.recordItemFire(klass: "sticker", id: "tell", label: "Tell", values: ["peeks": 1])
        }
        let reps = 1000
        let t0 = Date()
        for i in 0..<reps {
            c.recordItemFire(klass: "pillar", id: "heartBounty", label: "Heart Bounty",
                             values: ["coins": Double(i % 5)])
        }
        let onMs = Date().timeIntervalSince(t0) * 1000
        c.sharingEnabled = { false }
        let t1 = Date()
        for _ in 0..<reps {
            c.recordItemFire(klass: "pillar", id: "heartBounty", label: "Heart Bounty",
                             values: ["coins": 1])
        }
        let offMs = Date().timeIntervalSince(t1) * 1000
        print("TELEMETRY-PERF on=\(String(format: "%.2f", onMs))ms off=\(String(format: "%.2f", offMs))ms per \(reps) fires")
        XCTAssertLessThan(onMs, 16.0, "1000 enqueues must fit inside ONE 60Hz frame")
        XCTAssertLessThan(offMs, 4.0, "sharing OFF is a short-circuit")
    }
}
