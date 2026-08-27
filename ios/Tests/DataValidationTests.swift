import XCTest
@testable import GameCore

/// Mirrors the web suite's data-validation coverage: the bundled data files
/// must load, and a malformed entry must FAIL LOUDLY naming the item and field
/// — items are never silently dropped.
final class DataValidationTests: XCTestCase {

    private let data = GameData.shared

    // MARK: - The shipped data loads

    func testBundledDataLoads() throws {
        let d = try GameData.loadBundled()
        XCTAssertFalse(d.items.stickers.isEmpty)
        XCTAssertFalse(d.items.pillars.isEmpty)
        XCTAssertFalse(d.items.bases.isEmpty)
        XCTAssertFalse(d.items.samePowers.isEmpty)
        XCTAssertFalse(d.items.packs.isEmpty)
    }

    func testEveryGroupHasUniqueIds() {
        for (name, list) in [("stickers", data.items.stickers), ("pillars", data.items.pillars),
                             ("bases", data.items.bases), ("samePowers", data.items.samePowers),
                             ("packs", data.items.packs)] {
            let ids = list.map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count, "\(name) has duplicate ids")
            for id in ids { XCTAssertFalse(id.isEmpty, "\(name) has an empty id") }
        }
    }

    func testEveryEntryHasTierPriceDescription() {
        for (name, list) in [("stickers", data.items.stickers), ("pillars", data.items.pillars),
                             ("bases", data.items.bases), ("samePowers", data.items.samePowers),
                             ("packs", data.items.packs)] {
            for e in list {
                XCTAssertTrue(ItemData.tiers.contains(e.tier), "\(name) '\(e.id)': bad tier \(e.tier)")
                XCTAssertGreaterThanOrEqual(e.price, 0, "\(name) '\(e.id)': negative price")
                XCTAssertFalse(e.description.isEmpty, "\(name) '\(e.id)': empty description")
                XCTAssertFalse(e.label.isEmpty, "\(name) '\(e.id)': empty label")
            }
        }
    }

    func testRequiredPerGroupFields() {
        for e in data.items.stickers { XCTAssertNotNil(e.kind, "sticker '\(e.id)': missing kind") }
        for e in data.items.pillars {
            XCTAssertNotNil(e.kind, "pillar '\(e.id)': missing kind")
            XCTAssertNotNil(e.effect, "pillar '\(e.id)': missing effect")
        }
        for e in data.items.bases {
            XCTAssertNotNil(e.kind, "base '\(e.id)': missing kind")
            XCTAssertNotNil(e.effect, "base '\(e.id)': missing effect")
        }
        for e in data.items.samePowers { XCTAssertNotNil(e.effect, "samePower '\(e.id)': missing effect") }
        for e in data.items.packs { XCTAssertNotNil(e.kind, "pack '\(e.id)': missing kind") }
    }

    func testAtLeastOneCursedSticker() {
        // The mystery cursedSticker outcome rolls from this pool.
        XCTAssertTrue(data.items.stickers.contains { $0.cursed })
    }

    func testUnlockGatesAreWellFormed() {
        for e in (data.items.stickers + data.items.pillars + data.items.bases
                  + data.items.samePowers + data.items.packs) {
            guard let u = e.unlock else { continue }
            XCTAssertTrue(["milestone", "behavior"].contains(u.type), "'\(e.id)': bad unlock.type")
            XCTAssertTrue(data.meta.itemUnlockStats.contains(u.stat), "'\(e.id)': unknown unlock.stat \(u.stat)")
            XCTAssertGreaterThan(u.count, 0, "'\(e.id)': unlock.count must be positive")
        }
    }

    func testSuitRestrictionsUseRealSuits() {
        for e in data.items.stickers {
            guard let suits = e.suits else { continue }
            XCTAssertFalse(suits.isEmpty, "sticker '\(e.id)': empty suits array")
            for s in suits { XCTAssertTrue(["♠", "♥", "♦", "♣"].contains(s), "sticker '\(e.id)': bad suit \(s)") }
        }
    }

    func testPackStickerOddsStrictlyAscend() {
        var prev = -Double.infinity
        for pair in data.items.packStickerOdds {
            XCTAssertEqual(pair.count, 2)
            XCTAssertGreaterThan(pair[0], 0)
            XCTAssertLessThanOrEqual(pair[0], 1)
            XCTAssertGreaterThan(pair[0], prev, "packStickerOdds maxRoll must strictly ascend")
            prev = pair[0]
            XCTAssertEqual(pair[1], pair[1].rounded(), "stickerCount must be an integer")
        }
    }

    func testStoreConfigShape() {
        let s = data.items.store
        XCTAssertGreaterThan(s.slots, 0)
        XCTAssertGreaterThan(s.typeCap, 0)
        XCTAssertGreaterThanOrEqual(s.reroll.baseCost, 0)
        XCTAssertGreaterThanOrEqual(s.reroll.step, 0)
        for t in ItemData.tiers { XCTAssertGreaterThan(s.tierWeights[t] ?? 0, 0, "tierWeights.\(t)") }
        for k in ["sticker", "pillar", "base", "pack", "card", "samepower"] {
            XCTAssertGreaterThanOrEqual(s.classWeights[k] ?? -1, 0, "classWeights.\(k)")
        }
        XCTAssertGreaterThanOrEqual(s.card.price, 0)
        XCTAssertGreaterThanOrEqual(s.card.jokerPrice, 0)
        XCTAssertGreaterThanOrEqual(s.removal.price, 0)
    }

    func testMysteryConfigShape() {
        let m = data.items.mystery
        for k in MysteryConfig.outcomeKeys { XCTAssertGreaterThan(m.weights[k] ?? 0, 0, "mystery.weights.\(k)") }
        XCTAssertFalse(m.coinRangeByStage.isEmpty)
        for pair in m.coinRangeByStage {
            XCTAssertGreaterThanOrEqual(pair[0], 0)
            XCTAssertGreaterThanOrEqual(pair[1], pair[0])
        }
        XCTAssertEqual(m.cardGrantRange.count, 2)
        XCTAssertGreaterThanOrEqual(m.cardGrantRange[0], 1)
        XCTAssertGreaterThanOrEqual(m.cardGrantRange[1], m.cardGrantRange[0])
        XCTAssertGreaterThan(m.ambush.cards, 0)
        XCTAssertGreaterThan(m.ambush.piles, 0)
        XCTAssertGreaterThan(m.ambush.bounty, 0)
    }

    func testEconomyConfigShape() {
        XCTAssertEqual(data.items.economy.dealPayouts.count, 3,
                       "one payout per difficulty rating 1..3")
        for p in data.items.economy.dealPayouts { XCTAssertGreaterThan(p, 0) }
        XCTAssertGreaterThan(data.items.economy.bossPayout, 0)
    }

    // MARK: - Fail-loud contract

    /// A malformed items entry must throw, naming the group, the id and the field.
    func testMalformedItemFailsLoudNamingTheItemAndField() throws {
        var root = try JSONDecoder().decode([String: JSONValue].self, from: try shippedJSON("items"))
        var stickers = root["stickers"]!.asArray!
        var first = stickers[0].asObject!
        let id = first["id"]!.asString!
        first["tier"] = .string("mythic")           // not one of common|uncommon|rare
        stickers[0] = .object(first)
        root["stickers"] = .array(stickers)

        XCTAssertThrowsError(try ItemData.decode(try encode(root), unlockStats: data.meta.itemUnlockStats)) { err in
            guard let e = err as? DataValidationError else { return XCTFail("wrong error type: \(err)") }
            XCTAssertTrue(e.problems.contains { $0.contains("stickers '\(id)'") && $0.contains("`tier`") },
                          "problem list must name the item AND the field; got \(e.problems)")
            XCTAssertTrue(e.description.contains("validation FAILED"))
        }
    }

    func testDuplicateIdFailsLoud() throws {
        var root = try JSONDecoder().decode([String: JSONValue].self, from: try shippedJSON("items"))
        var pillars = root["pillars"]!.asArray!
        pillars.append(pillars[0])                  // an exact duplicate id
        root["pillars"] = .array(pillars)
        let dupId = pillars[0]["id"]!.asString!
        XCTAssertThrowsError(try ItemData.decode(try encode(root), unlockStats: data.meta.itemUnlockStats)) { err in
            let e = err as! DataValidationError
            XCTAssertTrue(e.problems.contains { $0.contains("pillars '\(dupId)'") && $0.contains("duplicate id") },
                          "got \(e.problems)")
        }
    }

    func testUnknownUnlockStatFailsLoud() throws {
        var root = try JSONDecoder().decode([String: JSONValue].self, from: try shippedJSON("items"))
        var bases = root["bases"]!.asArray!
        var first = bases[0].asObject!
        let id = first["id"]!.asString!
        first["unlock"] = .object(["type": .string("behavior"), "stat": .string("notAStat"), "count": .number(3)])
        bases[0] = .object(first)
        root["bases"] = .array(bases)
        XCTAssertThrowsError(try ItemData.decode(try encode(root), unlockStats: data.meta.itemUnlockStats)) { err in
            let e = err as! DataValidationError
            XCTAssertTrue(e.problems.contains { $0.contains("bases '\(id)'") && $0.contains("unlock.stat") },
                          "got \(e.problems)")
        }
    }

    func testMissingStoreConfigFailsLoud() throws {
        var root = try JSONDecoder().decode([String: JSONValue].self, from: try shippedJSON("items"))
        root["store"] = .null
        XCTAssertThrowsError(try ItemData.decode(try encode(root), unlockStats: data.meta.itemUnlockStats)) { err in
            let e = err as! DataValidationError
            XCTAssertTrue(e.problems.contains { $0.contains("store: missing config object") }, "got \(e.problems)")
        }
    }

    func testDifficultyBandInversionFailsLoud() throws {
        var root = try JSONDecoder().decode([String: JSONValue].self, from: try shippedJSON("difficulty"))
        var tiers = root["tiers"]!.asObject!
        var reg = tiers["regular"]!.asObject!
        var bands = reg["stageBands"]!.asArray!
        bands[0] = .array([.number(9), .number(2)])          // lo > hi
        reg["stageBands"] = .array(bands)
        tiers["regular"] = .object(reg)
        root["tiers"] = .object(tiers)
        XCTAssertThrowsError(try DifficultyData.decode(try encode(root))) { err in
            let e = err as! DataValidationError
            XCTAssertTrue(e.problems.contains { $0.contains("tiers.regular") && $0.contains("lo > hi") },
                          "got \(e.problems)")
        }
    }

    func testMissingTierFailsLoud() throws {
        var root = try JSONDecoder().decode([String: JSONValue].self, from: try shippedJSON("difficulty"))
        var tiers = root["tiers"]!.asObject!
        tiers["legendary"] = nil
        root["tiers"] = .object(tiers)
        XCTAssertThrowsError(try DifficultyData.decode(try encode(root))) { err in
            let e = err as! DataValidationError
            XCTAssertTrue(e.problems.contains { $0.contains("tiers.legendary: missing tier entry") }, "got \(e.problems)")
        }
    }

    func testBadZenSuitCountFailsLoud() throws {
        var root = try JSONDecoder().decode([String: JSONValue].self, from: try shippedJSON("difficulty"))
        var zen = root["zen"]!.asObject!
        var hard = zen["hard"]!.asObject!
        hard["suitCount"] = .number(9)
        zen["hard"] = .object(hard)
        root["zen"] = .object(zen)
        XCTAssertThrowsError(try DifficultyData.decode(try encode(root))) { err in
            let e = err as! DataValidationError
            XCTAssertTrue(e.problems.contains { $0.contains("zen.hard") && $0.contains("suitCount") }, "got \(e.problems)")
        }
    }

    /// Tutorial validation is deliberately SOFTER: a malformed group records a
    /// problem but never throws — the game must not brick on a copy typo.
    func testTutorialMalformedGroupRecordsButDoesNotThrow() throws {
        var root = try JSONDecoder().decode([String: JSONValue].self, from: try shippedJSON("tutorial"))
        var groups = root["groups"]!.asObject!
        groups["deal"] = .array([])                       // wrong step count
        root["groups"] = .object(groups)
        let t = try TutorialData.decode(try encode(root))   // must NOT throw
        XCTAssertTrue(t.problems.contains { $0.contains("groups.deal") }, "got \(t.problems)")
    }

    func testTutorialShippedCopyIsClean() {
        XCTAssertEqual(data.tutorial.problems, [], "the shipped tutorial.js must validate clean")
        for (key, count) in TutorialData.stepCounts {
            XCTAssertEqual(data.tutorial.steps(key).count, count, "groups.\(key) step count")
        }
    }

    // MARK: helpers

    private func shippedJSON(_ name: String) throws -> Data {
        let bundle = GameData.resourceBundle
        return try Data(contentsOf: bundle.url(forResource: name, withExtension: "json")!)
    }
    private func encode(_ root: [String: JSONValue]) throws -> Data { try JSONEncoder().encode(root) }
}
