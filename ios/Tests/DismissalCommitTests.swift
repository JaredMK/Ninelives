import XCTest
@testable import GameCore

/// DISMISSAL RULES (committed placement): the pickers' confirmed Skip is a
/// real DISCARD, not a deferral. These pin the GameCore contract that skip
/// path rides on — a declined tray card / inventory sticker leaves for good,
/// with no refund, the tray fronts the next item at index 0 (the walk always
/// passes 0), and the loss survives the save round-trip.
final class DismissalCommitTests: XCTestCase {

    private func campaign() -> CampaignState {
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular"); c.reset()
        return c
    }

    func testConfirmedSkipDiscardsTheTrayCardNoRefund() {
        let c = campaign()
        let src = c.getRunDeck().first { !$0.joker && !$0.blank }!
        let copy = c.duplicateCard(src.id)!
        XCTAssertEqual(c.packTrayCount(), 1)
        let coins = c.getCoins()
        XCTAssertTrue(c.discardPackCard(0))
        XCTAssertEqual(c.packTrayCount(), 0)
        XCTAssertEqual(c.getCoins(), coins, "declining a held card refunds nothing")
        // The emptied tray has nothing left to swap in.
        XCTAssertNil(c.replaceDeckCard(src.id, trayIndex: 0))
        XCTAssertFalse(c.getRunDeck().contains { $0.id == copy.id })
    }

    func testTrayCompactsSoTheWalkAlwaysFrontsIndexZero() {
        let c = campaign()
        let cards = c.getRunDeck().filter { !$0.joker && !$0.blank }
        let a = c.duplicateCard(cards[0].id)!
        let b = c.duplicateCard(cards[1].id)!
        XCTAssertEqual(c.getPackTray().map(\.id), [a.id, b.id])
        XCTAssertTrue(c.discardPackCard(0))
        XCTAssertEqual(c.getPackTray().map(\.id), [b.id],
                       "the next held card surfaces at 0 for the walk's next step")
    }

    func testConfirmedSkipDiscardsOneInventoryStickerCopy() {
        let c = campaign()
        // Live registry, never a pinned id.
        let type = c.data.items.stickers.first { !$0.cursed }!.id
        XCTAssertTrue(c.addStickerToInventory(type))
        XCTAssertTrue(c.addStickerToInventory(type))
        XCTAssertTrue(c.useStickerFromInventory(type))
        XCTAssertEqual(c.inventoryCount(type), 1, "one copy discarded, the other kept")
        XCTAssertTrue(c.useStickerFromInventory(type))
        XCTAssertEqual(c.inventoryCount(type), 0)
        XCTAssertFalse(c.useStickerFromInventory(type),
                       "an empty inventory has nothing left to discard")
    }

    func testDiscardsSurviveTheSaveRoundTrip() {
        let c = campaign()
        let src = c.getRunDeck().first { !$0.joker && !$0.blank }!
        _ = c.duplicateCard(src.id)
        let type = c.data.items.stickers.first { !$0.cursed }!.id
        _ = c.addStickerToInventory(type)
        _ = c.discardPackCard(0)
        _ = c.useStickerFromInventory(type)
        let c2 = CampaignState(store: MemoryStore())
        XCTAssertTrue(c2.restore(c.serialize()))
        XCTAssertEqual(c2.packTrayCount(), 0, "the declined tray card stays gone")
        XCTAssertEqual(c2.inventoryCount(type), 0, "the discarded sticker stays gone")
    }
}
