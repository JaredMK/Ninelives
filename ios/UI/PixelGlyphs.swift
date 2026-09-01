import UIKit

/// Pixel-art marks drawn on the 8×8 sprite grid (styleguide §6/§7) — the
/// game's own ✓ / ✗ / lock, replacing system text glyphs that read as foreign
/// to the pixel aesthetic. Palette colors only, nearest-neighbour scaling,
/// a baked 1px ink drop under the lit pixels so the mark sits on the felt
/// like every other sprite (hard shadow, no blur).
enum PixelGlyph {

    /// Tier CLEARED — a chunky gold check.
    static let check = [
        "........",
        ".......X",
        "......XX",
        ".....XX.",
        "X...XX..",
        "XX.XX...",
        ".XXXX...",
        "..XX....",
    ]

    /// Tier NOT cleared yet — an empty ring: the slot where the check goes.
    static let ring = [
        "..XXXX..",
        ".XX..XX.",
        "XX....XX",
        "X......X",
        "X......X",
        "XX....XX",
        ".XX..XX.",
        "..XXXX..",
    ]

    /// Tier LOCKED — a padlock.
    static let lock = [
        "..XXXX..",
        ".XX..XX.",
        ".XX..XX.",
        "XXXXXXXX",
        "XXXXXXXX",
        "XXX..XXX",
        "XXXX.XXX",
        "XXXXXXXX",
    ]

    // ---- The four suits (v6.66) --------------------------------------------
    // Neither VT323 nor Press Start 2P carries U+2660–2666, so every text
    // ♠♥♦♣ fell through to the SYSTEM font — a smooth foreign glyph (emoji-
    // presentation where a U+FE0F rode along) in the middle of pixel type.
    // These are the game's own suit marks, drawn on the same 8×8 grid.

    // v6.68 SPADE vs CLUB LEGIBILITY: at 8px (scale 1 — inline beside 14–16pt
    // text, half-scale cards) the old spade and club were near-twins: both a
    // lobed mass with side notches over a stem. Redrawn as opposites —
    // SPADE: ONE pointed leaf. Sharp 2px point, smooth widen to the full-width
    // base, a gentle tuck, then the stem. NO side-lobe notches anywhere: the
    // solid silhouette IS the spade.
    static let spade = [
        "...XX...",
        "..XXXX..",
        ".XXXXXX.",
        "XXXXXXXX",
        "XXXXXXXX",
        ".XXXXXX.",
        "...XX...",
        "..XXXX..",
    ]

    static let heart = [
        ".XX..XX.",
        "XXXXXXXX",
        "XXXXXXXX",
        "XXXXXXXX",
        ".XXXXXX.",
        "..XXXX..",
        "...XX...",
        "........",
    ]

    static let diamond = [
        "...XX...",
        "..XXXX..",
        ".XXXXXX.",
        "XXXXXXXX",
        "XXXXXXXX",
        ".XXXXXX.",
        "..XXXX..",
        "...XX...",
    ]

    // CLUB: THREE separated round lobes. A flat-topped 4px top lobe (vs the
    // spade's 2px point), a 2px neck, then the two side lobes with a visible
    // notch on BOTH sides of each (rows 3/5), fused only through the centre
    // row, then the stem. The dark gaps are the club's signature — the one
    // thing the spade never has.
    static let club = [
        "..XXXX..",
        "..XXXX..",
        "...XX...",
        "XX.XX.XX",
        "XXXXXXXX",
        "XX.XX.XX",
        "...XX...",
        "..XXXX..",
    ]

    static let suits: [String: [String]] = ["♠": spade, "♥": heart, "♦": diamond, "♣": club]

    // ---- The menu icon strip (v6.67) ---------------------------------------
    // Settings · How to Play · Stats · Rankings as 8×8 marks.

    /// SETTINGS — a gear: toothed ring, hollow hub.
    static let gear = [
        "X..XX..X",
        ".XXXXXX.",
        ".XX..XX.",
        "XX....XX",
        "XX....XX",
        ".XX..XX.",
        ".XXXXXX.",
        "X..XX..X",
    ]

    /// HOW TO PLAY — the question mark.
    static let question = [
        ".XXXXX..",
        "XX...XX.",
        ".....XX.",
        "....XX..",
        "...XX...",
        "...XX...",
        "........",
        "...XX...",
    ]

    /// STATS — three rising bars.
    static let bars = [
        "......XX",
        "......XX",
        "...XX.XX",
        "...XX.XX",
        "XX.XX.XX",
        "XX.XX.XX",
        "XX.XX.XX",
        "XX.XX.XX",
    ]

    /// RANKINGS — the trophy cup.
    static let trophy = [
        "XXXXXXXX",
        "X.XXXX.X",
        "X.XXXX.X",
        "XX.XX.XX",
        "..XXXX..",
        "...XX...",
        "...XX...",
        "..XXXX..",
    ]

    /// A suit mark sized to sit INSIDE text rendered at `size` — integer
    /// pixel scale (grid stays square), no baked shadow (an inline glyph
    /// casts none). Self-tinting suits paint their own colour (v6.96: the
    /// Colorful Cards scheme included — ♦ blue / ♣ green when ON); the rest
    /// take the surrounding run's ink. Nil for a non-suit string.
    static func suitImage(_ symbol: String, size: CGFloat, color: UIColor) -> UIImage? {
        guard let rows = suits[symbol] else { return nil }
        let tint = CRT.forcedSuitColor(symbol) ?? color
        return image(rows, color: tint, scale: max(1, (size / 12).rounded()), shadow: false)
    }

    /// PIXEL SUITS IN TEXT (v6.66): swap every suit character in `s` for an
    /// inline pixel mark (NSTextAttachment), centred against the RUN's own
    /// cap band (v6.97: read the font AT the suit — a display-face title
    /// used to be measured against the body face, which parked the mark a
    /// half-step low). Folds the emoji-presentation variants (♠️ = ♠ +
    /// U+FE0F) to the same mark. The one substitution point every text
    /// surface shares — CRTKit labels and PixelTexture-baked sprites alike.
    static func substituteSuits(_ s: NSAttributedString, size: CGFloat,
                                color: UIColor) -> NSAttributedString {
        guard s.string.contains(where: { suits[String($0)] != nil }) else { return s }
        let out = NSMutableAttributedString(attributedString: s)
        var i = (out.string as NSString).length - 1
        while i >= 0 {
            let ns = out.string as NSString
            let ch = ns.substring(with: NSRange(location: i, length: 1))
            let runFont = (out.attribute(.font, at: i, effectiveRange: nil) as? UIFont)
                ?? CRT.Font.of(size)
            if let img = suitImage(ch, size: size, color: color) {
                var range = NSRange(location: i, length: 1)
                if i + 1 < ns.length, ns.character(at: i + 1) == 0xFE0F { range.length = 2 }
                let att = NSTextAttachment()
                att.image = img
                att.bounds = CGRect(x: 0, y: (runFont.capHeight - img.size.height) / 2,
                                    width: img.size.width, height: img.size.height)
                out.replaceCharacters(in: range, with: NSAttributedString(attachment: att))
            }
            i -= 1
        }
        return out
    }

    private static var cache: [String: UIImage] = [:]

    /// Bake a matrix at `scale` pixels per grid cell. The shadow is one grid
    /// cell down-right, ink, behind the lit pixels.
    static func image(_ rows: [String], color: UIColor, scale: CGFloat = 3,
                      shadow: Bool = true) -> UIImage {
        let key = rows.joined() + "|\(color.description)|\(scale)|\(shadow)"
        if let c = cache[key] { return c }
        let w = CGFloat(rows[0].count) * scale + (shadow ? scale : 0)
        let h = CGFloat(rows.count) * scale + (shadow ? scale : 0)
        let img = PixelTexture.image(size: CGSize(width: w, height: h)) { cg in
            func pass(_ fill: UIColor, dx: CGFloat, dy: CGFloat) {
                cg.setFillColor(fill.cgColor)
                for (y, row) in rows.enumerated() {
                    for (x, ch) in row.enumerated() where ch == "X" {
                        cg.fill(CGRect(x: CGFloat(x) * scale + dx, y: CGFloat(y) * scale + dy,
                                       width: scale, height: scale))
                    }
                }
            }
            if shadow { pass(CRT.ink, dx: scale, dy: scale) }
            pass(color, dx: 0, dy: 0)
        }
        cache[key] = img
        return img
    }

    static func checkImage(scale: CGFloat = 3) -> UIImage { image(check, color: CRT.gold, scale: scale) }
    static func ringImage(scale: CGFloat = 3) -> UIImage { image(ring, color: CRT.disabledText, scale: scale, shadow: false) }
    static func lockImage(scale: CGFloat = 3) -> UIImage { image(lock, color: CRT.muted, scale: scale) }
}
