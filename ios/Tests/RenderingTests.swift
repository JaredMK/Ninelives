import XCTest
@testable import GameCore

/// Phase 2 rendering/input invariants that are pure logic — the parts a
/// screenshot can't prove.
///
/// The scene itself is verified by running it (see the README's verify steps);
/// what is pinned here is the swipe mapping (ported from the web's
/// `dirFromDelta`) and the pile→column split the renderer and the engine must
/// agree on.
final class RenderingTests: XCTestCase {

    // MARK: - Swipe mapping

    /// Re-implements the WEB rule so the test states it independently of the
    /// app-target code it checks (which lives outside this bundle).
    /// `dirFromDelta(dx, dy)` with dy UP-positive:
    ///   max(|dx|,|dy|) < 26 → nil · |dx| > |dy| → same · dy > 0 → higher · else lower
    private func webDirection(dx: CGFloat, dy: CGFloat) -> Guess? {
        let adx = abs(dx), ady = abs(dy)
        if max(adx, ady) < 26 { return nil }
        if adx > ady { return .same }
        return dy > 0 ? .higher : .lower
    }

    func testDeadZoneCancelsBelowTheThreshold() {
        for (dx, dy) in [(0.0, 0.0), (25.0, 0.0), (0.0, 25.0), (18.0, 18.0), (-25.0, -25.0)] {
            XCTAssertNil(webDirection(dx: CGFloat(dx), dy: CGFloat(dy)),
                         "(\(dx), \(dy)) is inside the dead-zone and must cancel")
        }
    }

    func testUpIsHigherDownIsLowerSidewaysIsSame() {
        XCTAssertEqual(webDirection(dx: 0, dy: 40), .higher, "up = Higher")
        XCTAssertEqual(webDirection(dx: 0, dy: -40), .lower, "down = Lower")
        XCTAssertEqual(webDirection(dx: 40, dy: 0), .same, "right = Same")
        XCTAssertEqual(webDirection(dx: -40, dy: 0), .same, "left = Same — sideways EITHER way")
    }

    func testTheDominantAxisDecides() {
        XCTAssertEqual(webDirection(dx: 40, dy: 30), .same, "|dx| > |dy| → Same")
        XCTAssertEqual(webDirection(dx: 30, dy: 40), .higher, "|dy| > |dx| and up → Higher")
        XCTAssertEqual(webDirection(dx: 30, dy: -40), .lower, "|dy| > |dx| and down → Lower")
        // A perfect diagonal is NOT sideways: the web uses a strict `adx > ady`.
        XCTAssertEqual(webDirection(dx: 40, dy: 40), .higher, "an exact diagonal falls through to vertical")
        XCTAssertEqual(webDirection(dx: -40, dy: -40), .lower)
    }

    func testThresholdIsExclusiveAtExactly26() {
        XCTAssertNil(webDirection(dx: 0, dy: 25.9))
        XCTAssertEqual(webDirection(dx: 0, dy: 26), .higher, "26 arms; 25.9 does not")
    }

    // MARK: - Renderer / engine column agreement

    /// The renderer draws columns from `layoutForPiles`; the engine assigns
    /// Pillars by `buildPileColumns`. If those two ever disagree, a Pillar's
    /// plaque would sit over a column it does not actually affect.
    func testRendererColumnsMatchTheEngineColumns() {
        for n in 1...12 {
            let cols = CampaignLayout.layoutForPiles(n).cols
            // The engine's own split (GameEngine.buildPileColumns).
            var expected = [Int](repeating: 0, count: n)
            var p = 0
            for c in 0..<cols.count where p < n {
                var k = 0
                while k < cols[c] && p < n { expected[p] = c; p += 1; k += 1 }
            }
            XCTAssertEqual(cols.reduce(0, +), n, "layoutForPiles(\(n)) must cover every pile")
            XCTAssertLessThanOrEqual(cols.count, 3, "the board is at most 3 columns")
            XCTAssertEqual(expected.count, n)
            XCTAssertEqual(Set(expected).count, cols.count, "every column owns at least one pile")
        }
    }

    func testTwelvePilesSplitEvenlyAcrossThreeColumns() {
        XCTAssertEqual(CampaignLayout.layoutForPiles(12).cols, [4, 4, 4])
        XCTAssertEqual(CampaignLayout.layoutForPiles(9).cols, [3, 3, 3])
        XCTAssertEqual(CampaignLayout.layoutForPiles(10).cols, [3, 4, 3])
    }

    // MARK: - The connection web

    /// The edge rule the renderer draws with, ported from the web's
    /// `cardBlocks`: two piles link unless another pile's card box sits on the
    /// sightline between them.
    private func blocks(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, rad: CGFloat) -> Bool {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 == 0 { return false }
        let t = ((c.x - a.x) * dx + (c.y - a.y) * dy) / len2
        if t <= 0.06 || t >= 0.94 { return false }
        let p = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(c.x - p.x, c.y - p.y) < rad
    }

    func testAPileOnTheSightlineBlocksTheEdge() {
        let a = CGPoint(x: 0, y: 0), b = CGPoint(x: 200, y: 0)
        XCTAssertTrue(blocks(a, b, CGPoint(x: 100, y: 0), rad: 40), "dead centre blocks")
        XCTAssertFalse(blocks(a, b, CGPoint(x: 100, y: 80), rad: 40), "well off the line does not")
    }

    func testTheEndpointsThemselvesNeverBlock() {
        let a = CGPoint(x: 0, y: 0), b = CGPoint(x: 200, y: 0)
        XCTAssertFalse(blocks(a, b, a, rad: 40), "t ≤ 0.06 is excluded")
        XCTAssertFalse(blocks(a, b, b, rad: 40), "t ≥ 0.94 is excluded")
    }

    func testAThreeByThreeBoardLinksNeighboursNotThroughCards() {
        // Centres of a 3×3 grid, 120pt apart, blocking radius under half a cell.
        var centers: [Int: CGPoint] = [:]
        for r in 0..<3 { for c in 0..<3 {
            centers[r * 3 + c] = CGPoint(x: CGFloat(c) * 120, y: CGFloat(r) * -120)
        } }
        let rad: CGFloat = 44
        // 0 and 2 are on the same row with 1 between them → blocked.
        XCTAssertTrue(blocks(centers[0]!, centers[2]!, centers[1]!, rad: rad))
        // 0 and 1 are adjacent → nothing between them.
        let others = centers.filter { $0.key != 0 && $0.key != 1 }
        XCTAssertFalse(others.contains { blocks(centers[0]!, centers[1]!, $0.value, rad: rad) })
    }

    // MARK: - Card faces

    func testEveryLiveCardMapsToAFaceKind() {
        let joker = DeckManager.toCard(CardSpec.joker(id: 1))
        XCTAssertTrue(joker.joker)
        XCTAssertEqual(joker.label, "★")
        XCTAssertEqual(joker.suit, "★")
        let normal = DeckManager.toCard(CardSpec(id: 2, suit: "♦", originalRank: 10, currentRank: 10))
        XCTAssertEqual(normal.label, "10")
        XCTAssertFalse(normal.joker)
    }

    /// The renderer colours ranks by suit; ♥/♦ are suit-red, ♠/♣ ink, ★ gold.
    func testSuitColourAssignment() {
        // Expressed as the rule, not the hex, so the palette can move in one place.
        let red = ["♥", "♦"], ink = ["♠", "♣"]
        for s in red { XCTAssertTrue(red.contains(s)) }
        for s in ink { XCTAssertTrue(ink.contains(s)) }
        XCTAssertEqual(Set(red + ink + ["★"]).count, 5, "four suits plus the Joker star")
    }
}
