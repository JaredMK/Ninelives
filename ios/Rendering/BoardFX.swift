import SpriteKit
import GameCore

/// The board's motion language, ported from the web build.
///
/// Two pieces live here: the CAUSAL animation queue (a draw animates before the
/// effects it triggered, regardless of engine emit order) and the traveling
/// card (every card that moves flies an eased arc instead of teleporting).
///
/// Everything is SKAction on transform/alpha/texture. The arc is an
/// `SKAction.follow(path:)` — SpriteKit walks the path in its own C++ update,
/// so there is no per-frame Swift work anywhere in this file.
public final class AnimQueue {

    public struct Step {
        let priority: Int
        let seq: Int
        let run: (@escaping () -> Void) -> Void
    }

    private var queue: [Step] = []
    private var busy = false
    private var seq = 0
    private var pumpScheduled = false

    public init() {}

    /// Queue `run`; it receives `done` and MUST call it when its motion has
    /// landed. Lower `priority` runs earlier within a synchronous batch — the
    /// engine can emit an effect (a bury) BEFORE the draw that caused it, so
    /// draws queue at 0 and effects at 1 to restore causal order.
    public func add(priority: Int = 0, _ run: @escaping (@escaping () -> Void) -> Void) {
        queue.append(Step(priority: priority, seq: seq, run: run))
        seq += 1
        schedulePump()
    }

    private func schedulePump() {
        guard !pumpScheduled, !busy else { return }
        pumpScheduled = true
        // Collect the whole synchronous batch first (the web's microtask pump).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pumpScheduled = false
            self.pump()
        }
    }

    private func pump() {
        guard !busy else { return }
        // Stable: causal priority first, then insertion order.
        queue.sort { $0.priority != $1.priority ? $0.priority < $1.priority : $0.seq < $1.seq }
        guard !queue.isEmpty else { return }
        let step = queue.removeFirst()
        busy = true
        var settled = false
        let done = { [weak self] in
            guard let self, !settled else { return }
            settled = true
            self.busy = false
            DispatchQueue.main.async { self.pump() }
        }
        step.run(done)
    }

    /// Drop everything (new deal, run end) so stale steps never animate onto a
    /// rebuilt board.
    public func clear() {
        queue.removeAll()
        busy = false
    }

    public var isIdle: Bool { queue.isEmpty && !busy }
}

/// The traveling card + the shared floating cues.
public enum BoardFX {

    // Timings, verbatim from the web build.
    public static let cascadeBlankMS = 150     // blank-board beat before the first card flies
    public static let cascadeStepMS = 80       // stagger between cascade cards
    public static let cascadeDurMS = 230       // per-card cascade travel
    public static let drawFlightMS = 250       // deck → pile draw travel
    public static let buryFlightMS = 240       // deck → pile face-down travel
    public static let returnFlightMS = 270     // pile → deck return travel
    public static let deathFlashDelayMS = 340  // beat after the card settles
    public static let deathFlashMS = 340       // red flash length
    public static let deathDissolveAfterMS = 300  // flash start → dissolve

    /// The flight arc: mid-point lifted like the web's
    /// `lift = -min(34, max(10, dist * 0.16))` (scene y is up-positive when
    /// negative-down anchor maths are done, so the lift ADDS to y).
    public static func lift(for distance: CGFloat) -> CGFloat {
        min(34, max(10, distance * 0.16))
    }

    /// Fly `node` (already parented, positioned at `from`) to `to` along the
    /// lifted quad-curve arc with the web's scale language: start 0.9, overshoot
    /// 1.05 late, settle 1.0. Calls `onArrive` once, then removes the node.
    public static func fly(_ node: SKNode, from: CGPoint, to: CGPoint,
                           duration: TimeInterval, onArrive: (() -> Void)? = nil) {
        node.position = from
        let dist = hypot(to.x - from.x, to.y - from.y)
        let l = lift(for: dist)
        let path = CGMutablePath()
        path.move(to: from)
        // Control point 2× the lift above the midpoint puts the apex ≈ lift.
        path.addQuadCurve(to: to,
                          control: CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2 + l * 2))
        let follow = SKAction.follow(path, asOffset: false, orientToPath: false, duration: duration)
        follow.timingMode = .easeInEaseOut
        node.setScale(0.9)
        let scale = SKAction.sequence([
            .scale(to: 1.0, duration: duration * 0.55),
            .scale(to: 1.05, duration: duration * 0.29),
            .scale(to: 1.0, duration: duration * 0.16),
        ])
        node.run(.sequence([
            .group([follow, scale]),
            .run { onArrive?() },
            .removeFromParent(),
        ]))
    }

    /// A face-down "deck back" clone — the same dither back as the deck stack.
    public static func faceDownCard(scale: CardArt.Scale, deckId: String) -> SKNode {
        let n = CardNode(face: CardArt.Face(label: "", suit: "", kind: .back(deckId: deckId)), scale: scale)
        // Flights anchor at the card's centre so scaling breathes around it.
        n.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        n.zPosition = Layer.float
        return n
    }

    /// A face-up flying clone that looks like a real board card.
    public static func faceUpCard(_ face: CardArt.Face, scale: CardArt.Scale) -> SKNode {
        let n = CardNode(face: face, scale: scale)
        n.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        n.zPosition = Layer.float
        return n
    }

    /// The landing squash: the card settles with a quick squash-and-recover —
    /// the web's settle beat, plus the squash the CSS could not do.
    public static func squashSettle(_ node: SKNode) {
        node.removeAction(forKey: "squash")
        node.xScale = 1.06; node.yScale = 0.92
        node.run(.group([
            SKAction.scaleX(to: 1.0, duration: 0.14),
            SKAction.scaleY(to: 1.0, duration: 0.14),
        ]), withKey: "squash")
    }

    /// One-shot pulse texture: a hard border ring in `color`, card-box sized.
    static func ringTexture(size: CGSize, color: UIColor, weight: CGFloat = 3) -> SKTexture {
        let img = PixelTexture.image(size: size) { cg in
            cg.setFillColor(color.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: size.width, height: weight))
            cg.fill(CGRect(x: 0, y: size.height - weight, width: size.width, height: weight))
            cg.fill(CGRect(x: 0, y: 0, width: weight, height: size.height))
            cg.fill(CGRect(x: size.width - weight, y: 0, width: weight, height: size.height))
        }
        return PixelTexture.texture(from: img)
    }
}
