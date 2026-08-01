import SpriteKit
import GameCore

/// One pile — a life. Renders the top card, the stacked-depth hint beneath it,
/// the count plaque, the dead mark, sticker badges and the selection ring.
///
/// Every visual is a pre-baked sprite; nothing here measures or lays out per
/// frame. `sync(...)` is called only when the pile actually changes.
///
/// A pile can be put on VISUAL HOLD while a traveling card is in flight toward
/// it: engine syncs that arrive mid-flight are deferred, and applied when the
/// flight lands — so the visible top never teleports ahead of the animation.
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
    private var plaqueText = ""
    private let badgeRow = SKNode()
    private var deadMark: SKSpriteNode?
    private var selectRing: SKSpriteNode?
    /// The fan-out hint: every card in the pile, splayed. Built on demand.
    private var fanNodes: [CardNode] = []
    /// One-shot pulse overlays (good pulse / death flash) sized to the card box.
    private let pulseOverlay: SKSpriteNode
    /// The finger-tracking drag nudge rides on the card only.
    private var dragOffset: CGPoint = .zero

    // MARK: Visual hold

    private struct PendingFace {
        var top: LiveCard?
        var dead: Bool
    }
    private var held = false
    private var pending: PendingFace?

    public var boxSize: CGSize { cardScale.size }

    public init(index: Int, scale: CardArt.Scale) {
        self.index = index
        self.cardScale = scale
        self.card = CardNode(face: CardArt.Face(label: "", suit: "", kind: .back(deckId: "pink")), scale: scale)
        self.pulseOverlay = SKSpriteNode(color: .clear, size: scale.size)
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
        pulseOverlay.anchorPoint = CGPoint(x: 0, y: 1)
        pulseOverlay.zPosition = Layer.card + 1
        pulseOverlay.alpha = 0
        addChild(pulseOverlay)
        plaque.zPosition = Layer.card + 2
        addChild(plaque)
        badgeRow.zPosition = Layer.card + 3
        addChild(badgeRow)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    // MARK: - Sync

    /// Push the pile's current state in. Only touches nodes that changed.
    ///
    /// While HELD, the FACE (top card, badges, dead look) is deferred until
    /// `endHold()` — the web repaints counts/HUD immediately on a resolve but
    /// swaps the visible card only when the traveling card lands. Counts,
    /// slivers and the plaque always apply now.
    public func sync(top: LiveCard?, count: Int, dead: Bool, deckId: String,
                     weighted: Int, anchored: Bool) {
        cardCount = count
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
        syncPlaque(weighted: weighted, anchored: anchored)
        if held {
            pending = PendingFace(top: top, dead: dead)
            return
        }
        applyFace(top: top, dead: dead)
    }

    private func applyFace(top: LiveCard?, dead: Bool, animateDeath: Bool = false) {
        // Top card face (a dead pile keeps showing the card that killed it).
        if let top {
            card.setFace(CardArt.Face(top))
            card.isHidden = false
        } else {
            card.isHidden = true
        }
        setDead(dead, animated: animateDeath)
        syncStickerBadges(top)
    }

    /// Begin deferring face changes — a traveling card owns this pile now.
    public func beginHold() { held = true }

    /// Land: apply whatever face arrived during the hold. `suppressDead` keeps
    /// the instant dead-repaint back so the death sequence (flash → dissolve)
    /// can show it in its own time.
    public func endHold(suppressDead: Bool = false) {
        held = false
        guard let p = pending else { return }
        pending = nil
        if suppressDead && p.dead {
            applyFace(top: p.top, dead: false)
        } else {
            applyFace(top: p.top, dead: p.dead)
        }
    }
    public var isHeld: Bool { held }

    private func setDead(_ dead: Bool, animated: Bool = false) {
        guard dead != isDead || (dead && deadMark == nil) else { return }
        isDead = dead
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
            if animated {
                // The dissolve: the card dims down and the X fades in together.
                card.colorBlendFactor = 0
                card.color = CRT.feltDeep
                card.run(.customDim(to: 0.55, duration: 0.22))
                deadMark?.alpha = 0
                deadMark?.isHidden = false
                deadMark?.run(.fadeIn(withDuration: 0.22))
            } else {
                card.colorBlendFactor = 0.55
                card.color = CRT.feltDeep
                deadMark?.alpha = 1
                deadMark?.isHidden = false
            }
        } else {
            card.removeAction(forKey: "dim")
            card.colorBlendFactor = 0
            deadMark?.isHidden = true
        }
    }

    /// The pile-count chip: a GOLD-framed cream chip riding the card's
    /// bottom-LEFT corner (the web's on-card plaque). Shows the WEIGHTED size
    /// — the same number every payout factor reads. A change POPS.
    private func syncPlaque(weighted: Int, anchored: Bool) {
        let text = anchored ? "\(weighted)⚓" : "\(weighted)"
        let changed = text != plaqueText && !plaqueText.isEmpty
        plaqueText = text
        plaqueBg?.removeFromParent()
        plaqueLabel?.removeFromParent()
        let ns = text as NSString
        let font = CRT.Font.of(14)
        let tsz = ns.size(withAttributes: [.font: font])
        let w = max(20, tsz.width + 8), h: CGFloat = 18
        let img = PixelTexture.image(size: CGSize(width: w + 2, height: h + 2)) { cg in
            cg.setFillColor(CRT.shadow.cgColor)
            cg.fill(CGRect(x: 2, y: 2, width: w, height: h))
            cg.setFillColor(CRT.cardFace.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
            cg.setFillColor((anchored ? CRT.phosphor : CRT.gold).cgColor)
            for r in [CGRect(x: 0, y: 0, width: w, height: 2), CGRect(x: 0, y: h - 2, width: w, height: 2),
                      CGRect(x: 0, y: 0, width: 2, height: h), CGRect(x: w - 2, y: 0, width: 2, height: h)] { cg.fill(r) }
            UIGraphicsPushContext(cg)
            ns.draw(at: CGPoint(x: (w - tsz.width) / 2, y: (h - tsz.height) / 2),
                    withAttributes: [.font: font, .foregroundColor: CRT.ink])
            UIGraphicsPopContext()
        }
        let chip = SKSpriteNode(texture: PixelTexture.texture(from: img))
        chip.size = img.size
        chip.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        chip.position = CGPoint(x: 6 + w / 2, y: -cardScale.size.height + 4)
        plaque.addChild(chip)
        plaqueBg = chip
        plaque.isHidden = cardCount == 0
        if changed {
            // The number pop — a quick scale beat marks the change.
            plaque.removeAction(forKey: "pop")
            plaque.setScale(1.0)
            plaque.run(.sequence([.scale(to: 1.3, duration: 0.09),
                                  .scale(to: 1.0, duration: 0.12)]), withKey: "pop")
        }
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

    // MARK: - Cascade visibility

    /// Hide the pile's content for the deal-out cascade (the board reads blank
    /// until each pile's traveling card lands).
    public func setContentHidden(_ hidden: Bool) {
        card.isHidden = hidden || cardCount == 0
        plaque.isHidden = hidden || cardCount == 0
        badgeRow.isHidden = hidden
        for s in depthSlivers where hidden { s.isHidden = true }
        if !hidden {
            // Re-show slivers per the current count.
            let buried = max(0, cardCount - 1)
            for (i, s) in depthSlivers.enumerated() { s.isHidden = !(i < min(3, buried)) }
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
                let n = SKSpriteNode(texture: BoardFX.ringTexture(size: box, color: CRT.phosphor, weight: CRT.px))
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

    // MARK: - Drag nudge (press feedback tracks the finger)

    /// Nudge the card toward the drag, capped to a whisker — press feedback
    /// that follows the finger without ever leaving the pile.
    public func setDragNudge(dx: CGFloat, dy: CGFloat) {
        let cap: CGFloat = 7
        let nx = max(-cap, min(cap, dx * 0.18))
        let ny = max(-cap, min(cap, dy * 0.18))
        dragOffset = CGPoint(x: nx, y: ny)
        card.position = CGPoint(x: nx, y: ny)
    }

    public func clearDragNudge() {
        guard dragOffset != .zero else { return }
        dragOffset = .zero
        card.removeAction(forKey: "nudge")
        card.run(.move(to: .zero, duration: 0.12), withKey: "nudge")
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

    /// A landing pop with squash — the card settles onto the pile.
    public func landPop() {
        card.removeAction(forKey: "pop")
        BoardFX.squashSettle(card)
    }

    /// The good pulse: a quick phosphor wash over the card (the web's
    /// `.flash-good`, 0.5s ease).
    public func goodPulse() {
        pulseOverlay.removeAction(forKey: "pulse")
        pulseOverlay.size = cardScale.size
        pulseOverlay.color = CRT.phosphor
        pulseOverlay.colorBlendFactor = 1
        pulseOverlay.alpha = 0
        pulseOverlay.run(.sequence([
            .fadeAlpha(to: 0.34, duration: 0.10),
            .fadeAlpha(to: 0, duration: 0.40),
        ]), withKey: "pulse")
    }

    /// The death flash: a hard suit-red wash (the web's `.death-flash`, 0.32s),
    /// before the dissolve.
    public func deathFlash() {
        pulseOverlay.removeAction(forKey: "pulse")
        pulseOverlay.size = cardScale.size
        pulseOverlay.color = CRT.suitRed
        pulseOverlay.colorBlendFactor = 1
        pulseOverlay.alpha = 0
        pulseOverlay.run(.sequence([
            .fadeAlpha(to: 0.52, duration: 0.07),
            .fadeAlpha(to: 0, duration: 0.25),
        ]), withKey: "pulse")
    }

    /// Apply the dead look with the dissolve animation (X fades in, card dims).
    public func dissolveToDead() {
        setDead(true, animated: true)
    }
}

private extension SKAction {
    /// Animate a sprite's colorBlendFactor — the card dim used by the dissolve.
    static func customDim(to factor: CGFloat, duration: TimeInterval) -> SKAction {
        SKAction.colorize(with: CRT.feltDeep, colorBlendFactor: factor, duration: duration)
    }
}
