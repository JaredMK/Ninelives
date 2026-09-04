import XCTest
import UIKit

/// COLORFUL CARDS (v6.96): pins the suit-colour chokepoint in BOTH modes.
///
/// CRT.swift / PixelGlyphs.swift / PixelTexture.swift compile INTO this
/// bundle (see the GameCoreTests sources in project.yml) — the app target is
/// not linkable from this logic-only test bundle, so the rule is tested
/// against the REAL sources compiled here, never a re-implementation.
final class ColorfulCardsTests: XCTestCase {

    override func tearDown() {
        CRT.colorfulCards = false   // never leak the flag into another suite
        super.tearDown()
    }

    // MARK: - The mapping, both modes

    /// OFF = today's exact tokens: ♥♦ suit-red, ♠♣ ink (cream on felt), ★ gold.
    func testClassicModeIsExactlyTheOldTokens() {
        CRT.colorfulCards = false
        XCTAssertEqual(CRT.suitColor("♥"), CRT.suitRed)
        XCTAssertEqual(CRT.suitColor("♦"), CRT.suitRed)
        XCTAssertEqual(CRT.suitColor("♠"), CRT.ink)
        XCTAssertEqual(CRT.suitColor("♣"), CRT.ink)
        XCTAssertEqual(CRT.suitColor("★"), CRT.gold)
        // The dark-surface split survives: ♠/♣ render cream on felt, not ink.
        XCTAssertEqual(CRT.suitColor("♠", onFelt: true), CRT.cardFace)
        XCTAssertEqual(CRT.suitColor("♣", onFelt: true), CRT.cardFace)
        XCTAssertEqual(CRT.suitColor("♥", onFelt: true), CRT.suitRed)
        XCTAssertEqual(CRT.suitColor("♦", onFelt: true), CRT.suitRed)
        // The legacy wrapper must agree with the chokepoint everywhere.
        for s in ["♥", "♦", "♠", "♣", "★"] {
            XCTAssertEqual(CRT.color(forSuit: s), CRT.suitColor(s),
                           "color(forSuit:) drifted from suitColor for \(s)")
        }
    }

    /// ON: ♦ blue, ♣ green; ♥/♠/★ untouched.
    func testColorfulModeRecoloursDiamondsAndClubsOnly() {
        CRT.colorfulCards = true
        XCTAssertEqual(CRT.suitColor("♦"), CRT.suitBlue)
        XCTAssertEqual(CRT.suitColor("♣"), CRT.suitGreen)
        XCTAssertEqual(CRT.suitColor("♥"), CRT.suitRed, "hearts stay red")
        XCTAssertEqual(CRT.suitColor("♠"), CRT.ink, "spades stay black")
        XCTAssertEqual(CRT.suitColor("♠", onFelt: true), CRT.cardFace)
        XCTAssertEqual(CRT.suitColor("★"), CRT.gold, "the Joker stays gold")
        // suitGreen must not collide with phosphor — the glow-only colour may
        // never double as a suit ink.
        XCTAssertNotEqual(CRT.suitGreen, CRT.phosphor)
        XCTAssertNotEqual(CRT.suitBlue, CRT.suitGreen)
        XCTAssertNotEqual(CRT.suitBlue, CRT.suitRed)
    }

    // MARK: - Bake level

    /// Toggling the flag must change a RENDERED ♦ while ♥ is bit-identical
    /// across modes — the "blue on the card, red in the histogram" guard.
    /// PixelGlyph.suitImage is the chokepoint every inline glyph and card pip
    /// shares; its cache keys on the tint, so a recoloured suit rebakes and
    /// an untouched one returns the same cached image.
    func testToggleRecoloursABakedDiamondButNotAHeart() {
        CRT.colorfulCards = false
        let diamondClassic = PixelGlyph.suitImage("♦", size: 24, color: CRT.cardFace)
        let heartClassic = PixelGlyph.suitImage("♥", size: 24, color: CRT.cardFace)
        CRT.colorfulCards = true
        let diamondColorful = PixelGlyph.suitImage("♦", size: 24, color: CRT.cardFace)
        let heartColorful = PixelGlyph.suitImage("♥", size: 24, color: CRT.cardFace)
        XCTAssertNotNil(diamondClassic)
        XCTAssertNotNil(diamondColorful)
        XCTAssertTrue(heartClassic === heartColorful,
                      "♥ is suit-red in both modes — one cache entry")
        XCTAssertFalse(diamondClassic === diamondColorful,
                       "♦ must rebake under Colorful Cards")
        XCTAssertEqual(heartClassic?.pngData(), heartColorful?.pngData(),
                       "♥ pixels are identical across modes")
        XCTAssertNotEqual(diamondClassic?.pngData(), diamondColorful?.pngData(),
                          "♦ pixels must change across modes")
    }

    /// ♠ (always) and classic ♣ take the SURROUNDING run's ink, never a
    /// self-tint — that's what lets them sit in cream HUD text and ink card
    /// faces alike.
    func testBlackSuitsTakeTheCallerInk() {
        CRT.colorfulCards = false
        let spadeClassic = PixelGlyph.suitImage("♠", size: 24, color: CRT.gold)
        CRT.colorfulCards = true
        let spadeColorful = PixelGlyph.suitImage("♠", size: 24, color: CRT.gold)
        XCTAssertTrue(spadeClassic === spadeColorful,
                      "♠ takes the run's ink in both modes")

        CRT.colorfulCards = false
        let clubClassic = PixelGlyph.suitImage("♣", size: 24, color: CRT.gold)
        CRT.colorfulCards = true
        let clubColorful = PixelGlyph.suitImage("♣", size: 24, color: CRT.gold)
        // v7.04: ♣ takes the CALLER's colour in BOTH modes, exactly like ♠ —
        // the felt/card distinction lives in what colour each surface passes
        // (suitColor(onFelt:)), never in suitImage forcing one.
        XCTAssertTrue(clubClassic === clubColorful,
                      "♣ takes the run's ink in both modes (the caller resolves felt vs card)")
    }

    /// REGRESSION (v7.04): every suit's pip must render, and must render
    /// VISIBLY on the cream card face, in BOTH colour modes. The v7.01 fix
    /// forced ♣→cream inside suitImage, so a colorful club drew cream-on-cream
    /// and vanished from every card. The guard: the pip drawn in the card's
    /// resolved ink must NOT be bit-identical to the same glyph drawn in the
    /// FACE colour (which would be invisible).
    func testAllFourSuitsRenderVisiblyOnCardFacesInBothModes() {
        for colorful in [false, true] {
            CRT.colorfulCards = colorful
            let mode = colorful ? "colorful" : "classic"
            for suit in ["♠", "♥", "♦", "♣"] {
                let ink = CRT.color(forSuit: suit)          // the card face's pip colour
                let pip = PixelGlyph.suitImage(suit, size: 24, color: ink)
                XCTAssertNotNil(pip, "\(suit) glyph resolves to an image (\(mode))")
                XCTAssertNotEqual(ink, CRT.cardFace,
                                  "\(suit) pip colour must differ from the card face (\(mode))")
                // ♠/♣ take the CALLER colour — so a wrong override could paint
                // them the face colour and vanish (the v7.01 club bug). ♥/♦
                // self-tint red/blue and can never be the face colour, so the
                // probe only applies to the caller-tinted suits.
                if suit == "♠" || suit == "♣" {
                    let invisible = PixelGlyph.suitImage(suit, size: 24, color: CRT.cardFace)
                    XCTAssertNotEqual(pip?.pngData(), invisible?.pngData(),
                                      "\(suit) must not render in the card-face colour (\(mode))")
                }
            }
        }
        CRT.colorfulCards = false
    }
}
