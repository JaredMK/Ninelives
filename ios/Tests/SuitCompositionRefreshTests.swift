import XCTest
@testable import GameCore

/// TASK 16 (v6.57) — the histogram's suit counts must refresh the MOMENT an
/// inventory suit sticker applies; on iOS they used to wait for the next
/// engine action. The UI fix (DealController.noteDeckCompositionChanged)
/// writes the new suit through to the live cards and re-derives the band's
/// cached totals. These tests pin the MODEL path that fix stands on:
///
///  1. applying a changeSuitTo sticker mutates the campaign deck's suit
///     composition IMMEDIATELY (the data the band's totals are read from);
///  2. a LiveCard suit write-through shows in the draw pile's
///     remainingSuitCounts() with no other trigger (the UI's recompute
///     mechanism);
///  3. changeSuitRandom always lands on a DIFFERENT suit, so the composition
///     genuinely moves.
final class SuitCompositionRefreshTests: XCTestCase {

    private func suits(_ specs: [CardSpec]) -> [String: Int] {
        var t: [String: Int] = [:]
        for c in specs where !c.joker && !c.blank { t[c.suit, default: 0] += 1 }
        return t
    }

    private func freshCampaign() -> CampaignState {
        let c = CampaignState()
        c.setDeck("pink"); c.setSeedOverride(4242); c.reset()
        return c
    }

    /// The campaign apply path (the picker's chokepoint minus the inventory
    /// spend) moves exactly one card between the suit tallies, immediately.
    func testChangeSuitToUpdatesDeckCompositionImmediately() {
        let c = freshCampaign()
        guard let def = GameData.shared.stickerTypes.all().first(where: {
            $0.behavior == "changeSuitTo" && $0.suit != nil
        }) else { return XCTFail("no changeSuitTo sticker in the registry") }
        guard let card = c.getRunDeck().first(where: {
            !$0.joker && !$0.blank && $0.suit != def.suit! && c.canApplySticker($0, def.id)
        }) else { return XCTFail("no legal target for \(def.id)") }

        let before = suits(c.getRunDeck())
        XCTAssertTrue(c.applyStickerDirect(card.id, def.id), "the apply must succeed")
        let after = suits(c.getRunDeck())

        XCTAssertEqual(after[def.suit!], (before[def.suit!] ?? 0) + 1,
                       "the target suit gains the card the MOMENT the sticker lands")
        XCTAssertEqual(after[card.suit], (before[card.suit] ?? 0) - 1,
                       "…and the old suit loses it — no second trigger needed")
    }

    /// The UI's recompute mechanism: mutating a LiveCard's suit (the
    /// write-through) is reflected in remainingSuitCounts() at once.
    func testLiveCardSuitWriteThroughMovesRemainingCounts() {
        let specs = DeckManager.buildStandardDeck()
        let deck = DeckManager.create(specs, rng: RNG(seed: 7))
        let before = deck.remainingSuitCounts()
        guard let card = deck.peekAll().first(where: { $0.suit == "♠" }),
              let heart = DeckManager.suits.first(where: { $0.symbol == "♥" })
        else { return XCTFail("standard deck must hold a ♠") }

        card.suit = heart.symbol
        card.red = heart.red
        let after = deck.remainingSuitCounts()

        XCTAssertEqual(after["♥"], (before["♥"] ?? 0) + 1)
        XCTAssertEqual(after["♠"], (before["♠"] ?? 0) - 1)
        XCTAssertEqual(after.values.reduce(0, +), before.values.reduce(0, +),
                       "a suit change moves a count, never creates one")
    }

    /// changeSuitRandom must pick a DIFFERENT suit — a same-suit "change"
    /// would leave the band's counts unmoved and look like the stale bug.
    func testChangeSuitRandomAlwaysMovesTheSuit() {
        guard let def = GameData.shared.stickerTypes.all().first(where: {
            $0.behavior == "changeSuitRandom"
        }) else { return XCTFail("no changeSuitRandom sticker in the registry") }
        for seed: UInt32 in 1...40 {
            let c = freshCampaign()
            c.setSeedOverride(seed)
            guard let card = c.getRunDeck().first(where: {
                !$0.joker && !$0.blank && c.canApplySticker($0, def.id)
            }) else { continue }
            let oldSuit = card.suit
            XCTAssertTrue(c.applyStickerDirect(card.id, def.id))
            let moved = c.getRunDeck().first { $0.id == card.id }
            XCTAssertNotEqual(moved?.suit, oldSuit,
                              "changeSuitRandom re-landed on \(oldSuit) (seed \(seed))")
        }
    }
}
