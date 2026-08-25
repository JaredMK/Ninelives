import UIKit
import SpriteKit
import GameCore

/// CRT CASINO chrome for UIKit screens (map, store, menus). The SpriteKit board
/// bakes textures; these views bake the SAME recipes into UIImages, so every
/// screen shares one look: flat faces, 2px ink borders, hard offset shadows,
/// square corners, VT323 body + Press Start 2P display, phosphor-only glow.
public enum CRTKit {

    /// A body-font label. Glow is drawn INTO the string via NSShadow — a baked
    /// halo, never a live layer effect.
    public static func label(_ text: String, size: CGFloat, color: UIColor = CRT.cardFace,
                             display: Bool = false, glow: Bool = false) -> UILabel {
        let l = UILabel()
        l.attributedText = attributed(text, size: size, color: color, display: display, glow: glow)
        l.numberOfLines = 0
        return l
    }

    /// `bold` FAUX-BOLDS the body face (v6.83). VT323 ships no bold cut, and
    /// the display face reads far heavier than VT323 at the same point size —
    /// so a "bold" sticker name drawn in the display face looked like a
    /// different, much larger type step next to its description. A negative
    /// stroke width strokes the glyphs in their own colour: same font, same
    /// size, same metrics, heavier ink.
    public static func attributed(_ text: String, size: CGFloat, color: UIColor,
                                  display: Bool = false, glow: Bool = false,
                                  bold: Bool = false) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: CRT.Font.of(size, display: display),
            .foregroundColor: color,
        ]
        if bold {
            attrs[.strokeColor] = color
            attrs[.strokeWidth] = -2.0      // negative = stroke AND fill
        }
        if glow {
            let s = NSShadow()
            s.shadowColor = CRT.phosphor.withAlphaComponent(CRT.glowAlpha)
            s.shadowBlurRadius = CRT.glowRadius
            s.shadowOffset = .zero
            attrs[.shadow] = s
        }
        // Every suit character becomes the game's own pixel mark (v6.66) —
        // neither game font carries ♠♥♦♣, so the system fallback glyph was
        // leaking into every label that named a suit.
        return PixelGlyph.substituteSuits(NSAttributedString(string: text, attributes: attrs),
                                          size: size, color: color)
    }

    /// The §1 dither tile as a UIColor pattern.
    public static func ditherColor(_ a: UIColor, _ b: UIColor) -> UIColor {
        let img = PixelTexture.image(size: CGSize(width: 2, height: 2)) { cg in
            cg.setFillColor(a.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
            cg.fill(CGRect(x: 1, y: 1, width: 1, height: 1))
            cg.setFillColor(b.cgColor)
            cg.fill(CGRect(x: 1, y: 0, width: 1, height: 1))
            cg.fill(CGRect(x: 0, y: 1, width: 1, height: 1))
        }
        return UIColor(patternImage: img)
    }
}

/// Bounds-safe indexing for the UI layer (GameCore keeps its own internal twin).
extension Array {
    subscript(safe i: Int) -> Element? {
        indices.contains(i) ? self[i] : nil
    }
}

/// The pixel panel as a UIView: flat face, ink border, hard ↘ shadow — all
/// drawn by sublayers (zero images, resizes for free, still zero live effects).
public final class PixelPanelView: UIView {
    private let shadowLayer = CALayer()
    private let faceLayer = CALayer()
    public var face: UIColor { didSet { faceLayer.backgroundColor = face.cgColor } }
    public var border: UIColor { didSet { faceLayer.borderColor = border.cgColor } }
    public var shadowOffsetPx: CGFloat { didSet { setNeedsLayout() } }

    public init(face: UIColor = CRT.feltMid, border: UIColor = CRT.ink,
                shadowOffsetPx: CGFloat = CRT.shadowOffset, borderWidth: CGFloat = CRT.px) {
        self.face = face; self.border = border; self.shadowOffsetPx = shadowOffsetPx
        super.init(frame: .zero)
        shadowLayer.backgroundColor = CRT.shadow.cgColor
        faceLayer.backgroundColor = face.cgColor
        faceLayer.borderColor = border.cgColor
        faceLayer.borderWidth = borderWidth
        layer.addSublayer(shadowLayer)
        layer.addSublayer(faceLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    public override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowLayer.frame = bounds.offsetBy(dx: shadowOffsetPx, dy: shadowOffsetPx)
        faceLayer.frame = bounds
        CATransaction.commit()
    }
}

/// §4 pixel button for UIKit: rest / pressed (sink 2px, shadow halves) /
/// disabled, in the same roles as the SpriteKit `PixelButton`.
public final class PixelButtonView: UIControl {
    public enum Role { case cta, ctaOutline, charged, gold, danger, plain }

    private let shadowLayer = CALayer()
    private let faceLayer = CALayer()
    private let titleLabel = UILabel()
    private var role: Role
    private var fontSize: CGFloat
    public var onTap: (() -> Void)?
    /// Every pixel button clicks on press (the shared UI-family click). Set
    /// false on buttons that own a louder cue of their own (CTA confirms), so
    /// the two don't stack into mush.
    public var playsClick = true

    public init(_ title: String, role: Role = .plain, fontSize: CGFloat = CRT.Font.heading) {
        self.role = role
        self.fontSize = fontSize
        super.init(frame: .zero)
        shadowLayer.backgroundColor = CRT.shadow.cgColor
        faceLayer.borderWidth = CRT.px
        layer.addSublayer(shadowLayer)
        layer.addSublayer(faceLayer)
        titleLabel.textAlignment = .center
        addSubview(titleLabel)
        setTitle(title)
        applyRole()
        // Real buttons to assistive tech AND the UI test runner.
        isAccessibilityElement = true
        accessibilityTraits = .button
        addTarget(self, action: #selector(touchDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside])
        addTarget(self, action: #selector(touchCancel), for: [.touchUpOutside, .touchCancel, .touchDragExit])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    public func setTitle(_ t: String) {
        let (_, text, _, glow) = colors()
        titleLabel.attributedText = CRTKit.attributed(t.uppercased(), size: fontSize, color: text, glow: glow)
        accessibilityLabel = t.uppercased()
    }

    /// A small leading pixel icon beside the label (the web menu buttons).
    private var iconView: UIImageView?
    public func setIcon(_ image: UIImage?) {
        iconView?.removeFromSuperview()
        iconView = nil
        guard let image else { return }
        let iv = UIImageView(image: image)
        iv.layer.magnificationFilter = .nearest
        iv.contentMode = .scaleAspectFit
        addSubview(iv)
        iconView = iv
        setNeedsLayout()
    }
    public var title: String { titleLabel.attributedText?.string ?? "" }

    public func setRole(_ r: Role) { role = r; applyRole() }

    public override var isEnabled: Bool { didSet { applyRole() } }

    private func colors() -> (UIColor, UIColor, UIColor, Bool) {
        if !isEnabled { return (CRT.feltMid, CRT.disabledText, CRT.ink, false) }
        switch role {
        case .cta:        return (CRT.phosphor, CRT.ink, CRT.ink, false)
        case .ctaOutline: return (CRT.feltDeep, CRT.phosphor, CRT.ink, true)
        case .charged:    return (CRT.feltDeep, CRT.phosphor, CRT.phosphor, true)
        case .gold:       return (CRT.feltDeep, CRT.gold, CRT.gold, false)
        case .danger:     return (CRT.suitRed, CRT.cardFace, CRT.ink, false)
        case .plain:      return (CRT.feltMid, CRT.cardFace, CRT.ink, false)
        }
    }

    private func applyRole() {
        let (face, text, border, glow) = colors()
        faceLayer.backgroundColor = face.cgColor
        faceLayer.borderColor = border.cgColor
        if let t = titleLabel.attributedText?.string {
            titleLabel.attributedText = CRTKit.attributed(t, size: fontSize, color: text, glow: glow)
        }
        setNeedsLayout()
    }

    private var pressed = false
    @objc private func touchDown() {
        pressed = true
        if isEnabled, playsClick { Sound.shared.button() }
        setNeedsLayout(); layoutIfNeeded()
    }
    @objc private func touchUp() { pressed = false; setNeedsLayout(); onTap?(); sendActions(for: .primaryActionTriggered) }
    @objc private func touchCancel() { pressed = false; setNeedsLayout() }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let sink: CGFloat = (pressed && isEnabled) ? CRT.pressSink : 0
        let shadow: CGFloat = (pressed || !isEnabled) ? CRT.pressSink : shadowOffset
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        faceLayer.frame = bounds.offsetBy(dx: sink, dy: sink)
        shadowLayer.frame = bounds.offsetBy(dx: shadow, dy: shadow)
        CATransaction.commit()
        titleLabel.frame = bounds.offsetBy(dx: sink, dy: sink)
        if let iv = iconView {
            // Centre the icon+label pair together, like the web buttons.
            let textW = titleLabel.attributedText.map { ceil($0.size().width) } ?? 0
            let iw = iv.image?.size.width ?? 0
            let pair = iw + 7 + textW
            iv.frame = CGRect(x: (bounds.width - pair) / 2 + sink,
                              y: (bounds.height - (iv.image?.size.height ?? 0)) / 2 + sink,
                              width: iw, height: iv.image?.size.height ?? 0)
            titleLabel.textAlignment = .left
            titleLabel.frame = CGRect(x: iv.frame.maxX + 7, y: sink,
                                      width: bounds.width - iv.frame.maxX - 7,
                                      height: bounds.height)
        } else {
            titleLabel.textAlignment = .center
        }
    }
    public var shadowOffset: CGFloat = CRT.shadowOffset
}

/// §2 CRT treatment for UIKit screens — the same baked scanline+vignette bitmap
/// the SpriteKit overlay uses, as one static pointer-inert image view.
public final class CRTOverlayUIView: UIImageView {
    public init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        contentMode = .scaleToFill
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    private var bakedSize: CGSize = .zero
    public override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != bakedSize, bounds.width > 0 else { return }
        bakedSize = bounds.size
        image = CRTOverlayUIView.bake(size: bounds.size)
    }

    /// One-shot flicker (240ms steps(4)) — big events only.
    public func flicker() {
        layer.removeAnimation(forKey: "flicker")
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = [1.0, 0.72, 1.0, 0.85, 1.0]
        a.keyTimes = [0, 0.25, 0.4, 0.6, 1]
        a.duration = 0.24
        a.calculationMode = .discrete
        layer.add(a, forKey: "flicker")
    }

    static func bake(size: CGSize) -> UIImage {
        // One bake, one source: the SpriteKit CRTOverlay's shared image —
        // a SMOOTH radial vignette under the scanlines, no rings.
        CRTOverlay.bakeImage(size: size)
    }
}

/// #tissue — the web's fixed, behind-everything atmosphere layer (index.html
/// ~5267), baked static: flat feltDeep base, two felt-mid whisper radials,
/// the felt-nap dither (feltMid checker dots at a 4px period — the web GIF's
/// second palette index is TRANSPARENT, so only the mid dots paint), and the
/// three soft haze blobs at 0.22 (the web drifts them on a 46s loop; a static
/// bake keeps the idle look with zero per-frame work — §10). The vein strokes
/// are deliberately omitted (barely-there even on the web). Baked once per
/// size, cached, pointer-inert.
public final class TissueView: UIImageView {
    public init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        contentMode = .scaleToFill
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    private var bakedSize: CGSize = .zero
    public override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != bakedSize, bounds.width > 0 else { return }
        bakedSize = bounds.size
        image = TissueView.bake(size: bounds.size)
    }

    private static var cache: [String: UIImage] = [:]

    public static func bake(size: CGSize) -> UIImage {
        let key = "\(Int(size.width))x\(Int(size.height))"
        if let c = cache[key] { return c }
        let img = PixelTexture.image(size: size) { cg in
            let w = size.width, h = size.height
            // Base: flat feltDeep (the web's third radial collapses — all the
            // felt tokens ARE deep felt under CRT CASINO).
            cg.setFillColor(CRT.feltDeep.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            // Whisper radials: feltMid 0.5 → feltMid 0. A CSS circle-gradient
            // percentage resolves against diagonal/√2.
            let diag = hypot(w, h) / 1.4142135623730951
            func whisper(_ fx: CGFloat, _ fy: CGFloat, _ frac: CGFloat) {
                let g = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [CRT.feltMid.withAlphaComponent(0.5).cgColor,
                             CRT.feltMid.withAlphaComponent(0).cgColor] as CFArray,
                    locations: [0, 1])!
                let c = CGPoint(x: w * fx, y: h * fy)
                cg.drawRadialGradient(g, startCenter: c, startRadius: 0,
                                      endCenter: c, endRadius: frac * diag, options: [])
            }
            whisper(0.28, 0.22, 0.46)
            whisper(0.78, 0.72, 0.48)

            // Felt nap: 4px-period checker, feltMid dots only (2×2px blocks on
            // the diagonal of each 4px cell — the web tile's other two pixels
            // are transparent).
            cg.setFillColor(CRT.feltMid.cgColor)
            for y in stride(from: 0, to: Int(h), by: 4) {
                for x in stride(from: 0, to: Int(w), by: 4) {
                    cg.fill(CGRect(x: x, y: y, width: 2, height: 2))
                    cg.fill(CGRect(x: x + 2, y: y + 2, width: 2, height: 2))
                }
            }

            // Haze blobs: feltMid 0.22 → 0 at 68% radius, at the web's
            // .b1/.b2/.b3 positions (squares sized in vw, so the y-centre uses
            // the WIDTH too).
            func blob(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
                let g = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [CRT.feltMid.withAlphaComponent(0.22).cgColor,
                             CRT.feltMid.withAlphaComponent(0).cgColor] as CFArray,
                    locations: [0, 1])!
                let c = CGPoint(x: cx, y: cy)
                cg.drawRadialGradient(g, startCenter: c, startRadius: 0,
                                      endCenter: c, endRadius: r * 0.68, options: [])
            }
            blob(0.06 * w + 0.23 * w, 0.12 * h + 0.23 * w, 0.23 * w)   // .b1 46vw @ 6%/12%
            blob(0.52 * w + 0.28 * w, 0.52 * h + 0.28 * w, 0.28 * w)   // .b2 56vw @ 52%/52%
            blob(0.24 * w + 0.25 * w, 0.78 * h + 0.25 * w, 0.25 * w)   // .b3 50vw @ 24%/78%
        }
        cache[key] = img
        return img
    }

    /// The same bake as a nearest-neighbour SK texture, for the deal scene.
    public static func texture(size: CGSize) -> SKTexture {
        PixelTexture.texture(from: bake(size: size))
    }
}

/// A UIKit traveling card — the same eased arc as the board's flyCard, for
/// screens outside SpriteKit (map collects, store→deck flights).
public enum UIFly {
    public static func fly(_ view: UIView, in container: UIView, from: CGPoint, to: CGPoint,
                           duration: TimeInterval = 0.3, delay: TimeInterval = 0,
                           startScale: CGFloat = 0.65, onArrive: (() -> Void)? = nil) {
        container.addSubview(view)
        view.center = from
        view.transform = CGAffineTransform(scaleX: startScale, y: startScale)
        let dist = hypot(to.x - from.x, to.y - from.y)
        let lift = min(34, max(10, dist * 0.16))
        UIView.animateKeyframes(withDuration: duration, delay: delay, options: [.calculationModeCubic]) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.55) {
                view.center = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 - lift)
                view.transform = .identity
            }
            UIView.addKeyframe(withRelativeStartTime: 0.55, relativeDuration: 0.29) {
                view.center = CGPoint(x: to.x + (to.x - from.x) * 0.02, y: to.y + (to.y - from.y) * 0.02)
                view.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.84, relativeDuration: 0.16) {
                view.center = to
                view.transform = .identity
            }
        } completion: { _ in
            view.removeFromSuperview()
            onArrive?()
        }
    }
}
