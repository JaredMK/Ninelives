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

    public static func attributed(_ text: String, size: CGFloat, color: UIColor,
                                  display: Bool = false, glow: Bool = false) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [
            .font: CRT.Font.of(size, display: display),
            .foregroundColor: color,
        ]
        if glow {
            let s = NSShadow()
            s.shadowColor = CRT.phosphor.withAlphaComponent(CRT.glowAlpha)
            s.shadowBlurRadius = CRT.glowRadius
            s.shadowOffset = .zero
            attrs[.shadow] = s
        }
        return NSAttributedString(string: text, attributes: attrs)
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

    public init(_ title: String, role: Role = .plain, fontSize: CGFloat = 19) {
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
    @objc private func touchDown() { pressed = true; setNeedsLayout(); layoutIfNeeded() }
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

    private static var cache: [String: UIImage] = [:]
    static func bake(size: CGSize) -> UIImage {
        let key = "\(Int(size.width))x\(Int(size.height))"
        if let c = cache[key] { return c }
        let img = PixelTexture.image(size: size) { cg in
            cg.setFillColor(UIColor.black.withAlphaComponent(0.13).cgColor)
            var y: CGFloat = 0
            while y < size.height {
                cg.fill(CGRect(x: 0, y: y, width: size.width, height: 1))
                y += 2
            }
            let cx = size.width * 0.5, cy = size.height * 0.45
            let rx = size.width * 0.70, ry = size.height * 0.525
            let steps = 22
            for i in 0..<steps {
                let t0 = 0.62 + (1.0 - 0.62) * (CGFloat(i) / CGFloat(steps))
                let t1 = 0.62 + (1.0 - 0.62) * (CGFloat(i + 1) / CGFloat(steps))
                let alpha = 0.28 * (CGFloat(i + 1) / CGFloat(steps))
                cg.setFillColor(UIColor.black.withAlphaComponent(alpha).cgColor)
                let outer = CGRect(x: cx - rx * t1, y: cy - ry * t1, width: rx * t1 * 2, height: ry * t1 * 2)
                let inner = CGRect(x: cx - rx * t0, y: cy - ry * t0, width: rx * t0 * 2, height: ry * t0 * 2)
                let path = CGMutablePath()
                path.addEllipse(in: outer)
                path.addEllipse(in: inner)
                cg.addPath(path)
                cg.fillPath(using: .evenOdd)
            }
        }
        cache[key] = img
        return img
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
