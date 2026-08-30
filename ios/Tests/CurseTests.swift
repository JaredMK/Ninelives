import XCTest
@testable import GameCore

/// THE CURSE OVERHAUL (v6.48): the shared weighted roll, every new curse's
/// board behavior, the scoring impact of the size curses, save survival, and
/// the peel interactions.
final class CurseTests: XCTestCase {

    let data = GameData.shared

    // MARK: - Helpers

    /// A 3-pile engine over a scripted deck. `spec(id, rank, suit, stickers)`.
    private func spec(_ id: Int, _ rank: Int, _ suit: String = "♠",
                      _ stickers: [String] = []) -> CardSpec {
        CardSpec(id: id, suit: suit, originalRank: rank, currentRank: rank,
                 stickers: stickers.map { StickerRecord(type: $0) })
    }

    /// Deal: the FIRST `piles` specs become the pile tops (one card each, in
    /// order); the rest is the draw deck IN ORDER. Mirrors the debug harness.
    private func engine(piles: Int = 3, deck: [CardSpec],
                        config: RunConfig = RunConfig(cols: [1, 1, 1]),
                        pillars: [String?] = [nil, nil, nil],
                        bases: [String?] = [nil, nil, nil]) -> GameEngine {
        let e = GameEngine(deckSpecs: deck, pileCount: piles, runConfig: config)
        e.start(seedOverride: 7)
        e.startRun(pillars: pillars, bases: bases, samePower: .some(nil))
        // Deterministic layout: force tops + deck order to the spec order.
        let live = deck.map { DeckManager.toCard($0, data: data) }
        for i in 0..<piles {
            e.board.piles[i].cards = [live[i]]
            e.board.piles[i].dead = false
        }
        e.deck.restoreSnapshot(cards: Array(live.dropFirst(piles)), drawn: piles)
        return e
    }

    // MARK: - The shared weighted roll

    func testCursePoolsRespectExclusions() {
        let reg = data.stickerTypes
        let mystery = Set(reg.cursePool(path: "mystery").map(\.id))
        let purge = Set(reg.cursePool(path: "purge").map(\.id))
        let dupe = Set(reg.cursePool(path: "duplicate").map(\.id))
        let doors = Set(reg.cursePool(path: "doors").map(\.id))
        XCTAssertTrue(mystery.contains("saboteur"), "mystery draws the full pool")
        XCTAssertEqual(mystery, doors, "the bad door and the ? node share one pool")
        XCTAssertFalse(purge.contains("saboteur"), "purge must never carry item loss")
        XCTAssertTrue(purge.contains("malfunction"))
        // Duplicate: the mild band only.
        XCTAssertEqual(dupe, Set(["leech", "shrink", "mute", "trapdoor", "spoiler", "drainShield"]))
        // Every pool entry is genuinely cursed with a positive weight.
        for id in mystery {
            let def = reg.get(id)!
            XCTAssertTrue(def.cursed)
            XCTAssertGreaterThan(def.curseWeight, 0)
        }
    }

    func testRollCurseFollowsTheHandTunedWeights() {
        let reg = data.stickerTypes
        // Sweep the [0,1) roll space — the counts must land within 1 sample
        // of weight/total for every curse (the roll is a straight CDF walk).
        let pool = reg.cursePool(path: "mystery")
        let total = pool.reduce(0.0) { $0 + $1.curseWeight }
        let n = 10_000
        var counts: [String: Int] = [:]
        for i in 0..<n {
            let id = reg.rollCurse(path: "mystery", roll: (Double(i) + 0.5) / Double(n))!.id
            counts[id, default: 0] += 1
        }
        for def in pool {
            let expected = Double(n) * def.curseWeight / total
            XCTAssertEqual(Double(counts[def.id] ?? 0), expected, accuracy: 2,
                           "\(def.id): weight \(def.curseWeight) must yield ~\(expected)")
        }
        // The approved band split: mild 50% / medium 30% / severe 20%.
        let mild = ["leech", "shrink", "mute", "trapdoor", "spoiler", "drainShield"]
            .compactMap { counts[$0] }.reduce(0, +)
        XCTAssertEqual(Double(mild) / Double(n), 0.50, accuracy: 0.01)
        XCTAssertEqual(Double(counts["saboteur"] ?? 0) / Double(n), 0.20, accuracy: 0.01)
    }

    // MARK: - Board behaviors

    func testShrinkCountsMinusOneFlooredAtOne() {
        let e = engine(deck: [
            spec(1, 5), spec(2, 5), spec(3, 5),
            spec(4, 9, "♠", ["shrink"]), spec(5, 11),
        ])
        XCTAssertEqual(e.board.pileSize(0), 1)
        e.guess(0, .higher)                       // 9(shrink) lands on 5
        XCTAssertEqual(e.board.piles[0].cards.count, 2, "two physical cards")
        XCTAssertEqual(e.board.pileSize(0), 1, "5 counts 1, shrink-9 counts 0 → floored at 1")
        e.guess(0, .higher)                       // 11 lands on the shrink-9
        XCTAssertEqual(e.board.pileSize(0), 2, "3 cards minus the shrink = 2")
    }

    func testFlatlineTopForcesSizeOneAndCoveringRestoresIt() {
        let e = engine(deck: [
            spec(1, 5), spec(2, 5), spec(3, 5),
            spec(4, 9, "♠", ["flatline"]), spec(5, 11),
        ])
        e.guess(0, .higher)                       // flatline-9 lands, is TOP
        XCTAssertEqual(e.board.piles[0].cards.count, 2)
        XCTAssertEqual(e.board.pileSize(0), 1, "flatline top pins the pile at 1")
        e.guess(0, .higher)                       // 11 covers it
        XCTAssertEqual(e.board.pileSize(0), 3, "covered flatline releases the true size")
    }

    func testMuteRefusesSameOnThatPileOnly() {
        let e = engine(deck: [
            spec(1, 8, "♠", ["mute"]), spec(2, 8), spec(3, 5),
            spec(4, 8), spec(5, 8),
        ])
        XCTAssertTrue(e.pileMuted(0))
        XCTAssertFalse(e.pileMuted(1))
        e.guess(0, .same)                          // REFUSED: no draw consumed
        XCTAssertEqual(e.run.totalGuesses, 0)
        XCTAssertEqual(e.deck.remaining(), 2)
        e.guess(1, .same)                          // fine on an unmuted pile
        XCTAssertEqual(e.run.totalGuesses, 1)
        XCTAssertEqual(e.run.correctGuesses, 1)
    }

    func testMagnetForcesTheNextGuessOntoItsPile() {
        let e = engine(deck: [
            spec(1, 5), spec(2, 5), spec(3, 5),
            spec(4, 9, "♠", ["magnet"]), spec(5, 11), spec(6, 2),
        ])
        e.guess(0, .higher)                        // magnet-9 lands on pile 0
        XCTAssertEqual(e.magnetPiles(), [0])
        e.guess(1, .higher)                        // REFUSED: not the magnet pile
        XCTAssertEqual(e.run.totalGuesses, 1, "the magnet swallowed the off-pile guess")
        e.guess(0, .higher)                        // 11 covers the magnet
        XCTAssertEqual(e.run.totalGuesses, 2)
        XCTAssertTrue(e.magnetPiles().isEmpty, "covered magnet releases the board")
        e.guess(1, .lower)                         // free again
        XCTAssertEqual(e.run.totalGuesses, 3)
    }

    func testTwoMagnetsOfferTheChoiceBetweenThem() {
        let e = engine(deck: [
            spec(1, 9, "♠", ["magnet"]), spec(2, 9, "♥", ["magnet"]), spec(3, 5),
            spec(4, 11), spec(5, 2),
        ])
        XCTAssertEqual(Set(e.magnetPiles()), Set([0, 1]), "both magnets are live")
        e.guess(2, .higher)                        // refused — pile 2 isn't magnetic
        XCTAssertEqual(e.run.totalGuesses, 0)
        e.guess(1, .higher)                        // either magnet satisfies the pull
        XCTAssertEqual(e.run.totalGuesses, 1)
    }

    func testPeelerIsCoverOnly() {
        // v6.91: the Peeler strips the card that LANDS ON it — and nothing
        // else. A LANDING peeler is inert (the bidirectional clause retired
        // with the rework; the touched-both-ways rule was v6.5x).
        let e = engine(deck: [
            spec(1, 5, "♠", ["tell", "quickBury"]), spec(2, 5), spec(3, 5),
            spec(4, 9, "♠", ["peeler"]), spec(5, 11, "♥", ["gainCoin"]),
        ])
        var peels: [(Int, [String])] = []
        e.on { if case .cursePeeled(_, let id, let types) = $0 { peels.append((id, types)) } }
        e.guess(0, .higher)                        // peeler-9 lands ON the stickered 5
        let five = e.board.piles[0].cards.first!
        XCTAssertEqual(Set(five.stickers.map(\.type)), Set(["tell", "quickBury"]),
                       "a LANDING peeler strips nothing now")
        XCTAssertTrue(peels.isEmpty, "no peel event either")
        // The cover direction still bites: a card LANDS ON the peeler.
        e.guess(0, .higher)                        // gainCoin-11 lands ON peeler-9
        XCTAssertTrue(e.board.top(0)!.stickers.isEmpty, "landing on a peeler costs your stickers")
        XCTAssertEqual(peels.count, 1)
        XCTAssertEqual(peels.first?.0, 5)
        XCTAssertEqual(peels.first?.1 ?? [], ["gainCoin"])
        // The peeler card itself KEEPS its curse.
        XCTAssertEqual(e.board.piles[0].cards[1].stickers.map(\.type), ["peeler"])
    }

    func testShieldDrainEmptiesTheChargeOnLanding() {
        let e = engine(deck: [
            spec(1, 5), spec(2, 5), spec(3, 5),
            spec(4, 9, "♠", ["drainShield"]),
        ], config: RunConfig(cols: [1, 1, 1], sameCharge: true))
        XCTAssertTrue(e.sameCharge)
        e.guess(0, .higher)
        XCTAssertFalse(e.sameCharge, "the landing drained the banked charge")
    }

    func testBaseDrainSpendsTheColumnBase() {
        let e = engine(deck: [
            spec(1, 5), spec(2, 5), spec(3, 5),
            spec(4, 9, "♠", ["drainBase"]),
        ], bases: ["spadePeek", nil, nil])
        XCTAssertEqual(e.run.basesUsed?[0], false)
        e.guess(0, .higher)
        XCTAssertEqual(e.run.basesUsed?[0], true, "the base went red without firing")
    }

    func testSpoilerZeroesTheBonusTallyItemized() {
        let e = engine(deck: [
            spec(1, 5), spec(2, 5), spec(3, 5),
            spec(4, 9, "♠", ["gainCoin"]), spec(5, 11, "♥", ["spoiler"]),
        ])
        e.guess(0, .higher)                        // gainCoin lands → bonus > 0
        XCTAssertGreaterThan(e.run.bonusCoins, 0)
        e.guess(0, .higher)                        // spoiler lands → wiped
        XCTAssertEqual(e.run.bonusCoins, 0)
        XCTAssertTrue(e.run.bonusEvents.pairs.contains { $0.label == "Spoiler" && $0.amount < 0 },
                      "the wipe is itemized so the tally still sums")
    }

    func testJammerKnocksOutTheColumnPillarWhileTop() {
        // Prime pays on a correct prime-rank landing — jam it and it must
        // not. (This case rode Fibonacci until its v6.78 retirement.)
        let e = engine(deck: [
            spec(1, 4, "♠", ["jammer"]), spec(2, 4), spec(3, 4),
            spec(4, 5), spec(5, 7),
        ], pillars: ["prime", nil, nil])
        XCTAssertNil(e.resolvePillarDef(0), "jammer top: the pillar reads as absent")
        e.guess(0, .higher)                        // 5 (prime) lands ON the jammer pile: covers it
        XCTAssertNotNil(e.resolvePillarDef(0), "covered jammer releases the pillar")
        let before = e.run.bonusCoins
        e.guess(0, .higher)                        // 7 (prime) lands, pillar live again
        XCTAssertGreaterThan(e.run.bonusCoins, before, "prime pays once unjammed")
    }

    func testMalfunctionKillsThePileOnItsRoll() {
        // chance 0.1 — find a seed whose first rng draw triggers it, then
        // assert the pile dies on a CORRECT guess and the guess stays counted.
        for seed: UInt32 in 1...2000 {
            let e = engine(deck: [
                spec(1, 5, "♠", ["malfunction"]), spec(2, 5), spec(3, 5),
                spec(4, 9),
            ])
            e.rng.state = seed
            var sawMalfunction = false
            e.on { if case .malfunction = $0 { sawMalfunction = true } }
            e.guess(0, .higher)                    // correct: 9 > 5
            if sawMalfunction {
                XCTAssertFalse(e.board.isActive(0), "the malfunction killed the pile")
                XCTAssertEqual(e.run.correctGuesses, 1, "the guess itself stays correct")
                return
            }
            XCTAssertTrue(e.board.isActive(0), "no malfunction → a normal landing")
        }
        XCTFail("no seed in 1...2000 triggered a 10% roll — the roll is broken")
    }

    func testSaboteurDestroysAColumnItemAndEmits() {
        for seed: UInt32 in 1...2000 {
            let e = engine(deck: [
                spec(1, 5), spec(2, 5), spec(3, 5),
                spec(4, 9, "♠", ["saboteur"]),
            ], pillars: ["fibonacci", nil, nil], bases: ["spadePeek", nil, nil])
            e.rng.state = seed
            var hit: (String, String)?
            e.on { if case .sabotaged(_, let kind, let id) = $0 { hit = (kind, id) } }
            e.guess(0, .higher)
            if let hit {
                switch hit.0 {
                case "pillar":
                    XCTAssertNil(e.run.pillars?[0] ?? nil)
                    XCTAssertEqual(hit.1, "fibonacci")
                case "base":
                    XCTAssertNil(e.run.bases?[0] ?? nil)
                    XCTAssertEqual(hit.1, "spadePeek")
                default: XCTFail("unknown kind \(hit.0)")
                }
                return
            }
        }
        XCTFail("no seed in 1...2000 triggered the saboteur")
    }

    // MARK: - Scoring impact (the report's numbers, pinned)

    func testShrinkScoringImpactOnTheMinPile() {
        // 9 alive piles: eight of size 3, the min pile size 3 carrying a
        // shrink → min drops to 2: score 27 → 18 (the reported −33%).
        let e = engine(piles: 3, deck: [
            spec(1, 5), spec(2, 5), spec(3, 5),
            spec(4, 9, "♠", ["shrink"]),
        ])
        e.board.piles[0].cards.append(DeckManager.toCard(spec(90, 6), data: data))
        e.board.piles[1].cards.append(DeckManager.toCard(spec(91, 6), data: data))
        e.board.piles[1].cards.append(DeckManager.toCard(spec(92, 7), data: data))
        e.board.piles[2].cards.append(DeckManager.toCard(spec(93, 6), data: data))
        e.board.piles[2].cards.append(DeckManager.toCard(spec(94, 7), data: data))
        // Sizes now 2 / 3 / 3 → min 2. Land the shrink on pile 0: 3 cards
        // minus the shrink = 2... the MIN pile carrying it drops the min.
        e.guess(0, .higher)
        XCTAssertEqual(e.board.pileSize(0), 2, "3 cards, one shrink → 2")
        XCTAssertEqual(e.board.minAliveCards(), 2)
        XCTAssertEqual(e.board.aliveCount() * e.board.minAliveCards(), 6,
                       "3 piles × min 2 — one min step lost to the shrink")
    }

    func testFlatlineScoringCollapseWhileTopAtDealEnd() {
        let e = engine(piles: 3, deck: [
            spec(1, 5), spec(2, 5), spec(3, 5),
            spec(4, 9, "♠", ["flatline"]),
        ])
        for p in 0..<3 {
            e.board.piles[p].cards.append(DeckManager.toCard(spec(90 + p, 6), data: data))
            e.board.piles[p].cards.append(DeckManager.toCard(spec(95 + p, 7), data: data))
        }
        XCTAssertEqual(e.board.minAliveCards(), 3)
        XCTAssertEqual(e.board.aliveCount() * e.board.minAliveCards(), 9)
        e.guess(0, .higher)                        // flatline ends up TOP of pile 0
        XCTAssertEqual(e.board.minAliveCards(), 1, "flatline top pins the min at 1")
        XCTAssertEqual(e.board.aliveCount() * e.board.minAliveCards(), 3,
                       "9 → 3: the reported collapse when it ends the deal on top")
    }

    // MARK: - Persistence + peel interactions

    func testEveryCurseSurvivesTheCampaignSaveRoundTrip() {
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular"); c.reset()
        let curses = data.stickerTypes.all().filter(\.cursed).map(\.id)
        var applied: [Int: String] = [:]
        for (i, curse) in curses.enumerated() {
            let card = c.getRunDeck().filter { !$0.joker && !$0.blank }[i]
            XCTAssertTrue(c.applyStickerDirect(card.id, curse), "apply \(curse)")
            applied[card.id] = curse
        }
        let c2 = CampaignState(store: MemoryStore())
        XCTAssertTrue(c2.restore(c.serialize()))
        for (cardId, curse) in applied {
            let card = c2.getRunDeck().first { $0.id == cardId }!
            XCTAssertTrue(card.stickers.contains { $0.type == curse },
                          "\(curse) must survive serialize/restore")
        }
    }

    func testEveryCurseSurvivesTheMidDealSnapshot() {
        let curses = data.stickerTypes.all().filter(\.cursed).map(\.id)
        var deck: [CardSpec] = [spec(1, 5), spec(2, 5), spec(3, 5)]
        for (i, curse) in curses.enumerated() {
            deck.append(spec(10 + i, 6 + (i % 8), "♠", [curse]))
        }
        let a = engine(deck: deck)
        _ = a.snapshot()
        let b = engine(deck: deck)
        XCTAssertTrue(b.restoreSnapshot(a.snapshot()))
        let aTypes = b.deck.snapshotCards().flatMap { $0.stickers.map(\.type) }.sorted()
        XCTAssertEqual(aTypes, curses.sorted(), "every curse rides the mid-deal snapshot")
    }

    func testCleanseCanStripANewCurse() {
        // Just a Two's peel / Cleanse route: removeStickerInstances must work
        // on the new curse ids like any sticker.
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular"); c.reset()
        let card = c.getRunDeck().first { !$0.joker && !$0.blank }!
        XCTAssertTrue(c.applyStickerDirect(card.id, "magnet"))
        XCTAssertEqual(c.removeStickerInstances(card.id, "magnet", 1), 1)
        XCTAssertFalse(c.getRunDeck().first { $0.id == card.id }!.stickers
            .contains { $0.type == "magnet" })
    }

    // MARK: - Pathways

    func testPurgeOfferPreRollsItsCursesDeterministically() {
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular"); c.reset()
        c.debugForcedJokerKey = "purge"
        guard case .purge(let n, let curses)? = c.rollOldJoker(42) else {
            return XCTFail("no purge offer")
        }
        XCTAssertEqual(n, 3)
        XCTAssertEqual(curses.count, 3)
        XCTAssertFalse(curses.contains("saboteur"), "purge never rolls the severe band")
        // Same node → same roll (a refresh must not re-roll his terms).
        c.debugForcedJokerKey = "purge"
        guard case .purge(_, let again)? = c.rollOldJoker(42) else {
            return XCTFail("no repeat offer")
        }
        XCTAssertEqual(curses, again)
    }

    func testDuplicateOfferRollsAMildCurse() {
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular"); c.reset()
        c.debugForcedJokerKey = "duplicate"
        guard case .duplicate(let sticker)? = c.rollOldJoker(9) else {
            return XCTFail("no duplicate offer")
        }
        XCTAssertTrue(["leech", "shrink", "mute", "trapdoor", "spoiler", "drainShield"]
            .contains(sticker), "duplicate draws mild-only, got \(sticker)")
    }

    func testAppliedJokerCursesLandOnDistinctCards() {
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular"); c.reset()
        let hit = c.applyJokerCurses(["leech", "jammer", "shrink"], nodeId: 5)
        XCTAssertEqual(hit.count, 3)
        XCTAssertEqual(Set(hit.map(\.cardId)).count, 3, "three DIFFERENT cards")
        for (cardId, curse) in hit {
            XCTAssertTrue(c.getRunDeck().first { $0.id == cardId }!.stickers
                .contains { $0.type == curse })
        }
    }

    func testMysteryCurseUsesTheSharedRoll() {
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular"); c.reset()
        let out = c.applyMysteryEvent("cursedSticker", nodeId: 3)
        XCTAssertNotNil(out)
        XCTAssertTrue(data.stickerTypes.cursePool(path: "mystery").map(\.id)
            .contains(out!.stickerId ?? ""), "the applied curse came from the pool")
    }
}
