import SpriteKit
import GameCore

/// The deck panel: the rank histogram, the per-suit counts, and the deck
/// character carrying the remaining count.
///
/// In the web's active `thumb-deal` layout this band rides at the TOP, under
/// the HUD: suit counts on the left, rank histogram beside them, deck stack at
/// the end. Same arrangement here.
public final class DeckPanel: SKNode {

    private let bg = SKSpriteNode()
    private let histLayer = SKNode()
    private let suitLayer = SKNode()
    private let deckLayer = SKNode()
    private var size: CGSize = .zero

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
        zPosition = Layer.chrome
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    public func resize(to s: CGSize) {
        size = s
        let tex = PixelTexture.panel(size: s)
        bg.texture = tex; bg.size = tex.size()
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
        let char = DeckCharacter.node(deckId: deckId, mood: mood, scale: 2)
        char.position = CGPoint(x: charX + 8, y: -pad - 4)
        deckLayer.addChild(char)
        let count = PixelTexture.label("\(deckRemaining)", size: 20, color: CRT.cardFace)
        count.anchorPoint = CGPoint(x: 0, y: 1)
        count.position = CGPoint(x: charX + 8 + 34, y: -pad - 8)
        deckLayer.addChild(count)
        let lbl = PixelTexture.label("left", size: 12, color: CRT.muted)
        lbl.anchorPoint = CGPoint(x: 0, y: 1)
        lbl.position = CGPoint(x: charX + 8 + 34, y: -pad - 8 - count.size.height)
        deckLayer.addChild(lbl)

        deckRect = CGRect(x: charX, y: -size.height + pad, width: deckW, height: size.height - pad * 2)
    }
}

/// §6 Sprites — 16×16 base grid, 1px ink outline, palette colors + dither mixes
/// only. The deck character, drawn procedurally on that grid and baked.
public enum DeckCharacter {

    public enum Mood: String { case idle, looking, happy, sad, win }

    private struct Key: Hashable { let deckId: String; let mood: Mood; let scale: Int }
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

    public static func texture(deckId: String, mood: Mood, scale: Int) -> SKTexture {
        let key = Key(deckId: deckId, mood: mood, scale: scale)
        if let c = cache[key] { return c }
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
            // Eyes + mouth per mood.
            let eyeY: Int
            switch mood {
            case .idle, .looking: eyeY = 6
            case .happy, .win:    eyeY = 6
            case .sad:            eyeY = 7
            }
            switch mood {
            case .looking:
                px(7, eyeY, CRT.ink); px(11, eyeY, CRT.ink)          // glancing right
            case .happy, .win:
                // ^ ^ happy eyes
                px(5, eyeY + 1, CRT.ink); px(6, eyeY, CRT.ink); px(7, eyeY + 1, CRT.ink)
                px(9, eyeY + 1, CRT.ink); px(10, eyeY, CRT.ink); px(11, eyeY + 1, CRT.ink)
            default:
                px(6, eyeY, CRT.ink); px(10, eyeY, CRT.ink)
            }
            switch mood {
            case .sad:
                px(7, 9, CRT.ink); px(8, 10, CRT.ink); px(9, 9, CRT.ink)
            case .happy, .win:
                px(6, 9, CRT.ink); px(7, 10, CRT.ink); px(8, 10, CRT.ink)
                px(9, 10, CRT.ink); px(10, 9, CRT.ink)
            default:
                px(7, 9, CRT.ink); px(8, 9, CRT.ink); px(9, 9, CRT.ink)
            }
            // A win gets one phosphor spark — the only glow color.
            if mood == .win { px(13, 2, CRT.phosphor); px(2, 4, CRT.phosphor) }
        }
        let tex = PixelTexture.texture(from: img)
        cache[key] = tex
        return tex
    }
}
