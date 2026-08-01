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
    private var tissue: SKSpriteNode!

    private var fanButton: PixelButton!
    private var higherButton: PixelButton!
    private var sameButton: PixelButton!
    private var lowerButton: PixelButton!
    private var reshuffleButton: PixelButton!
    private var menuButton: PixelButton!
    private var buttons: [PixelButton] {
        var b = [fanButton!, higherButton!, sameButton!, lowerButton!, reshuffleButton!]
        if showsMenuButton { b.append(menuButton) }
        return b
    }

    /// The corner pause-menu button (campaign/zen deals only).
    public var showsMenuButton = false { didSet { menuButton?.isHidden = !showsMenuButton } }
    public var onMenuTapped: (() -> Void)?

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

        // The #tissue atmosphere under the board (whispers + felt nap + haze,
        // baked static). z −1: ignoresSiblingOrder is on, so equal-z order is
        // undefined and the tissue must sit strictly below every sibling.
        tissue = SKSpriteNode(texture: TissueView.texture(size: size))
        tissue.position = CGPoint(x: size.width / 2, y: -size.height / 2)
        tissue.zPosition = -1
        addChild(tissue)

        addChild(boardLayer)
        boardLayer.addChild(webLayer)
        addChild(floatLayer)
        floatLayer.zPosition = Layer.float
        addChild(deckPanel)
        addChild(rewardLine)

        hud = HUDBar(width: size.width)
        addChild(hud)

        // The guess rail: TALL slab buttons filling the board's left column,
        // matching the web's guess-side layout proportions.
        let railW: CGFloat = 52
        fanButton = PixelButton(id: "fan", title: "FAN", size: CGSize(width: railW, height: 52), role: .plain, fontSize: 14)
        higherButton = PixelButton(id: "higher", title: "▲", size: CGSize(width: railW, height: 118), role: .plain, fontSize: 22)
        sameButton = PixelButton(id: "same", title: "＝", size: CGSize(width: railW, height: 118), role: .ctaOutline, fontSize: 22)
        lowerButton = PixelButton(id: "lower", title: "▼", size: CGSize(width: railW, height: 118), role: .plain, fontSize: 22)
        reshuffleButton = PixelButton(id: "reshuffle", title: "↺ RESHUFFLE", size: CGSize(width: 210, height: 38), role: .plain, fontSize: 16)
        menuButton = PixelButton(id: "menu", title: "≡", size: CGSize(width: 34, height: 28), role: .plain, fontSize: 16)
        menuButton.isHidden = !showsMenuButton
        [fanButton, higherButton, sameButton, lowerButton, reshuffleButton, menuButton].forEach { addChild($0) }

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
        tissue.texture = TissueView.texture(size: size)
        tissue.size = size
        tissue.position = CGPoint(x: size.width / 2, y: -size.height / 2)
        crt.resize(to: size)
        crt.position = CGPoint(x: size.width / 2, y: -size.height / 2)
        layoutChrome()
        controller?.refreshAll()
    }

    /// Safe-area insets pushed in by the hosting view controller. The equality
    /// guard matters: viewDidLayoutSubviews re-pushes these on EVERY layout
    /// pass, and an unconditional relayout here cancelled the deal-out cascade
    /// the moment it started (the Phase 2 "board never moves" bug).
    public var safeInsets: UIEdgeInsets = .zero {
        didSet {
            guard safeInsets != oldValue else { return }
            if layoutDone { layoutChrome(); controller?.refreshAll() }
        }
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

        // Left rail: FAN on top, then ▲ ＝ ▼ as TALL slabs (the web's dedicated
        // guess strip fills the board column's height).
        railX = pad
        railTop = y
        let bottomLimit = -(size.height - safeInsets.bottom - pad - 52)
        let railSpan = (y - 6) - bottomLimit
        let slabH = max(88, (railSpan - fanButton.frameSize.height - 26) / 3)
        higherButton.resize(CGSize(width: fanButton.frameSize.width, height: slabH))
        sameButton.resize(CGSize(width: fanButton.frameSize.width, height: slabH))
        lowerButton.resize(CGSize(width: fanButton.frameSize.width, height: slabH))
        var ry = y - 6
        fanButton.position = CGPoint(x: railX, y: ry); ry -= fanButton.frameSize.height + 8
        higherButton.position = CGPoint(x: railX, y: ry); ry -= slabH + 6
        sameButton.position = CGPoint(x: railX, y: ry); ry -= slabH + 6
        lowerButton.position = CGPoint(x: railX, y: ry)

        // Reshuffle sits at the very bottom, centred; the pause menu bottom-left.
        reshuffleButton.position = CGPoint(x: (size.width - reshuffleButton.frameSize.width) / 2,
                                           y: -(size.height - safeInsets.bottom - pad))
        menuButton.position = CGPoint(x: pad,
                                      y: -(size.height - safeInsets.bottom - pad - 3))

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
        deckId = snap.deckId
        // The drawn web follows the VISIBLE state (a dying pile stays wired
        // until its dissolve severs it); the ENGINE adjacency follows the truth.
        refreshWeb()
        let alive = Set((0..<piles.count).filter { !snap.dead[$0] })
        controller?.pushLinks(WebLayer.adjacency(centers: pileCenters, alive: alive, rad: blockRadius))
    }

    private var deckId = "pink"
    private var blockRadius: CGFloat { cardScale.size.width * 0.46 }

    /// Rebuild the drawn connection web from what the PLAYER currently sees —
    /// called when a death dissolve completes, a revive repaints, or the board
    /// syncs. The blocking radius: a little under half a card box, as on the
    /// web (the card is the obstacle, its centre the node).
    public func refreshWeb() {
        let visibleAlive = Set((0..<piles.count).filter { !piles[$0].isDead })
        webLayer.rebuild(centers: pileCenters, alive: visibleAlive, rad: blockRadius)
    }

    public func syncHUD(stageLabel: String, phaseIndex: Int, altSuits: Bool,
                        phasesTotal: Int, showTrack: Bool, sameCharged: Bool, samePower: String?,
                        coins: Int, deckCount: Int, score: Int) {
        hud.sync(stageLabel: stageLabel, phaseIndex: phaseIndex, altSuits: altSuits,
                 phasesTotal: phasesTotal, showTrack: showTrack, sameCharged: sameCharged,
                 samePower: samePower, coins: coins, deckCount: deckCount, score: score)
        sameButton.setRole(sameCharged ? .charged : .ctaOutline)
    }

    public func syncDeckPanel(counts: [Int: Int], suitCounts: [String: Int], total: Int,
                              remaining: Int, deckId: String, mood: DeckCharacter.Mood,
                              tier: String = "regular", suitTotals: [String: Int] = [:]) {
        deckPanel.sync(counts: counts, suitCounts: suitCounts, total: total,
                       deckRemaining: remaining, deckId: deckId, mood: mood, tier: tier,
                       suitTotals: suitTotals)
    }

    /// The revealed NEXT draw (Scout / peek Pillars), or nil to clear.
    public func syncDeckPeek(_ face: CardArt.Face?) { deckPanel.syncPeek(face) }

    public func syncReward(base: Double, bonus: Double, alive: Int, minAlive: Int) {
        rewardLine.sync(base: base, bonus: bonus, alive: alive, minAlive: minAlive, width: size.width)
    }

    public func setReshuffleTitle(_ t: String) { reshuffleButton.setTitle(t) }

    public func syncControls(canGuess: Bool, showReshuffle: Bool) {
        higherButton.setEnabled(canGuess)
        sameButton.setEnabled(canGuess)
        lowerButton.setEnabled(canGuess)
        reshuffleButton.isHidden = !showReshuffle
    }

    public func setPillars(_ ids: [String?], bases: [String?]) {
        for (c, node) in pillarPlaques.enumerated() {
            node.removeAllChildren()
            if c < ids.count, let id = ids[c], let def = GameData.shared.pillarTypes.get(id) {
                node.addChild(plaque(text: String(def.label.prefix(10)), tint: CRT.gold))
            } else {
                node.addChild(emptySlot())   // the web draws EMPTY slots dashed
            }
        }
        for (c, node) in basePlaques.enumerated() {
            node.removeAllChildren()
            if c < bases.count, let id = bases[c], let def = GameData.shared.baseTypes.get(id) {
                node.addChild(plaque(text: String(def.label.prefix(10)), tint: CRT.phosphor))
            } else {
                node.addChild(emptySlot())
            }
        }
        baseIds = bases
    }

    /// An empty artifact slot: a low-contrast dashed outline, like the web's
    /// empty pillar/base cells.
    private func emptySlot() -> SKNode {
        let n = SKNode()
        let w = cardScale.size.width, h: CGFloat = 16
        let img = PixelTexture.image(size: CGSize(width: w, height: h)) { cg in
            cg.setStrokeColor(CRT.cardFace.withAlphaComponent(0.16).cgColor)
            cg.setLineWidth(1)
            cg.setLineDash(phase: 0, lengths: [4, 4])
            cg.stroke(CGRect(x: 0.5, y: 0.5, width: w - 1, height: h - 1))
        }
        let s = SKSpriteNode(texture: PixelTexture.texture(from: img))
        s.anchorPoint = CGPoint(x: 0, y: 1)
        s.zPosition = 0
        n.addChild(s)
        return n
    }
    private var baseIds: [String?] = []

    /// Light the tappable (activatable) Base plaques — a slow compositor-only
    /// pulse, the web's `.activatable` cue.
    public func syncActivatableBases(_ cols: [Int]) {
        for (c, node) in basePlaques.enumerated() {
            let on = cols.contains(c)
            if on, node.action(forKey: "act") == nil {
                node.run(.repeatForever(.sequence([
                    .fadeAlpha(to: 0.55, duration: 0.7),
                    .fadeAlpha(to: 1.0, duration: 0.7),
                ])), withKey: "act")
            } else if !on {
                node.removeAction(forKey: "act")
                node.alpha = (baseIds[safe: c] ?? nil) != nil ? 1 : 1
                node.alpha = 1
            }
        }
    }

    /// The Base plaque column at a scene point (tap-to-fire routing).
    public func baseCol(at p: CGPoint) -> Int? {
        let w = cardScale.size.width
        for (c, node) in basePlaques.enumerated() {
            guard (baseIds[safe: c] ?? nil) != nil else { continue }
            let r = CGRect(x: node.position.x - 4, y: node.position.y - 22, width: w + 8, height: 28)
            if r.contains(p) { return c }
        }
        return nil
    }

    /// Outline a set of piles as tap TARGETS (revive / Phoenix pick).
    public func setActionTargets(_ targets: [Int]) {
        for (i, p) in piles.enumerated() { p.setSelected(targets.contains(i)) }
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

    /// Motion is skipped entirely under auto-play (the scripted verification
    /// runs render instantly, the web's `prefersReduce` behaviour).
    public var reduceMotion = false

    /// THE shared +N / −N / SAVED floating cue over a pile — the web's
    /// `.pillar-float` chip: rise and fade, with a small entry pop.
    public func floatCue(_ text: String, at pile: Int, color: UIColor) {
        guard let c = pileCenters[pile] else { return }
        floatCue(text, atPoint: c, color: color)
    }

    public func floatCue(_ text: String, atPoint c: CGPoint, color: UIColor) {
        let n = PixelTexture.label(text, size: 18, color: color, glow: color == CRT.phosphor)
        n.position = c
        n.zPosition = Layer.float
        floatLayer.addChild(n)
        if reduceMotion {
            n.run(.sequence([.wait(forDuration: 0.6), .removeFromParent()]))
            return
        }
        n.setScale(0.8)
        n.run(.sequence([
            .scale(to: 1.0, duration: 0.10),
            .group([.moveBy(x: 0, y: 30, duration: 0.9), .fadeOut(withDuration: 0.9)]),
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
    public func goodPulse(at index: Int) { guard index < piles.count else { return }; piles[index].goodPulse() }

    // MARK: - Traveling cards

    /// The deck character's centre in scene space — where every deck flight
    /// starts and every return lands.
    public func deckSourcePoint() -> CGPoint {
        let c = deckPanel.characterCenter
        return CGPoint(x: deckPanel.position.x + c.x, y: deckPanel.position.y + c.y)
    }

    public func pileCardCenter(_ i: Int) -> CGPoint { pileCenters[i] ?? .zero }

    /// Begin/end a visual hold on one pile (the traveling card owns its face).
    public func beginHold(_ i: Int) { guard i < piles.count else { return }; piles[i].beginHold() }
    public func endHold(_ i: Int, suppressDead: Bool = false) {
        guard i < piles.count else { return }
        piles[i].endHold(suppressDead: suppressDead)
    }

    /// Fly a face-up card from the deck to a pile. The drawn card is visible
    /// the whole way — the pile's existing top stays under it until landing.
    public func flyDraw(face: CardArt.Face, to pile: Int, onArrive: @escaping () -> Void) {
        guard !reduceMotion, let to = pileCenters[pile] else { onArrive(); return }
        let clone = BoardFX.faceUpCard(face, scale: cardScale)
        floatLayer.addChild(clone)
        BoardFX.fly(clone, from: deckSourcePoint(), to: to,
                    duration: Double(BoardFX.drawFlightMS) / 1000, onArrive: onArrive)
    }

    /// Fly a face-down card deck → pile (a bury arriving).
    public func flyFaceDown(to pile: Int, onArrive: @escaping () -> Void) {
        guard !reduceMotion, let to = pileCenters[pile] else { onArrive(); return }
        let clone = BoardFX.faceDownCard(scale: cardScale, deckId: deckId)
        floatLayer.addChild(clone)
        BoardFX.fly(clone, from: deckSourcePoint(), to: to,
                    duration: Double(BoardFX.buryFlightMS) / 1000, onArrive: onArrive)
    }

    /// Fly a face-up card from a pile BACK to the deck (a guard bouncing the
    /// drawn card away, Phoenix returning its buried cards).
    public func flyToDeck(face: CardArt.Face?, from pile: Int, delay: TimeInterval = 0,
                          onArrive: (() -> Void)? = nil) {
        guard !reduceMotion, let from = pileCenters[pile] else { onArrive?(); return }
        let clone = face.map { BoardFX.faceUpCard($0, scale: cardScale) }
            ?? BoardFX.faceDownCard(scale: cardScale, deckId: deckId)
        clone.alpha = 0
        floatLayer.addChild(clone)
        clone.run(.sequence([.wait(forDuration: delay), .fadeIn(withDuration: 0.05), .run { [weak self] in
            guard let self else { return }
            BoardFX.fly(clone, from: from, to: self.deckSourcePoint(),
                        duration: Double(BoardFX.returnFlightMS) / 1000) { onArrive?() }
        }]))
    }

    /// Fly a face-down card pile → pile (Diamond Distribution's net moves,
    /// Donate). No identity is ever revealed.
    public func flyPileToPile(from: Int, to: Int, onArrive: @escaping () -> Void) {
        guard !reduceMotion, let a = pileCenters[from], let b = pileCenters[to] else { onArrive(); return }
        let clone = BoardFX.faceDownCard(scale: cardScale, deckId: deckId)
        floatLayer.addChild(clone)
        BoardFX.fly(clone, from: a, to: b, duration: 0.26, onArrive: onArrive)
    }

    /// The bury tuck: ghost card slivers slide down behind the pile's top,
    /// staggered — the web's `.bury-tuck` flourish (capped at 3 ghosts).
    public func buryTuck(at pile: Int, count: Int) {
        guard pile < piles.count else { return }
        if count >= 2 { floatCue("⤵\(count)", at: pile, color: CRT.muted) }
        guard !reduceMotion, let c = pileCenters[pile] else { return }
        let n = max(1, min(count, 3))
        for k in 0..<n {
            let ghost = BoardFX.faceDownCard(scale: cardScale, deckId: deckId)
            ghost.zPosition = Layer.card - 5   // behind the pile's card
            ghost.alpha = 0
            ghost.setScale(0.92)
            ghost.position = CGPoint(x: c.x, y: c.y + cardScale.size.height * 0.66)
            boardLayer.addChild(ghost)
            ghost.run(.sequence([
                .wait(forDuration: Double(k) * 0.15),
                .group([
                    .fadeAlpha(to: 0.9, duration: 0.17),
                    .move(to: CGPoint(x: c.x, y: c.y - cardScale.size.height * 0.32), duration: 0.6),
                    .scale(to: 0.66, duration: 0.6),
                ]),
                .fadeOut(withDuration: 0.05),
                .removeFromParent(),
            ]))
        }
    }

    // MARK: - The deal-out cascade

    /// When a deal begins the board reads BLANK for a beat, then a card flies
    /// out of the deck character to each pile ONE BY ONE, revealing each pile's
    /// real card as its clone lands. Ported timings: 150ms blank, 80ms step,
    /// 230ms per flight.
    public func dealCascade(tops: [CardArt.Face?], completion: @escaping () -> Void) {
        guard !reduceMotion, !piles.isEmpty else { completion(); return }
        for p in piles { p.setContentHidden(true) }
        let blank = Double(BoardFX.cascadeBlankMS) / 1000
        let step = Double(BoardFX.cascadeStepMS) / 1000
        let dur = Double(BoardFX.cascadeDurMS) / 1000
        let from = deckSourcePoint()
        for (i, p) in piles.enumerated() {
            guard i < tops.count, let face = tops[i], let to = pileCenters[i] else {
                p.setContentHidden(false); continue
            }
            run(.sequence([.wait(forDuration: blank + Double(i) * step), .run { [weak self] in
                guard let self else { return }
                let clone = BoardFX.faceUpCard(face, scale: self.cardScale)
                self.floatLayer.addChild(clone)
                BoardFX.fly(clone, from: from, to: to, duration: dur) {
                    p.setContentHidden(false)
                    p.landPop()
                }
            }]), withKey: "cascade-\(i)")
        }
        // Safety net: every card revealed + control handed back even if a
        // flight is lost to a relayout.
        run(.sequence([
            .wait(forDuration: blank + Double(piles.count) * step + dur + 0.25),
            .run { [weak self] in
                self?.piles.forEach { $0.setContentHidden(false) }
                completion()
            },
        ]), withKey: "cascade-done")
    }

    /// SUBSET REVEAL: the full deck fans out as face-down backs, the sitting-out
    /// portion dims, over an "X of Y in play" count. Anonymity total — every
    /// back is blank. ~1.2s, then removes itself.
    public func playSubsetReveal(inPlay: Int, total: Int) {
        guard total > 0, inPlay >= 0 else { return }
        let holder = SKNode()
        holder.zPosition = Layer.overlay
        holder.position = CGPoint(x: size.width / 2, y: -size.height * 0.42)
        addChild(holder)
        let cap = 55
        let drawN = min(total, cap)
        let litN = Int((Double(drawN) * Double(inPlay) / Double(total)).rounded())
        let spread = min(84.0, 10.0 + Double(drawN) * 1.4) * .pi / 180
        for i in 0..<drawN {
            let t = drawN > 1 ? Double(i) / Double(drawN - 1) : 0.5
            let angle = (t - 0.5) * spread
            let back = BoardFX.faceDownCard(scale: .half, deckId: deckId)
            back.zRotation = CGFloat(-angle)
            back.position = CGPoint(x: CGFloat(sin(angle)) * 90, y: CGFloat(cos(angle)) * 26)
            back.alpha = 0
            back.setScale(0.8)
            holder.addChild(back)
            let lit = i < litN
            back.run(.sequence([
                .wait(forDuration: Double(i) * 0.006),
                .group([.fadeAlpha(to: 1, duration: 0.12), .scale(to: 1, duration: 0.12)]),
                .wait(forDuration: 0.56),
                .fadeAlpha(to: lit ? 1 : 0.28, duration: 0.2),
            ]))
        }
        let label = PixelTexture.label("\(inPlay) of \(total) cards in play", size: 19,
                                       color: CRT.phosphor, glow: true)
        label.position = CGPoint(x: 0, y: -74)
        label.zPosition = 1
        holder.addChild(label)
        let sub = PixelTexture.label("A random hand from your deck — the rest sit this one out",
                                     size: 13, color: CRT.muted)
        sub.position = CGPoint(x: 0, y: -94)
        sub.zPosition = 1
        holder.addChild(sub)
        holder.run(.sequence([.wait(forDuration: 1.22), .fadeOut(withDuration: 0.22), .removeFromParent()]))
    }

    // MARK: - Death, saves, powers

    /// The guess-death presentation: (land) → beat → red flash → dissolve →
    /// the web severs. `onDissolved` fires after the dissolve completes.
    public func playDeathSequence(at pile: Int, onDissolved: (() -> Void)? = nil) {
        guard pile < piles.count else { onDissolved?(); return }
        if reduceMotion {
            piles[pile].dissolveToDead()
            refreshWeb()
            onDissolved?()
            return
        }
        let p = piles[pile]
        let flashDelay = Double(BoardFX.deathFlashDelayMS) / 1000
        let dissolveAfter = Double(BoardFX.deathDissolveAfterMS) / 1000
        run(.sequence([
            .wait(forDuration: flashDelay),
            .run { p.deathFlash() },
            .wait(forDuration: dissolveAfter),
            .run { [weak self] in
                p.dissolveToDead()
                self?.refreshWeb()
            },
            .wait(forDuration: 0.25),
            .run { onDissolved?() },
        ]))
    }

    /// Instant-kill presentation (Kamikaze, Heart Demolish): flash now, dissolve
    /// at 300ms — no landing beat.
    public func playImmediateDeath(at pile: Int) {
        guard pile < piles.count else { return }
        if reduceMotion {
            piles[pile].dissolveToDead()
            refreshWeb()
            return
        }
        let p = piles[pile]
        p.deathFlash()
        run(.sequence([
            .wait(forDuration: Double(BoardFX.deathDissolveAfterMS) / 1000),
            .run { [weak self] in p.dissolveToDead(); self?.refreshWeb() },
        ]))
    }

    /// THE shared pile-SAVED indicator — a protective phosphor ring sweep + a
    /// floating "SAVED · source" badge, distinct from a plain correct pulse.
    public func savedIndicator(at pile: Int, label: String?) {
        guard let c = pileCenters[pile] else { return }
        floatCue("SAVED" + (label.map { " · \($0)" } ?? ""), at: pile, color: CRT.phosphor)
        guard !reduceMotion else { return }
        let box = CGSize(width: cardScale.size.width + 6, height: cardScale.size.height + 6)
        let ring = SKSpriteNode(texture: BoardFX.ringTexture(size: box, color: CRT.phosphor, weight: 3))
        ring.position = c
        ring.zPosition = Layer.float
        ring.setScale(0.9)
        floatLayer.addChild(ring)
        ring.run(.sequence([
            .group([.scale(to: 1.22, duration: 0.75), .fadeOut(withDuration: 0.75)]),
            .removeFromParent(),
        ]))
    }

    /// The Same-Power firing flourish: a gold pulse on the hub + each linked
    /// target, and the power's name floated on the hub.
    public func powerFeedback(hub: Int?, targets: [Int], label: String?) {
        func pulse(_ idx: Int, isHub: Bool) {
            guard let c = pileCenters[idx] else { return }
            let box = CGSize(width: cardScale.size.width + 4, height: cardScale.size.height + 4)
            let ring = SKSpriteNode(texture: BoardFX.ringTexture(size: box, color: CRT.gold, weight: isHub ? 4 : 2))
            ring.position = c
            ring.zPosition = Layer.float
            ring.setScale(0.94)
            floatLayer.addChild(ring)
            ring.run(.sequence([
                .group([.scale(to: isHub ? 1.28 : 1.16, duration: 0.72), .fadeOut(withDuration: 0.72)]),
                .removeFromParent(),
            ]))
        }
        if !reduceMotion {
            if let hub { pulse(hub, isHub: true) }
            for t in targets where t != hub { pulse(t, isHub: false) }
        }
        if let hub, let label { floatCue(label, at: hub, color: CRT.gold) }
    }

    /// The synapse pulse: signal dots ride the web out of the landed pile.
    public func synapsePulse(from pile: Int) {
        guard !reduceMotion else { return }
        webLayer.pulse(from: pile)
    }

    /// "Shoulda said same" — the teasing pill over a pile that died on a tie.
    public func shouldaNudge(at pile: Int) {
        guard let c = pileCenters[pile] else { return }
        let label = PixelTexture.label("Shoulda said same", size: 13, color: CRT.cardFace)
        let pad: CGFloat = 8
        let box = CGSize(width: label.size.width + pad * 2, height: label.size.height + 8)
        let holder = SKNode()
        holder.position = CGPoint(x: c.x - box.width / 2, y: c.y + box.height / 2)
        holder.zPosition = Layer.float + 1
        let bg = PixelTexture.panelNode(size: box, face: CRT.feltMid, border: CRT.ink, shadowOffset: 2)
        holder.addChild(bg)
        label.position = CGPoint(x: box.width / 2, y: -box.height / 2)
        label.zPosition = 1
        holder.addChild(label)
        holder.alpha = 0
        floatLayer.addChild(holder)
        if reduceMotion {
            holder.run(.sequence([.fadeIn(withDuration: 0.1), .wait(forDuration: 0.9),
                                  .fadeOut(withDuration: 0.2), .removeFromParent()]))
            return
        }
        holder.setScale(0.9)
        holder.run(.sequence([
            .wait(forDuration: Double(BoardFX.deathFlashDelayMS) / 1000),
            .group([.fadeIn(withDuration: 0.16), .scale(to: 1.0, duration: 0.16),
                    .moveBy(x: 0, y: 9, duration: 0.16)]),
            .wait(forDuration: 0.68),
            .group([.fadeOut(withDuration: 0.42), .moveBy(x: 0, y: 13, duration: 0.42)]),
            .removeFromParent(),
        ]))
    }

    // MARK: - Deck character hooks

    /// Look toward a selected pile (quantized gaze), release, react, reset.
    public func charLookAt(pile: Int) {
        guard let c = pileCenters[pile] else { return }
        let src = deckSourcePoint()
        deckPanel.character.lookToward(dx: c.x - src.x, dy: c.y - src.y)
    }
    public func charReleaseLook() { deckPanel.character.releaseLook() }
    public func charReact(_ m: DeckCharacter.Mood) { deckPanel.character.react(m) }
    public func charReset() { deckPanel.character.reset() }

    // MARK: - Drag nudge

    public func dragNudge(pile: Int, dx: CGFloat, dy: CGFloat) {
        guard pile < piles.count else { return }
        piles[pile].setDragNudge(dx: dx, dy: dy)
    }
    public func clearDragNudge() { piles.forEach { $0.clearDragNudge() } }

    /// One-shot CRT flicker — deal won/lost only.
    public func crtFlicker() { crt.flicker() }

    // MARK: - Frame timing

    /// A frame-time sampler. Pure arithmetic in `update` — no layout, no
    /// measurement, no allocation — so it can stay on in release builds.
    public private(set) var frameStats = FrameStats()
    private var lastFrameTime: TimeInterval = 0
    /// Perf forensics: the controller stamps what just happened; a hitch frame
    /// records the stamp so the receipt can NAME its cause.
    public var breadcrumb = ""
    public private(set) var hitchLog: [String] = []
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
            if dt > 0.05, dt < 1, hitchLog.count < 24 {
                hitchLog.append(String(format: "%.0fms after [%@]", dt * 1000, breadcrumb))
            }
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
