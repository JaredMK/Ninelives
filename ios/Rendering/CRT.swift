import UIKit

/// CRT CASINO — the locked design system, transcribed from `/styleguide.html`.
///
/// "A haunted video poker machine from 1985." The styleguide is the contract:
/// if a surface disagrees with it, the surface is wrong. Everything here is a
/// direct port of that page's `:root` block and its component recipes.
public enum CRT {

    // MARK: - §1 Palette — locked, 8 colors, no others

    /// deep felt — app background, screen wells
    public static let feltDeep = UIColor(hex: 0x142820)
    /// felt mid — panels, HUD, recessed chrome
    public static let feltMid  = UIColor(hex: 0x1e3a2c)
    /// card face — aged cream, NEVER pure white
    public static let cardFace = UIColor(hex: 0xece4cf)
    /// suit red — ♥ ♦, danger, death
    public static let suitRed  = UIColor(hex: 0xc22f45)
    /// ink — outlines, ♠ ♣, text on light
    public static let ink      = UIColor(hex: 0x10100e)
    /// coin gold — coins, prices, secondary accents
    public static let gold     = UIColor(hex: 0xd9a441)
    /// phosphor — CTAs, highlights, score. THE ONLY thing that may glow.
    public static let phosphor = UIColor(hex: 0x4ef08a)
    /// shadow — hard offset ↘, zero blur
    public static let shadow   = UIColor.black

    /// Dimmed body text (`small, .muted` → opacity 0.62).
    public static let muted = cardFace.withAlphaComponent(0.62)
    /// Disabled button text (`rgba(236,228,207,0.45)`).
    public static let disabledText = cardFace.withAlphaComponent(0.45)

    // MARK: - Pixel grid

    /// `--px: 2px` — the pixel-grid unit. Borders are 2–4px, offsets multiples of it.
    public static let px: CGFloat = 2
    /// The standard hard shadow offset (`4px 4px 0 0`), down-right, no blur.
    public static let shadowOffset: CGFloat = 4
    /// A pressed button sinks one pixel step and its shadow halves.
    public static let pressSink: CGFloat = 2

    /// `--glow: 0 0 6px rgba(78,240,138,0.55)` — THE one glow. Baked into a
    /// texture at creation, never applied per frame.
    public static let glowRadius: CGFloat = 6
    public static let glowAlpha: CGFloat = 0.55

    /// Snap a value to the pixel grid so nothing ever lands on a half-pixel and
    /// blurs. Every layout coordinate goes through this.
    public static func snap(_ v: CGFloat) -> CGFloat { (v / px).rounded() * px }

    // MARK: - §3 Typography — one family everywhere

    public enum Font {
        /// The game family. VT323 stays legible at 7–10px where Press Start 2P
        /// collapses into unreadable blocks (styleguide §3 verdict).
        public static let body = "VT323-Regular"
        /// Display headers ONLY — screen titles, the wordmark.
        public static let display = "PressStart2P-Regular"

        // THE TYPE SCALE (styleguide §3b) — every text node in the game sits
        // on one of these steps. No off-scale sizes in new code; when copy
        // stops fitting, give the CONTAINER room or cut words — never invent
        // a smaller step.
        /// Fine print: chip meta, footnotes, dim hints. THE HARD MINIMUM.
        public static let caption: CGFloat = 14
        /// Stat rows, list meta, HUD counters, secondary buttons.
        public static let label: CGFloat = 16
        /// Descriptions, help copy, prompt questions.
        public static let bodySize: CGFloat = 18
        /// Panel headers, item names, standard buttons.
        public static let heading: CGFloat = 20
        /// Screen titles (VT323 or Press Start 2P at title size).
        public static let title: CGFloat = 22
        /// Heroes: the wordmark, big numerals, overlay banners. Sized to the
        /// container, never below `title`.
        public static let displaySize: CGFloat = 28

        /// The legibility floor = the `caption` step. v6.46 raised it from 13
        /// after the on-device ramp test (`-typeRamp 1`): 13pt VT323 on felt
        /// fails the arm's-length read, 14pt is the first comfortable step.
        /// ENFORCED, not advisory — every font in the app comes through `of`,
        /// so nothing can slip under it. When something stops fitting, give
        /// the CONTAINER room; never pass a smaller size expecting it to be
        /// honoured.
        public static let floor: CGFloat = caption

        public static func of(_ size: CGFloat, display useDisplay: Bool = false) -> UIFont {
            let name = useDisplay ? display : body
            return UIFont(name: name, size: max(floor, size))
                // A missing font would silently swap in Helvetica and quietly
                // destroy the whole aesthetic — fail loud in debug instead.
                ?? {
                    assertionFailure("Pixel font '\(name)' is not registered — check UIAppFonts + Assets/Fonts")
                    return .monospacedSystemFont(ofSize: size, weight: .regular)
                }()
        }
    }

    // MARK: - Suits

    public static func color(forSuit suit: String) -> UIColor {
        switch suit {
        case "♥", "♦": return suitRed
        case "★":      return gold        // Joker
        default:       return ink         // ♠ ♣
        }
    }
}

public extension UIColor {
    /// Mix `amount` of `other` into this colour. Used for the store's rarity
    /// wash — a tint of the hue over felt, never a new colour outside the
    /// locked palette.
    func blended(with other: UIColor, amount: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = max(0, min(1, amount))
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t, alpha: a1)
    }

    convenience init(hex: UInt32) {
        self.init(red:   CGFloat((hex >> 16) & 0xff) / 255,
                  green: CGFloat((hex >> 8)  & 0xff) / 255,
                  blue:  CGFloat( hex        & 0xff) / 255,
                  alpha: 1)
    }
}
