import SpriteKit
import GameCore

/// One pile — a life. Renders the top card, the stacked-depth hint beneath it,
/// the count plaque, the dead mark, sticker badges and the selection ring.
///
/// Every visual is a pre-baked sprite; nothing here measures or lays out per
/// frame. `sync(...)` is called only when the pile actually changes.
public final class PileNode: SKNode {

    public let index: Int
    public private(set) var isDead = false
    public private(set) var isSelected = false
    public private(set) var cardCount = 0

    private let cardScale: CardArt.Scale
    private let card: CardNode
    /// Up to 3 offset slivers behind the top card, so a deep pile reads deep.
    private var depthSlivers: [SKSpriteNode] = []
    private let plaque = SKNode()
    private var plaqueBg: SKSpriteNode?
    private var plaqueLabel: SKSpriteNode?
    private let badgeRow = SKNode()
    private var deadMark: SKSpriteNode?
    private var selectRing: SKSpriteNode?
    /// The fan-out hint: every card in the pile, splayed. Built on demand.
    private var fanNodes: [CardNode] = []

    public var boxSize: CGSize { cardScale.size }

    public init(index: Int, scale: CardArt.Scale) {
        self.index = index
        self.cardScale = scale
        self.card = CardNode(face: CardArt.Face(label: "", suit: "", kind: .back(deckId: "pink")), scale: scale)
        super.init()
        // Slivers sit behind the top card; the plaque and badges in front.
        for i in 0..<3 {
            let s = SKSpriteNode(color: CRT.feltDeep, size: CGSize(width: scale.size.width, height: 3))
            s.anchorPoint = CGPoint(x: 0, y: 1)
            s.zPosition = Layer.card - CGFloat(3 - i)
            s.isHidden = true
            addChild(s)
            depthSlivers.append(s)
        }
        addChild(card)
        plaque.zPosition = Layer.card + 2
        addChild(plaque)
        badgeRow.zPosition = Layer.card + 3
        addChild(badgeRow)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    // MARK: - Sync

    /// Push the pile's current state in. Only touches nodes that changed.
    public func sync(top: LiveCard?, count: Int, dead: Bool, deckId: String,
                     weighted: Int, anchored: Bool) {
        cardCount = count
        // Top card face (a dead pile keeps showing the card that killed it).
        if let top {
            card.setFace(CardArt.Face(top))
            card.isHidden = false
        } else {
            card.isHidden = true
        }
        // Depth slivers: one per buried card, capped at 3.
        let buried = max(0, count - 1)
        for (i, s) in depthSlivers.enumerated() {
            let show = i < min(3, buried)
            s.isHidden = !show
            if show {
                let off = CGFloat(i + 1) * 3
                s.position = CGPoint(x: off, y: off)
            }
        }
        setDead(dead)
        syncPlaque(weighted: weighted, anchored: anchored)
        syncStickerBadges(top)
    }

    private func setDead(_ dead: Bool) {
        guard dead != isDead || (dead && deadMark == nil) else { return }
        isDead = dead
        card.colorBlendFactor = dead ? 0.55 : 0
        card.color = CRT.feltDeep
        if dead {
            if deadMark == nil {
                // A hard suit-red X across the card — death is red (§1).
                let s = cardScale.size
                let img = PixelTexture.image(size: s) { cg in
                    cg.setStrokeColor(CRT.suitRed.cgColor)
                    cg.setLineWidth(CRT.px * 2)
                    let pad: CGFloat = 8
                    cg.move(to: CGPoint(x: pad, y: pad))
                    cg.addLine(to: CGPoint(x: s.width - pad, y: s.height - pad))
                    cg.move(to: CGPoint(x: s.width - pad, y: pad))
                    cg.addLine(to: CGPoint(x: pad, y: s.height - pad))
                    cg.strokePath()
                }
                let n = SKSpriteNode(texture: PixelTexture.texture(from: img))
                n.anchorPoint = CGPoint(x: 0, y: 1)
                n.zPosition = Layer.card + 1
                addChild(n)
                deadMark = n
            }
            deadMark?.isHidden = false
        } else {
            deadMark?.isHidden = true
        }
    }

    /// The pile-count plaque. Shows the WEIGHTED size (Heavy stickers count
    /// extra) — the same number every payout factor reads.
    private func syncPlaque(weighted: Int, anchored: Bool) {
        let text = anchored ? "\(weighted)⚓" : "\(weighted)"
        let label = PixelTexture.label(text, size: 14, color: anchored ? CRT.gold : CRT.cardFace)
        if plaqueBg == nil {
            let bg = SKSpriteNode(color: CRT.feltMid, size: .zero)
            bg.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            bg.zPosition = 0
            plaque.addChild(bg)
            plaqueBg = bg
        }
        plaqueLabel?.removeFromParent()
        label.zPosition = 1
        plaque.addChild(label)
        plaqueLabel = label
        let w = max(18, label.size.width + 8)
        plaqueBg?.size = CGSize(width: w, height: 16)
        // Bottom-centre of the card box.
        let p = CGPoint(x: cardScale.size.width / 2, y: -cardScale.size.height + 9)
        plaqueBg?.position = p
        label.position = p
        plaque.isHidden = cardCount == 0
    }

    /// Sticker badges on the top card — a small chip row along the card's top
    /// edge, one per sticker instance (capped so a heavily-stickered card still
    /// reads as a card).
    private func syncStickerBadges(_ top: LiveCard?) {
        badgeRow.removeAllChildren()
        guard let top, !top.stickers.isEmpty else { return }
        let chip: CGFloat = 8
        let shown = min(top.stickers.count, 5)
        for i in 0..<shown {
            let s = top.stickers[i]
            let def = GameData.shared.stickerTypes.get(s.type)
            // Cursed stickers wear suit-red; everything else gold on ink.
            let tint = (def?.cursed ?? false) ? CRT.suitRed : CRT.gold
            let n = SKSpriteNode(color: tint, size: CGSize(width: chip, height: chip))
            n.anchorPoint = CGPoint(x: 0, y: 1)
            n.position = CGPoint(x: 3 + CGFloat(i) * (chip + 2), y: -3)
            let outline = SKSpriteNode(color: CRT.ink, size: CGSize(width: chip + 2, height: chip + 2))
            outline.anchorPoint = CGPoint(x: 0, y: 1)
            outline.position = CGPoint(x: n.position.x - 1, y: n.position.y + 1)
            outline.zPosition = -1
            badgeRow.addChild(outline)
            badgeRow.addChild(n)
        }
    }

    // MARK: - Selection

    public func setSelected(_ on: Bool) {
        guard on != isSelected else { return }
        isSelected = on
        if on {
            if selectRing == nil {
                let s = cardScale.size
                let pad: CGFloat = 3
                let box = CGSize(width: s.width + pad * 2, height: s.height + pad * 2)
                let img = PixelTexture.image(size: box) { cg in
                    cg.setFillColor(CRT.phosphor.cgColor)
                    let b = CRT.px
                    cg.fill(CGRect(x: 0, y: 0, width: box.width, height: b))
                    cg.fill(CGRect(x: 0, y: box.height - b, width: box.width, height: b))
                    cg.fill(CGRect(x: 0, y: 0, width: b, height: box.height))
                    cg.fill(CGRect(x: box.width - b, y: 0, width: b, height: box.height))
                }
                let n = SKSpriteNode(texture: PixelTexture.texture(from: img))
                n.anchorPoint = CGPoint(x: 0, y: 1)
                n.position = CGPoint(x: -pad, y: pad)
                n.zPosition = Layer.card + 4
                addChild(n)
                selectRing = n
            }
            selectRing?.isHidden = false
        } else {
            selectRing?.isHidden = true
        }
    }

    // MARK: - Fan

    /// Splay every card in the pile face-up (the memory aid). `hint` is the
    /// light global fan; the full fan shows all cards.
    public func showFan(_ cards: [LiveCard], full: Bool) {
        hideFan()
        guard cards.count > 1 else { return }
        let shown = full ? cards : Array(cards.suffix(3))
        // Bottom-of-stack first so the top card stays on top.
        for (i, c) in shown.enumerated() where i < shown.count - 1 {
            let n = CardNode(face: CardArt.Face(c), scale: full ? cardScale : .half)
            let step: CGFloat = full ? 16 : 6
            let off = CGFloat(shown.count - 1 - i) * step
            n.position = CGPoint(x: -off * 0.35, y: off)
            n.zPosition = Layer.card - CGFloat(shown.count - i)
            addChild(n)
            fanNodes.append(n)
        }
    }

    public func hideFan() {
        fanNodes.forEach { $0.removeFromParent() }
        fanNodes.removeAll()
    }

    // MARK: - Feedback

    /// A short hard nudge — used for a wrong guess / a pile dying.
    public func wince() {
        let d = 0.045
        run(.sequence([
            .moveBy(x: -3, y: 0, duration: d), .moveBy(x: 6, y: 0, duration: d * 2),
            .moveBy(x: -6, y: 0, duration: d * 2), .moveBy(x: 3, y: 0, duration: d),
        ]))
    }

    /// A landing pop — the card settles onto the pile.
    public func landPop() {
        card.removeAction(forKey: "pop")
        card.run(.sequence([
            .scale(to: 1.06, duration: 0.06),
            .scale(to: 1.0, duration: 0.09),
        ]), withKey: "pop")
    }
}
