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
        let img = PixelTexture.image(size: size) { cg in
            // Scanlines: 2px period, rgba(0,0,0,0.13) on the first row.
            cg.setFillColor(UIColor.black.withAlphaComponent(0.13).cgColor)
            var y: CGFloat = 0
            while y < size.height {
                cg.fill(CGRect(x: 0, y: y, width: size.width, height: 1))
                y += 2
            }
            // Corner vignette: ellipse 140% × 105% at 50% 45%, transparent to
            // 62%, then out to rgba(0,0,0,0.28). Drawn as concentric rings so
            // there is no gradient object and no blur — just flat steps on the
            // pixel grid, which is also more honest to the aesthetic.
            let cx = size.width * 0.5, cy = size.height * 0.45
            let rx = size.width * 0.70, ry = size.height * 0.525   // 140%/105% diameters
            let steps = 22
            for i in 0..<steps {
                let t0 = 0.62 + (1.0 - 0.62) * (CGFloat(i) / CGFloat(steps))
                let t1 = 0.62 + (1.0 - 0.62) * (CGFloat(i + 1) / CGFloat(steps))
                let alpha = 0.28 * (CGFloat(i + 1) / CGFloat(steps))
                cg.setFillColor(UIColor.black.withAlphaComponent(alpha).cgColor)
                // Ring = outer ellipse minus inner ellipse, via even-odd fill.
                let outer = CGRect(x: cx - rx * t1, y: cy - ry * t1, width: rx * t1 * 2, height: ry * t1 * 2)
                let inner = CGRect(x: cx - rx * t0, y: cy - ry * t0, width: rx * t0 * 2, height: ry * t0 * 2)
                let path = CGMutablePath()
                path.addEllipse(in: outer)
                path.addEllipse(in: inner)
                cg.addPath(path)
                cg.fillPath(using: .evenOdd)
            }
        }
        let tex = PixelTexture.texture(from: img)
        cache[key] = tex
        return tex
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
