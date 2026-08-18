import XCTest
@testable import GameCore

/// v6.55 CONSENT CHOICES — Second Wind's save and the Link Shuffler's
/// board-wide shuffle park for a player decision when their consent flags are
/// set (the iOS UI sets them; the web and every fixture/trace run with them
/// unset, i.e. the AUTO behaviour). Covers: park shape, accept, decline,
/// snapshot round-trip mid-choice, and the untouched auto default.
final class PendingChoiceTests: XCTestCase {

    /// A 3-pile, one-column deal with Second Wind on the column and pile 0
    /// holding a known 3-card stack; the killer is forced via debug.
    private func windEngine(consent: Bool) -> GameEngine {
        let e = GameEngine(deckSpecs: DeckManager.buildStandardDeck(), pileCount: 3,
                           runConfig: RunConfig(cols: [3]))
        e.start(seedOverride: 4242)
        e.startRun(pillars: ["secondWind"], bases: [nil], samePower: .some(nil))
        e.run.secondWindNeedsConsent = consent
        e.board.piles[0].cards = [DeckManager.cardForValue(3),
                                  DeckManager.cardForValue(4),
                                  DeckManager.cardForValue(5)]
        e.debug.setNextCard(9)
        return e
    }

    /// The first rng state in 1...2000 whose Second Wind roll SAVES pile 0.
    /// (Probed on scratch engines so the assertions below are deterministic.)
    private func savingSeed(consent: Bool) -> UInt32? {
        for seed: UInt32 in 1...2000 {
            let t = windEngine(consent: consent)
            t.rng.state = seed
            t.guess(0, .lower)   // 5 → 9 is wrong → death unless the roll hits
            let saved = consent ? t.run.pendingSecondWind != nil : t.board.isActive(0)
            if saved { return seed }
        }
        return nil
    }

    // MARK: - Second Wind choice (task 9)

    /// The roll hits → the save PARKS: pile untouched, the killer held out of
    /// the deck, the recycle count stated for the prompt (pile 3 + killer 1).
    func testSecondWindConsentParksTheSave() {
        guard let seed = savingSeed(consent: true) else {
            return XCTFail("no saving seed in 1...2000 — the 25% roll is broken")
        }
        let e = windEngine(consent: true)
        let deckBefore = e.deck.remaining()
        e.rng.state = seed
        e.guess(0, .lower)
        let p = e.run.pendingSecondWind
        XCTAssertNotNil(p, "the hit save waits for the player")
        XCTAssertEqual(p?.index, 0)
        XCTAssertEqual(p?.col, 0)
        XCTAssertEqual(p?.recycleCount, 4, "3 pile cards + the killing card")
        XCTAssertEqual(p?.killingCard.value, 9, "the held killer is the drawn card")
        XCTAssertTrue(e.board.isActive(0), "nothing decided yet — the pile lives")
        XCTAssertEqual(e.board.piles[0].cards.map(\.value), [3, 4, 5], "…untouched")
        XCTAssertEqual(e.deck.remaining(), deckBefore - 1, "only the draw came out")
        XCTAssertEqual(e.run.secondWindUsed?[0], false, "the used-flag rides the SAVE, not the roll")
    }

    /// Accept: the parked save applies exactly like the auto path — the pile
    /// is dealt one fresh top, everything else recycled into the deck.
    func testSecondWindChoiceAcceptSaves() {
        guard let seed = savingSeed(consent: true) else { return XCTFail("no saving seed") }
        let e = windEngine(consent: true)
        var events: [String] = []
        e.on { ev in
            if case .secondWind = ev { events.append("secondWind") }
            if case .pileKilled = ev { events.append("pileKilled") }
        }
        e.rng.state = seed
        e.guess(0, .lower)
        XCTAssertTrue(events.isEmpty, "parked: no save/death events before the answer")
        e.answerSecondWind(true)
        XCTAssertNil(e.run.pendingSecondWind)
        XCTAssertTrue(e.board.isActive(0), "saved")
        XCTAssertEqual(e.board.piles[0].cards.count, 1, "one fresh top after the recycle")
        XCTAssertEqual(e.run.secondWindUsed?[0], true)
        XCTAssertEqual(events, ["secondWind"], "the save cue fires on the answer")
        XCTAssertEqual(e.status, "playing")
    }

    /// Decline: the pile dies the death the roll interrupted — the held killer
    /// lands as the final top, the kill events fire, end-of-deal re-evaluates.
    func testSecondWindChoiceDeclineLetsItDie() {
        guard let seed = savingSeed(consent: true) else { return XCTFail("no saving seed") }
        let e = windEngine(consent: true)
        var killed = false, resolvedWrong = false
        e.on { ev in
            if case .pileKilled(0) = ev { killed = true }
            if case .resolved(0, _, _, _, let correct) = ev { resolvedWrong = !correct }
        }
        e.rng.state = seed
        e.guess(0, .lower)
        e.answerSecondWind(false)
        XCTAssertNil(e.run.pendingSecondWind)
        XCTAssertFalse(e.board.isActive(0), "declined — the pile dies")
        XCTAssertEqual(e.board.piles[0].cards.last?.value, 9, "the killer is the final top")
        XCTAssertEqual(e.board.piles[0].cards.count, 4, "its cards stay buried with it")
        XCTAssertTrue(killed); XCTAssertTrue(resolvedWrong)
        XCTAssertEqual(e.run.secondWindUsed?[0], false, "no save, no used-flag")
    }

    /// DEFAULT (web parity / fixtures): consent unset → the save auto-applies
    /// inline, exactly as before, and nothing parks.
    func testSecondWindAutoModeUnchanged() {
        guard let seed = savingSeed(consent: false) else { return XCTFail("no saving seed") }
        let e = windEngine(consent: false)
        e.rng.state = seed
        e.guess(0, .lower)
        XCTAssertNil(e.run.pendingSecondWind, "auto mode never parks")
        XCTAssertTrue(e.board.isActive(0))
        XCTAssertEqual(e.board.piles[0].cards.count, 1, "the auto-save shape")
    }

    /// A kill mid-choice resumes INTO the prompt: the pending (and its held
    /// killing card) round-trips the snapshot and answers correctly after.
    func testSecondWindPendingSnapshotRoundTrip() {
        guard let seed = savingSeed(consent: true) else { return XCTFail("no saving seed") }
        let a = windEngine(consent: true)
        a.rng.state = seed
        a.guess(0, .lower)
        XCTAssertNotNil(a.run.pendingSecondWind)

        let blob = a.snapshot()
        let b = windEngine(consent: true)   // same plan/seed — the boot path
        XCTAssertTrue(b.restoreSnapshot(blob), "a mid-choice blob must restore")
        XCTAssertEqual(b.run.pendingSecondWind?.index, 0)
        XCTAssertEqual(b.run.pendingSecondWind?.recycleCount, 4)
        XCTAssertEqual(b.run.pendingSecondWind?.killingCard.id,
                       a.run.pendingSecondWind?.killingCard.id,
                       "the held killer survives the round-trip (it lives ONLY in the pending)")
        // …and both answers work off the restored state.
        b.answerSecondWind(true)
        XCTAssertTrue(b.board.isActive(0))
        XCTAssertEqual(b.board.piles[0].cards.count, 1)
    }

    // MARK: - Link Shuffler confirm (task 10)

    /// A deal with Link Shuffler equipped; pile 0's top is a 7 and the next
    /// draw is forced to a 7 — a correct Same on cue.
    private func shufflerEngine(consent: Bool) -> GameEngine {
        let e = GameEngine(deckSpecs: DeckManager.buildStandardDeck(), pileCount: 3,
                           runConfig: RunConfig(cols: [3], samePower: "linkShuffle"))
        e.start(seedOverride: 4242)
        e.startRun(pillars: [nil], bases: [nil], samePower: .some("linkShuffle"))
        e.run.samePowerNeedsConsent = consent
        e.board.piles[0].cards = [DeckManager.cardForValue(7)]
        e.debug.setNextCard(7)
        return e
    }

    /// Consent on: the correct Same banks its charge but PARKS the shuffle —
    /// no .samePower fire until the player confirms.
    func testShufflerConsentParksThenConfirmFires() {
        let e = shufflerEngine(consent: true)
        var fires: [SamePowerResult] = []
        e.on { ev in if case .samePower(let r) = ev { fires.append(r) } }
        e.guess(0, .same)
        XCTAssertEqual(e.run.pendingPowerShuffle, 0, "parked on the hub")
        XCTAssertTrue(e.sameCharge, "the Same Charge banks either way — the call was correct")
        XCTAssertTrue(fires.isEmpty, "no fire before the confirm")
        e.answerPowerShuffle(true)
        XCTAssertNil(e.run.pendingPowerShuffle)
        XCTAssertEqual(fires.count, 1)
        XCTAssertEqual(fires.first?.effect, "linkShuffle")
        XCTAssertEqual(fires.first?.targets.sorted(), [0, 1, 2], "every alive pile shuffles")
    }

    /// Decline: the power never fires, the piles keep their order, the banked
    /// charge is untouched.
    func testShufflerConsentDeclineKeepsOrder() {
        let e = shufflerEngine(consent: true)
        var fires = 0
        e.on { ev in if case .samePower = ev { fires += 1 } }
        let order = e.board.piles.map { $0.cards.map(\.id) }
        e.guess(0, .same)
        e.answerPowerShuffle(false)
        XCTAssertNil(e.run.pendingPowerShuffle)
        XCTAssertEqual(fires, 0, "declined — the shuffle never fires")
        // The landing itself pushed the 7 onto pile 0; every other pile's
        // order is byte-identical.
        XCTAssertEqual(e.board.piles[1].cards.map(\.id), order[1])
        XCTAssertEqual(e.board.piles[2].cards.map(\.id), order[2])
        XCTAssertTrue(e.sameCharge)
    }

    /// DEFAULT (web parity / fixtures): consent unset → the power fires inline
    /// on the correct Same, as before.
    func testShufflerAutoModeUnchanged() {
        let e = shufflerEngine(consent: false)
        var fires = 0
        e.on { ev in if case .samePower = ev { fires += 1 } }
        e.guess(0, .same)
        XCTAssertNil(e.run.pendingPowerShuffle, "auto mode never parks")
        XCTAssertEqual(fires, 1, "the power fires inline, web-style")
    }

    /// The parked confirm round-trips the mid-deal snapshot and still fires.
    func testShufflerPendingSnapshotRoundTrip() {
        let a = shufflerEngine(consent: true)
        a.guess(0, .same)
        XCTAssertEqual(a.run.pendingPowerShuffle, 0)
        let b = shufflerEngine(consent: true)
        XCTAssertTrue(b.restoreSnapshot(a.snapshot()))
        // The restored engine's board needs the same scripted pile-0 state —
        // the snapshot carries it (the landing happened before the park).
        XCTAssertEqual(b.run.pendingPowerShuffle, 0)
        var fires = 0
        b.on { ev in if case .samePower = ev { fires += 1 } }
        b.answerPowerShuffle(true)
        XCTAssertEqual(fires, 1)
    }

    // MARK: - Queen's Restock spend (task 11's exactly-once)

    /// The free refresh is spent by the FIRST reroll of the visit and only
    /// that one: cost 0 on arrival, the free reroll charges nothing, and the
    /// ladder is pricing again afterwards.
    func testFreeRefreshSpendsExactlyOnce() {
        let c = CampaignState()
        c.setDeck("pink"); c.setSeedOverride(4242); c.reset()
        c.addCoins(50)
        XCTAssertEqual(c.applyMysteryEvent("freeRefresh", nodeId: 7)?.key, "freeRefresh")
        _ = c.openStore(node: 7)
        XCTAssertEqual(c.storeRerollCost(), 0, "the visit's first refresh is free")
        let coinsBefore = c.getCoins()
        XCTAssertTrue(c.rerollStore(), "the free refresh rerolls")
        XCTAssertEqual(c.getCoins(), coinsBefore, "…and charges nothing")
        XCTAssertGreaterThan(c.storeRerollCost(), 0, "the ladder prices the NEXT one")
        XCTAssertTrue(c.rerollStore())
        XCTAssertLessThan(c.getCoins(), coinsBefore, "the second refresh pays for real")
    }

    // MARK: - Second Wind sequencing (v6.56): the draw precedes the save prompt

    /// The park emits ONE `.secondWindOffer` carrying the drawn killer — and NO
    /// `.resolved`/`.pileKilled`/`.secondWind` yet: the UI shows the drawn card
    /// and the dying moment FIRST, then asks. The pile is untouched and the
    /// deal is NOT evaluated while the choice sits open.
    func testSecondWindOfferPrecedesTheChoice() {
        guard let seed = savingSeed(consent: true) else { return XCTFail("no saving seed") }
        let e = windEngine(consent: true)
        var order: [String] = []
        var offer: (index: Int, col: Int, drawnId: Int, recycle: Int)?
        e.on { ev in
            switch ev {
            case .secondWindOffer(let i, let c, _, _, let drawn, let rc):
                order.append("offer"); offer = (i, c, drawn.id, rc)
            case .resolved: order.append("resolved")
            case .pileKilled: order.append("pileKilled")
            case .secondWind: order.append("secondWind")
            case .won: order.append("won")
            case .lost: order.append("lost")
            default: break
            }
        }
        e.rng.state = seed
        e.guess(0, .lower)
        XCTAssertEqual(order, ["offer"],
                       "the offer is the guess's ONLY terminal event — the fate events wait for the answer")
        XCTAssertEqual(offer?.index, 0); XCTAssertEqual(offer?.col, 0)
        XCTAssertEqual(offer?.drawnId, e.run.pendingSecondWind?.killingCard.id)
        XCTAssertEqual(offer?.recycle, 4)
        XCTAssertEqual(e.status, "playing", "the deal must not end mid-choice")
        // …and the answer's events follow, in the documented order.
        e.answerSecondWind(true)
        XCTAssertEqual(order, ["offer", "secondWind"])
    }

    /// The killer is held OUT of the deck while parked; when it was the LAST
    /// card the deck reads empty, and the deal still must not call the win
    /// until the player answers. Accept recycles (the deal goes on); decline
    /// lands the killer and only THEN re-evaluates.
    func testSecondWindParkDefersEndOfDeal() {
        func lastCardEngine() -> GameEngine {
            let e = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), IV.spec(3, 6)],
                              deckOrder: [IV.spec(50, 9, "♥")],   // the killer is the LAST card
                              pillars: ["secondWind", nil, nil])
            e.run.secondWindNeedsConsent = true
            return e
        }
        var state: UInt32?
        for s: UInt32 in 1...2000 {
            let t = lastCardEngine()
            t.rng.state = s
            t.guess(0, .lower)
            if t.run.pendingSecondWind != nil { state = s; break }
        }
        guard let s = state else { return XCTFail("no saving state in 1...2000") }

        // Accept: no premature win while parked; the recycle refills the deck.
        let a = lastCardEngine()
        var ended = false
        a.on { if case .won = $0 { ended = true }; if case .lost = $0 { ended = true } }
        a.rng.state = s
        a.guess(0, .lower)
        XCTAssertEqual(a.deck.remaining(), 0, "the held killer emptied the deck")
        XCTAssertFalse(ended, "no win/loss may fire while the save choice is parked")
        XCTAssertEqual(a.status, "playing")
        a.answerSecondWind(true)
        XCTAssertTrue(a.board.isActive(0), "saved")
        XCTAssertEqual(a.deck.remaining(), 1, "2 recycled − 1 fresh top")
        XCTAssertEqual(a.status, "playing", "the deal continues after the recycle")

        // Decline: the killer lands, the pile dies, and end-of-deal evaluates
        // NOW (deck empty with survivors → the deal clears).
        let b = lastCardEngine()
        b.rng.state = s
        b.guess(0, .lower)
        b.answerSecondWind(false)
        XCTAssertFalse(b.board.isActive(0), "declined — the pile dies")
        XCTAssertEqual(b.status, "won", "the deck is spent with survivors — evaluated on the answer")
    }

    /// DEFAULT (web parity / fixtures): consent unset → no offer event; the
    /// save applies inline exactly as before.
    func testSecondWindAutoModeEmitsNoOffer() {
        guard let seed = savingSeed(consent: false) else { return XCTFail("no saving seed") }
        let e = windEngine(consent: false)
        var offers = 0, saves = 0
        e.on { ev in
            if case .secondWindOffer = ev { offers += 1 }
            if case .secondWind = ev { saves += 1 }
        }
        e.rng.state = seed
        e.guess(0, .lower)
        XCTAssertNil(e.run.pendingSecondWind)
        XCTAssertEqual(offers, 0, "auto mode never emits the offer")
        XCTAssertEqual(saves, 1, "the save fires inline, web-style")
        XCTAssertTrue(e.board.isActive(0))
    }

    // MARK: - Revive targeting (v6.56)

    /// The forced layout the Revive scenarios share: pile 0 one guess short of
    /// the pillar's `trigger`, pile 2 dead, a correct higher draw staged on
    /// top of the deck (and one more card behind it for the revive's fresh
    /// top). The trigger is read from the registry, never hardcoded.
    private func reviveEngine() -> GameEngine {
        let def = GameData.shared.pillarTypes.get("revive")
        let trigger = def?.int("trigger", 10) ?? 10
        let e = IV.engine(tops: [IV.spec(1, 5), IV.spec(2, 6), nil],
                          deckOrder: [IV.spec(50, 9), IV.spec(59, 2)],
                          pillars: ["revive", nil, nil])
        for i in 0..<(trigger - 2) {
            e.board.piles[0].cards.append(DeckManager.toCard(IV.spec(100 + i, 3), data: GameData.shared))
        }
        return e
    }

    /// v6.56 REGRESSION — the native UI let the PromptBar's full-screen scrim
    /// eat the target tap, so the pick silently resolved as Skip and the pile
    /// never came back. Engine-side pin for the exact flow the fixed tap
    /// routing drives: the offer ARMS at the pillar's trigger naming the dead
    /// piles, the player's answer registers, and the chosen pile returns with
    /// a fresh top drawn from the deck.
    func testReviveOfferAnswerRevivesTheChosenPile() {
        let e = reviveEngine()
        var offeredDead: [Int]?
        var revivedIndex: Int?
        e.on { ev in
            if case .reviveOffer(_, let dead) = ev { offeredDead = dead }
            if case .revived(_, let index) = ev { revivedIndex = index }
        }
        e.guess(0, .higher)   // 5 → 9 correct; pile 0 reaches the trigger
        XCTAssertEqual(offeredDead, [2], "the offer fires and names the dead pile")
        XCTAssertEqual(e.run.reviveUsed?[0], false, "the offer alone spends nothing")
        XCTAssertTrue(e.reviveDeadPile(col: 0, targetIndex: 2), "the answer registers")
        XCTAssertTrue(e.board.isActive(2), "the chosen pile is back")
        XCTAssertEqual(e.board.piles[2].cards.last?.id, 59, "…with a fresh top drawn from the deck")
        XCTAssertEqual(e.board.piles[2].cards.count, 2, "the buried card stays under the fresh top")
        XCTAssertEqual(revivedIndex, 2)
        XCTAssertEqual(e.run.reviveUsed?[0], true, "the one-shot is spent on the answer")
    }

    /// Skip (the prompt's nil answer makes NO revive call): the pile stays
    /// dead and the charge stays armed — a dismissed prompt must not silently
    /// consume the pillar. The engine also rejects a LIVING pile as target.
    func testReviveOfferSkipLeavesPileDeadAndChargeArmed() {
        let e = reviveEngine()
        var offered = false
        e.on { ev in if case .reviveOffer = ev { offered = true } }
        e.guess(0, .higher)
        XCTAssertTrue(offered)
        XCTAssertFalse(e.board.isActive(2), "no answer, no revive")
        XCTAssertEqual(e.run.reviveUsed?[0], false, "a skip keeps the charge")
        XCTAssertFalse(e.reviveDeadPile(col: 0, targetIndex: 1),
                       "a living pile is not a legal target")
        XCTAssertFalse(e.board.isActive(2))
        XCTAssertEqual(e.run.reviveUsed?[0], false, "a rejected target spends nothing")
    }
}
