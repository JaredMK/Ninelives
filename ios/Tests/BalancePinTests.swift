import XCTest
@testable import GameCore

/// Deliberate DESIGN PINS — values the user has retuned repeatedly and asked
/// to be held by test. Unlike the registry-driven suites (which read live so
/// data stays the source of truth), these assert the agreed number itself:
/// a retune should CONSCIOUSLY update the pin.
final class BalancePinTests: XCTestCase {
    /// v6.74 batch: "Bonus Coin → cost 2".
    func testBonusCoinCostsTwo() {
        XCTAssertEqual(GameData.shared.stickerTypes.get("gainCoin")?.price, 2,
                       "Bonus Coin costs 2 (pinned by request)")
    }

    /// v6.71 batch: "set the payout to 8 coins (I've moved it twice)".
    func testInsurancePaysEight() {
        let def = GameData.shared.pillarTypes.get("insurance")
        XCTAssertEqual(def?.value, 8, "Insurance pays +8 at deal end (pinned by request)")
        XCTAssertTrue(def?.description.contains("+8 coins") == true,
                      "the help text states the pinned payout")
    }
}
