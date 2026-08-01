import SpriteKit

/// §2 CRT treatment — ONE static node above everything.
///
/// The styleguide's implementation note is a perf contract, not a suggestion:
/// *"both background-images static; no filter, no backdrop-filter, no per-frame
/// work."* So this is a single pre-rendered sprite. The scanline + vignette
/// bitmap is baked once per size and never touched again.
///
/// The flicker is the ONE exception: a one-shot 240ms `steps(4)` opacity
/// keyframe, fired ONLY on deal won/lost.
public final class CRTOverlay: SKSpriteNode {

    public init(size: CGSize) {
        let tex = CRTOverlay.bake(size: size)
        super.init(texture: tex, color: .clear, size: size)
        zPosition = Layer.crt
        isUserInteractionEnabled = false   // pointer-events: none
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// Rebuild for a new size (rotation / split view). Still zero per-frame work.
    public func resize(to size: CGSize) {
        texture = CRTOverlay.bake(size: size)
        self.size = size
    }

    /// One-shot flicker. Fired ONLY on deal won/lost — nothing else animates.
    /// `steps(4)` over 240ms, matching the `crt-flicker` keyframe exactly.
    public func flicker() {
        removeAction(forKey: "flicker")
        let frames: [CGFloat] = [1.0, 0.72, 1.0, 0.85, 1.0]
        let step = 0.240 / Double(frames.count)
        let seq = frames.map { a in
            SKAction.sequence([SKAction.fadeAlpha(to: a, duration: 0),
                               SKAction.wait(forDuration: step)])
        }
        run(SKAction.sequence(seq), withKey: "flicker")
    }

    // MARK: - Baking

    private static var cache: [String: SKTexture] = [:]

    private static func bake(size: CGSize) -> SKTexture {
        let key = "\(Int(size.width))x\(Int(size.height))"
        if let c = cache[key] { return c }
        let tex = PixelTexture.texture(from: bakeImage(size: size))
        cache[key] = tex
        return tex
    }

    private static var imageCache: [String: UIImage] = [:]

    /// The CRT bitmap as a UIImage — `CRTOverlayUIView` (UIKit screens) uses
    /// this exact bake so every screen wears the identical overlay.
    public static func bakeImage(size: CGSize) -> UIImage {
        let key = "\(Int(size.width))x\(Int(size.height))"
        if let c = imageCache[key] { return c }
        let img = PixelTexture.image(size: size) { cg in
            // Corner vignette FIRST — on the web it sits UNDER the scanlines
            // (background-image list order). One SMOOTH radial gradient:
            // `radial-gradient(ellipse 140% 105% at 50% 45%, transparent 62%,
            // rgba(0,0,0,0.28) 100%)`. A unit-circle gradient drawn under an
            // affine scale IS the ellipse; .drawsAfterEndLocation holds the
            // 0.28 edge colour out to the corners like the CSS last stop.
            let cx = size.width * 0.5, cy = size.height * 0.45
            let rx = size.width * 0.70, ry = size.height * 0.525   // 140%/105% diameters
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor.clear.cgColor,
                         UIColor.black.withAlphaComponent(0.28).cgColor] as CFArray,
                locations: [0.62, 1.0])!
            cg.saveGState()
            cg.translateBy(x: cx, y: cy)
            cg.scaleBy(x: rx, y: ry)
            cg.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0,
                                  endCenter: .zero, endRadius: 1,
                                  options: .drawsAfterEndLocation)
            cg.restoreGState()
            // Scanlines on top: 2px period, rgba(0,0,0,0.13) on the first row.
            cg.setFillColor(UIColor.black.withAlphaComponent(0.13).cgColor)
            var y: CGFloat = 0
            while y < size.height {
                cg.fill(CGRect(x: 0, y: y, width: size.width, height: 1))
                y += 2
            }
        }
        imageCache[key] = img
        return img
    }
}

/// zPosition bands, so nothing ever fights for depth.
public enum Layer {
    public static let felt: CGFloat      = 0
    public static let web: CGFloat       = 10
    public static let board: CGFloat     = 20
    public static let card: CGFloat      = 30
    public static let chrome: CGFloat    = 60
    public static let float: CGFloat     = 80    // +N cues, swipe label
    public static let overlay: CGFloat   = 100   // pile fan, help popup
    public static let crt: CGFloat       = 900   // the CRT layer, topmost
}
