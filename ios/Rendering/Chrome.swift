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

/// §7 Stat bar — recedes into the felt. ONLY the score is phosphor.
public final class HUDBar: SKNode {
    private let bg = SKSpriteNode()
    private var content = SKNode()
    private var width: CGFloat
    public private(set) var height: CGFloat = 30

    /// Frames of the tappable chips, for hold-for-help routing.
    public private(set) var sameChargeRect: CGRect = .zero
    public private(set) var samePowerRect: CGRect = .zero
    public private(set) var scoreRect: CGRect = .zero
    public private(set) var coinRect: CGRect = .zero

    /// Last values, so a change POPS its chip (the number pop).
    private var lastCoins = Int.min
    private var lastScore = Int.min

    public init(width: CGFloat) {
        self.width = width
        super.init()
        bg.anchorPoint = CGPoint(x: 0, y: 1)
        bg.zPosition = 0
        addChild(bg)
        content.zPosition = 1
        addChild(content)
        zPosition = Layer.chrome
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    public func resize(width w: CGFloat) { width = w }

    /// `STG 2·3 | ♥ ♦ ♣ ♠ | = | ◉ 214 | DECK 38 | SCORE 1180`
    public func sync(stageLabel: String, suitsInPlay: [String], sameCharged: Bool,
                     samePower: String?, coins: Int, deckCount: Int, score: Int) {
        let tex = PixelTexture.panel(size: CGSize(width: width, height: height))
        bg.texture = tex; bg.size = tex.size()

        content.removeAllChildren()
        var x: CGFloat = 8
        let midY = -height / 2

        func put(_ node: SKSpriteNode, gap: CGFloat = 8) -> CGRect {
            node.anchorPoint = CGPoint(x: 0, y: 0.5)
            node.position = CGPoint(x: x, y: midY)
            content.addChild(node)
            let r = CGRect(x: x, y: midY - node.size.height / 2,
                           width: node.size.width, height: node.size.height)
            x += node.size.width + gap
            return r
        }

        _ = put(PixelTexture.label(stageLabel, size: 16, color: CRT.muted))
        // The suit phase track: suits in play are cream/red, the rest dimmed.
        for s in ["♥", "♦", "♣", "♠"] {
            let live = suitsInPlay.contains(s)
            let c = live ? CRT.color(forSuit: s) : CRT.cardFace.withAlphaComponent(0.28)
            // ♠/♣ ink is invisible on felt — use cream for the live black suits.
            let shown = (live && (s == "♠" || s == "♣")) ? CRT.cardFace : c
            _ = put(PixelTexture.label(s, size: 17, color: shown), gap: 3)
        }
        x += 5
        // Same Charge — the equals mark; lit gold when banked.
        sameChargeRect = put(PixelTexture.label("=", size: 18,
                                                color: sameCharged ? CRT.gold : CRT.cardFace.withAlphaComponent(0.3)))
        if let samePower, let def = GameData.shared.samePowerTypes.get(samePower) {
            samePowerRect = put(PixelTexture.label(String(def.label.prefix(1)).uppercased(),
                                                   size: 14, color: CRT.gold))
        } else {
            samePowerRect = .zero
        }
        let coinLabel = PixelTexture.label("◉ \(coins)", size: 17, color: CRT.gold)
        coinRect = put(coinLabel)
        _ = put(PixelTexture.label("DECK \(deckCount)", size: 16, color: CRT.muted))

        // Score is the single phosphor element, right-aligned.
        let scoreLabel = PixelTexture.label("SCORE \(score)", size: 17, color: CRT.phosphor, glow: true)
        scoreLabel.anchorPoint = CGPoint(x: 1, y: 0.5)
        scoreLabel.position = CGPoint(x: width - 8, y: midY)
        content.addChild(scoreLabel)
        scoreRect = CGRect(x: width - 8 - scoreLabel.size.width, y: midY - scoreLabel.size.height / 2,
                           width: scoreLabel.size.width, height: scoreLabel.size.height)

        // Number pops: a changed coin/score chip marks its change with a beat.
        if lastCoins != Int.min && coins != lastCoins {
            coinLabel.setScale(1.25)
            coinLabel.run(.scale(to: 1.0, duration: 0.16))
        }
        if lastScore != Int.min && score != lastScore {
            scoreLabel.setScale(1.25)
            scoreLabel.run(.scale(to: 1.0, duration: 0.16))
        }
        lastCoins = coins
        lastScore = score
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
        let reward = Int(base + max(0, bonus))
        var parts: [(String, UIColor, Bool)] = [
            ("REWARD ", CRT.muted, false),
            ("+\(reward)", CRT.phosphor, true),
        ]
        if bonus < 0 { parts.append((" \(Int(bonus))", CRT.suitRed, false)) }
        parts.append(("  ·  SCORE ", CRT.muted, false))
        parts.append(("\(alive)×\(minAlive)", CRT.gold, false))
        var total: CGFloat = 0
        var nodes: [SKSpriteNode] = []
        for (t, c, glow) in parts where !t.isEmpty {
            let n = PixelTexture.label(t, size: t.contains("×") ? 18 : 15, color: c, glow: glow)
            n.anchorPoint = CGPoint(x: 0, y: 0.5)
            nodes.append(n); total += n.size.width
        }
        var x = (width - total) / 2
        for n in nodes { n.position = CGPoint(x: x, y: 0); content.addChild(n); x += n.size.width }
    }
}
