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
///                restriction hangs BELOW the chip as a small italic suit
///                caption on a 16×20 canvas (the chip keeps its silhouette).
///   pillar     = the `pillar` pennant matrix + the item's own glyph
///                (pillarGlyphs) inked gold over an ink halo on the emblem
///                spot (web .pb-emblem).
///   base       = the `base` plaque matrix (trimmed like the web) + the
///                item's own symbol (baseGlyphs) in its FAMILY colour (dig
///                phosphor · destroy red · coins gold · peek/util cream).
///   samePower  = the `samePower` phosphor-diamond class mark + the power's
///                own ink mark (samePowerMarks) in place of the generic "=",
///                over the name.
///   pack       = the `packCard`/`packSticker` foil matrices (large = registry
///                `keep` ≥ 2, the web rule: `packLarge` brass star for cards,
///                `packLargeSticker` brass chip for stickers) + the name.
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
        "packLargeSticker": [
            "................",
            "..KKKKKKKKKKKK..",
            "..KCKCKCKCKCKK..",
            "..KKKKKKKKKKKK..",
            "..KbbbbbbbbbbK..",
            "..KbbbKKKKbbbK..",
            "..KbbKCCCCKbbK..",
            "..KbKCRRRCKbbK..",
            "..KbKCRRRCKbbK..",
            "..KbbKCCCCKbbK..",
            "..KbbbKKKKbbbK..",
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
            "................",
            "..KKKKKKKKKKKK..",
            "..KCCCCCCCCCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCKKKKCCCK..",
            "..KCCKKKKKKCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCCCCCCCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCKKKKCCCK..",
            "..KCCKKKKKKCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCCCCCCCCK..",
            "..KKKKKKKKKKKK..",
            "................",
            "................"],
        "rankDown2": [
            "................",
            "..KKKKKKKKKKKK..",
            "..KCCCCCCCCCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCKKKKKKCCK..",
            "..KCCCKKKKCCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCCCCCCCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCKKKKKKCCK..",
            "..KCCCKKKKCCCK..",
            "..KCCCCKKCCCCK..",
            "..KCCCCCCCCCCK..",
            "..KKKKKKKKKKKK..",
            "................",
            "................"],
        "randomFixedValue": [
            "................",
            "................",
            "..KKKKKKKKKKKK..",
            "..KKKKKKKKKKKK..",
            "..KKCCKKKKCCKK..",
            "..KKCCKKKKCCKK..",
            "..KKKKKKKKKKKK..",
            "..KKKKKCCKKKKK..",
            "..KKKKKCCKKKKK..",
            "..KKKKKKKKKKKK..",
            "..KKCCKKKKCCKK..",
            "..KKCCKKKKCCKK..",
            "..KKKKKKKKKKKK..",
            "..KKKKKKKKKKKK..",
            "................",
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
            "..KCCCCCCCCCCK..",
            "..KC.K.CR.RCCK..",
            "..KCKKKCRRRCCK..",
            "..KCKKKC.R.CCK..",
            "..KCCCCCCCCCCK..",
            "..KC.R.C.K.CCK..",
            "..KCRRRCKKKCCK..",
            "..KC.R.C.K.CCK..",
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
            "....KGGGGGGK....",
            "....KGGGGGGK....",
            "...KKKKKKKKKK...",
            "..KGGGGGGGGGGK..",
            "..KGGGGGGGGGGK..",
            ".KKKKKKKKKKKKKK.",
            "KGGGGGGGGGGGGGGK",
            "KGGGGGGGGGGGGGGK",
            ".KKKKKKKKKKKKKK.",
            "................",
            "................",
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
            "..KKK...........",
            ".KGGGK..........",
            ".KGGGK..........",
            ".KGGGK...KKK....",
            "..KKK...KGGGK...",
            "........KGGGK...",
            "........KGGGK...",
            ".........KKK....",
            "...KKK..........",
            "..KGGGK.........",
            "..KGGGK.........",
            "..KGGGK.........",
            "...KKK..........",
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
            "....KKKKKKK.....",
            "...KK.....KK....",
            "...KK.....KK....",
            "....KKKKKKK.....",
            "..KKKKKKKKKKK...",
            ".KKKKKKKKKKKKK..",
            ".KKCKKKKKKKKKK..",
            ".KKCKKKKKKKKKK..",
            ".KKKKKKKKKKKKK..",
            ".KKKKKKKKKKKKK..",
            ".KKKKKKKKKKKKK..",
            "..KKKKKKKKKKK...",
            "...KKKKKKKKK....",
            "................",
            "................"],
        "massive": [
            "................",
            "................",
            "...KKKKKKKKKK...",
            "..KKKKKKKKKKKK..",
            "..KKKKKKKKKKKK..",
            ".KKKKKKKKKKKKKK.",
            ".KKKKKKKKKKKKKK.",
            "..KKKKKKKKKKKK..",
            "..KKKKKKKKKKKK..",
            "...KKKKKKKKKK...",
            "....KKKKKKKK....",
            "................",
            "................",
            "................",
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

    // MARK: - SUIT CAPTION (the restriction mark under the chip)

    /// 5×5 suit marks for the restriction caption BELOW the chip (Task: the
    /// old 8×8 badges rode the bottom rim and deformed the chip outline).
    /// Drawn upright here; the composer leans each row for the italic read.
    /// ♠/♣ cream, ♥/♦ red over a small felt-deep plate, so the caption reads
    /// on dark felt AND on cream card faces while staying quieter than the
    /// chip above it.
    private static let suitCaptionMarks: [String: [String]] = [
        "♠": ["..C..", ".CCC.", "CCCCC", ".CCC.", ".C.C."],
        "♥": [".R.R.", "RRRRR", "RRRRR", ".RRR.", "..R.."],
        "♦": ["..R..", ".RRR.", "RRRRR", ".RRR.", "..R.."],
        "♣": [".C.C.", "CCCCC", ".CCC.", "..C..", "..C.."],
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

    // MARK: - PER-ID GLYPHS (pillar emblems + base symbols)

    /// 12×12 glyphs keyed by item id — every pillar and base gets its OWN
    /// emblem (the web's ELEM_GLYPH/BASE_SYM contract: the generic fallbacks
    /// below are for items with no authored art, never the norm). "X" paints
    /// in the caller's accent colour (gold on the pillar's ink halo, the
    /// family colour on the base's felt plate); the palette letters paint
    /// fixed colours for suit/effect accents.
    private static let pillarGlyphs: [String: [String]] = [
        // Heart Bonus: ♥ lands → +1 coin (heart + coin drop).
        "heartBounty": [
            "............",
            "..RR..RR....",
            ".RRRR.RRRR..",
            ".RRRRRRRR...",
            ".RRRRRRRR...",
            "..RRRRRR....",
            "...RRRR..X..",
            "....RR..XXX.",
            "........XXX.",
            ".........X..",
            "............",
            "............"],
        // Column Tie-Safe: every pile survives a tie (shield + "=").
        "columnTieSafe": [
            "..XXXXXXXX..",
            ".XXXXXXXXXX.",
            ".XX......XX.",
            ".XX.XXXX.XX.",
            ".XX......XX.",
            ".XX.XXXX.XX.",
            ".XX......XX.",
            "..XX....XX..",
            "...XX..XX...",
            "....XXXX....",
            ".....XX.....",
            "............"],
        // Guardian: all piles survive → +7 (crenellated tower).
        "columnGuardian": [
            ".XX..XX..XX.",
            ".XX..XX..XX.",
            ".XXXXXXXXXX.",
            "..XXXXXXXX..",
            "..XXXXXXXX..",
            "..XXX..XXX..",
            "..XXX..XXX..",
            "..XXX..XXX..",
            "..XXX..XXX..",
            "..XXXXXXXX..",
            "............",
            "............"],
        // 8 Bury: sticker-free ♣ → bury 1 (club + arrow into ground).
        "clubTribute": [
            "............",
            "....XX......",
            "...XXXX.....",
            "..XXXXXX....",
            "...X..X.....",
            "....XX......",
            "....XX......",
            "...XXXX.....",
            "....XX......",
            "XXXXXXXXXXXX",
            "............",
            "............"],
        // All Hearts: every pile ♥-top → +8 (a big heart over two small).
        "allHeartsCoin": [
            "............",
            "..RRR.RRR...",
            "..RRRRRRR...",
            "...RRRRR....",
            "....RRR.....",
            "............",
            ".R.R....R.R.",
            ".RRR....RRR.",
            "..R......R..",
            "............",
            "............",
            "............"],
        // Envy: +4 per ♥-topped pile (two hearts + coin).
        "envy": [
            "............",
            ".R..RR..R...",
            ".RRRRRRRR...",
            ".RRRRRRRR...",
            "..RR..RR.XX.",
            "...R...RXXXX",
            "........XX..",
            "............",
            "............",
            "............",
            "............",
            "............"],
        // Streak Size: in-column streak → +1 pile size (rising bars).
        "streakBank": [
            "............",
            ".........XX.",
            ".........XX.",
            ".....XX..XX.",
            ".....XX..XX.",
            "..XX.XX..XX.",
            "..XX.XX..XX.",
            "..XX.XX..XX.",
            "..XX.XX..XX.",
            "XXXXXXXXXXXX",
            "............",
            "............"],
        // Streak Bury: streak → bury per guess (bars + arrow into ground).
        "streakTribute": [
            "............",
            ".........XX.",
            ".....XX..XX.",
            "..XX.XX..XX.",
            "..XX.XX..XX.",
            "..XX.XX..XX.",
            "............",
            "....XX......",
            "...XXXX.....",
            "....XX......",
            "XXXXXXXXXXXX",
            "............"],
        // Second Wind: first death saved, buried return (return arrow).
        "secondWind": [
            "............",
            ".....XX.....",
            "....XXXX....",
            "...XX.XX....",
            "..XX..XX....",
            "..X...XX....",
            "..X...XX....",
            "..X...XX....",
            "..XXXXX.....",
            "............",
            "............",
            "............"],
        // Greedy: all survive + lone pillar → +20 (star in a coin).
        "greedy": [
            "............",
            "....XXXX....",
            "..XX....XX..",
            ".X...XX...X.",
            ".X...XX...X.",
            "X..XXXXXX..X",
            "X...XXXX...X",
            ".X..X..X..X.",
            "..XX....XX..",
            "....XXXX....",
            "............",
            "............"],
        // Fibonacci: A/2/3/5/8 → +1 (golden spiral).
        "fibonacci": [
            ".XXXXXXXXXX.",
            ".X........X.",
            ".X.XXXXXX.X.",
            ".X.X....X.X.",
            ".X.X.XX.X.X.",
            ".X.X..X.X.X.",
            ".X.X..XXX.X.",
            ".X.X......X.",
            ".X.XXXXXXXX.",
            ".X..........",
            "............",
            "............"],
        // Highest Heart: coins = highest ♥ top (heart + up arrow).
        "highestEven": [
            "..RR..RR....",
            ".RRRRRRRR...",
            ".RRRRRRRR...",
            "..RRRRRR....",
            "...RRRR.....",
            "....RR......",
            "....XX......",
            "...XXXX.....",
            "..XXXXXX....",
            "....XX......",
            "....XX......",
            "............"],
        // Dense Bury: ♣ with 2+ stickers → bury (club + stickers + ground).
        "denseBury": [
            "............",
            "....XX......",
            "...XXXX.....",
            "..XXXXXX....",
            "...X..X.....",
            "....XX......",
            "............",
            "..XX...XX...",
            "..XX...XX...",
            "............",
            "XXXXXXXXXXXX",
            "............"],
        // Revive: pile hits 10 → revive a dead pile (circular arrow).
        "revive": [
            "...XXXX.....",
            ".XXX....X...",
            "XX......X...",
            "X.......X...",
            "X......X....",
            ".X....X.....",
            "..X..X......",
            "...XXXX.....",
            "............",
            "............",
            "............",
            "............"],
        // Insurance: lone surviving pile here → +20 (life ring).
        "insurance": [
            "....XXXX....",
            "..XXXXXXXX..",
            "..XX....XX..",
            ".XX..XX..XX.",
            ".X...XX...X.",
            ".X...XX...X.",
            ".XX..XX..XX.",
            "..XX....XX..",
            "..XXXXXXXX..",
            "....XXXX....",
            "............",
            "............"],
        // Ditto: mirrors the center pillar (ditto marks).
        "ditto": [
            "............",
            "...X...X....",
            "...X...X....",
            "...X...X....",
            "....X...X...",
            "....X...X...",
            ".....X...X..",
            ".....X...X..",
            "............",
            "............",
            "............",
            "............"],
        // Massive Diamond: ♦ counts +2 pile size (tag with ♦ core).
        "stickerCount": [
            ".....XX.....",
            "....XXXX....",
            "...XXXXXX...",
            "..XXXXXXXX..",
            "..X.RRRR.X..",
            "..X.RRRR.X..",
            "..XXXXXXXX..",
            "...XXXXXX...",
            "....XXXX....",
            ".....XX.....",
            "............",
            "............"],
        // Prime: prime rank → +1 (hash mark).
        "prime": [
            "...X...X....",
            "...X...X....",
            ".XXXXXXXXX..",
            "..X...X.....",
            "..X...X.....",
            "XXXXXXXXXX..",
            ".X...X......",
            ".X...X......",
            "............",
            "............",
            "............",
            "............"],
        // Queen's Eye: royal ♠ → peek (crown + eye).
        "queensEye": [
            "..X.X.X.X...",
            "..X.X.X.X...",
            "..XXXXXXX...",
            "...XXXXX....",
            "............",
            "....XXXX....",
            "..XX....XX..",
            "..X..PP..X..",
            "..XX....XX..",
            "....XXXX....",
            "............",
            "............"],
        // Shuffler: ♦ lands → shuffle others (crown).
        "royalCourt": [
            "............",
            "..X..X..X...",
            "..X..X..X...",
            "..XX.X.XX...",
            "..XXXXXXX...",
            "..XXXXXXX...",
            "..XXXXXXX...",
            "..XXXXXXX...",
            "............",
            "............",
            "............",
            "............"],
        // Excavator: +2 per buried card in the ♥ pile (pickaxe).
        "excavator": [
            "............",
            "..XXXXXXXX..",
            ".X...XX...X.",
            "X....XX....X",
            ".....XX.....",
            ".....XX.....",
            "....XX......",
            "....XX......",
            "...XX.......",
            "...XX.......",
            "............",
            "............"],
        // Gambler: 50/50 +10 (die showing five).
        "gambler": [
            "..XXXXXXXX..",
            ".XXXXXXXXXX.",
            ".X..XXXX..X.",
            ".X..XXXX..X.",
            ".XXXX..XXXX.",
            ".XXXX..XXXX.",
            ".X..XXXX..X.",
            ".X..XXXX..X.",
            ".XXXXXXXXXX.",
            "..XXXXXXXX..",
            "............",
            "............"],
        // Last Rites: pile dies → peek (lit candle).
        "lastRites": [
            ".....XX.....",
            "....X..X....",
            ".....XX.....",
            ".....XX.....",
            "....XXXX....",
            "....XXXX....",
            "....XXXX....",
            "....XXXX....",
            "....XXXX....",
            "..XXXXXXXX..",
            "............",
            "............"],
        // Static: ♠ lands → 50% peek (bolt in a ring).
        "static": [
            "...XXXXXX...",
            "..X......X..",
            ".X...PP...X.",
            ".X..PP....X.",
            "X...PPPP...X",
            "X....PP....X",
            ".X..PP....X.",
            ".X.PP.....X.",
            "..X......X..",
            "...XXXXXX...",
            "............",
            "............"],
        // Wild Aces: aces flex high/low (card between chevrons).
        "wildAces": [
            "....XX......",
            "...XXXX.....",
            "..XXXXXX....",
            "............",
            "...XXXXX....",
            "...X...X....",
            "...X...X....",
            "...XXXXX....",
            "............",
            "..XXXXXX....",
            "...XXXX.....",
            "....XX......"],
        // Diamond Anchor: ♦ pile excluded from score (anchor, ♦ head).
        "diamondAnchor": [
            "....RR......",
            "...RRRR.....",
            "....RR......",
            "....XX......",
            "....XX......",
            ".X..XXXX..X.",
            ".XX..XX..XX.",
            "..X..XX..X..",
            "..XX.XX.XX..",
            "...XXXXX....",
            "............",
            "............"],
        // Diamond Distribution: ♦ → equalize piles (♦ + equal bars).
        "diamondDistribution": [
            "....RR......",
            "...RRRR.....",
            "..RRRRRR....",
            "...RRRR.....",
            "....RR......",
            "............",
            ".XX..XX..XX.",
            ".XX..XX..XX.",
            ".XX..XX..XX.",
            "............",
            "............",
            "............"],
    ]

    /// The bases' own 12×12 symbols (same "X" = accent convention).
    private static let baseGlyphs: [String: [String]] = [
        // Kamikaze: kill a ♠ pile, peek 3 (explosion burst).
        "kamikaze": [
            ".....X......",
            "..X..X..X...",
            "...XXXXX....",
            "X.XXXXXXX.X.",
            "..XXXXXXX...",
            "X.XXXXXXX.X.",
            "...XXXXX....",
            "..X..X..X...",
            ".....X......",
            "............",
            "............",
            "............"],
        // Spade Peeker: peek X = ♠-topped piles (spade + eye).
        "spadePeek": [
            "....XX......",
            "...XXXX.....",
            "..XXXXXX....",
            "..XXXXXX....",
            "...XXXX.....",
            "....XX......",
            "...XXXX.....",
            "............",
            "...XXXXXX...",
            "..X..PP..X..",
            "...XXXXXX...",
            "............"],
        // Upheaval: shuffle every pile (crossing arrows).
        "shuffleColumn": [
            "..X......X..",
            "..XX....XX..",
            "..X.X..X.X..",
            "..X..XX..X..",
            "..X...X..X..",
            "..X..X.X.X..",
            "..X.X..X.X..",
            "..XX....XX..",
            "..X......X..",
            "............",
            "............",
            "............"],
        // Phoenix: revive a dead pile (flame).
        "revive": [
            ".....X......",
            "....XXX.....",
            "....XXXX....",
            "...XX.XX....",
            "...X...X....",
            "..XX...XX...",
            "..X.....X...",
            "..XX...XX...",
            "...XXXXX....",
            "....XXX.....",
            "............",
            "............"],
        // Wild Sticker: random sticker to a random top (chip + sparkles).
        "randomSticker": [
            "...XXXXXX...",
            "..X......X..",
            "..X..XX..X..",
            "..X.XXXX.X..",
            "..X..XX..X..",
            "..X......X..",
            "...XXXXXX...",
            "............",
            ".X.......X..",
            "....X..X....",
            "............",
            "............"],
        // Ballast: equalize all piles (beam + equal bars).
        "evenOut": [
            "............",
            "XXXXXXXXXXXX",
            ".....XX.....",
            ".....XX.....",
            ".XX..XX..XX.",
            ".XX..XX..XX.",
            ".XX..XX..XX.",
            ".XX..XX..XX.",
            "............",
            "............",
            "............",
            "............"],
        // Cast: set top ranks to the bottom rank (card + arrow + bar).
        "setValue": [
            "..XXXXX.....",
            "..X...X.....",
            "..X...X.....",
            "..XXXXX.....",
            "....XX......",
            "....XX......",
            "...XXXX.....",
            "....XX......",
            "............",
            "XXXXXXXXXXXX",
            "............",
            "............"],
        // Suit Setter: set top suits to the bottom suit (♦ + arrow + bar).
        "setSuit": [
            "....RR......",
            "...RRRR.....",
            "..RRRRRR....",
            "...RRRR.....",
            "....RR......",
            "....XX......",
            "...XXXX.....",
            "....XX......",
            "............",
            "XXXXXXXXXXXX",
            "............",
            "............"],
        // Sticker Harvest: bury per sticker, peel them (chip + ground).
        "stickerHarvest": [
            "...XXXXXX...",
            "..X......X..",
            "..X.XXXX.X..",
            "..X......X..",
            "...XXXXXX...",
            "....XX......",
            "...XXXX.....",
            "....XX......",
            "...XXXX.....",
            "............",
            "XXXXXXXXXXXX",
            "............"],
        // Reactor: recharge the other bases (chasing arrows).
        "refreshBases": [
            "....XXXXX...",
            "..XX....XX..",
            ".XXX....X...",
            "..X.....X...",
            "..X.....X...",
            "..X.....X...",
            "..X....XXX..",
            "..XX....XX..",
            "...XXXXX....",
            "............",
            "............",
            "............"],
        // Club Dig: bury under each ♣ pile (club + arrow + ground).
        "clubDig": [
            "....XX......",
            "...XXXX.....",
            "..XXXXXX....",
            "...X..X.....",
            "....XX......",
            "....XX......",
            "...XXXX.....",
            "....XX......",
            "............",
            "XXXXXXXXXXXX",
            "............",
            "............"],
        // Demolish: destroy a pillar, peek 2 (hammer).
        "demolish": [
            "..XXXXXX....",
            ".XXXXXXXX...",
            "..XXXXXX....",
            "....XX......",
            "....XX......",
            "....XX......",
            "....XX......",
            "....XX......",
            "............",
            "............",
            "............",
            "............"],
        // Heart Demolish: destroy ♥ piles, +7 each (broken heart).
        "heartDemolish": [
            "..RR..RR....",
            ".RRRR.RRRR..",
            ".RRRR..RRR..",
            ".RRRRR.RRR..",
            "..RRR..RRR..",
            "..RRRR.RR...",
            "...R..RRR...",
            "....RR.R....",
            ".....R......",
            "............",
            "............",
            "............"],
        // Heart Tax: +1 per ♥ card (heart + coin).
        "tax": [
            "..RR..RR....",
            ".RRRR.RRRR..",
            ".RRRRRRRR...",
            "..RRRRRR....",
            "...RRRR.....",
            "....RR..XX..",
            ".....R.X..X.",
            ".......X..X.",
            "........XX..",
            "............",
            "............",
            "............"],
        // Recharge Cell: bank a Same Charge (battery + charge bars).
        "rechargeSame": [
            "............",
            ".XXXXXXXXX..",
            ".X.PP.PP.XXX",
            ".X.PP.PP.XXX",
            ".X.PP.PP.XXX",
            ".XXXXXXXXX..",
            "............",
            "............",
            "............",
            "............",
            "............",
            "............"],
        // Power Surge: fire the Same-Power ("=" + bolt).
        "activateSame": [
            "..XXXX......",
            "..XXXX......",
            "............",
            "..XXXX......",
            "..XXXX......",
            "............",
            "......PPP...",
            ".....PP.....",
            "....PPP.....",
            "....PP......",
            "...PPP......",
            "............"],
    ]

    /// 8×8 marks composited onto the Same-Power diamond's centre (in ink over
    /// the cleared "="), so the six powers no longer share one identical mark.
    /// Pixels must stay inside matrix rows 5–10 / cols 4–11 of the diamond.
    private static let samePowerMarks: [String: [String]] = [
        "linkBury": [    // Burrow — bury under every alive pile
            "........",
            "...KK...",
            "...KK...",
            ".KKKKKK.",
            "..KKKK..",
            "........",
            "KKKKKKKK",
            "........"],
        "linkRevive": [  // Rekindle — revive the largest dead pile
            "........",
            "..K..K..",
            ".KK..KK.",
            "..KKKK..",
            "...KK...",
            "...KK...",
            "...KK...",
            "........"],
        "linkCoins": [   // Dividend — coin per alive pile
            "........",
            "..KKKK..",
            ".KK..KK.",
            ".K.KK.K.",
            ".K.KK.K.",
            ".KK..KK.",
            "..KKKK..",
            "........"],
        "linkShuffle": [ // Link Shuffler — shuffle every alive pile
            "........",
            ".K....K.",
            ".KK..KK.",
            "..K.KK..",
            "..KK.K..",
            ".KK..KK.",
            ".K....K.",
            "........"],
        "samePeek": [    // Same Peeker — peek the next card
            "........",
            "..KKKK..",
            ".KK..KK.",
            ".K.KK.K.",
            ".K.KK.K.",
            ".KK..KK.",
            "..KKKK..",
            "........"],
        "linkHeavy": [   // Same Heavy — +size to every pile
            "........",
            "...KK...",
            "...KK...",
            "..KKKK..",
            ".KKKKKK.",
            ".KKKKKK.",
            "..KKKK..",
            "........"],
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
                                 color: UIColor, size: CGFloat,
                                 perId: [String: [String]]? = nil) {
        // Per-id authored glyphs beat every fallback. "X" = the accent colour,
        // palette letters paint fixed (suit reds, phosphor charge, ink).
        if let rows = perId?[def.id] {
            let cell = min(rect.width, rect.height) / 12
            let ox = rect.midX - cell * 6, oy = rect.midY - cell * 6
            for (yy, row) in rows.enumerated() {
                for (xx, ch) in row.enumerated() {
                    let c: UIColor?
                    switch ch {
                    case "X": c = color
                    case "K": c = CRT.ink
                    case "R": c = CRT.suitRed
                    case "G": c = CRT.gold
                    case "P": c = CRT.phosphor
                    case "C": c = CRT.cardFace
                    default: c = nil
                    }
                    guard let c else { continue }
                    cg.setFillColor(c.cgColor)
                    cg.fill(CGRect(x: ox + CGFloat(xx) * cell, y: oy + CGFloat(yy) * cell,
                                   width: cell + 0.4, height: cell + 0.4))
                }
            }
            return
        }
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
    /// the sticker's own 16×16 face contain-fit in the centre. A `suits`
    /// restriction rides BELOW the chip as a small italic suit caption
    /// (transparent-ground, so the chip keeps its clean silhouette); no
    /// restriction → no caption. Cursed stickers are the
    /// `stickerCursed`/`stickerCursed2` corruption art with no face.
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
            // Suit caption: 5×5 marks leaning italic, on rows 15–19 of a
            // 16×20 matrix canvas — the strip is 25% of the total height, so
            // aspect-fit callers keep the chip dominant with no layout change.
            let suits = (def.suits ?? []).compactMap { suitCaptionMarks[$0] }
            let captionH = suits.isEmpty ? 0 : 5 * k
            return PixelTexture.image(size: CGSize(width: side, height: side + captionH)) { cg in
                drawMatrix(cg, chip, ox: 0, oy: 0, cell: cell)
                if let face {
                    // The web's .dcs-ic: a centred 58% box, contain-fit.
                    let fk = max(1, Int((Double(k) * 0.58).rounded()))
                    let fs = 16 * fk
                    drawMatrix(cg, face, ox: CGFloat(side - fs) / 2,
                               oy: CGFloat(side - fs) / 2, cell: CGFloat(fk))
                }
                if !suits.isEmpty {
                    let advance = 7 * k   // 5px glyph + 2px air
                    let totalW = suits.count * advance - 2 * k
                    var gx = CGFloat(side - totalW) / 2
                    let gy = CGFloat(15 * k)
                    // The quiet plate the caption sits on: dark on dark it
                    // all but vanishes (the marks carry it); on a cream card
                    // face it gives the cream ♠/♣ their ground.
                    cg.setFillColor(CRT.feltDeep.cgColor)
                    cg.fill(CGRect(x: CGFloat(side - totalW) / 2 - cell,
                                   y: CGFloat(14 * k),
                                   width: CGFloat(totalW + 2 * k),
                                   height: CGFloat(6 * k)))
                    for mark in suits {
                        for (y, row) in mark.enumerated() {
                            // The italic lean: top rows shift right, bottom left.
                            let lean = (2 - y) / 2
                            for (x, ch) in row.enumerated() where ch != "." {
                                guard let c = pxColor(ch, x: x, y: y) else { continue }
                                cg.setFillColor(c.cgColor)
                                cg.fill(CGRect(x: gx + CGFloat(x + lean) * cell,
                                               y: gy + CGFloat(y) * cell,
                                               width: cell, height: cell))
                            }
                        }
                        gx += CGFloat(advance)
                    }
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
                         color: CRT.gold, size: halo * 0.6, perId: pillarGlyphs)
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
                         color: baseSymbolColor(def), size: sh * 0.8, perId: baseGlyphs)
            }
        }
    }

    /// A pack: the web's sealed pixel foil — `packSticker` for sticker
    /// packs, the brass large foils (`packLarge` star / `packLargeSticker`
    /// chip) when the registry's `keep` ≥ 2, else `packCard` — trimmed like
    /// the web, name plate under the art.
    public static func pack(_ def: ItemDef, deckId: String, width: CGFloat = 46, height: CGFloat = 60) -> UIImage {
        baked("pak-\(def.id)-\(Int(width))x\(Int(height))") {
            let key = def.int("keep", 1) >= 2
                ? (def.kind == "sticker" ? "packLargeSticker" : "packLarge")
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

    /// A Same-Power: the web's class mark (the `samePower` phosphor diamond)
    /// with the power's own ink mark (samePowerMarks) replacing the generic
    /// "=" at its centre, over the power's name plate.
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
                let cell = CGFloat(k)
                let artX = (canvasW - mark) / 2
                if let art = classArt["samePower"] {
                    drawMatrix(cg, art, ox: artX, oy: 0, cell: cell)
                }
                // The power's own mark replaces the generic "=" at the
                // diamond's centre: clear the "=" back to phosphor, then ink
                // the 8×8 mark (pixels stay inside rows 5–10, cols 4–11).
                if let rows = samePowerMarks[def.id] {
                    cg.setFillColor(CRT.phosphor.cgColor)
                    cg.fill(CGRect(x: artX + 4 * cell, y: 6 * cell,
                                   width: 8 * cell, height: 4 * cell))
                    drawMatrix(cg, rows, ox: artX + 4 * cell, oy: 4 * cell, cell: cell)
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
