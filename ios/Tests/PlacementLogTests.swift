import XCTest
@testable import GameCore

/// THE PLACEMENT-DECISION LOG (v6.84). Pins the whole contract:
/// - a placement records the sticker, source, chosen card, the exact
///   eligible field, the equipped loadout, and the meaningfulness verdict
///   with its inputs;
/// - the debug flag gates EVERYTHING — off (the shipping default), a
///   placement writes nothing anywhere;
/// - recording never touches gameplay: the same ops with the log on and off
///   produce byte-identical campaign state.
final class PlacementLogTests: XCTestCase {

    private func campaign(seed: UInt32 = 4242) -> CampaignState {
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular"); c.setSeedOverride(seed); c.reset()
        return c
    }

    private var hadAccess = false

    override func setUp() {
        super.setUp()
        hadAccess = UserDefaults.standard.bool(forKey: "debugAccess")
        PlacementLog.clearFile()
        PlacementLog.resetOrigins()
        DebugEventLog.shared.clear()
    }

    override func tearDown() {
        UserDefaults.standard.set(hadAccess, forKey: "debugAccess")
        PlacementLog.clearFile()
        PlacementLog.resetOrigins()
        DebugEventLog.shared.clear()
        super.tearDown()
    }

    private func lastRecord() throws -> [String: JSONValue] {
        let lines = PlacementLog.fileText().split(separator: "\n", omittingEmptySubsequences: true)
        let last = try XCTUnwrap(lines.last, "no placement record written")
        return try XCTUnwrap(
            try? JSONDecoder().decode([String: JSONValue].self, from: Data(last.utf8)))
    }

    // MARK: - The record's content

    func testPlacementRecordCapturesTheDecision() throws {
        UserDefaults.standard.set(true, forKey: "debugAccess")
        let c = campaign()
        c.debugGrantSticker("rankUp")
        // The field the player chooses from, computed the same way the picker
        // greys cards: every deck card the sticker may legally land on.
        let expectedEligible = c.getRunDeck().filter { c.canApplySticker($0, "rankUp") }
        let chosen = try XCTUnwrap(expectedEligible.first(where: { $0.currentRank < 14 }))
        XCTAssertTrue(c.applySticker(chosen.id, "rankUp"))

        let rec = try lastRecord()
        XCTAssertEqual(rec["sticker"]?.asString, "rankUp")
        XCTAssertEqual(rec["name"]?.asString, GameData.shared.stickerTypes.get("rankUp")?.label)
        XCTAssertEqual(rec["source"]?.asString, "debug", "the origin note from debugGrantSticker")
        XCTAssertEqual(rec["chosen"]?["id"]?.asInt, chosen.id)
        XCTAssertEqual(rec["chosen"]?["rank"]?.asInt, chosen.currentRank)
        XCTAssertEqual(rec["chosen"]?["suit"]?.asString, chosen.suit)
        // The eligible field matches what the picker offered, card for card,
        // recorded BEFORE the apply (the chosen card shows its old stickers).
        XCTAssertEqual(rec["eligible"]?.asArray?.compactMap { $0["id"]?.asInt },
                       expectedEligible.map(\.id))
        XCTAssertEqual(rec["eligibleCount"]?.asInt, expectedEligible.count)
        XCTAssertEqual(rec["chosen"]?["stickers"]?.asArray?.count, 0,
                       "recorded pre-apply: the new sticker is not on the card yet")
        // Loadout snapshot (fresh Pinky: nothing equipped).
        XCTAssertEqual(rec["pillars"]?.asArray?.compactMap(\.asString),
                       c.columnPillars.map { $0 ?? "-" })
        XCTAssertEqual(rec["power"]?.asString, "-")
        // A rank sticker over a full mixed deck: the rank axis differs.
        XCTAssertEqual(rec["meaningful"]?.asBool, true)
        let axes = rec["axes"]?.asArray ?? []
        XCTAssertTrue(axes.contains { $0["axis"]?.asString == "rank"
            && $0["from"]?.asString == "sticker:rankUp" },
                      "the rank axis names its contributor")
        XCTAssertGreaterThan(rec["distinctRanks"]?.asInt ?? 0, 1)
        // …and the on-screen event log carries the compact line.
        XCTAssertTrue(DebugEventLog.shared.text().contains("PLACE|sticker=rankUp"),
                      "the PLACE line reaches the debug panel's event log")
    }

    /// A sticker with no intrinsic axis and no rank/suit-keyed equipment:
    /// every eligible card is the same home — meaningful=no, and the record
    /// says WHY with auditable inputs.
    func testInterchangeablePlacementIsFlaggedWithItsInputs() throws {
        UserDefaults.standard.set(true, forKey: "debugAccess")
        let c = campaign()
        c.debugGrantSticker("twinSpark")   // ♠-restricted twin peek: the axis table gives it none
        let eligible = c.getRunDeck().filter { c.canApplySticker($0, "twinSpark") }
        let chosen = try XCTUnwrap(eligible.first)
        XCTAssertTrue(c.applySticker(chosen.id, "twinSpark"))
        let rec = try lastRecord()
        XCTAssertEqual(rec["meaningful"]?.asBool, false)
        XCTAssertEqual(rec["axes"]?.asArray?.count, 0)
        XCTAssertTrue(rec["why"]?.asString?.contains("no axis cared") == true)
        // The inputs to re-derive the verdict are all present.
        XCTAssertNotNil(rec["distinctRanks"]?.asInt)
        XCTAssertNotNil(rec["distinctSuits"]?.asInt)
        XCTAssertNotNil(rec["distinctLoads"]?.asInt)
    }

    /// An equipped rank-keyed item adds ITS axis to a placement — and the
    /// axis names the enabler. (gainCoin also brings its own v6.85 suit
    /// axis; the rank axis here must come from the pillar.)
    func testEquippedItemTurnsAPlacementMeaningful() throws {
        UserDefaults.standard.set(true, forKey: "debugAccess")
        let c = campaign()
        c.setColumnPillar(col: 0, typeId: "eightPeek")   // rank-keyed pillar
        c.debugGrantSticker("gainCoin")
        let eligible = c.getRunDeck().filter { c.canApplySticker($0, "gainCoin") }
        let chosen = try XCTUnwrap(eligible.first)
        XCTAssertTrue(c.applySticker(chosen.id, "gainCoin"))
        let rec = try lastRecord()
        XCTAssertEqual(rec["meaningful"]?.asBool,
                       Set(eligible.map(\.currentRank)).count > 1)
        XCTAssertTrue(rec["axes"]?.asArray?.contains {
            $0["axis"]?.asString == "rank" && $0["from"]?.asString == "equipped:eightPeek"
        } == true, "the enabling pillar is named as the axis source")
        XCTAssertEqual(rec["pillars"]?.asArray?.first?.asString, "eightPeek")
    }

    /// Origin notes: a pack keep and a store buy each stamp their source.
    func testOriginNotesNameTheAcquisitionPath() throws {
        UserDefaults.standard.set(true, forKey: "debugAccess")
        let c = campaign()
        _ = c.addStickerToInventory("tell")               // the pack-keep path
        let eligible = c.getRunDeck().filter { c.canApplySticker($0, "tell") }
        XCTAssertTrue(c.applySticker(try XCTUnwrap(eligible.first).id, "tell"))
        XCTAssertEqual(try lastRecord()["source"]?.asString, "pack")
        // An explicit source (the shelf's place-then-pay flow) wins outright.
        c.debugGrantSticker("shuffle")
        let el2 = c.getRunDeck().filter { c.canApplySticker($0, "shuffle") }
        XCTAssertTrue(c.applySticker(try XCTUnwrap(el2.first).id, "shuffle", source: "store"))
        XCTAssertEqual(try lastRecord()["source"]?.asString, "store")
    }

    // MARK: - The gate + neutrality

    func testNothingFiresOutsideDebug() throws {
        UserDefaults.standard.set(false, forKey: "debugAccess")
        let c = campaign()
        c.debugGrantSticker("rankUp")
        let eligible = c.getRunDeck().filter { c.canApplySticker($0, "rankUp") }
        XCTAssertTrue(c.applySticker(try XCTUnwrap(eligible.first).id, "rankUp"))
        XCTAssertEqual(PlacementLog.fileText(), "", "no file record outside debug")
        XCTAssertFalse(FileManager.default.fileExists(atPath: PlacementLog.fileURL.path),
                       "the file is never even created")
        XCTAssertFalse(DebugEventLog.shared.text().contains("PLACE|"),
                       "no PLACE line outside debug")
    }

    /// The log is a pure read: identical ops with the flag on and off leave
    /// byte-identical campaign state (same rng consumption, same deck).
    func testLoggingIsGameplayNeutral() throws {
        func play(_ debug: Bool) -> [String: JSONValue] {
            UserDefaults.standard.set(debug, forKey: "debugAccess")
            let c = campaign(seed: 777)
            c.debugGrantSticker("rankUp")
            c.debugGrantSticker("shuffle")
            let e1 = c.getRunDeck().filter { c.canApplySticker($0, "rankUp") }
            _ = c.applySticker(e1[2].id, "rankUp")
            let e2 = c.getRunDeck().filter { c.canApplySticker($0, "shuffle") }
            _ = c.applySticker(e2[0].id, "shuffle")
            return c.serialize()
        }
        let with = play(true)
        PlacementLog.clearFile()
        let without = play(false)
        XCTAssertEqual(JSONValue.object(with), JSONValue.object(without),
                       "the log must not shift rng, deck state, or any save field")
    }
}
