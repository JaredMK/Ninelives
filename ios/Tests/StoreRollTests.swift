import XCTest
@testable import GameCore

/// STORE ROLL REWORK (v6.58): each ROLLED slot draws its class independently
/// against `store.classWeights` (sticker 40 / pillar 20 / base 15 / card 10 /
/// pack 10 / samepower 5), then an item within the class by rarity. The
/// permanent Removal slot sits OUTSIDE the roll. These tests pin the realized
/// distribution over many shelves and the structural guarantees around it.
final class StoreRollTests: XCTestCase {

    private var nextCardId = 10_000
    private func mintCard(_ rng: RNG) -> CardSpec? {
        nextCardId += 1
        let rank = 2 + Int(rng.next() * 12)
        return CardSpec(id: nextCardId, suit: "♠", originalRank: rank, currentRank: rank)
    }

    private func rollShelves(_ n: Int, seed: UInt32 = 20_260_818) -> [[StoreSlot]] {
        let data = GameData.shared
        let rng = RNG(seed: seed)
        return (0..<n).map { _ in
            StoreRoll.rollUnifiedSlots(rng, count: data.items.store.slots - 1, data: data,
                                       isUnlocked: { _ in true }, isEquipped: nil,
                                       tierWeights: nil, genCard: { self.mintCard($0) })
                .compactMap { $0 }
        }
    }

    /// The data file carries the reworked weights — the test reads them live
    /// (never pins values) but the RATIO SHAPE is the design under test:
    /// sticker is the bulk, samepower the garnish, card and pack equal.
    func testClassWeightShape() {
        let cw = GameData.shared.items.store.classWeights
        let get = { (k: String) in cw[k] ?? 0 }
        XCTAssertGreaterThan(get("sticker"), get("pillar"))
        XCTAssertGreaterThan(get("pillar"), get("base"))
        XCTAssertGreaterThan(get("base"), get("card"))
        XCTAssertEqual(get("card"), get("pack"), "card and pack draw at the same weight")
        XCTAssertGreaterThan(get("samepower"), 0)
        XCTAssertLessThan(get("samepower"), get("pack"))
    }

    /// 4000 shelves × 5 rolled slots: every realized class share must sit
    /// near its configured weight. The type cap (3) and the one-mystery rule
    /// shave the sticker/samepower tails a little, so the windows are
    /// tolerant — ±2.5 points around each weight (wider under the cap).
    func testRealizedDistributionTracksWeights() {
        let data = GameData.shared
        let cw = data.items.store.classWeights
        let total = cw.values.reduce(0, +)
        let shelves = rollShelves(4000)
        var counts: [String: Int] = [:]
        var slotTotal = 0
        for shelf in shelves {
            XCTAssertEqual(shelf.count, data.items.store.slots - 1,
                           "every rolled slot fills — no dead slots")
            for s in shelf { counts[s.kind, default: 0] += 1; slotTotal += 1 }
        }
        for (key, w) in cw {
            let want = w / total
            let got = Double(counts[key] ?? 0) / Double(slotTotal)
            XCTAssertEqual(got, want, accuracy: 0.025,
                           "class \(key): realized \(got) vs configured \(want)")
        }
    }

    /// The max-per-type constraint survives the new weights: no shelf carries
    /// more than `typeCap` of one type, and no shelf repeats an item id.
    func testTypeCapAndNoRepeatHold() {
        let data = GameData.shared
        let cap = data.items.store.typeCap
        for shelf in rollShelves(2000) {
            var perType: [String: Int] = [:]
            var ids = Set<String>()
            for s in shelf {
                let key = s.kind == "card" ? "card" : StoreRoll.slotTypeKey(s.kind, s.id, data: data)
                perType[key, default: 0] += 1
                if s.kind != "card" {
                    XCTAssertTrue(ids.insert("\(s.kind).\(s.id)").inserted,
                                  "shelf repeated \(s.kind).\(s.id)")
                }
            }
            for (k, n) in perType {
                XCTAssertLessThanOrEqual(n, cap, "type \(k) over the cap (\(n))")
            }
            // The mystery Same-Power shares one id, so it can never exceed 1.
            XCTAssertLessThanOrEqual(shelf.filter { $0.kind == "samepower" }.count, 1)
        }
    }

    /// The permanent Removal slot stays OUTSIDE the roll: freshOffer rolls
    /// slots−1 and appends removal LAST, at every weight configuration.
    func testRemovalSlotOutsideTheRoll() {
        let data = GameData.shared
        let offer = StoreRoll.freshOffer(RNG(seed: 99), data: data, removalOn: true,
                                         isUnlocked: { _ in true }, isEquipped: nil,
                                         tierWeights: nil, genCard: { self.mintCard($0) })
        XCTAssertEqual(offer.slots.count, data.items.store.slots)
        XCTAssertEqual(offer.slots.last??.kind, "removal", "removal is the fixed last slot")
        XCTAssertEqual(offer.slots.dropLast().compactMap { $0 }.filter { $0.kind == "removal" }.count,
                       0, "removal never appears among the rolled slots")
    }

    /// Diagnostic composition sample: prints the realized shares and the
    /// per-shelf composition histogram (report material, asserts nothing
    /// beyond a sane shelf size).
    func testCompositionSampleReport() {
        let shelves = rollShelves(4000)
        var counts: [String: Int] = [:]
        var perShelfSticker: [Int: Int] = [:]
        for shelf in shelves {
            for s in shelf { counts[s.kind, default: 0] += 1 }
            perShelfSticker[shelf.filter { $0.kind == "sticker" }.count, default: 0] += 1
        }
        let slotTotal = shelves.reduce(0) { $0 + $1.count }
        let shares = counts.sorted { $0.value > $1.value }
            .map { String(format: "%@ %.1f%%", $0.key, 100 * Double($0.value) / Double(slotTotal)) }
            .joined(separator: " · ")
        let hist = perShelfSticker.sorted { $0.key < $1.key }
            .map { "\($0.key)×sticker: \(String(format: "%.1f%%", 100 * Double($0.value) / Double(shelves.count)))" }
            .joined(separator: " · ")
        print("STORE COMPOSITION over \(shelves.count) shelves — \(shares)")
        print("STICKERS PER SHELF — \(hist)")
        XCTAssertGreaterThan(slotTotal, 0)
    }
}
