import XCTest
@testable import GameCore

final class SmokeTests: XCTestCase {
    func testDataLoads() throws {
        let d = try GameData.load(from: Bundle(for: GameData.self))
        XCTAssertFalse(d.items.stickers.isEmpty)
    }
}
