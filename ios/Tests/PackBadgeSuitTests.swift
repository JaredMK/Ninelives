import XCTest
@testable import GameCore

/// PACK BADGE (v6.61): the map badge must advertise exactly the suit set of
/// the cards the pack ACTUALLY grants. `packSuits(for:)` derives it by
/// replaying the seeded resolution stream (no cards materialize), so this
/// pins the replay against the real `resolvePack` across seeds — including
/// pink's altSuits packs, whose badge used to print all four suits always.
final class PackBadgeSuitTests: XCTestCase {

    func testBadgeSuitsEqualResolvedContents() {
        var packsChecked = 0
        for seed: UInt32 in [11, 222, 3333, 44444, 987_654, 20_260_818] {
            let c = CampaignState()
            c.setDeck("pink"); c.setSeedOverride(seed); c.reset()
            let packs = (c.runMap?.nodes ?? []).filter { $0.type == "pack" }
            // Derive every badge FIRST — the advertised set is a promise made
            // before the player collects anything — then resolve the packs
            // sequentially: grants along the way must not bend later badges.
            let advertised = packs.map { c.packSuits(for: $0) }
            for (node, badge) in zip(packs, advertised) {
                let contents = c.resolvePack(node)
                let got = Set(contents.filter { !$0.blank }.map(\.suit))
                XCTAssertEqual(got, Set(badge),
                               "seed \(seed) node \(node.id) (+\(node.addOf)): badge \(badge) vs contents \(got)")
                XCTAssertEqual(badge.count, Set(badge).count,
                               "seed \(seed) node \(node.id): badge is deduped — no per-suit counts leak")
                XCTAssertEqual(badge, DeckManager.suits.map(\.symbol).filter { badge.contains($0) },
                               "seed \(seed) node \(node.id): fixed suit order — no roll-order leak")
                packsChecked += 1
            }
        }
        XCTAssertGreaterThan(packsChecked, 5, "the seed sample actually exercised pack nodes")
    }

    /// The badge is a pure read: deriving it twice, before and after other
    /// packs resolve, returns the same set (collection-independence).
    func testBadgeIsStableAcrossCollectionChanges() {
        let c = CampaignState()
        c.setDeck("pink"); c.setSeedOverride(4242); c.reset()
        let packs = (c.runMap?.nodes ?? []).filter { $0.type == "pack" }
        guard packs.count >= 2 else { return }
        let laterBadgeEarly = c.packSuits(for: packs[1])
        _ = c.resolvePack(packs[0])                       // collection changes
        XCTAssertEqual(c.packSuits(for: packs[1]), laterBadgeEarly,
                       "resolving one pack must not change another pack's badge")
    }
}
