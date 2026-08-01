import SpriteKit
import GameCore

/// The connection web — dashed pixel edges between piles.
///
/// §5: *"Map web lines — dashed pixel edges, low-contrast felt (lit = phosphor
/// for the taken path)."* Two edges of a given length/angle share one baked
/// texture, so a full 12-pile web costs a handful of textures and N sprites.
///
/// The EDGE RULE is ported from the web renderer: an edge exists between two
/// ALIVE piles when no OTHER alive pile's card box blocks the sightline.
/// Alive↔dead edges are also computed (Same-Powers can revive a linked dead
/// pile) but are never drawn.
public final class WebLayer: SKNode {

    private var edgeNodes: [SKSpriteNode] = []
    /// The drawn edges, retained so the synapse pulse can ride them.
    public private(set) var drawnEdges: [(a: Int, b: Int, pa: CGPoint, pb: CGPoint)] = []
    private static var texCache: [Key: SKTexture] = [:]
    private struct Key: Hashable { let len: Int; let lit: Bool; let weight: Int }

    public override init() {
        super.init()
        zPosition = Layer.web
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    /// The blocking test, ported verbatim from `cardBlocks` in index.html: a
    /// point-to-segment distance with the endpoints excluded (t ≤ 0.06 / ≥ 0.94).
    private static func blocks(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, rad: CGFloat) -> Bool {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 == 0 { return false }
        let t = ((c.x - a.x) * dx + (c.y - a.y) * dy) / len2
        if t <= 0.06 || t >= 0.94 { return false }      // not between the endpoints
        let p = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
        return hypot(c.x - p.x, c.y - p.y) < rad
    }

    /// Compute the adjacency the engine should use for Same-Power targeting.
    /// Mirrors the web exactly: drawn alive↔alive edges, PLUS undrawn
    /// alive↔dead edges (dead piles are empty space, so paths pass through).
    public static func adjacency(centers: [Int: CGPoint], alive: Set<Int>, rad: CGFloat) -> [Int: [Int]] {
        var adj: [Int: [Int]] = [:]
        let aliveNodes = centers.filter { alive.contains($0.key) }.sorted { $0.key < $1.key }
        for i in 0..<aliveNodes.count {
            for j in (i + 1)..<aliveNodes.count {
                let a = aliveNodes[i], b = aliveNodes[j]
                let blocked = aliveNodes.contains { other in
                    other.key != a.key && other.key != b.key
                        && blocks(a.value, b.value, other.value, rad: rad)
                }
                if blocked { continue }
                adj[a.key, default: []].append(b.key)
                adj[b.key, default: []].append(a.key)
            }
        }
        // Alive ↔ dead (never drawn).
        for (d, cd) in centers where !alive.contains(d) {
            for a in aliveNodes {
                let blocked = aliveNodes.contains { other in
                    other.key != a.key && blocks(a.value, cd, other.value, rad: rad)
                }
                if !blocked {
                    adj[a.key, default: []].append(d)
                    adj[d, default: []].append(a.key)
                }
            }
        }
        return adj
    }

    /// Rebuild the drawn edges. Called only when the board changes (a pile dies,
    /// a deal starts) — never per frame.
    public func rebuild(centers: [Int: CGPoint], alive: Set<Int>, rad: CGFloat, litHub: Int? = nil) {
        edgeNodes.forEach { $0.removeFromParent() }
        edgeNodes.removeAll(keepingCapacity: true)
        drawnEdges.removeAll(keepingCapacity: true)

        let aliveNodes = centers.filter { alive.contains($0.key) }.sorted { $0.key < $1.key }
        for i in 0..<aliveNodes.count {
            for j in (i + 1)..<aliveNodes.count {
                let a = aliveNodes[i], b = aliveNodes[j]
                let blocked = aliveNodes.contains { other in
                    other.key != a.key && other.key != b.key
                        && WebLayer.blocks(a.value, b.value, other.value, rad: rad)
                }
                if blocked { continue }
                let lit = litHub == a.key || litHub == b.key
                addEdge(from: a.value, to: b.value, lit: lit)
                drawnEdges.append((a: a.key, b: b.key, pa: a.value, pb: b.value))
            }
        }
    }

    /// The synapse pulse: a phosphor signal dot rides every edge OUT of `hub`
    /// (the pile a correct guess just landed on) to its linked neighbours —
    /// 520ms, brighten in, fade over the last third. Transform/alpha only.
    public func pulse(from hub: Int) {
        let dur = Double(BoardFX.synapsePulseMS) / 1000
        for e in drawnEdges where e.a == hub || e.b == hub {
            let from = e.a == hub ? e.pa : e.pb
            let to = e.a == hub ? e.pb : e.pa
            let dot = SKSpriteNode(color: CRT.phosphor, size: CGSize(width: 5, height: 5))
            dot.position = from
            dot.alpha = 0
            // Above the cards: the iOS board packs piles tighter than the web,
            // so a web-layer dot would vanish under the card sprites.
            dot.zPosition = Layer.card + 6
            addChild(dot)
            let move = SKAction.move(to: to, duration: dur)
            move.timingMode = .easeInEaseOut
            dot.run(.group([
                move,
                .sequence([.fadeAlpha(to: 1, duration: dur * 0.15),
                           .wait(forDuration: dur * 0.51),
                           .fadeAlpha(to: 0, duration: dur * 0.34)]),
            ]))
            dot.run(.sequence([.wait(forDuration: dur), .removeFromParent()]))
        }
    }

    private func addEdge(from a: CGPoint, to b: CGPoint, lit: Bool) {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy)
        guard len > 1 else { return }
        let tex = WebLayer.dashTexture(length: len, lit: lit)
        let n = SKSpriteNode(texture: tex)
        n.size = tex.size()
        n.anchorPoint = CGPoint(x: 0, y: 0.5)
        n.position = a
        n.zRotation = atan2(dy, dx)
        n.zPosition = lit ? Layer.web + 1 : Layer.web
        addChild(n)
        edgeNodes.append(n)
    }

    /// A horizontal dashed strip, baked once per (rounded length, lit). The web
    /// uses `repeating-linear-gradient(90deg, C 0 8px, transparent 8px 14px)` —
    /// an 8px dash on a 14px period, 4px thick.
    private static func dashTexture(length: CGFloat, lit: Bool) -> SKTexture {
        // Round to 4px buckets so a board of ~30 edges shares a few textures.
        let bucket = Int((length / 4).rounded()) * 4
        let key = Key(len: bucket, lit: lit, weight: 4)
        if let c = texCache[key] { return c }
        let h: CGFloat = 4
        let size = CGSize(width: max(4, CGFloat(bucket)), height: h)
        let img = PixelTexture.image(size: size) { cg in
            cg.setFillColor((lit ? CRT.phosphor : CRT.feltMid).cgColor)
            var x: CGFloat = 0
            while x < size.width {
                cg.fill(CGRect(x: x, y: 0, width: min(8, size.width - x), height: h))
                x += 14
            }
        }
        let tex = PixelTexture.texture(from: img)
        texCache[key] = tex
        return tex
    }
}
