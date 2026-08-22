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

    func testCompoundResetsOnAWrongGuessAgainstTheCarrier() {
        // v6.51: Snowball's reset semantics, keyed off the pile-TOP card the
        // wrong guess was made AGAINST (snowball keys off the drawn card).
        var specs = DeckManager.buildStandardDeck()
        let i = specs.firstIndex { $0.suit == "♦" && $0.currentRank == 3 }!
        specs[i].stickers.append(StickerRecord(type: "compound"))
        let e = engine(specs: specs)
        let carrier = DeckManager.toCard(specs[i], data: data)
        for hit in 1...2 {
            e.board.piles[0].cards = [carrier]
            e.debug.setNextCard(14)
            e.guess(0, .higher)                           // correct: bank grows
            XCTAssertEqual(e.run.compoundUpdates[carrier.id], hit)
        }
        // A WRONG guess against the carrier spends the whole bank.
        e.board.piles[0].cards = [carrier]                // 3♦ on top
        e.debug.setNextCard(2)
        e.guess(0, .higher)                               // 3 → 2 is wrong
        XCTAssertEqual(carrier.compoundHits, 0, "a wrong guess against it resets the bank")
        XCTAssertEqual(e.run.compoundUpdates[carrier.id], 0, "the reset rides the write-back")
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
        // PILE-TOP (v6.75): the carrier tops the pile; a card LANDING ON it
        // buries 1 from the deck bottom beneath that pile.
        var specs = DeckManager.buildStandardDeck()
        let i = specs.firstIndex { $0.suit == "♦" && $0.currentRank == 10 }!
        let e = engine(specs: specs)
        let carrierTop = DeckManager.cardForValue(4)
        carrierTop.stickers.append(StickerRecord(type: "quickBury"))
        e.board.piles[0].cards = [carrierTop]
        e.debug.setNextCardObj(DeckManager.toCard(specs[i], data: data))
        let before = e.deck.remaining()
        e.guess(0, .higher)
        XCTAssertEqual(e.deck.remaining(), before - 1 - 1, "one draw + one burial")
        XCTAssertEqual(e.board.piles[0].cards.count, 3, "the buried card sits UNDER the pile")
        XCTAssertEqual(e.board.piles[0].cards.last?.value, 10, "the landing card is still the top")
    }

    func testQuickBuryDoesNotFireWhenTheCarrierItselfLands() {
        // Regression (v6.75, the reported bug): a DRAWN carrier landing
        // CORRECTLY must NOT bury — the trigger is the NEXT landing on it.
        var specs = DeckManager.buildStandardDeck()
        let i = specs.firstIndex { $0.suit == "♦" && $0.currentRank == 10 }!
        specs[i].stickers.append(StickerRecord(type: "quickBury"))
        let e = engine(specs: specs)
        e.board.piles[0].cards = [DeckManager.cardForValue(4)]
        e.debug.setNextCardObj(DeckManager.toCard(specs[i], data: data))
        let before = e.deck.remaining()
        e.guess(0, .higher)
        XCTAssertEqual(e.deck.remaining(), before - 1, "the carrier's own landing buries nothing")
        XCTAssertEqual(e.board.piles[0].cards.count, 2, "just the landing")
        // …and the NEXT card landing on the carrier (now the top) fires it.
        let k = specs.firstIndex { $0.suit == "♠" && $0.currentRank == 13 }!
        e.debug.setNextCardObj(DeckManager.toCard(specs[k], data: data))
        e.guess(0, .higher)                                   // K on 10 → correct
        XCTAssertEqual(e.board.piles[0].cards.count, 4, "the next landing on the carrier fires it (+1 buried)")
        XCTAssertEqual(e.board.piles[0].cards.last?.value, 13, "the second landing is the top")
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

    // MARK: - Snobs, both directions (v6.51)

    /// A snob on the DRAWN card fires when the pile it lands on is topped by
    /// the snob's suit — the reverse of the classic direction.
    func testHeartSnobReversePaysWhenDrawnCardCarriesIt() {
        let hv = data.stickerTypes.get("heartSnob")?.num("value", 4) ?? 4
        var specs = DeckManager.buildStandardDeck()
        let i = specs.firstIndex { $0.suit == "♠" && $0.currentRank == 9 }!
        specs[i].stickers.append(StickerRecord(type: "heartSnob"))
        let e = engine(specs: specs)
        e.board.piles[0].cards = [LiveCard(id: 901, label: "5", value: 5, suit: "♥", red: true)]
        e.debug.setNextCardObj(DeckManager.toCard(specs[i], data: data))
        e.guess(0, .higher)                               // 9♠ lands on the ♥ top
        XCTAssertEqual(e.run.bonusCoins, hv, "the drawn card's own snob fires on a ♥ top")
    }

    func testSuitSnobReversePeeksAndClubSnobReverseBuries() {
        let dig = data.stickerTypes.get("clubSnob")?.int("digCount", 1) ?? 1
        // suitSnob carried by the drawn card, landing on a ♠ top → peek.
        var specs = DeckManager.buildStandardDeck()
        let i = specs.firstIndex { $0.suit == "♦" && $0.currentRank == 9 }!
        specs[i].stickers.append(StickerRecord(type: "suitSnob"))
        let e = engine(specs: specs)
        e.board.piles[0].cards = [LiveCard(id: 902, label: "5", value: 5, suit: "♠", red: false)]
        e.debug.setNextCardObj(DeckManager.toCard(specs[i], data: data))
        e.guess(0, .higher)
        XCTAssertTrue(e.run.revealNextActive, "the drawn suitSnob peeks on a ♠ top")

        // clubSnob carried by the drawn card, landing on a ♣ top → bury.
        var specs2 = DeckManager.buildStandardDeck()
        let j = specs2.firstIndex { $0.suit == "♦" && $0.currentRank == 9 }!
        specs2[j].stickers.append(StickerRecord(type: "clubSnob"))
        let e2 = engine(specs: specs2)
        e2.board.piles[0].cards = [LiveCard(id: 903, label: "5", value: 5, suit: "♣", red: false)]
        let before = e2.board.piles[0].cards.count
        e2.debug.setNextCardObj(DeckManager.toCard(specs2[j], data: data))
        e2.guess(0, .higher)
        XCTAssertEqual(e2.board.piles[0].cards.count, before + 1 + dig,
                       "the drawn clubSnob buries under its landing pile on a ♣ top")
    }

    func testDiamondSnobReverseShufflesWithoutMovingCards() {
        var specs = DeckManager.buildStandardDeck()
        let i = specs.firstIndex { $0.suit == "♣" && $0.currentRank == 9 }!
        specs[i].stickers.append(StickerRecord(type: "diamondSnob"))
        let e = engine(specs: specs)
        e.board.piles[0].cards = [LiveCard(id: 904, label: "5", value: 5, suit: "♦", red: true)]
        e.board.piles[1].cards = [LiveCard(id: 905, label: "6", value: 6, suit: "♦", red: true)]
        let counts = (0..<e.board.size).map { e.board.piles[$0].cards.count }
        e.debug.setNextCardObj(DeckManager.toCard(specs[i], data: data))
        e.guess(0, .higher)                               // 9♣ lands on a ♦ top
        XCTAssertEqual(e.run.bonusCoins, 0, "a shuffle pays nothing")
        var after = counts
        after[0] += 1                                     // only the landing adds a card
        XCTAssertEqual((0..<e.board.size).map { e.board.piles[$0].cards.count }, after,
                       "the shuffle moves no cards between piles")
    }

    func testSnobBothDirectionsFireOnOnePlacement() {
        // A ♥ carrying heartSnob lands on a ♥ top ALSO carrying heartSnob:
        // the top's snob fires (a matching-suit card landed on it) AND the
        // drawn card's snob fires (it landed on a matching-suit top).
        let hv = data.stickerTypes.get("heartSnob")?.num("value", 4) ?? 4
        var specs = DeckManager.buildStandardDeck()
        let i = specs.firstIndex { $0.suit == "♥" && $0.currentRank == 9 }!
        specs[i].stickers.append(StickerRecord(type: "heartSnob"))
        let e = engine(specs: specs)
        let top = LiveCard(id: 906, label: "5", value: 5, suit: "♥", red: true)
        top.stickers = [StickerRecord(type: "heartSnob")]
        e.board.piles[0].cards = [top]
        e.debug.setNextCardObj(DeckManager.toCard(specs[i], data: data))
        e.guess(0, .higher)
        XCTAssertEqual(e.run.bonusCoins, hv * 2, "both directions pay on one placement")
    }

    func testSnobReverseIgnoresAnOffSuitTop() {
        var specs = DeckManager.buildStandardDeck()
        let i = specs.firstIndex { $0.suit == "♠" && $0.currentRank == 9 }!
        specs[i].stickers.append(StickerRecord(type: "heartSnob"))
        let e = engine(specs: specs)
        e.board.piles[0].cards = [LiveCard(id: 907, label: "5", value: 5, suit: "♠", red: false)]
        e.debug.setNextCardObj(DeckManager.toCard(specs[i], data: data))
        e.guess(0, .higher)
        XCTAssertEqual(e.run.bonusCoins, 0, "a ♠ top is no ♥ top — the drawn snob stays quiet")
        XCTAssertFalse(e.run.revealNextActive)
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
        // v6.65: the column-survival clause is gone — a dead pile doesn't void it.
        solo.board.kill(0)
        XCTAssertEqual(solo.pillarPayout().lines.filter { $0.label == g.label }.count, 1,
                       "a dead pile in Greedy's column no longer voids it")
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

    /// v5.74 deleted the dead Pillar effect paths (echo, symmetryRight,
    /// stickerCount, unearth, sameSpark) from both engines. Nothing may
    /// re-introduce a dispatch for an effect no items.js entry carries —
    /// a dead branch is unreachable code that silently rots.
    func testNoPillarDispatchesAnEffectTheDataFileDoesNotShip() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let src = try String(contentsOf: root.appendingPathComponent("GameCore/GameEngineEffects.swift"), encoding: .utf8)
            + (try String(contentsOf: root.appendingPathComponent("GameCore/GameEngine.swift"), encoding: .utf8))
        let shipped = Set(data.items.pillars.compactMap(\.effect))
        for dead in ["echo", "symmetryRight", "stickerCount", "unearth", "sameSpark"] {
            XCTAssertFalse(shipped.contains(dead), "'\(dead)' is back in items.js — re-add its dispatch too")
            XCTAssertFalse(src.contains("\"\(dead)\""), "GameCore still dispatches the removed effect '\(dead)'")
        }
        // The item ID `stickerCount` is LIVE (label "Massive Diamond") — only the
        // dead EFFECT of that name went. Guard against over-deleting it.
        XCTAssertNotNil(data.pillarTypes.get("stickerCount"), "the stickerCount ITEM must survive")
        XCTAssertEqual(data.pillarTypes.get("stickerCount")?.effect, "heavyDiamond")
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

    /// The UI contract: exactly these Bases need the player to pick something.
    /// Sticker Harvest and Demolish were unreachable on native for a whole
    /// release because the tap path fired them with no target and
    /// `baseActivate` silently returned nil (v5.83). If a new Base gains a
    /// `target`, this test fails so its picker gets wired too.
    /// (v6.51: Demolish lost its `target` — it now destroys its OWN column's
    /// pillar, no picker.)
    func testOnlyTheseBasesRequireAPlayerChosenTarget() {
        let targeted = data.items.bases.filter { $0.target != nil }
            .map { "\($0.id):\($0.target ?? "")" }.sorted()
        // v6.76: Sacrifice and Diamond Boost join Sticker Harvest as
        // pile-target Bases — their pickers wire in DealController with the
        // batch's UI pass. Devil's Deal carries NO target: its curse lands on
        // a seeded in-column pick.
        XCTAssertEqual(targeted, ["diamondBoost:pile", "sacrifice:pile", "stickerHarvest:pile"],
                       "a Base with a target needs a picker in DealController.basePlaqueTapped")
    }

    /// A targeted Base fires with a target and REFUSES without one — the exact
    /// asymmetry the broken confirm path fell into.
    func testATargetedBaseRefusesToFireWithoutATarget() {
        // Only `target == "pile"` bases still take a target — Demolish kept its
        // data field but went own-column in v6.51 (its picker path is gone).
        for b in data.items.bases where b.target == "pile" {
            let e = engine(pillars: ["columnGuardian", nil, nil], bases: [b.id, nil, nil], seed: 6161)
            guard e.baseAvailable(0) else { continue }
            XCTAssertNil(e.baseActivate(col: 0, targetIndex: nil),
                         "\(b.id): must not fire without the target it declares")
            XCTAssertTrue(e.baseCharged(0), "\(b.id): a refused activation keeps its charge")
        }
    }

    /// Phoenix carries NO target: it picks a dead pile in its own column by
    /// itself. Native had invented a pile picker for it that offered dead piles
    /// board-wide, so a tap outside the column appeared to do nothing.
    func testPhoenixRevivesWithoutAnyPlayerTarget() {
        guard let b = data.items.bases.first(where: { $0.effect == "reviveBase" }) else {
            XCTFail("need a reviveBase base"); return
        }
        XCTAssertNil(b.target, "Phoenix must not declare a target — it auto-picks")
        let e = engine(bases: [b.id, nil, nil], seed: 6161)
        // Kill a pile in Phoenix's own column so the precondition holds.
        guard let victim = (0..<e.board.size).first(where: { e.run.pileColumns?[$0] == 0 }) else {
            XCTFail("no pile in column 0"); return
        }
        e.board.kill(victim)
        XCTAssertTrue(e.baseAvailable(0), "a dead pile in its column arms Phoenix")
        XCTAssertNotNil(e.baseActivate(col: 0, targetIndex: nil),
                        "Phoenix fires on a plain confirm, no target needed")
        XCTAssertTrue(e.board.isActive(victim), "the dead pile in its column came back")
    }

    /// BURROW + SECOND SIGHT roll a CLIMB-FIXED variant (v6.38): a suit for
    /// Burrow, red-or-black for Second Sight. The roll is a pure function of
    /// the run seed, so it is identical whenever the item appears this climb,
    /// and the engine filters its targets by it.
    func testVariantPowersRollPerClimbAndFilterTheirTargets() {
        // The variant is deterministic per seed and in-domain.
        let c = CampaignState()
        c.setDeck("pink"); c.setSeedOverride(9090); c.reset()
        let c2 = CampaignState()
        c2.setDeck("pink"); c2.setSeedOverride(9090); c2.reset()
        let suit = c.samePowerVariant("linkBury")
        XCTAssertEqual(suit, c2.samePowerVariant("linkBury"), "same climb, same roll")
        XCTAssertTrue(["♠", "♥", "♦", "♣"].contains(suit ?? ""), "Burrow rolls a real suit")
        let colour = c.samePowerVariant("linkTell")
        XCTAssertEqual(colour, c2.samePowerVariant("linkTell"))
        XCTAssertTrue(["red", "black"].contains(colour ?? ""), "Second Sight rolls a colour")
        XCTAssertNil(c.samePowerVariant("linkCoins"), "fixed powers roll nothing")
        // …and the substituted description names it (no leaked template).
        if let def = data.items.samePowers.first(where: { $0.id == "linkBury" }), let suit {
            XCTAssertTrue(c.itemDescription(def).contains(suit))
            XCTAssertFalse(c.itemDescription(def).contains("{suit}"))
        }
        // ENGINE: Burrow buries only under alive piles wearing the suit.
        let e = GameEngine(deckSpecs: DeckManager.buildStandardDeck(), pileCount: 9,
                           runConfig: RunConfig(cols: [3, 3, 3], samePower: "linkBury",
                                                samePowerVariant: "♠"))
        e.start(seedOverride: 777)
        e.startRun(pillars: [nil, nil, nil], bases: [nil, nil, nil], samePower: .some("linkBury"))
        var fired: SamePowerResult?
        e.on { if case .samePower(let r) = $0 { fired = r } }
        e.debugFireSamePower(0)
        guard let res = fired else { XCTFail("Burrow did not fire"); return }
        let spadeTops = (0..<9).filter { e.board.isActive($0) && e.board.top($0)?.suit == "♠" }
        XCTAssertEqual(Set(res.targets), Set(spadeTops),
                       "Burrow's targets are exactly the ♠-topped alive piles")
        // Second Sight counts only the rolled colour's piles.
        let e2 = GameEngine(deckSpecs: DeckManager.buildStandardDeck(), pileCount: 9,
                            runConfig: RunConfig(cols: [3, 3, 3], samePower: "linkTell",
                                                 samePowerVariant: "red"))
        e2.start(seedOverride: 777)
        e2.startRun(pillars: [nil, nil, nil], bases: [nil, nil, nil], samePower: .some("linkTell"))
        var fired2: SamePowerResult?
        e2.on { if case .samePower(let r) = $0 { fired2 = r } }
        e2.debugFireSamePower(0)
        guard let res2 = fired2 else { XCTFail("Second Sight did not fire"); return }
        let redTops = (0..<9).filter { j in
            guard e2.board.isActive(j), let t = e2.board.top(j) else { return false }
            return t.suit == "♥" || t.suit == "♦"
        }
        XCTAssertEqual(Set(res2.targets), Set(redTops),
                       "Second Sight counts exactly the red-topped alive piles")
        // v6.58: Second Sight rides its own window — the count still comes
        // from the red-topped piles, but the DISPLAY anchors to the most
        // recently landed top card, not the counted set.
        XCTAssertEqual(e2.run.sightDrawsLeft, redTops.count)
        XCTAssertEqual(e2.run.tellDrawsLeft, 0, "Second Sight no longer rides the whisper window")
    }

    /// SECOND SIGHT (v6.58): during the window the hint shows ONLY on the
    /// pile that most recently landed a living top card — a correct landing
    /// moves the hint, a fatal landing clears it, and no other pile ever
    /// hints (the batch-4 "tell shows on every pile" bug).
    func testSecondSightHintsOnlyOnLastLandedPile() {
        let e = IV.engine(tops: [IV.spec(1, 5, "♥"), IV.spec(2, 8, "♥"), IV.spec(3, 6, "♥")],
                          deckOrder: [IV.spec(50, 9), IV.spec(51, 3), IV.spec(52, 12), IV.spec(53, 4)],
                          samePower: "linkTell", samePowerVariant: "red")
        e.debugFireSamePower(0)
        XCTAssertEqual(e.run.sightDrawsLeft, 3, "three red tops bought three sighted draws")
        XCTAssertNil(e.run.lastLandedPile, "nothing has landed yet — nowhere to hint")
        XCTAssertTrue((0..<3).allSatisfy { e.pileHint($0) == nil },
                      "the window alone lights NO pile")
        e.guess(0, .higher)                       // 9 on 5 — lands correctly
        XCTAssertEqual(e.run.lastLandedPile, 0)
        XCTAssertNotNil(e.pileHint(0), "the just-landed pile hints")
        XCTAssertNil(e.pileHint(1), "no other pile hints")
        XCTAssertNil(e.pileHint(2), "no other pile hints")
        e.guess(1, .higher)                       // 3 on 8 — fatal
        XCTAssertNil(e.run.lastLandedPile, "the landed top died with its pile")
        XCTAssertTrue((0..<3).allSatisfy { e.pileHint($0) == nil },
                      "a death shows no hint anywhere")
        e.guess(2, .higher)                       // 12 on 6 — lands correctly
        XCTAssertEqual(e.run.lastLandedPile, 2)
        XCTAssertNil(e.pileHint(2), "the window (3 draws) is spent — no hint")
    }

    /// THE SIX SHOP ITEMS (router batch 3). Bulk Rate flattens the Purge
    /// ladder; Freebie gifts one deterministic slot; Rare Hunter doubles the
    /// rare weight; Last Resort ends the deal as a NORMAL win; Empty Purse
    /// peeks for everything; Same Tell answers exactly one question.
    func testBulkRateFlattensThePurgeLadderAndSurvivesASave() {
        let c = CampaignState()
        c.setDeck("pink"); c.setSeedOverride(7171); c.reset()
        c.addCoins(500)
        let base = Int(c.removalPrice())
        _ = c.buyRemoval(c.getRunDeck().first!.id)
        let stepFull = Int(c.removalPrice()) - base
        XCTAssertEqual(stepFull, 2, "the naked ladder climbs by priceStep (2)")
        guard let def = data.items.pillars.first(where: { $0.effect == "purgeStepDiscount" }) else {
            return XCTFail("no Bulk Rate in the registry")
        }
        c.setColumnPillar(col: 0, typeId: def.id)
        let discounted = Int(c.removalPrice())
        XCTAssertEqual(discounted, base + 1, "equipped, the climb is 1 less per purchase")
        // Save/restore: derived pricing, identical after a round trip.
        let c2 = CampaignState()
        XCTAssertTrue(c2.restore(c.serialize()))
        XCTAssertEqual(Int(c2.removalPrice()), discounted)
        // Unequip → the full ladder returns instantly.
        c.setColumnPillar(col: 0, typeId: nil)
        XCTAssertEqual(Int(c.removalPrice()), base + stepFull)
    }

    func testFreebieGiftsExactlyOneSlotDeterministically() {
        guard let def = data.items.pillars.first(where: { $0.effect == "freebie" }) else {
            return XCTFail("no Freebie in the registry")
        }
        func campaignWithFreebie() -> CampaignState {
            let c = CampaignState()
            c.setDeck("pink"); c.setSeedOverride(8181); c.reset()
            c.setColumnPillar(col: 0, typeId: def.id)
            if let first = c.legalNextNodes().first { c.moveToNode(first.id) }
            return c
        }
        let a = campaignWithFreebie(), b = campaignWithFreebie()
        let oa = a.openStore(), ob = b.openStore()
        XCTAssertNotNil(oa.freeSlot, "one slot is gifted")
        XCTAssertEqual(oa.freeSlot, ob.freeSlot, "same seed, same gift")
        XCTAssertEqual(a.priceOfMixed(oa.freeSlot!), 0, "the gifted slot costs 0")
        XCTAssertNotEqual(oa.slots[oa.freeSlot!]?.kind, "removal", "the Purge slot is never the gift")
        // The gift survives a mid-visit save.
        let a2 = CampaignState()
        XCTAssertTrue(a2.restore(a.serialize()))
        XCTAssertEqual(a2.getStoreOffer()?.freeSlot, oa.freeSlot)
        // Without the pillar: no gift.
        let plain = CampaignState()
        plain.setDeck("pink"); plain.setSeedOverride(8181); plain.reset()
        if let first = plain.legalNextNodes().first { plain.moveToNode(first.id) }
        XCTAssertNil(plain.openStore().freeSlot)
    }

    func testRareHunterDoublesOnlyTheRareWeight() {
        guard let def = data.items.pillars.first(where: { $0.effect == "rareHunter" }) else {
            return XCTFail("no Rare Hunter in the registry")
        }
        let c = CampaignState()
        c.setDeck("pink"); c.setSeedOverride(1); c.reset()
        let before = c.effectiveTierWeights()
        XCTAssertEqual(before, data.items.store.tierWeights, "unequipped: stock weights")
        c.setColumnPillar(col: 0, typeId: def.id)
        let after = c.effectiveTierWeights()
        XCTAssertEqual(after["rare"], (data.items.store.tierWeights["rare"] ?? 0) * 2)
        XCTAssertEqual(after["common"], data.items.store.tierWeights["common"])
        XCTAssertEqual(after["uncommon"], data.items.store.tierWeights["uncommon"])
    }

    func testLastResortWinsInstantlyAndScoresLikeANormalWin() {
        let e = GameEngine(deckSpecs: DeckManager.buildStandardDeck(), pileCount: 9,
                           runConfig: RunConfig(cols: [3, 3, 3]))
        e.start(seedOverride: 4242)
        e.startRun(pillars: [nil, nil, nil], bases: ["lastResort", nil, nil], samePower: nil)
        XCTAssertTrue(e.baseAvailable(0))
        let before = e.deck.remaining()
        XCTAssertGreaterThan(before, 0)
        guard let res = e.baseActivate(col: 0, targetIndex: nil) else {
            return XCTFail("Last Resort did not fire")
        }
        XCTAssertEqual(res.buried, before, "the WHOLE remaining deck went under")
        XCTAssertEqual(e.deck.remaining(), 0)
        XCTAssertEqual(e.status, "won", "an empty deck through the normal end check = a win")
        // SCORING UNCHANGED: alive piles × smallest, on the final board.
        let expected = e.board.aliveCount() * e.board.minAliveCards()
        print("LAST-RESORT-SAMPLE score=\(expected) alive=\(e.board.aliveCount()) min=\(e.board.minAliveCards()) buried=\(before)")
        XCTAssertGreaterThan(expected, 0)
        // …and it is SEALED in a boss deal.
        let boss = GameEngine(deckSpecs: DeckManager.buildStandardDeck(), pileCount: 9,
                              runConfig: RunConfig(cols: [3, 3, 3], isBoss: true))
        boss.start(seedOverride: 4242)
        boss.startRun(pillars: [nil, nil, nil], bases: ["lastResort", nil, nil], samePower: nil)
        XCTAssertFalse(boss.baseAvailable(0), "never in a boss deal")
    }

    func testEmptyPurseAndSameTell() {
        // Empty Purse (v6.74 rework): 1 peek BASELINE + 1 more per 10 coins
        // in the purse — 0 coins still peeks 1. The purse is threaded in by
        // the caller (`purseCoins`) and drained from `res.purseSpent`.
        for (coins, want) in [(0, 1), (9, 1), (10, 2), (25, 3)] {
            let e = GameEngine(deckSpecs: DeckManager.buildStandardDeck(), pileCount: 9,
                               runConfig: RunConfig(cols: [3, 3, 3]))
            e.start(seedOverride: 999)
            e.startRun(pillars: [nil, nil, nil], bases: ["emptyPurse", nil, nil], samePower: nil)
            XCTAssertTrue(e.baseAvailable(0), "no coin minimum — it fires broke too")
            let res = e.baseActivate(col: 0, targetIndex: nil, purseCoins: coins)
            XCTAssertEqual(res?.peekCount, want, "\(coins) coins → \(want) peek(s)")
            XCTAssertEqual(res?.cards?.count, want, "\(coins) coins: the peek snapshot")
            XCTAssertEqual(res?.purseSpent, coins, "\(coins) coins: the result reports the exact spend")
            XCTAssertGreaterThanOrEqual(e.run.kamikazeRevealLeft, want,
                                        "\(coins) coins: the peek window is armed")
        }
        // …and the purse EMPTIES: the flow drains exactly res.purseSpent
        // (DealController's spend path — the same contract the web's
        // "base-fired" handler runs).
        let c = CampaignState()
        _ = c.earnCoins(25)
        let e = GameEngine(deckSpecs: DeckManager.buildStandardDeck(), pileCount: 9,
                           runConfig: RunConfig(cols: [3, 3, 3]))
        e.start(seedOverride: 999)
        e.startRun(pillars: [nil, nil, nil], bases: ["emptyPurse", nil, nil], samePower: nil)
        let res = e.baseActivate(col: 0, targetIndex: nil, purseCoins: c.getCoins())
        XCTAssertEqual(res?.purseSpent, 25)
        XCTAssertTrue(c.spendCoins(res?.purseSpent ?? 0), "the drain succeeds")
        XCTAssertEqual(c.getCoins(), 0, "every coin spent")
        // Same Tell: the = mark only on a genuine rank match, board-wide (v6.62).
        let e2 = GameEngine(deckSpecs: DeckManager.buildStandardDeck(), pileCount: 9,
                            runConfig: RunConfig(cols: [3, 3, 3]))
        e2.start(seedOverride: 424242)
        e2.startRun(pillars: [nil, nil, nil], bases: ["sameTell", nil, nil], samePower: nil)
        guard let next = e2.deck.peek(1).first else { return XCTFail("empty deck") }
        let alivePiles = (0..<9).filter { e2.board.isActive($0) }
        let hasMatch = alivePiles.contains { e2.board.top($0)?.value == next.value && e2.board.top($0)?.joker == false }
        let res2 = e2.baseActivate(col: 0, targetIndex: nil)
        if hasMatch {
            XCTAssertEqual(res2?.tellDirection, .same, "a match gets the = mark")
            XCTAssertNotNil(res2?.tellPile)
            XCTAssertEqual(e2.pileHint(res2!.tellPile!), .same, "the marked pile shows =")
        } else {
            XCTAssertNil(res2?.tellPile, "no match, no word")
        }
    }

    /// STICKER SPRAY hits the CALLED pile's whole column, and reports every
    /// sticker so the flow can write it onto the campaign card — without that
    /// report the stickers lasted exactly one deal.
    func testStickerSpraySpraysTheColumnAndReportsForPersistence() {
        guard let def = data.items.samePowers.first(where: { $0.effect == "linkSticker" }) else {
            XCTFail("no linkSticker same-power in the registry"); return
        }
        let e = GameEngine(deckSpecs: DeckManager.buildStandardDeck(), pileCount: 9,
                           runConfig: RunConfig(cols: [3, 3, 3], samePower: def.id))
        e.start()
        e.startRun(pillars: [nil, nil, nil], bases: [nil, nil, nil], samePower: .some(def.id))
        var fired: SamePowerResult?
        e.on { if case .samePower(let r) = $0 { fired = r } }
        // Fire it on a pile in column 1.
        guard let hub = (0..<9).first(where: { e.run.pileColumns?[$0] == 1 }) else {
            XCTFail("no pile in column 1"); return
        }
        e.debugFireSamePower(hub)
        guard let res = fired else { XCTFail("the power did not fire"); return }
        // Every target is in the SAME column as the pile it was called on.
        for t in res.targets {
            XCTAssertEqual(e.run.pileColumns?[t], 1, "pile \(t) is outside the called column")
        }
        XCTAssertFalse(res.targets.isEmpty, "a live column gets sprayed")
        // …and each one is reported for the durable write.
        XCTAssertEqual(res.stickersApplied.count, res.targets.count,
                       "every sprayed sticker is reported so it can be persisted")
        for s in res.stickersApplied {
            XCTAssertFalse(s.typeId.isEmpty)
            XCTAssertTrue(e.board.piles.contains { $0.cards.contains { $0.id == s.cardId } },
                          "the reported card is a real board card")
        }
    }

    /// ESCAPE HATCH: usable ONLY in an ambush, and it ends the deal in a win.
    func testEscapeHatchOnlyFiresInAnAmbushAndClearsIt() {
        guard let def = data.items.bases.first(where: { $0.effect == "ambushWin" }) else {
            XCTFail("no ambushWin base in the registry"); return
        }
        // An ORDINARY deal: charged, but it can never fire.
        let plain = GameEngine(deckSpecs: DeckManager.buildStandardDeck(), pileCount: 9,
                               runConfig: RunConfig(cols: [3, 3, 3]))
        plain.start()
        plain.startRun(pillars: [nil, nil, nil], bases: [def.id, nil, nil], samePower: .some(nil))
        XCTAssertTrue(plain.baseCharged(0), "it is charged like any Base")
        XCTAssertFalse(plain.baseAvailable(0), "…but never usable outside an ambush")
        XCTAssertNil(plain.baseActivate(col: 0), "…and refuses to fire")

        // An AMBUSH: it fires, and the deal is won on the spot.
        let ambush = GameEngine(deckSpecs: DeckManager.buildStandardDeck(), pileCount: 9,
                                runConfig: RunConfig(cols: [3, 3, 3], isAmbush: true))
        ambush.start()
        ambush.startRun(pillars: [nil, nil, nil], bases: [def.id, nil, nil], samePower: .some(nil))
        XCTAssertTrue(ambush.baseAvailable(0), "an ambush arms it")
        XCTAssertNotNil(ambush.baseActivate(col: 0))
        XCTAssertEqual(ambush.status, "won", "it clears the deal outright")
        XCTAssertTrue(ambush.deck.isEmpty, "…through the engine's own win path")
    }

    /// LAST LICKS: the mirror of Guardian — it pays only when the column is
    /// WIPED OUT, and pays nothing while a single pile still stands.
    func testLastLicksPaysOnlyOnAWipedColumn() {
        guard let def = data.items.pillars.first(where: { $0.effect == "columnNoneAlive" }) else {
            XCTFail("no columnNoneAlive pillar in the registry"); return
        }
        let e = GameEngine(deckSpecs: DeckManager.buildStandardDeck(), pileCount: 9,
                           runConfig: RunConfig(cols: [3, 3, 3]))
        e.start()
        e.startRun(pillars: [def.id, nil, nil], bases: [nil, nil, nil], samePower: .some(nil))
        let colPiles = (0..<9).filter { e.run.pileColumns?[$0] == 0 }
        XCTAssertEqual(colPiles.count, 3)
        // All alive → nothing.
        XCTAssertEqual(e.pillarPayout().bonus, 0, "a living column pays nothing")
        // Kill all but one → still nothing.
        for i in colPiles.dropLast() { e.board.kill(i) }
        XCTAssertEqual(e.pillarPayout().bonus, 0, "one survivor is still a survivor")
        // Kill the last → it pays.
        e.board.kill(colPiles.last!)
        XCTAssertEqual(e.pillarPayout().bonus, def.value, "a wiped column pays \(def.value)")
    }

    /// FOURTH SEAT: its column always opens the deal with `value` piles. The
    /// normal 3-way split runs first, so it only ever ADDS seats.
    func testFourthSeatWidensOnlyItsOwnColumn() {
        guard let def = data.items.pillars.first(where: { $0.effect == "columnPiles" }) else {
            XCTFail("no columnPiles pillar in the registry"); return
        }
        let want = Int(def.value)
        for piles in [3, 6, 9, 12] {
            let plain = CampaignLayout.layoutForPiles(piles)
            for col in 0..<CampaignLayout.columnSlots {
                var equipped = [String?](repeating: nil, count: CampaignLayout.columnSlots)
                equipped[col] = def.id
                let wide = CampaignLayout.layoutForPiles(piles, pillars: equipped)
                guard col < plain.cols.count else { continue }
                // FOURTH SEAT adds ONE seat, capped at `want` — it no longer
                // forces the column straight to the cap.
                XCTAssertEqual(wide.cols[col], min(want, plain.cols[col] + 1),
                               "\(piles) piles, col \(col): the seated column gains one, capped at \(want)")
                for other in 0..<wide.cols.count where other != col {
                    XCTAssertEqual(wide.cols[other], plain.cols[other],
                                   "\(piles) piles: col \(other) must be untouched")
                }
                XCTAssertEqual(wide.piles, wide.cols.reduce(0, +), "the total counts the real seats")
                XCTAssertGreaterThanOrEqual(wide.piles, plain.piles, "it never removes a pile")
            }
        }
    }

    func testFourthSeatNeverShrinksAnAlreadyWiderColumn() {
        guard let def = data.items.pillars.first(where: { $0.effect == "columnPiles" }) else { return }
        // 15 piles splits 5/5/5 — already wider than 4.
        var equipped = [String?](repeating: nil, count: CampaignLayout.columnSlots)
        equipped[0] = def.id
        let plain = CampaignLayout.layoutForPiles(15)
        let wide = CampaignLayout.layoutForPiles(15, pillars: equipped)
        XCTAssertEqual(wide.cols, plain.cols, "a column already past the floor is left alone")
    }

    /// The board and the engine must agree on WHICH column got the extra pile.
    /// Re-deriving the split from the pile count alone is not equivalent once a
    /// Pillar can widen a column: 10 piles re-derives to [3,4,3] while the
    /// engine holds [4,3,3], so the board drew the fourth pile in the wrong
    /// column and its Pillar plaque pointed at the wrong stack.
    func testAWidenedLayoutIsNotRecoverableFromThePileCount() {
        guard let def = data.items.pillars.first(where: { $0.effect == "columnPiles" }) else { return }
        var equipped = [String?](repeating: nil, count: CampaignLayout.columnSlots)
        equipped[0] = def.id
        let wide = CampaignLayout.layoutForPiles(9, pillars: equipped)
        XCTAssertEqual(wide.cols, [4, 3, 3])   // 3 → 4, one seat, at the cap
        XCTAssertEqual(wide.piles, 10)
        // The trap: same total, different shape.
        XCTAssertNotEqual(CampaignLayout.layoutForPiles(wide.piles).cols, wide.cols,
                          "if these ever match, this test has stopped proving anything")
        // And the pile→column map must follow the REAL split.
        let map = GameEngine.buildPileColumns(wide.cols, wide.piles)
        XCTAssertEqual(map.filter { $0 == 0 }.count, 4, "column 0 owns four piles")
        XCTAssertEqual(map.filter { $0 == 1 }.count, 3)
        XCTAssertEqual(map.filter { $0 == 2 }.count, 3)
    }

    func testALayoutWithNoPillarsIsUnchanged() {
        for piles in [1, 2, 3, 5, 9, 12] {
            let none = [String?](repeating: nil, count: CampaignLayout.columnSlots)
            XCTAssertEqual(CampaignLayout.layoutForPiles(piles, pillars: none).cols,
                           CampaignLayout.layoutForPiles(piles).cols,
                           "\(piles): no pillars must mean the untouched split")
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

    /// The store card slot's OWN odds table (store.card.stickerOdds): every
    /// band returns its row's count, a roll past the last cap returns 0, and
    /// the shipped table is the designed 1% → 3, 5% → 2, 25% → 1.
    func testStoreCardStickerOddsTable() {
        let odds = data.items.store.card.stickerOdds
        XCTAssertFalse(odds.isEmpty, "store.card.stickerOdds must ship")
        for (i, row) in odds.enumerated() {
            let inBand = i == 0 ? row[0] / 2 : (odds[i - 1][0] + row[0]) / 2
            XCTAssertEqual(StoreRoll.stickerCount(inBand, odds: odds), Int(row[1]),
                           "band \(i) must return its own count")
        }
        XCTAssertEqual(StoreRoll.stickerCount(0.999999, odds: odds), 0, "past every maxRoll → 0 stickers")
    }
}
