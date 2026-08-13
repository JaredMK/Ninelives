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
