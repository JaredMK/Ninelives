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
    private var hud: DealTopBar!
    private let deckPanel = DeckPanel()
    private let rewardLine = RewardLine()
    private let boardLayer = SKNode()
    private let webLayer = WebLayer()
    /// The web's `.board.fan-hint` under-cards: two rotated cream layers
    /// peeking behind every alive pile's top card while the fan toggle is on.
    private let fanPeekLayer = SKNode()
    private let floatLayer = SKNode()
    private var crt: CRTOverlay!
    private var tissue: SKSpriteNode!

    private var fanButton: PixelButton!
    private var higherButton: PixelButton!
    private var sameButton: PixelButton!
    private var lowerButton: PixelButton!
    private var reshuffleButton: PixelButton!
    private var menuButton: PixelButton!
    /// The FAN chip's own face/icon/label covers (the web's quiet recessed
    /// well + fan glyph + "FAN" label; phosphor with ink art while ON). They
    /// sit above the PixelButton's own bg/label so the chip reads like the
    /// web's, not like a boxed button.
    private var fanCoverOff: SKSpriteNode?
    private var fanCoverOn: SKSpriteNode?
    private var fanIcon: SKSpriteNode?
    private var fanCaption: SKSpriteNode?
    private var buttons: [PixelButton] {
        var b = [fanButton!, higherButton!, sameButton!, lowerButton!, reshuffleButton!]
        if showsMenuButton { b.append(menuButton) }
        return b
    }

    /// The corner pause-menu button (campaign/zen deals only).
    public var showsMenuButton = false { didSet { menuButton?.isHidden = !showsMenuButton } }
    public var onMenuTapped: (() -> Void)?

    /// The hold-for-help panel; takes over the deck band's room, like the web.
    private let helpPanel = SKNode()

    // MARK: Board
    private var piles: [PileNode] = []
    private var pileColumns: [Int] = []
    private var columnSizes: [Int] = []
    private var cardScale: CardArt.Scale = .three
    private var pillarPlaques: [SKNode] = []
    private var basePlaques: [SKNode] = []
    /// Campaign/debug deals show the artifact slot rows (the web's `show-slots`
    /// stays on through play); Zen collapses them for bigger cards.
    public var slotsVisible = true
    /// Zen deals run the slim chrome (the web hides `#dealStatus`, the coins
    /// and the SCORE chip in Zen): no reward band, a compacted centred board.
    public var isZen = false
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
        // The fan peek layers sit BEHIND the piles' top cards (and behind the
        // web — the pile cards render at z 0 in this layer, the web at 10).
        fanPeekLayer.zPosition = -5
        boardLayer.addChild(fanPeekLayer)
        addChild(floatLayer)
        floatLayer.zPosition = Layer.float
        addChild(deckPanel)
        addChild(rewardLine)

        hud = DealTopBar(width: size.width)
        addChild(hud)

        // The guess rail: TALL slab buttons filling the board's left column,
        // matching the web's guess-side layout proportions.
        let railW: CGFloat = 52
        fanButton = PixelButton(id: "fan", title: "FAN", size: CGSize(width: railW, height: 46), role: .plain, fontSize: 14)
        higherButton = PixelButton(id: "higher", title: "▲", size: CGSize(width: railW, height: 118), role: .plain, fontSize: 22)
        sameButton = PixelButton(id: "same", title: "＝", size: CGSize(width: railW, height: 118), role: .ctaOutline, fontSize: 22)
        lowerButton = PixelButton(id: "lower", title: "▼", size: CGSize(width: railW, height: 118), role: .plain, fontSize: 22)
        reshuffleButton = PixelButton(id: "reshuffle", title: "↺ RESHUFFLE", size: CGSize(width: 210, height: 38), role: .plain, fontSize: 16)
        menuButton = PixelButton(id: "menu", title: "≡", size: CGSize(width: 34, height: 28), role: .plain, fontSize: 16)
        menuButton.isHidden = !showsMenuButton
        menuButton.zPosition = Layer.chrome + 1   // above the baked top-bar content
        [fanButton, higherButton, sameButton, lowerButton, reshuffleButton, menuButton].forEach { addChild($0) }
        buildFanChip()

        helpPanel.zPosition = Layer.overlay
        helpPanel.isHidden = true
        addChild(helpPanel)

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

        rewardLine.isHidden = isZen   // Zen hides #dealStatus — no reward band
        if !isZen {
            rewardLine.position = CGPoint(x: 0, y: y - 10)
            y -= 26
        }

        // Bottom reservation: never hug the screen edge — a real gap for
        // the home-indicator zone and down-swipes even where the safe-area
        // bottom inset is 0, PLUS a fixed lift so the lowest cards stay
        // comfortably thumb-reachable. RESHUFFLE rides just above the
        // reserved strip; Zen has no reshuffle (climb deals only).
        let bottomGap = max(safeInsets.bottom, 20) + 12
        let footerZone: CGFloat = 34
        let reshuffleY = -(size.height - bottomGap - 4 - footerZone)
        reshuffleButton.isHidden = isZen
        reshuffleButton.position = CGPoint(x: (size.width - reshuffleButton.frameSize.width) / 2,
                                           y: reshuffleY)
        let boardBottom = isZen ? reshuffleY - 6
                                : reshuffleY - reshuffleButton.frameSize.height - 6

        // The ≡ pause button lives IN the top bar, like the web's global
        // top-left menu button (it used to sit bottom-left).
        menuButton.position = CGPoint(x: 4, y: -(top + 6))

        // Left rail: FAN on top, then ▲ ＝ ▼ as TALL slabs (the web's dedicated
        // guess strip fills the board column's height).
        railX = pad
        railTop = y
        let bottomLimit = boardBottom - 8
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

        // The board owns everything right of the rail.
        let boardX = railX + fanButton.frameSize.width + 10
        let boardW = size.width - boardX - pad
        boardRect = CGRect(x: boardX, y: boardBottom, width: boardW, height: y - boardBottom)

        rebuildBoardLayout()
    }

    // MARK: - Fan chip + build footer

    /// The web's `.fan-all-btn`: a quiet recessed deep-felt well riding the top
    /// of the left rail — the three-card fan glyph over a tiny "FAN" caption,
    /// phosphor with ink art while the hint is ON. The covers sit above the
    /// PixelButton's own bg/label (z 0/1), so the underlying button keeps the
    /// hit/press plumbing while the chip reads like the web's.
    private func buildFanChip() {
        let box = fanButton.frameSize
        let coverOff = PixelTexture.panelNode(size: box, face: CRT.feltDeep,
                                              border: CRT.ink, shadowOffset: CRT.pressSink)
        coverOff.zPosition = 1.5
        fanButton.addChild(coverOff)
        fanCoverOff = coverOff
        let coverOn = PixelTexture.panelNode(size: box, face: CRT.phosphor,
                                             border: CRT.ink, shadowOffset: CRT.pressSink)
        coverOn.zPosition = 1.5
        coverOn.isHidden = true
        fanButton.addChild(coverOn)
        fanCoverOn = coverOn
        let icon = SKSpriteNode(texture: DealScene.fanIconTexture())
        icon.size = icon.texture!.size()
        icon.position = CGPoint(x: box.width / 2, y: -16)
        icon.zPosition = 2
        icon.color = CRT.cardFace
        icon.colorBlendFactor = 1
        icon.alpha = 0.72
        fanButton.addChild(icon)
        fanIcon = icon
        let cap = PixelTexture.label("FAN", size: 12, color: CRT.cardFace.withAlphaComponent(0.72))
        cap.position = CGPoint(x: box.width / 2, y: -34)
        cap.zPosition = 2
        fanButton.addChild(cap)
        fanCaption = cap
    }

    /// Sync the chip's ON/OFF look with the hint state.
    private func updateFanChip() {
        fanCoverOff?.isHidden = fanHintOn
        fanCoverOn?.isHidden = !fanHintOn
        fanIcon?.color = fanHintOn ? CRT.ink : CRT.cardFace
        fanIcon?.colorBlendFactor = 1
        fanIcon?.alpha = fanHintOn ? 1 : 0.72
        fanCaption?.removeFromParent()
        let cap = PixelTexture.label("FAN", size: 12,
                                     color: fanHintOn ? CRT.ink : CRT.cardFace.withAlphaComponent(0.72))
        cap.position = CGPoint(x: fanButton.frameSize.width / 2, y: -34)
        cap.zPosition = 2
        fanButton.addChild(cap)
        fanCaption = cap
    }

    /// The Same-Power chip's icon: a small unique gold pixel mark per power
    /// (the web gives every power its own monoline logo — GLYPHS). 8×8
    /// matrices, baked once; unknown powers fall back to the class diamond.
    private static var samePowerIconCache: [String: SKTexture] = [:]
    static func samePowerIcon(effect: String) -> SKTexture {
        if let c = samePowerIconCache[effect] { return c }
        let matrices: [String: [String]] = [
            "linkBury": [   // arrow down onto a stack
                "...GG...",
                "...GG...",
                "...GG...",
                ".GGGGGG.",
                "..GGGG..",
                "...GG...",
                ".GGGGGG.",
                "........"],
            "linkRevive": [ // a sprout rising
                ".G....G.",
                ".GG..GG.",
                ".GGG.GG.",
                "..GGGG..",
                "...GG...",
                "...GG...",
                "..GGGG..",
                "........"],
            "linkCoins": [  // a coin
                "..GGGG..",
                ".GGGGGG.",
                "GGGGGGGG",
                "GGGGGGGG",
                "GGGGGGGG",
                "GGGGGGGG",
                ".GGGGGG.",
                "..GGGG.."],
            "linkShuffle": [// the swap hourglass
                ".G....G.",
                ".GG..GG.",
                "..GGGG..",
                "...GG...",
                "...GG...",
                "..GGGG..",
                ".GG..GG.",
                ".G....G."],
            "samePeek": [   // an eye
                "..GGGG..",
                ".G....G.",
                "G..GG..G",
                "G..GG..G",
                "G..GG..G",
                "G..GG..G",
                ".G....G.",
                "..GGGG.."],
            "linkHeavy": [  // an anchor
                "...GG...",
                "..G..G..",
                "...GG...",
                "...G....",
                "GGGGGGGG",
                "G..GG..G",
                ".GG..GG.",
                "..GGGG.."],
        ]
        let rows = matrices[effect] ?? [
            "...GG...",
            "..G..G..",
            ".G.GG.G.",
            "G.G..G.G",
            "G.G..G.G",
            ".G.GG.G.",
            "..G..G..",
            "...GG..."]
        let cell: CGFloat = 2.5
        let side = CGFloat(8) * cell
        let img = PixelTexture.image(size: CGSize(width: side, height: side)) { cg in
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() where ch == "G" {
                    cg.setFillColor(CRT.gold.cgColor)
                    cg.fill(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell,
                                   width: cell, height: cell))
                }
            }
        }
        let tex = PixelTexture.texture(from: img)
        samePowerIconCache[effect] = tex
        return tex
    }

    /// The fan glyph: three card outlines — one straight, the outer two
    /// rotated ±14° — the web's inline `#fanAllBtn` SVG, redrawn at 22pt.
    private static func fanIconTexture() -> SKTexture {
        let s: CGFloat = 22.0 / 14.0   // the web's 14×14 viewBox at 22pt
        let img = PixelTexture.image(size: CGSize(width: 22, height: 22)) { cg in
            cg.setStrokeColor(UIColor.white.cgColor)   // tinted via colorBlend
            cg.setLineWidth(1.3 * s)
            func card(_ x: CGFloat, _ y: CGFloat, deg: CGFloat, aboutX: CGFloat, aboutY: CGFloat) {
                cg.saveGState()
                cg.translateBy(x: aboutX * s, y: aboutY * s)
                cg.rotate(by: deg * .pi / 180)
                cg.translateBy(x: -aboutX * s, y: -aboutY * s)
                let p = UIBezierPath(roundedRect: CGRect(x: x * s, y: y * s, width: 5.4 * s, height: 8 * s),
                                     cornerRadius: 1.1 * s)
                cg.addPath(p.cgPath)
                cg.strokePath()
                cg.restoreGState()
            }
            card(1.4, 3.6, deg: -14, aboutX: 4.1, aboutY: 7.6)
            card(4.3, 2.8, deg: 0, aboutX: 0, aboutY: 0)
            card(7.2, 3.6, deg: 14, aboutX: 9.9, aboutY: 7.6)
        }
        return PixelTexture.texture(from: img)
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

        cardScale = DealScene.pickScale(cols: columnSizes, in: boardRect,
                                        bands: pillarBand + baseBand)
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

    /// The web's slot rows: the Pillar row above the grid (--pillar-row-h 48px)
    /// and the Base row below it (--base-row-h 32px + margin), each with one
    /// flex gap. Shown on campaign/debug deals (the web's `show-slots` stays on
    /// through play); Zen collapses them and deals bigger cards.
    private static let pillarRowH: CGFloat = 48
    private static let baseRowH: CGFloat = 34
    private var pillarBand: CGFloat { slotsVisible ? DealScene.pillarRowH + 6 : 0 }
    private var baseBand: CGFloat { slotsVisible ? DealScene.baseRowH + 6 : 0 }

    /// Choose the biggest card size that fits the board box.
    private static func pickScale(cols: [Int], in rect: CGRect, bands: CGFloat) -> CardArt.Scale {
        guard !cols.isEmpty, rect.width > 0 else { return .half }
        let rows = cols.max() ?? 3
        for scale in [CardArt.Scale.full, .three, .half] {
            let w = CGFloat(cols.count) * scale.size.width + CGFloat(cols.count - 1) * 8
            let h = CGFloat(rows) * scale.size.height + CGFloat(rows - 1) * 8
            if w <= rect.width && h <= rect.height - bands { return scale }
        }
        return .half
    }

    /// Column/pile placement mirrors the web's fitBoard + column grid:
    /// columns spread EDGE TO EDGE (`justify-content: space-between`), a light
    /// deal's freed height becomes inter-card gap so the tallest column fills
    /// the grid (vGap, capped at 1.3× the card), and shorter columns centre
    /// vertically against it — that centring is the web's row stagger.
    private func rebuildBoardLayout() {
        guard !piles.isEmpty, boardRect.width > 0 else { return }
        let bands = pillarBand + baseBand
        cardScale = DealScene.pickScale(cols: columnSizes, in: boardRect, bands: bands)
        let box = cardScale.size
        let cols = columnSizes.count
        let baseGap: CGFloat = 8

        let gridTop = boardRect.maxY - pillarBand
        let gridH = max(box.height, gridTop - boardRect.minY - baseBand)
        let rows = CGFloat(columnSizes.max() ?? 1)
        // fitBoard's vGap: spread the tallest column to fill the grid. Zen caps
        // the spread tighter (1.1×) and CENTRES the whole pile block vertically
        // instead — the piles sit in the thumb zone, not edge-to-edge.
        let vGap: CGFloat = rows > 1
            ? max(baseGap, min((gridH - rows * box.height) / (rows - 1),
                               (isZen ? 1.1 : 1.3) * box.height))
            : 0
        let blockH = rows * box.height + max(0, rows - 1) * vGap
        let blockTop = isZen ? CRT.snap(gridTop - (gridH - blockH) / 2) : gridTop

        pileCenters.removeAll(keepingCapacity: true)
        var pileIndex = 0
        for (c, colCount) in columnSizes.enumerated() {
            // space-between: first column flush left, last flush right.
            let colX: CGFloat = cols == 1
                ? CRT.snap(boardRect.midX - box.width / 2)
                : CRT.snap(boardRect.minX + CGFloat(c) * (boardRect.width - box.width) / CGFloat(cols - 1))
            let colH = CGFloat(colCount) * box.height + CGFloat(colCount - 1) * vGap
            // Shorter columns centre against the block (the stagger).
            let startY = isZen
                ? CRT.snap(blockTop - (blockH - colH) / 2)
                : CRT.snap(gridTop - (gridH - colH) / 2)

            // The Pillar row: ONE level row above the grid (web .board-pillars).
            if c < pillarPlaques.count {
                pillarPlaques[c].position = CGPoint(x: colX, y: boardRect.maxY)
            }
            for r in 0..<colCount {
                guard pileIndex < piles.count else { break }
                let y = CRT.snap(startY - CGFloat(r) * (box.height + vGap))
                piles[pileIndex].position = CGPoint(x: colX, y: y)
                pileCenters[pileIndex] = CGPoint(x: colX + box.width / 2, y: y - box.height / 2)
                pileIndex += 1
            }
            // The Base row: ONE level row below the grid (web .board-bases).
            if c < basePlaques.count {
                basePlaques[c].position = CGPoint(x: colX, y: boardRect.minY + baseBand - 6)
            }
        }
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
        public var minStates: [BoardState.MinState]
        public init(tops: [LiveCard?], counts: [Int], weighted: [Int], dead: [Bool],
                    anchored: [Bool], pileCards: [[LiveCard]], deckId: String,
                    minStates: [BoardState.MinState]) {
            self.tops = tops; self.counts = counts; self.weighted = weighted
            self.dead = dead; self.anchored = anchored; self.pileCards = pileCards
            self.deckId = deckId; self.minStates = minStates
        }
    }

    public func syncBoard(_ snap: BoardSnapshot) {
        // A board change invalidates any open pile fan (stale card faces).
        hidePileFan()
        for (i, p) in piles.enumerated() where i < snap.tops.count {
            p.sync(top: snap.tops[i], count: snap.counts[i], dead: snap.dead[i],
                   deckId: snap.deckId, weighted: snap.weighted[i], anchored: snap.anchored[i],
                   minState: snap.minStates[i])
        }
        deckId = snap.deckId
        // The fan hint's peek layers track life/death (web: `.pile:not(.dead)`).
        if fanHintOn { buildFanPeek(animate: false) } else if !fanPeekLayer.children.isEmpty {
            fanPeekLayer.removeAllChildren()
        }
        // The drawn web follows the VISIBLE state (a dying pile stays wired
        // until its dissolve severs it); the ENGINE adjacency follows the truth.
        refreshWeb()
        let alive = Set((0..<piles.count).filter { !snap.dead[$0] })
        controller?.pushLinks(WebLayer.adjacency(centers: pileCenters, alive: alive, rad: blockRadius))
    }

    private var deckId = "pink"
    private var blockRadius: CGFloat { cardScale.size.width * 0.46 }

    /// The Tell / Spade Whispers directional hints, one per pile (nil = none).
    /// Pushed every board refresh so a hint tracks the real deck top and dies
    /// with its pile (web `renderPileHints`).
    public func syncPileHints(_ dirs: [Guess?]) {
        for (i, p) in piles.enumerated() { p.syncHint(i < dirs.count ? dirs[i] : nil) }
    }

    // MARK: - Histogram scrub (the deck band's drag-odds readout)

    /// The histogram rank under a scene point, if the point is over the deck
    /// band's rank histogram (the web's `stripBarAt`).
    public func histogramRank(at scenePoint: CGPoint) -> (value: Int, label: String)? {
        let local = CGPoint(x: scenePoint.x - deckPanel.position.x,
                            y: scenePoint.y - deckPanel.position.y)
        return deckPanel.rankValue(atLocal: local)
    }

    public func showScrub(value: Int, label: String) { deckPanel.showScrub(value: value, label: label) }
    public func hideScrub() { deckPanel.hideScrub() }

    // MARK: - HUD chip hit-testing (hold-for-help)

    /// The HUD chip id under a scene point (sameCharge / samePower / stageRun /
    /// dealStatus / score / coins), or nil. Drives the top-bar hold-for-help.
    public func hudChip(at scenePoint: CGPoint) -> String? {
        let local = CGPoint(x: scenePoint.x - hud.position.x, y: scenePoint.y - hud.position.y)
        if let id = hud.chipId(at: local) { return id }
        if !rewardLine.isHidden {
            let r = CGRect(x: 0, y: rewardLine.position.y - 13, width: size.width, height: 26)
            if r.contains(scenePoint) { return "dealStatus" }
        }
        return nil
    }

    /// Rebuild the drawn connection web from what the PLAYER currently sees —
    /// called when a death dissolve completes, a revive repaints, or the board
    /// syncs. The blocking radius: a little under half a card box, as on the
    /// web (the card is the obstacle, its centre the node).
    public func refreshWeb() {
        let visibleAlive = Set((0..<piles.count).filter { !piles[$0].isDead })
        webLayer.rebuild(centers: pileCenters, alive: visibleAlive, rad: blockRadius)
    }

    public func syncHUD(phaseIndex: Int, altSuits: Bool,
                        phasesTotal: Int, showTrack: Bool, sameCharged: Bool, samePower: String?,
                        coins: Int, score: Int, zen: Bool) {
        hud.sync(phaseIndex: phaseIndex, altSuits: altSuits,
                 phasesTotal: phasesTotal, showTrack: showTrack, sameCharged: sameCharged,
                 samePower: samePower, coins: coins, score: score,
                 menuShown: showsMenuButton, zen: zen)
        sameButton.setRole(sameCharged ? .charged : .ctaOutline)
    }

    public func syncDeckPanel(counts: [Int: Int], suitCounts: [String: Int], total: Int,
                              remaining: Int, deckId: String, mood: DeckCharacter.Mood,
                              tier: String = "regular", suitTotals: [String: Int] = [:],
                              rankTotals: [Int: Int] = [:]) {
        deckPanel.sync(counts: counts, suitCounts: suitCounts, total: total,
                       deckRemaining: remaining, deckId: deckId, mood: mood, tier: tier,
                       suitTotals: suitTotals, rankTotals: rankTotals)
    }

    /// The revealed NEXT draw (Scout / peek Pillars), or nil to clear.
    public func syncDeckPeek(_ face: CardArt.Face?) { deckPanel.syncPeek(face) }

    public func syncReward(base: Double, bonus: Double, alive: Int, minAlive: Int) {
        rewardLine.sync(base: base, bonus: bonus, alive: alive, minAlive: minAlive, width: size.width)
    }

    public func setReshuffleTitle(_ t: String) { reshuffleButton.setTitle(t) }

    public func syncControls(canGuess: Bool, showReshuffle: Bool, reshuffleEnabled: Bool = true) {
        higherButton.setEnabled(canGuess)
        sameButton.setEnabled(canGuess)
        lowerButton.setEnabled(canGuess)
        // Web parity (renderReshuffleBtn): an unaffordable reshuffle stays
        // VISIBLE with its price, disabled — it never hides for poverty.
        reshuffleButton.isHidden = !showReshuffle
        reshuffleButton.setEnabled(reshuffleEnabled)
    }

    public func setPillars(_ ids: [String?], bases: [String?]) {
        pillarBadges.removeAll()   // the rebuild below drops the badge nodes too
        for (c, node) in pillarPlaques.enumerated() {
            node.removeAllChildren()
            if c < ids.count, let id = ids[c], let def = GameData.shared.pillarTypes.get(id) {
                let p = plaque(text: String(def.label.prefix(10)), tint: CRT.gold)
                p.position = CGPoint(x: 0, y: -4)
                node.addChild(p)
            } else if slotsVisible {
                node.addChild(emptyPillarSlot())   // the web's dashed empty slot
            }
        }
        for (c, node) in basePlaques.enumerated() {
            node.removeAllChildren()
            if c < bases.count, let id = bases[c], let def = GameData.shared.baseTypes.get(id) {
                let p = plaque(text: String(def.label.prefix(10)), tint: CRT.phosphor)
                p.position = CGPoint(x: 0, y: -9)
                node.addChild(p)
            } else if slotsVisible {
                node.addChild(emptyBaseSlot())
            }
        }
        baseIds = bases
    }

    /// An empty Pillar slot: the web's `.cph-banner.empty` — a small dashed
    /// gold box (72% of the column, max 74pt × 30pt) centred in the slot row.
    private func emptyPillarSlot() -> SKNode {
        let w = min(cardScale.size.width * 0.72, 74), h: CGFloat = 30
        let img = PixelTexture.image(size: CGSize(width: w, height: h)) { cg in
            cg.setStrokeColor(CRT.gold.withAlphaComponent(0.35).cgColor)
            cg.setLineWidth(1)
            cg.setLineDash(phase: 0, lengths: [4, 4])
            cg.stroke(CGRect(x: 0.5, y: 0.5, width: w - 1, height: h - 1))
        }
        let s = SKSpriteNode(texture: PixelTexture.texture(from: img))
        s.anchorPoint = CGPoint(x: 0, y: 1)
        s.position = CGPoint(x: (cardScale.size.width - w) / 2,
                             y: -(DealScene.pillarRowH - h) / 2)
        let n = SKNode()
        n.addChild(s)
        return n
    }

    /// An empty Base slot: the web's `.base-banner.empty` — a thin dashed gold
    /// line (80% of the column, max 96pt) centred in the base row.
    private func emptyBaseSlot() -> SKNode {
        let w = min(cardScale.size.width * 0.8, 96), h: CGFloat = 3
        let img = PixelTexture.image(size: CGSize(width: w, height: h)) { cg in
            cg.setStrokeColor(CRT.gold.withAlphaComponent(0.35).cgColor)
            cg.setLineWidth(1)
            cg.setLineDash(phase: 0, lengths: [4, 4])
            cg.stroke(CGRect(x: 0.5, y: 0.5, width: w - 1, height: h - 1))
        }
        let s = SKSpriteNode(texture: PixelTexture.texture(from: img))
        s.anchorPoint = CGPoint(x: 0, y: 1)
        s.position = CGPoint(x: (cardScale.size.width - w) / 2,
                             y: -(DealScene.baseRowH - h) / 2)
        let n = SKNode()
        n.addChild(s)
        return n
    }
    private var baseIds: [String?] = []

    // MARK: - Pillar live badges (streak pill / count pill / Second Wind pip)

    /// The live badge a Pillar plaque carries (the web's `.cph-streak`,
    /// `.cph-count` and `.cph-sw`), driven by engine state every refresh.
    public enum PillarBadge {
        /// Consecutive-correct streak on the column; `hot` once past threshold.
        case streak(Int, hot: Bool)
        /// The live would-be payout of an accumulating scoring Pillar.
        case count(Int)
        /// Second Wind: charged pip, or the spent (dimmed) pip once fired.
        case secondWind(spent: Bool)
    }

    private var pillarBadges: [Int: SKNode] = [:]

    public func syncPillarBadges(_ badges: [Int: PillarBadge]) {
        for (_, old) in pillarBadges { old.removeFromParent() }
        pillarBadges.removeAll()
        for (c, badge) in badges where c < pillarPlaques.count {
            let node = DealScene.badgeNode(badge)
            node.position = CGPoint(x: cardScale.size.width - node.frame.width - 1, y: -5)
            node.zPosition = 2
            pillarPlaques[c].addChild(node)
            pillarBadges[c] = node
        }
    }

    /// One baked badge chip. Web styles: streak/count = ink chip, cream 12px
    /// digits (dim at zero, gold-on-ink when the streak crosses its threshold);
    /// Second Wind = a phosphor ↻ pip, felt-deep and struck once spent.
    private static func badgeNode(_ badge: PillarBadge) -> SKSpriteNode {
        let text: String
        let fill: UIColor
        var ink = CRT.cardFace
        var struck = false
        var alpha: CGFloat = 1
        switch badge {
        case .streak(let n, let hot):
            text = "\(n)"
            fill = hot ? CRT.gold : CRT.ink
            ink = hot ? CRT.ink : CRT.cardFace
            if n == 0 { alpha = 0.5 }
        case .count(let n):
            text = "\(n)"
            fill = CRT.ink
            if n == 0 { alpha = 0.5 }
        case .secondWind(let spent):
            text = "↻"
            fill = spent ? CRT.feltDeep : CRT.phosphor
            ink = spent ? CRT.muted : CRT.ink
            struck = spent
        }
        let ns = text as NSString
        let font = CRT.Font.of(13)
        let tsz = ns.size(withAttributes: [.font: font])
        let w = max(16, ceil(tsz.width) + 7), h: CGFloat = 15
        let img = PixelTexture.image(size: CGSize(width: w, height: h)) { cg in
            cg.setFillColor(fill.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: w, height: h))
            cg.setStrokeColor(CRT.cardFace.withAlphaComponent(0.4).cgColor)
            cg.setLineWidth(1)
            cg.stroke(CGRect(x: 0.5, y: 0.5, width: w - 1, height: h - 1))
            UIGraphicsPushContext(cg)
            ns.draw(at: CGPoint(x: (w - tsz.width) / 2, y: (h - tsz.height) / 2),
                    withAttributes: [.font: font, .foregroundColor: ink])
            UIGraphicsPopContext()
            if struck {
                cg.setStrokeColor(ink.cgColor)
                cg.setLineWidth(1.5)
                cg.move(to: CGPoint(x: 2, y: h / 2))
                cg.addLine(to: CGPoint(x: w - 2, y: h / 2))
                cg.strokePath()
            }
        }
        let n = SKSpriteNode(texture: PixelTexture.texture(from: img))
        n.size = img.size
        n.anchorPoint = CGPoint(x: 0, y: 1)
        n.alpha = alpha
        return n
    }

    // MARK: - Base spent state

    /// Columns whose Base has fired its once-per-deal charge (the web's
    /// `.base-banner.spent` — dimmed so "used" reads at a glance).
    private var spentBaseCols = Set<Int>()

    public func syncSpentBases(_ cols: [Int]) {
        spentBaseCols = Set(cols)
    }

    /// Light the tappable (activatable) Base plaques — a slow compositor-only
    /// pulse, the web's `.activatable` cue. Spent plaques never pulse and sit
    /// dimmed (the web's `.spent` greying).
    public func syncActivatableBases(_ cols: [Int]) {
        for (c, node) in basePlaques.enumerated() {
            let spent = spentBaseCols.contains(c)
            let on = !spent && cols.contains(c)
            if on, node.action(forKey: "act") == nil {
                node.run(.repeatForever(.sequence([
                    .fadeAlpha(to: 0.55, duration: 0.7),
                    .fadeAlpha(to: 1.0, duration: 0.7),
                ])), withKey: "act")
            } else if !on {
                node.removeAction(forKey: "act")
                node.alpha = spent ? 0.6 : 1
            }
        }
    }

    /// The Base plaque column at a scene point (tap-to-fire routing).
    public func baseCol(at p: CGPoint) -> Int? {
        let w = cardScale.size.width
        for (c, node) in basePlaques.enumerated() {
            guard (baseIds[safe: c] ?? nil) != nil else { continue }
            let r = CGRect(x: node.position.x - 4, y: node.position.y - DealScene.baseRowH,
                           width: w + 8, height: DealScene.baseRowH)
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

    /// Roles captured when a swipe arms a rail button, restored on clear —
    /// the armed button "colors in" without clobbering Same's charged state.
    private var railSwipeRoles: [ObjectIdentifier: PixelButton.Role]?

    /// The swipe indicator is the RAIL ONLY (no centre popup): the armed
    /// button pops AND colors in to the direction's fill, the others dim.
    /// nil (finger back in the dead-zone) clears the rail completely.
    public func showSwipeDirection(_ dir: Guess?) {
        guard let dir else { clearSwipeDirection(); return }
        let armed: [(PixelButton, Guess, PixelButton.Role)] = [
            (higherButton!, .higher, .cta),
            (sameButton!, .same, .gold),
            (lowerButton!, .lower, .danger),
        ]
        if railSwipeRoles == nil {
            railSwipeRoles = Dictionary(uniqueKeysWithValues: armed.map {
                (ObjectIdentifier($0.0), $0.0.currentRole)
            })
        }
        for (b, d, lit) in armed {
            b.alpha = d == dir ? 1.0 : 0.45
            b.setRole(d == dir ? lit : (railSwipeRoles?[ObjectIdentifier(b)] ?? b.currentRole))
        }
    }

    public func clearSwipeDirection() {
        buttons.forEach { $0.alpha = 1 }
        if let saved = railSwipeRoles {
            for b in [higherButton!, sameButton!, lowerButton!] {
                if let r = saved[ObjectIdentifier(b)] { b.setRole(r) }
            }
            railSwipeRoles = nil
        }
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

    /// The global slight-fan hint (the web's `.board.fan-hint`): while ON,
    /// every ALIVE pile shows two cream under-card layers peeking out rotated
    /// behind its top card. The hint is an ARMED MODE — guessing stays fully
    /// live, and a pile tap while armed opens that pile's full face-up fan
    /// (`showPileFan`, the web's openPileFan) instead of selecting.
    public func toggleFanHint() {
        fanHintOn.toggle()
        updateFanChip()
        buildFanPeek(animate: fanHintOn)
        if !fanHintOn { hidePileFan() }
    }

    /// The pile currently showing its full fan (hint armed + pile tap).
    private var fannedPile: Int?
    public var fannedPileIndex: Int? { fannedPile }

    /// The armed-mode pile tap: splay that pile's cards face-up in place (the
    /// web's `openPileFan`). Tapping the pile again, tapping empty felt, or
    /// any board change collapses it.
    public func showPileFan(_ index: Int, cards: [LiveCard]) {
        hidePileFan()
        guard index < piles.count, cards.count > 1 else { return }
        fannedPile = index
        piles[index].showFan(cards, full: true)
    }

    public func hidePileFan() {
        if let i = fannedPile, i < piles.count { piles[i].hideFan() }
        fannedPile = nil
    }

    private var fanPeekTexture: SKTexture?
    private var fanPeekScale: CardArt.Scale?

    /// Two rotated cream layers per alive pile — the web's fan-hint pseudos
    /// (::before −7° left, ::after +6° right, 84% of the card, ±7.5% offset).
    private func buildFanPeek(animate: Bool) {
        fanPeekLayer.removeAllChildren()
        guard fanHintOn else { return }
        let box = cardScale.size
        if fanPeekTexture == nil || fanPeekScale != cardScale {
            let size = CGSize(width: box.width * 0.84, height: box.height * 0.84)
            let img = PixelTexture.image(size: CGSize(width: size.width + 2, height: size.height + 2)) { cg in
                cg.setFillColor(CRT.shadow.cgColor)
                cg.fill(CGRect(x: 2, y: 2, width: size.width, height: size.height))
                cg.setFillColor(CRT.cardFace.cgColor)
                cg.fill(CGRect(origin: .zero, size: size))
                cg.setStrokeColor(CRT.ink.cgColor)
                cg.setLineWidth(1)
                cg.stroke(CGRect(x: 0.5, y: 0.5, width: size.width - 1, height: size.height - 1))
            }
            fanPeekTexture = PixelTexture.texture(from: img)
            fanPeekScale = cardScale
        }
        guard let tex = fanPeekTexture else { return }
        let off = min(box.width, box.height) * 0.075
        for (i, p) in piles.enumerated() where !p.isDead {
            guard let c = pileCenters[i] else { continue }
            for (deg, dx) in [(CGFloat(-7), -off), (CGFloat(6), off)] {
                let s = SKSpriteNode(texture: tex)
                s.position = CGPoint(x: c.x + dx, y: c.y)
                let rot = deg * .pi / 180
                if animate && !reduceMotion {
                    // The web's fanPeek keyframe: fade + un-rotate in 0.24s.
                    s.alpha = 0
                    s.zRotation = 0
                    s.run(.group([.fadeIn(withDuration: 0.24),
                                  .rotate(toAngle: rot, duration: 0.24)]))
                } else {
                    s.zRotation = rot
                }
                fanPeekLayer.addChild(s)
            }
        }
    }

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
        // Paragraphs (sticker rows) wrap independently, capped at 3 lines total.
        var lines: [String] = []
        for para in body.split(separator: "\n", omittingEmptySubsequences: true) {
            for line in DealScene.wrap(String(para), width: Int((w - 16) / 7.2), maxLines: 3) {
                lines.append(line)
                if lines.count == 3 { break }
            }
            if lines.count == 3 { break }
        }
        for (i, line) in lines.enumerated() {
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

/// §7 The deal top bar — the web's slim `.hud` line over the play screen:
/// [≡ menu] [♥ ♦ ♣ ♠ phase track] [= synapse mark] [SCORE n] … [◎ coins].
/// The ≡ button itself is a separate tappable node (DealScene.menuButton);
/// this bar leaves room for it. Unlike the old bar there is NO STG/ZEN label
/// and NO DECK count — the web shows neither on the deal screen (the deck
/// count lives in the tracker band's deck chip).
final class DealTopBar: SKNode {
    private let bg = SKSpriteNode()
    private let content = SKNode()
    private var width: CGFloat
    public private(set) var height: CGFloat = 40

    /// Last values, so a change POPS its chip (the number pop).
    private var lastCoins = Int.min
    private var lastScore = Int.min

    init(width: CGFloat) {
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

    func resize(width w: CGFloat) { width = w }

    /// Hit regions for the top bar's hold-for-help, in content-local space:
    /// (chip id, frame). Rebuilt every sync; DealScene maps them to scene
    /// space. Zen registers ONLY the Same-Charge chip (the one chip it keeps).
    var chips: [(id: String, frame: CGRect)] = []

    func chipId(at p: CGPoint) -> String? {
        for c in chips where c.frame.insetBy(dx: -4, dy: -4).contains(p) { return c.id }
        return nil
    }

    func sync(phaseIndex: Int, altSuits: Bool, phasesTotal: Int, showTrack: Bool,
              sameCharged: Bool, samePower: String?, coins: Int, score: Int,
              menuShown: Bool, zen: Bool = false) {
        let tex = PixelTexture.panel(size: CGSize(width: width, height: height))
        bg.texture = tex; bg.size = tex.size()

        content.removeAllChildren()
        chips.removeAll()
        // Zen strips the campaign chrome (score / coins / Same-Power / track)
        // but KEEPS the Same-Charge mark, hugged centred like the web's
        // `body.zen-mode .hud` (index.html:537-546).
        if zen {
            let mark = SKSpriteNode(texture: PixelTexture.texture(from: MapArt.menuLogo(width: 24)))
            mark.size = mark.texture!.size()
            mark.alpha = sameCharged ? 1 : 0.45
            mark.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            mark.position = CGPoint(x: width / 2, y: -height / 2)
            content.addChild(mark)
            chips.append(("sameCharge", CGRect(x: width / 2 - 16, y: -height + 4,
                                               width: 32, height: height - 8)))
            return
        }
        var x: CGFloat = menuShown ? 46 : 12
        let midY = -height / 2

        func put(_ node: SKSpriteNode, gap: CGFloat = 8) {
            node.anchorPoint = CGPoint(x: 0, y: 0.5)
            node.position = CGPoint(x: x, y: midY)
            content.addChild(node)
            x += node.size.width + gap
        }

        // The suit track mirrors the web's `.suit-track` (see TopShellView):
        // ♥ pre-held, each phase suit DONE once cleared, ACTIVE (baked ×1.28)
        // while in it, TODO at 26%. Alt decks show numbered stage chips. Zen
        // hides the track entirely.
        if showTrack {
            let trackStart = x
            if altSuits {
                for p in 0..<max(1, phasesTotal) {
                    let state: ChipState = phaseIndex > p ? .done : (phaseIndex == p ? .active : .todo)
                    put(stageChip(p + 1, state: state), gap: 4)
                }
            } else {
                let order = ["♥", "♦", "♣", "♠"]
                let phaseOf = ["♥": -1, "♦": 0, "♣": 1, "♠": 2]
                for s in order {
                    let ph = phaseOf[s]!
                    let done = ph < 0 || phaseIndex > ph
                    let active = !done && phaseIndex == ph
                    let base: UIColor = (s == "♥" || s == "♦") ? CRT.suitRed : CRT.cardFace
                    let color = (done || active) ? base : CRT.cardFace.withAlphaComponent(0.26)
                    put(PixelTexture.label(s, size: active ? 22 : 17, color: color), gap: 3)
                }
            }
            chips.append(("stageRun", CGRect(x: trackStart - 4, y: -height + 4,
                                             width: max(20, x - trackStart + 4), height: height - 8)))
        }

        // The Same mark: the equals-synapse logo (the menu-logo art), dim
        // until a charge is banked. Sits at the bar's centre-left like the web.
        let mark = SKSpriteNode(texture: PixelTexture.texture(from: MapArt.menuLogo(width: 24)))
        mark.size = mark.texture!.size()
        mark.alpha = sameCharged ? 1 : 0.45
        mark.anchorPoint = CGPoint(x: 0, y: 0.5)
        mark.position = CGPoint(x: width / 2 - 30, y: midY)
        content.addChild(mark)
        chips.append(("sameCharge", CGRect(x: width / 2 - 34, y: -height + 4,
                                           width: 32, height: height - 8)))
        var scoreX = width / 2 - 2
        if let samePower, let def = GameData.shared.samePowerTypes.get(samePower) {
            // The power's own pixel mark (web parity: the chip shows the
            // power's icon, never its initial).
            let icon = SKSpriteNode(texture: DealScene.samePowerIcon(effect: def.effect ?? def.id))
            icon.size = icon.texture!.size()
            icon.anchorPoint = CGPoint(x: 0, y: 0.5)
            icon.position = CGPoint(x: scoreX, y: midY)
            content.addChild(icon)
            chips.append(("samePower", CGRect(x: scoreX - 4, y: -height + 4,
                                              width: icon.size.width + 8, height: height - 8)))
        }
        scoreX += 26

        // SCORE: the one phosphor element in the bar (glow baked), muted label.
        let lab = PixelTexture.label("SCORE ", size: 12, color: CRT.muted)
        lab.anchorPoint = CGPoint(x: 0, y: 0.5)
        lab.position = CGPoint(x: scoreX, y: midY)
        content.addChild(lab)
        let val = PixelTexture.label("\(score)", size: 19, color: CRT.phosphor, glow: true)
        val.anchorPoint = CGPoint(x: 0, y: 0.5)
        val.position = CGPoint(x: scoreX + lab.size.width, y: midY)
        content.addChild(val)
        chips.append(("score", CGRect(x: scoreX - 4, y: -height + 4,
                                      width: lab.size.width + val.size.width + 8, height: height - 8)))

        // Coins, far right.
        let num = PixelTexture.label("\(coins)", size: 19, color: CRT.gold)
        var coinW = num.size.width
        var coinIcon: SKSpriteNode?
        if let img = ArtBundle.image("pxi-coin") {
            let t = PixelTexture.texture(from: img)
            let s = SKSpriteNode(texture: t)
            let ch: CGFloat = 15
            s.size = CGSize(width: ch * t.size().width / max(1, t.size().height), height: ch)
            coinIcon = s
            coinW += s.size.width + 4
        }
        var cx = width - 10 - coinW
        if let coinIcon {
            coinIcon.anchorPoint = CGPoint(x: 0, y: 0.5)
            coinIcon.position = CGPoint(x: cx, y: midY)
            content.addChild(coinIcon)
            cx += coinIcon.size.width + 4
        }
        num.anchorPoint = CGPoint(x: 0, y: 0.5)
        num.position = CGPoint(x: cx, y: midY)
        content.addChild(num)
        chips.append(("coins", CGRect(x: width - 10 - coinW - 4, y: -height + 4,
                                      width: coinW + 14, height: height - 8)))

        // Number pops: a changed coin/score chip marks its change with a beat.
        if lastCoins != Int.min && coins != lastCoins {
            num.setScale(1.25)
            num.run(.scale(to: 1.0, duration: 0.16))
        }
        if lastScore != Int.min && score != lastScore {
            val.setScale(1.25)
            val.run(.scale(to: 1.0, duration: 0.16))
        }
        lastCoins = coins
        lastScore = score
    }

    /// Web `.st-suit.st-stage`: a 23×23 bordered chip (active ×1.15 → 26),
    /// border + number in cream; TODO at 26%.
    private enum ChipState { case done, active, todo }

    private func stageChip(_ n: Int, state: ChipState) -> SKSpriteNode {
        let box: CGFloat = state == .active ? 26 : 23
        let alpha: CGFloat = state == .todo ? 0.26 : 1
        let img = PixelTexture.image(size: CGSize(width: box, height: box)) { cg in
            cg.setStrokeColor(CRT.cardFace.withAlphaComponent(alpha).cgColor)
            cg.setLineWidth(2)
            cg.stroke(CGRect(x: 1, y: 1, width: box - 2, height: box - 2))
        }
        let node = SKSpriteNode(texture: PixelTexture.texture(from: img))
        node.size = CGSize(width: box, height: box)
        let num = PixelTexture.label("\(n)", size: state == .active ? 16 : 14,
                                     color: CRT.cardFace.withAlphaComponent(alpha))
        num.position = CGPoint(x: box / 2, y: 0)
        node.addChild(num)
        return node
    }
}
