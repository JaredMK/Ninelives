import XCTest
import CoreGraphics
@testable import GameCore

/// STICKER DISPLAY (v6.72) — pins the canonical sticker-chip layout and the
/// picker's ineligibility-reason classifier.
///
/// The canonical geometry lives in `StickerChipLayout` (PileNode.swift, app
/// target) and the classifier in `CardPickerViewController` — this bundle
/// links only GameCore, so both are MIRRORED here verbatim and the source
/// files are grep-pinned below: if the app-side constants or messages drift
/// from these mirrors, the source assertions fail and name the file.
final class StickerDisplayTests: XCTestCase {
    private let data = GameData.shared

    // MARK: - Mirror of StickerChipLayout (PileNode.swift)

    private enum Mirror {
        static let rightOverhang: CGFloat = 3
        static let topRaise: CGFloat = 2
        static let overlapFactor: CGFloat = 0.62
        static let widthFactor: CGFloat = 0.44
        static let minChip: CGFloat = 14
        static let maxChip: CGFloat = 38

        static func chipSize(forCardWidth w: CGFloat) -> CGFloat {
            min(maxChip, max(minChip, (w * widthFactor).rounded()))
        }
        static func leanDegrees(_ idx: Int) -> CGFloat {
            CGFloat(max(-15, min(15, -11 + idx * 8)))
        }
        static func step(chip: CGFloat, count: Int, cardWidth: CGFloat) -> CGFloat {
            guard count > 1 else { return chip * overlapFactor }
            let fit = (cardWidth + rightOverhang * 2 - chip) / CGFloat(count - 1)
            return min(chip * overlapFactor, max(1, fit))
        }
        static func frames(count: Int, cardWidth: CGFloat, chip: CGFloat? = nil)
            -> [(frame: CGRect, leanDegrees: CGFloat)] {
            guard count > 0 else { return [] }
            let c = chip ?? chipSize(forCardWidth: cardWidth)
            let s = step(chip: c, count: count, cardWidth: cardWidth)
            return (0..<count).map { idx in
                (CGRect(x: cardWidth + rightOverhang - c - CGFloat(idx) * s,
                        y: -topRaise, width: c, height: c),
                 leanDegrees(idx))
            }
        }
    }

    /// The three board card sizes (CardArt.Scale: full / three / half).
    private let cardSizes: [(name: String, size: CGSize)] = [
        ("full", CGSize(width: 96, height: 134)),
        ("three", CGSize(width: 72, height: 100)),
        ("half", CGSize(width: 48, height: 67)),
    ]

    // MARK: - Data ceiling

    func testMaxStickersPerCardIsFour() {
        XCTAssertEqual(data.items.maxStickersPerCard, 4,
                       "items.js maxStickersPerCard — the display paths size their fans to it")
    }

    // MARK: - Layout: four chips, all on the card, at every scale

    func testFourChipsAllIntersectTheCardAtEveryScale() {
        let max = data.items.maxStickersPerCard
        for (name, size) in cardSizes {
            let card = CGRect(origin: .zero, size: size)
            let placed = Mirror.frames(count: max, cardWidth: size.width)
            XCTAssertEqual(placed.count, max, "\(name): \(max) stickers must yield \(max) chip frames")
            for (i, p) in placed.enumerated() {
                let visible = p.frame.intersection(card)
                XCTAssertFalse(visible.isNull, "\(name): chip \(i) is entirely off the card")
                // A sliver of at least 8pt of the chip's width must remain on
                // the card — "on the card" must mean SEEABLE, not a 1pt graze
                // (the pre-v6.72 bug left the 4th chip at zero visible width
                // on a half card).
                XCTAssertGreaterThanOrEqual(visible.width, 8,
                    "\(name): chip \(i) shows only \(visible.width)pt of width")
            }
            // The fan is strictly leftward — no two chips stack exactly.
            for i in 1..<placed.count {
                XCTAssertLessThan(placed[i].frame.minX, placed[i - 1].frame.minX,
                                  "\(name): chip \(i) does not step left")
            }
        }
    }

    func testChipSizesAreRecognizableAndCardProportional() {
        // Full cards carry the big 38pt chip; half cards stay at/above the
        // 14pt recognizability floor and never above the card-proportional cap.
        XCTAssertEqual(Mirror.chipSize(forCardWidth: 96), 38)
        XCTAssertEqual(Mirror.chipSize(forCardWidth: 72), 32)
        XCTAssertEqual(Mirror.chipSize(forCardWidth: 48), 21)
        for (_, size) in cardSizes {
            let chip = Mirror.chipSize(forCardWidth: size.width)
            XCTAssertGreaterThanOrEqual(chip, Mirror.minChip)
            XCTAssertLessThanOrEqual(chip, Mirror.maxChip)
            XCTAssertLessThanOrEqual(chip, size.width * 0.5,
                "chips must not dwarf the card (or bury the centred numeral)")
        }
    }

    func testLeanMatchesTheEstablishedFan() {
        XCTAssertEqual(Mirror.leanDegrees(0), -11)
        XCTAssertEqual(Mirror.leanDegrees(1), -3)
        XCTAssertEqual(Mirror.leanDegrees(2), 5)
        XCTAssertEqual(Mirror.leanDegrees(3), 13)
        XCTAssertEqual(Mirror.leanDegrees(9), 15, "clamped at ±15")
    }

    func testSingleChipSitsAtTheTopRightCorner() {
        for (name, size) in cardSizes {
            let placed = Mirror.frames(count: 1, cardWidth: size.width)
            XCTAssertEqual(placed.count, 1)
            XCTAssertEqual(placed[0].frame.maxX, size.width + Mirror.rightOverhang,
                           accuracy: 0.01, "\(name): first chip overhangs the right edge by 3")
            XCTAssertEqual(placed[0].frame.minY, -Mirror.topRaise,
                           accuracy: 0.01, "\(name): chips ride 2pt above the top edge")
        }
    }

    // MARK: - Source pins (app-target files, grep-level)

    /// ios/ root, resolved from this file's compile-time path.
    private var iosRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: iosRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    func testCanonicalConstantsMatchTheAppSource() throws {
        let master = try source("Rendering/PileNode.swift")
        // The mirror above must match the master's constants.
        for needle in [
            "rightOverhang: CGFloat = 3",
            "topRaise: CGFloat = 2",
            "overlapFactor: CGFloat = 0.62",
            "widthFactor: CGFloat = 0.44",
            "minChip: CGFloat = 14",
            "maxChip: CGFloat = 38",
            "-11 + idx * 8",
            "CANONICAL STICKER CHIP LAYOUT",
        ] {
            XCTAssertTrue(master.contains(needle),
                          "PileNode.swift lost the canonical constant/marker: \(needle)")
        }
    }

    func testEverySurfaceRoutesThroughTheCanonicalLayout() throws {
        // v6.81: UIKit surfaces that show a card WITH its chips must route
        // through the ONE baked renderer, CardComposite — never hand-placed
        // chip views beside card faces (the negative-zPosition trap that
        // kept sinking chips 2…4 beneath sibling card faces; see
        // CardComposite's header). The composite itself is the one place
        // that caps at maxStickersPerCard and reads StickerChipLayout.
        for path in ["UI/DeckInspectViewController.swift", "UI/PileFanOverlayView.swift"] {
            let src = try source(path)
            XCTAssertTrue(src.contains("CardComposite"),
                          "\(path) must render cards through CardComposite")
            XCTAssertFalse(src.contains("zPosition = CGFloat(-"),
                           "\(path) re-grew sibling chip views with negative zPositions")
        }
        let composite = try source("UI/CardComposite.swift")
        XCTAssertTrue(composite.contains("StickerChipLayout"),
                      "CardComposite must take its geometry from StickerChipLayout")
        XCTAssertTrue(composite.contains("maxStickersPerCard"),
                      "CardComposite must cap at maxStickersPerCard")
        XCTAssertFalse(composite.contains(".prefix(3)"),
                       "CardComposite truncates below maxStickersPerCard")
        // The remaining chip-drawing surfaces (SpriteKit board, the picker's
        // isolated chip holder, baked map minis, curse cells) still compute
        // geometry through the shared layout and never hard-truncate.
        let surfaces = [
            "Rendering/PileNode.swift",
            "UI/CardPickerViewController.swift",
            "UI/PhaseOverlayView.swift",
            "UI/MapViewController.swift",
        ]
        for path in surfaces {
            let src = try source(path)
            XCTAssertTrue(src.contains("StickerChipLayout"),
                          "\(path) no longer routes through StickerChipLayout")
            XCTAssertFalse(src.contains(".prefix(3)"),
                           "\(path) truncates a sticker display below maxStickersPerCard")
            XCTAssertTrue(src.contains("maxStickersPerCard"),
                          "\(path) must cap its chip fan at maxStickersPerCard")
        }
    }

    func testPickerCarriesTheCanonicalReasonMessages() throws {
        let src = try source("UI/CardPickerViewController.swift")
        for needle in [
            #""Card has max (\(max)) stickers""#,
            #""This sticker can only be applied to \(suits.joined(separator: "/")) cards""#,
            "Rank is already at the top (Ace)",
            "Rank is already at the bottom (2)",
            "Jokers never take stickers",
            "stickerIneligibilityReason",
        ] {
            XCTAssertTrue(src.contains(needle),
                          "CardPickerViewController.swift lost the reason text/function: \(needle)")
        }
    }

    // MARK: - Mirror of the ineligibility classifier (CardPickerViewController)

    private enum Reason: Equatable {
        case deckNoStickers, joker, purgeCard
        case maxStickers(Int)
        case duplicate(String)
        case wrongSuit([String])
        case rankAtMax, rankAtMin

        var message: String {
            switch self {
            case .deckNoStickers: return "This deck never takes stickers"
            case .joker: return "Jokers never take stickers"
            case .purgeCard: return "Purge cards never take stickers"
            case .maxStickers(let max): return "Card has max (\(max)) stickers"
            case .duplicate(let label): return "Card already has \(label)"
            case .wrongSuit(let suits):
                return "This sticker can only be applied to \(suits.joined(separator: "/")) cards"
            case .rankAtMax: return "Rank is already at the top (Ace)"
            case .rankAtMin: return "Rank is already at the bottom (2)"
            }
        }
    }

    private func reason(_ card: CardSpec, _ def: ItemDef,
                        deckNoStickers: Bool = false) -> Reason? {
        let maxStickers = data.items.maxStickersPerCard
        if deckNoStickers { return .deckNoStickers }
        if card.joker { return .joker }
        if card.blank { return .purgeCard }
        if card.stickers.count >= maxStickers { return .maxStickers(maxStickers) }
        if card.stickers.contains(where: { $0.type == def.id }) { return .duplicate(def.label) }
        if let suits = def.suits, !suits.isEmpty,
           !CardRules.isWildSuit(card, data: data), !suits.contains(card.suit) {
            return .wrongSuit(suits)
        }
        if def.kind == "rank" {
            let delta = def.num("rankDelta", 0)
            if delta > 0 && card.currentRank >= maxRank { return .rankAtMax }
            if delta < 0 && card.currentRank <= minRank { return .rankAtMin }
        }
        return nil
    }

    /// A plain unrestricted (non-rank, non-suit-locked) sticker for baselines.
    private var plainSticker: ItemDef? {
        data.items.stickers.first {
            !$0.cursed && ($0.suits?.isEmpty ?? true) && $0.kind != "rank"
        }
    }

    func testMaxStickersReasonFiresExactlyAtTheCap() {
        guard let plain = plainSticker else { return XCTFail("need an unrestricted sticker") }
        let cap = data.items.maxStickersPerCard
        XCTAssertEqual(cap, 4)
        // Fill the card with cap DISTINCT other stickers (duplicates are
        // banned, so the full-card case in the wild is always distinct types).
        let others = data.items.stickers.filter { $0.id != plain.id }.prefix(cap)
        XCTAssertEqual(others.count, cap, "items.js should carry > \(cap) sticker types")
        var card = CardSpec(id: 1, suit: "♠", originalRank: 7, currentRank: 7)
        for d in others.dropLast() { card.stickers.append(StickerRecord(type: d.id)) }
        XCTAssertNil(reason(card, plain), "one slot left — still eligible")
        card.stickers.append(StickerRecord(type: others.last!.id))
        XCTAssertEqual(reason(card, plain), .maxStickers(cap))
        XCTAssertEqual(reason(card, plain)?.message, "Card has max (4) stickers")
    }

    func testWrongSuitReasonFiresExactlyOffSuit() {
        guard let restricted = data.items.stickers.first(where: { ($0.suits?.count ?? 0) == 1 })
        else { return XCTFail("items.js should ship a suit-locked sticker") }
        let wanted = restricted.suits![0]
        for s in ["♠", "♥", "♦", "♣"] {
            let card = CardSpec(id: 2, suit: s, originalRank: 5, currentRank: 5)
            if s == wanted {
                XCTAssertNil(reason(card, restricted), "on-suit must be eligible")
            } else {
                XCTAssertEqual(reason(card, restricted), .wrongSuit(restricted.suits!))
                XCTAssertEqual(reason(card, restricted)?.message,
                               "This sticker can only be applied to \(wanted) cards")
            }
        }
        // A Wild Suit card counts as every suit — no reason fires.
        if let wild = data.items.stickers.first(where: { $0.behavior == "wildSuit" }) {
            let off = ["♠", "♥", "♦", "♣"].first { $0 != wanted }!
            var card = CardSpec(id: 3, suit: off, originalRank: 5, currentRank: 5)
            card.stickers.append(StickerRecord(type: wild.id))
            XCTAssertNil(reason(card, restricted))
        }
    }

    func testRankBoundaryReasons() {
        guard let up = data.items.stickers.first(where: { $0.kind == "rank" && $0.num("rankDelta", 0) > 0 }),
              let down = data.items.stickers.first(where: { $0.kind == "rank" && $0.num("rankDelta", 0) < 0 })
        else { return XCTFail("items.js should ship ±rank stickers") }
        let ace = CardSpec(id: 4, suit: "♠", originalRank: maxRank, currentRank: maxRank)
        let two = CardSpec(id: 5, suit: "♠", originalRank: minRank, currentRank: minRank)
        let mid = CardSpec(id: 6, suit: "♠", originalRank: 8, currentRank: 8)
        XCTAssertEqual(reason(ace, up), .rankAtMax)
        XCTAssertEqual(reason(two, down), .rankAtMin)
        XCTAssertNil(reason(mid, up))
        XCTAssertNil(reason(mid, down))
        XCTAssertNil(reason(ace, down), "an Ace can still go DOWN")
        XCTAssertNil(reason(two, up), "a 2 can still go UP")
    }

    func testDuplicateJokerAndPurgeReasons() {
        guard let plain = plainSticker else { return XCTFail("need an unrestricted sticker") }
        var carrying = CardSpec(id: 7, suit: "♥", originalRank: 9, currentRank: 9)
        carrying.stickers.append(StickerRecord(type: plain.id))
        XCTAssertEqual(reason(carrying, plain), .duplicate(plain.label))
        XCTAssertEqual(reason(CardSpec.joker(id: 8), plain), .joker)
        XCTAssertEqual(reason(CardSpec.blank(id: 9), plain), .purgeCard)
        XCTAssertEqual(reason(carrying, plain, deckNoStickers: true), .deckNoStickers,
                       "the deck rule outranks every card-level reason")
    }

    /// The classifier must agree with the engine's real gate: for every
    /// sticker type × a spread of cards, `reason == nil` exactly when
    /// `CardRules.stickerEligible` + the rank-boundary rule say yes.
    func testClassifierAgreesWithTheRealEligibilityGate() {
        var cards: [CardSpec] = [
            CardSpec.joker(id: 100), CardSpec.blank(id: 101),
        ]
        for (i, s) in ["♠", "♥", "♦", "♣"].enumerated() {
            for r in [minRank, 8, maxRank] {
                cards.append(CardSpec(id: 200 + i * 10 + r, suit: s, originalRank: r, currentRank: r))
            }
        }
        var full = CardSpec(id: 300, suit: "♠", originalRank: 7, currentRank: 7)
        for d in data.items.stickers.prefix(data.items.maxStickersPerCard) {
            full.stickers.append(StickerRecord(type: d.id))
        }
        cards.append(full)
        for def in data.items.stickers {
            for card in cards {
                let gate = CardRules.stickerEligible(card, def.id, data: data)
                var rankOK = true
                if def.kind == "rank" {
                    let delta = def.num("rankDelta", 0)
                    if delta > 0 && card.currentRank >= maxRank { rankOK = false }
                    if delta < 0 && card.currentRank <= minRank { rankOK = false }
                }
                XCTAssertEqual(reason(card, def) == nil, gate && rankOK,
                               "classifier disagrees with the gate: '\(def.id)' on card \(card.id)")
            }
        }
    }
}
