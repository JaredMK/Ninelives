import XCTest
@testable import GameCore

/// Deliberate DESIGN PINS — values the user has retuned repeatedly and asked
/// to be held by test. Unlike the registry-driven suites (which read live so
/// data stays the source of truth), these assert the agreed number itself:
/// a retune should CONSCIOUSLY update the pin.
final class BalancePinTests: XCTestCase {
    /// v6.74 pinned cost 2; v6.98 GLOBAL FLATTENING supersedes it — every
    /// active sticker prices by rarity (common 1 / uncommon 3 / rare 5), so
    /// the pin now holds the flat rule for the same item.
    func testBonusCoinCostsTheFlatUncommonPrice() {
        XCTAssertEqual(GameData.shared.stickerTypes.get("gainCoin")?.price, 3,
                       "Bonus Coin is uncommon → flat price 3 (v6.98 rule, pinned)")
    }

    /// v6.71 batch: "set the payout to 8 coins (I've moved it twice)".
    func testInsurancePaysEight() {
        let def = GameData.shared.pillarTypes.get("insurance")
        XCTAssertEqual(def?.value, 8, "Insurance pays +8 at deal end (pinned by request)")
        XCTAssertTrue(def?.description.contains("+8 coins") == true,
                      "the help text states the pinned payout")
    }
}
