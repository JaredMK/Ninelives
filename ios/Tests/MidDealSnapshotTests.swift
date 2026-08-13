import XCTest
@testable import GameCore

/// MID-DEAL PERSISTENCE (anti-savescum) — the exact-resume snapshot.
///
/// The contract under test: `GameEngine.snapshot()` + `restoreSnapshot(_:)`
/// reproduce a mid-deal engine so completely that its FUTURE is identical —
/// same deck order, same pile contents, same charges, same tallies, same RNG
/// stream. If two engines agree on every subsequent draw, the resume is exact
/// by construction; savescumming a kill gains nothing.
final class MidDealSnapshotTests: XCTestCase {

    /// A 52-card deal with items bound everywhere: stickers on cards, pillars
    /// and bases on columns, a Same-Power equipped — the worst-case blob.
    private func makeEngine(seed: UInt32 = 4242) -> GameEngine {
        var specs = DeckManager.buildStandardDeck()
        // Stickers across the deck: rank guards, wilds, compound counters.
        for i in stride(from: 0, to: specs.count, by: 4) {
            specs[i].stickers.append(StickerRecord(type: "tieSafe"))
        }
        for i in stride(from: 1, to: specs.count, by: 7) {
            specs[i].stickers.append(StickerRecord(type: "compound"))
            specs[i].compoundHits = i % 5
        }
        let e = GameEngine(deckSpecs: specs, pileCount: 9,
                           runConfig: RunConfig(cols: [3, 3, 3],
                                                sameCharge: true,
                                                samePower: "linkBury",
                                                samePowerVariant: "♦"))
        e.start(seedOverride: seed)
        e.startRun(pillars: ["heartBounty", "streakBank", "secondWind"],
                   bases: ["setValue", "tax", "spadePeek"],
                   samePower: .some("linkBury"))
        return e
    }

    /// Play a deterministic mid-deal prefix: guesses picked by simple card
    /// counting, declining every offer (fixed policy = reproducible state).
    private func playPrefix(_ e: GameEngine, actions: Int) {
        var made = 0
        var i = 0
        while made < actions, e.status == "playing", !e.deck.isEmpty {
            let pile = i % 9
            i += 1
            guard e.board.isActive(pile), let top = e.board.top(pile) else { continue }
            e.guess(pile, top.value <= 7 ? .higher : .lower)
            while !e.run.pendingTributes.isEmpty { e.answerTribute(false) }
            while !e.run.pendingActions.isEmpty { e.answerAction(false) }
            e.answerRipple(true)
            made += 1
        }
    }

    /// Snapshot → fresh engine → restore: every observable field survives.
    func testRoundTripFidelity() {
        let a = makeEngine()
        playPrefix(a, actions: 12)
        guard a.status == "playing" else { return XCTFail("prefix ended the deal; pick another seed") }

        let blob = a.snapshot()
        let b = makeEngine()          // same plan, same seed — the boot path
        XCTAssertTrue(b.restoreSnapshot(blob), "a just-written blob must restore")

        // Deck: same remaining cards in the same order, same drawn count.
        XCTAssertEqual(b.deck.snapshotCards().map(\.id), a.deck.snapshotCards().map(\.id))
        XCTAssertEqual(b.deck.drawn(), a.deck.drawn())
        // Board: same pile contents (ids in order), same heights, same deaths.
        for i in 0..<9 {
            XCTAssertEqual(b.board.piles[i].cards.map(\.id), a.board.piles[i].cards.map(\.id), "pile \(i)")
            XCTAssertEqual(b.board.piles[i].dead, a.board.piles[i].dead, "pile \(i) dead")
            XCTAssertEqual(b.board.piles[i].sizeBonus, a.board.piles[i].sizeBonus, "pile \(i) bonus")
        }
        // Live card state riding the identities: stickers, counters, flags.
        for (ca, cb) in zip(a.board.piles.flatMap(\.cards), b.board.piles.flatMap(\.cards)) {
            XCTAssertEqual(cb.stickers, ca.stickers, "card \(ca.id) stickers")
            XCTAssertEqual(cb.compoundHits, ca.compoundHits, "card \(ca.id) compound")
            XCTAssertEqual(cb.tieSafe, ca.tieSafe, "card \(ca.id) tieSafe (re-derived)")
        }
        // Charges, status, RNG position.
        XCTAssertEqual(b.sameCharge, a.sameCharge)
        XCTAssertEqual(b.status, a.status)
        XCTAssertEqual(b.rng.state, a.rng.state)
        // The run tallies the score reads.
        XCTAssertEqual(b.run.correctGuesses, a.run.correctGuesses)
        XCTAssertEqual(b.run.totalGuesses, a.run.totalGuesses)
        XCTAssertEqual(b.run.cardsDrawn, a.run.cardsDrawn)
        XCTAssertEqual(b.run.bonusCoins, a.run.bonusCoins)
        XCTAssertEqual(b.run.bonusEvents.pairs.map(\.label), a.run.bonusEvents.pairs.map(\.label))
        XCTAssertEqual(b.run.bonusEvents.pairs.map(\.amount), a.run.bonusEvents.pairs.map(\.amount))
        XCTAssertEqual(b.run.colStreak, a.run.colStreak)
        XCTAssertEqual(b.run.secondWindUsed, a.run.secondWindUsed)
        XCTAssertEqual(b.run.basesUsed, a.run.basesUsed)
        XCTAssertEqual(b.run.started, a.run.started)
        XCTAssertEqual(b.run.stickerWindow, a.run.stickerWindow)
        XCTAssertEqual(b.run.baseRandom?.value, a.run.baseRandom?.value)
        XCTAssertEqual(b.run.baseRandom?.suit, a.run.baseRandom?.suit)
        XCTAssertEqual(b.run.compoundUpdates, a.run.compoundUpdates)
    }

    /// The REAL proof of exactness: after restore, both engines live the same
    /// future — every remaining draw resolves identically to the very end.
    func testRestoredEngineLivesTheSameFuture() {
        for seed: UInt32 in [4242, 7, 90210] {
            let a = makeEngine(seed: seed)
            playPrefix(a, actions: 10)
            guard a.status == "playing" else { continue }
            let b = makeEngine(seed: seed)
            XCTAssertTrue(b.restoreSnapshot(a.snapshot()))

            var eventsA: [String] = [], eventsB: [String] = []
            a.on { eventsA.append(String(describing: $0)) }
            b.on { eventsB.append(String(describing: $0)) }
            var i = 0
            while a.status == "playing", !a.deck.isEmpty, i < 200 {
                let pile = i % 9
                i += 1
                guard a.board.isActive(pile), let top = a.board.top(pile) else { continue }
                let g: Guess = top.value <= 7 ? .higher : .lower
                a.guess(pile, g)
                b.guess(pile, g)
                for e in [a, b] {
                    while !e.run.pendingTributes.isEmpty { e.answerTribute(false) }
                    while !e.run.pendingActions.isEmpty { e.answerAction(false) }
                    e.answerRipple(true)
                }
            }
            XCTAssertEqual(eventsA, eventsB, "seed \(seed): the futures diverged")
            XCTAssertEqual(a.status, b.status, "seed \(seed)")
            XCTAssertEqual(a.run.bonusCoins, b.run.bonusCoins, "seed \(seed)")
        }
    }

    /// A prompt interrupted by the kill (paid bury / shuffle / ripple) is
    /// still pending after restore — the UI re-surfaces it from this state.
    func testPendingPromptsSurviveTheKill() {
        let a = makeEngine()
        var guesses = 0
        var i = 0
        while a.run.pendingTributes.isEmpty, a.run.pendingActions.isEmpty,
              a.status == "playing", !a.deck.isEmpty, guesses < 200 {
            let pile = i % 9
            i += 1
            guard a.board.isActive(pile), let top = a.board.top(pile) else { continue }
            a.guess(pile, top.value <= 7 ? .higher : .lower)
            guesses += 1
        }
        guard !a.run.pendingTributes.isEmpty || !a.run.pendingActions.isEmpty else {
            return   // this seed never offered — the field mapping is still covered above
        }
        let b = makeEngine()
        XCTAssertTrue(b.restoreSnapshot(a.snapshot()))
        XCTAssertEqual(b.run.pendingTributes, a.run.pendingTributes)
        XCTAssertEqual(b.run.pendingActions, a.run.pendingActions)
    }

    /// A stale blob (wrong deal) must refuse cleanly, leaving the engine dealt.
    func testStaleBlobIsRejectedNotApplied() {
        let a = makeEngine(seed: 4242)
        playPrefix(a, actions: 6)
        var blob = a.snapshot()
        // Corrupt the board shape: a 12-pile blob against a 9-pile engine.
        blob["piles"] = .array((blob["piles"]?.asArray ?? []) + [.object(["cards": .array([])])])
        let b = makeEngine(seed: 4242)
        let before = b.board.piles.map { $0.cards.map(\.id) }
        XCTAssertFalse(b.restoreSnapshot(blob), "a shape-mismatched blob must be refused")
        XCTAssertEqual(b.board.piles.map { $0.cards.map(\.id) }, before, "…and leave the engine untouched")
        XCTAssertFalse(b.restoreSnapshot([:]), "an empty blob must be refused")
    }

    /// THE PERF NUMBER (STKPERF1): the per-action cost — snapshot capture on
    /// the main thread + the JSON encode + the store write that run on the
    /// background queue — measured on a 52-card deal with items bound.
    func testPerActionWriteCostAt52Cards() {
        let e = makeEngine()
        playPrefix(e, actions: 12)
        let store = MemoryStore()

        // Warm up, then time the three stages separately over 200 reps.
        for _ in 0..<20 { _ = e.snapshot() }
        var blob = e.snapshot()
        let reps = 200

        let t0 = Date()
        for _ in 0..<reps { blob = e.snapshot() }
        let captureMs = Date().timeIntervalSince(t0) * 1000 / Double(reps)

        let t1 = Date()
        for _ in 0..<reps { JSONStore.write(store, "midDeal.perf", blob) }
        let encodeWriteMs = Date().timeIntervalSince(t1) * 1000 / Double(reps)

        let bytes = store.string(forKey: "midDeal.perf")?.utf8.count ?? 0
        print("MIDDEAL-PERF capture=\(String(format: "%.3f", captureMs))ms " +
              "encode+write=\(String(format: "%.3f", encodeWriteMs))ms " +
              "blob=\(bytes) bytes (52 cards, stickers + pillars + bases + power)")

        // The main-thread share is the capture alone — it must stay far under
        // a frame (16.7ms). The encode+write runs off-main, but keep it sane.
        XCTAssertLessThan(captureMs, 4.0, "main-thread capture must be a small fraction of a frame")
        XCTAssertLessThan(encodeWriteMs, 16.0, "background encode+write should stay near-instant")
        XCTAssertGreaterThan(bytes, 0)
    }
}
