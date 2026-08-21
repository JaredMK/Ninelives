import XCTest
@testable import GameCore

/// THE STARTING HAND'S STICKER CONTRACT (v6.73). A climb opens with a CLEAN
/// deck for every character except Mr. Garden, whose every-card override is
/// his whole identity. This is the regression net for a bug where a Pinky
/// climb opened with a stickered card: it sweeps every deck × both tiers ×
/// a spread of seeds, so a leak from ANY minting path fails loudly here.
final class StartingDeckTests: XCTestCase {
    private let seeds: [UInt32] = [1, 7, 42, 555, 4242, 99_999, 123_456, 20_260_820]

    private func climb(_ deck: String, _ tier: String, _ seed: UInt32) -> CampaignState {
        let c = CampaignState(store: MemoryStore())
        c.setDeck(deck); c.setTier(tier); c.setSeedOverride(seed); c.reset()
        return c
    }

    /// Pinky, Mamma, Slyrex, Rocko: ZERO stickers and ZERO curses at start.
    func testCleanDecksStartWithNoStickers() {
        for deck in ["pink", "mamma", "slyrex", "rocko"] {
            for tier in DifficultyData.tierIds {
                for seed in seeds {
                    let c = climb(deck, tier, seed)
                    let start = c.getRunDeck()
                    XCTAssertFalse(start.isEmpty, "\(deck)/\(tier)/\(seed): a deck was dealt")
                    for card in start {
                        XCTAssertTrue(card.stickers.isEmpty,
                                      "\(deck)/\(tier)/\(seed): card \(card.id) "
                                      + "(\(card.suit)\(card.currentRank)) opened with "
                                      + "\(card.stickers.map(\.type).joined(separator: ","))")
                    }
                }
            }
        }
    }

    /// MR. GARDEN's override: every starting card carries exactly his coat.
    func testGardenStartsEveryCardStickered() {
        for tier in DifficultyData.tierIds {
            for seed in seeds {
                let c = climb("garden", tier, seed)
                for card in c.getRunDeck() where !card.joker && !card.blank {
                    XCTAssertFalse(card.stickers.isEmpty,
                                   "garden/\(tier)/\(seed): card \(card.id) opened bare")
                }
            }
        }
    }

    /// ROCKO takes no stickers ANYWHERE — the starting hand, the whole draft
    /// pool, and every mint. (Just a Two's curses are his one exception and
    /// arrive later, mid-climb; nothing may ride the opening deck.)
    func testRockoIsStickerFreeAcrossThePool() {
        for tier in DifficultyData.tierIds {
            for seed in seeds {
                let c = climb("rocko", tier, seed)
                for card in c.baseDeck {
                    XCTAssertTrue(card.stickers.isEmpty,
                                  "rocko/\(tier)/\(seed): pool card \(card.id) carries stickers")
                }
                let rng = RNG(seed: 5)
                for _ in 0..<20 {
                    XCTAssertTrue(c.genNormalCard(rng).stickers.isEmpty,
                                  "rocko/\(tier)/\(seed): a mint carried a sticker")
                }
            }
        }
    }

    /// The whole DRAFT POOL — not just the 13 dealt cards — opens clean for
    /// the plain decks: a leak into an unclaimed card would surface the
    /// moment the player picks it up, which is the same bug one step later.
    func testPlainDeckPoolsAlsoOpenClean() {
        for deck in ["pink", "mamma", "slyrex"] {
            for seed in seeds {
                let c = climb(deck, "regular", seed)
                for card in c.baseDeck {
                    XCTAssertTrue(card.stickers.isEmpty,
                                  "\(deck)/\(seed): pool card \(card.id) carries "
                                  + "\(card.stickers.map(\.type).joined(separator: ",")) at climb start")
                }
            }
        }
    }
}
