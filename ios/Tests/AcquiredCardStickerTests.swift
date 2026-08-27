import XCTest
@testable import GameCore

/// v6.86 (batch item 11): identity-MUTATING stickers — suit changers, ±rank,
/// random rank — never arrive PRE-ATTACHED on an acquired card. The store
/// card slot and bought card packs mint through `genNormalCard`; sealed map
/// packs dress through `applyPackCardStickers` (pinned in
/// MapCardStickerTests). They only exist as standalone stickers the player
/// places. Wild Suit stays grantable on cards.
final class AcquiredCardStickerTests: XCTestCase {
    private let data = GameData.shared

    func testTheExclusionSetIsExactlyTheIdentityMutators() {
        let excluded = Set(data.items.stickers.filter(\.mutatesCardIdentity).map(\.id))
        for id in ["rankUp", "rankDown", "rankUp2", "rankDown2",
                   "randomFixedValue", "changeSuitRandom",
                   "changeSuitSpade", "changeSuitHeart", "changeSuitDiamond", "changeSuitClub"] {
            XCTAssertTrue(excluded.contains(id), "'\(id)' must never pre-attach")
        }
        XCTAssertFalse(excluded.contains("wildSuit"), "Wild Suit stays allowed — it widens, never rewrites")
        XCTAssertFalse(excluded.contains("tell"), "plain stickers stay allowed")
        XCTAssertFalse(excluded.contains("tieSafe"), "Same-Safe stays allowed")
    }

    func testMintedCardsNeverPreCarryMutatingStickers() {
        // Store card slot + bought card packs both mint via genNormalCard.
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular"); c.setSeedOverride(7); c.reset()
        let rng = RNG(seed: 99)
        var dressed = 0
        for _ in 0..<400 {
            let card = c.genNormalCard(rng, curseChance: 0)
            for s in card.stickers {
                dressed += 1
                XCTAssertFalse(data.stickerTypes.get(s.type)?.mutatesCardIdentity ?? false,
                               "a minted card pre-carried identity-mutating '\(s.type)'")
            }
        }
        XCTAssertGreaterThan(dressed, 0, "the odds table should dress SOME of 400 mints")
    }
}
