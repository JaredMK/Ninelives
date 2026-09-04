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

    // MARK: - v7.00 schema completeness

    func testDealStartCarriesConfigLoadoutAndArmsTheEnvelope() {
        let (c, batches) = core()
        c.flushThreshold = 100
        _ = c.beginRun(mode: "climb", deck: "pink", tier: "regular", seed: 7)
        c.recordDealStart(number: 1, stage: 2, cards: 15, piles: 4, rating: 2,
                          pillars: ["rankShield", nil, "envy"], bases: [nil, "chorus", nil],
                          samePower: "linkCoins")
        // An in-deal item fire joins the deal WITHOUT its own param.
        c.recordItemFire(klass: "pillar", id: "envy", label: "Envy", values: ["coins": 2])
        // A redeal re-boot of the SAME deal number is deduped.
        c.recordDealStart(number: 1, stage: 2, cards: 15, piles: 4, rating: 2,
                          pillars: [nil, nil, nil], bases: [nil, nil, nil], samePower: nil)
        c.recordDealEnd(won: true, number: 1, stage: 2, pilesAlive: 3, deckSize: 30,
                        cards: 15, piles: 4, rating: 2, nodeId: 9, nodeType: "deal")
        // …and after deal_end nothing is "in" a deal any more.
        c.record("store_visit", ["purse": "5"])
        c.flush()
        let s = batches()[0]
        XCTAssertEqual(s.map(\.name), ["deal_start", "item_fired", "deal_end", "store_visit"],
                       "one deal_start per deal number — the redeal re-boot deduped")
        let start = s[0].params
        XCTAssertEqual(start["stage"], "2")
        XCTAssertEqual(start["cards"], "15")
        XCTAssertEqual(start["piles"], "4")
        XCTAssertEqual(start["rating"], "2")
        XCTAssertEqual(start["deal_number"], "1", "the envelope stamps the live deal")
        XCTAssertEqual(start["pillars"], "rankShield,-,envy")
        XCTAssertEqual(start["bases"], "-,chorus,-")
        XCTAssertEqual(start["same_power"], "linkCoins")
        XCTAssertEqual(s[1].params["deal_number"], "1",
                       "item_fired joins deal_start with no param of its own")
        XCTAssertEqual(s[1].params["run_id"], start["run_id"], "…and shares the run id")
        let end = s[2].params
        XCTAssertEqual(end["cards"], "15"); XCTAssertEqual(end["piles"], "4")
        XCTAssertEqual(end["rating"], "2"); XCTAssertEqual(end["deal_number"], "1")
        XCTAssertEqual(end["piles_alive"], "3"); XCTAssertEqual(end["node_type"], "deal")
        XCTAssertNil(s[3].params["deal_number"], "between deals the envelope is clean")
    }

    func testRunEndCarriesTheFinalBuild() {
        let (c, batches) = core()
        c.flushThreshold = 100
        _ = c.beginRun(mode: "climb", deck: "pink", tier: "legendary", seed: 9)
        let comp = TelemetryCore.CompositionSummary(
            deckSize: 21, suits: ["♠": 6, "♥": 5, "♦": 4, "♣": 6],
            ranks: [2: 3, 14: 2], stickers: 4, curses: 1)
        c.recordRunEnd(outcome: "win", stageReached: 3, score: 240, dealsPlayed: 9,
                       seconds: 1200, pillars: ["envy", nil, nil],
                       bases: [nil, nil, "tax"], samePower: nil, composition: comp)
        c.flush()
        let p = batches()[0][0].params
        XCTAssertEqual(batches()[0][0].name, "run_end")
        XCTAssertEqual(p["outcome"], "win")
        XCTAssertEqual(p["pillars"], "envy,-,-")
        XCTAssertEqual(p["bases"], "-,-,tax")
        XCTAssertEqual(p["same_power"], "-")
        XCTAssertEqual(p["deck_size"], "21")
        XCTAssertEqual(p["suits"], "♠6|♥5|♦4|♣6")
        XCTAssertTrue(p["ranks"]!.hasPrefix("2:3|3:0|"), "the full 2–14 histogram renders")
        XCTAssertTrue(p["ranks"]!.hasSuffix("|14:2"))
        XCTAssertEqual(p["sticker_count"], "4")
        XCTAssertEqual(p["curse_count"], "1")
        XCTAssertEqual(p["tier"], "legendary", "the envelope still rides")
    }

    func testZenEndAndItemOffered() {
        let (c, batches) = core()
        c.flushThreshold = 100
        c.context.mode = "zen"
        c.context.deck = "pink"
        c.recordZenEnd(outcome: "loss", diff: "hard", seconds: 95)
        c.recordItemsOffered([(kind: "sticker", id: "tell", price: 3),
                              (kind: "pillar", id: "envy", price: 6)])
        c.flush()
        let s = batches()[0]
        XCTAssertEqual(s.map(\.name), ["zen_end", "item_offered", "item_offered"])
        XCTAssertEqual(s[0].params["outcome"], "loss")
        XCTAssertEqual(s[0].params["zen_diff"], "hard")
        XCTAssertEqual(s[0].params["seconds"], "95")
        XCTAssertEqual(s[0].params["game_mode"], "zen")
        XCTAssertEqual(s[1].params["item_id"], "tell")
        XCTAssertEqual(s[1].params["price"], "3")
        XCTAssertEqual(s[2].params["kind"], "pillar")
    }

    func testEndRunClearsTheDealStamp() {
        let (c, batches) = core()
        c.flushThreshold = 100
        _ = c.beginRun(mode: "climb", deck: "pink", tier: "regular", seed: 1)
        c.recordDealStart(number: 3, stage: 1, cards: 12, piles: 3, rating: 1,
                          pillars: [nil], bases: [nil], samePower: nil)
        c.endRun()
        c.record("mode_start", ["picked_mode": "zen"])
        c.flush()
        let last = batches()[0].last!
        XCTAssertNil(last.params["deal_number"], "endRun cleared the deal stamp")
        XCTAssertEqual(last.params["run_id"], "none")
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
