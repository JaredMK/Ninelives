import SpriteKit
import GameCore

/// §4 Buttons — the pixel button recipe, every state.
///
/// Rest: 2px ink border + 4px hard shadow, face color per role.
/// Pressed: translate(2px, 2px) + shadow 2px — the button "sinks" one step.
/// Disabled: felt-mid face, 45% text, shadow 2px, no glow.
public final class PixelButton: SKNode {

    public enum Role {
        case cta            // phosphor fill, ink text — the loudest thing on screen
        case ctaOutline     // deep felt face, phosphor text + glow (Same, ready)
        case charged        // deep felt, phosphor border + text + glow (Same, charged)
        case gold           // deep felt face, gold text + border
        case danger         // suit-red face
        case plain          // felt mid face, cream text
    }

    public let id: String
    public private(set) var isEnabled = true
    public private(set) var isPressed = false
    private var role: Role
    private var title: String
    private var boxSize: CGSize
    private let bg = SKSpriteNode()
    private var label: SKSpriteNode?
    private let fontSize: CGFloat

    public init(id: String, title: String, size: CGSize, role: Role = .plain, fontSize: CGFloat = 20) {
        self.id = id; self.title = title; self.boxSize = size; self.role = role; self.fontSize = fontSize
        super.init()
        bg.anchorPoint = CGPoint(x: 0, y: 1)
        bg.zPosition = 0
        addChild(bg)
        zPosition = Layer.chrome
        redraw()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    public var frameSize: CGSize { boxSize }
    public var currentRole: Role { role }

    public func setRole(_ r: Role) { guard r != role else { return }; role = r; redraw() }
    public func setTitle(_ t: String) { guard t != title else { return }; title = t; redraw() }
    public func setEnabled(_ on: Bool) { guard on != isEnabled else { return }; isEnabled = on; redraw() }
    public func resize(_ s: CGSize) { guard s != boxSize else { return }; boxSize = s; redraw() }

    public func setPressed(_ on: Bool) {
        guard on != isPressed, isEnabled else { return }
        isPressed = on
        redraw()
    }

    private func redraw() {
        let (face, text, border, glow): (UIColor, UIColor, UIColor, Bool)
        if !isEnabled {
            (face, text, border, glow) = (CRT.feltMid, CRT.disabledText, CRT.ink, false)
        } else {
            switch role {
            case .cta:        (face, text, border, glow) = (CRT.phosphor, CRT.ink, CRT.ink, false)
            case .ctaOutline: (face, text, border, glow) = (CRT.feltDeep, CRT.phosphor, CRT.ink, true)
            case .charged:    (face, text, border, glow) = (CRT.feltDeep, CRT.phosphor, CRT.phosphor, true)
            case .gold:       (face, text, border, glow) = (CRT.feltDeep, CRT.gold, CRT.gold, false)
            case .danger:     (face, text, border, glow) = (CRT.suitRed, CRT.cardFace, CRT.ink, false)
            case .plain:      (face, text, border, glow) = (CRT.feltMid, CRT.cardFace, CRT.ink, false)
            }
        }
        // Disabled and pressed both halve the shadow.
        let shadow: CGFloat = (!isEnabled || isPressed) ? CRT.pressSink : CRT.shadowOffset
        let tex = PixelTexture.panel(size: boxSize, face: face, border: border, shadowOffset: shadow)
        bg.texture = tex
        bg.size = tex.size()

        label?.removeFromParent()
        let l = PixelTexture.label(title, size: fontSize, color: text, glow: glow)
        l.position = CGPoint(x: boxSize.width / 2, y: -boxSize.height / 2)
        l.zPosition = 1
        addChild(l)
        label = l

        // Pressed sinks the whole button one pixel step (the shadow already halved).
        let sink: CGFloat = isPressed && isEnabled ? CRT.pressSink : 0
        bg.position = CGPoint(x: sink, y: -sink)
        label?.position = CGPoint(x: boxSize.width / 2 + sink, y: -boxSize.height / 2 - sink)
    }

    /// Hit box in this node's parent space.
    public func contains(scenePoint p: CGPoint) -> Bool {
        guard let parent else { return false }
        let local = parent.convert(p, from: scene ?? parent)
        let r = CGRect(x: position.x, y: position.y - boxSize.height,
                       width: boxSize.width, height: boxSize.height)
        return r.insetBy(dx: -6, dy: -6).contains(local)   // a forgiving thumb target
    }
}

/// The deal-status glance row, matching the web exactly:
/// `REWARD +N · SCORE A×B` — the reward's +N in PHOSPHOR, the score PRODUCT
/// (alive piles × smallest pile) in GOLD with the × form.
public final class RewardLine: SKNode {
    private var content = SKNode()
    public override init() { super.init(); addChild(content); zPosition = Layer.chrome }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not supported") }

    public func sync(base: Double, bonus: Double, alive: Int, minAlive: Int, width: CGFloat) {
        content.removeAllChildren()
        // BASE + BONUS, shown apart. Summed into one number, the line couldn't
        // show a sticker or Pillar PAYING you — it just ticked up with no
        // visible cause. Split, the deal opens "4 + 0" and the second figure
        // is visibly what your build is earning you.
        var parts: [(String, UIColor, Bool)] = [
            ("REWARD ", CRT.muted, false),
            ("\(Int(base))", CRT.phosphor, true),
            (" + ", CRT.muted, false),
            ("\(Int(max(0, bonus)))", bonus > 0 ? CRT.gold : CRT.muted, bonus > 0),
        ]
        // A NEGATIVE bonus (a leech taking coins) is its own red term — it is
        // not a smaller bonus, it is money going the other way.
        if bonus < 0 { parts.append((" \(Int(bonus))", CRT.suitRed, false)) }
        parts.append(("  ·  SCORE ", CRT.muted, false))
        parts.append(("\(alive)×\(minAlive)", CRT.gold, false))
        var total: CGFloat = 0
        var nodes: [SKSpriteNode] = []
        for (t, c, glow) in parts where !t.isEmpty {
            // 15/18 → 18/22 (router batch 2): the two numbers the player
            // plays FOR were the smallest text over the board.
            let n = PixelTexture.label(t, size: t.contains("×") ? 22 : 18, color: c, glow: glow)
            n.anchorPoint = CGPoint(x: 0, y: 0.5)
            nodes.append(n); total += n.size.width
        }
        var x = (width - total) / 2
        for n in nodes { n.position = CGPoint(x: x, y: 0); content.addChild(n); x += n.size.width }
    }
}
