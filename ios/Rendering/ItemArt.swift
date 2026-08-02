import UIKit
import GameCore

/// Store/inventory object art — the merchandise itself, in the CRT CASINO
/// language. EVERY object is the web's PixelArt sheet (index.html, the
/// `PixelArt` module ~line 7393) ported to Swift matrices below: same 16×16
/// grids, same palette, same dither phase — rendered flat at an integer
/// matrix scale (nearest-neighbour, no filters) and cached per (kind, id,
/// size). Callers aspect-fit + `.nearest`-scale the result, the same trick
/// as the web's `image-rendering: pixelated`.
///
/// Matrix alphabet (identical to the web):
///   K ink · C cream · R red · G gold · P phosphor · F felt-mid · D felt-deep
///   '.' transparent; lowercase = the §1 optical dithers, expanded per-pixel
///   by (x+y)%2 (even → first colour):
///     p = C⊕R "pink" · b = G⊕D "brass" · g = F⊕D "felt" · s = C⊕F "smoke".
///
/// Composition mirrors the web exactly:
///   sticker    = the `sticker` chip matrix + the sticker's own 16×16 face
///                (STICKER_ICONS) contain-fit in the central 58% box; cursed
///                (leech/leech2) = the `stickerCursed`/`stickerCursed2`
///                corruption matrices with NO inner face; a `suits`
///                restriction rides the bottom rim as 8×8 pixel badges.
///   pillar     = the `pillar` pennant matrix + the item's glyph inked gold
///                over an ink halo on the emblem spot (web .pb-emblem).
///   base       = the `base` plaque matrix (trimmed like the web) + the
///                item's symbol in its FAMILY colour (dig phosphor · destroy
///                red · coins gold · peek/util cream).
///   samePower  = the `samePower` phosphor-diamond class mark + the name.
///   pack       = the `packCard`/`packSticker`/`packLarge` foil matrices
///                (large = registry `keep` ≥ 2, the web rule) + the name.
///   removal    = the `removal` torn-card matrix (trimmed).
public enum ItemArt {

    private static var cache: [String: UIImage] = [:]
    private static func baked(_ key: String, _ make: () -> UIImage) -> UIImage {
        if let c = cache[key] { return c }
        let img = make()
        cache[key] = img
        return img
    }

    /// Tier rim colors: common recedes, uncommon gold, rare phosphor.
    static func tierColor(_ tier: String) -> UIColor {
        switch tier {
        case "rare": return CRT.phosphor
        case "uncommon": return CRT.gold
        default: return CRT.cardFace
        }
    }

    // MARK: - PixelArt engine (the web's colorAt / matrixToDataURI / trimmed)

    /// One matrix cell → palette colour (nil = transparent). Dither phase
    /// from MATRIX coords, so it never swims at any render scale.
    private static func pxColor(_ ch: Character, x: Int, y: Int) -> UIColor? {
        let even = (x + y) % 2 == 0
        switch ch {
        case "K": return CRT.ink
        case "C": return CRT.cardFace
        case "R": return CRT.suitRed
        case "G": return CRT.gold
        case "P": return CRT.phosphor
        case "F": return CRT.feltMid
        case "D": return CRT.feltDeep
        case "p": return even ? CRT.cardFace : CRT.suitRed    // pink   C⊕R
        case "b": return even ? CRT.gold : CRT.feltDeep       // brass  G⊕D
        case "g": return even ? CRT.feltMid : CRT.feltDeep    // felt   F⊕D
        case "s": return even ? CRT.cardFace : CRT.feltMid    // smoke  C⊕F
        default: return nil
        }
    }

    /// Paint a matrix into `cg` at (ox, oy), one `cell`-sized rect per pixel.
    private static func drawMatrix(_ cg: CGContext, _ rows: [String],
                                   ox: CGFloat, oy: CGFloat, cell: CGFloat) {
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                guard let c = pxColor(ch, x: x, y: y) else { continue }
                cg.setFillColor(c.cgColor)
                cg.fill(CGRect(x: ox + CGFloat(x) * cell, y: oy + CGFloat(y) * cell,
                               width: cell, height: cell))
            }
        }
    }

    /// Crop fully-transparent border rows/cols — the web's `trimmed()`, used
    /// for the icons that FILL a shaped box (plaque / pack / card faces).
    private static func trimmed(_ rows: [String]) -> [String] {
        var top = rows.count, bot = -1, left = Int.max, right = -1
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() where ch != "." {
                if y < top { top = y }
                if y > bot { bot = y }
                if x < left { left = x }
                if x > right { right = x }
            }
        }
        guard bot >= 0 else { return rows }
        return rows[top...bot].map { String($0.dropFirst(left).prefix(right - left + 1)) }
    }

    /// A matrix rendered to a UIImage at integer scale — the bitmap IS the
    /// pixel grid; callers scale with `.nearest`.
    private static func matrixImage(_ rows: [String], scale k: Int) -> UIImage {
        let w = rows[0].count * k, h = rows.count * k
        return PixelTexture.image(size: CGSize(width: w, height: h)) { cg in
            drawMatrix(cg, rows, ox: 0, oy: 0, cell: CGFloat(k))
        }
    }

    // MARK: - ITEM-CLASS ICONS (the web's `ICONS`, §7)

    private static let classArt: [String: [String]] = [
        "sticker": [
            "................",
            ".....KKKKKK.....",
            "...KKCCCCCCKK...",
            "..KCCCCCCCCCCK..",
            "..KCCCCCCCCCCK..",
            ".KCCCCCRRCCCCCK.",
            ".KCCCCRRRRCCCCK.",
            ".KCCCRRRRRRCCCK.",
            ".KCCCCRRRRCCCsK.",
            ".KCCCCCRRCCCssK.",
            "..KCCCCCCCCssK..",
            "..KCCCCCCCsssK..",
            "...KKCCCCssKK...",
            ".....KKKKKK.....",
            "................",
            "................"],
        // cursed = the same chip corrupted: phosphor bit-rot, one displaced
        // row, a torn rim — the template for cursing ANY chip.
        "stickerCursed": [
            "................",
            ".....KKKKKK.....",
            "...KKCCCPCCKK...",
            "..KCCCCCCCCCCK..",
            "..KCCCCCCCCCCK..",
            ".KCCCCCRRCCPCCK.",
            ".KCCCCRRRRCCCCK.",
            "....KCCRRRRRRCCK",
            ".KCCCCRRPRCCCsK.",
            ".KCCPCCRRCCCssK.",
            "..KCCCCCCCCssK..",
            "..KCCCCCPCsssK..",
            "...KKCCCCssKK...",
            ".....KK.KKK.....",
            "................",
            "................"],
        // Leech SWARM's own corruption — same torn chip family, but a SCATTER
        // of small leeches instead of Leech's single big one.
        "stickerCursed2": [
            "................",
            ".....KKKKKK.....",
            "...KKCCCPCCKK...",
            "..KCRRCCCCCCCK..",
            "..KCRRCCCRRCCK..",
            ".KCCCCCCCRRCCCK.",
            ".KCCPCCCCCCCCCK.",
            "....KCCCCCCCCCCK",
            ".KCCRRCCCCCCCsK.",
            ".KCCRRCCCCPCssK.",
            "..KCCCCRRCCCsK..",
            "..KCCPCRRCsssK..",
            "...KKCCCCssKK...",
            ".....KK.KKK.....",
            "................",
            "................"],
        "pillar": [
            "................",
            ".KKKKKKKKKKKKKK.",
            ".KGGGGGGGGGGGGK.",
            ".KKKKKKKKKKKKKK.",
            "....KRRRRRRK....",
            "....KRRRRRRK....",
            "....KRCCCCRK....",
            "....KRCGGCRK....",
            "....KRCCCCRK....",
            "....KRRRRRRK....",
            "....KRRRRRRK....",
            "....KRRRRRRK....",
            "....KRRKKRRK....",
            "....KRK..KRK....",
            "....KK....KK....",
            "................"],
        "base": [
            "................",
            "................",
            "................",
            ".KKKKKKKKKKKKKK.",
            ".KCDDDDDDDDDDCK.",
            ".KDDDDDDDDDDDDK.",
            ".KDDssssssssDDK.",
            ".KDDDDDDDDDDDDK.",
            ".KDDDDDPPDDDDDK.",
            ".KDDDDDDDDDDDDK.",
            ".KCDDDDDDDDDDCK.",
            ".KKKKKKKKKKKKKK.",
            "................",
            "................",
            "................",
            "................"],
        "samePower": [
            "................",
            ".......KK.......",
            "......KPPK......",
            ".....KPPPPK.....",
            "....KPPPPPPK....",
            "...KPPPPPPPPK...",
            "..KPPPPPPPPPPK..",
            ".KPPPKKKKKKPPPK.",
            ".KPPPPPPPPPPPPK.",
            "..KPPKKKKKKPPK..",
            "...KPPPPPPPPK...",
            "....KPPPPPPK....",
            ".....KPPPPK.....",
            "......KPPK......",
            ".......KK.......",
            "................"],
        "packCard": [
            "................",
            "...KKKKKKKKKK...",
            "...KCKCKCKCKK...",
            "...KKKKKKKKKK...",
            "...KRRRRRRRRK...",
            "...KRRRRRRRRK...",
            "...KRKKKKKKRK...",
            "...KRKDCCDKRK...",
            "...KRKDCCDKRK...",
            "...KRKDCCDKRK...",
            "...KRKKKKKKRK...",
            "...KRRRRRRRRK...",
            "...KKKKKKKKKK...",
            "...KCKCKCKCKK...",
            "...KKKKKKKKKK...",
            "................"],
        "packSticker": [
            "................",
            "...KKKKKKKKKK...",
            "...KCKCKCKCKK...",
            "...KKKKKKKKKK...",
            "...KFFFFFFFFK...",
            "...KFFFFFFFFK...",
            "...KFKKKKKKFK...",
            "...KFKDCCDKFK...",
            "...KFKCRRCKFK...",
            "...KFKDCCDKFK...",
            "...KFKKKKKKFK...",
            "...KFFFFFFFFK...",
            "...KKKKKKKKKK...",
            "...KCKCKCKCKK...",
            "...KKKKKKKKKK...",
            "................"],
        "packLarge": [
            "................",
            "..KKKKKKKKKKKK..",
            "..KCKCKCKCKCKK..",
            "..KKKKKKKKKKKK..",
            "..KbbbbbbbbbbK..",
            "..KbbbbCCbbbbK..",
            "..KbbbCCCCbbbK..",
            "..KbCCCCCCCCbK..",
            "..KbbCCCCCCbbK..",
            "..KbbCCbbCCbbK..",
            "..KbCCbbbbCCbK..",
            "..KbbbbbbbbbbK..",
            "..KKKKKKKKKKKK..",
            "..KCKCKCKCKCKK..",
            "..KKKKKKKKKKKK..",
            "................"],
        // a card TORN IN HALF (offset halves, interlocking jagged tear, a
        // broken red pip split across the gap) — "removal" reads as
        // destruction, not an abstract circle-slash scribble.
        "removal": [
            "................",
            "..KKKKKK........",
            "..KCCCCK.KKKK...",
            "..KCCCCKKKCCKK..",
            "..KCCCKK.KCCCK..",
            "..KCRRK..KRCCK..",
            "..KCRRKK.KRRCK..",
            "..KCCCCK..KRCK..",
            "..KCCCKK.KCCCK..",
            "..KCCCK..KCCCK..",
            "..KCCCKK.KCCCK..",
            "..KCCCCK.KCCCK..",
            "..KKKKKK.KCCCK..",
            ".........KKKKK..",
            "................",
            "................"],
    ]

    // MARK: - PER-STICKER CHIP FACES (the web's `STICKER_ICONS`, CRT-STK)

    /// One hand-authored 16×16 matrix per NON-CURSED items.js sticker (cursed
    /// leech/leech2 keep the stickerCursed corruption art). Families share a
    /// silhouette so the FUNCTION reads first, then the item within its
    /// family. The web's StickerTypes FAILS LOUDLY if a non-cursed sticker
    /// lacks art here — the sheet and items.js stay 1:1 by contract.
    private static let stickerFaces: [String: [String]] = [
        "rankUp": [
            "......KKKK......",
            ".....KCCCCK.....",
            "....KCCKKCCK....",
            "...KCCCKKCCCK...",
            "..KCCCCCCCCCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCKKKKCCCK..",
            "..KCCKKKKKKCCK..",
            "..KCKKKKKKKKCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCCCCCCCCK..",
            "..KKKKKKKKKKKK..",
            "................"],
        "rankDown": [
            "......KKKK......",
            ".....KCCCCK.....",
            "....KCCKKCCK....",
            "...KCCCKKCCCK...",
            "..KCCCCCCCCCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCCKKCCCCK..",
            "..KCKKKKKKKKCK..",
            "..KCCKKKKKKCCK..",
            "..KCCCKKKKCCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCCCCCCCCK..",
            "..KKKKKKKKKKKK..",
            "................"],
        "rankUp2": [
            "......KKKK......",
            ".....KCCCCK.....",
            "....KCCKKCCK....",
            "...KCCCKKCCCK...",
            "..KCCCCCCCCCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCKKKKCCCK..",
            "..KCCKKKKKKCCK..",
            "..KCCCCCCCCCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCKKKKCCCK..",
            "..KCCKKKKKKCCK..",
            "..KCCCCCCCCCCK..",
            "..KCCCCCCCCCCK..",
            "..KKKKKKKKKKKK..",
            "................"],
        "rankDown2": [
            "......KKKK......",
            ".....KCCCCK.....",
            "....KCCKKCCK....",
            "...KCCCKKCCCK...",
            "..KCCCCCCCCCCK..",
            "..KCCKKKKKKCCK..",
            "..KCCCKKKKCCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCCCCCCCCK..",
            "..KCCKKKKKKCCK..",
            "..KCCCKKKKCCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCCCCCCCCK..",
            "..KCCCCCCCCCCK..",
            "..KKKKKKKKKKKK..",
            "................"],
        "randomFixedValue": [
            "......KKKK......",
            ".....KCCCCK.....",
            "....KCCKKCCK....",
            "...KCCCKKCCCK...",
            "..KCCCCCCCCCCK..",
            "..KCCCKKKKCCCK..",
            "..KCCKKCCKKCCK..",
            "..KCCCCCCKKCCK..",
            "..KCCCCKKKCCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCCCCCCCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCCCCCCCCK..",
            "..KKKKKKKKKKKK..",
            "................"],
        "changeSuitSpade": [
            "................",
            "..KKKKKKKKKKKK..",
            "..KCCCCKKCCCCK..",
            "..KCCCKKKKCCCK..",
            "..KCCKKKKKKCCK..",
            "..KCKKKKKKKKCK..",
            "..KCKKKKKKKKCK..",
            "..KCCKKCCKKCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCKKKKCCCK..",
            "...KCCCCCCCCK...",
            "....KCCCCCCK....",
            ".....KCCCCK.....",
            "......KCCK......",
            ".......KK.......",
            "................"],
        "changeSuitHeart": [
            "................",
            "..KKKKKKKKKKKK..",
            "..KCCCCCCCCCCK..",
            "..KCRRCCCCRRCK..",
            "..KRRRRCCRRRRK..",
            "..KRRRRRRRRRRK..",
            "..KRRRRRRRRRRK..",
            "..KCRRRRRRRRCK..",
            "..KCCRRRRRRCCK..",
            "..KCCCRRRRCCCK..",
            "...KCCCRRCCCK...",
            "....KCCCCCCK....",
            ".....KCCCCK.....",
            "......KCCK......",
            ".......KK.......",
            "................"],
        "changeSuitDiamond": [
            "................",
            "..KKKKKKKKKKKK..",
            "..KCCCCRRCCCCK..",
            "..KCCCRRRRCCCK..",
            "..KCCRRRRRRCCK..",
            "..KCRRRRRRRRCK..",
            "..KCRRRRRRRRCK..",
            "..KCCRRRRRRCCK..",
            "..KCCCRRRRCCCK..",
            "..KCCCCRRCCCCK..",
            "...KCCCCCCCCK...",
            "....KCCCCCCK....",
            ".....KCCCCK.....",
            "......KCCK......",
            ".......KK.......",
            "................"],
        "changeSuitClub": [
            "................",
            "..KKKKKKKKKKKK..",
            "..KCCCCKKCCCCK..",
            "..KCCCKKKKCCCK..",
            "..KCCCKKKKCCCK..",
            "..KCKKKCCKKKCK..",
            "..KCKKKKKKKKCK..",
            "..KCKKKCCKKKCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCKKKKCCCK..",
            "...KCCCCCCCCK...",
            "....KCCCCCCK....",
            ".....KCCCCK.....",
            "......KCCK......",
            ".......KK.......",
            "................"],
        "changeSuitRandom": [
            "................",
            "..KKKKKKKKKKKK..",
            "..KCCCKKKKCCCK..",
            "..KCCKKCCKKCCK..",
            "..KCCCCCCKKCCK..",
            "..KCCCCKKKCCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCCCCCCCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCCKKCCCCK..",
            "...KCCCCCCCCK...",
            "....KCCCCCCK....",
            ".....KCCCCK.....",
            "......KCCK......",
            ".......KK.......",
            "................"],
        "wildSuit": [
            "KKKKKKK.KKKKKKK.",
            "KCCKCCK.KRRCRRK.",
            "KCKKKCK.KRRRRRK.",
            "KKKKKKK.KRRRRRK.",
            "KKKKKKK.KCRRRCK.",
            "KCCKCCK.KCCRCCK.",
            "KKKKKKK.KKKKKKK.",
            "................",
            "KKKKKKK.KKKKKKK.",
            "KCCRCCK.KCCKCCK.",
            "KCRRRCK.KCKKKCK.",
            "KRRRRRK.KKKKKKK.",
            "KCRRRCK.KCCKCCK.",
            "KCCRCCK.KCKKKCK.",
            "KKKKKKK.KKKKKKK.",
            "................"],
        "suitImmunity": [
            "................",
            "..KKKKKKKKKKKK..",
            "..KCCCCCCCCCCK..",
            "..KCKKKKKKKKCK..",
            "..KCKKKCCKKKCK..",
            "..KCKKCCCCKKCK..",
            "..KCKCCCCCCKCK..",
            "..KCKCCCCCCKCK..",
            "..KCKKKCCKKKCK..",
            "..KCKKCCCCKKCK..",
            "...KCKKKKKKCK...",
            "....KCKKKKCK....",
            ".....KCKKCK.....",
            "......KCCK......",
            ".......KK.......",
            "................"],
        "heartGuard": [
            "................",
            "..KKKKKKKKKKKK..",
            "..KCCCCCCCCCCK..",
            "..KCKKKKKKKKCK..",
            "..KCKRRKKRRKCK..",
            "..KCKRRRRRRKCK..",
            "..KCKRRRRRRKCK..",
            "..KCKKRRRRKKCK..",
            "..KCKKKRRKKKCK..",
            "..KCKKKKKKKKCK..",
            "...KCKKKKKKCK...",
            "....KCKKKKCK....",
            ".....KCKKCK.....",
            "......KCCK......",
            ".......KK.......",
            "................"],
        "diamondGuard": [
            "................",
            "..KKKKKKKKKKKK..",
            "..KCCCCCCCCCCK..",
            "..KCKKKRRKKKCK..",
            "..KCKKRRRRKKCK..",
            "..KCKRRRRRRKCK..",
            "..KCKRRRRRRKCK..",
            "..KCKKRRRRKKCK..",
            "..KCKKKRRKKKCK..",
            "..KCKKKKKKKKCK..",
            "...KCKKKKKKCK...",
            "....KCKKKKCK....",
            ".....KCKKCK.....",
            "......KCCK......",
            ".......KK.......",
            "................"],
        "clubGuard": [
            "................",
            "..KKKKKKKKKKKK..",
            "..KCCCCCCCCCCK..",
            "..KCKKKCCKKKCK..",
            "..KCKKKCCKKKCK..",
            "..KCKCCKKCCKCK..",
            "..KCKCCCCCCKCK..",
            "..KCKKKCCKKKCK..",
            "..KCKKCCCCKKCK..",
            "..KCKKKKKKKKCK..",
            "...KCKKKKKKCK...",
            "....KCKKKKCK....",
            ".....KCKKCK.....",
            "......KCCK......",
            ".......KK.......",
            "................"],
        "tieSafe": [
            "................",
            "..KKKKKKKKKKKK..",
            "..KCCCCCCCCCCK..",
            "..KCKKKKKKKKCK..",
            "..KCKPPPPPPKCK..",
            "..KCKPPPPPPKCK..",
            "..KCKKKKKKKKCK..",
            "..KCKPPPPPPKCK..",
            "..KCKPPPPPPKCK..",
            "..KCKKKKKKKKCK..",
            "...KCKKKKKKCK...",
            "....KCKKKKCK....",
            ".....KCKKCK.....",
            "......KCCK......",
            ".......KK.......",
            "................"],
        "extraCoin": [
            "................",
            "................",
            ".....KKKKKK.....",
            "...KKGGGGGGKK...",
            "..KGGGKKKKGGGK..",
            "..KGGGKKKKGGGK..",
            ".KGGGGGGGGGGGGK.",
            ".KGGGKKKKKKGGGK.",
            ".KGGGKKKKKKGGGK.",
            ".KGGGGGGGGGGGGK.",
            "..KGKKKKKKKKGK..",
            "..KGKKKKKKKKGK..",
            "...KKGGGGGGKK...",
            ".....KKKKKK.....",
            "................",
            "................"],
        "gainCoin": [
            "................",
            "................",
            ".....KKKKKK.....",
            "...KKGGGGGGKK...",
            "..KGGGGKKGGGGK..",
            "..KGGGGKKGGGGK..",
            ".KGGGGGKKGGGGGK.",
            ".KGGKKKKKKKKGGK.",
            ".KGGKKKKKKKKGGK.",
            ".KGGGGGKKGGGGGK.",
            "..KGGGGKKGGGGK..",
            "..KGGGGKKGGGGK..",
            "...KKGGGGGGKK...",
            ".....KKKKKK.....",
            "................",
            "................"],
        "deathBounty": [
            "................",
            "................",
            ".....KKKKKK.....",
            "...KKGGGGGGKK...",
            "..KGGGCCCCGGGK..",
            "..KGGCCCCCCGGK..",
            ".KGGCKKCCKKCGGK.",
            ".KGGCKKCCKKCGGK.",
            ".KGGCCCCCCCCGGK.",
            ".KGGGCCCCCCGGGK.",
            "..KGGCGCGCGGGK..",
            "..KGGGGGGGGGGK..",
            "...KKGGGGGGKK...",
            ".....KKKKKK.....",
            "................",
            "................"],
        "looseChange": [
            "................",
            "................",
            ".....KKKKKK.....",
            "...KKGGGGGGKK...",
            "..KGKKGGGGKKGK..",
            "..KGKKGGGGKKGK..",
            ".KGGGGGGGGGGGGK.",
            ".KGGGGGKKGGGGGK.",
            ".KGGGGGKKGGGGGK.",
            ".KGGGGGGGGGGGGK.",
            "..KGKKGGGGKKGK..",
            "..KGKKGGGGKKGK..",
            "...KKGGGGGGKK...",
            ".....KKKKKK.....",
            "................",
            "................"],
        "deepPockets": [
            "................",
            "......KKKK......",
            "....KKGGGGKK....",
            "...KGGGGGGGGK...",
            "...KGGGGGGGGK...",
            "...KGGGGGGGGK...",
            ".KKKKKKKKKKKKKK.",
            ".KFFFFFFFFFFFFK.",
            ".KFFFFFFFFFFFFK.",
            ".KFFFFFFFFFFFFK.",
            ".KFFFFFFFFFFFFK.",
            "..KFFFFFFFFFFK..",
            "...KFFFFFFFFK...",
            "....KKKKKKKK....",
            "................",
            "................"],
        "collector": [
            "................",
            "................",
            ".....KKKKKK.....",
            "...KKGGGGGGKK...",
            "..KGGCCGGCCGGK..",
            "..KGGKKGGKKGGK..",
            ".KGGGKKGGKKGGGK.",
            ".KGGGKKGGKKGGGK.",
            ".KGGGKKGGKKGGGK.",
            ".KGGGKKKKKKGGGK.",
            "..KGGKKKKKKGGK..",
            "..KGGGKKKKGGGK..",
            "...KKGGGGGGKK...",
            ".....KKKKKK.....",
            "................",
            "................"],
        "compound": [
            "................",
            "................",
            ".....KKKKKK.....",
            "...KKGGGGGGKK...",
            "..KGGGGGGGGGGK..",
            "..KGGGGGGGKKGK..",
            ".KGGGGGGGGKKGGK.",
            ".KGGGGGKKGKKGGK.",
            ".KGGGGGKKGKKGGK.",
            ".KGGKKGKKGKKGGK.",
            "..KGKKGKKGKKGK..",
            "..KGKKKKKKKKGK..",
            "...KKGGGGGGKK...",
            ".....KKKKKK.....",
            "................",
            "................"],
        "heartSnob": [
            "................",
            "................",
            ".....KKKKKK.....",
            "...KKGGGGGGKK...",
            "..KGGGGGGGGGGK..",
            "..KGKRRKKRRKGK..",
            ".KGKRRRRRRRRKGK.",
            ".KGKRRRRRRRRKGK.",
            ".KGGKRRRRRRKGGK.",
            ".KGGGKRRRRKGGGK.",
            "..KGGGKRRKGGGK..",
            "..KGGGGKKGGGGK..",
            "...KKGGGGGGKK...",
            ".....KKKKKK.....",
            "................",
            "................"],
        "heartChoir": [
            "................",
            "................",
            ".....KKKKKK.....",
            "...KKGGGGGGKK...",
            "..KGGGGGGGGGGK..",
            "..KGGGGGGGGGGK..",
            ".KRRGRRGGRRGRRK.",
            ".KRRRRRGGRRRRRK.",
            ".KGRRRGGGGRRRGK.",
            ".KGGRGGGGGGRGGK.",
            "..KGGGGGGGGGGK..",
            "..KGGGGGGGGGGK..",
            "...KKGGGGGGKK...",
            ".....KKKKKK.....",
            "................",
            "................"],
        "oneTribute": [
            "....KKKKKK......",
            "....KCCCCK......",
            "....KKCCKK......",
            ".....KCCK.......",
            ".....KCCK.......",
            ".....KCCK.......",
            ".....KCCK.......",
            "..KKKKCCKKKK....",
            "..KDDDCCDDDK....",
            "..KDDDCCDDDK....",
            "..KDDDDDDDDK....",
            "...KDDDDDDK.....",
            "....KDDDDK......",
            ".....KDDK.......",
            "......KK........",
            "................"],
        "twoTribute": [
            "....KKKKKK......",
            "....KCCCCK......",
            "....KKCCKK......",
            ".....KCCK.......",
            ".....KCCK.......",
            ".....KCCK.......",
            ".....KCCK.......",
            "..KKKKCCKKKK....",
            "..KDCCDDCCDK....",
            "..KDCCDDCCDK....",
            "..KDDDDDDDDK....",
            "...KDDDDDDK.....",
            "....KDDDDK......",
            ".....KDDK.......",
            "......KK........",
            "................"],
        "quickBury": [
            "....KKKKKK...KK.",
            "....KCCCCK..KK..",
            "....KKCCKK.KK...",
            ".....KCCK..KKKK.",
            ".....KCCK...KK..",
            ".....KCCK..KK...",
            ".....KCCK.KK....",
            "..KKKKCCKKKK....",
            "..KDDDDDDDDK....",
            "..KDDDDDDDDK....",
            "..KDDDDDDDDK....",
            "...KDDDDDDK.....",
            "....KDDDDK......",
            ".....KDDK.......",
            "......KK........",
            "................"],
        "snowball": [
            "....KKKKKK..KKK.",
            "....KCCCCK.KCCCK",
            "....KKCCKK.KCsCK",
            ".....KCCK..KCCCK",
            ".....KCCK...KKK.",
            ".....KCCK.......",
            ".....KCCK.......",
            "..KKKKCCKKKK....",
            "..KDDDDDDDDK....",
            "..KDDDDDDDDK....",
            "..KDDDDDDDDK....",
            "...KDDDDDDK.....",
            "....KDDDDK......",
            ".....KDDK.......",
            "......KK........",
            "................"],
        "clubSnob": [
            "....KKKKKK......",
            "....KCCCCK......",
            "....KKCCKK......",
            ".....KCCK.......",
            ".....KCCK.......",
            ".....KCCK.......",
            ".....KCCK.......",
            "..KKKKCCKKKK....",
            "..KDDDCCDDDK....",
            "..KDCCDCCDDK....",
            "..KDCCCCCCDK....",
            "...KDDCCDDK.....",
            "....KDCCDK......",
            ".....KDDK.......",
            "......KK........",
            "................"],
        "clubRoots": [
            "....KKKKKK..PP..",
            "....KCCCCK..PP..",
            "....KKCCKKPP..PP",
            ".....KCCK.PPPPPP",
            ".....KCCK...PP..",
            ".....KCCK..PPPP.",
            ".....KCCK.......",
            "..KKKKCCKKKK....",
            "..KDDDDDDDDK....",
            "..KDDDDDDDDK....",
            "..KDDDDDDDDK....",
            "...KDDDDDDK.....",
            "....KDDDDK......",
            ".....KDDK.......",
            "...PP.KK..PP....",
            ".......PP......."],
        "donate": [
            "....KKKKKK......",
            "....KCCCCK...K..",
            "....KKCCKK...KK.",
            ".....KCCK.KKKKKK",
            ".....KCCK.KKKKKK",
            ".....KCCK....KK.",
            ".....KCCK....K..",
            "..KKKKCCKKKK....",
            "..KDDDDDDDDK....",
            "..KDDDDDDDDK....",
            "..KDDDDDDDDK....",
            "...KDDDDDDK.....",
            "....KDDDDK......",
            ".....KDDK.......",
            "......KK........",
            "................"],
        "revealNext": [
            "................",
            "................",
            "................",
            ".....KKKKKK.....",
            "...KKCCCCCCKK...",
            "..KCCCKPPKCCCK..",
            ".KCCCPPPPPPCCCK.",
            ".KCCCPPKKPPCCCK.",
            ".KCCCPPKKPPCCCK.",
            ".KCCCPPPPPPCCCK.",
            "..KCCCKPPKCCCK..",
            "...KKCCCCCCKK...",
            ".....KKKKKK.....",
            "................",
            "................",
            "................"],
        "tell": [
            ".......KK.......",
            "......KKKK......",
            ".....KKKKKK.....",
            "................",
            ".....KKKKKK.....",
            "...KKCCCCCCKK...",
            "..KCCCPPPPCCCK..",
            ".KCCCPPKKPPCCCK.",
            ".KCCCPPKKPPCCCK.",
            "..KCCCPPPPCCCK..",
            "...KKCCCCCCKK...",
            ".....KKKKKK.....",
            "................",
            ".....KKKKKK.....",
            "......KKKK......",
            ".......KK......."],
        "twinSpark": [
            ".....KK.........",
            "....KPPK........",
            "...KKPPKK.......",
            "..KPPPPPPK......",
            "...KKPPKK.......",
            "....KPPK........",
            ".....KK.........",
            "................",
            "...........KK...",
            "..........KPPK..",
            ".........KKPPKK.",
            "........KPPPPPPK",
            ".........KKPPKK.",
            "..........KPPK..",
            "...........KK...",
            "................"],
        "spadeWhispers": [
            "................",
            "...........PP...",
            "...KK.......PP..",
            "..KKKK...PP..PP.",
            ".KKKKKK...PP..PP",
            "KKKKKKKK..PP..PP",
            "KKKKKKKK..PP..PP",
            ".KK..KK..PP..PP.",
            "...KK.......PP..",
            "..KKKK.....PP...",
            "................",
            "................",
            "................",
            "................",
            "................",
            "................"],
        "suitSnob": [
            "....KKKKKK......",
            "..KKKKKKKKKK....",
            "..KKCCCCCCKK....",
            ".KKCCCCCCCCKK...",
            ".KKCCCKKCCCKK...",
            ".KKCCKKKKCCKK...",
            ".KKCKKKKKKCKK...",
            ".KKCKKKKKKCKK...",
            ".KKCCCKKCCCKK...",
            ".KKCCKKKKCCKK...",
            "..KKCCCCCCKK....",
            "..KKKKKKKKKK....",
            "..........KKK...",
            "...........KKK..",
            "............KK..",
            "................"],
        "pillarScout": [
            ".....KKKKKK.....",
            "...KKCCCCCCKK...",
            "..KCCCPPPPCCCK..",
            "...KKCCCCCCKK...",
            ".....KKKKKK.....",
            "................",
            "..KKKKKKKKKKKK..",
            "..KGGGGGGGGGGK..",
            "..KKKKKKKKKKKK..",
            ".....KRRRRK.....",
            ".....KRCCRK.....",
            ".....KRRRRK.....",
            ".....KRRRRK.....",
            ".....KRK.KRK....",
            ".....KK...KK....",
            "................"],
        "baseScout": [
            ".....KKKKKK.....",
            "...KKCCCCCCKK...",
            "..KCCCPPPPCCCK..",
            "...KKCCCCCCKK...",
            ".....KKKKKK.....",
            "................",
            "................",
            "................",
            ".KKKKKKKKKKKKKK.",
            ".KCDDDDDDDDDDCK.",
            ".KDDDDDDDDDDDDK.",
            ".KDDDPPPPPPDDDK.",
            ".KDDDDDDDDDDDDK.",
            ".KCDDDDDDDDDDCK.",
            ".KKKKKKKKKKKKKK.",
            "................"],
        "heavy": [
            "................",
            ".....KKKKKK.....",
            "....KK....KK....",
            "....KK....KK....",
            "..KKKKKKKKKKKK..",
            "..KKKKKKKKKKKK..",
            "..KKKKKCCKKKKK..",
            "..KKKKCCCKKKKK..",
            "..KKKKKCCKKKKK..",
            "..KKKKKCCKKKKK..",
            "..KKKKKCCKKKKK..",
            "..KKKKKCCKKKKK..",
            "..KKKCCCCCCKKK..",
            "..KKKKKKKKKKKK..",
            "................",
            "................"],
        "massive": [
            ".....KKKKKK.....",
            "....KK....KK....",
            "....KK....KK....",
            ".KKKKKKKKKKKKKK.",
            ".KKKKKKKKKKKKKK.",
            ".KKKKKCCCCKKKKK.",
            ".KKKKCCKKCCKKKK.",
            ".KKKKKKKKCCKKKK.",
            ".KKKKKKKCCKKKKK.",
            ".KKKKKKCCKKKKKK.",
            ".KKKKKCCKKKKKKK.",
            ".KKKKCCKKKKKKKK.",
            ".KKKKCCCCCCKKKK.",
            ".KKKKKKKKKKKKKK.",
            "................",
            "................"],
        "anchor": [
            "................",
            "......KKKK......",
            ".....KK..KK.....",
            ".....KK..KK.....",
            "......KKKK......",
            ".......KK.......",
            "....KKKKKKKK....",
            ".......KK.......",
            ".......KK.......",
            ".KK....KK....KK.",
            ".KKK...KK...KKK.",
            "..KKK..KK..KKK..",
            "...KKK.KK.KKK...",
            "....KKKKKKKK....",
            "......KKKK......",
            "................"],
        "shuffle": [
            "..............K.",
            ".............KK.",
            "............KKK.",
            ".KK.......KKKKK.",
            "..KK.....KK.....",
            "...KK...KK......",
            "....KK.KK.......",
            ".....KKKK.......",
            ".....KKKK.......",
            "....KK.KK.......",
            "...KK...KK......",
            "..KK.....KKKKKK.",
            ".KK.......KKKKK.",
            ".............KK.",
            "..............K.",
            "................"],
        "diamondRipple": [
            "................",
            ".......KK.......",
            "......KRRK......",
            ".....KRRRRK.....",
            "....KRRRRRRK....",
            "...KRRRRRRRRK...",
            "....KRRRRRRK....",
            ".....KRRRRK.....",
            "......KRRK......",
            ".......KK.......",
            "................",
            "..KKK......KKK..",
            ".KK..KKKKKK..KK.",
            "................",
            "KKK..........KKK",
            ".KKKKK....KKKKK."],
        "diamondSnob": [
            "..............K.",
            ".............KK.",
            "............KKK.",
            ".KK.......KKKKK.",
            "..KK...RRKK.....",
            "...KK.RRRR......",
            "....KRRRRRR.....",
            "....RRRRRRRR....",
            "....RRRRRRRR....",
            "....KRRRRRR.....",
            "...KK.RRRR......",
            "..KK...RRKKKKKK.",
            ".KK.......KKKKK.",
            ".............KK.",
            "..............K.",
            "................"],
        "rechargeSameShield": [
            "............KKK.",
            "...........KGGK.",
            ".KKKKKKKK.KGGK..",
            ".KPPPPPPK.KGGK..",
            ".KPPPPPPKKGGK...",
            ".KKKKKKKKKGGKKK.",
            ".........KGGGGK.",
            ".KKKKKKKK.KGK...",
            ".KPPPPPPK.KGK...",
            ".KPPPPPPKKGK....",
            ".KKKKKKKKKGK....",
            ".........KK.....",
            ".........K......",
            "................",
            "................",
            "................"],
        "activateSamePower": [
            ".K.....KK.....K.",
            "..K....KK....K..",
            "................",
            "...KKKKKKKKKK...",
            "...KPPPPPPPPK...",
            "...KPPPPPPPPK...",
            "...KKKKKKKKKK...",
            "KK............KK",
            "...KKKKKKKKKK...",
            "...KPPPPPPPPK...",
            "...KPPPPPPPPK...",
            "...KKKKKKKKKK...",
            "................",
            "..K....KK....K..",
            ".K.....KK.....K.",
            "................"],
    ]

    // MARK: - SUIT BADGES (the web's `SUIT_BADGES`)

    /// 8×8 suit-restriction badges — full-bleed suit on a cream chip,
    /// composited on the sticker chip's BOTTOM rim from the def's `suits`.
    private static let suitBadges: [String: [String]] = [
        "♠": ["CCCCCCCC", "CCCKKCCC", "CCKKKKCC", "CKKKKKKC", "CKKKKKKC", "CCCKKCCC", "CCKKKKCC", "CCCCCCCC"],
        "♥": ["CCCCCCCC", "CCCCCCCC", "CRRCCRRC", "CRRRRRRC", "CRRRRRRC", "CCRRRRCC", "CCCRRCCC", "CCCCCCCC"],
        "♦": ["CCCCCCCC", "CCCRRCCC", "CCRRRRCC", "CRRRRRRC", "CRRRRRRC", "CCRRRRCC", "CCCRRCCC", "CCCCCCCC"],
        "♣": ["CCCCCCCC", "CCCKKCCC", "CCCKKCCC", "CKKCCKKC", "CKKKKKKC", "CCCKKCCC", "CCKKKKCC", "CCCCCCCC"],
    ]

    // MARK: - Legacy glyph fallback (no-matrix items + emblem/symbol overlays)

    /// 12×12 pixel glyphs mapped from the item's behavior/effect family —
    /// used for the pillar's emblem glyph, the base's family symbol, and as
    /// the chip face for any sticker with no ported matrix (the web's
    /// fail-loud contract makes that set empty today).
    private static let iconMatrices: [String: [String]] = [
        // . transparent, K ink, R red, G gold, P phosphor, C cream
        "bury":    ["....KKKK....", "....K..K....", ".KK.K..K.KK.", ".K..K..K..K.", ".K.KKKKKK.K.", ".K...KK...K.",
                    ".K...KK...K.", ".K...KK...K.", ".K..KKKK..K.", ".K...KK...K.", ".KKKKKKKKKK.", "............"],
        "coin":    ["...KKKKKK...", "..KGGGGGGK..", ".KGGKKKKGGK.", ".KGKGGGGKGK.", ".KGKGKKGKGK.", ".KGKGKKGKGK.",
                    ".KGKGKKGKGK.", ".KGKGGGGKGK.", ".KGGKKKKGGK.", "..KGGGGGGK..", "...KKKKKK...", "............"],
        "shield":  ["..KKKKKKKK..", ".KCCCCCCCCK.", ".KCCCRRCCCK.", ".KCCRRRRCCK.", ".KCCRRRRCCK.", ".KCCCRRCCCK.",
                    "..KCCCCCCK..", "..KCCCCCCK..", "...KCCCCK...", "....KCCK....", ".....KK.....", "............"],
        "peek":    ["............", "............", "...KKKKKK...", "..KCCCCCCK..", ".KCCKKKKCCK.", "KCCKKPPKKCCK",
                    "KCCKKPPKKCCK", ".KCCKKKKCCK.", "..KCCCCCCK..", "...KKKKKK...", "............", "............"],
        "shuffle": ["............", ".KKKK...KKK.", ".K..K...K.K.", ".K..KKKKK.K.", ".K........K.", ".KKKKKKKKKK.",
                    ".K........K.", ".K.KKKKK..K.", ".K.K...K..K.", ".KKK...KKKK.", "............", "............"],
        "star":    [".....KK.....", "....KGGK....", "....KGGK....", ".KKKKGGKKKK.", ".KGGGGGGGGK.", "..KGGGGGGK..",
                    "...KGGGGK...", "...KGGGGK...", "..KGGKKGGK..", "..KGK..KGK..", "..KK....KK..", "............"],
        "skull":   ["...KKKKKK...", "..KCCCCCCK..", ".KCCCCCCCCK.", ".KCKKCCKKCK.", ".KCKKCCKKCK.", ".KCCCCCCCCK.",
                    "..KCCKKCCK..", "..KKCCCCKK..", "...KCKKCK...", "...KKKKKK...", "............", "............"],
        "bolt":    ["......KKK...", ".....KPPK...", "....KPPK....", "...KPPK.....", "..KPPPKKKK..", ".KPPPPPPPK..",
                    "...KKKPPK...", ".....KPPK...", "....KPPK....", "...KPK......", "..KK........", "............"],
        "anchor":  ["....KKKK....", "....K..K....", "....KKKK....", ".....KK.....", ".....KK.....", ".KK..KK..KK.",
                    ".K.K.KK.K.K.", ".K.K.KK.K.K.", "..K.KKKK.K..", "...KKKKKK...", "............", "............"],
        "heart":   ["............", "..KK....KK..", ".KRRK..KRRK.", "KRRRRKKRRRRK", "KRRRRRRRRRRK", "KRRRRRRRRRRK",
                    ".KRRRRRRRRK.", "..KRRRRRRK..", "...KRRRRK...", "....KRRK....", ".....KK.....", "............"],
    ]

    static func iconKey(for def: ItemDef) -> String? {
        let b = (def.behavior ?? def.effect ?? "").lowercased()
        let id = def.id.lowercased()
        if b.contains("bury") || id.contains("bury") || b.contains("tribute") { return "bury" }
        if b.contains("coin") || b.contains("payout") || b.contains("dividend") || id.contains("coin") { return "coin" }
        if b.contains("guard") || b.contains("shield") || b.contains("save") || b.contains("safe") { return "shield" }
        if b.contains("reveal") || b.contains("peek") || b.contains("scout") { return "peek" }
        if b.contains("shuffle") || b.contains("distribution") || b.contains("evenout") { return "shuffle" }
        if b.contains("joker") || b.contains("wild") { return "star" }
        if b.contains("kill") || b.contains("kamikaze") || b.contains("demolish") || b.contains("death") { return "skull" }
        if b.contains("revive") || b.contains("wind") || b.contains("phoenix") { return "bolt" }
        if b.contains("anchor") || b.contains("heavy") { return "anchor" }
        if b.contains("heart") || b.contains("leech") { return "heart" }
        return nil
    }

    private static func drawIcon(_ cg: CGContext, _ def: ItemDef, at rect: CGRect,
                                 color: UIColor, size: CGFloat) {
        // A suit glyph in the icon field renders as text (monochrome), a known
        // family gets its pixel matrix, anything else the label's first letter.
        let suitGlyphs = ["♠", "♥", "♦", "♣", "★", "=", "∅", "◉"]
        if let icon = def.icon, suitGlyphs.contains(icon) {
            UIGraphicsPushContext(cg)
            let text = icon as NSString
            let font = CRT.Font.of(size)
            let sz = text.size(withAttributes: [.font: font])
            let tint = (icon == "♥" || icon == "♦") ? CRT.suitRed : color
            text.draw(at: CGPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2),
                      withAttributes: [.font: font, .foregroundColor: tint])
            UIGraphicsPopContext()
            return
        }
        if let key = iconKey(for: def), let rows = iconMatrices[key] {
            let cell = min(rect.width, rect.height) / 12
            let ox = rect.midX - cell * 6, oy = rect.midY - cell * 6
            let pal: [Character: UIColor] = ["K": CRT.ink, "R": CRT.suitRed, "G": CRT.gold,
                                             "P": CRT.phosphor, "C": CRT.cardFace]
            for (yy, row) in rows.enumerated() {
                for (xx, ch) in row.enumerated() {
                    guard let c = pal[ch] else { continue }
                    cg.setFillColor(c.cgColor)
                    cg.fill(CGRect(x: ox + CGFloat(xx) * cell, y: oy + CGFloat(yy) * cell,
                                   width: cell + 0.4, height: cell + 0.4))
                }
            }
            return
        }
        UIGraphicsPushContext(cg)
        let text = String(def.label.prefix(1)).uppercased() as NSString
        let font = CRT.Font.of(size)
        let sz = text.size(withAttributes: [.font: font])
        text.draw(at: CGPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2),
                  withAttributes: [.font: font, .foregroundColor: color])
        UIGraphicsPopContext()
    }

    /// The pre-port octagon chip, kept ONLY for a non-cursed sticker with no
    /// matrix in `stickerFaces` (the web's StickerTypes contract fails loud
    /// long before that can happen — this is pure belt-and-braces).
    private static func legacyStickerChip(_ def: ItemDef, size: CGFloat) -> UIImage {
        PixelTexture.image(size: CGSize(width: size + 3, height: size + 3)) { cg in
            let cut = size * 0.22
            func chipPath(_ o: CGFloat) -> CGPath {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: o + cut, y: o))
                p.addLine(to: CGPoint(x: o + size - cut, y: o))
                p.addLine(to: CGPoint(x: o + size, y: o + cut))
                p.addLine(to: CGPoint(x: o + size, y: o + size - cut))
                p.addLine(to: CGPoint(x: o + size - cut, y: o + size))
                p.addLine(to: CGPoint(x: o + cut, y: o + size))
                p.addLine(to: CGPoint(x: o, y: o + size - cut))
                p.addLine(to: CGPoint(x: o, y: o + cut))
                p.closeSubpath()
                return p
            }
            cg.addPath(chipPath(3))
            cg.setFillColor(CRT.shadow.cgColor)
            cg.fillPath()
            cg.addPath(chipPath(0))
            cg.setFillColor(CRT.cardFace.cgColor)
            cg.fillPath()
            cg.addPath(chipPath(0))
            cg.setStrokeColor(tierColor(def.tier).cgColor)
            cg.setLineWidth(3)
            cg.strokePath()
            drawIcon(cg, def, at: CGRect(x: 0, y: -4, width: size, height: size),
                     color: CRT.ink, size: size * 0.4)
        }
    }

    // MARK: - The objects

    /// A sticker: the web's pixel die-cut chip (the `sticker` matrix) with
    /// the sticker's own 16×16 face contain-fit in the centre, and its
    /// suit-restriction badges riding the bottom rim. Cursed stickers are
    /// the `stickerCursed`/`stickerCursed2` corruption art with no face.
    public static func sticker(_ def: ItemDef, size: CGFloat = 56) -> UIImage {
        baked("stk-\(def.id)-\(Int(size))") {
            let k = max(4, Int((size / 16).rounded(.up)))
            let cell = CGFloat(k)
            let side = 16 * k
            // The chip art: cursed = the corruption matrix (per-id, like the
            // web's dcs-c-leech2), everything else the standard chip.
            let chipKey = def.cursed ? (def.id == "leech2" ? "stickerCursed2" : "stickerCursed") : "sticker"
            guard let chip = classArt[chipKey] else { return legacyStickerChip(def, size: size) }
            // The face: cursed chips carry no inner icon (the corruption IS
            // the face); a non-cursed sticker without a matrix keeps the
            // legacy octagon (empty set by the web's fail-loud contract).
            let face = def.cursed ? nil : stickerFaces[def.id]
            if !def.cursed && face == nil { return legacyStickerChip(def, size: size) }
            // Suit-restriction badges (the web's .dcs-suits): 8×8 chips
            // straddling the bottom rim, 1px apart.
            let suits = (def.suits ?? []).compactMap { suitBadges[$0] }
            let badgeScale = max(1, Int((Double(k) * 0.68).rounded()))
            let badgeSide = 8 * badgeScale
            let badgeGap = max(1, k / 2)
            let badgesW = suits.isEmpty ? 0 : suits.count * badgeSide + (suits.count - 1) * badgeGap
            let hang = suits.isEmpty ? 0 : badgeSide / 2
            let canvasW = max(side, badgesW), canvasH = side + hang
            return PixelTexture.image(size: CGSize(width: canvasW, height: canvasH)) { cg in
                let chipOx = CGFloat(canvasW - side) / 2
                drawMatrix(cg, chip, ox: chipOx, oy: 0, cell: cell)
                if let face {
                    // The web's .dcs-ic: a centred 58% box, contain-fit.
                    let fk = max(1, Int((Double(k) * 0.58).rounded()))
                    let fs = 16 * fk
                    drawMatrix(cg, face, ox: CGFloat(canvasW - fs) / 2,
                               oy: CGFloat(side - fs) / 2, cell: CGFloat(fk))
                }
                var bx = CGFloat(canvasW - badgesW) / 2
                let by = CGFloat(side) - CGFloat(badgeSide) / 2
                for badge in suits {
                    drawMatrix(cg, badge, ox: bx, oy: by, cell: CGFloat(badgeScale))
                    bx += CGFloat(badgeSide + badgeGap)
                }
            }
        }
    }

    /// A pillar: the web's pixel pennant (gold rod, red swallowtail cloth),
    /// with the item's glyph inked gold over an ink halo on the emblem spot —
    /// the web's .pb-emblem at centre ≈46% of the square, 42% wide.
    public static func pillar(_ def: ItemDef, width: CGFloat = 52, height: CGFloat = 68) -> UIImage {
        baked("pil-\(def.id)-\(Int(width))") {
            let k = max(4, Int((min(width, height) / 16).rounded(.up)))
            let side = 16 * k
            return PixelTexture.image(size: CGSize(width: side, height: side)) { cg in
                if let art = classArt["pillar"] {
                    drawMatrix(cg, art, ox: 0, oy: 0, cell: CGFloat(k))
                }
                let halo = (CGFloat(side) * 0.42).rounded()
                let hx = (CGFloat(side) - halo) / 2
                let hy = (CGFloat(side) * 0.46 - halo / 2).rounded()
                cg.setFillColor(CRT.ink.cgColor)
                cg.fill(CGRect(x: hx, y: hy, width: halo, height: halo))
                let inset = halo * 0.14
                drawIcon(cg, def, at: CGRect(x: hx + inset, y: hy + inset,
                                             width: halo - inset * 2, height: halo - inset * 2),
                         color: CRT.gold, size: halo * 0.6)
            }
        }
    }

    /// Base FAMILY colours (the web's BASE_FAMILY → --mtl-mid): the plaque
    /// face is fixed deep-felt; the SYMBOL carries the effect-type read.
    private static func baseSymbolColor(_ def: ItemDef) -> UIColor {
        switch def.id {
        case "clubDig", "stickerHarvest": return CRT.phosphor      // dig/bury
        case "kamikaze", "demolish", "heartDemolish": return CRT.suitRed  // destroy
        case "tax": return CRT.gold                                 // coins
        default: return CRT.cardFace                                // peek + util
        }
    }

    /// A base: the web's pixel plaque (ink frame, deep plate, cream corner
    /// screws, smoke etch, baked phosphor LED — trimmed to its content like
    /// the web's TRIM_ICONS) with the item's symbol in its family colour.
    public static func base(_ def: ItemDef, width: CGFloat = 58, height: CGFloat = 40) -> UIImage {
        baked("bas-\(def.id)-\(Int(width))") {
            let rows = trimmed(classArt["base"] ?? [])
            guard !rows.isEmpty else {
                return PixelTexture.image(size: CGSize(width: width, height: height)) { _ in }
            }
            let cols = rows[0].count
            let k = max(4, Int(min(width / CGFloat(cols), height / CGFloat(rows.count)).rounded(.up)))
            let w = cols * k, h = rows.count * k
            return PixelTexture.image(size: CGSize(width: w, height: h)) { cg in
                drawMatrix(cg, rows, ox: 0, oy: 0, cell: CGFloat(k))
                // The web's .base-sym: a bold symbol filling most of the
                // plate's height, centred, in the family accent.
                let sh = CGFloat(h) * 0.55
                drawIcon(cg, def, at: CGRect(x: 0, y: (CGFloat(h) - sh) / 2,
                                             width: CGFloat(w), height: sh),
                         color: baseSymbolColor(def), size: sh * 0.8)
            }
        }
    }

    /// A pack: the web's sealed pixel foil — `packSticker` for sticker
    /// packs, `packLarge` (brass star) when the registry's `keep` ≥ 2, else
    /// `packCard` — trimmed like the web, name plate under the art.
    public static func pack(_ def: ItemDef, deckId: String, width: CGFloat = 46, height: CGFloat = 60) -> UIImage {
        baked("pak-\(def.id)-\(Int(width))x\(Int(height))") {
            let key = def.int("keep", 1) >= 2 ? "packLarge"
                : (def.kind == "sticker" ? "packSticker" : "packCard")
            let rows = trimmed(classArt[key] ?? [])
            let name = def.label.uppercased() as NSString
            let f = CRT.Font.of(12)
            let nameSize = name.size(withAttributes: [.font: f])
            let nameH = ceil(nameSize.height) + 3
            let cols = rows[0].count
            let k = max(3, Int(min(width / CGFloat(cols), (height - nameH) / CGFloat(rows.count)).rounded(.up)))
            let artW = CGFloat(cols * k), artH = CGFloat(rows.count * k)
            let canvasW = max(CGFloat(ceil(nameSize.width) + 4), artW)
            return PixelTexture.image(size: CGSize(width: canvasW, height: artH + nameH)) { cg in
                drawMatrix(cg, rows, ox: (canvasW - artW) / 2, oy: 0, cell: CGFloat(k))
                UIGraphicsPushContext(cg)
                name.draw(at: CGPoint(x: (canvasW - nameSize.width) / 2, y: artH + 2),
                          withAttributes: [.font: f, .foregroundColor: CRT.cardFace])
                UIGraphicsPopContext()
            }
        }
    }

    /// A Same-Power: the web's class mark (the `samePower` phosphor diamond
    /// with the ink "=") over the power's name plate.
    public static func samePower(_ def: ItemDef, width: CGFloat = 56, height: CGFloat = 58) -> UIImage {
        baked("sp-\(def.id)-\(Int(width))x\(Int(height))") {
            let name = String(def.label.prefix(10)) as NSString
            let f = CRT.Font.of(13)
            let nameSize = name.size(withAttributes: [.font: f])
            let nameH = ceil(nameSize.height) + 2
            let k = max(4, Int(((height - nameH) / 16).rounded(.up)))
            let mark = CGFloat(16 * k)
            let canvasW = max(mark, ceil(nameSize.width) + 4)
            return PixelTexture.image(size: CGSize(width: canvasW, height: mark + nameH)) { cg in
                if let art = classArt["samePower"] {
                    drawMatrix(cg, art, ox: (canvasW - mark) / 2, oy: 0, cell: CGFloat(k))
                }
                UIGraphicsPushContext(cg)
                name.draw(at: CGPoint(x: (canvasW - nameSize.width) / 2, y: mark + 1),
                          withAttributes: [.font: f, .foregroundColor: CRT.cardFace])
                UIGraphicsPopContext()
            }
        }
    }

    /// The Removal slot object: the web's torn-card pixel art, trimmed.
    public static func removal(width: CGFloat = 44, height: CGFloat = 58) -> UIImage {
        baked("removal-\(Int(width))x\(Int(height))") {
            let rows = trimmed(classArt["removal"] ?? [])
            let cols = rows[0].count
            let k = max(3, Int(min(width / CGFloat(cols), height / CGFloat(rows.count)).rounded(.up)))
            return matrixImage(rows, scale: k)
        }
    }

    /// The shelf's removal object: the torn card with the web's "REMOVAL"
    /// caption hanging under the art.
    public static func removalWithLabel() -> UIImage {
        baked("removal-labelled") {
            let art = removal(width: 52, height: 66)
            let label = NSAttributedString(
                string: "REMOVAL",
                attributes: [.font: CRT.Font.of(13),
                             .foregroundColor: CRT.cardFace.withAlphaComponent(0.6)])
            let ls = label.size()
            let w = max(art.size.width, ceil(ls.width) + 4)
            return PixelTexture.image(size: CGSize(width: w, height: art.size.height + 18)) { cg in
                UIGraphicsPushContext(cg)
                art.draw(at: CGPoint(x: (w - art.size.width) / 2, y: 0))
                label.draw(at: CGPoint(x: (w - ls.width) / 2, y: art.size.height + 2))
                UIGraphicsPopContext()
            }
        }
    }

    /// Shelf art for any store slot kind.
    public static func forSlot(kind: String, id: String, card: CardSpec?, deckId: String) -> UIImage {
        let data = GameData.shared
        switch kind {
        case "card":
            if let card { return CardArt.image(CardArt.Face(card), scale: .half) }
            return removal()
        case "removal": return removalWithLabel()
        case "pillar": if let d = data.pillarTypes.get(id) { return pillar(d) }
        case "base": if let d = data.baseTypes.get(id) { return base(d) }
        case "pack": if let d = data.packTypes.get(id) { return pack(d, deckId: deckId) }
        case "samepower": if let d = data.samePowerTypes.get(id) { return samePower(d) }
        default: if let d = data.stickerTypes.get(id) { return sticker(d) }
        }
        return removal()
    }
}
