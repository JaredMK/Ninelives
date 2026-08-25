import SpriteKit
import UIKit

/// Texture baking. EVERYTHING that could cost per-frame work — text layout,
/// the phosphor glow, panel borders, card faces, the CRT overlay — is drawn
/// ONCE into a texture here and then blitted as a plain sprite.
///
/// This is the whole reason the port exists: the browser paid layout + filter
/// costs every frame. Nothing in `Rendering/` may use `SKEffectNode`,
/// `CIFilter`, or `SKShapeNode` on the hot path.
public enum PixelTexture {

    /// Textures are nearest-neighbour — a pixel game must never bilinear-blur.
    public static func texture(from image: UIImage) -> SKTexture {
        let t = SKTexture(image: image)
        t.filteringMode = .nearest
        return t
    }

    /// Draw at scale 1 so the bitmap IS the pixel grid, then let SpriteKit
    /// upscale with nearest-neighbour — the same trick as the web's
    /// `image-rendering: pixelated`.
    public static func image(size: CGSize, _ draw: (CGContext) -> Void) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let cg = ctx.cgContext
            cg.interpolationQuality = .none
            cg.setAllowsAntialiasing(false)
            cg.setShouldAntialias(false)
            draw(cg)
        }
    }

    // MARK: - Text

    private struct TextKey: Hashable {
        let text: String, size: CGFloat, rgba: UInt32, display: Bool, glow: Bool
    }
    private static var textCache: [TextKey: SKTexture] = [:]

    /// A baked text texture. The phosphor glow is drawn INTO the bitmap (a
    /// blur at bake time is free; a blur per frame is not), so a glowing label
    /// costs exactly one sprite draw.
    public static func text(_ string: String, size: CGFloat, color: UIColor,
                            display: Bool = false, glow: Bool = false) -> SKTexture {
        let key = TextKey(text: string, size: size, rgba: color.packed, display: display, glow: glow)
        if let cached = textCache[key] { return cached }

        let font = CRT.Font.of(size, display: display)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        // Suit characters bake as the game's own pixel marks (v6.66) — the
        // fonts carry no ♠♥♦♣, so the system fallback leaked into every
        // suit-naming sprite (the deal HUD's suit tallies above all).
        let rich = PixelGlyph.substituteSuits(NSAttributedString(string: string, attributes: attrs),
                                              size: size, color: color)
        let measured = rich.boundingRect(with: CGSize(width: 4096, height: 4096),
                                         options: .usesLineFragmentOrigin, context: nil).size
        // Room for the glow bleed on every side.
        let pad = glow ? CRT.glowRadius + 2 : 0
        let canvas = CGSize(width: ceil(measured.width) + pad * 2,
                            height: ceil(measured.height) + pad * 2)

        let img = image(size: canvas) { cg in
            UIGraphicsPushContext(cg)
            defer { UIGraphicsPopContext() }
            let origin = CGPoint(x: pad, y: pad)
            if glow {
                // THE one glow: 0 0 6px rgba(phosphor, 0.55), baked.
                cg.setShadow(offset: .zero, blur: CRT.glowRadius,
                             color: CRT.phosphor.withAlphaComponent(CRT.glowAlpha).cgColor)
                // Text itself must stay crisp, so let the shadow pass render the
                // halo and draw the glyphs again on top with no shadow.
                rich.draw(at: origin)
                cg.setShadow(offset: .zero, blur: 0, color: nil)
            }
            rich.draw(at: origin)
        }
        let tex = texture(from: img)
        textCache[key] = tex
        return tex
    }

    /// A baked ATTRIBUTED block, wrapped to `maxWidth` (v6.83). The plain
    /// `text` bake above carries ONE colour and ONE face for the whole
    /// string; the in-deal help panel needs a coloured, bolded sticker name
    /// inline with its cream description, so the caller composes the runs
    /// (CardInfo does it) and this bakes the laid-out result as one sprite.
    /// Cached like every other bake — keyed on the string's own hash.
    public static func attributedText(_ rich: NSAttributedString,
                                      maxWidth: CGFloat) -> SKTexture {
        let key = AttrKey(hash: rich.hash, length: rich.length, width: Int(maxWidth.rounded()))
        if let cached = attrCache[key] { return cached }
        let bounds = CGSize(width: maxWidth, height: 4096)
        let measured = rich.boundingRect(with: bounds,
                                         options: [.usesLineFragmentOrigin, .usesFontLeading],
                                         context: nil)
        let canvas = CGSize(width: max(1, ceil(measured.width)),
                            height: max(1, ceil(measured.height)))
        let img = image(size: canvas) { cg in
            UIGraphicsPushContext(cg)
            defer { UIGraphicsPopContext() }
            rich.draw(with: CGRect(origin: .zero, size: CGSize(width: maxWidth, height: canvas.height)),
                      options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
        let tex = texture(from: img)
        attrCache[key] = tex
        return tex
    }

    private struct AttrKey: Hashable { let hash: Int; let length: Int; let width: Int }
    private static var attrCache: [AttrKey: SKTexture] = [:]

    /// A ready-to-place label sprite. `anchorPoint` defaults to centre.
    public static func label(_ string: String, size: CGFloat, color: UIColor,
                            display: Bool = false, glow: Bool = false) -> SKSpriteNode {
        let tex = text(string, size: size, color: color, display: display, glow: glow)
        let node = SKSpriteNode(texture: tex)
        node.size = tex.size()
        return node
    }

    // MARK: - Panels (§ the standard container)

    private struct PanelKey: Hashable {
        let w: Int, h: Int, face: UInt32, border: UInt32, shadow: CGFloat, borderWidth: CGFloat
    }
    private static var panelCache: [PanelKey: SKTexture] = [:]

    /// The pixel panel: flat face, `--px` ink border, hard offset shadow with
    /// ZERO blur, square corners. Never a gradient, never a rounded corner.
    public static func panel(size: CGSize,
                             face: UIColor = CRT.feltMid,
                             border: UIColor = CRT.ink,
                             borderWidth: CGFloat = CRT.px,
                             shadowOffset: CGFloat = CRT.shadowOffset) -> SKTexture {
        let key = PanelKey(w: Int(size.width), h: Int(size.height), face: face.packed,
                           border: border.packed, shadow: shadowOffset, borderWidth: borderWidth)
        if let cached = panelCache[key] { return cached }

        // The shadow lives inside the same bitmap, offset down-right.
        let canvas = CGSize(width: size.width + shadowOffset, height: size.height + shadowOffset)
        let img = image(size: canvas) { cg in
            // Hard shadow first, down-RIGHT. In UIKit's flipped image context
            // "down" is +y, so the shadow rect sits at (offset, offset).
            cg.setFillColor(CRT.shadow.cgColor)
            cg.fill(CGRect(x: shadowOffset, y: shadowOffset, width: size.width, height: size.height))
            // Face.
            cg.setFillColor(face.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            // Border, drawn INSIDE the face box so the panel's outer size is exact.
            if borderWidth > 0 {
                cg.setFillColor(border.cgColor)
                let b = borderWidth
                cg.fill(CGRect(x: 0, y: 0, width: size.width, height: b))
                cg.fill(CGRect(x: 0, y: size.height - b, width: size.width, height: b))
                cg.fill(CGRect(x: 0, y: 0, width: b, height: size.height))
                cg.fill(CGRect(x: size.width - b, y: 0, width: b, height: size.height))
            }
        }
        let tex = texture(from: img)
        panelCache[key] = tex
        return tex
    }

    /// A panel sprite whose ANCHOR is the panel's top-left (excluding the
    /// shadow), so layout maths ignores the shadow bleed.
    public static func panelNode(size: CGSize,
                                 face: UIColor = CRT.feltMid,
                                 border: UIColor = CRT.ink,
                                 borderWidth: CGFloat = CRT.px,
                                 shadowOffset: CGFloat = CRT.shadowOffset) -> SKSpriteNode {
        let tex = panel(size: size, face: face, border: border,
                        borderWidth: borderWidth, shadowOffset: shadowOffset)
        let node = SKSpriteNode(texture: tex)
        node.size = tex.size()
        node.anchorPoint = CGPoint(x: 0, y: 1)   // top-left of the whole bitmap
        return node
    }

    // MARK: - Dither tiles (§1 optical mixing)

    private static var ditherCache: [UInt64: SKTexture] = [:]

    /// Intermediate hues exist ONLY as a 2×2 checker of two palette colors.
    /// Flat intermediate hex values are forbidden.
    public static func dither(_ a: UIColor, _ b: UIColor) -> SKTexture {
        let key = UInt64(a.packed) << 32 | UInt64(b.packed)
        if let cached = ditherCache[key] { return cached }
        let img = image(size: CGSize(width: 2, height: 2)) { cg in
            cg.setFillColor(a.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
            cg.fill(CGRect(x: 1, y: 1, width: 1, height: 1))
            cg.setFillColor(b.cgColor)
            cg.fill(CGRect(x: 1, y: 0, width: 1, height: 1))
            cg.fill(CGRect(x: 0, y: 1, width: 1, height: 1))
        }
        let tex = texture(from: img)
        ditherCache[key] = tex
        return tex
    }

    /// A dithered fill of arbitrary size, tiled from the 2×2 checker.
    public static func ditheredFill(size: CGSize, _ a: UIColor, _ b: UIColor) -> SKTexture {
        let img = image(size: size) { cg in
            for y in stride(from: 0, to: Int(size.height), by: 1) {
                for x in stride(from: 0, to: Int(size.width), by: 1) {
                    cg.setFillColor(((x + y) % 2 == 0 ? a : b).cgColor)
                    cg.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        return texture(from: img)
    }

    /// Purge the caches (a resize rebuilds every panel at new pixel sizes).
    public static func flushLayoutCaches() {
        panelCache.removeAll(keepingCapacity: true)
    }
}

extension UIColor {
    /// A stable cache key for a color.
    var packed: UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (UInt32(max(0, min(255, r * 255))) << 24)
             | (UInt32(max(0, min(255, g * 255))) << 16)
             | (UInt32(max(0, min(255, b * 255))) << 8)
             |  UInt32(max(0, min(255, a * 255)))
    }
}
