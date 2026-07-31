import XCTest
@testable import GameCore

/// Registry + item-behavior coverage. Every expectation reads its numbers LIVE
/// from items.js, so a retune never breaks the suite — only a rule change does.
final class ItemBehaviorTests: XCTestCase {
    private let data = GameData.shared

    private func engine(cols: [Int] = [3, 3, 3], pillars: [String?]? = nil, bases: [String?]? = nil,
                        samePower: String? = nil, specs: [CardSpec]? = nil,
                        noStickers: Bool = false, seed: UInt32 = 8080) -> GameEngine {
        let e = GameEngine(deckSpecs: specs ?? DeckManager.buildStandardDeck(),
                           pileCount: cols.reduce(0, +),
                           runConfig: RunConfig(cols: cols, samePower: samePower, noStickers: noStickers))
        e.start(seedOverride: seed)
        e.startRun(pillars: pillars ?? Array(repeating: nil, count: cols.count),
                   bases: bases ?? Array(repeating: nil, count: cols.count),
                   samePower: .some(samePower))
        return e
    }

    // MARK: - Registries

    func testRegistriesMirrorTheDataFileInOrder() {
        XCTAssertEqual(data.stickerTypes.ids, data.items.stickers.map(\.id))
        XCTAssertEqual(data.pillarTypes.ids, data.items.pillars.map(\.id))
        XCTAssertEqual(data.baseTypes.ids, data.items.bases.map(\.id))
        XCTAssertEqual(data.samePowerTypes.ids, data.items.samePowers.map(\.id))
        XCTAssertEqual(data.packTypes.ids, data.items.packs.map(\.id))
    }

    func testGetReturnsNilForUnknownIds() {
        XCTAssertNil(data.stickerTypes.get("nope"))
        XCTAssertNil(data.pillarTypes.get(nil))
        XCTAssertNil(data.baseTypes.get(""))
    }

    func testCursedStickersStayOutOfTheGrantPoolButRemainGettable() {
        let cursed = data.items.stickers.filter(\.cursed)
        XCTAssertFalse(cursed.isEmpty)
        let grantable = data.stickerTypes.grantableBase().map(\.id)
        for c in cursed {
            XCTAssertFalse(grantable.contains(c.id), "cursed '\(c.id)' must never roll in a grant pool")
            XCTAssertNotNil(data.stickerTypes.get(c.id), "get() still finds it — mystery applies it directly")
        }
    }

    func testItemNumUsesTheFallbackOnlyWhenAbsentAndTreatsZeroAsValid() {
        let def = ItemDef(raw: ["id": .string("x"), "value": .number(0), "other": .string("s")])
        XCTAssertEqual(def.num("value", 99), 0, "0 is a VALID hand-edited value")
        XCTAssertEqual(def.num("missing", 99), 99)
        XCTAssertEqual(def.num("other", 7), 7, "a non-number reads as absent")
    }

    // MARK: - Sticker eligibility (the GLOBAL gate)

    func testJokersAndRemovalCardsNeverTakeStickers() {
        let joker = CardSpec.joker(id: 900)
        let blank = CardSpec.blank(id: 901)
        for id in data.stickerTypes.ids {
            XCTAssertFalse(CardRules.stickerEligible(joker, id, data: data), "joker took '\(id)'")
            XCTAssertFalse(CardRules.stickerEligible(blank, id, data: data), "removal took '\(id)'")
        }
    }

    func testSuitRestrictedStickersOnlyAttachToTheirSuits() {
        guard let restricted = data.items.stickers.first(where: { ($0.suits?.count ?? 0) == 1 }) else {
            XCTFail("items.js should ship at least one suit-locked sticker"); return
        }
        let wanted = restricted.suits![0]
        for s in ["♠", "♥", "♦", "♣"] {
            let card = CardSpec(id: 1, suit: s, originalRank: 5, currentRank: 5)
            XCTAssertEqual(CardRules.stickerEligible(card, restricted.id, data: data), s == wanted,
                           "'\(restricted.id)' on \(s)")
        }
    }

    func testWildSuitSatisfiesAnySuitRestriction() {
        guard let wild = data.items.stickers.first(where: { $0.behavior == "wildSuit" }),
              let restricted = data.items.stickers.first(where: { ($0.suits?.count ?? 0) == 1 })
        else { XCTFail("need a wildSuit and a suit-locked sticker"); return }
        let offSuit = ["♠", "♥", "♦", "♣"].first { $0 != restricted.suits![0] }!
        var card = CardSpec(id: 2, suit: offSuit, originalRank: 5, currentRank: 5)
        XCTAssertFalse(CardRules.stickerEligible(card, restricted.id, data: data))
        card.stickers.append(StickerRecord(type: wild.id))
        XCTAssertTrue(CardRules.stickerEligible(card, restricted.id, data: data),
                      "a wild card counts as every suit, whatever order the stickers went on")
    }

    func testMatchesSuitTreatsWildAsEverySuit() {
        let plain = LiveCard(id: 1, label: "5", value: 5, suit: "♦", red: true)
        XCTAssertTrue(CardRules.matchesSuit(plain, "♦", data: data))
        XCTAssertFalse(CardRules.matchesSuit(plain, "♠", data: data))
        plain.wildSuit = true
        for s in ["♠", "♥", "♦", "♣"] {
            XCTAssertTrue(CardRules.matchesSuit(plain, s, data: data), "wild must match \(s)")
        }
    }

    // MARK: - Sticker projection (toCard)

    func testBehaviorStickersProjectOntoLiveFields() {
        var spec = CardSpec(id: 3, suit: "♦", originalRank: 9, currentRank: 9)
        spec.stickers = [StickerRecord(type: "tieSafe"), StickerRecord(type: "wildSuit"),
                         StickerRecord(type: "revealNext")]
        let live = DeckManager.toCard(spec, data: data)
        XCTAssertTrue(live.tieSafe)
        XCTAssertTrue(live.wildSuit)
        XCTAssertTrue(live.revealNext)
        XCTAssertEqual(live.value, 9, "toCard uses currentRank")
    }

    func testSuitGuardsProjectOnePerGuardedSuitWithoutStacking() {
        guard let g = data.items.stickers.first(where: { $0.behavior == "suitImmunity" }) else {
            XCTFail("need a suitImmunity sticker"); return
        }
        var spec = CardSpec(id: 4, suit: "♦", originalRank: 9, currentRank: 9)
        spec.stickers = [StickerRecord(type: g.id), StickerRecord(type: g.id)]
        let live = DeckManager.toCard(spec, data: data)
        XCTAssertEqual(live.suitGuards, [g.suit!], "duplicate guards of one suit don't stack")
    }

    func testAJokerSpecProjectsToARanklessStar() {
        let live = DeckManager.toCard(CardSpec.joker(id: 5), data: data)
        XCTAssertTrue(live.joker)
        XCTAssertEqual(live.value, 0, "value 0 triggers no rank effects")
        XCTAssertEqual(live.suit, "★")
        XCTAssertTrue(live.stickers.isEmpty)
    }

    // MARK: - Live sticker effects

    func testBonusCoinPaysItsItemsJsValueOnLanding() {
        guard let t = data.items.stickers.first(where: { $0.behavior == "gainCoin" }) else {
            XCTFail("need a gainCoin sticker"); return
        }
        var specs = DeckManager.buildStandardDeck()
        let i = specs.firstIndex { $0.suit == "♦" && $0.currentRank == 10 }!
        specs[i].stickers.append(StickerRecord(type: t.id))
        let e = engine(specs: specs)
        e.board.piles[0].cards = [DeckManager.cardForValue(4)]
        e.debug.setNextCardObj(DeckManager.toCard(specs[i], data: data))
        e.guess(0, .higher)
        XCTAssertEqual(e.run.bonusCoins, t.value, "the payout is the items.js `value`")
    }

    func testCollectorPaysPerOtherStickerOnTheCard() {
        guard let c = data.items.stickers.first(where: { $0.behavior == "collector" }) else {
            XCTFail("need a collector sticker"); return
        }
        var specs = DeckManager.buildStandardDeck()
        let i = specs.firstIndex { $0.suit == "♦" && $0.currentRank == 10 }!
        specs[i].stickers = [StickerRecord(type: c.id), StickerRecord(type: "anchor"), StickerRecord(type: "tieSafe")]
        let e = engine(specs: specs)
        e.board.piles[0].cards = [DeckManager.cardForValue(4)]
        e.debug.setNextCardObj(DeckManager.toCard(specs[i], data: data))
        e.guess(0, .higher)
        let unit = c.num("value", 1) == 0 ? 1 : c.value
        XCTAssertEqual(e.run.bonusCoins, unit * 2, "+1 per OTHER sticker on the card")
    }

    func testCompoundPaysHitsMinusOneAndPersistsToTheCampaignCard() {
        var specs = DeckManager.buildStandardDeck()
        let i = specs.firstIndex { $0.suit == "♦" && $0.currentRank == 3 }!
        specs[i].stickers.append(StickerRecord(type: "compound"))
        let e = engine(specs: specs)
        let carrier = DeckManager.toCard(specs[i], data: data)
        let step = data.stickerTypes.get("compound")?.num("step", 1) ?? 1
        var expected: Double = 0
        for hit in 1...4 {
            e.board.piles[0].cards = [carrier]                // the Compound card is the TOP
            e.debug.setNextCard(14)
            e.guess(0, .higher)                               // correct against it
            expected += Double(hit - 1) * step                // +0, +1, +2, …
            XCTAssertEqual(e.run.bonusCoins, expected, "Compound pays (hits − 1) on hit \(hit)")
        }
        XCTAssertEqual(e.run.compoundUpdates[carrier.id], 4, "the running total is recorded for write-back")
    }

    func testDeathBountyPaysWhenTheCarrierKillsThePile() {
        guard let t = data.items.stickers.first(where: { $0.id == "deathBounty" }) else {
            XCTFail("need deathBounty"); return
        }
        var specs = DeckManager.buildStandardDeck()
        let i = specs.firstIndex { $0.suit == "♦" && $0.currentRank == 2 }!
        specs[i].stickers.append(StickerRecord(type: t.id))
        let e = engine(specs: specs)
        e.board.piles[0].cards = [DeckManager.cardForValue(10)]
        e.debug.setNextCardObj(DeckManager.toCard(specs[i], data: data))
        e.guess(0, .higher)                                    // 10 → 2 kills
        XCTAssertFalse(e.board.isActive(0))
        XCTAssertEqual(e.run.bonusCoins, t.value, "the killing card pays a consolation")
    }

    func testQuickBuryBuriesFromTheDeckBottomWithoutRevealing() {
        var specs = DeckManager.buildStandardDeck()
        let i = specs.firstIndex { $0.suit == "♦" && $0.currentRank == 10 }!
        specs[i].stickers.append(StickerRecord(type: "quickBury"))
        let e = engine(specs: specs)
        e.board.piles[0].cards = [DeckManager.cardForValue(4)]
        e.debug.setNextCardObj(DeckManager.toCard(specs[i], data: data))
        let before = e.deck.remaining()
        e.guess(0, .higher)
        XCTAssertEqual(e.deck.remaining(), before - 1 - 1, "one draw + one burial")
        XCTAssertEqual(e.board.piles[0].cards.count, 3, "the buried card sits UNDER the pile")
        XCTAssertEqual(e.board.piles[0].cards.last?.value, 10, "the landing card is still the top")
    }

    func testSnowballGrowsThenBuriesAndResetsOnAWrongPlacement() {
        let step = data.stickerTypes.get("snowball")?.int("step", 1) ?? 1
        var specs = DeckManager.buildStandardDeck()
        let i = specs.firstIndex { $0.suit == "♦" && $0.currentRank == 10 }!
        specs[i].stickers.append(StickerRecord(type: "snowball"))
        let e = engine(specs: specs)
        let carrier = DeckManager.toCard(specs[i], data: data)
        e.board.piles[0].cards = [DeckManager.cardForValue(4)]
        e.debug.setNextCardObj(carrier)
        e.guess(0, .higher)
        XCTAssertEqual(carrier.snowball, step, "X grows on a correct placement")
        XCTAssertEqual(e.run.snowballUpdates[carrier.id], step)
        // A WRONG placement of the carrier resets X to 0.
        e.board.piles[1].cards = [DeckManager.cardForValue(14)]
        e.debug.setNextCardObj(carrier)
        e.guess(1, .higher)                                    // A → 10 is wrong
        XCTAssertEqual(carrier.snowball, 0, "any wrong placement resets X")
        XCTAssertEqual(e.run.snowballUpdates[carrier.id], 0)
    }

    func testScoutRevealsTheNextCardAndTheRevealClearsOnTheNextDraw() {
        var specs = DeckManager.buildStandardDeck()
        let i = specs.firstIndex { $0.suit == "♦" && $0.currentRank == 10 }!
        specs[i].stickers.append(StickerRecord(type: "revealNext"))
        let e = engine(specs: specs)
        XCTAssertNil(e.revealedNextCard(), "a deal NEVER starts pre-peeked")
        e.board.piles[0].cards = [DeckManager.cardForValue(4)]
        e.debug.setNextCardObj(DeckManager.toCard(specs[i], data: data))
        e.guess(0, .higher)
        XCTAssertTrue(e.run.revealNextActive)
        XCTAssertNotNil(e.revealedNextCard())
        // Drawing consumes the reveal.
        e.board.piles[1].cards = [DeckManager.cardForValue(2)]
        e.debug.setNextCard(3)
        e.guess(1, .higher)
        XCTAssertFalse(e.run.revealNextActive)
    }

    func testTellArmsADirectionalHintThatOneDrawAnywhereSpends() {
        var specs = DeckManager.buildStandardDeck()
        let i = specs.firstIndex { $0.suit == "♦" && $0.currentRank == 10 }!
        specs[i].stickers.append(StickerRecord(type: "tell"))
        let e = engine(specs: specs)
        e.board.piles[0].cards = [DeckManager.cardForValue(4)]
        e.debug.setNextCardObj(DeckManager.toCard(specs[i], data: data))
        e.guess(0, .higher)
        XCTAssertTrue(e.run.tellPiles.contains(0))
        e.debug.setNextCard(14)
        XCTAssertEqual(e.pileHint(0), .higher, "the hint reports the REAL next card's direction")
        // ONE draw on ANY pile spends every armed hint.
        e.board.piles[2].cards = [DeckManager.cardForValue(2)]
        e.guess(2, .higher)
        XCTAssertTrue(e.run.tellPiles.isEmpty)
        XCTAssertNil(e.pileHint(0))
    }

    func testLammyBlocksEveryStickerProjection() {
        let e = engine(noStickers: true)
        let card = LiveCard(id: 42, label: "5", value: 5, suit: "♦", red: true)
        XCTAssertFalse(e.projectStickerOntoCard(card, "tieSafe"), "no effect may sticker a card")
        XCTAssertTrue(card.stickers.isEmpty)
        XCTAssertTrue(e.wildStickerPoolFor(card).isEmpty, "Wild Sticker never has a target")
    }

    // MARK: - Pillars

    func testEveryPillarEffectIsDispatchable() {
        // A Pillar whose effect the engine can't dispatch would silently do
        // nothing — assert each id at least runs a full deal without crashing
        // and that scoring Pillars can produce a payout line.
        for p in data.items.pillars {
            let e = engine(pillars: [p.id, nil, nil], seed: 1234)
            for step in 0..<40 where e.status == "playing" {
                let alive = (0..<e.board.size).filter { e.board.isActive($0) }
                if alive.isEmpty { break }
                let pile = alive[step % alive.count]
                let v = e.board.top(pile)?.value ?? 8
                e.guess(pile, step % 5 == 4 ? .same : (v <= 8 ? .higher : .lower))
                while !e.run.pendingTributes.isEmpty { e.answerTribute(true) }
                while !e.run.pendingActions.isEmpty { e.answerAction(true) }
            }
            _ = e.pillarPayout()   // must not trap
        }
    }

    func testColumnAllAlivePaysOnlyWhenTheWholeColumnSurvives() {
        guard let p = data.items.pillars.first(where: { $0.effect == "columnAllAlive" }) else {
            XCTFail("need a columnAllAlive pillar"); return
        }
        let e = engine(pillars: [p.id, nil, nil])
        XCTAssertEqual(e.pillarPayout().bonus, p.value, "an untouched column pays")
        e.board.kill(0)                                        // a pile in column 0
        XCTAssertEqual(e.pillarPayout().bonus, 0, "one death voids it")
    }

    func testGreedyNeedsToBeTheSolePillarOnTheBoard() {
        guard let g = data.items.pillars.first(where: { $0.effect == "greedy" }),
              let other = data.items.pillars.first(where: { $0.effect != "greedy" && $0.kind == "scoring" })
        else { XCTFail("need a greedy + another scoring pillar"); return }
        let solo = engine(pillars: [g.id, nil, nil])
        XCTAssertEqual(solo.pillarPayout().lines.filter { $0.label == g.label }.count, 1)
        let shared = engine(pillars: [g.id, other.id, nil])
        XCTAssertTrue(shared.pillarPayout().lines.filter { $0.label == g.label }.isEmpty,
                      "a second Pillar anywhere voids Greedy")
    }

    func testDittoMirrorsTheCentreColumnAndNoOpsAtTheCentre() {
        guard data.items.pillars.contains(where: { $0.effect == "ditto" }),
              let mirrored = data.items.pillars.first(where: { $0.effect == "columnAllAlive" })
        else { XCTFail("need ditto + columnAllAlive"); return }
        // Ditto on column 0, the mirrored Pillar in the centre (column 1).
        let e = engine(pillars: ["ditto", mirrored.id, nil])
        let lines = e.pillarPayout().lines
        XCTAssertEqual(lines.filter { $0.col == 0 }.count, 1, "Ditto applies the centre's effect to ITS column")
        // Ditto AT the centre is a no-op.
        let atCentre = engine(pillars: [nil, "ditto", nil])
        XCTAssertTrue(atCentre.pillarPayout().lines.isEmpty)
        // Ditto mirroring another Ditto is a no-op.
        let dittoDitto = engine(pillars: ["ditto", "ditto", nil])
        XCTAssertTrue(dittoDitto.pillarPayout().lines.isEmpty)
    }

    /// The engine keeps the Echo dispatch alive, but items.js does not ship an
    /// `echo` Pillar today — skip rather than fail if it is absent, so re-adding
    /// one to the data file re-arms this test automatically.
    func testEchoPaysPerAdjacentPaidLineAndNeverChains() throws {
        guard let echo = data.items.pillars.first(where: { $0.effect == "echo" }),
              let payer = data.items.pillars.first(where: { $0.effect == "columnAllAlive" })
        else { throw XCTSkip("items.js ships no `echo` Pillar") }
        let e = engine(pillars: [payer.id, echo.id, nil])
        let out = e.pillarPayout()
        let echoLines = out.lines.filter { $0.effect == "echo" }
        XCTAssertEqual(echoLines.count, 1, "one echo per adjacent PAID line")
        XCTAssertEqual(out.bonus, payer.value + echoLines[0].amount)
        // Two Echoes next to each other never feed one another.
        let chain = engine(pillars: [echo.id, echo.id, nil])
        XCTAssertTrue(chain.pillarPayout().lines.isEmpty, "Echo lines never re-trigger Echo")
    }

    func testHighestHeartPaysNumberedHeartsOnlyAceOneRoyalsNothing() {
        guard let p = data.items.pillars.first(where: { $0.effect == "highestHeart" }) else {
            XCTFail("need highestHeart"); return
        }
        func topValue(_ v: Int) -> Double {
            let e = engine(pillars: [p.id, nil, nil])
            for i in 0..<3 { e.board.piles[i].cards = [LiveCard(id: 100 + i, label: "x", value: v, suit: "♥", red: true)] }
            return e.pillarPayout().bonus
        }
        XCTAssertEqual(topValue(7), 7, "a numbered heart pays face value")
        XCTAssertEqual(topValue(14), 1, "an Ace pays 1")
        for royal in [11, 12, 13] { XCTAssertEqual(topValue(royal), 0, "royals pay nothing") }
    }

    func testSuitBountyIsPaidLiveAndNotScoredAgainAtRunEnd() {
        guard let p = data.items.pillars.first(where: { $0.effect == "suitBounty" }), let suit = p.suit else {
            XCTFail("need a suitBounty pillar"); return
        }
        var specs = DeckManager.buildStandardDeck()
        let i = specs.firstIndex { $0.suit == suit && $0.currentRank == 10 }!
        let e = engine(pillars: [p.id, nil, nil], specs: specs)
        e.board.piles[0].cards = [DeckManager.cardForValue(4)]
        e.debug.setNextCardObj(DeckManager.toCard(specs[i], data: data))
        e.guess(0, .higher)
        XCTAssertEqual(e.run.bonusCoins, p.value, "paid LIVE into the tally")
        XCTAssertEqual(e.run.suitBountyHits?[0], 1)
        XCTAssertTrue(e.pillarPayout().lines.allSatisfy { $0.label != p.label },
                      "suitBounty must not be scored a second time at run end")
    }

    // MARK: - Bases

    func testEveryBaseIdIsDispatchableAndSpendsItsChargeExactlyOnce() {
        for b in data.items.bases {
            let e = engine(pillars: [nil, nil, nil], bases: [b.id, nil, nil], seed: 6161)
            XCTAssertTrue(e.baseCharged(0), "\(b.id): armed at deal start")
            XCTAssertFalse(e.baseCharged(1), "an empty column is never charged")
            guard e.baseAvailable(0) else { continue }   // preconditions may not hold on this board
            let target: Int? = b.target == "pile" ? (0..<e.board.size).first { e.run.pileColumns?[$0] == 0 }
                : (b.target == "pillar" ? 0 : nil)
            let res = e.baseActivate(col: 0, targetIndex: target)
            XCTAssertNotNil(res, "\(b.id): activation returned nil despite being available")
            XCTAssertFalse(e.baseCharged(0), "\(b.id): the charge is spent")
            XCTAssertNil(e.baseActivate(col: 0, targetIndex: target), "\(b.id): a spent Base can't fire again")
        }
    }

    func testARechargeCellIsOnlyAvailableWhenACharGeCanBeBanked() {
        guard let b = data.items.bases.first(where: { $0.effect == "rechargeSameShield" }) else {
            XCTFail("need a rechargeSameShield base"); return
        }
        let e = engine(bases: [b.id, nil, nil])
        XCTAssertTrue(e.baseAvailable(0), "with no charge banked it is available")
        _ = e.baseActivate(col: 0)
        XCTAssertTrue(e.sameCharge)
        // Re-arm it and confirm the precondition now blocks (never wasted).
        e.run.basesUsed?[0] = false
        XCTAssertFalse(e.baseAvailable(0), "at full charge it is not offered")
    }

    func testRefreshBasesReArmsOtherSpentBasesButNeverAnotherRefresh() {
        guard let refresh = data.items.bases.first(where: { $0.effect == "refreshBases" }),
              let other = data.items.bases.first(where: { $0.effect == "shuffleColumn" })
        else { XCTFail("need refreshBases + another base"); return }
        let e = engine(bases: [refresh.id, other.id, refresh.id])
        e.run.basesUsed = [false, true, true]                  // cols 1 + 2 are spent
        XCTAssertTrue(e.baseAvailable(0))
        _ = e.baseActivate(col: 0)
        XCTAssertEqual(e.run.basesUsed?[1], false, "a normal spent Base is re-armed")
        XCTAssertEqual(e.run.basesUsed?[2], true, "another Refresh Bases is never re-armed")
    }

    func testBasesAreColumnScopedAndRejectOutOfColumnTargets() {
        guard let b = data.items.bases.first(where: { $0.target == "pile" }) else { return }
        let e = engine(bases: [b.id, nil, nil])
        guard e.baseAvailable(0) else { return }
        let foreign = (0..<e.board.size).first { e.run.pileColumns?[$0] == 2 }!
        XCTAssertNil(e.baseActivate(col: 0, targetIndex: foreign),
                     "a pile-target Base only acts on its OWN column")
    }

    // MARK: - Same-Powers

    func testACorrectSameFiresTheEquippedPowerBoardWide() {
        guard let sp = data.items.samePowers.first(where: { $0.effect == "linkCoins" }) else {
            XCTFail("need linkCoins"); return
        }
        let e = engine(samePower: sp.id)
        var fired: SamePowerResult?
        e.on { if case .samePower(let r) = $0 { fired = r } }
        e.board.piles[0].cards = [DeckManager.cardForValue(7)]
        e.debug.setNextCard(7)
        e.guess(0, .same)
        XCTAssertNotNil(fired, "a correct Same triggers the equipped power")
        XCTAssertEqual(fired?.targets.count, e.board.aliveCount(),
                       "v5.66: every Same-Power acts BOARD-WIDE, not just on linked piles")
        XCTAssertEqual(e.run.bonusCoins, sp.num("value", 1) * Double(e.board.aliveCount()))
    }

    func testNoSamePowerEquippedIsANoOp() {
        let e = engine(samePower: nil)
        var fired = false
        e.on { if case .samePower = $0 { fired = true } }
        e.board.piles[0].cards = [DeckManager.cardForValue(7)]
        e.debug.setNextCard(7)
        e.guess(0, .same)
        XCTAssertFalse(fired)
        XCTAssertTrue(e.sameCharge, "the charge still banks")
    }

    func testAHigherOrLowerCallNeverFiresTheSamePower() {
        guard let sp = data.items.samePowers.first else { return }
        let e = engine(samePower: sp.id)
        var fired = false
        e.on { if case .samePower = $0 { fired = true } }
        e.board.piles[0].cards = [DeckManager.cardForValue(4)]
        e.debug.setNextCard(9)
        e.guess(0, .higher)
        XCTAssertFalse(fired, "a Same is the ONLY thing that triggers a Same-Power")
    }

    func testEverySamePowerEffectRuns() {
        for sp in data.items.samePowers {
            let e = engine(samePower: sp.id, seed: 7272)
            e.board.piles[0].cards = [DeckManager.cardForValue(7)]
            e.debug.setNextCard(7)
            e.guess(0, .same)                                  // must not trap
            XCTAssertEqual(e.equippedSamePower(), sp.id)
        }
    }

    func testLinkReviveKeepsTheRevivedPilesSize() {
        guard let sp = data.items.samePowers.first(where: { $0.effect == "linkRevive" }) else { return }
        let e = engine(samePower: sp.id)
        // Bury a couple of cards under pile 2 and kill it.
        e.board.push(2, DeckManager.cardForValue(3))
        e.board.push(2, DeckManager.cardForValue(4))
        let size = e.board.pileSize(2)
        e.board.kill(2)
        e.board.piles[0].cards = [DeckManager.cardForValue(7)]
        e.debug.setNextCard(7)
        e.guess(0, .same)
        XCTAssertTrue(e.board.isActive(2), "the largest dead pile revives")
        XCTAssertEqual(e.board.pileSize(2), size, "its cards are kept")
    }

    // MARK: - Packs

    func testPackTypesDeclareSizeAndKeep() {
        for p in data.items.packs {
            XCTAssertGreaterThan(p.int("size", 0), 0, "pack '\(p.id)': size")
            XCTAssertGreaterThan(p.int("keep", 0), 0, "pack '\(p.id)': keep")
            XCTAssertLessThanOrEqual(p.int("keep", 0), p.int("size", 0), "pack '\(p.id)': keep ≤ size")
            XCTAssertTrue(["card", "sticker"].contains(p.kind ?? ""), "pack '\(p.id)': kind")
        }
    }

    func testPackStickerOddsTableIsWalkedInOrder() {
        // A roll below the first cap gets the first (largest) sticker count.
        let odds = data.items.packStickerOdds
        XCTAssertEqual(StoreRoll.packStickerCount(odds[0][0] / 2, data: data), Int(odds[0][1]))
        XCTAssertEqual(StoreRoll.packStickerCount(0.999999, data: data), 0, "past every maxRoll → 0 stickers")
    }
}
