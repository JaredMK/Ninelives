import XCTest
@testable import GameCore

/// v6.89 batch pins: Long Odds at 50%, Flypaper's curse-free pool, Chorus's
/// live {rank}, and retired items hidden from every unlock surface.
final class FixesV689Tests: XCTestCase {
    private let data = GameData.shared

    func testLongOddsIsAFiftyFiftyNow() {
        let def = data.samePowerTypes.get("linkPurge")!
        XCTAssertEqual(def.num("chance", 0), 0.5, "the approved v6.89 value")
        XCTAssertTrue(def.description.hasPrefix("50%"), "the text names the new odds")
    }

    func testFlypaperPoolNeverContainsACurse() {
        // The pool chain (wildStickerPoolFor → baseStickerPool →
        // grantableBase) excludes curses at the ROOT — pin it per card shape.
        let e = IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 6, "♦")],
                          deckOrder: [IV.spec(50, 9)])
        for card in [DeckManager.toCard(IV.spec(90, 5, "♠"), data: data),
                     DeckManager.toCard(IV.spec(91, 14, "♥"), data: data),
                     DeckManager.toCard(IV.spec(92, 2, "♦", ["tell"]), data: data)] {
            let pool = e.wildStickerPoolFor(card)
            XCTAssertFalse(pool.isEmpty, "the pool has normal stickers to grant")
            XCTAssertTrue(pool.allSatisfy { !$0.cursed }, "Flypaper can NEVER grant a curse")
            XCTAssertTrue(pool.allSatisfy { !$0.inactive }, "…nor a retired sticker")
        }
    }

    func testFlypaperGrantsAreNeverCursedAcrossSeeds() {
        // Belt and braces on top of the pool pin: sweep real landings.
        var granted: [String] = []
        for seed: UInt32 in 1...200 {
            let e = IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6), IV.spec(3, 6)],
                              deckOrder: [IV.spec(50, 9, "♥"), IV.spec(51, 3)],
                              pillars: ["flypaper", nil, nil], seed: seed)
            e.on { if case .pillarSticker(_, _, _, let t) = $0 { granted.append(t) } }
            e.rng.state = seed
            e.guess(0, .higher)
        }
        XCTAssertGreaterThan(granted.count, 0, "the 5% roll hit somewhere in 200 seeds")
        for t in granted {
            XCTAssertEqual(data.stickerTypes.get(t)?.cursed, false,
                           "Flypaper granted '\(t)' — never a curse")
        }
    }

    func testChorusDescriptionNamesTheLiveRank() {
        let def = data.baseTypes.get("chorus")!
        XCTAssertTrue(def.description.contains("{rank}"), "the registry text is templated now")
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular"); c.setSeedOverride(7); c.reset()
        let out = c.itemDescription(def)
        XCTAssertFalse(out.contains("{rank}"), "the campaign text substitutes the live rank")
        let r = c.mostCommonRank()!
        let label = DeckManager.ranks.first { $0.value == r }!.label
        XCTAssertTrue(out.contains("to \(label)"),
                      "…and it IS the deck's most-common rank (ties → lowest)")
    }

    func testRetiredItemsNeverPopOrTease() {
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular"); c.reset()
        // Cross a retired sticker's gate (Snowball: perfectDeals 6) with room
        // to spare, then demand the pop list skips it while the gate itself
        // reads crossed.
        c.stats.bump("perfectDeals", 50)
        let popped = c.itemUnlocks.checkNewUnlocks()
        XCTAssertTrue(c.itemUnlocks.isUnlocked(data.stickerTypes.get("snowball")!),
                      "the retired gate IS crossed")
        XCTAssertFalse(popped.contains { $0.id == "snowball" }, "…but it never pops")
        func def(_ id: String) -> ItemDef? {
            data.stickerTypes.get(id) ?? data.pillarTypes.get(id) ?? data.baseTypes.get(id)
                ?? data.samePowerTypes.get(id) ?? data.packTypes.get(id)
        }
        for u in popped {
            XCTAssertEqual(def(u.id)?.inactive, false, "'\(u.id)' popped while retired")
        }
        for miss in c.itemUnlocks.nearestLocked(10) {
            XCTAssertEqual(def(miss.id)?.inactive, false,
                           "the near-miss teaser named retired '\(miss.id)'")
        }
    }

    func testCollectionGroupsSourceFiltersInactive() throws {
        // MenuScreens is app-target UI, out of this test bundle's reach —
        // pin its list builder by SOURCE, the StickerDisplayTests idiom.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let src = try String(contentsOf: root.appendingPathComponent("UI/MenuScreens.swift"),
                             encoding: .utf8)
        for needle in ["stickers.filter { !$0.cursed && !$0.inactive }",
                       "pillars.filter { !$0.inactive }",
                       "bases.filter { !$0.inactive }",
                       "samePowers.filter { !$0.inactive }",
                       "packs.filter { !$0.inactive }"] {
            XCTAssertTrue(src.contains(needle),
                          "Collection groups() lost the inactive filter: \(needle)")
        }
    }
}
