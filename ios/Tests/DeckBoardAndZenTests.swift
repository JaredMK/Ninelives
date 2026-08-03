import XCTest
@testable import GameCore

/// Deck / board mechanics, Zen configuration, seed codes and map traversal.
final class DeckBoardAndZenTests: XCTestCase {
    private let data = GameData.shared

    // MARK: - Deck construction

    func testStandardDeckIsFiftyTwoStableIdentities() {
        let deck = DeckManager.buildStandardDeck()
        XCTAssertEqual(deck.count, 52)
        XCTAssertEqual(Set(deck.map(\.id)).count, 52, "ids are stable and unique")
        XCTAssertEqual(deck.map(\.id), Array(0..<52), "ids 0..51, in suit-then-rank order")
        for c in deck {
            XCTAssertEqual(c.originalRank, c.currentRank, "a fresh deck is unmodified")
            XCTAssertTrue(c.stickers.isEmpty)
            XCTAssertTrue(c.modifications.isEmpty)
        }
        for s in DeckManager.suits {
            XCTAssertEqual(deck.filter { $0.suit == s.symbol }.count, 13, "13 of \(s.symbol)")
        }
    }

    func testSuitOrderIsTheStageIntroductionSchedule() {
        // Stage 1 = ♦+♥, Stage 2 adds ♣, Stage 3 adds ♠.
        XCTAssertEqual(DeckManager.suits.map(\.symbol), ["♦", "♥", "♣", "♠"])
        XCTAssertEqual(CampaignLayout.suitsForStage(1), ["♦", "♥"])
        XCTAssertEqual(CampaignLayout.suitsForStage(2), ["♦", "♥", "♣"])
        XCTAssertEqual(CampaignLayout.suitsForStage(3), ["♦", "♥", "♣", "♠"])
        XCTAssertTrue(DeckManager.suits[0].red)
        XCTAssertTrue(DeckManager.suits[1].red)
        XCTAssertFalse(DeckManager.suits[2].red)
        XCTAssertFalse(DeckManager.suits[3].red)
    }

    func testZenDecksSliceTheZenSuitOrder() {
        XCTAssertEqual(DeckManager.zenSuitOrder, ["♥", "♠", "♦", "♣"], "Zen's own order — Easy reads red-vs-black")
        for n in 1...4 {
            let deck = DeckManager.buildZenDeck(suitCount: n)
            XCTAssertEqual(deck.count, n * 13, "suitCount × 13 cards")
            XCTAssertEqual(Set(deck.map(\.suit)), Set(DeckManager.zenSuitOrder.prefix(n)))
            XCTAssertFalse(deck.contains { $0.joker || $0.blank }, "never a joker")
            XCTAssertTrue(deck.allSatisfy { $0.stickers.isEmpty }, "never a sticker")
        }
        XCTAssertEqual(DeckManager.buildZenDeck(suitCount: 0).count, 13, "clamped to ≥1")
        XCTAssertEqual(DeckManager.buildZenDeck(suitCount: 9).count, 52, "clamped to ≤4")
    }

    func testZenConfigIsDataDriven() {
        for id in DifficultyData.zenIds {
            let z = data.difficulty.zen(id)
            XCTAssertEqual(z.id, id)
            XCTAssertFalse(z.label.isEmpty)
            XCTAssertTrue((1...4).contains(z.suitCount))
            XCTAssertGreaterThan(z.piles, 0)
        }
        XCTAssertEqual(data.difficulty.zen("nonsense").id, "easy", "unknown ids fall back to Easy")
        // Harder difficulties use more of the deck.
        XCTAssertLessThanOrEqual(data.difficulty.zen("easy").suitCount, data.difficulty.zen("hard").suitCount)
    }

    // MARK: - Deck mechanics

    func testDrawFromTopAndBottomBothCount() {
        let deck = DeckManager.create(DeckManager.buildStandardDeck(), rng: RNG(seed: 7), data: data)
        let all = deck.peekAll()
        XCTAssertEqual(deck.draw()?.id, all.first?.id, "draw() takes the TOP")
        XCTAssertEqual(deck.drawFromBottom()?.id, all.last?.id, "drawFromBottom() takes the BOTTOM")
        XCTAssertEqual(deck.drawn(), 2)
        XCTAssertEqual(deck.remaining(), 50)
    }

    func testReturnCardReinsertsWithoutUncountingTheDraw() {
        let deck = DeckManager.create(DeckManager.buildStandardDeck(), rng: RNG(seed: 7), data: data)
        let c = deck.draw()!
        XCTAssertEqual(deck.drawn(), 1)
        deck.returnCard(c)
        XCTAssertEqual(deck.remaining(), 52, "composition is restored")
        XCTAssertEqual(deck.drawn(), 1, "a re-drawn card counts each time it LEAVES the deck")
    }

    func testPeekNeverChangesDrawOrder() {
        let deck = DeckManager.create(DeckManager.buildStandardDeck(), rng: RNG(seed: 99), data: data)
        let peeked = deck.peek(3).map(\.id)
        XCTAssertEqual(deck.remaining(), 52, "peeking draws nothing")
        XCTAssertEqual((0..<3).map { _ in deck.draw()!.id }, peeked)
    }

    func testRemainingCountsAreOrderFree() {
        let deck = DeckManager.create(DeckManager.buildStandardDeck(), rng: RNG(seed: 5), data: data)
        let byRank = deck.remainingCounts()
        XCTAssertEqual(byRank.values.reduce(0, +), 52)
        for r in DeckManager.ranks { XCTAssertEqual(byRank[r.value], 4, "4 of rank \(r.label)") }
        let bySuit = deck.remainingSuitCounts()
        XCTAssertEqual(bySuit.values.reduce(0, +), 52)
        for s in ["♥", "♦", "♣", "♠"] { XCTAssertEqual(bySuit[s], 13) }
    }

    func testDeckStatsTurnCountsIntoPercentages() {
        let out = DeckStats.fromCounts([2: 3, 14: 1])
        XCTAssertEqual(out.total, 4)
        XCTAssertEqual(out.rows.count, DeckManager.ranks.count, "every rank gets a row")
        XCTAssertEqual(out.rows.first { $0.value == 2 }?.pct, 75)
        XCTAssertEqual(out.rows.first { $0.value == 14 }?.pct, 25)
        XCTAssertEqual(out.rows.first { $0.value == 7 }?.count, 0)
        XCTAssertEqual(DeckStats.fromCounts([:]).total, 0, "an empty deck never divides by zero")
    }

    func testSetNextNeverChangesTheDeckCount() {
        let deck = DeckManager.create(DeckManager.buildStandardDeck(), rng: RNG(seed: 3), data: data)
        let before = deck.remaining()
        XCTAssertEqual(deck.setNext(value: 9).value, 9)
        XCTAssertEqual(deck.remaining(), before, "moving a card to the top must not change the count")
        // Drain every 9, then force one — it SWAPS rather than adding.
        while let i = deck.peekAll().firstIndex(where: { $0.value == 9 }) {
            _ = i; deck.setNext(value: 9); _ = deck.draw()
        }
        let n = deck.remaining()
        XCTAssertEqual(deck.setNext(value: 9).value, 9)
        XCTAssertEqual(deck.remaining(), n, "a synthesized card swaps the next card, never adds one")
    }

    // MARK: - Board mechanics

    func testShufflePileIsCompositionOnly() {
        let board = BoardState(size: 1, data: data)
        for v in [2, 3, 4, 5, 6] { board.push(0, DeckManager.cardForValue(v)) }
        let before = Set(board.piles[0].cards.map(\.value))
        board.shufflePile(0, RNG(seed: 42))
        XCTAssertEqual(Set(board.piles[0].cards.map(\.value)), before, "the same cards, reordered")
        XCTAssertEqual(board.piles[0].cards.count, 5)
    }

    func testMoveBottomCardShiftsCompositionOnly() {
        let board = BoardState(size: 2, data: data)
        board.push(0, DeckManager.cardForValue(2)); board.push(0, DeckManager.cardForValue(3))
        board.push(1, DeckManager.cardForValue(9))
        XCTAssertTrue(board.moveBottomCard(0, 1))
        XCTAssertEqual(board.piles[0].cards.count, 1)
        XCTAssertEqual(board.piles[1].cards.count, 2)
        XCTAssertEqual(board.piles[1].cards.first?.value, 2, "it arrives at the BOTTOM")
        XCTAssertEqual(board.top(1)?.value, 9, "the receiving pile keeps its top")
        XCTAssertFalse(board.moveBottomCard(0, 0), "a pile can't donate to itself")
    }

    func testPushBottomBuriesUnderEverything() {
        let board = BoardState(size: 1, data: data)
        board.push(0, DeckManager.cardForValue(9))
        board.pushBottom(0, DeckManager.cardForValue(2))
        XCTAssertEqual(board.piles[0].cards.first?.value, 2)
        XCTAssertEqual(board.top(0)?.value, 9, "the top is unchanged")
    }

    func testDrainEmptiesButKeepsThePileAlive() {
        let board = BoardState(size: 1, data: data)
        board.push(0, DeckManager.cardForValue(9))
        board.push(0, DeckManager.cardForValue(4))
        let out = board.drain(0)
        XCTAssertEqual(out.count, 2)
        XCTAssertTrue(board.piles[0].cards.isEmpty)
        XCTAssertTrue(board.isActive(0), "drain never kills")
    }

    func testKillAndRevive() {
        let board = BoardState(size: 2, data: data)
        board.push(0, DeckManager.cardForValue(9))
        board.push(1, DeckManager.cardForValue(4))
        XCTAssertEqual(board.aliveCount(), 2)
        board.kill(0)
        XCTAssertEqual(board.aliveCount(), 1)
        XCTAssertTrue(board.anyAlive())
        board.revive(0)
        XCTAssertEqual(board.aliveCount(), 2)
        XCTAssertEqual(board.piles[0].cards.count, 1, "revive keeps the pile's cards")
    }

    func testSizeBonusRidesTheDealOnly() {
        let board = BoardState(size: 1, data: data)
        board.push(0, DeckManager.cardForValue(9))
        XCTAssertEqual(board.pileSize(0), 1)
        board.addSizeBonus(0, 5)
        XCTAssertEqual(board.pileSize(0), 6)
        XCTAssertEqual(board.piles[0].cards.count, 1, "the physical count is untouched")
    }

    // MARK: - SeedCode

    func testSeedCodeRoundTripsEveryBoundary() {
        for seed: UInt32 in [0, 1, 31, 32, 0xFFFF, 0x7FFF_FFFF, 0xFFFF_FFFF] {
            let code = SeedCode.encode(seed)
            XCTAssertEqual(code.count, SeedCode.length)
            XCTAssertEqual(SeedCode.decode(code), seed, "round trip \(seed)")
        }
    }

    func testSeedCodeAlphabetIsUnambiguous() {
        XCTAssertEqual(SeedCode.alphabet.count, SeedCode.base)
        for banned: Character in ["0", "O", "1", "I", "L"] {
            XCTAssertFalse(SeedCode.alphabet.contains(banned), "'\(banned)' is ambiguous")
        }
    }

    func testSeedCodeDecodeIsTrimAndCaseTolerantButStrictOtherwise() {
        let code = SeedCode.encode(123456)
        XCTAssertEqual(SeedCode.decode("  " + code.lowercased() + " "), 123456)
        XCTAssertNil(SeedCode.decode(""), "wrong length")
        XCTAssertNil(SeedCode.decode(String(code.dropLast())), "wrong length")
        XCTAssertNil(SeedCode.decode(code + "A"), "wrong length")
        XCTAssertNil(SeedCode.decode("AAAAAA0"), "0 is not in the alphabet")
        XCTAssertNil(SeedCode.decode("9999999"), "past 0xFFFFFFFF")
        XCTAssertNil(SeedCode.decode(nil))
    }

    // MARK: - Map traversal

    func testTraversalStartsAtTheOpeningsAndFollowsOutEdges() {
        let c = CampaignState()
        c.setSeedOverride(2024); c.reset()
        let opens = c.legalNextNodes()
        XCTAssertEqual(Set(opens.map(\.id)), Set(c.runMap!.row0), "the run starts below row 0")
        XCTAssertNil(c.nodePos)
        XCTAssertFalse(c.moveToNode(-1), "an illegal move is refused")
        XCTAssertTrue(c.moveToNode(opens[0].id))
        XCTAssertEqual(c.nodePos, opens[0].id)
        XCTAssertEqual(Set(c.legalNextNodes().map(\.id)), Set(opens[0].next))
    }

    func testMovingOntoANodeAdoptsItsPhase() {
        let c = CampaignState()
        c.setSeedOverride(2024); c.reset()
        let opens = c.legalNextNodes()
        c.moveToNode(opens[0].id)
        XCTAssertEqual(c.phaseIndex, opens[0].phase)
    }

    func testClearingANodeIsIdempotent() {
        let c = CampaignState()
        c.setSeedOverride(2024); c.reset()
        let id = c.legalNextNodes()[0].id
        XCTAssertTrue(c.markNodeCleared(id))
        XCTAssertFalse(c.markNodeCleared(id), "a second clear reports false")
        XCTAssertTrue(c.nodeCleared(id))
    }

    func testTheRunBossIsTheSpadeBoss() {
        let c = CampaignState()
        c.setSeedOverride(2024); c.reset()
        let m = c.runMap!
        XCTAssertTrue(c.isRunBoss(m.runBossId!))
        XCTAssertFalse(c.isRunBoss(m.phases[0].bossId), "an earlier stage boss does not end the climb")
        XCTAssertFalse(c.isRunComplete())
        c.markNodeCleared(m.runBossId!)
        XCTAssertTrue(c.isRunComplete())
    }

    func testEveryPickupNodeShowsExactlyTheCardItGrants() {
        let c = CampaignState()
        c.setSeedOverride(31415); c.reset()
        let pickups = c.runMap!.nodes.filter { $0.type == "pickup" }
        XCTAssertFalse(pickups.isEmpty)
        for n in pickups.prefix(8) {
            let shown = c.nodeCard(n)
            XCTAssertNotNil(shown, "node \(n.id) is locked to a card up front")
            let granted = c.resolvePickup(n)
            if shown!.joker {
                XCTAssertEqual(granted?.joker, true, "the sentinel mints a REAL Joker on the grant")
            } else if shown!.blank {
                XCTAssertEqual(granted?.blank, true, "a Blank grants a removal, not a card")
            } else {
                XCTAssertEqual(granted?.id, shown!.id, "shown == granted")
                XCTAssertTrue(c.ownedIds.contains(granted!.id))
            }
            XCTAssertTrue(c.nodeCleared(n.id))
        }
    }

    func testRevealedTwoCardPacksCommitBothFacesUpFront() {
        let c = CampaignState()
        c.setSeedOverride(31415); c.reset()
        let packs = c.runMap!.nodes.filter { $0.type == "pack" && $0.packCount == 2 }
        for n in packs.prefix(4) {
            let faces = c.packNodeCards(n)
            XCTAssertEqual(faces.count, 2, "a revealed +2 pack shows both cards")
            let granted = c.resolvePack(n)
            let realFaces = faces.filter { !$0.blank }
            XCTAssertEqual(granted.count, faces.count, "Blanks stay in the grant list (one removal picker each)")
            XCTAssertEqual(granted.filter { !$0.blank }.count, realFaces.count,
                           "it grants exactly the real cards it showed")
            XCTAssertFalse(granted.contains { $0.blank && c.ownedIds.contains($0.id) },
                           "a Blank never joins the deck")
        }
    }

    func testLockedCardsAreNeverDoubleClaimed() {
        let c = CampaignState()
        c.setSeedOverride(9001); c.reset()
        var seen = Set<Int>()
        for (_, id) in c.nodeCards where id >= 0 {
            XCTAssertTrue(seen.insert(id).inserted, "card \(id) is locked to two different nodes")
        }
        for (_, ids) in c.packCards {
            for id in ids where id >= 0 {
                XCTAssertTrue(seen.insert(id).inserted, "card \(id) is claimed twice")
            }
        }
        for id in c.ownedIds {
            XCTAssertFalse(seen.contains(id), "an owned card \(id) was also locked to a node")
        }
    }

    func testAPackAlwaysGrantsItsFullCount() {
        let c = CampaignState()
        c.setSeedOverride(4711); c.reset()
        for n in c.runMap!.nodes.filter({ $0.type == "pack" && $0.addOf >= 3 }).prefix(5) {
            let granted = c.resolvePack(n)
            XCTAssertEqual(granted.count, n.addOf,
                           "a +\(n.addOf) pack grants exactly \(n.addOf) cards (minting duplicates once the suit runs out)")
        }
    }

    // MARK: - Store

    func testTheStoreShelfRespectsTheSlotCountAndTypeCap() {
        let c = CampaignState()
        c.setSeedOverride(606); c.reset()
        if let first = c.legalNextNodes().first { c.moveToNode(first.id) }
        let offer = c.openStore()
        XCTAssertEqual(offer.slots.count, data.items.store.slots)
        var perType: [String: Int] = [:]
        for s in offer.slots.compactMap({ $0 }) {
            let key = s.kind == "card" ? "card" : StoreRoll.slotTypeKey(s.kind, s.id, data: data)
            perType[key, default: 0] += 1
        }
        for (k, n) in perType where k != "removal" {
            XCTAssertLessThanOrEqual(n, data.items.store.typeCap, "type '\(k)' floods the shelf")
        }
    }

    func testTheRemovalSlotIsPermanentAndLast() {
        let c = CampaignState()
        c.setSeedOverride(606); c.reset()
        if let first = c.legalNextNodes().first { c.moveToNode(first.id) }
        c.setRemovalSlot(true)
        let offer = c.openStore()
        XCTAssertEqual(offer.slots.last??.kind, "removal")
        c.setRemovalSlot(false)
        let plain = c.openStore()
        XCTAssertFalse(plain.slots.contains { $0?.kind == "removal" })
    }

    func testRerollChargesAndClimbs() {
        let c = CampaignState()
        c.setSeedOverride(606); c.reset()
        if let first = c.legalNextNodes().first { c.moveToNode(first.id) }
        let base = data.items.store.reroll.baseCost, step = data.items.store.reroll.step
        c.addCoins(1000)
        let offer = c.openStore()
        XCTAssertEqual(offer.rerollCost, base)
        let before = c.getCoins()
        XCTAssertTrue(c.rerollStore())
        XCTAssertEqual(c.getCoins(), before - Int(base))
        XCTAssertEqual(c.storeRerollCost(), base + step, "the cost climbs per reroll within a visit")
        // A fresh visit resets the ladder.
        let fresh = c.openStore()
        XCTAssertEqual(fresh.rerollCost, base)
    }

    func testAnUnaffordableRerollIsRefused() {
        let c = CampaignState()
        c.setSeedOverride(606); c.reset()
        if let first = c.legalNextNodes().first { c.moveToNode(first.id) }
        _ = c.openStore()
        XCTAssertEqual(c.getCoins(), 0)
        XCTAssertFalse(c.canReroll())
        XCTAssertFalse(c.rerollStore())
    }

    func testBuyingASlotEmptiesOnlyThatSlot() {
        let c = CampaignState()
        c.setSeedOverride(2468); c.reset()
        if let first = c.legalNextNodes().first { c.moveToNode(first.id) }
        c.addCoins(10_000)
        let offer = c.openStore()
        guard let i = offer.slots.firstIndex(where: { $0?.kind == "pillar" }) else { return }
        let before = c.getStoreOffer()!.slots.compactMap { $0 }.count
        XCTAssertTrue(c.buyMixedSlot(i).ok)
        XCTAssertNil(c.getStoreOffer()!.slots[i])
        XCTAssertEqual(c.getStoreOffer()!.slots.compactMap { $0 }.count, before - 1)
    }

    func testRemovalIsRepeatableAndPermanentlyRemovesACard() {
        let c = CampaignState()
        c.setSeedOverride(2468); c.reset()
        c.addCoins(10_000)
        let target = c.ownedIds[0]
        let size = c.deckSize()
        XCTAssertTrue(c.buyRemoval(target))
        XCTAssertEqual(c.deckSize(), size - 1)
        XCTAssertFalse(c.ownedIds.contains(target))
        XCTAssertFalse(c.buyRemoval(target), "the card is already gone")
        XCTAssertTrue(c.buyRemoval(c.ownedIds[0]), "the Removal slot never depletes")
    }

    // MARK: - Inventories

    func testPillarPlacementRoundTripsThroughTheInventory() {
        let c = CampaignState()
        c.setDeck("pink"); c.setSeedOverride(13); c.reset()
        c.addCoins(10_000)
        let id = data.pillarTypes.ids[0]
        XCTAssertTrue(c.buyPillarToInventory(id))
        XCTAssertEqual(c.pillarInventory[id], 1)
        XCTAssertTrue(c.placePillar(id, col: 0))
        XCTAssertEqual(c.columnPillar(0), id)
        XCTAssertNil(c.pillarInventory[id], "placing spends the inventory copy")
        XCTAssertTrue(c.unplacePillar(col: 0))
        XCTAssertEqual(c.pillarInventory[id], 1, "unplacing returns it")
        XCTAssertNil(c.columnPillar(0))
    }

    func testPlacingOverAPillarReturnsTheDisplacedOne() {
        let c = CampaignState()
        c.setSeedOverride(13); c.reset()
        c.addCoins(10_000)
        let a = data.pillarTypes.ids[0], b = data.pillarTypes.ids[1]
        c.buyPillarToInventory(a); c.buyPillarToInventory(b)
        c.placePillar(a, col: 1)
        c.placePillar(b, col: 1)
        XCTAssertEqual(c.columnPillar(1), b)
        XCTAssertEqual(c.pillarInventory[a], 1, "the displaced Pillar goes back to the inventory")
    }

    func testExactlyOneSamePowerIsEquipped() {
        let c = CampaignState()
        c.setSeedOverride(13); c.reset()
        c.addCoins(10_000)
        let a = data.samePowerTypes.ids[0], b = data.samePowerTypes.ids[1]
        c.buySamePowerToInventory(a); c.buySamePowerToInventory(b)
        XCTAssertTrue(c.equipSamePower(a))
        XCTAssertEqual(c.getSamePower(), a)
        XCTAssertTrue(c.equipSamePower(b))
        XCTAssertEqual(c.getSamePower(), b, "only ONE is equipped at a time")
        XCTAssertEqual(c.samePowerInventory[a], 1, "the old one returns to the inventory")
        XCTAssertTrue(c.unequipSamePower())
        XCTAssertNil(c.getSamePower())
    }

    func testAnUnaffordablePurchaseChangesNothing() {
        let c = CampaignState()
        c.setSeedOverride(13); c.reset()
        XCTAssertEqual(c.getCoins(), 0)
        let id = data.pillarTypes.ids[0]
        XCTAssertFalse(c.buyPillarToInventory(id))
        XCTAssertTrue(c.pillarInventory.isEmpty)
        XCTAssertEqual(c.getCoins(), 0)
    }

    // MARK: - Reset

    func testANewCampaignResetsEverythingToAVanillaStart() {
        let c = CampaignState()
        c.setSeedOverride(77); c.reset()
        c.addCoins(500); c.addRunScore(90); c.markRunWon()
        c.setSameCharge(true)
        c.buyPillarToInventory(data.pillarTypes.ids[0])
        c.reset()
        XCTAssertEqual(c.getCoins(), 0)
        XCTAssertEqual(c.getRunScore(), 0)
        XCTAssertEqual(c.getCampaignScore(), 0)
        XCTAssertFalse(c.runWonBanked)
        XCTAssertFalse(c.getSameCharge())
        XCTAssertTrue(c.pillarInventory.isEmpty)
        XCTAssertTrue(c.clearedNodes.isEmpty)
        XCTAssertNil(c.nodePos)
        XCTAssertEqual(c.actionCounter, 0, "the action stream restarts with the campaign")
        // The id counter is reset to 52 and then grows only from the NEW run's
        // own minting (start Jokers, and duplicates for suit-exhausted stages).
        XCTAssertGreaterThanOrEqual(c.nextCardId, 52)
        XCTAssertEqual(Set(c.baseDeck.map(\.id)).count, c.baseDeck.count, "no id is ever handed out twice")
        XCTAssertGreaterThan(c.nextCardId, c.baseDeck.map(\.id).max()!, "the counter is always ahead of the deck")
    }
}
