import SpriteKit
import GameCore

/// The deal board. Everything the player sees while playing a deal.
///
/// Layout mirrors the web's active `thumb-deal` arrangement top→bottom:
/// HUD bar · deck band (suit counts + rank histogram + deck character) ·
/// reward/score line · [left rail: FAN + ▲ ＝ ▼] beside the pile board ·
/// reshuffle bar. The CRT layer sits above all of it as one static node.
///
/// The scene's anchor is TOP-LEFT (0, 1), so +x is right and −y is down and
/// every node's own (0, 1) anchor composes without sign juggling.
public final class DealScene: SKScene {

    // MARK: Chrome
    private var hud: HUDBar!
    private let deckPanel = DeckPanel()
    private let rewardLine = RewardLine()
    private let boardLayer = SKNode()
    private let webLayer = WebLayer()
    private let floatLayer = SKNode()
    private var crt: CRTOverlay!

    private var fanButton: PixelButton!
    private var higherButton: PixelButton!
    private var sameButton: PixelButton!
    private var lowerButton: PixelButton!
    private var reshuffleButton: PixelButton!
    private var buttons: [PixelButton] { [fanButton, higherButton, sameButton, lowerButton, reshuffleButton] }

    /// The big centred direction word shown while swiping.
    private let swipeLabel = SKNode()
    /// The hold-for-help panel; takes over the deck band's room, like the web.
    private let helpPanel = SKNode()
    /// The full-screen pile fan-out viewer.
    private let fanOverlay = SKNode()

    // MARK: Board
    private var piles: [PileNode] = []
    private var pileColumns: [Int] = []
    private var columnSizes: [Int] = []
    private var cardScale: CardArt.Scale = .three
    private var pillarPlaques: [SKNode] = []
    private var basePlaques: [SKNode] = []
    /// Pile centres in scene space — the web layer and hit-testing read these.
    private var pileCenters: [Int: CGPoint] = [:]
    private var boardRect: CGRect = .zero

    // MARK: State
    public weak var controller: DealController?
    private var fanHintOn = false
    private var selectedPile: Int?

    private var layoutDone = false

    // MARK: - Setup

    public override func didMove(to view: SKView) {
        guard !layoutDone else { return }
        layoutDone = true
        anchorPoint = CGPoint(x: 0, y: 1)
        backgroundColor = CRT.feltDeep
        scaleMode = .resizeFill

        addChild(boardLayer)
        boardLayer.addChild(webLayer)
        addChild(floatLayer)
        floatLayer.zPosition = Layer.float
        addChild(deckPanel)
        addChild(rewardLine)

        hud = HUDBar(width: size.width)
        addChild(hud)

        let railW: CGFloat = 58
        fanButton = PixelButton(id: "fan", title: "FAN", size: CGSize(width: railW, height: 34), role: .plain, fontSize: 15)
        higherButton = PixelButton(id: "higher", title: "▲", size: CGSize(width: railW, height: 46), role: .cta, fontSize: 22)
        sameButton = PixelButton(id: "same", title: "＝", size: CGSize(width: railW, height: 46), role: .ctaOutline, fontSize: 22)
        lowerButton = PixelButton(id: "lower", title: "▼", size: CGSize(width: railW, height: 46), role: .cta, fontSize: 22)
        reshuffleButton = PixelButton(id: "reshuffle", title: "RESHUFFLE", size: CGSize(width: 180, height: 34), role: .gold, fontSize: 16)
        buttons.forEach { addChild($0) }

        swipeLabel.zPosition = Layer.float
        addChild(swipeLabel)
        helpPanel.zPosition = Layer.overlay
        helpPanel.isHidden = true
        addChild(helpPanel)
        fanOverlay.zPosition = Layer.overlay
        fanOverlay.isHidden = true
        addChild(fanOverlay)

        crt = CRTOverlay(size: size)
        crt.position = CGPoint(x: size.width / 2, y: -size.height / 2)
        addChild(crt)

        layoutChrome()
        controller?.sceneReady()
    }

    public override func didChangeSize(_ oldSize: CGSize) {
        guard layoutDone else { return }
        PixelTexture.flushLayoutCaches()
        hud.resize(width: size.width)
        crt.resize(to: size)
        crt.position = CGPoint(x: size.width / 2, y: -size.height / 2)
        layoutChrome()
        controller?.refreshAll()
    }

    /// Safe-area insets pushed in by the hosting view controller.
    public var safeInsets: UIEdgeInsets = .zero {
        didSet { if layoutDone { layoutChrome(); controller?.refreshAll() } }
    }

    // MARK: - Layout (runs on size/rotation only, never per frame)

    private var railTop: CGFloat = 0
    private var railX: CGFloat = 0

    private func layoutChrome() {
        let pad: CGFloat = 8
        let top = safeInsets.top + pad
        var y = -top

        hud.position = CGPoint(x: 0, y: y)
        y -= hud.height + 6

        let bandH: CGFloat = 78
        deckPanel.resize(to: CGSize(width: size.width - pad * 2, height: bandH))
        deckPanel.position = CGPoint(x: pad, y: y)
        y -= bandH + 6

        rewardLine.position = CGPoint(x: 0, y: y - 10)
        y -= 26

        // Left rail: FAN on top, then ▲ ＝ ▼ (the web's dedicated guess strip).
        railX = pad
        railTop = y
        let bottomLimit = -(size.height - safeInsets.bottom - pad - 40)
        let railH = fanButton.frameSize.height + 6 + higherButton.frameSize.height * 3 + 12
        let railStart = max(y - 4, bottomLimit + railH)
        var ry = railStart
        fanButton.position = CGPoint(x: railX, y: ry); ry -= fanButton.frameSize.height + 8
        higherButton.position = CGPoint(x: railX, y: ry); ry -= higherButton.frameSize.height + 6
        sameButton.position = CGPoint(x: railX, y: ry); ry -= sameButton.frameSize.height + 6
        lowerButton.position = CGPoint(x: railX, y: ry)

        // Reshuffle sits at the very bottom, centred.
        reshuffleButton.position = CGPoint(x: (size.width - reshuffleButton.frameSize.width) / 2,
                                           y: -(size.height - safeInsets.bottom - pad))

        // The board owns everything right of the rail.
        let boardX = railX + fanButton.frameSize.width + 10
        let boardW = size.width - boardX - pad
        let boardBottom = -(size.height - safeInsets.bottom - pad - 44)
        boardRect = CGRect(x: boardX, y: boardBottom, width: boardW, height: y - boardBottom)

        swipeLabel.position = CGPoint(x: boardRect.midX, y: boardRect.midY)
        rebuildBoardLayout()
    }

    // MARK: - Board construction

    /// Build the pile grid for `count` piles. Columns come from the same
    /// `layoutForPiles` split the engine uses, so pile → column matches exactly.
    public func buildBoard(pileCount: Int) {
        let layout = CampaignLayout.layoutForPiles(pileCount)
        columnSizes = layout.cols
        pileColumns = GameEngineColumns.map(layout.cols, pileCount)

        piles.forEach { $0.removeFromParent() }
        piles.removeAll()
        pillarPlaques.forEach { $0.removeFromParent() }; pillarPlaques.removeAll()
        basePlaques.forEach { $0.removeFromParent() }; basePlaques.removeAll()

        cardScale = DealScene.pickScale(cols: columnSizes, in: boardRect)
        for i in 0..<pileCount {
            let p = PileNode(index: i, scale: cardScale)
            boardLayer.addChild(p)
            piles.append(p)
        }
        // Pillar plaques above the columns, Base plaques below.
        for _ in columnSizes {
            let top = SKNode(); boardLayer.addChild(top); pillarPlaques.append(top)
            let bot = SKNode(); boardLayer.addChild(bot); basePlaques.append(bot)
        }
        rebuildBoardLayout()
    }

    /// Choose the biggest card size that fits the board box.
    private static func pickScale(cols: [Int], in rect: CGRect) -> CardArt.Scale {
        guard !cols.isEmpty, rect.width > 0 else { return .half }
        let rows = cols.max() ?? 3
        for scale in [CardArt.Scale.full, .three, .half] {
            let w = CGFloat(cols.count) * scale.size.width + CGFloat(cols.count - 1) * 10
            let h = CGFloat(rows) * (scale.size.height + 10) + 44   // + plaque rows
            if w <= rect.width && h <= rect.height { return scale }
        }
        return .half
    }

    private func rebuildBoardLayout() {
        guard !piles.isEmpty, boardRect.width > 0 else { return }
        cardScale = DealScene.pickScale(cols: columnSizes, in: boardRect)
        let box = cardScale.size
        let gapX: CGFloat = max(6, (boardRect.width - CGFloat(columnSizes.count) * box.width) / CGFloat(max(1, columnSizes.count + 1)))
        let gapY: CGFloat = 8
        let plaqueH: CGFloat = 18

        pileCenters.removeAll(keepingCapacity: true)
        // Centre the WHOLE block (pillar plaques + the tallest column + base
        // plaques) in the board box, so the plaques hug their columns instead
        // of floating at the far edges.
        let tallest: CGFloat = CGFloat(columnSizes.max() ?? 1)
        let tallestH: CGFloat = tallest * box.height + (tallest - 1) * gapY
        let plaqueBand: CGFloat = plaqueH * 2 + 12
        let blockH: CGFloat = tallestH + plaqueBand
        let slack: CGFloat = max(0, (boardRect.height - blockH) / 2)
        let blockTop: CGFloat = CRT.snap(boardRect.maxY - slack)
        var pileIndex = 0
        for (c, colCount) in columnSizes.enumerated() {
            let colX = CRT.snap(boardRect.minX + gapX + CGFloat(c) * (box.width + gapX))
            let colH = CGFloat(colCount) * box.height + CGFloat(colCount - 1) * gapY
            // Shorter columns centre against the tallest one.
            let colSlack: CGFloat = (tallestH - colH) / 2
            let startY: CGFloat = CRT.snap(blockTop - plaqueH - 6 - colSlack)

            // Pillar plaque directly above this column's first card.
            if c < pillarPlaques.count {
                pillarPlaques[c].position = CGPoint(x: colX, y: startY + 6 + plaqueH)
            }
            for r in 0..<colCount {
                guard pileIndex < piles.count else { break }
                let y = CRT.snap(startY - CGFloat(r) * (box.height + gapY))
                // A relayout wins over any in-flight deal-in tween — otherwise
                // a stale `.move(to:)` lands afterwards and stomps the layout.
                piles[pileIndex].removeAction(forKey: "dealin")
                piles[pileIndex].alpha = 1
                piles[pileIndex].position = CGPoint(x: colX, y: y)
                pileCenters[pileIndex] = CGPoint(x: colX + box.width / 2, y: y - box.height / 2)
                pileIndex += 1
            }
            // Base plaque below the column.
            if c < basePlaques.count {
                basePlaques[c].position = CGPoint(x: colX, y: startY - colH - 6)
            }
        }
        swipeLabel.position = CGPoint(x: boardRect.midX, y: boardRect.midY)
    }

    // MARK: - Sync from the engine

    public struct BoardSnapshot {
        public var tops: [LiveCard?]
        public var counts: [Int]
        public var weighted: [Int]
        public var dead: [Bool]
        public var anchored: [Bool]
        public var pileCards: [[LiveCard]]
        public var deckId: String
        public init(tops: [LiveCard?], counts: [Int], weighted: [Int], dead: [Bool],
                    anchored: [Bool], pileCards: [[LiveCard]], deckId: String) {
            self.tops = tops; self.counts = counts; self.weighted = weighted
            self.dead = dead; self.anchored = anchored; self.pileCards = pileCards; self.deckId = deckId
        }
    }

    public func syncBoard(_ snap: BoardSnapshot) {
        for (i, p) in piles.enumerated() where i < snap.tops.count {
            p.sync(top: snap.tops[i], count: snap.counts[i], dead: snap.dead[i],
                   deckId: snap.deckId, weighted: snap.weighted[i], anchored: snap.anchored[i])
            if fanHintOn && !snap.dead[i] { p.showFan(snap.pileCards[i], full: false) } else { p.hideFan() }
        }
        let alive = Set((0..<piles.count).filter { !snap.dead[$0] })
        // The blocking radius: a little under half a card box, as on the web
        // (the card is the obstacle, its centre the node).
        let rad = cardScale.size.width * 0.46
        webLayer.rebuild(centers: pileCenters, alive: alive, rad: rad)
        controller?.pushLinks(WebLayer.adjacency(centers: pileCenters, alive: alive, rad: rad))
    }

    public func syncHUD(stageLabel: String, suitsInPlay: [String], sameCharged: Bool, samePower: String?,
                        coins: Int, deckCount: Int, score: Int) {
        hud.sync(stageLabel: stageLabel, suitsInPlay: suitsInPlay, sameCharged: sameCharged,
                 samePower: samePower, coins: coins, deckCount: deckCount, score: score)
        sameButton.setRole(sameCharged ? .charged : .ctaOutline)
    }

    public func syncDeckPanel(counts: [Int: Int], suitCounts: [String: Int], total: Int,
                              remaining: Int, deckId: String, mood: DeckCharacter.Mood) {
        deckPanel.sync(counts: counts, suitCounts: suitCounts, total: total,
                       deckRemaining: remaining, deckId: deckId, mood: mood)
    }

    public func syncReward(base: Double, bonus: Double, score: Int) {
        rewardLine.sync(base: base, bonus: bonus, score: score, width: size.width)
    }

    public func syncControls(canGuess: Bool, showReshuffle: Bool) {
        higherButton.setEnabled(canGuess)
        sameButton.setEnabled(canGuess)
        lowerButton.setEnabled(canGuess)
        reshuffleButton.isHidden = !showReshuffle
    }

    public func setPillars(_ ids: [String?], bases: [String?]) {
        for (c, node) in pillarPlaques.enumerated() {
            node.removeAllChildren()
            guard c < ids.count, let id = ids[c], let def = GameData.shared.pillarTypes.get(id) else { continue }
            node.addChild(plaque(text: String(def.label.prefix(10)), tint: CRT.gold))
        }
        for (c, node) in basePlaques.enumerated() {
            node.removeAllChildren()
            guard c < bases.count, let id = bases[c], let def = GameData.shared.baseTypes.get(id) else { continue }
            node.addChild(plaque(text: String(def.label.prefix(10)), tint: CRT.phosphor))
        }
    }

    private func plaque(text: String, tint: UIColor) -> SKNode {
        let n = SKNode()
        let w = cardScale.size.width
        let bg = PixelTexture.panelNode(size: CGSize(width: w, height: 16), face: CRT.feltMid,
                                        border: tint, shadowOffset: 2)
        bg.zPosition = 0
        n.addChild(bg)
        let l = PixelTexture.label(text, size: 12, color: tint)
        l.position = CGPoint(x: w / 2, y: -8)
        l.zPosition = 1
        n.addChild(l)
        return n
    }

    // MARK: - Selection + swipe feedback

    public func setSelected(_ index: Int?) {
        selectedPile = index
        for (i, p) in piles.enumerated() { p.setSelected(i == index) }
    }
    public var currentSelection: Int? { selectedPile }

    /// The big faded direction word, CENTRED on the board and fixed for the
    /// whole swipe (it never follows the finger) — the web's style A.
    public func showSwipeDirection(_ dir: Guess?) {
        swipeLabel.removeAllChildren()
        guard let dir else { swipeLabel.isHidden = true; return }
        swipeLabel.isHidden = false
        let (glyph, word, color): (String, String, UIColor) = {
            switch dir {
            case .higher: return ("▲", "HIGHER", CRT.phosphor)
            case .lower:  return ("▼", "LOWER", CRT.suitRed)
            case .same:   return ("＝", "SAME", CRT.gold)
            }
        }()
        let g = PixelTexture.label(glyph, size: 62, color: color)
        let w = PixelTexture.label(word, size: 27, color: color)
        g.position = CGPoint(x: 0, y: 16)
        w.position = CGPoint(x: 0, y: -26)
        swipeLabel.addChild(g); swipeLabel.addChild(w)
        swipeLabel.alpha = 0.72
        // Mirror the armed direction on the rail: armed pops, the others dim.
        for (b, d) in [(higherButton!, Guess.higher), (sameButton!, .same), (lowerButton!, .lower)] {
            b.alpha = d == dir ? 1.0 : 0.45
        }
    }

    public func clearSwipeDirection() {
        swipeLabel.removeAllChildren()
        swipeLabel.isHidden = true
        buttons.forEach { $0.alpha = 1 }
    }

    // MARK: - Hit testing

    public func pileIndex(at scenePoint: CGPoint) -> Int? {
        let box = cardScale.size
        for (i, p) in piles.enumerated() {
            let r = CGRect(x: p.position.x, y: p.position.y - box.height, width: box.width, height: box.height)
            if r.insetBy(dx: -4, dy: -4).contains(scenePoint) { return i }
        }
        return nil
    }

    public func button(at scenePoint: CGPoint) -> PixelButton? {
        buttons.first { !$0.isHidden && $0.contains(scenePoint: scenePoint) }
    }

    public func isDeckPanel(_ p: CGPoint) -> Bool {
        let r = CGRect(x: deckPanel.position.x + deckPanel.deckRect.minX,
                       y: deckPanel.position.y + deckPanel.deckRect.minY,
                       width: deckPanel.deckRect.width, height: deckPanel.deckRect.height)
        return r.contains(p)
    }

    public func press(_ button: PixelButton?, down: Bool) {
        buttons.forEach { $0.setPressed($0 === button && down) }
    }

    // MARK: - Fan

    public var isFanHintOn: Bool { fanHintOn }

    public func toggleFanHint() {
        fanHintOn.toggle()
        fanButton.setRole(fanHintOn ? .cta : .plain)
        controller?.refreshBoard()
    }

    /// The full face-up fan of one pile — the memory aid.
    public func showPileFan(_ cards: [LiveCard], pile: Int) {
        fanOverlay.removeAllChildren()
        fanOverlay.isHidden = false
        let scrim = SKSpriteNode(color: CRT.feltDeep.withAlphaComponent(0.88), size: size)
        scrim.anchorPoint = CGPoint(x: 0, y: 1)
        scrim.zPosition = 0
        fanOverlay.addChild(scrim)
        let title = PixelTexture.label("PILE \(pile + 1) · \(cards.count) CARDS", size: 18, color: CRT.phosphor, glow: true)
        title.zPosition = 2
        title.position = CGPoint(x: size.width / 2, y: -safeInsets.top - 40)
        fanOverlay.addChild(title)
        // Bottom-of-pile first, left→right, wrapping.
        let s = CardArt.Scale.half
        let perRow = max(1, Int((size.width - 32) / (s.size.width + 8)))
        for (i, c) in cards.enumerated() {
            let n = CardNode(face: CardArt.Face(c), scale: s)
            let row = i / perRow, col = i % perRow
            let rowCount = min(perRow, cards.count - row * perRow)
            let rowW = CGFloat(rowCount) * (s.size.width + 8) - 8
            n.position = CGPoint(x: (size.width - rowW) / 2 + CGFloat(col) * (s.size.width + 8),
                                 y: -safeInsets.top - 70 - CGFloat(row) * (s.size.height + 10))
            n.zPosition = 1
            fanOverlay.addChild(n)
        }
        let hint = PixelTexture.label("TAP ANYWHERE TO CLOSE", size: 14, color: CRT.muted)
        hint.zPosition = 2
        hint.position = CGPoint(x: size.width / 2, y: -(size.height - safeInsets.bottom - 24))
        fanOverlay.addChild(hint)
    }

    public var isPileFanOpen: Bool { !fanOverlay.isHidden }
    public func closePileFan() { fanOverlay.isHidden = true; fanOverlay.removeAllChildren() }

    // MARK: - Hold-for-help

    /// Help takes over the deck band's room, exactly like the web's peek-band.
    public func showHelp(title: String, body: String) {
        helpPanel.removeAllChildren()
        helpPanel.isHidden = false
        let w = size.width - 16
        let h: CGFloat = 78
        let bg = PixelTexture.panelNode(size: CGSize(width: w, height: h), face: CRT.feltMid, border: CRT.phosphor)
        bg.zPosition = 0
        helpPanel.addChild(bg)
        helpPanel.position = deckPanel.position
        let t = PixelTexture.label(title, size: 16, color: CRT.phosphor, glow: true)
        t.anchorPoint = CGPoint(x: 0, y: 1)
        t.zPosition = 1
        t.position = CGPoint(x: 8, y: -6)
        helpPanel.addChild(t)
        // Wrap the body by hand — one baked texture per line, no layout engine.
        for (i, line) in DealScene.wrap(body, width: Int((w - 16) / 7.2), maxLines: 3).enumerated() {
            let l = PixelTexture.label(line, size: 14, color: CRT.cardFace)
            l.anchorPoint = CGPoint(x: 0, y: 1)
            l.zPosition = 1
            l.position = CGPoint(x: 8, y: -28 - CGFloat(i) * 16)
            helpPanel.addChild(l)
        }
    }

    public func hideHelp() { helpPanel.isHidden = true; helpPanel.removeAllChildren() }
    public var isHelpVisible: Bool { !helpPanel.isHidden }

    static func wrap(_ text: String, width: Int, maxLines: Int) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ") {
            if current.isEmpty { current = String(word) }
            else if current.count + 1 + word.count <= width { current += " " + word }
            else { lines.append(current); current = String(word); if lines.count == maxLines { break } }
        }
        if lines.count < maxLines && !current.isEmpty { lines.append(current) }
        return lines
    }

    // MARK: - Effect feedback

    /// THE shared +N / −N / SAVED floating cue over a pile.
    public func floatCue(_ text: String, at pile: Int, color: UIColor) {
        guard let c = pileCenters[pile] else { return }
        let n = PixelTexture.label(text, size: 18, color: color, glow: color == CRT.phosphor)
        n.position = c
        n.zPosition = Layer.float
        floatLayer.addChild(n)
        n.run(.sequence([
            .group([.moveBy(x: 0, y: 26, duration: 0.55), .fadeOut(withDuration: 0.55)]),
            .removeFromParent(),
        ]))
    }

    /// Pulse a column's Pillar/Base plaque when its effect fires.
    public func pulseColumn(_ col: Int, base: Bool) {
        let list = base ? basePlaques : pillarPlaques
        guard col >= 0, col < list.count else { return }
        list[col].run(.sequence([.scale(to: 1.12, duration: 0.08), .scale(to: 1.0, duration: 0.12)]))
    }

    public func pileWince(_ index: Int) { guard index < piles.count else { return }; piles[index].wince() }
    public func pileLandPop(_ index: Int) { guard index < piles.count else { return }; piles[index].landPop() }

    /// The deal-out cascade: each pile's first card flies in from the deck.
    public func dealOutAnimation(from: CGPoint, completion: @escaping () -> Void) {
        let step = 0.045
        for (i, p) in piles.enumerated() {
            let target = p.position
            p.position = from
            p.alpha = 0
            p.run(.sequence([
                .wait(forDuration: Double(i) * step),
                .group([.fadeIn(withDuration: 0.08),
                        .move(to: target, duration: 0.16)]),
            ]), withKey: "dealin")
        }
        run(.sequence([.wait(forDuration: Double(piles.count) * step + 0.2), .run(completion)]))
    }

    /// One-shot CRT flicker — deal won/lost only.
    public func crtFlicker() { crt.flicker() }

    // MARK: - Frame timing

    /// A frame-time sampler. Pure arithmetic in `update` — no layout, no
    /// measurement, no allocation — so it can stay on in release builds.
    public private(set) var frameStats = FrameStats()
    private var lastFrameTime: TimeInterval = 0
    /// Draw the live readout (enabled with the `-fps` launch argument).
    public var showsFrameHUD = false
    private var fpsLabel: SKSpriteNode?
    private var fpsAccum: TimeInterval = 0

    public struct FrameStats {
        public private(set) var count = 0
        public private(set) var total: Double = 0
        public private(set) var worst: Double = 0
        /// Frames that missed a 60 Hz budget (16.7ms).
        public private(set) var over60 = 0
        public var meanMS: Double { count == 0 ? 0 : total / Double(count) * 1000 }
        public var worstMS: Double { worst * 1000 }
        public var fps: Double { meanMS == 0 ? 0 : 1000 / meanMS }

        mutating func add(_ dt: Double) {
            // Ignore the first frame and any hitch over a second (backgrounding).
            guard dt > 0, dt < 1 else { return }
            count += 1; total += dt
            if dt > worst { worst = dt }
            if dt > 1.0 / 60.0 + 0.001 { over60 += 1 }
        }
        public mutating func reset() { self = FrameStats() }
    }

    public override func update(_ currentTime: TimeInterval) {
        if lastFrameTime > 0 {
            let dt = currentTime - lastFrameTime
            frameStats.add(dt)
            if showsFrameHUD {
                fpsAccum += dt
                if fpsAccum > 0.5 {
                    fpsAccum = 0
                    fpsLabel?.removeFromParent()
                    let l = PixelTexture.label(
                        String(format: "%.1f fps · mean %.2fms · worst %.2fms · >16.7ms %d",
                               frameStats.fps, frameStats.meanMS, frameStats.worstMS, frameStats.over60),
                        size: 12, color: CRT.phosphor)
                    l.anchorPoint = CGPoint(x: 0, y: 1)
                    l.position = CGPoint(x: 6, y: -(size.height - safeInsets.bottom - 6) + l.size.height)
                    l.zPosition = Layer.crt + 1
                    addChild(l)
                    fpsLabel = l
                }
            }
        }
        lastFrameTime = currentTime
    }

    /// The deal result, on its own panel so it reads over a board full of cards.
    public func showResultBanner(_ text: String, win: Bool) {
        let tint = win ? CRT.phosphor : CRT.suitRed
        let label = PixelTexture.label(text, size: 24, color: tint, glow: win)
        let boxW: CGFloat = min(size.width - 32, label.size.width + 44)
        let boxH: CGFloat = 62
        let holder = SKNode()
        holder.zPosition = Layer.overlay
        holder.position = CGPoint(x: (size.width - boxW) / 2, y: boardRect.midY + boxH / 2)
        let bg = PixelTexture.panelNode(size: CGSize(width: boxW, height: boxH),
                                        face: CRT.feltMid, border: tint)
        bg.zPosition = 0
        holder.addChild(bg)
        label.position = CGPoint(x: boxW / 2, y: -boxH / 2)
        label.zPosition = 1
        holder.addChild(label)
        holder.setScale(0.7)
        addChild(holder)
        holder.run(.sequence([.scale(to: 1.0, duration: 0.14), .wait(forDuration: 2.2),
                              .fadeOut(withDuration: 0.4), .removeFromParent()]))
    }
}

/// The pile → column map, mirroring `GameEngine.buildPileColumns` so the
/// renderer's columns and the engine's Pillar columns can never disagree.
public enum GameEngineColumns {
    public static func map(_ colSizes: [Int], _ count: Int) -> [Int] {
        var out = [Int](repeating: 0, count: count)
        var p = 0
        for c in 0..<colSizes.count where p < count {
            var k = 0
            while k < colSizes[c] && p < count { out[p] = c; p += 1; k += 1 }
        }
        return out
    }
}
