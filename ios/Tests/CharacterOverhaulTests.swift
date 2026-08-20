import XCTest
@testable import GameCore

/// THE v6.67 CHARACTER OVERHAUL: Slyrex's fixed-rank start, Mr. Garden's
/// sticker-on-everything + no-Pillars/Bases rules, Rocko's full loadout and
/// sticker suppression, the reordered unlock chain, and the save migration
/// that carries smith/lammy-era progress into the new ids.
final class CharacterOverhaulTests: XCTestCase {
    let data = GameData.shared

    private func campaign(_ deck: String, seed: UInt32) -> CampaignState {
        let c = CampaignState(store: MemoryStore())
        c.setDeck(deck); c.setSeedOverride(seed); c.reset()
        return c
    }

    // MARK: - Slyrex

    func testSlyrexStartsWithSixTwosSixAcesAndAnEight() {
        for seed: UInt32 in [7, 4242, 987_654] {
            let c = campaign("slyrex", seed: seed)
            let start = c.getRunDeck()
            XCTAssertEqual(start.count, 13, "seed \(seed): 13 start cards")
            var byRank: [Int: Int] = [:]
            for card in start { byRank[card.originalRank, default: 0] += 1 }
            XCTAssertEqual(byRank, [2: 6, 14: 6, 8: 1],
                           "seed \(seed): six 2s, six Aces, one 8 — nothing else")
            XCTAssertTrue(start.allSatisfy { $0.stickers.isEmpty }, "as Pinky: bare start")
            // Determinism: the same seed deals the same hand.
            let c2 = campaign("slyrex", seed: seed)
            XCTAssertEqual(c2.getRunDeck().map(\.id), start.map(\.id), "seeded start replays")
        }
    }

    func testSlyrexOtherwisePlaysLikePinky() {
        let r = data.meta.rules("slyrex")
        XCTAssertTrue(r.altSuits); XCTAssertEqual(r.priceMult, 1)
        XCTAssertFalse(r.noStickers); XCTAssertFalse(r.preEquip)
        XCTAssertFalse(r.stickerEverything); XCTAssertFalse(r.noPillarsBases)
    }

    // MARK: - Mr. Garden

    func testGardenEveryCardEverywhereCarriesASticker() {
        let c = campaign("garden", seed: 31)
        // The whole draft pool is dressed — so store shelves, packs and map
        // pickups all show a stickered card before it's taken.
        for card in c.baseDeck where !card.joker && !card.blank {
            XCTAssertFalse(card.stickers.isEmpty, "draft card \(card.id) is bare")
        }
        // A store-minted card slot never leaves bare either.
        let rng = RNG(seed: 99)
        for _ in 0..<20 {
            let minted = c.genNormalCard(rng, stickerOdds: data.items.store.card.stickerOdds)
            XCTAssertFalse(minted.stickers.isEmpty, "store mint left bare")
        }
        // Packs grant dressed cards.
        if let pack = (c.runMap?.nodes ?? []).first(where: { $0.type == "pack" }) {
            for card in c.resolvePack(pack) where !card.joker && !card.blank {
                XCTAssertFalse(card.stickers.isEmpty, "pack card \(card.id) is bare")
            }
        }
        // Map +1 pickups preview dressed cards.
        if let pickup = (c.runMap?.nodes ?? []).first(where: { $0.type == "pickup" }),
           let preview = c.previewPickupCard(pickup), !preview.joker, !preview.blank {
            XCTAssertFalse(preview.stickers.isEmpty, "pickup preview is bare")
        }
    }

    func testGardenHasNoPillarsOrBasesAnywhere() {
        let c = campaign("garden", seed: 47)
        c.addCoins(500)
        // The store never shelves them (across the visit and a restock).
        _ = c.openStore()
        var kinds = Set(c.getStoreOffer()!.slots.compactMap { $0?.kind })
        _ = c.rerollStore()
        kinds.formUnion(c.getStoreOffer()!.slots.compactMap { $0?.kind })
        XCTAssertFalse(kinds.contains("pillar"), "a Pillar reached Garden's shelf")
        XCTAssertFalse(kinds.contains("base"), "a Base reached Garden's shelf")
        // They can't be equipped even by force.
        XCTAssertFalse(c.placePillar(data.pillarTypes.ids[0], col: 0))
        XCTAssertFalse(c.placeBase(data.baseTypes.ids[0], col: 0))
        XCTAssertEqual(c.columnPillars.compactMap { $0 }.count, 0)
        XCTAssertEqual(c.columnBases.compactMap { $0 }.count, 0)
    }

    // MARK: - Rocko

    func testRockoStartsFullyLoadedAndStickerFree() {
        let c = campaign("rocko", seed: 61)
        XCTAssertEqual(c.columnPillars.compactMap { $0 }.count, CampaignLayout.columnSlots,
                       "all Pillar slots filled")
        XCTAssertEqual(c.columnBases.compactMap { $0 }.count, CampaignLayout.columnSlots,
                       "all Base slots filled")
        XCTAssertNotNil(c.equippedSamePower, "a random Same-Power is equipped")
        // No stickers anywhere: the pool, mints, and the store's sticker class.
        for card in c.baseDeck { XCTAssertTrue(card.stickers.isEmpty, "card \(card.id) stickered") }
        let rng = RNG(seed: 5)
        for _ in 0..<10 { XCTAssertTrue(c.genNormalCard(rng).stickers.isEmpty, "mint stickered") }
        c.addCoins(500)
        _ = c.openStore()
        XCTAssertFalse(c.getStoreOffer()!.slots.compactMap { $0?.kind }.contains("sticker"),
                       "a sticker reached Rocko's shelf")
        // The one exception: JUST A TWO's curse still lands.
        c.setSameCharge(false)
        let o = c.applyMysteryEvent("cursedSticker", nodeId: 3)
        if let cardId = o?.cardId {
            let cursed = c.baseDeck.first { $0.id == cardId }
            XCTAssertEqual(cursed?.stickers.isEmpty, false, "the Two's curse must still stick")
            XCTAssertTrue(cursed!.stickers.allSatisfy {
                data.stickerTypes.get($0.type)?.cursed == true
            }, "only a CURSE may ride a Rocko card")
        }
    }

    // MARK: - Unlock chain + roster order

    func testDeckOrderIsTheNewChain() {
        XCTAssertEqual(GameMeta.deckOrder, ["pink", "mamma", "slyrex", "garden", "rocko"])
        for id in GameMeta.deckOrder {
            XCTAssertNotNil(data.meta.deckRules[id], "\(id) has rules")
        }
        XCTAssertNil(data.meta.deckRules["smith"], "smith is gone")
        XCTAssertNil(data.meta.deckRules["lammy"], "lammy is gone")
    }

    func testLeaderboardTokensCoverTheRoster() {
        for id in GameMeta.deckOrder {
            XCTAssertNotNil(LeaderboardID.identifier(deck: id, tier: "regular"), "\(id) board id")
        }
        XCTAssertEqual(LeaderboardID.identifier(deck: "pink", tier: "legendary"),
                       "sss.pinky.straight", "the live board's id never moves")
        XCTAssertNil(LeaderboardID.identifier(deck: "smith", tier: "regular"), "old id resolves no board")
    }

    // MARK: - Save migration

    func testDeckIdMigrationCarriesWinsStatsAndTheSave() {
        let store = MemoryStore()
        // An old install: smith cleared regular+legendary, lammy regular; a
        // lammy high score; an in-flight smith climb.
        store.set(#"{"smith":true,"smith.legendary":true,"lammy":true}"#,
                  forKey: DeckUnlocks.key)
        store.set(#"{"deckTierBest":{"smith.regular":220,"lammy.regular":90},"runsPlayed":12}"#,
                  forKey: Stats.key)
        store.set(#"{"deckId":"smith","phase":"map"}"#, forKey: SaveStore.key)
        SaveMigrations.migrateDeckIds(store)
        let wins = DeckUnlocks(store: store)
        XCTAssertTrue(wins.wonWith("garden"), "smith's base win carried")
        XCTAssertTrue(wins.wonWithTier("garden", "legendary"), "smith's legendary carried")
        XCTAssertTrue(wins.wonWith("rocko"), "lammy's win carried")
        XCTAssertFalse(wins.wonWith("smith"), "nothing left under the old key")
        let stats = store.string(forKey: Stats.key) ?? ""
        XCTAssertTrue(stats.contains(#""garden.regular":220"#), "high score followed the rename")
        XCTAssertTrue(stats.contains(#""rocko.regular":90"#))
        XCTAssertFalse(stats.contains("smith"), "no stale ids in stats")
        let save = store.string(forKey: SaveStore.key) ?? ""
        XCTAssertTrue(save.contains(#""deckId":"garden""#), "the in-flight climb migrated")
        // Idempotent: running again changes nothing.
        let before = store.string(forKey: Stats.key)
        SaveMigrations.migrateDeckIds(store)
        XCTAssertEqual(store.string(forKey: Stats.key), before)
    }

    func testUnlockProgressSurvivesTheChainReorder() {
        // Old world: a player who beat Mamma could play Smith; who beat Smith
        // could play Lammy. New world: Mamma → Slyrex → Garden → Rocko. After
        // migration, a smith winner (now garden) still unlocks rocko, and any
        // mamma winner unlocks slyrex — nobody loses a playable deck.
        let store = MemoryStore()
        store.set(#"{"pink":true,"mamma":true,"smith":true}"#, forKey: DeckUnlocks.key)
        SaveMigrations.migrateDeckIds(store)
        let wins = DeckUnlocks(store: store)
        XCTAssertTrue(wins.wonWith("mamma"), "slyrex's requirement (mamma win) is met")
        XCTAssertTrue(wins.wonWith("garden"), "rocko's requirement (garden win) is met")
    }
}
