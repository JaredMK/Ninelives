import XCTest
@testable import GameCore

/// v6.88 batch pins beyond the per-item validation:
/// - CLEANSE ALL (the new Same-Power): board-wide, Same-gated, durable via
///   .cursePeeled, repeatable — and clearly distinct from the Cleanse Base
///   (column-scoped, tap-fired, once per deal).
/// - FINAL CUT's durable half: the campaign write the .finalCutPurged event
///   commits (removeDeckCard) really removes the card for good.
final class WardCutCleanseTests: XCTestCase {
    private let data = GameData.shared

    func testCleanseAllStripsEveryTopOnACorrectSame() {
        // Three alive piles, every top cursed (one also carries a PLAIN
        // sticker that must survive). Drawn 5♥ on the 5♠ top: a correct Same.
        // NOTE: the Same is called on pile 1, whose curse must not be MUTE
        // (Mute forbids the Same call itself) — Shrink gates nothing.
        let e = IV.engine(tops: [IV.spec(1, 5, "♠", ["shrink"]),
                                 IV.spec(2, 7, "♦", ["leech", "tell"]),
                                 IV.spec(3, 9, "♣", ["mute"])],
                          deckOrder: [IV.spec(50, 5, "♥"), IV.spec(51, 8, "♥")],
                          samePower: "sameCleanseAll")
        var peels: [(index: Int, types: [String])] = []
        var powerFired = false
        e.on { ev in
            if case .cursePeeled(let i, _, let types) = ev { peels.append((i, types)) }
            if case .samePower(let r) = ev, r.effect == "sameCleanseAll" { powerFired = true }
        }
        e.guess(0, .same)
        XCTAssertTrue(powerFired, "the power fired on the correct Same")
        // TOP cards only, board-wide: piles 2 and 3 (other columns' worth of
        // board) are cleansed; the hub's NEW top is the landed 5♥ (clean),
        // and the old cursed 5♠ is BURIED — buried cards keep their curses,
        // the Cleanse Base's exact depth rule.
        for i in 0..<3 {
            XCTAssertFalse(e.board.top(i)!.stickers
                .contains { self.data.stickerTypes.get($0.type)?.cursed == true },
                "pile \(i + 1)'s TOP is curse-free — board-wide, not column")
        }
        XCTAssertTrue(e.board.piles[0].cards.first!.stickers.contains { $0.type == "shrink" },
                      "the hub's BURIED old top keeps its curse — tops only")
        XCTAssertTrue(e.board.top(1)!.stickers.contains { $0.type == "tell" },
                      "non-cursed stickers survive the cleanse")
        XCTAssertEqual(peels.count, 2, "one .cursePeeled per top that HELD a curse")
        XCTAssertEqual(Set(peels.map(\.index)), [1, 2])
    }

    func testCleanseAllIsRepeatableEveryCorrectSame() {
        // No once-per-deal gate: a SECOND correct Same cleanses again.
        let e = IV.engine(tops: [IV.spec(1, 5, "♠", ["shrink"]), IV.spec(2, 7, "♦"), IV.spec(3, 9, "♣")],
                          deckOrder: [IV.spec(50, 5, "♥"), IV.spec(51, 5, "♦"), IV.spec(52, 8, "♥")],
                          samePower: "sameCleanseAll")
        var fires = 0
        e.on { if case .samePower(let r) = $0, r.effect == "sameCleanseAll" { fires += 1 }
        }
        e.guess(0, .same)                                   // 5♥ on 5♠ w/mute — cleansed
        e.board.top(1)!.stickers.append(StickerRecord(type: "leech"))
        e.guess(1, .same)                                   // 5♦ on 7♦? — no: 5 ≠ 7
        XCTAssertEqual(fires, 1, "a wrong Same fires nothing")
        e.board.piles[1].cards = [DeckManager.toCard(IV.spec(60, 8, "♦", ["leech"]), data: data)]
        e.board.piles[1].dead = false   // the wrong Same above killed it
        e.guess(1, .same)                                   // 8♥ on 8♦ — fires again
        XCTAssertEqual(fires, 2, "repeatable — every correct Same cleanses again")
        XCTAssertFalse(e.board.top(1)!.stickers.contains { $0.type == "leech" })
    }

    func testFinalCutsDurableWriteRemovesTheCardForGood() {
        // The campaign half of .finalCutPurged: removeDeckCard drops the
        // card from the owned deck permanently (and feeds removalsUsed).
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular"); c.setSeedOverride(7); c.reset()
        guard let victim = c.getRunDeck().first else { return XCTFail("a fresh deck has cards") }
        let sizeBefore = c.deckSize()
        XCTAssertTrue(c.removeDeckCard(victim.id))
        XCTAssertEqual(c.deckSize(), sizeBefore - 1, "one card gone")
        XCTAssertFalse(c.getRunDeck().contains { $0.id == victim.id }, "…and it is THAT card")
        // (removeDeckCard also bumps removalsUsed on unseeded campaigns —
        // a seeded test campaign is an exhibition, so no stats here.)
        // Durable across save/restore.
        let c2 = CampaignState(store: MemoryStore())
        XCTAssertTrue(c2.restore(c.serialize()))
        XCTAssertFalse(c2.getRunDeck().contains { $0.id == victim.id })
    }
}
