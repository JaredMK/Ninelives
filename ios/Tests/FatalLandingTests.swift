import XCTest
@testable import GameCore

/// FATAL-LANDING AUDIT (v6.52) — landing-triggered stickers fire ONLY when
/// the card lands CORRECTLY. Field report: a Spoiler landing wrong (killing
/// its pile) still wiped the deal's bonus coins. Root cause: `curseTouch`
/// (Peeler / Shield Drain / Base Drain / Spoiler / Saboteur) ran from the
/// fatal branch and the Same-Charge-save branch too. Every other landing
/// sticker already gated on the correct branch; this file pins ALL of them
/// against the fatal case, plus the two DELIBERATE exceptions:
///   - Death Bounty pays ON the kill (its trigger IS the fatal landing)
///   - Malfunction's kill keeps touch curses (that guess WAS correct)
final class FatalLandingTests: XCTestCase {

    /// Wrong-guess kill: top 9, drawn 2 (carrying `stickers`), HIGHER.
    private func fatalEngine(drawnStickers: [String] = [], topStickers: [String] = [],
                             sameCharge: Bool = false,
                             pillars: [String?]? = nil, bases: [String?]? = nil) -> GameEngine {
        IV.engine(tops: [IV.spec(1, 9, "♠", topStickers), IV.spec(2, 6), IV.spec(3, 6)],
                  deckOrder: [IV.spec(50, 2, "♥", drawnStickers), IV.spec(51, 3)],
                  pillars: pillars, bases: bases, sameCharge: sameCharge)
    }

    // MARK: - The five that were wrong (curseTouch on the fatal branch)

    func testSpoilerDoesNotFireOnAFatalLanding() {
        let e = fatalEngine(drawnStickers: ["spoiler"])
        e.run.bonusCoins = 7
        e.guess(0, .higher)                       // 2 on 9 → wrong → pile dies
        XCTAssertFalse(e.board.isActive(0), "the pile died")
        XCTAssertEqual(e.run.bonusCoins, 7, "Spoiler must NOT wipe the bonus on a fatal landing")
    }

    func testShieldDrainDoesNotFireOnASameChargeSavedLanding() {
        let e = fatalEngine(drawnStickers: ["drainShield"], sameCharge: true)
        e.guess(0, .higher)                       // wrong → Same Charge saves
        XCTAssertTrue(e.board.isActive(0), "the charge saved the pile")
        XCTAssertFalse(e.sameCharge, "the save spent the charge (by the save, not the curse)")
    }

    func testSpoilerDoesNotFireOnASameChargeSavedLanding() {
        let e = fatalEngine(drawnStickers: ["spoiler"], sameCharge: true)
        e.run.bonusCoins = 5
        e.guess(0, .higher)
        XCTAssertTrue(e.board.isActive(0), "saved")
        XCTAssertEqual(e.run.bonusCoins, 5, "a saved WRONG landing is still not a correct landing")
    }

    func testBaseDrainDoesNotFireOnAFatalLanding() {
        let e = fatalEngine(drawnStickers: ["drainBase"], bases: ["shuffleColumn", nil, nil])
        e.guess(0, .higher)
        XCTAssertFalse(e.board.isActive(0))
        XCTAssertEqual(e.run.basesUsed?[0], false, "the Base survives a fatal landing")
    }

    func testPeelerDoesNotStripOnAFatalLanding() {
        let e = fatalEngine(drawnStickers: ["peeler"], topStickers: ["gainCoin", "tell"])
        e.guess(0, .higher)
        XCTAssertFalse(e.board.isActive(0))
        // The killing card sits on top; the card it landed on (id 1) is
        // beneath it — and must still carry both stickers.
        let touched = e.board.piles[0].cards.first { $0.id == 1 }
        XCTAssertEqual(touched?.stickers.count, 2,
                       "the touched card keeps its stickers — Peeler needs a correct landing")
    }

    func testSaboteurDoesNotRollOnAFatalLanding() {
        let e = fatalEngine(drawnStickers: ["saboteur"],
                            pillars: ["columnGuardian", nil, nil], bases: ["shuffleColumn", nil, nil])
        e.guess(0, .higher)
        XCTAssertFalse(e.board.isActive(0))
        XCTAssertEqual(e.run.pillars?[0], "columnGuardian", "the Pillar survives — no roll happened")
        XCTAssertEqual(e.run.bases?[0], "shuffleColumn", "the Base survives — no roll happened")
    }

    // MARK: - Correct-only stickers stay correct-only (representatives)

    func testCoinAndBuryStickersPayNothingOnAFatalLanding() {
        let e = fatalEngine(drawnStickers: ["gainCoin", "deepPockets", "looseChange", "quickBury"])
        let deckBefore = e.deck.remaining()
        e.guess(0, .higher)
        XCTAssertFalse(e.board.isActive(0))
        XCTAssertEqual(e.run.bonusCoins, 0, "no coin sticker pays on a fatal landing")
        XCTAssertEqual(e.deck.remaining(), deckBefore - 1, "only the draw left the deck — no burial")
    }

    func testLeechTakesNoTollOnAFatalLanding() {
        let e = fatalEngine(drawnStickers: ["leech"])
        e.guess(0, .higher)
        XCTAssertEqual(e.run.bonusCoins, 0, "the Leech toll needs a correct landing")
    }

    func testPeekAndHintStickersStayDarkOnAFatalLanding() {
        let e = fatalEngine(drawnStickers: ["revealNext", "tell"])
        e.guess(0, .higher)
        XCTAssertFalse(e.run.revealNextActive, "Scout does not reveal on a fatal landing")
        XCTAssertTrue(e.run.tellPiles.isEmpty, "Tell does not arm on a fatal landing")
    }

    func testSnobOnThePileTopPaysNothingWhenTheLandingKills() {
        // ♥ Snob on the top; a ♥ lands WRONG and kills the pile.
        let e = fatalEngine(drawnStickers: [], topStickers: ["heartSnob"])
        e.guess(0, .higher)                       // drawn is ♥ 2 → wrong
        XCTAssertFalse(e.board.isActive(0))
        XCTAssertEqual(e.run.bonusCoins, 0, "a snob needs a CORRECT matching-suit landing")
    }

    func testQuickBuryOnThePileTopFiresNothingWhenTheLandingKills() {
        // PILE-TOP (v6.75): the carrier tops the pile, but the landing KILLS
        // it — no pile-top effect fires on a fatal landing (the audit stands).
        let e = fatalEngine(drawnStickers: [], topStickers: ["quickBury"])
        let deckBefore = e.deck.remaining()
        e.guess(0, .higher)
        XCTAssertFalse(e.board.isActive(0))
        XCTAssertEqual(e.deck.remaining(), deckBefore - 1, "only the draw left the deck — no burial")
    }

    func testTrapdoorDoesNotOpenOnAFatalLanding() {
        // Grow the pile with a correct landing first, so there is a bottom
        // card the trapdoor could steal; then land the trapdoor FATALLY.
        let e = IV.engine(tops: [IV.spec(1, 9, "♠"), IV.spec(2, 6), IV.spec(3, 6)],
                          deckOrder: [IV.spec(49, 10, "♥"),
                                      IV.spec(50, 2, "♥", ["trapdoor"]), IV.spec(51, 3)])
        e.guess(0, .higher)                       // 10 on 9 → correct, pile grows
        let count = e.board.piles[0].cards.count
        let deckBefore = e.deck.remaining()
        e.guess(0, .higher)                       // 2 on 10 → wrong → fatal
        XCTAssertFalse(e.board.isActive(0))
        XCTAssertEqual(e.board.piles[0].cards.count, count + 1,
                       "the trapdoor stays shut on a fatal landing (+1 = the killing card)")
        XCTAssertEqual(e.deck.remaining(), deckBefore - 1, "no bottom card slipped back in")
    }

    // MARK: - The deliberate exceptions

    func testDeathBountyStillPaysOnTheKill() {
        let e = fatalEngine(drawnStickers: ["deathBounty"])
        e.guess(0, .higher)
        XCTAssertFalse(e.board.isActive(0))
        let v = GameData.shared.stickerTypes.get("deathBounty")!.value
        XCTAssertEqual(e.run.bonusCoins, v, "Death Bounty's trigger IS the kill — it keeps paying")
    }

    func testMalfunctionKillKeepsTouchCurses() {
        // A correct guess against a malfunction top that blows the pile: the
        // guess WAS correct, so the drawn card's touch curses still fire.
        // The 10% roll is seed-deterministic — walk seeds until it blows.
        var fired = false
        for seed: UInt32 in 1...200 {
            // v6.99: malfunction rides the CARRIER now — same card as the
            // Spoiler, so the kill and the touch curse share one landing.
            let e = IV.engine(tops: [IV.spec(1, 5, "♠"), IV.spec(2, 6), IV.spec(3, 6)],
                              deckOrder: [IV.spec(50, 9, "♥", ["spoiler", "malfunction"]), IV.spec(51, 3)],
                              seed: seed)
            e.run.bonusCoins = 4
            e.guess(0, .higher)                   // 9 on 5 → correct; may malfunction
            if !e.board.isActive(0) {             // it blew
                fired = true
                XCTAssertEqual(e.run.bonusCoins, 0,
                               "seed \(seed): the correct-guess malfunction kill keeps the Spoiler wipe")
                break
            }
        }
        XCTAssertTrue(fired, "no seed in 1...200 rolled the 10% malfunction — statistically broken")
    }
}
