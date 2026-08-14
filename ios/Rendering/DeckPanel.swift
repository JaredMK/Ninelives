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
    /// The drag-scrub odds readout (the web's `.ds-scrub`): an overlay line
    /// over the histogram while a finger scrubs the bars.
    private let scrubLayer = SKNode()
    /// The last synced rank → remaining counts (the scrubber sums these).
    private var lastCounts: [Int: Int] = [:]
    /// Per-rank bar geometry from the last sync, for scrub hit-testing.
    private var barFrames: [(value: Int, label: String, x: CGFloat, w: CGFloat)] = []
    private var histMinX: CGFloat = 0
    private var histMaxX: CGFloat = 0

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
        scrubLayer.zPosition = 4
        addChild(scrubLayer)
        zPosition = Layer.chrome
    }

    /// Show/clear the revealed NEXT draw beside the deck — the web's deck-reveal
    /// strip. A peek that appears slides in with a small pop.
    public func syncPeek(_ face: CardArt.Face?) {
        guard face != peekShown else { return }
        peekShown = face
        peekLayer.removeAllChildren()
        guard let face else { return }
        // v6.52: the peeked card sits DIRECTLY OVER the character (no "NEXT"
        // tag — the placement says it) and reads bigger, with a phosphor
        // halo behind it on top of the alpha-breathe: the old pulse alone
        // didn't pull the eye off the board.
        let card = CardNode(face: face, scale: .half)
        card.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        card.setScale(0.92)
        card.position = CGPoint(x: character.position.x + 16, y: character.position.y - 12)
        card.zPosition = 4
        let halo = SKShapeNode(rectOf: CGSize(width: 54, height: 72), cornerRadius: 4)
        halo.fillColor = CRT.phosphor
        halo.strokeColor = .clear
        halo.alpha = 0.22
        halo.blendMode = .add
        halo.zPosition = -0.5
        halo.run(.repeatForever(.sequence([.fadeAlpha(to: 0.10, duration: 0.55),
                                           .fadeAlpha(to: 0.28, duration: 0.55)])))
        card.addChild(halo)
        peekLayer.addChild(card)
        card.alpha = 0
        card.run(.group([.fadeIn(withDuration: 0.15),
                         .sequence([.scale(to: 1.0, duration: 0.1), .scale(to: 0.92, duration: 0.1)])]))
        // The peeked card GLOWS (a slow alpha-breathe — the eye catches the
        // motion) and the character does a quick two-hop to point you at it
        // (router batch). Both transform/alpha-only.
        card.run(.repeatForever(.sequence([
            .fadeAlpha(to: 0.72, duration: 0.55),
            .fadeAlpha(to: 1.0, duration: 0.55),
        ])), withKey: "peekGlow")
        if character.action(forKey: "peekHop") == nil {
            character.run(.sequence([
                .moveBy(x: 0, y: 6, duration: 0.1), .moveBy(x: 0, y: -6, duration: 0.1),
                .moveBy(x: 0, y: 4, duration: 0.09), .moveBy(x: 0, y: -4, duration: 0.09),
            ]), withKey: "peekHop")
        }
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

    /// `counts` is rank value → remaining, `suitCounts` is suit → remaining,
    /// `suitTotals` the deal's initial per-suit composition (the web's "8/13"),
    /// `rankTotals` the deal's initial per-rank composition (the web's
    /// renderHistogram grey "total this stage" ghost behind each bright bar).
    public func sync(counts: [Int: Int], suitCounts: [String: Int], total: Int,
                     deckRemaining: Int, deckId: String, mood: DeckCharacter.Mood,
                     tier: String = "regular", suitTotals: [String: Int] = [:],
                     rankTotals: [Int: Int] = [:], showJoker: Bool = true,
                     showSuits: Bool = true) {
        histLayer.removeAllChildren()
        suitLayer.removeAllChildren()
        deckLayer.removeAllChildren()
        scrubLayer.removeAllChildren()
        lastCounts = counts
        barFrames.removeAll()

        let pad: CGFloat = 8
        // ---- suit counts (left, remaining/total like the web) ----
        // Zen passes showSuits: false (v6.52) — a fresh standard deck's suit
        // tallies say nothing there, and the column crowded the histogram
        // into the "11/13" overlap. The histogram reclaims the width.
        if showSuits {
            var sy: CGFloat = -pad - 6
            for s in ["♥", "♦", "♣", "♠"] {
                let n = suitCounts[s] ?? 0
                let t = suitTotals[s] ?? n
                // All four tallies read CREAM (v6.36): red-on-felt was the
                // hardest text on the board, and the glyph already carries the suit.
                let text = "\(s) \(n)/\(t)"
                let label = PixelTexture.label(text, size: 16, color: n == 0 && t == 0 ? CRT.muted : CRT.cardFace)
                label.anchorPoint = CGPoint(x: 0, y: 0.5)
                label.position = CGPoint(x: pad, y: sy)
                suitLayer.addChild(label)
                sy -= 15
            }
        }

        // ---- rank histogram (middle): one column per rank, 2..A left→right ----
        let histX = pad + (showSuits ? 46 : 0)
        let deckW: CGFloat = 62
        let histW = size.width - histX - deckW - pad * 2
        // +1 column for ★ (jokers), which sit at rank 0 and are therefore
        // outside DeckManager.ranks entirely. Zen never mints one, so the
        // column drops there and the ranks breathe wider.
        let columns = DeckManager.ranks.count + (showJoker ? 1 : 0)
        let barW = max(3, (histW - CGFloat(columns - 1) * 2) / CGFloat(columns))
        // Web parity (renderHistogram): the scale reads the FULL stage counts.
        let scaleMax = max(1, rankTotals.values.max() ?? counts.values.max() ?? 1)
        let histH = size.height - pad * 2 - 12
        histMinX = histX
        histMaxX = histX + CGFloat(columns) * (barW + 2)
        for (i, r) in DeckManager.ranks.enumerated() {
            let n = counts[r.value] ?? 0
            let full = rankTotals[r.value] ?? 0
            let barX = histX + CGFloat(i) * (barW + 2)
            let barY = -size.height + pad + 12
            barFrames.append((value: r.value, label: r.label, x: barX, w: barW))
            if full > 0 {
                // The grey ghost: the full count of this rank at deal start.
                let gh = max(3, CGFloat(full) / CGFloat(scaleMax) * histH)
                let ghost = SKSpriteNode(color: CRT.feltDeep, size: CGSize(width: barW, height: gh))
                ghost.anchorPoint = CGPoint(x: 0, y: 0)
                ghost.position = CGPoint(x: barX, y: barY)
                histLayer.addChild(ghost)
            }
            if n > 0 {
                // The bright overlay: how many of this rank are still drawable.
                let h = max(3, CGFloat(n) / CGFloat(scaleMax) * histH)
                let bar = SKSpriteNode(color: CRT.cardFace, size: CGSize(width: barW, height: h))
                bar.anchorPoint = CGPoint(x: 0, y: 0)
                bar.position = CGPoint(x: barX, y: barY)
                histLayer.addChild(bar)
            } else if full == 0 {
                // No such rank this stage at all: the old 2px felt stub.
                let stub = SKSpriteNode(color: CRT.feltDeep, size: CGSize(width: barW, height: 2))
                stub.anchorPoint = CGPoint(x: 0, y: 0)
                stub.position = CGPoint(x: barX, y: barY)
                histLayer.addChild(stub)
            }
            // Rank tick under the bar (12px floor).
            let tick = PixelTexture.label(r.label, size: 14, color: CRT.muted)
            tick.anchorPoint = CGPoint(x: 0.5, y: 1)
            tick.position = CGPoint(x: barX + barW / 2, y: -size.height + pad + 11)
            histLayer.addChild(tick)
        }

        // ---- ★ JOKERS, the last column. They are rank 0, so the rank loop
        // above can never reach them; without this a deck holding nothing but
        // a Joker drew an entirely empty histogram.
        if showJoker {
            let jokers = counts[0] ?? 0
            let fullJokers = rankTotals[0] ?? 0
            let barX = histX + CGFloat(DeckManager.ranks.count) * (barW + 2)
            let barY = -size.height + pad + 12
            barFrames.append((value: 0, label: "★", x: barX, w: barW))
            if fullJokers > 0 {
                let gh = max(3, CGFloat(fullJokers) / CGFloat(scaleMax) * histH)
                let ghost = SKSpriteNode(color: CRT.feltDeep, size: CGSize(width: barW, height: gh))
                ghost.anchorPoint = CGPoint(x: 0, y: 0)
                ghost.position = CGPoint(x: barX, y: barY)
                histLayer.addChild(ghost)
            }
            if jokers > 0 {
                // GOLD, like the shell band's ★ column — a Joker is not an
                // ordinary rank and must never read as one.
                let h = max(3, CGFloat(jokers) / CGFloat(scaleMax) * histH)
                let bar = SKSpriteNode(color: CRT.gold, size: CGSize(width: barW, height: h))
                bar.anchorPoint = CGPoint(x: 0, y: 0)
                bar.position = CGPoint(x: barX, y: barY)
                histLayer.addChild(bar)
            } else if fullJokers == 0 {
                let stub = SKSpriteNode(color: CRT.feltDeep, size: CGSize(width: barW, height: 2))
                stub.anchorPoint = CGPoint(x: 0, y: 0)
                stub.position = CGPoint(x: barX, y: barY)
                histLayer.addChild(stub)
            }
            let tick = PixelTexture.label("★", size: 14,
                                          color: jokers > 0 ? CRT.gold : CRT.muted)
            tick.anchorPoint = CGPoint(x: 0.5, y: 1)
            tick.position = CGPoint(x: barX + barW / 2, y: -size.height + pad + 11)
            histLayer.addChild(tick)
        }

        // ---- the deck IS the character (right): the jar sprite standing as
        // the card stack, with the gold-framed count plaque at its feet ----
        let charX = size.width - deckW - pad
        character.position = CGPoint(x: charX - 2, y: -pad + 2)
        character.configure(deckId: deckId, tier: tier)
        character.setBaseMood(mood)

        // The gold count plaque, overlapping the sprite's bottom-right corner.
        let countText = "\(deckRemaining)" as NSString
        let font = CRT.Font.of(20)
        let tsz = countText.size(withAttributes: [.font: font])
        let pw = max(28, tsz.width + 10), ph: CGFloat = 25
        // THE LAST CARD is an event (router batch): the plaque goes full
        // gold and the character dances — excited or nervous, who can say.
        let lastCard = deckRemaining == 1
        let plaqueImg = PixelTexture.image(size: CGSize(width: pw + 2, height: ph + 2)) { cg in
            cg.setFillColor(CRT.shadow.cgColor)
            cg.fill(CGRect(x: 2, y: 2, width: pw, height: ph))
            cg.setFillColor((lastCard ? CRT.gold : CRT.cardFace).cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: pw, height: ph))
            cg.setFillColor((lastCard ? CRT.ink : CRT.gold).cgColor)
            for r in [CGRect(x: 0, y: 0, width: pw, height: 2), CGRect(x: 0, y: ph - 2, width: pw, height: 2),
                      CGRect(x: 0, y: 0, width: 2, height: ph), CGRect(x: pw - 2, y: 0, width: 2, height: ph)] { cg.fill(r) }
            UIGraphicsPushContext(cg)
            countText.draw(at: CGPoint(x: (pw - tsz.width) / 2, y: (ph - tsz.height) / 2),
                           withAttributes: [.font: font, .foregroundColor: CRT.ink])
            UIGraphicsPopContext()
        }
        let count = SKSpriteNode(texture: PixelTexture.texture(from: plaqueImg))
        count.size = plaqueImg.size
        count.anchorPoint = CGPoint(x: 0, y: 1)
        count.position = CGPoint(x: charX + 34, y: -size.height + pad + ph + 4)
        count.zPosition = 3
        // The dance: a tight hop + wag loop, transform-only, keyed so sync
        // never stacks a second copy. Stops the moment a card returns.
        if lastCard {
            if character.action(forKey: "lastCardDance") == nil {
                let hop = SKAction.sequence([
                    SKAction.moveBy(x: 0, y: 5, duration: 0.12),
                    SKAction.moveBy(x: 0, y: -5, duration: 0.12),
                ])
                let wag = SKAction.sequence([
                    SKAction.rotate(toAngle: 0.08, duration: 0.1),
                    SKAction.rotate(toAngle: -0.08, duration: 0.2),
                    SKAction.rotate(toAngle: 0, duration: 0.1),
                    SKAction.wait(forDuration: 0.45),
                ])
                character.run(SKAction.repeatForever(SKAction.group([
                    SKAction.sequence([hop, SKAction.wait(forDuration: 0.61)]),
                    wag,
                ])), withKey: "lastCardDance")
            }
        } else {
            character.removeAction(forKey: "lastCardDance")
            character.zRotation = 0
        }
        deckLayer.addChild(count)
        countLabel = count

        // Deck-count pop on change (the draw is felt in the number).
        if lastRemaining >= 0 && deckRemaining != lastRemaining {
            count.setScale(1.25)
            count.run(.scale(to: 1.0, duration: 0.14))
        }
        lastRemaining = deckRemaining

        deckRect = CGRect(x: charX - 4, y: -size.height + pad, width: deckW + 4, height: size.height - pad * 2)
    }

    // MARK: - Drag-scrub odds readout (the web's deckStrip scrubber)

    /// The histogram rank under a panel-local point (inside a bar's span, else
    /// the nearest bar — the web's `stripBarAt` fallback for the gaps).
    public func rankValue(atLocal p: CGPoint) -> (value: Int, label: String)? {
        guard !barFrames.isEmpty, size.height > 0 else { return nil }
        guard p.x >= histMinX - 4, p.x <= histMaxX + 4,
              p.y <= 0, p.y >= -size.height else { return nil }
        if let f = barFrames.first(where: { p.x >= $0.x - 1 && p.x <= $0.x + $0.w + 1 }) {
            return (f.value, f.label)
        }
        guard let best = barFrames.min(by: {
            abs($0.x + $0.w / 2 - p.x) < abs($1.x + $1.w / 2 - p.x)
        }) else { return nil }
        return (best.value, best.label)
    }

    /// Show the odds line for a scrubbed rank: "R · ↑N higher · =N same · ↓N
    /// lower" (jokers append "· ★N safe" — safe on any call, so they sit
    /// outside the split, matching the web's ★ column note). The touched bar
    /// gets the web's `.ds-active` gold frame.
    public func showScrub(value: Int, label: String) {
        scrubLayer.removeAllChildren()
        var above = 0, same = 0, below = 0
        for (v, n) in lastCounts where v != 0 {
            if v > value { above += n }
            else if v < value { below += n }
            else { same += n }
        }
        let jokers = lastCounts[0] ?? 0
        // The NUMBER is always bright cream — it's the answer, and a red
        // count sank into the felt. The arrow + word keep the semantic tint.
        var segments: [[(String, UIColor)]] = [
            [("↑", CRT.phosphor), ("\(above)", CRT.cardFace), (" higher", CRT.phosphor)],
            [("=", CRT.cardFace), ("\(same)", CRT.cardFace), (" same", CRT.cardFace)],
            [("↓", CRT.suitRed), ("\(below)", CRT.cardFace), (" lower", CRT.suitRed)],
        ]
        if jokers > 0 {
            segments.append([("★", CRT.gold), ("\(jokers)", CRT.cardFace), (" safe", CRT.gold)])
        }
        // The readout sits in its OWN full-width panel BELOW the band, not
        // squeezed inside the histogram — the numbers are the whole point of
        // the gesture, so they get their own room. v6.24: the counts grew to
        // 20pt on a DEEP-felt face (the red "lower" was unreadable on
        // felt-mid at 16pt), the dim " · " separators became real gaps, and
        // the panel got taller to seat the larger line.
        let boxW = size.width
        let boxH: CGFloat = 56
        let holder = SKNode()
        let bg = PixelTexture.panelNode(size: CGSize(width: boxW, height: boxH),
                                        face: CRT.feltDeep, border: CRT.phosphor, shadowOffset: 3)
        holder.addChild(bg)
        // Line 1: which rank the finger is on.
        let head = PixelTexture.label(label, size: 18, color: CRT.gold)
        head.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        head.position = CGPoint(x: boxW / 2, y: -15)
        head.zPosition = 1
        holder.addChild(head)
        // Line 2: the counts, spread evenly across the full width — each
        // segment is a run of adjacent labels (arrow · number · word).
        var clusters: [[SKSpriteNode]] = []
        var total: CGFloat = 0
        for seg in segments {
            var run: [SKSpriteNode] = []
            for (t, c) in seg {
                let n = PixelTexture.label(t, size: 20, color: c)
                n.anchorPoint = CGPoint(x: 0, y: 0.5)
                run.append(n)
                total += n.size.width
            }
            clusters.append(run)
        }
        let gap = clusters.count > 1
            ? max(8, min(26, (boxW - 12 - total) / CGFloat(clusters.count - 1))) : 0
        var tx = max(6, (boxW - total - gap * CGFloat(clusters.count - 1)) / 2)
        for run in clusters {
            for n in run {
                n.position = CGPoint(x: tx, y: -38)
                n.zPosition = 1
                holder.addChild(n)
                tx += n.size.width
            }
            tx += gap
        }
        // Hangs just under the band, over the top of the board.
        holder.position = CGPoint(x: 0, y: -size.height - 4)
        holder.zPosition = 40
        scrubLayer.addChild(holder)
        // The .ds-active marker: a gold frame around the touched bar's column.
        if let f = barFrames.first(where: { $0.value == value }) {
            let frame = SKSpriteNode()
            let img = PixelTexture.image(size: CGSize(width: f.w + 4, height: size.height - 12)) { cg in
                cg.setStrokeColor(CRT.gold.cgColor)
                cg.setLineWidth(CRT.px)
                cg.stroke(CGRect(x: 1, y: 1, width: f.w + 2, height: size.height - 14))
            }
            frame.texture = PixelTexture.texture(from: img)
            frame.size = img.size
            frame.anchorPoint = CGPoint(x: 0, y: 1)
            frame.position = CGPoint(x: f.x - 2, y: -6)
            scrubLayer.addChild(frame)
        }
    }

    public func hideScrub() { scrubLayer.removeAllChildren() }

    /// The scrub fallback for a finger that has WANDERED off the band mid-drag:
    /// the horizontal position still picks the rank (clamped into the
    /// histogram's span) and the vertical position is ignored — once the scrub
    /// activates it tracks the drag until the finger lifts, wherever it roams.
    public func rankValue(nearLocalX x: CGFloat) -> (value: Int, label: String)? {
        guard !barFrames.isEmpty, size.height > 0 else { return nil }
        let cx = max(histMinX, min(histMaxX, x))
        if let f = barFrames.first(where: { cx >= $0.x - 1 && cx <= $0.x + $0.w + 1 }) {
            return (f.value, f.label)
        }
        guard let best = barFrames.min(by: {
            abs($0.x + $0.w / 2 - cx) < abs($1.x + $1.w / 2 - cx)
        }) else { return nil }
        return (best.value, best.label)
    }
}

/// The living deck character. Wraps the baked `DeckCharacter` textures in the
/// web's state machine: transient reactions with holds, a blink loop on a
/// randomized timer, idle glances, an eye-tracking "looking" state, and the
/// celebrate dance. All texture swaps + tiny transforms — no per-frame work.
public final class DeckCharNode: SKNode {

    private let sprite = SKSpriteNode()
    private var deckId = "pink"
    private var tier = "regular"
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

    public func configure(deckId id: String, tier t: String = "regular") {
        guard id != deckId || t != tier else { refresh(); return }
        deckId = id
        tier = t
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
        // THE DANCE IS FOR A CLEARED DEAL. A correct guess gets a small bob
        // and a loss a small droop — dancing on every guess spent the
        // celebration dozens of times a deal and left nothing for the win.
        switch m {
        case .celebrate, .win: dance(m)
        case .happy, .glad, .sad: smallEmote(m)
        default: break
        }
        if hold > 0 {
            run(.sequence([.wait(forDuration: hold), .run { [weak self] in
                self?.reaction = nil
                self?.sprite.removeAction(forKey: "dance")
                self?.sprite.position = .zero
                self?.sprite.zRotation = 0
                self?.sprite.yScale = 1
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
        sprite.yScale = 1
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
                                        gaze: looking ? gaze : (0, 0), tier: tier)
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
        let closed = DeckCharacter.texture(deckId: deckId, mood: .blink, scale: 2, gaze: (0, 0), tier: tier)
        let open = DeckCharacter.texture(deckId: deckId, mood: mood, scale: 2,
                                         gaze: looking ? gaze : (0, 0), tier: tier)
        sprite.run(.sequence([
            .setTexture(closed), .wait(forDuration: 0.14), .setTexture(open),
        ]))
        // An occasional idle glance rides the same tick (web: 50% of blinks).
        if !looking, baseMood == .idle, Bool.random() {
            let g = (Int.random(in: -1...1), Int.random(in: -1...1))
            let glanced = DeckCharacter.texture(deckId: deckId, mood: .idle, scale: 2, gaze: g, tier: tier)
            sprite.run(.sequence([
                .wait(forDuration: 0.3),
                .setTexture(glanced),
                .wait(forDuration: 1.0),
                .run { [weak self] in self?.refresh() },
            ]), withKey: "glance")
        }
    }

    /// The win dance: a bouncing sway while celebrating.
    /// EACH CHARACTER MOVES LIKE ITSELF. They shared one hop, so four
    /// distinct sprites read as one animation with different hats. The
    /// choreography below is per deck AND per reaction — a win is a different
    /// motion from a loss, and Pinky's win is different from Lammy's.
    ///
    /// All of it is compositor-only (move/rotate/scale on the existing
    /// sprite), repeats forever, and is torn down by `react`'s revert.
    private func dance(_ m: DeckCharacter.Mood) {
        sprite.removeAction(forKey: "dance")
        let happy = (m == .celebrate || m == .win || m == .happy || m == .glad)
        sprite.run(.repeatForever(happy ? winMove() : lossMove()), withKey: "dance")
    }

    /// A SMALL reaction: one beat, not a routine. Still per-character in
    /// feel — a bob for good news, a dip for bad — but over in ~0.3s and
    /// never repeating, so the win dance stays special.
    private func smallEmote(_ m: DeckCharacter.Mood) {
        let up = (m != .sad)
        let dy: CGFloat = up ? 4 : -3
        let tilt: CGFloat = up ? 0.06 : -0.05
        sprite.run(.sequence([
            .group([.moveBy(x: 0, y: dy, duration: 0.10),
                    .rotate(toAngle: tilt, duration: 0.10)]),
            .group([.moveBy(x: 0, y: -dy, duration: 0.14),
                    .rotate(toAngle: 0, duration: 0.14)]),
        ]), withKey: "dance")
    }

    /// The GOOD-NEWS move, per character.
    private func winMove() -> SKAction {
        switch deckId {
        case "pink":
            // PINKY bounces — quick, light, full of itself.
            return .sequence([
                .group([.moveBy(x: 0, y: 7, duration: 0.10), .rotate(toAngle: 0.10, duration: 0.10)]),
                .group([.moveBy(x: 0, y: -7, duration: 0.10), .rotate(toAngle: -0.10, duration: 0.10)]),
                .wait(forDuration: 0.05),
            ])
        case "mamma":
            // MAMMA sways — a slow, pleased hip-swing, barely leaves the floor.
            return .sequence([
                .group([.moveBy(x: 4, y: 2, duration: 0.26), .rotate(toAngle: -0.12, duration: 0.26)]),
                .group([.moveBy(x: -8, y: 0, duration: 0.34), .rotate(toAngle: 0.12, duration: 0.34)]),
                .group([.moveBy(x: 4, y: -2, duration: 0.26), .rotate(toAngle: 0, duration: 0.26)]),
            ])
        case "smith":
            // MR. SMITH does not dance. He straightens, gives one crisp bow,
            // and returns to attention.
            return .sequence([
                .wait(forDuration: 0.35),
                .group([.moveBy(x: 0, y: -4, duration: 0.14), .scaleY(to: 0.90, duration: 0.14)]),
                .group([.moveBy(x: 0, y: 4, duration: 0.18), .scaleY(to: 1.0, duration: 0.18)]),
                .wait(forDuration: 0.45),
            ])
        case "lammy":
            // LAMMY wobbles — a woolly, off-balance shimmy that never quite
            // settles.
            return .sequence([
                .rotate(toAngle: 0.16, duration: 0.18),
                .rotate(toAngle: -0.16, duration: 0.22),
                .group([.moveBy(x: 0, y: 4, duration: 0.12), .rotate(toAngle: 0.05, duration: 0.12)]),
                .group([.moveBy(x: 0, y: -4, duration: 0.12), .rotate(toAngle: 0, duration: 0.12)]),
            ])
        default:
            return .sequence([
                .group([.moveBy(x: 0, y: 5, duration: 0.12), .rotate(toAngle: 0.08, duration: 0.12)]),
                .group([.moveBy(x: 0, y: -5, duration: 0.12), .rotate(toAngle: -0.08, duration: 0.12)]),
            ])
        }
    }

    /// The BAD-NEWS move — every character deflates in its own way.
    private func lossMove() -> SKAction {
        switch deckId {
        case "pink":
            // PINKY flinches and shivers: the bounce, punctured.
            return .sequence([
                .moveBy(x: -2, y: 0, duration: 0.05),
                .moveBy(x: 4, y: 0, duration: 0.05),
                .moveBy(x: -2, y: 0, duration: 0.05),
                .wait(forDuration: 0.55),
            ])
        case "mamma":
            // MAMMA sighs — one long sag and a slow recovery.
            return .sequence([
                .group([.moveBy(x: 0, y: -3, duration: 0.45), .scaleY(to: 0.94, duration: 0.45)]),
                .group([.moveBy(x: 0, y: 3, duration: 0.55), .scaleY(to: 1.0, duration: 0.55)]),
            ])
        case "smith":
            // MR. SMITH is merely disappointed. A single slow head-tilt.
            return .sequence([
                .rotate(toAngle: -0.07, duration: 0.5),
                .wait(forDuration: 0.3),
                .rotate(toAngle: 0, duration: 0.5),
            ])
        case "lammy":
            // LAMMY droops, ears and all, then bobs weakly back.
            return .sequence([
                .group([.moveBy(x: 0, y: -5, duration: 0.6), .rotate(toAngle: 0.12, duration: 0.6)]),
                .group([.moveBy(x: 0, y: 5, duration: 0.7), .rotate(toAngle: 0, duration: 0.7)]),
            ])
        default:
            return .sequence([
                .moveBy(x: 0, y: -3, duration: 0.4),
                .moveBy(x: 0, y: 3, duration: 0.5),
            ])
        }
    }
}

/// §6 Sprites — 16×16 base grid, 1px ink outline, palette colors + dither mixes
/// only. The four deck characters drawn procedurally on that grid and baked:
/// Pinky (cat ears, red⊕cream "pink"), Mamma (bow, red⊕gold rose), Mr. Smith
/// (top hat + monocle, steel felt), Lammy (droopy wool ears, slate fleece).
/// Tier accessories overlay the same sheet: Master's gold belt, Legendary's
/// gold crown.
public enum DeckCharacter {

    public enum Mood: String { case idle, looking, happy, glad, sad, celebrate, win, blink }

    private struct Key: Hashable {
        let deckId: String; let mood: Mood; let scale: Int
        let gx: Int; let gy: Int; let tier: String
    }
    private static var cache: [Key: SKTexture] = [:]

    /// Body dithers per deck (§1 optical mixes).
    private static func body(_ deckId: String) -> (UIColor, UIColor) {
        switch deckId {
        case "pink":  return (CRT.suitRed, CRT.cardFace)   // pink
        case "mamma": return (CRT.suitRed, CRT.gold)       // warm rose
        case "smith": return (CRT.feltMid, CRT.cardFace)   // steel
        case "lammy": return (CRT.cardFace, CRT.feltMid)   // slate fleece
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
                               gaze: (dx: Int, dy: Int) = (0, 0), tier: String = "regular") -> SKTexture {
        let key = Key(deckId: deckId, mood: mood, scale: scale, gx: gaze.dx, gy: gaze.dy, tier: tier)
        if let c = cache[key] { return c }
        let tex = PixelTexture.texture(from: image(deckId: deckId, mood: mood, scale: scale,
                                                   gaze: gaze, tier: tier))
        cache[key] = tex
        return tex
    }

    /// The same sprite as a UIImage — the map avatar and the UIKit screens
    /// (deck select, victory) draw the character with this.
    ///
    /// FIDELITY: the EXACT web sprites (32×32 jar characters + tier overlay
    /// sheets, extracted from the web build's baked data-URIs) are the primary
    /// source; the procedural 16×16 fallback below survives only for a missing
    /// asset. `gaze` is ignored on the sheet path — the web's `look` state is
    /// one fixed frame, not per-direction pupils.
    public static func image(deckId: String, mood: Mood, scale: Int,
                             gaze: (dx: Int, dy: Int) = (0, 0), tier: String = "regular") -> UIImage {
        if let sheet = ArtBundle.character(deckId: deckId, mood: mood, tier: tier) {
            let px = CGFloat(scale)
            let size = CGSize(width: sheet.size.width * px, height: sheet.size.height * px)
            let fmt = UIGraphicsImageRendererFormat()
            fmt.scale = 1
            return UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
                ctx.cgContext.interpolationQuality = .none
                sheet.draw(in: CGRect(origin: .zero, size: size))
            }
        }
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
            // Per-character silhouette features.
            switch deckId {
            case "smith":
                // Top hat: brim + crown in ink.
                for x in 3...12 { px(x, 2, CRT.ink) }
                for x in 5...10 { px(x, 1, CRT.ink); px(x, 0, CRT.ink) }
            case "lammy":
                // Droopy wool ears + fleece lumps along the crown.
                px(3, 4, CRT.ink); px(2, 5, CRT.ink); px(2, 6, CRT.ink)
                px(12, 4, CRT.ink); px(13, 5, CRT.ink); px(13, 6, CRT.ink)
                px(5, 2, CRT.cardFace); px(7, 2, CRT.cardFace); px(9, 2, CRT.cardFace); px(11, 2, CRT.cardFace)
            case "mamma":
                // Cat ears + the bow at the top-right corner.
                px(4, 2, CRT.ink); px(5, 2, CRT.ink); px(10, 2, CRT.ink); px(11, 2, CRT.ink)
                px(11, 1, CRT.suitRed); px(13, 1, CRT.suitRed)
                px(12, 2, CRT.suitRed)
                px(11, 2, CRT.suitRed); px(13, 2, CRT.suitRed)
            default:
                // Pinky's cat ears.
                px(4, 2, CRT.ink); px(5, 2, CRT.ink); px(10, 2, CRT.ink); px(11, 2, CRT.ink)
            }
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
            // Mr. Smith's monocle: a gold ring around the right eye.
            if deckId == "smith", mood != .blink {
                px(9, 5, CRT.gold); px(11, 5, CRT.gold)
                px(9, 7, CRT.gold); px(11, 7, CRT.gold)
                px(11, 8, CRT.gold)   // the chain drop
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
            // TIER ACCESSORIES: Master's gold belt, Legendary's gold crown.
            if tier == "master" {
                for x in 4...11 { px(x, 12, CRT.gold) }
                px(7, 12, CRT.ink); px(8, 12, CRT.ink)   // the buckle
            } else if tier == "legendary" {
                let top = deckId == "smith" ? 0 : 1
                for x in 5...10 { px(x, top + 1, CRT.gold) }
                px(5, top, CRT.gold); px(7, top, CRT.gold); px(10, top, CRT.gold)
            }
            // A win gets phosphor sparks — the only glow color.
            if mood == .win || mood == .celebrate { px(13, 2, CRT.phosphor); px(2, 4, CRT.phosphor) }
        }
        return img
    }
}
