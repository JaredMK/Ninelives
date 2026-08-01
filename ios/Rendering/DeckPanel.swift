import SpriteKit
import GameCore

/// The deck panel: the rank histogram, the per-suit counts, and the deck
/// character carrying the remaining count.
///
/// In the web's active `thumb-deal` layout this band rides at the TOP, under
/// the HUD: suit counts on the left, rank histogram beside them, deck stack at
/// the end. Same arrangement here.
///
/// The character is a PERSISTENT node — sync never rebuilds it, so its blink
/// loop and reaction holds survive every histogram repaint.
public final class DeckPanel: SKNode {

    private let bg = SKSpriteNode()
    private let histLayer = SKNode()
    private let suitLayer = SKNode()
    private let deckLayer = SKNode()
    /// The living mascot (blinks, looks, reacts) — never rebuilt by sync.
    public let character = DeckCharNode()
    private var countLabel: SKSpriteNode?
    private var lastRemaining = -1
    private var size: CGSize = .zero
    /// The peek chip: the revealed upcoming draw (Scout / peek Pillars).
    private let peekLayer = SKNode()
    private var peekShown: CardArt.Face?

    /// The deck stack's hit box (tap = inspect, hold = quick peek).
    public private(set) var deckRect: CGRect = .zero

    public override init() {
        super.init()
        bg.anchorPoint = CGPoint(x: 0, y: 1)
        // SKView.ignoresSiblingOrder is on (it is a real batching win), so equal
        // zPositions draw in ARBITRARY order — every layer states its own depth.
        bg.zPosition = 0
        addChild(bg)
        histLayer.zPosition = 1; suitLayer.zPosition = 1; deckLayer.zPosition = 1
        addChild(histLayer); addChild(suitLayer); addChild(deckLayer)
        character.zPosition = 2
        addChild(character)
        peekLayer.zPosition = 3
        addChild(peekLayer)
        zPosition = Layer.chrome
    }

    /// Show/clear the revealed NEXT draw beside the deck — the web's deck-reveal
    /// strip. A peek that appears slides in with a small pop.
    public func syncPeek(_ face: CardArt.Face?) {
        guard face != peekShown else { return }
        peekShown = face
        peekLayer.removeAllChildren()
        guard let face else { return }
        let card = CardNode(face: face, scale: .half)
        card.anchorPoint = CGPoint(x: 0, y: 1)
        card.setScale(0.62)
        card.position = CGPoint(x: character.position.x - 38, y: character.position.y + 2)
        peekLayer.addChild(card)
        let tag = PixelTexture.label("NEXT", size: 12, color: CRT.phosphor, glow: true)
        tag.anchorPoint = CGPoint(x: 0.5, y: 1)
        tag.position = CGPoint(x: card.position.x + 15, y: card.position.y - 44)
        peekLayer.addChild(tag)
        card.alpha = 0
        card.run(.group([.fadeIn(withDuration: 0.15),
                         .sequence([.scale(to: 0.7, duration: 0.1), .scale(to: 0.62, duration: 0.1)])]))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    public func resize(to s: CGSize) {
        size = s
        let tex = PixelTexture.panel(size: s)
        bg.texture = tex; bg.size = tex.size()
    }

    /// The character's centre in THIS panel's coordinate space — the deal-out
    /// cascade and every deck→pile flight starts here.
    public var characterCenter: CGPoint {
        CGPoint(x: character.position.x + 16, y: character.position.y - 16)
    }

    /// `counts` is rank value → remaining, `suitCounts` is suit → remaining.
    public func sync(counts: [Int: Int], suitCounts: [String: Int], total: Int,
                     deckRemaining: Int, deckId: String, mood: DeckCharacter.Mood) {
        histLayer.removeAllChildren()
        suitLayer.removeAllChildren()
        deckLayer.removeAllChildren()

        let pad: CGFloat = 8
        // ---- suit counts (left) ----
        var sy: CGFloat = -pad - 6
        for s in ["♥", "♦", "♣", "♠"] {
            let n = suitCounts[s] ?? 0
            let c = (s == "♥" || s == "♦") ? CRT.suitRed : CRT.cardFace
            let label = PixelTexture.label("\(s) \(n)", size: 14, color: n == 0 ? CRT.muted : c)
            label.anchorPoint = CGPoint(x: 0, y: 0.5)
            label.position = CGPoint(x: pad, y: sy)
            suitLayer.addChild(label)
            sy -= 15
        }

        // ---- rank histogram (middle): one column per rank, 2..A left→right ----
        let histX = pad + 46
        let deckW: CGFloat = 62
        let histW = size.width - histX - deckW - pad * 2
        let barW = max(3, (histW - CGFloat(DeckManager.ranks.count - 1) * 2) / CGFloat(DeckManager.ranks.count))
        let maxCount = max(1, counts.values.max() ?? 1)
        let histH = size.height - pad * 2 - 12
        for (i, r) in DeckManager.ranks.enumerated() {
            let n = counts[r.value] ?? 0
            let h = n == 0 ? 2 : max(3, CGFloat(n) / CGFloat(maxCount) * histH)
            let bar = SKSpriteNode(color: n == 0 ? CRT.feltDeep : CRT.cardFace,
                                   size: CGSize(width: barW, height: h))
            bar.anchorPoint = CGPoint(x: 0, y: 0)
            bar.position = CGPoint(x: histX + CGFloat(i) * (barW + 2), y: -size.height + pad + 12)
            histLayer.addChild(bar)
            // Rank tick under the bar (12px floor).
            let tick = PixelTexture.label(r.label, size: 12, color: CRT.muted)
            tick.anchorPoint = CGPoint(x: 0.5, y: 1)
            tick.position = CGPoint(x: bar.position.x + barW / 2, y: -size.height + pad + 11)
            histLayer.addChild(tick)
        }

        // ---- deck stack + character (right) ----
        let charX = size.width - deckW - pad
        character.position = CGPoint(x: charX + 8, y: -pad - 4)
        character.configure(deckId: deckId)
        character.setBaseMood(mood)
        let count = PixelTexture.label("\(deckRemaining)", size: 20, color: CRT.cardFace)
        count.anchorPoint = CGPoint(x: 0, y: 1)
        count.position = CGPoint(x: charX + 8 + 34, y: -pad - 8)
        deckLayer.addChild(count)
        countLabel = count
        let lbl = PixelTexture.label("left", size: 12, color: CRT.muted)
        lbl.anchorPoint = CGPoint(x: 0, y: 1)
        lbl.position = CGPoint(x: charX + 8 + 34, y: -pad - 8 - count.size.height)
        deckLayer.addChild(lbl)

        // Deck-count pop on change (the draw is felt in the number).
        if lastRemaining >= 0 && deckRemaining != lastRemaining {
            count.setScale(1.25)
            count.run(.scale(to: 1.0, duration: 0.14))
        }
        lastRemaining = deckRemaining

        deckRect = CGRect(x: charX, y: -size.height + pad, width: deckW, height: size.height - pad * 2)
    }
}

/// The living deck character. Wraps the baked `DeckCharacter` textures in the
/// web's state machine: transient reactions with holds, a blink loop on a
/// randomized timer, idle glances, an eye-tracking "looking" state, and the
/// celebrate dance. All texture swaps + tiny transforms — no per-frame work.
public final class DeckCharNode: SKNode {

    private let sprite = SKSpriteNode()
    private var deckId = "pink"
    /// The resting mood pushed by the controller (idle-family or sad-family).
    private var baseMood: DeckCharacter.Mood = .idle
    /// The transient reaction currently overriding the base, if any.
    private var reaction: DeckCharacter.Mood?
    /// Quantized eye offset while looking (-1/0/1 each axis).
    private var gaze: (dx: Int, dy: Int) = (0, 0)
    private var looking = false

    public override init() {
        super.init()
        sprite.anchorPoint = CGPoint(x: 0, y: 1)
        addChild(sprite)
        startBlink()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    public func configure(deckId id: String) {
        guard id != deckId else { refresh(); return }
        deckId = id
        refresh()
    }

    /// The slow mood underneath (idle / sad from board state). Reactions and
    /// looking win while they last.
    public func setBaseMood(_ m: DeckCharacter.Mood) {
        guard m != baseMood else { return }
        baseMood = m
        refresh()
    }

    /// Player selected a pile → look toward it (dx/dy is the pile's direction
    /// from the character, quantized to the pixel grid's 3×3 gaze).
    public func lookToward(dx: CGFloat, dy: CGFloat) {
        looking = true
        gaze = (dx < -20 ? -1 : (dx > 20 ? 1 : 0), dy < -20 ? -1 : (dy > 20 ? 1 : 0))
        refresh()
    }

    public func releaseLook() {
        guard looking else { return }
        looking = false
        gaze = (0, 0)
        refresh()
    }

    /// A named transient reaction. Holds mirror the web: happy 1100ms (a Same
    /// won), glad 550ms (any correct guess), sad 1300ms (a pile lost),
    /// celebrate 1500ms (deal cleared — the win dance).
    public func react(_ m: DeckCharacter.Mood) {
        let hold: TimeInterval
        switch m {
        case .happy: hold = 1.1
        case .glad: hold = 0.55
        case .sad: hold = 1.3
        case .celebrate, .win: hold = 1.5
        default: hold = 0
        }
        reaction = m
        refresh()
        removeAction(forKey: "revert")
        if m == .celebrate || m == .win { dance() }
        if hold > 0 {
            run(.sequence([.wait(forDuration: hold), .run { [weak self] in
                self?.reaction = nil
                self?.sprite.removeAction(forKey: "dance")
                self?.sprite.position = .zero
                self?.sprite.zRotation = 0
                self?.refresh()
            }]), withKey: "revert")
        }
    }

    /// Hard reset (new deal).
    public func reset() {
        reaction = nil
        looking = false
        gaze = (0, 0)
        removeAction(forKey: "revert")
        sprite.removeAction(forKey: "dance")
        sprite.position = .zero
        sprite.zRotation = 0
        refresh()
    }

    /// The current expression, resolved: reaction > looking > base.
    private var mood: DeckCharacter.Mood {
        if let reaction { return reaction }
        if looking { return .looking }
        return baseMood
    }

    private func refresh() {
        let tex = DeckCharacter.texture(deckId: deckId, mood: mood, scale: 2,
                                        gaze: looking ? gaze : (0, 0))
        sprite.texture = tex
        sprite.size = tex.size()
    }

    /// The ambient-life loop: blink every 3.2–6.4s, and now and then sneak a
    /// tiny idle glance — the character never reads frozen. Randomized waits
    /// come from `SKAction.wait(forDuration:withRange:)`; the closures run once
    /// per cycle, not per frame.
    private func startBlink() {
        let cycle = SKAction.sequence([
            .wait(forDuration: 4.8, withRange: 3.2),
            .run { [weak self] in self?.blinkOnce() },
        ])
        run(.repeatForever(cycle), withKey: "blink")
    }

    private func blinkOnce() {
        guard reaction == nil else { return }
        let closed = DeckCharacter.texture(deckId: deckId, mood: .blink, scale: 2, gaze: (0, 0))
        let open = DeckCharacter.texture(deckId: deckId, mood: mood, scale: 2,
                                         gaze: looking ? gaze : (0, 0))
        sprite.run(.sequence([
            .setTexture(closed), .wait(forDuration: 0.14), .setTexture(open),
        ]))
        // An occasional idle glance rides the same tick (web: 50% of blinks).
        if !looking, baseMood == .idle, Bool.random() {
            let g = (Int.random(in: -1...1), Int.random(in: -1...1))
            let glanced = DeckCharacter.texture(deckId: deckId, mood: .idle, scale: 2, gaze: g)
            sprite.run(.sequence([
                .wait(forDuration: 0.3),
                .setTexture(glanced),
                .wait(forDuration: 1.0),
                .run { [weak self] in self?.refresh() },
            ]), withKey: "glance")
        }
    }

    /// The win dance: a bouncing sway while celebrating.
    private func dance() {
        sprite.removeAction(forKey: "dance")
        let hop = SKAction.sequence([
            .group([.moveBy(x: 0, y: 5, duration: 0.12), .rotate(toAngle: 0.08, duration: 0.12)]),
            .group([.moveBy(x: 0, y: -5, duration: 0.12), .rotate(toAngle: -0.08, duration: 0.12)]),
        ])
        sprite.run(.repeatForever(hop), withKey: "dance")
    }
}

/// §6 Sprites — 16×16 base grid, 1px ink outline, palette colors + dither mixes
/// only. The deck character, drawn procedurally on that grid and baked.
public enum DeckCharacter {

    public enum Mood: String { case idle, looking, happy, glad, sad, celebrate, win, blink }

    private struct Key: Hashable { let deckId: String; let mood: Mood; let scale: Int; let gx: Int; let gy: Int }
    private static var cache: [Key: SKTexture] = [:]

    /// Body colors per deck — Pinky's "pink" is the red⊕cream dither (§1).
    private static func body(_ deckId: String) -> (UIColor, UIColor) {
        switch deckId {
        case "pink":  return (CRT.suitRed, CRT.cardFace)
        case "mamma": return (CRT.gold, CRT.cardFace)
        case "smith": return (CRT.feltMid, CRT.cardFace)
        case "lammy": return (CRT.cardFace, CRT.feltMid)
        default:      return (CRT.suitRed, CRT.cardFace)
        }
    }

    public static func node(deckId: String, mood: Mood, scale: Int) -> SKSpriteNode {
        let tex = texture(deckId: deckId, mood: mood, scale: scale)
        let n = SKSpriteNode(texture: tex)
        n.size = tex.size()
        n.anchorPoint = CGPoint(x: 0, y: 1)
        return n
    }

    public static func texture(deckId: String, mood: Mood, scale: Int,
                               gaze: (dx: Int, dy: Int) = (0, 0)) -> SKTexture {
        let key = Key(deckId: deckId, mood: mood, scale: scale, gx: gaze.dx, gy: gaze.dy)
        if let c = cache[key] { return c }
        let tex = PixelTexture.texture(from: image(deckId: deckId, mood: mood, scale: scale, gaze: gaze))
        cache[key] = tex
        return tex
    }

    /// The same sprite as a UIImage — the map avatar and the UIKit screens
    /// (deck select, victory) draw the character with this.
    public static func image(deckId: String, mood: Mood, scale: Int,
                             gaze: (dx: Int, dy: Int) = (0, 0)) -> UIImage {
        let g = 16
        let img = PixelTexture.image(size: CGSize(width: g * scale, height: g * scale)) { cg in
            let (a, b) = body(deckId)
            func px(_ x: Int, _ y: Int, _ color: UIColor) {
                cg.setFillColor(color.cgColor)
                cg.fill(CGRect(x: x * scale, y: y * scale, width: scale, height: scale))
            }
            // Head block 10×9 at (3,3), 1px ink outline, dithered body fill.
            for y in 3...11 {
                for x in 3...12 {
                    let edge = (y == 3 || y == 11 || x == 3 || x == 12)
                    px(x, y, edge ? CRT.ink : ((x + y) % 2 == 0 ? a : b))
                }
            }
            // Ears.
            px(4, 2, CRT.ink); px(5, 2, CRT.ink); px(10, 2, CRT.ink); px(11, 2, CRT.ink)
            // Eyes + mouth per mood. `gaze` shifts the pupils on the grid.
            let eyeY = (mood == .sad ? 7 : 6) + max(-1, min(1, gaze.dy == 0 ? 0 : -gaze.dy))
            let ex = max(-1, min(1, gaze.dx))
            switch mood {
            case .blink:
                px(5, 6, CRT.ink); px(6, 6, CRT.ink); px(9, 6, CRT.ink); px(10, 6, CRT.ink)
            case .looking:
                px(6 + ex, eyeY, CRT.ink); px(10 + ex, eyeY, CRT.ink)
            case .happy, .win, .celebrate:
                // ^ ^ happy eyes
                px(5, 7, CRT.ink); px(6, 6, CRT.ink); px(7, 7, CRT.ink)
                px(9, 7, CRT.ink); px(10, 6, CRT.ink); px(11, 7, CRT.ink)
            case .glad:
                // A lighter squint — flat happy lines.
                px(5, 6, CRT.ink); px(6, 6, CRT.ink)
                px(9, 6, CRT.ink); px(10, 6, CRT.ink)
            default:
                px(6 + ex, eyeY, CRT.ink); px(10 + ex, eyeY, CRT.ink)
            }
            switch mood {
            case .sad:
                px(7, 9, CRT.ink); px(8, 10, CRT.ink); px(9, 9, CRT.ink)
                // One small tear.
                px(11, 8, CRT.phosphor)
            case .happy, .win, .celebrate:
                px(6, 9, CRT.ink); px(7, 10, CRT.ink); px(8, 10, CRT.ink)
                px(9, 10, CRT.ink); px(10, 9, CRT.ink)
            case .glad:
                px(7, 9, CRT.ink); px(8, 10, CRT.ink); px(9, 9, CRT.ink)
            default:
                px(7, 9, CRT.ink); px(8, 9, CRT.ink); px(9, 9, CRT.ink)
            }
            // A win gets phosphor sparks — the only glow color.
            if mood == .win || mood == .celebrate { px(13, 2, CRT.phosphor); px(2, 4, CRT.phosphor) }
        }
        return img
    }
}
