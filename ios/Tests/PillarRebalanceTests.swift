import XCTest
@testable import GameCore

/// v6.87 PILLAR REBALANCE. Two batch-level pins the per-item validation
/// can't carry alone:
/// 1. the EMPTY RANKS family — ONE derived condition (ranks with zero
///    copies in the full deck), THREE effect keys, three DIFFERENT
///    observables from the SAME constructed deck;
/// 2. the retired pillars are out of EVERY acquisition path (v6.87
///    also closed the hole: `inactive` used to gate stickers only — a
///    retired pillar kept rolling onto shelves; v6.94 added the flat
///    pile-size family — seven pillars, one base, one same-power).
final class PillarRebalanceTests: XCTestCase {
    private let data = GameData.shared

    // MARK: - The Empty Ranks family: same condition, three effects

    /// One board, one deck (ranks 5–14 present → 2/3/4 empty = 3 ranks),
    /// one landing per leg in its own suit. Each leg produces ITS effect
    /// and neither of the other two.
    func testEmptyRanksFamilyThreeLegsThreeDistinctEffects() {
        let tops = [IV.spec(1, 5, "♠"), IV.spec(2, 6, "♥"), IV.spec(3, 7, "♣")]
        let fillers = [9, 10, 11, 12, 13, 14, 14, 13, 12, 11].enumerated().map {
            IV.spec(51 + $0.offset, $0.element, "♥")
        }
        func land(_ pillarId: String, drawnSuit: String) -> GameEngine {
            let e = IV.engine(tops: tops, deckOrder: [IV.spec(50, 8, drawnSuit)] + fillers,
                              pillars: [pillarId, nil, nil])
            e.guess(0, .higher)
            return e
        }
        // The BURY leg: 3 cards under the pile — no coins, no size latch.
        let bury = land("zeroRanksBury", drawnSuit: "♣")
        XCTAssertEqual(bury.board.piles[0].cards.count, 1 + 1 + 3, "bury: 3 buried under the landing")
        XCTAssertEqual(bury.run.bonusCoins, 0, "bury: no coins")
        XCTAssertEqual(bury.board.pileSize(0), 5, "bury: size = its 5 physical cards, no latch")
        // The COIN leg (v6.98 retrigger): fires on the MOST-HELD rank now,
        // not ♥ — two extra 8s make the landing 8 the leader; the empty
        // ranks are still 2, 3, 4.
        let coinE = IV.engine(tops: tops,
                              deckOrder: [IV.spec(50, 8, "♥")] + fillers
                                  + [IV.spec(61, 8, "♥"), IV.spec(62, 8, "♠")],
                              pillars: ["heartZeroRanksCoin", nil, nil])
        coinE.guess(0, .higher)
        let v = data.pillarTypes.get("heartZeroRanksCoin")!.num("value", 2)
        XCTAssertEqual(coinE.run.bonusCoins, v * 3, "coins: +value per empty rank")
        XCTAssertEqual(coinE.board.piles[0].cards.count, 2, "coins: nothing buried")
        XCTAssertEqual(coinE.board.pileSize(0), 2, "coins: no size latch")
        // The SIZE leg: +value × 3 latched — nothing buried, no coins.
        let size = land("diamondZeroRanksSize", drawnSuit: "♦")
        XCTAssertEqual(size.board.pileSize(0), 2 + 3, "size: +1 per empty rank, latched")
        XCTAssertEqual(size.board.piles[0].cards.count, 2, "size: nothing buried")
        XCTAssertEqual(size.run.bonusCoins, 0, "size: no coins")
        // Three ids, three keys — nobody shares the bury key.
        XCTAssertEqual(data.pillarTypes.get("zeroRanksBury")?.effect, "clubZeroRanksBury")
        XCTAssertEqual(data.pillarTypes.get("heartZeroRanksCoin")?.effect, "heartZeroRanksCoin")
        XCTAssertEqual(data.pillarTypes.get("diamondZeroRanksSize")?.effect, "diamondZeroRanksSize")
    }

    // MARK: - The v6.87 retirement set is out of every acquisition path

    func testInactivePillarsNeverAppearFromAnyAcquisitionPath() {
        let retired: Set<String> = ["clubTribute", "clubThin", "absentSuitClubBury",
                                    "excavator", "prime", "allHeartsCoin", "highestEven",
                                    "gambler", "static", "sameTolSum10",
                                    // v6.94: the flat pile-size family joins them.
                                    "streakBank", "stickerCount", "diamondZeroRanksSize",
                                    "eightStart", "diamondDupeSize", "pauperDiamond",
                                    "sizeOneDiamonds"]
        XCTAssertEqual(Set(data.items.pillars.filter(\.inactive).map(\.id)), retired,
                       "the v6.87 + v6.94 retirement sets, exactly")
        // The chokepoint every class pools through now (the v6.87 fix —
        // grantableBase used to be consulted for stickers only):
        XCTAssertFalse(data.pillarTypes.grantableBase().contains { retired.contains($0.id) })
        // Store shelves, EVERY kind, many seeds:
        for seed: UInt32 in 1...120 {
            let rng = RNG(seed: seed)
            var scratch: [String: ShopRoll] = [:]
            let slots = StoreRoll.rollUnifiedSlots(rng, count: 12, data: data,
                                                   isUnlocked: { _ in true }, genCard: nil,
                                                   shopRolls: &scratch)
            for s in slots.compactMap({ $0 }) {
                XCTAssertFalse(retired.contains(s.id),
                               "seed \(seed): retired '\(s.id)' rolled onto a shelf as \(s.kind)")
            }
        }
        // …and the registry still resolves every one for old saves + the
        // greyed Collection tile.
        for id in retired {
            XCTAssertNotNil(data.pillarTypes.get(id), "'\(id)' stays registered")
        }
    }

    // MARK: - The v6.94 base + same-power retirements are out too

    /// Diamond Boost (base) and Same Heavy (same-power) retired with the
    /// pile-size family — same contract: out of every pool, still resolved.
    func testRetiredBaseAndSamePowerNeverAppearFromAnyAcquisitionPath() {
        XCTAssertEqual(Set(data.items.bases.filter(\.inactive).map(\.id)),
                       ["transmute", "diamondBoost"], "the retired bases, exactly")
        XCTAssertEqual(Set(data.items.samePowers.filter(\.inactive).map(\.id)),
                       ["linkHeavy"], "the retired same-powers, exactly")
        XCTAssertFalse(data.baseTypes.grantableBase().contains { $0.id == "diamondBoost" })
        XCTAssertFalse(data.samePowerTypes.grantableBase().contains { $0.id == "linkHeavy" })
        // Store shelves, EVERY kind, many seeds:
        let retired: Set<String> = ["diamondBoost", "linkHeavy"]
        for seed: UInt32 in 1...120 {
            let rng = RNG(seed: seed)
            var scratch: [String: ShopRoll] = [:]
            let slots = StoreRoll.rollUnifiedSlots(rng, count: 12, data: data,
                                                   isUnlocked: { _ in true }, genCard: nil,
                                                   shopRolls: &scratch)
            for s in slots.compactMap({ $0 }) {
                XCTAssertFalse(retired.contains(s.id),
                               "seed \(seed): retired '\(s.id)' rolled onto a shelf as \(s.kind)")
            }
        }
        // …and both stay registered for old saves.
        XCTAssertNotNil(data.baseTypes.get("diamondBoost"))
        XCTAssertNotNil(data.samePowerTypes.get("linkHeavy"))
    }
}
