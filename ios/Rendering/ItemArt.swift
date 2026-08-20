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
///                corruption matrices with NO inner face. ALWAYS a square
///                16×16 composition at full size — a `suits` restriction is
///                NEVER baked in; it rides as a SEPARATE image
///                (`suitCaption`/`suitCaptionView`) the caller parks ABOVE
///                the chip, so suited chips render the same size as unsuited.
///   pillar     = the `pillar` pennant matrix + the item's own glyph
///                (pillarGlyphs) inked gold over an ink halo on the emblem
///                spot (web .pb-emblem).
///   base       = the `base` plaque matrix (trimmed like the web) + the
///                item's own symbol (baseGlyphs) in its FAMILY colour (dig
///                phosphor · destroy red · coins gold · peek/util cream).
///   samePower  = the `samePower` phosphor-diamond class mark + the power's
///                own ink mark (samePowerMarks) in place of the generic "=".
///                No baked name — call sites render the label.
///   pack       = the `packCard`/`packSticker` foil matrices (large = registry
///                `keep` ≥ 2, the web rule: `packLarge` brass star for cards,
///                `packLargeSticker` brass chip for stickers). No baked name —
///                call sites render the label (store tile `.pf-name` etc.).
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

    /// Widen a symmetric frame matrix to `targetCols` by repeating its CENTRE
    /// column. Both plaque plates are frames with a plain repeating interior,
    /// so this stretches the plate without touching its border, its corner
    /// details or its symmetry — the plaque reaches the card's width at a whole
    /// pixel scale, instead of being letterboxed narrower than the pile it
    /// belongs to. (Scaling to fit instead would put the plate on fractional
    /// pixels, which §10 forbids; growing the cell size would need a taller
    /// band, and `pickScale` pays for taller bands with smaller cards.)
    private static func widened(_ rows: [String], to targetCols: Int) -> [String] {
        guard let first = rows.first else { return rows }
        let cols = first.count
        let extra = targetCols - cols
        guard extra > 0, cols > 0 else { return rows }
        let mid = cols / 2
        return rows.map { row -> String in
            guard row.count == cols else { return row }
            let chars = Array(row)
            let fill = String(repeating: String(chars[mid]), count: extra)
            return String(chars[0..<mid]) + fill + String(chars[mid...])
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

    /// THE OLD JOKER — the DEAL's Joker card, aged. 14×20.
    ///
    /// He must read as the same card the player already knows from the board,
    /// only older: CardNode draws a Joker as a deep-felt face inside a GOLD
    /// border with a gold ★ and a gold JOKER caption, so this is that card —
    /// deep-felt face (D), gold frame (G), a gold ★ filling the middle, and a
    /// gold caption bar standing in for the word at a size too small to letter.
    ///
    /// The AGE is damage to that card, never a different design: the gold
    /// frame is broken in three places where it has rubbed through to grime
    /// (F = felt-mid), the top-left and bottom-right corners are scuffed off
    /// entirely, and a brass-dither crease (b) runs under the star where the
    /// card has been folded and reopened. Palette-pure: nothing outside the
    /// locked eight.
    static let oldJokerArt: [String] = [
        "...FGGGGGGGF..",
        "..GDDDDDDDDDG.",
        ".FDDDDDDDDDDDG",
        ".GDDDDDGDDDDDF",
        ".GDDDDGGGDDDDG",
        ".FDDGGGGGGGDDG",
        ".GDDDGGGGGDDDG",
        ".GDDDDGGGDDDDG",
        ".GDDDGGGGGDDDG",
        ".GDDGGGDGGGDDF",
        ".GDDGGDDDGGDDG",
        ".GDDDDDDDDDDDG",
        ".FDbbDDDDDbbDG",
        ".GDDDbbDbbDDDG",
        ".GDDDDDbbDDDDG",
        ".GDDDDDDDDDDDG",
        ".GDDGGGGGGGDDG",
        ".FDDDDDDDDDDDF",
        "..GGGGGGGGGF..",
        "...FFFFFFF....",
    ]

    /// The Old Joker card at `k`× the pixel grid. Nearest-filtered and baked
    /// once per size — no per-frame work.
    public static func oldJoker(scale k: Int = 6) -> UIImage {
        baked("oldjoker-\(k)") { characterCard(oldJokerArt, scale: k) }
    }

    /// THE BEHEADED QUEEN — a MIRRORED court card with the top half RIPPED
    /// OFF. 14×20: real queens are two half-figures meeting at the waist, so
    /// what survives the tear is the LOWER twin, upside down — her red gown
    /// meeting the torn mirror line, then her inverted face (mouth above the
    /// closed eyes — that's how you know she hangs head-down), gold hair
    /// framing it, and her crown pointing DOWN at the card's foot. The upper
    /// twin — the right-way-up queen — is exactly what was torn away.
    static let beheadedQueenArt: [String] = [
        "..KK....K..K..",
        ".KCCK.KKCKKCK.",
        "KCCCCKCCCCCCCK",
        "KCRRRRRRRRRRCK",
        "KCRRRGGGGRRRCK",
        "KCCRRRGGRRRCCK",
        "KCCRRRGGRRRCCK",
        "KCCCRRRRRRCCCK",
        "KCCCCRRRRCCCCK",
        "KCCCCCKKCCCCCK",
        "KCCCKKKKKKCCCK",
        "KCGKCCCCCCKGCK",
        "KCGKCCRRCCKGCK",
        "KCGKCCCCCCKGCK",
        "KCGKCKCCKCKGCK",
        "KCCGKKKKKKGCCK",
        "KCCGGGGGGGGCCK",
        "KCRGGCGGCGGCCK",
        "KCCCCCCCCCCCCK",
        ".KKKKKKKKKKKK.",
    ]

    /// JUST A TWO — the deck's lowest card, and it knows it. 14×20: a plain
    /// two of spades wearing the only face it has ever been given — V-brows,
    /// a flat grimace — with its bottom-right corner clipped off from years
    /// of mistreatment. Nothing torn, nothing gilded: it's just a two.
    static let justATwoArt: [String] = [
        ".KKKKKKKKKKKK.",
        "KCCCCCCCCCCCCK",
        "KCKKKCCCCCCCCK",
        "KCCCKCCCCCCCCK",
        "KCCKKCCCCCCCCK",
        "KCKCCCCCCCCCCK",
        "KCKKKKCCCCCCCK",
        "KCCCCCCCCCCCCK",
        "KCCCKCCCCKCCCK",
        "KCCCCKCCKCCCCK",
        "KCCCKKCCKKCCCK",
        "KCCCCCCCCCCCCK",
        "KCCCCKKKKCCCCK",
        "KCCCKCCCCKCCCK",
        "KCCCCCCCCCCCCK",
        "KCCCCCKKCCCCCK",
        "KCCCKKKKKKCCCK",
        "KCCCKKKKKKCKK.",
        "KCCCCCKKCCCK..",
        ".KKKKKKKKKKK..",
    ]

    /// The Beheaded Queen at `k`× the pixel grid, baked like the Old Joker.
    public static func beheadedQueen(scale k: Int = 6) -> UIImage {
        baked("beheadedqueen-\(k)") { characterCard(beheadedQueenArt, scale: k) }
    }

    /// Just a Two at `k`× the pixel grid, baked like the Old Joker.
    public static func justATwo(scale k: Int = 6) -> UIImage {
        baked("justatwo-\(k)") { characterCard(justATwoArt, scale: k) }
    }

    /// The shared character-card treatment: the matrix over its own drop
    /// shadow. The shadow follows the SILHOUETTE, not the bounding rect — a
    /// rect showed as a dark slab through the Beheaded Queen's torn-open top.
    private static func characterCard(_ rows: [String], scale k: Int) -> UIImage {
        let w = rows[0].count * k, h = rows.count * k
        return PixelTexture.image(size: CGSize(width: w + 3, height: h + 3)) { cg in
            cg.setFillColor(CRT.shadow.cgColor)
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() where ch != "." {
                    cg.fill(CGRect(x: CGFloat(x * k + 3), y: CGFloat(y * k + 3),
                                   width: CGFloat(k), height: CGFloat(k)))
                }
            }
            drawMatrix(cg, rows, ox: 0, oy: 0, cell: CGFloat(k))
        }
    }

    private static let classArt: [String: [String]] = [
        // A BLANK die-cut chip: cream face, ink rim, the shaded lower-right
        // curl. The red diamond that used to sit dead centre showed through
        // behind every sticker's own glyph as a red blob.
        "sticker": [
            "................",
            ".....KKKKKK.....",
            "...KKCCCCCCKK...",
            "..KCCCCCCCCCCK..",
            "..KCCCCCCCCCCK..",
            ".KCCCCCCCCCCCCK.",
            ".KCCCCCCCCCCCCK.",
            ".KCCCCCCCCCCCCK.",
            ".KCCCCCCCCCCCsK.",
            ".KCCCCCCCCCCssK.",
            "..KCCCCCCCCssK..",
            "..KCCCCCCCsssK..",
            "...KKCCCCssKK...",
            ".....KKKKKK.....",
            "................",
            "................"],
        // The CURSE PLATE (v6.57 — third pass, player directive: curses read
        // RED/BLACK/EVIL, never green): drawn UNDER every corruption matrix —
        // the chip's own silhouette dilated one pixel, a near-black (ink)
        // void with two suit-red DROPS bleeding off the bottom edge. The v6.55
        // phosphor ring still read GREEN at deal scale and the v6.52 red
        // square cost the round silhouette; this keeps the silhouette and
        // drops the phosphor entirely. Tokens only (K ink, R suit-red).
        "cursedPlate": [
            "................",
            ".....KKKKKK.....",
            "...KKKKKKKKKK...",
            "..KKKKKKKKKKKK..",
            ".KKKKKKKKKKKKKK.",
            ".KKKKKKKKKKKKKK.",
            "KKKKKKKKKKKKKKKK",
            "KKKKKKKKKKKKKKKK",
            "KKKKKKKKKKKKKKKK",
            "KKKKKKKKKKKKKKKK",
            ".KKKKKKKKKKKKKK.",
            ".KKKKKKKKKKKKKK.",
            "..KKKKKKKKKKKK..",
            "...KKKKKKKKKK...",
            ".....KKKKKK.....",
            "......R..R......"],
        // The CURSE RIM (v6.57): drawn OVER the corruption matrix — a flat
        // suit-red ring tracing the chip's own round outline, so EVERY cursed
        // chip carries an unmistakable red perimeter at any size. (The plate's
        // edge alone was mostly hidden behind the chip's own ink rim.)
        "cursedRim": [
            "................",
            ".....RRRRRR.....",
            "...RR......RR...",
            "..R..........R..",
            "..R..........R..",
            ".R............R.",
            ".R............R.",
            ".R............R.",
            ".R............R.",
            ".R............R.",
            "..R..........R..",
            "..R..........R..",
            "..R..........R..",
            "...RR......RR...",
            ".....RR.RRR.....",
            "................"],
        // cursed = the same chip corrupted (v6.57): a NEAR-BLACK face (cream
        // is for honest stickers), the motif in suit-red — or cream where the
        // motif was ink and would vanish — with the torn rim's smoke tatters
        // kept. No phosphor anywhere. The template for cursing ANY chip.
        "stickerCursed": [
            "................",
            ".....KKKKKK.....",
            "...KKKKKRKKKK...",
            "..KKKKKKKKKKKK..",
            "..KKKKKKKKKKKK..",
            ".KKKKKKRRKKRKKK.",
            ".KKKKKRRRRKKKKK.",
            "....KKKRRRRRRKKK",
            ".KKKKKRRRRKKKsK.",
            ".KKKRKKRRKKKssK.",
            "..KKKKKKKKKssK..",
            "..KKKKKKRKsssK..",
            "...KKKKKKssKK...",
            ".....KK.KKK.....",
            "................",
            "................"],
        // TRAPDOOR's corruption — the same torn chip family, but the middle
        // has simply GIVEN WAY: a cream-rimmed hole into felt-deep dark (the
        // rim was ink on cream; on the black face it turns cream or vanishes).
        "stickerCursedTrapdoor": [
            "................",
            ".....KKKKKK.....",
            "...KKKKKKKKKK...",
            "..KKKKKKKKKKKK..",
            "..KKKCCCCKKKKK..",
            ".KKKKCCDDCCKKKK.",
            ".KKKCDDDDDDKKKK.",
            "....CDDDDDCKKKK",
            ".KKKCDDDDDCKKsK.",
            ".KKKKCDDDDCKssK.",
            "..KKKKCCCCKKsK..",
            "..KKKKKKKKsssK..",
            "...KKKKKKssKK...",
            ".....KK.KKK.....",
            "................",
            "................"],
        // Leech SWARM's own corruption — same torn chip family, but a SCATTER
        // of small red leeches instead of Leech's single big one.
        "stickerCursed2": [
            "................",
            ".....KKKKKK.....",
            "...KKKKKRKKKK...",
            "..KKRRKKKKKKKK..",
            "..KKRRKKKRRKKK..",
            ".KKKKKKKKRRKKKK.",
            ".KKKRKKKKKKKKKK.",
            "....KKKKKKKKKKKK",
            ".KKKRRKKKKKKKsK.",
            ".KKKRRKKKKRKssK.",
            "..KKKKKRRKKKsK..",
            "..KKKRKRRKsssK..",
            "...KKKKKKssKK...",
            ".....KK.KKK.....",
            "................",
            "................"],
        // v6.48 CURSE FAMILY — every curse keeps the torn-chip silhouette
        // (red rim, BLACK face, ripped right edge into smoke) with its OWN
        // centre motif, so a cursed card reads "curse" at a glance and WHICH
        // curse on the second look. (v6.57: faces went black, phosphor
        // accents went red, ink motifs flipped to cream — the cream-faced
        // chips read as ordinary stickers at deal scale.)
        // SHRINK: the ghost of a chip inside the chip — cream outline, red
        // core — the thing is smaller than it was.
        "stickerCursedShrink": [
            "................",
            ".....KKKKKK.....",
            "...KKKKKKKKKK...",
            "..KKKKKKKKKKKK..",
            "..KKKCCCCCKKKK..",
            ".KKKKCKKKKCKKKK.",
            ".KKKKCKRRKCKKKK.",
            "....KKKRRKCKKKK",
            ".KKKKCKKKKCKKsK.",
            ".KKKKCCCCCCKssK.",
            "..KKKKKKKKKssK..",
            "..KKKKKKKKsssK..",
            "...KKKKKKssKK...",
            ".....KK.KKK.....",
            "................",
            "................"],
        // MUTE: the Same sign, struck through red (cream sign on the black).
        "stickerCursedMute": [
            "................",
            ".....KKKKKK.....",
            "...KKKKKKKKKK...",
            "..KKKKKKKKKRKK..",
            "..KKKKKKKKRRKK..",
            ".KKKKCCCCCRRKKK.",
            ".KKKKKKKRRKKKKK.",
            "....KKKRRKKKKKK",
            ".KKKKCCRRCCCKsK.",
            ".KKKKRRKKKKKssK.",
            "..KKRRKKKKKKsK..",
            "..KRRKKKKKsssK..",
            "...KKKKKKssKK...",
            ".....KK.KKK.....",
            "................",
            "................"],
        // SPOILER: the coin gone rotten — gold ring, red rot inside.
        "stickerCursedSpoiler": [
            "................",
            ".....KKKKKK.....",
            "...KKKKKKKKKK...",
            "..KKKKGGGGKKKK..",
            "..KKKGGGGGGKKK..",
            ".KKKGGRKKRGGKKK.",
            ".KKKGGKRRKGGKKK.",
            "....KGKRRKGKKKK",
            ".KKKGGRKKRGGKsK.",
            ".KKKGGGGGGGKssK.",
            "..KKKGGGGGKKsK..",
            "..KKKKKKKKsssK..",
            "...KKKKKKssKK...",
            ".....KK.KKK.....",
            "................",
            "................"],
        // SHIELD DRAIN: the shield tipped over (cream on black), RED spilling.
        "stickerCursedDrainShield": [
            "................",
            ".....KKKKKK.....",
            "...KKKKKKKKKK...",
            "..KKKCCCCCKKKK..",
            "..KKKCRRRRCKKK..",
            ".KKKKCRRRRCKKKK.",
            ".KKKKCCDDCCKKKK.",
            "....KKCDDCKKKKK",
            ".KKKKKCCCCKKKsK.",
            ".KKKKKKRKKKKssK.",
            "..KKKKRRKKKKsK..",
            "..KKKRKKKKsssK..",
            "...KKKKKKssKK...",
            ".....KK.KKK.....",
            "................",
            "................"],
        // FLATLINE: the monitor line went flat, one last blip.
        "stickerCursedFlatline": [
            "................",
            ".....KKKKKK.....",
            "...KKKKKKKKKK...",
            "..KKKKKKKKKKKK..",
            "..KKKKKRKKKKKK..",
            ".KKKKKKRRKKKKKK.",
            ".KKKKKRKRKKKKKK.",
            "....KKRKRKKKKKK",
            ".KRRRRKKKRRRRsK.",
            ".KKKKKKKKKKKssK.",
            "..KKKKKKKKKKsK..",
            "..KKKKKKKKsssK..",
            "...KKKKKKssKK...",
            ".....KK.KKK.....",
            "................",
            "................"],
        // MAGNET: the red horseshoe. No card escapes it.
        "stickerCursedMagnet": [
            "................",
            ".....KKKKKK.....",
            "...KKKKKKKKKK...",
            "..KKKRRKKRRKKK..",
            "..KKKRRKKRRKKK..",
            ".KKKKRRKKRRKKKK.",
            ".KKKKRRKKRRKKKK.",
            "....KRRKKRRKKKK",
            ".KKKKRRRRRRKKsK.",
            ".KKKKKRRRRKKssK.",
            "..KKKKKKKKKKsK..",
            "..KKKKKKKKsssK..",
            "...KKKKKKssKK...",
            ".....KK.KKK.....",
            "................",
            "................"],
        // JAMMER: the pillar's cloth, barred shut (cream bars, red pins).
        "stickerCursedJammer": [
            "................",
            ".....KKKKKK.....",
            "...KKKKKKKKKK...",
            "..KKKCCCCCKKKK..",
            "..KKKKCRRCKKKK..",
            ".KKCCCCCCCCCCKK.",
            ".KKKKKCRRCKKKKK.",
            "....KKCRRCKKKKK",
            ".KKCCCCCCCCCCsK.",
            ".KKKKKCRRCKKssK.",
            "..KKKKCCCCKKsK..",
            "..KKKKKKKKsssK..",
            "...KKKKKKssKK...",
            ".....KK.KKK.....",
            "................",
            "................"],
        // PEELER: the chip's own corner lifting away — the lifted flap shows
        // its CREAM underside against the black face.
        "stickerCursedPeeler": [
            "................",
            ".....KKKKKK.....",
            "...KKKKKKCCKK...",
            "..KKKKKKCCCCK...",
            "..KKKKKCCCCKK...",
            ".KKKKKKKCCKKKK..",
            ".KKKKKKKKKKKKKK.",
            "....KKKKKKKKKKK",
            ".KKKKKKKKKKKKsK.",
            ".KKKKKKKKKKKssK.",
            "..KKKKKKKKKKsK..",
            "..KKKKKKKKsssK..",
            "...KKKKKKssKK...",
            ".....KK.KKK.....",
            "................",
            "................"],
        // BASE DRAIN: an empty battery (cream outline, dark cells), one red
        // sliver left.
        "stickerCursedDrainBase": [
            "................",
            ".....KKKKKK.....",
            "...KKKKKKKKKK...",
            "..KKKCCCCKKKKK..",
            "..KKCCCDDCCCKK..",
            ".KKKCDDDDDDKKKK.",
            ".KKKCDDDDDDKKKK.",
            "....CDDDDDCKKKK",
            ".KKKCDDDDDDCKsK.",
            ".KKKCRRDDDDCKssK",
            "..KKCCCCCCCCsK..",
            "..KKKKKKKKsssK..",
            "...KKKKKKssKK...",
            ".....KK.KKK.....",
            "................",
            "................"],
        // MALFUNCTION: corruption — a RED glitch fracture, one row shoved
        // sideways (the styleguide's corrupted-icon recipe, de-phosphored).
        "stickerCursedMalfunction": [
            "................",
            ".....KKKKKK.....",
            "...KKKKKKKKKK...",
            "..KKKKKRKKKKKK..",
            "..KKKKRRKKKRKK..",
            ".KKKKRRKKKKKKKK.",
            "..KKKKRRRKKKKK..",
            ".KKRKKKRRKKKKKK.",
            "....KKKRKKKKKsK",
            ".KKKKKRRKKRKssK.",
            "..KKKRRKKKKKsK..",
            "..KKKRKKKKsssK..",
            "...KKKKKKssKK...",
            ".....KK.KKK.....",
            "................",
            "................"],
        // SABOTEUR: the round bomb, fuse lit (cream bomb, red spark).
        "stickerCursedSaboteur": [
            "................",
            ".....KKKKKK.....",
            "...KKKKKKKKKK...",
            "..KKKKKKKRRKKK..",
            "..KKKKKRRKKKKK..",
            ".KKKKCCCCCCKKKK.",
            ".KKKCCCCCCCCKKK.",
            "....CCCCCCCCKKK",
            ".KKKCCCCCCCCCsK.",
            ".KKKCCCCCCCCssK.",
            "..KKKCCCCCCCsK..",
            "..KKKKCCCCsssK..",
            "...KKKKKKssKK...",
            ".....KK.KKK.....",
            "................",
            "................"],
        // The cloth hangs the FULL width of the crossbeam it is strung from —
        // it used to be half the beam's width, which read as a narrow pennant
        // on an oversized pole (v5.86).
        "pillar": [
            "................",
            ".KKKKKKKKKKKKKK.",
            ".KGGGGGGGGGGGGK.",
            ".KKKKKKKKKKKKKK.",
            ".KRRRRRRRRRRRRK.",
            ".KRRRRRRRRRRRRK.",
            ".KRCCCCCCCCCCRK.",
            ".KRCCCCGGCCCCRK.",
            ".KRCCCCCCCCCCRK.",
            ".KRRRRRRRRRRRRK.",
            ".KRRRRRRRRRRRRK.",
            ".KRRRRRRRRRRRRK.",
            ".KRRRRRKKRRRRRK.",
            ".KRRK......KRRK.",
            "..KK........KK..",
            "................"],
        // A PLAIN plate: ink frame, deep face, nothing else. The cream corner
        // screws, the smoke etch and the two baked phosphor pixels all read as
        // stray dots behind the item's own symbol — and the etch and LED got
        // LONGER when the plaque was widened, since widening repeats the
        // centre column. The real charge LED is its own node on top.
        "base": [
            "................",
            "................",
            "................",
            ".KKKKKKKKKKKKKK.",
            ".KDDDDDDDDDDDDK.",
            ".KDDDDDDDDDDDDK.",
            ".KDDDDDDDDDDDDK.",
            ".KDDDDDDDDDDDDK.",
            ".KDDDDDDDDDDDDK.",
            ".KDDDDDDDDDDDDK.",
            ".KDDDDDDDDDDDDK.",
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
        // The spade echoes the canonical PixelGlyph silhouette (v6.68): a
        // solid pointed leaf with a smooth tuck — NO side-lobe notch row
        // (the notches are the club's signature, never the spade's).
        "changeSuitSpade": [
            "................",
            "..KKKKKKKKKKKK..",
            "..KCCCCKKCCCCK..",
            "..KCCCKKKKCCCK..",
            "..KCCKKKKKKCCK..",
            "..KCKKKKKKKKCK..",
            "..KCKKKKKKKKCK..",
            "..KCCKKKKKKCCK..",
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
        // The club echoes the canonical PixelGlyph silhouette (v6.68): a
        // FLAT-TOPPED top lobe over a 2px neck (the old 2px pointed top was
        // exactly what blurred it into the spade), then the notched side
        // lobes.
        "changeSuitClub": [
            "................",
            "..KKKKKKKKKKKK..",
            "..KCCCKKKKCCCK..",
            "..KCCCKKKKCCCK..",
            "..KCCCCKKCCCCK..",
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
        // Flat-topped top lobe (canonical club, v6.68) — the old 2px pointed
        // top read as a spade inside the shield.
        "clubGuard": [
            "................",
            "..KKKKKKKKKKKK..",
            "..KCCCCCCCCCCK..",
            "..KCKKCCCCKKCK..",
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

    // MARK: - SUIT CAPTION (the restriction row ABOVE the chip)

    /// Upright 7×7 suit pips for the restriction caption — clean readable
    /// silhouettes (a point-top spade vs a round-top club, a lobed heart, a
    /// hard diamond), ♠/♣ cream, ♥/♦ suit-red. Drawn on TRANSPARENCY with no
    /// plate and no lean: the caption is a separate image (`suitCaption`),
    /// never baked into the chip, so suited and unsuited chips render at the
    /// SAME size and the chip keeps its clean rim.
    // ♠/♣ echo the canonical PixelGlyph silhouettes (suit-glyph sweep 2 —
    // the v6.68 redesign): the SPADE is one solid pointed leaf with NO side-
    // lobe notches; the CLUB is a flat-topped lobe over side lobes with a
    // dark gap on BOTH sides of the centre. The old caption pips still wore
    // the pre-redesign lobed spade / round-top club.
    private static let suitCaptionMarks: [String: [String]] = [
        "♠": ["...C...", "..CCC..", ".CCCCC.", "CCCCCCC", ".CCCCC.", "...C...", "..CCC.."],
        "♥": [".RR.RR.", "RRRRRRR", "RRRRRRR", "RRRRRRR", ".RRRRR.", "..RRR..", "...R..."],
        "♦": ["...R...", "..RRR..", ".RRRRR.", "RRRRRRR", ".RRRRR.", "..RRR..", "...R..."],
        "♣": ["..CCC..", "..CCC..", "CC.C.CC", "CCCCCCC", "CC.C.CC", "...C...", "..CCC.."],
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
        // Heart Bonus: ♥ lands → +1 coin (heart dropping a small coin ring).
        "heartBounty": [
            "............",
            "..RR..RR....",
            ".RRRR.RRRR..",
            ".RRRRRRRR...",
            ".RRRRRRRR...",
            "..RRRRRR....",
            "...RRRR.....",
            "....RR.XXXX.",
            ".......X..X.",
            ".......X..X.",
            "........XXXX",
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
        // 8 Bury: sticker-free ♣ → bury 1 (a clean club sinking into the
        // ground — the bury family's shared motif).
        "clubTribute": [
            "............",
            "....XXX.....",
            "...XXXXX....",
            "..XXXXXXX...",
            "...XX.XX....",
            ".....X......",
            ".....X......",
            "....XXX.....",
            ".....X......",
            "....XXX.....",
            "XXXXXXXXXXXX",
            "............"],
        // All Hearts: every pile ♥-top → +8 (a field of hearts, no coin —
        // the "all" read; Envy carries the hearts→coin read).
        "allHeartsCoin": [
            "............",
            "............",
            ".R.R...R.R..",
            ".RRR...RRR..",
            ".RRR...RRR..",
            "..R.....R...",
            "....R.R.....",
            "....RRR.....",
            "....RRR.....",
            ".....R......",
            "............",
            "............"],
        // Envy: +4 per ♥-topped pile (two hearts over a coin ring — every
        // heart pays out).
        "envy": [
            "............",
            ".R.R...R.R..",
            ".RRR...RRR..",
            ".RRR...RRR..",
            "..R.....R...",
            "............",
            "....XXXX....",
            "....X..X....",
            "....X..X....",
            "....XXXX....",
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
        // Streak Bury: streak → bury per guess (rising bars + a down arrow
        // into the ground — the streak pays IN burials).
        "streakTribute": [
            "............",
            "........X...",
            "....XX..X...",
            "....XX..X...",
            ".X..XX..X...",
            ".X..XX..X...",
            ".X..XX.XXXXX",
            ".X..XX..XXX.",
            ".X..XX...X..",
            "XXXXXXXXXXXX",
            "............",
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
        // Fibonacci: A/2/3/5/8 → +1 (a square spiral — the golden spiral's
        // pixel silhouette; the old scribble and the nested rects both read
        // as noise at emblem size).
        "fibonacci": [
            "............",
            "............",
            "..XXXXXXXXX.",
            "..........X.",
            "..X.XXXXX.X.",
            "..X.X...X.X.",
            "..X.X.X.X.X.",
            "..X.X...X.X.",
            "..X.XXXXX.X.",
            "..X.......X.",
            "..XXXXXXXXX.",
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
        // Dense Bury: ♣ with 2+ stickers → bury (the club-into-ground motif
        // flanked by two sticker chips).
        "denseBury": [
            "............",
            "....XXX.....",
            "...XXXXX....",
            "..XXXXXXX...",
            "...XX.XX....",
            ".....X......",
            ".XX..X..XX..",
            ".XX.XXX.XX..",
            ".....X......",
            "....XXX.....",
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
        // Insurance: lone surviving pile here → +20 (an umbrella — cover for
        // the last pile standing; the old life ring read as a skull).
        "insurance": [
            "............",
            "....XXXX....",
            "..XXXXXXXX..",
            ".XXXXXXXXXX.",
            ".X..X..X..X.",
            "............",
            ".....X......",
            ".....X......",
            ".....X......",
            "..X..X......",
            "..XXX.......",
            "............"],
        // Ditto: mirrors the center pillar (two chevrons facing each other —
        // a reflection, not the quote-mark noise of the old ditto marks).
        "ditto": [
            "............",
            "............",
            "..X.....X...",
            "...X...X....",
            "....X.X.....",
            "...X...X....",
            "..X.....X...",
            "............",
            "............",
            "............",
            "............",
            "............"],
        // Massive Diamond: ♦ counts +2 pile size (a big gold diamond with a
        // solid red ♦ core — the suit IS the emblem).
        "stickerCount": [
            "............",
            ".....XX.....",
            "....XRRX....",
            "...XRRRRX...",
            "..XRRRRRRX..",
            ".XRRRRRRRRX.",
            "..XRRRRRRX..",
            "...XRRRRX...",
            "....XRRX....",
            ".....XX.....",
            "............",
            "............"],
        // Prime: prime rank → +1 (a number pyramid — dot rows 2·3·5·7, the
            // prime ladder; the old hash read as a "#" character).
        "prime": [
            "............",
            ".....XX.....",
            "............",
            "....XXX.....",
            "............",
            "...XXXXX....",
            "............",
            "..XXXXXXX...",
            "............",
            "............",
            "............",
            "............"],
        // Queen's Eye: royal ♠ → peek (a small crown over a big eye — the
        // EYE carries it; Shuffler keeps the crown read).
        "queensEye": [
            "............",
            "..X.X.X.X...",
            "..XXXXXXX...",
            "...XXXXX....",
            "............",
            "...XXXX.....",
            "..XXPPXX....",
            "...XXXX.....",
            "............",
            "............",
            "............",
            "............"],
        // Shuffler: ♦ lands → shuffle others (crown with a red ♦ jewel —
        // the royal court; distinct from Queen's Eye's bare crown).
        "royalCourt": [
            "............",
            "..X..X..X...",
            "..X..X..X...",
            "..XX.X.XX...",
            "..XXXXXXX...",
            "..XXRRRXX...",
            "..XXRRRXX...",
            "..XXXXXXX...",
            "............",
            "............",
            "............",
            "............"],
        // Excavator: +2 per buried card in the ♥ pile (a shovel digging
        // down-left — handle, then a wide blade tapering to its point).
        "excavator": [
            "............",
            ".......XX...",
            "......XX....",
            ".....XX.....",
            "....XX......",
            "...XX.......",
            "..XX........",
            ".XXXXX......",
            ".XXXXX......",
            "..XXX.......",
            "...X........",
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
        // Last Rites: pile dies → peek (a lit candle: red flame with a cream
        // core over a gold body and base plate).
        "lastRites": [
            "............",
            ".....R......",
            "....RRR.....",
            "....RCR.....",
            ".....R......",
            "....XXX.....",
            "....XXX.....",
            "....XXX.....",
            "....XXX.....",
            "..XXXXXXX...",
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
        // ---- v6.68 sweep: every pillar gets its OWN emblem (these seven had
        // been falling to the label's first LETTER in the system font). ----
        // Last Licks: +3 coins if NO pile in the column survived (a headstone
        // with a cross cut out, standing on the ground line — the column's
        // grave pays out).
        "lastLicks": [
            "............",
            "...XXXXXX...",
            "..XXXXXXXX..",
            "..XXX..XXX..",
            "..XX....XX..",
            "..XXX..XXX..",
            "..XXX..XXX..",
            "..XXX..XXX..",
            "..XXXXXXXX..",
            "..XXXXXXXX..",
            "XXXXXXXXXXXX",
            "............"],
        // Fourth Seat: the column starts with 1 extra pile — another chair
        // pulled up to the table.
        "fourthSeat": [
            "............",
            "..XX........",
            "..XX........",
            "..XX........",
            "..XXXXXXXX..",
            "..XXXXXXXX..",
            "..XX....XX..",
            "..XX....XX..",
            "..XX....XX..",
            "..XX....XX..",
            "............",
            "............"],
        // Bulk Rate: the Purge ladder climbs slower (a price tag with its
        // string hole, and a down arrow — the price comes DOWN).
        "bulkRate": [
            "............",
            ".XXXXXXXX...",
            ".X......XX..",
            ".X.XX....XX.",
            ".X.XX.....X.",
            ".X........X.",
            ".XXXXXXXXXX.",
            ".....XX.....",
            ".....XX.....",
            "...XXXXXX...",
            "....XXXX....",
            ".....XX....."],
        // Freebie: one store item costs 0 (a ribboned gift box, bow on top).
        "freebie": [
            "............",
            "..XX....XX..",
            "....XXXX....",
            ".XXXXXXXXXX.",
            ".X...XX...X.",
            ".XXXXXXXXXX.",
            ".X...XX...X.",
            ".X...XX...X.",
            ".X...XX...X.",
            ".XXXXXXXXXX.",
            "............",
            "............"],
        // Rare Hunter: rares roll twice as often (a scope ring closed on a
        // phosphor gem — phosphor IS the rare-tier colour).
        "rareHunter": [
            "............",
            ".....XX.....",
            "...XX..XX...",
            "..X......X..",
            "..X..PP..X..",
            ".X..PPPP..X.",
            ".X..PPPP..X.",
            "..X..PP..X..",
            "..X......X..",
            "...XX..XX...",
            ".....XX.....",
            "............"],
        // Bouncer: 30% to turn Just a Two away (the Two's own corner pips,
        // cream, with the house's bar slashed between them — not tonight).
        "twoWard": [
            "............",
            ".XX.........",
            ".XXX....CC..",
            "..XXX...CC..",
            "...XXX......",
            "....XXX.....",
            ".....XXX....",
            "......XXX...",
            "..CC...XXX..",
            "..CC....XXX.",
            ".........XX.",
            "............"],
        // Flypaper: landings can pick up a random sticker (the hanging sticky
        // strip, two chips already stuck to it).
        "flypaper": [
            "............",
            "....XXXX....",
            ".....XX.....",
            ".....XX.....",
            "...CCXX.....",
            "...CCXX.....",
            ".....XX.....",
            ".....XXCC...",
            ".....XXCC...",
            ".....XX.....",
            "....XXXX....",
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
        // Spade Peeker: peek X = ♠-topped piles (a clean spade pip over an
        // eye — the old stack read as an exclamation mark).
        "spadePeek": [
            "............",
            "....X.......",
            "...XXX......",
            "..XXXXX.....",
            "..XXXXX.....",
            "...X.X......",
            "....X.......",
            "............",
            "..XXXXXX....",
            "..X.PP.X....",
            "..XXXXXX....",
            "............"],
        // Upheaval: shuffle every pile (two fat opposing arrows — the swap
        // read; the old crossing arrows collapsed into an "M").
        "shuffleColumn": [
            "............",
            "............",
            "............",
            "......XX....",
            "..XXXXXXX...",
            "......XX....",
            "............",
            "..XX........",
            ".XXXXXXX....",
            "..XX........",
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
        // Wild Sticker: random sticker to a random top (a vinyl chip with
        // two 4-point sparkles — the old chip+bits read as a robot face).
        "randomSticker": [
            "............",
            "........X...",
            "..XXX..XXX..",
            ".XXXXX..X...",
            ".XXXXX......",
            ".XXXXX......",
            ".XXXXX..X...",
            "..XXX..XXX..",
            "........X...",
            "............",
            "............",
            "............"],
        // Ballast: equalize all piles (a balance scale — beam, two pans,
        // base; the old beam+bars read as "TT").
        "evenOut": [
            "............",
            ".....XX.....",
            ".XXXXXXXXXX.",
            "..X..XX..X..",
            "..X..XX..X..",
            ".XXX.XX.XXX.",
            "..X..XX..X..",
            ".....XX.....",
            ".....XX.....",
            "..XXXXXX....",
            "............",
            "............"],
        // Cast: set top ranks to the bottom rank (an outlined card — the
        // rank pip inside — cast down onto the baseline).
        "setValue": [
            "............",
            "..XXXXX.....",
            "..X...X.....",
            "..X.X.X.....",
            "..X...X.....",
            "..XXXXX.....",
            "....XX......",
            "....XX......",
            "...XXXX.....",
            "....XX......",
            "XXXXXXXXXXXX",
            "............"],
        // Suit Setter: set top suits to the bottom suit (red ♦ cast down
        // onto the baseline — same composition as Cast, suit not rank).
        "setSuit": [
            "............",
            "....RR......",
            "...RRRR.....",
            "..RRRRRR....",
            "...RRRR.....",
            "....RR......",
            "....XX......",
            "....XX......",
            "...XXXX.....",
            "....XX......",
            "XXXXXXXXXXXX",
            "............"],
        // Sticker Harvest: bury per sticker, peel them (a dog-eared vinyl
        // chip — the peel — sinking into the ground).
        "stickerHarvest": [
            "............",
            "..XXXXX.....",
            "..X...XX....",
            "..X..X.X....",
            "..X.X..X....",
            "..XX...X....",
            "..XXXXXX....",
            "....XX......",
            "...XXXX.....",
            "....XX......",
            "XXXXXXXXXXXX",
            "............"],
        // Reactor: recharge the other bases (an atom — nucleus, ring, two
        // phosphor electrons; distinct from Revive's circular arrow).
        "refreshBases": [
            "............",
            "...XXXXXX...",
            "..P......X..",
            ".X.......X..",
            ".X..XX...X..",
            ".X..XX...X..",
            ".X.......X..",
            "..X......P..",
            "...XXXXXX...",
            "............",
            "............",
            "............"],
        // Club Dig: bury under each ♣ pile (the club pip digging through a
        // BROKEN ground line — the dig gap separates it from 8 Bury).
        "clubDig": [
            "............",
            "....XXX.....",
            "...XXXXX....",
            "..XXXXXXX...",
            "...XX.XX....",
            ".....X......",
            ".....X......",
            "....XXX.....",
            ".....X......",
            "XXXXX..XXXXX",
            "............",
            "............"],
        // Demolish: destroy a pillar, peek 2 (a hammer with a DIAGONAL
        // handle — the old vertical handle read as a "T").
        "demolish": [
            "............",
            ".XXXXXX.....",
            ".XXXXXX.....",
            "....XX......",
            ".....XX.....",
            "......XX....",
            ".......XX...",
            "........XX..",
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
        // Heart Tax: +1 per ♥ card (a heart over a stack of coins — the
        // column's hearts pay into the pile).
        "tax": [
            "............",
            "...R.R......",
            "..RRRRR.....",
            "..RRRRR.....",
            "...RRR......",
            "....R.......",
            "..XXXXXX....",
            "............",
            "..XXXXXX....",
            "............",
            "..XXXXXX....",
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
        // Power Surge: fire the Same-Power ("=" + a phosphor bolt).
        "activateSame": [
            "............",
            "..XXXXX.....",
            "..XXXXX.....",
            "............",
            "..XXXXX.....",
            "..XXXXX.....",
            "............",
            "......PPP...",
            ".....PP.....",
            "....PPP.....",
            "....PP......",
            "............"],
        // ---- v6.68 sweep: every base gets its OWN symbol (these five had
        // been falling to the label's first LETTER in the system font). ----
        // Last Resort: bury the whole deck, win the deal, blow up the
        // neighbours (the TNT bundle, fuse lit — red spark).
        "lastResort": [
            "............",
            ".......R....",
            "......RR....",
            "......X.....",
            ".....X......",
            ".XX.XX.XX...",
            ".XX.XX.XX...",
            ".XXXXXXXX...",
            ".XX.XX.XX...",
            ".XX.XX.XX...",
            "............",
            "............"],
        // Empty Purse: spend EVERY coin for one peek (the pouch tipped
        // upside-down, gold coins tumbling out of it).
        "emptyPurse": [
            "............",
            "...XXXXXX...",
            "..X......X..",
            "..X......X..",
            "...X....X...",
            "....X..X....",
            "....XXXX....",
            "............",
            ".....GG.....",
            "...GG.......",
            "......GG....",
            "............"],
        // Same Tell: the = mark appears on a same-rank top card (a card face
        // wearing the game's own = mark).
        "sameTell": [
            "............",
            "...XXXXXXX..",
            "...X.....X..",
            "...X.XXX.X..",
            "...X.....X..",
            "...X.XXX.X..",
            "...X.....X..",
            "...X.....X..",
            "...XXXXXXX..",
            "............",
            "............",
            "............"],
        // Club Oracle: tell markers on every ♣ top (the club pip over the
        // family eye — Spade Peeker's composition, club edition).
        "clubOracle": [
            "............",
            "....XX......",
            "...XXXX.....",
            ".XXXXXXXX...",
            ".XX.XX.XX...",
            "....XX......",
            "...XXXX.....",
            "............",
            "..XXXXXX....",
            "..X.PP.X....",
            "..XXXXXX....",
            "............"],
        // Escape Hatch: only in an ambush — clear the deal instantly (the
        // open doorway, an arrow bursting OUT through its wall).
        "ambushOut": [
            "............",
            ".XXXXXXX....",
            ".X.....X....",
            ".X.....X....",
            ".X......X...",
            ".X..XXXXXXX.",
            ".X..XXXXXXX.",
            ".X......X...",
            ".X.....X....",
            ".X.....X....",
            ".XXXXXXX....",
            "............"],
    ]

    /// 8×8 marks composited onto the Same-Power diamond's centre (in ink over
    /// the cleared "="), so the six powers no longer share one identical mark.
    /// Pixels must stay inside matrix rows 5–10 / cols 4–11 of the diamond.
    private static let samePowerMarks: [String: [String]] = [
        "linkBury": [    // Burrow — bury under every alive pile (down arrow into ground)
            "...KK...",
            "...KK...",
            ".KKKKKK.",
            "..KKKK..",
            "...KK...",
            "........",
            "KKKKKKKK",
            "........"],
        "linkRevive": [  // Rekindle — revive the largest dead pile (up arrow from ground)
            "...KK...",
            "..KKKK..",
            ".KKKKKK.",
            "...KK...",
            "...KK...",
            "........",
            "KKKKKKKK",
            "........"],
        "linkCoins": [   // Dividend — coin per alive pile (a stack of coins)
            "........",
            "..KKKK..",
            "..KKKK..",
            "........",
            "..KKKK..",
            "..KKKK..",
            "........",
            "..KKKK.."],
        "linkShuffle": [ // Link Shuffler — shuffle every alive pile
            "........",
            ".K....K.",
            ".KK..KK.",
            "..K.KK..",
            "..KK.K..",
            ".KK..KK.",
            ".K....K.",
            "........"],
        "samePeek": [    // Same Peeker — peek the next card (an eye, pupil included)
            "........",
            "..KKKK..",
            ".K....K.",
            "K..KK..K",
            "K..KK..K",
            ".K....K.",
            "..KKKK..",
            "........"],
        "linkHeavy": [   // Same Heavy — +size to every pile (expand arrows)
            "KK....KK",
            ".KK..KK.",
            "..K..K..",
            "........",
            "..K..K..",
            ".KK..KK.",
            "KK....KK",
            "........"],
        // ---- v6.68 sweep: the last three powers still wore the generic "=".
        "linkTell": [    // Second Sight — higher/lower tells (both chevrons)
            "...KK...",
            "..KKKK..",
            ".KK..KK.",
            "........",
            ".KK..KK.",
            "..KKKK..",
            "...KK...",
            "........"],
        "linkSticker": [ // Sticker Spray — chip sprayed onto every column top
            "........",
            ".KKK....",
            "KKKKK.K.",
            "KKKKK...",
            "KKKKK.K.",
            ".KKK....",
            "......K.",
            "........"],
        "linkPurge": [   // Long Odds — 25% to purge a deck card (the target)
            "..KKKK..",
            ".K....K.",
            "K..KK..K",
            "K.KKKK.K",
            "K.KKKK.K",
            "K..KK..K",
            ".K....K.",
            "..KKKK.."],
    ]

    /// The mystery Same-Power's centre mark: a "?" in place of any power's own
    /// (same 8×8 shape as samePowerMarks, inked over the phosphor diamond).
    private static let mysterySamePowerMark: [String] = [
        "..KKKK..",
        ".KK..KK.",
        ".....KK.",
        "....KK..",
        "...KK...",
        "...KK...",
        "........",
        "...KK...",
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
        // palette letters paint fixed (suit reds, phosphor charge, ink). The
        // cell snaps to an INTEGER pixel — a fractional cell smears the
        // matrix into mush at emblem size.
        if let rows = perId?[def.id] {
            let cell = max(1, (min(rect.width, rect.height) / 12).rounded())
            // Centre the CONTENT, not the grid: an authored glyph rarely
            // fills its matrix symmetrically, and the empty margin read as
            // an off-centre icon on every base plate (v6.36).
            let (ox, oy) = contentCentred(rows, painted: "XKRGPC", in: rect, cell: cell)
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
                                   width: cell, height: cell))
                }
            }
            return
        }
        // A suit glyph in the icon field renders as the game's own pixel suit
        // (v6.66 — never the system font's), a known family gets its pixel
        // matrix, anything else the label's first letter. The FE0F variation
        // selector some icon fields carry (♠️) folds to the bare suit.
        let suitGlyphs = ["♠", "♥", "♦", "♣", "★", "=", "∅", "◉"]
        if let icon = def.icon?.replacingOccurrences(of: "\u{FE0F}", with: ""),
           suitGlyphs.contains(icon) {
            if let img = PixelGlyph.suitImage(icon, size: size, color: color) {
                UIGraphicsPushContext(cg)
                img.draw(in: CGRect(x: rect.midX - img.size.width / 2,
                                    y: rect.midY - img.size.height / 2,
                                    width: img.size.width, height: img.size.height))
                UIGraphicsPopContext()
                return
            }
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
            let (ox, oy) = contentCentred(rows, painted: "KRGPC", in: rect, cell: cell)
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

    /// The origin that centres a matrix's PAINTED pixels (not its grid) in
    /// `rect`. Falls back to grid-centring when nothing is painted.
    private static func contentCentred(_ rows: [String], painted: String,
                                       in rect: CGRect, cell: CGFloat) -> (CGFloat, CGFloat) {
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for (yy, row) in rows.enumerated() {
            for (xx, ch) in row.enumerated() where painted.contains(ch) {
                minX = min(minX, xx); maxX = max(maxX, xx)
                minY = min(minY, yy); maxY = max(maxY, yy)
            }
        }
        guard minX <= maxX else {
            return (rect.midX - cell * 6, rect.midY - cell * 6)
        }
        let cx = CGFloat(minX + maxX + 1) / 2, cy = CGFloat(minY + maxY + 1) / 2
        return (rect.midX - cell * cx, rect.midY - cell * cy)
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
    /// the sticker's own 16×16 face contain-fit in the centre. ALWAYS the
    /// square chip at full size — a `suits` restriction is never baked in
    /// (it made suited chips aspect-fit ~20% smaller); callers that want it
    /// park `suitCaption` ABOVE the chip as its own view. Cursed stickers
    /// are the `stickerCursed`/`stickerCursed2` corruption art with no face.
    /// Curse id → its corruption matrix. Leech keeps the original torn chip
    /// (the big worm IS its motif); everything else is v6.48 family art.
    static let cursedChipKeys: [String: String] = [
        "leech": "stickerCursed",
        "leech2": "stickerCursed2",
        "trapdoor": "stickerCursedTrapdoor",
        "shrink": "stickerCursedShrink",
        "mute": "stickerCursedMute",
        "spoiler": "stickerCursedSpoiler",
        "drainShield": "stickerCursedDrainShield",
        "flatline": "stickerCursedFlatline",
        "magnet": "stickerCursedMagnet",
        "jammer": "stickerCursedJammer",
        "peeler": "stickerCursedPeeler",
        "drainBase": "stickerCursedDrainBase",
        "malfunction": "stickerCursedMalfunction",
        "saboteur": "stickerCursedSaboteur",
    ]

    public static func sticker(_ def: ItemDef, size: CGFloat = 56) -> UIImage {
        baked("stk-\(def.id)-\(Int(size))") {
            let k = max(4, Int((size / 16).rounded(.up)))
            let side = 16 * k
            // The chip art: cursed = the curse's OWN corruption matrix (v6.48:
            // every curse has one), everything else the standard chip.
            let chipKey = def.cursed
                ? (ItemArt.cursedChipKeys[def.id] ?? "stickerCursed")
                : "sticker"
            guard let chip = classArt[chipKey] else { return legacyStickerChip(def, size: size) }
            // The face: cursed chips carry no inner icon (the corruption IS
            // the face); a non-cursed sticker without a matrix keeps the
            // legacy octagon (empty set by the web's fail-loud contract).
            let face = def.cursed ? nil : stickerFaces[def.id]
            if !def.cursed && face == nil { return legacyStickerChip(def, size: size) }
            return PixelTexture.image(size: CGSize(width: side, height: side)) { cg in
                if def.cursed {
                    // v6.57 (third pass, player directive: red/black/evil —
                    // the v6.55 phosphor ring still read GREEN at deal
                    // scale): the chip rides its curse plate — the near-black
                    // void with red drips (see cursedPlate) — and closes with
                    // the suit-red cursedRim ring ON TOP, so a curse reads as
                    // a curse at a glance wherever the chip appears (cards,
                    // pickers, reveals, the collection) WITHOUT losing the
                    // round sticker silhouette the old red square cost it.
                    drawMatrix(cg, classArt["cursedPlate"] ?? [], ox: 0, oy: 0, cell: CGFloat(k))
                }
                drawMatrix(cg, chip, ox: 0, oy: 0, cell: CGFloat(k))
                if def.cursed {
                    drawMatrix(cg, classArt["cursedRim"] ?? [], ox: 0, oy: 0, cell: CGFloat(k))
                }
                if let face {
                    // The web's .dcs-ic: a centred 58% box, contain-fit.
                    let fk = max(1, Int((Double(k) * 0.58).rounded()))
                    let fs = 16 * fk
                    drawMatrix(cg, face, ox: CGFloat(side - fs) / 2,
                               oy: CGFloat(side - fs) / 2, cell: CGFloat(fk))
                }
            }
        }
    }

    /// The suit restriction as its OWN quiet image — nil when the sticker is
    /// unrestricted. A single row of upright 7×7 suit pips (♠♣ cream, ♥♦
    /// suit-red, 2px air between pips) on transparency: no plate, no lean.
    /// `width` is the row's target width; the pip scale derives from a full
    /// three-suit row so EVERY sticker's pips render at the same size (the
    /// returned image's own size is whatever the integer scale lands on —
    /// lay out from `image.size`, never from `width`).
    /// Placement contract: centred ABOVE the chip, bottom edge 2pt over the
    /// chip's top; the chip's frame never changes.
    public static func suitCaption(_ def: ItemDef, width: CGFloat = 40) -> UIImage? {
        guard let suits = def.suits, !suits.isEmpty else { return nil }
        let marks = suits.compactMap { suitCaptionMarks[$0] }
        guard !marks.isEmpty else { return nil }
        return baked("cap-\(def.id)-\(Int(width))") {
            let pip = 7, air = 2
            let cols = marks.count * pip + (marks.count - 1) * air
            let k = max(1, Int((width / CGFloat(3 * pip + 2 * air)).rounded()))
            return PixelTexture.image(size: CGSize(width: cols * k, height: pip * k)) { cg in
                var ox: CGFloat = 0
                for mark in marks {
                    drawMatrix(cg, mark, ox: ox, oy: 0, cell: CGFloat(k))
                    ox += CGFloat((pip + air) * k)
                }
            }
        }
    }

    /// `suitCaption` as a ready view (nearest filter, frame = image size) —
    /// centre it above the chip, bottom 2pt over the chip's top.
    public static func suitCaptionView(_ def: ItemDef, width: CGFloat = 40) -> UIImageView? {
        guard let img = suitCaption(def, width: width) else { return nil }
        let iv = UIImageView(image: img)
        iv.contentMode = .scaleAspectFit
        iv.layer.magnificationFilter = .nearest
        iv.isUserInteractionEnabled = false
        iv.frame = CGRect(origin: .zero, size: img.size)
        return iv
    }

    /// A pillar: the web's pixel pennant (gold rod, red swallowtail cloth),
    /// with the item's glyph inked gold over an ink halo on the emblem spot —
    /// the web's .pb-emblem at centre ≈46% of the square, 46% wide.
    public static func pillar(_ def: ItemDef, width: CGFloat = 52, height: CGFloat = 68) -> UIImage {
        baked("pil-\(def.id)-\(Int(width))x\(Int(height))") {
            // HEIGHT picks the pixel scale (the band is the hard limit); WIDTH
            // is then met by repeating the plate's centre column, so the plaque
            // spans its pile instead of floating narrow inside the column.
            let k = max(3, Int(min(width / 16, height / 16).rounded()))
            let cols = max(16, Int((width / CGFloat(k)).rounded()))
            let art = widened(classArt["pillar"] ?? [], to: cols)
            let w = CGFloat(cols * k), h = CGFloat(16 * k)
            return PixelTexture.image(size: CGSize(width: w, height: h)) { cg in
                drawMatrix(cg, art, ox: 0, oy: 0, cell: CGFloat(k))
                // The emblem stays a SQUARE keyed to the plate's height and
                // centred on the (now wider) plate.
                let halo = (h * 0.46).rounded()
                let hx = (w - halo) / 2
                let hy = (h * 0.46 - halo / 2).rounded()
                cg.setFillColor(CRT.ink.cgColor)
                cg.fill(CGRect(x: hx, y: hy, width: halo, height: halo))
                let inset = halo * 0.10
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
        case "kamikaze", "demolish", "heartDemolish",
             "lastResort": return CRT.suitRed                       // destroy
        case "tax": return CRT.gold                                 // coins
        default: return CRT.cardFace                                // peek + util
        }
    }

    /// A base: the web's pixel plaque (ink frame, deep plate, cream corner
    /// screws, smoke etch, baked phosphor LED — trimmed to its content like
    /// the web's TRIM_ICONS) with the item's symbol in its family colour.
    public static func base(_ def: ItemDef, width: CGFloat = 58, height: CGFloat = 40) -> UIImage {
        baked("bas-\(def.id)-\(Int(width))x\(Int(height))") {
            let rows = trimmed(classArt["base"] ?? [])
            guard !rows.isEmpty else {
                return PixelTexture.image(size: CGSize(width: width, height: height)) { _ in }
            }
            // Same rule as the pillar: the band height picks the pixel scale,
            // then the plate is widened by whole columns to span the card.
            let k = max(3, Int(min(width / CGFloat(rows[0].count),
                                   height / CGFloat(rows.count)).rounded()))
            let cols = max(rows[0].count, Int((width / CGFloat(k)).rounded()))
            let plate = widened(rows, to: cols)
            let w = cols * k, h = rows.count * k
            return PixelTexture.image(size: CGSize(width: w, height: h)) { cg in
                drawMatrix(cg, plate, ox: 0, oy: 0, cell: CGFloat(k))
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
    /// the web. NO baked name: the name is LIVE text at every call site
    /// (store tile `.pf-name` caption, detail, collection).
    public static func pack(_ def: ItemDef, deckId: String, width: CGFloat = 46, height: CGFloat = 60) -> UIImage {
        baked("pak-\(def.id)-\(Int(width))x\(Int(height))") {
            let key = def.int("keep", 1) >= 2
                ? (def.kind == "sticker" ? "packLargeSticker" : "packLarge")
                : (def.kind == "sticker" ? "packSticker" : "packCard")
            let rows = trimmed(classArt[key] ?? [])
            let cols = rows[0].count
            let k = max(3, Int(min(width / CGFloat(cols), height / CGFloat(rows.count)).rounded(.up)))
            return matrixImage(rows, scale: k)
        }
    }

    /// A Same-Power: the web's class mark (the `samePower` phosphor diamond)
    /// with the power's own ink mark (samePowerMarks) replacing the generic
    /// "=" at its centre. NO baked name: the label is live text below the
    /// art at every call site.
    public static func samePower(_ def: ItemDef, width: CGFloat = 56, height: CGFloat = 58) -> UIImage {
        baked("sp-\(def.id)-\(Int(width))x\(Int(height))") {
            let k = max(4, Int((min(width, height) / 16).rounded(.up)))
            let mark = CGFloat(16 * k)
            return PixelTexture.image(size: CGSize(width: mark, height: mark)) { cg in
                let cell = CGFloat(k)
                if let art = classArt["samePower"] {
                    drawMatrix(cg, art, ox: 0, oy: 0, cell: cell)
                }
                // The power's own mark replaces the generic "=" at the
                // diamond's centre: clear the "=" back to phosphor, then ink
                // the 8×8 mark (pixels stay inside rows 5–10, cols 4–11).
                if let rows = samePowerMarks[def.id] {
                    cg.setFillColor(CRT.phosphor.cgColor)
                    cg.fill(CGRect(x: 4 * cell, y: 6 * cell,
                                   width: 8 * cell, height: 4 * cell))
                    drawMatrix(cg, rows, ox: 4 * cell, oy: 4 * cell, cell: cell)
                }
            }
        }
    }

    /// The MYSTERY Same-Power slot object (v6.51): the phosphor diamond class
    /// mark with a "?" ink mark in place of any power's own — an unknown
    /// Same-Power until the buy reveals it. No baked name — call sites render
    /// the config label.
    public static func mysterySamePower(width: CGFloat = 56, height: CGFloat = 58) -> UIImage {
        baked("sp-mystery-\(Int(width))x\(Int(height))") {
            let k = max(4, Int((min(width, height) / 16).rounded(.up)))
            let mark = CGFloat(16 * k)
            return PixelTexture.image(size: CGSize(width: mark, height: mark)) { cg in
                let cell = CGFloat(k)
                if let art = classArt["samePower"] {
                    drawMatrix(cg, art, ox: 0, oy: 0, cell: cell)
                }
                // Clear the generic "=" back to phosphor, then ink the "?".
                cg.setFillColor(CRT.phosphor.cgColor)
                cg.fill(CGRect(x: 4 * cell, y: 6 * cell,
                               width: 8 * cell, height: 4 * cell))
                drawMatrix(cg, mysterySamePowerMark, ox: 4 * cell, oy: 4 * cell, cell: cell)
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
                string: "PURGE",
                attributes: [.font: CRT.Font.of(14),
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
