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
    /// The charge LED per column, held directly. See syncBaseLights.
    private var baseLEDs: [Int: SKSpriteNode] = [:]
    /// Campaign/debug deals show the artifact slot rows (the web's `show-slots`
    /// stays on through play); Zen collapses them for bigger cards.
    public var slotsVisible = true
    /// DAILY SUIT (v6.76): column → the suit its Daily Suit pillar shields this
    /// deal. Set through `setPillars(_:bases:dailySuits:)`; read when a
    /// suitShieldDaily plaque is drawn.
    private var dailySuits: [Int: String]?
    /// RANK SHIELD (v6.78): the rank label the shield protects this deal —
    /// one shared rank, drawn on every rankShield plaque.
    private var rankShieldRank: String?
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

        let bandH = DealScene.deckBandH
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
        let bottomGap = max(safeInsets.bottom, 20) + 26
        let footerZone: CGFloat = 34
        let reshuffleY = -(size.height - bottomGap - 4 - footerZone)
        reshuffleButton.isHidden = isZen
        reshuffleButton.position = CGPoint(x: (size.width - reshuffleButton.frameSize.width) / 2,
                                           y: reshuffleY)
        // The board must CLEAR the reshuffle bar: the button hangs DOWN from
        // reshuffleY (top-left anchor), so the board ends 6pt above its top
        // edge — otherwise the bottom grid sliver and the whole Base slot row
        // render behind the button (the old sign hid every centre-column Base).
        let boardBottom = isZen ? reshuffleY - 6 : reshuffleY + 6

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
        let cap = PixelTexture.label("FAN", size: 14, color: CRT.cardFace.withAlphaComponent(0.72))
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
        let cap = PixelTexture.label("FAN", size: 14,
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

    /// Build the pile grid. The caller passes the ENGINE's column split — the
    /// scene must never re-derive it from the pile count. It used to, which was
    /// fine while the split was a pure function of the count; a `columnPiles`
    /// Pillar (Fourth Seat) breaks that assumption, and the board would then
    /// draw the extra pile in a different column from the one the engine put it
    /// in (10 piles: engine [4,3,3] vs a re-derived [3,4,3]).
    public func buildBoard(pileCount: Int, cols: [Int]? = nil) {
        let colSizes = (cols?.isEmpty == false) ? cols! : CampaignLayout.layoutForPiles(pileCount).cols
        columnSizes = colSizes
        pileColumns = GameEngineColumns.map(colSizes, pileCount)

        piles.forEach { $0.removeFromParent() }
        piles.removeAll()
        pillarPlaques.forEach { $0.removeFromParent() }; pillarPlaques.removeAll()
        basePlaques.forEach { $0.removeFromParent() }; basePlaques.removeAll()
        pillarBadges.removeAll(); baseBadges.removeAll()   // died with their plaques

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
    // Pillars and Bases are equipment the player is meant to think about, so
    // the plaques are sized to their COLUMN (a pile wide) rather than the
    // pocket-sized chips they were. The bands grew to match — modestly, because
    // `pickScale` subtracts them from the board before choosing a card size and
    // a bigger plaque is not worth smaller cards.
    private static let pillarRowH: CGFloat = 58
    private static let baseRowH: CGFloat = 44
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

        pileBasePos.removeAll(keepingCapacity: true)
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
                pileBasePos.append(CGPoint(x: colX, y: y))
                pileIndex += 1
            }
            // The Base row: ONE level row below the grid (web .board-bases).
            if c < basePlaques.count {
                basePlaques[c].position = CGPoint(x: colX, y: boardRect.minY + baseBand - 6)
            }
        }
        applyFanSpread(animated: false)
    }

    /// Pile positions from the layout pass, before the fan spread — the spread
    /// offsets them away from the board's centre while the fan hint is armed.
    private var pileBasePos: [CGPoint] = []

    /// While the fan hint is ON the piles visibly SPREAD (the mode reads at a
    /// glance): each pile slides a few pixel-snapped points away from the
    /// board's centre. Reversible — fan off slides them back. Pile centres (hit
    /// testing, the web, the peek layers) track the spread positions.
    private func applyFanSpread(animated: Bool) {
        guard !piles.isEmpty, boardRect.width > 0 else { return }
        let f: CGFloat = fanHintOn ? 1 : 0
        let bc = CGPoint(x: boardRect.midX, y: boardRect.midY)
        let box = cardScale.size
        pileCenters.removeAll(keepingCapacity: true)
        for (i, p) in piles.enumerated() {
            guard i < pileBasePos.count else { continue }
            let base = pileBasePos[i]
            let cc = CGPoint(x: base.x + box.width / 2, y: base.y - box.height / 2)
            // Capped ±10 so the spread can never push a pile into the chrome.
            let dx = max(-10, min(10, CRT.snap((cc.x - bc.x) * 0.055 * f)))
            let dy = max(-10, min(10, CRT.snap((cc.y - bc.y) * 0.045 * f)))
            let dest = CGPoint(x: base.x + dx, y: base.y + dy)
            if animated && !reduceMotion {
                p.run(.move(to: dest, duration: 0.18), withKey: "fanSpread")
            } else {
                p.removeAction(forKey: "fanSpread")
                p.position = dest
            }
            pileCenters[i] = CGPoint(x: dest.x + box.width / 2, y: dest.y - box.height / 2)
        }
        refreshWeb()
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

    /// v6.89: a DISPLAY-ONLY badge override for one pile — the deferred-
    /// reveal window between a landing and its queued morph/grant beat. The
    /// engine's truth is untouched; nil clears. Takes effect on the next
    /// board sync (the handlers set it BEFORE refreshAll repaints).
    public func setBadgeOverride(_ pile: Int, _ stickers: [StickerRecord]?) {
        guard pile >= 0, pile < piles.count else { return }
        piles[pile].badgeOverride = stickers
    }
    public func badgeOverride(for pile: Int) -> [StickerRecord]? {
        guard pile >= 0, pile < piles.count else { return nil }
        return piles[pile].badgeOverride
    }

    /// v6.89: the reveal beat's badge flash — the chip fan pops and settles.
    public func badgeMorphFlash(at pile: Int) {
        guard pile >= 0, pile < piles.count else { return }
        piles[pile].badgePop()
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

    /// ODDS ASSIST (v6.72, all-best v6.78): light EVERY recommended
    /// (pile, call) — an inset strip along the pile's TOP edge for HIGHER,
    /// BOTTOM for LOWER, an inset frame for SAME; a pile may carry several
    /// at once when its calls tie. nil/empty clears every pile. Display only.
    public func syncAssist(_ recs: [(pile: Int, call: Guess)]?) {
        var byPile: [Int: Set<Guess>] = [:]
        for r in recs ?? [] { byPile[r.pile, default: []].insert(r.call) }
        for (i, p) in piles.enumerated() {
            p.syncAssist(byPile[i] ?? [])
        }
    }

    /// The pile whose STICKER-BADGE corner contains the point — tap-for-help
    /// (v6.52). nil when nothing badge-like sits there.
    public func stickerBadgePile(at scenePoint: CGPoint) -> Int? {
        for (i, pile) in piles.enumerated() {
            let frame = pile.stickerBadgeFrame
            guard !frame.isNull, !frame.isEmpty else { continue }
            let local = pile.convert(scenePoint, from: self)
            // A finger-friendly pad: the chips are small targets.
            if frame.insetBy(dx: -8, dy: -8).contains(local) { return i }
        }
        return nil
    }

    // MARK: - Histogram scrub (the deck band's drag-odds readout)

    /// The histogram rank under a scene point, if the point is over the deck
    /// band's rank histogram (the web's `stripBarAt`).
    public func histogramRank(at scenePoint: CGPoint) -> (value: Int, label: String)? {
        let local = CGPoint(x: scenePoint.x - deckPanel.position.x,
                            y: scenePoint.y - deckPanel.position.y)
        return deckPanel.rankValue(atLocal: local)
    }

    /// The scrub rank for a drag that left the band vertically — once the
    /// histogram hold activates, x alone keeps driving it until finger-up.
    public func histogramRank(nearX x: CGFloat) -> (value: Int, label: String)? {
        deckPanel.rankValue(nearLocalX: x - deckPanel.position.x)
    }

    public func showScrub(value: Int, label: String) { deckPanel.showScrub(value: value, label: label) }
    public func hideScrub() { deckPanel.hideScrub() }

    // MARK: - HUD chip hit-testing (hold-for-help)

    /// The HUD chip id under a scene point (sameCharge / samePower / stageRun /
    /// dealStatus / score / coins), or nil. Drives the top-bar hold/tap-for-help
    /// (v6.96: only sameCharge / samePower / dealStatus still answer help).
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
                        coins: Int, score: Int, best: Int, zen: Bool) {
        hud.sync(phaseIndex: phaseIndex, altSuits: altSuits,
                 phasesTotal: phasesTotal, showTrack: showTrack, sameCharged: sameCharged,
                 samePower: samePower, coins: coins, score: score, best: best,
                 menuShown: showsMenuButton, zen: zen)
        sameButton.setRole(sameCharged ? .charged : .ctaOutline)
    }

    public func syncDeckPanel(counts: [Int: Int], suitCounts: [String: Int], total: Int,
                              remaining: Int, deckId: String, mood: DeckCharacter.Mood,
                              tier: String = "regular", suitTotals: [String: Int] = [:],
                              rankTotals: [Int: Int] = [:], showJoker: Bool = true) {
        // Zen drops the suit-remaining column entirely (v6.52) — a standard
        // deck's tallies say nothing there and they crowded the histogram.
        deckPanel.sync(counts: counts, suitCounts: suitCounts, total: total,
                       deckRemaining: remaining, deckId: deckId, mood: mood, tier: tier,
                       suitTotals: suitTotals, rankTotals: rankTotals, showJoker: showJoker,
                       showSuits: !isZen)
    }

    /// The revealed NEXT draw (Scout / peek Pillars), or nil to clear.
    /// v6.94: the REAL card — its sticker/curse chips ride the peek card.
    public func syncDeckPeek(_ card: LiveCard?) { deckPanel.syncPeek(card) }

    public func syncReward(base: Double, bonus: Double, alive: Int, minAlive: Int) {
        rewardLine.sync(base: base, bonus: bonus, alive: alive, minAlive: minAlive, width: size.width)
    }

    public func setReshuffleTitle(_ t: String) { reshuffleButton.setTitle(t) }

    /// The Queen's Mulligan glow: while the deal's first reshuffle is FREE the
    /// button wears the charged plate (phosphor border + text glow — the one
    /// "green glow" the visual law allows; static, no animation, so the
    /// pause-behind-overlay contract has nothing to pause).
    public func setReshuffleGlow(_ on: Bool) {
        reshuffleButton.setRole(on ? .charged : .plain)
    }

    /// The deal-start reminder line for a pending free reshuffle: a one-shot
    /// phosphor cue floated above the reshuffle button (the persistent half of
    /// the reminder is the button's own "· FREE" title + glow).
    public func announceFreeRedeal() {
        let c = CGPoint(x: reshuffleButton.position.x + reshuffleButton.frameSize.width / 2,
                        y: reshuffleButton.position.y - reshuffleButton.frameSize.height - 26)
        floatCue("FIRST RESHUFFLE FREE — THE QUEEN'S MULLIGAN", atPoint: c, color: CRT.phosphor)
    }

    public func syncControls(canGuess: Bool, showReshuffle: Bool, reshuffleEnabled: Bool = true,
                             sameBlocked: Bool = false) {
        higherButton.setEnabled(canGuess)
        // MUTE curse: the Same rail goes dark AND carries a red slash chip,
        // so a dead button reads as "blocked here", not "can't guess".
        sameButton.setEnabled(canGuess && !sameBlocked)
        setSameBlockChip(sameBlocked)
        lowerButton.setEnabled(canGuess)
        // Web parity (renderReshuffleBtn): an unaffordable reshuffle stays
        // VISIBLE with its price, disabled — it never hides for poverty.
        reshuffleButton.isHidden = !showReshuffle
        reshuffleButton.setEnabled(reshuffleEnabled)
    }

    private var sameBlockChip: SKNode?
    private func setSameBlockChip(_ on: Bool) {
        if !on { sameBlockChip?.removeFromParent(); sameBlockChip = nil; return }
        guard sameBlockChip == nil else { return }
        // A suit-red ✕ plate centered exactly on the Same button.
        let chip = PixelTexture.label("✕", size: 20, color: CRT.suitRed)
        let plate = SKSpriteNode(texture: PixelTexture.panel(
            size: CGSize(width: chip.size.width + 10, height: chip.size.height + 6),
            face: CRT.feltDeep, border: CRT.suitRed, shadowOffset: 2))
        chip.position = .zero
        plate.addChild(chip)
        // A child of the button itself (its origin is its TOP-LEFT, so the
        // button spans y ∈ [-height, 0]): the local center rides every
        // relayout for free.
        plate.position = CGPoint(x: sameButton.frameSize.width / 2,
                                 y: -sameButton.frameSize.height / 2)
        plate.zPosition = Layer.float
        sameButton.addChild(plate)
        sameBlockChip = plate
    }

    public func setPillars(_ ids: [String?], bases: [String?], dailySuits: [Int: String]? = nil,
                           rankShieldRank: String? = nil) {
        // DAILY SUIT (v6.76): the suit each suitShieldDaily pillar shields THIS
        // deal, read live off the engine run state by the caller at deal start
        // / redeal (a redeal re-boots and re-calls this — no reset needed).
        self.dailySuits = dailySuits
        // RANK SHIELD (v6.78): the rank the shield protects this deal, shown
        // on every rankShield plaque (one shared rank — the most common in
        // the full deck, picked at Start Run).
        self.rankShieldRank = rankShieldRank
        pillarBadges.removeAll()   // the rebuild below drops the badge nodes too
        baseBadges.removeAll()
        for (c, node) in pillarPlaques.enumerated() {
            node.removeAllChildren()
            if c < ids.count, let id = ids[c], let def = GameData.shared.pillarTypes.get(id) {
                node.addChild(pillarArtNode(def, col: c))
            } else if slotsVisible {
                node.addChild(emptyPillarSlot())   // the web's dashed empty slot
            }
        }
        baseLEDs.removeAll()
        for (c, node) in basePlaques.enumerated() {
            node.removeAllChildren()
            if c < bases.count, let id = bases[c], let def = GameData.shared.baseTypes.get(id) {
                let art = baseArtNode(def)
                node.addChild(art)
                // Capture THIS column's LED as it is built — no name lookup.
                baseLEDs[c] = art.children.compactMap { $0 as? SKSpriteNode }
                    .first { $0.name == DealScene.chargeLEDName }
            } else if slotsVisible {
                node.addChild(emptyBaseSlot())
            }
        }
        baseIds = bases
        pillarIds = ids
    }

    /// An equipped Pillar on the board: the web's pennant ART (rod + swallowtail
    /// cloth + the item's gold emblem), never text — a square filling the slot
    /// row's height, centred in the column. Pixel-crisp (nearest filter).
    private func pillarArtNode(_ def: ItemDef, col: Int) -> SKNode {
        // Full column width, capped by the band so it never spills into the
        // first card row.
        var img = ItemArt.pillar(def, width: cardScale.size.width,
                                 height: DealScene.pillarRowH - 2)
        // DAILY SUIT (v6.76): the plaque SHOWS this deal's shielded suit — the
        // pixel suit pip replaces the item's generic emblem, inked over the
        // same ink halo (geometry mirrors ItemArt.pillar's emblem spot).
        if def.effect == "suitShieldDaily", let suit = dailySuits?[col] {
            let h = img.size.height
            let halo = (h * 0.46).rounded()
            let hx = (img.size.width - halo) / 2
            let hy = (h * 0.46 - halo / 2).rounded()
            let inset = halo * 0.10
            if let pip = PixelGlyph.suitImage(suit, size: (halo - inset * 2) * 0.75,
                                              color: CRT.gold) {
                let rect = CGRect(x: hx + inset, y: hy + inset,
                                  width: halo - inset * 2, height: halo - inset * 2)
                img = UIGraphicsImageRenderer(size: img.size).image { _ in
                    img.draw(at: .zero)
                    // Repaint the halo so the generic 📅 emblem doesn't ghost
                    // through behind the suit pip.
                    CRT.ink.setFill()
                    UIRectFill(rect)
                    pip.draw(in: CGRect(x: rect.midX - pip.size.width / 2,
                                        y: rect.midY - pip.size.height / 2,
                                        width: pip.size.width, height: pip.size.height))
                }
            }
        }
        // RANK SHIELD (v6.78, fitted v6.80): the plaque SHOWS the rank it
        // protects this deal. The ink patch is sized to the LABEL, not the
        // emblem halo — a two-glyph "10" at the 14pt display floor is wider
        // than the halo, so a fixed patch clipped it; the fitted band grows
        // with the text and stays centred on the emblem spot.
        if def.effect == "rankShield", let rank = rankShieldRank {
            let h = img.size.height
            let halo = (h * 0.46).rounded()
            let cx = img.size.width / 2
            let cy = (h * 0.46 - halo / 2).rounded() + halo / 2
            let text = NSAttributedString(string: rank, attributes: [
                .font: CRT.Font.of(14, display: true), .foregroundColor: CRT.gold,
            ])
            let ts = text.size()
            let pad: CGFloat = 3
            let rect = CGRect(x: (cx - ts.width / 2 - pad).rounded(),
                              y: (cy - ts.height / 2 - pad).rounded(),
                              width: (ts.width + pad * 2).rounded(),
                              height: (ts.height + pad * 2).rounded())
            img = UIGraphicsImageRenderer(size: img.size).image { _ in
                img.draw(at: .zero)
                CRT.ink.setFill()
                UIRectFill(rect)
                text.draw(at: CGPoint(x: rect.midX - ts.width / 2,
                                      y: rect.midY - ts.height / 2))
            }
        }
        let s = SKSpriteNode(texture: PixelTexture.texture(from: img))
        s.size = img.size
        s.anchorPoint = CGPoint(x: 0.5, y: 1)
        s.position = CGPoint(x: cardScale.size.width / 2, y: -2)
        let n = SKNode()
        n.addChild(s)
        return n
    }

    /// An equipped Base on the board: the web's plaque ART (ink frame + family-
    /// coloured symbol), centred in the base row. Pixel-crisp (nearest filter).
    private func baseArtNode(_ def: ItemDef) -> SKNode {
        let img = ItemArt.base(def, width: cardScale.size.width,
                               height: DealScene.baseRowH - 2)
        let s = SKSpriteNode(texture: PixelTexture.texture(from: img))
        s.size = img.size
        s.anchorPoint = CGPoint(x: 0.5, y: 1)
        s.position = CGPoint(x: cardScale.size.width / 2,
                             y: -(DealScene.baseRowH - img.size.height) / 2)
        let n = SKNode()
        n.addChild(s)
        // The web's `.base-charge`: a phosphor LED on the plaque's right edge
        // saying "charged — activate once this deal", going dark when spent.
        // The port had lost it — the plate's two phosphor pixels sit dead
        // centre and the family symbol is drawn straight over them.
        let led = SKSpriteNode(texture: PixelTexture.texture(from: DealScene.chargeLED(CRT.phosphor)))
        led.size = CGSize(width: 7, height: 7)
        led.anchorPoint = CGPoint(x: 1, y: 0.5)
        led.position = CGPoint(x: s.position.x + img.size.width / 2 - 5,
                               y: s.position.y - img.size.height / 2)
        led.zPosition = 3
        led.name = DealScene.chargeLEDName
        n.addChild(led)
        return n
    }

    static let chargeLEDName = "baseChargeLED"

    /// The Base plaque's status light — the ONE place a player reads whether a
    /// Base is usable: GREEN it can fire right now, AMBER charged but its
    /// criteria aren't met, RED spent for this deal. (Pillars deliberately have
    /// no light: they are passive, never player-fired, and only two of them can
    /// even be spent — a dot there would be decoration posing as data.)
    public enum BaseLight { case ready, idle, spent }

    public func syncBaseLights(_ lights: [Int: BaseLight]) {
        for (c, node) in basePlaques.enumerated() {
            // "//" = search DESCENDANTS. The LED hangs off the plaque's art
            // node, not off the plaque itself, so a plain name lookup found
            // nothing and this whole method silently did nothing — every Base
            // sat on the phosphor it was created with, spent or not.
            guard let led = baseLEDs[c] else { continue }
            _ = node
            let state = lights[c] ?? .spent
            let color: UIColor
            switch state {
            case .ready: color = CRT.phosphor
            case .idle:  color = CRT.gold
            case .spent: color = CRT.suitRed
            }
            led.texture = PixelTexture.texture(from: DealScene.chargeLED(color))
            // READY BLINKS, the other two HOLD. Colour alone was carrying the
            // whole distinction and green-vs-amber is a weak cue at 7px; the
            // motion is what actually catches the eye and says "you can fire
            // this now". Steady amber/red then read as "nothing to do here".
            //
            // The action is added ONCE and left alone — this runs on every
            // board refresh, and re-issuing it would restart the blink from
            // full every time, so a ready Base would sit permanently lit.
            if state == .ready && !reduceMotion {
                if led.action(forKey: "blink") == nil {
                    led.run(.repeatForever(.sequence([
                        .fadeAlpha(to: 0.25, duration: 0.42),
                        .fadeAlpha(to: 1.0, duration: 0.42),
                    ])), withKey: "blink")
                }
            } else {
                led.removeAction(forKey: "blink")
                led.alpha = 1
            }
        }
    }

    /// The 7px LED bitmap — a lit core inside its own soft ring. Baked once
    /// per colour and cached, never per frame.
    private static func chargeLED(_ color: UIColor) -> UIImage {
        PixelTexture.image(size: CGSize(width: 7, height: 7)) { cg in
            cg.setFillColor(color.withAlphaComponent(0.32).cgColor)
            cg.fillEllipse(in: CGRect(x: 0, y: 0, width: 7, height: 7))
            cg.setFillColor(color.cgColor)
            cg.fillEllipse(in: CGRect(x: 1.5, y: 1.5, width: 4, height: 4))
        }
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
    private var pillarIds: [String?] = []

    // MARK: - Pillar live badges (streak pill / count pill / Second Wind pip)

    /// The live badge a Pillar plaque carries (the web's `.cph-streak`,
    /// `.cph-count` and `.cph-sw`), driven by engine state every refresh.
    public enum PillarBadge {
        /// Consecutive-correct streak on the column; `hot` once past threshold.
        case streak(Int, hot: Bool)
        /// The live would-be payout of an accumulating scoring Pillar.
        case count(Int)
        /// Second Wind: charged pip, or the spent (dimmed) pip once fired.
        case secondWind
    }

    private var pillarBadges: [Int: SKNode] = [:]

    public func syncPillarBadges(_ badges: [Int: PillarBadge]) {
        for (_, old) in pillarBadges { old.removeFromParent() }
        pillarBadges.removeAll()
        // Anchored to the pennant cloth (the web's .cph-streak: bottom 18%,
        // right 12% of the art square), not the old text banner.
        let side = CRT.snap(min(cardScale.size.width, DealScene.pillarRowH))
        let clothRight = cardScale.size.width
        for (c, badge) in badges where c < pillarPlaques.count {
            let node = DealScene.badgeNode(badge)
            node.position = CGPoint(x: clothRight - side * 0.12 - node.frame.width,
                                    y: -2 - side * 0.82 + node.frame.height)
            node.zPosition = 2
            pillarPlaques[c].addChild(node)
            pillarBadges[c] = node
        }
    }

    private var baseBadges: [Int: SKNode] = [:]

    /// The live "if activated now" figure on each charged Base plaque — the
    /// web's `.base-count-badge` (left 3px / top 2px of the plaque).
    public func syncBaseBadges(_ badges: [Int: Int]) {
        for (_, old) in baseBadges { old.removeFromParent() }
        baseBadges.removeAll()
        let artLeft: CGFloat = 2
        for (c, n) in badges where c < basePlaques.count {
            let node = DealScene.badgeNode(.count(n))
            node.position = CGPoint(x: artLeft + 2, y: -3)
            node.zPosition = 2
            basePlaques[c].addChild(node)
            baseBadges[c] = node
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
        case .secondWind:
            // No spent state (router batch 2): the save is a flat 25% roll,
            // unlimited times — the badge is a constant mark, never struck.
            text = "↻"
            fill = CRT.phosphor
            ink = CRT.ink
        }
        let ns = text as NSString
        let font = CRT.Font.of(16)
        let tsz = ns.size(withAttributes: [.font: font])
        let h = max(19, ceil(tsz.height) + 3)
        let w = max(h + 2, ceil(tsz.width) + 9)
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

    /// Dim the SPENT Base plaques (the web's `.spent` greying). The "you can
    /// fire this" cue is the LED's blink (see syncBaseLights), not the plaque.
    ///
    /// The plaque used to pulse its whole alpha down to 0.55 when activatable,
    /// which fought this dim of 0.6: a READY Base spent half its cycle looking
    /// exactly as faded as a SPENT one, so the pulse was reading as "used up".
    /// Ready is now the only thing on the plaque that MOVES, and alpha means
    /// one thing again — dimmed is spent, full is not.
    public func syncSpentBases(_ cols: [Int]) {
        spentBaseCols = Set(cols)
        for (c, node) in basePlaques.enumerated() {
            node.removeAction(forKey: "act")
            node.alpha = spentBaseCols.contains(c) ? 0.6 : 1
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

    /// The Pillar plaque column at a scene point (hold-for-help routing).
    public func pillarCol(at p: CGPoint) -> Int? {
        for (c, node) in pillarPlaques.enumerated() {
            guard (pillarIds[safe: c] ?? nil) != nil else { continue }
            // Measure the ART, not a guessed box. The hand-built rect assumed
            // the plaque was exactly `pillarRowH` tall starting at the node's
            // own y — but the pennant hangs below that origin and is taller
            // since the plaques were widened, so the bottom of every Pillar
            // was dead to touch (Demolish could not be aimed at it).
            var r = node.calculateAccumulatedFrame()
            guard !r.isEmpty else { continue }
            r = r.insetBy(dx: -6, dy: -6)          // a finger's worth of slack
            if r.contains(p) { return c }
        }
        return nil
    }

    /// Outline the Pillars a Base may target (Demolish). Without this the
    /// prompt said "tap one of your Pillars" and nothing on screen said which.
    public func setPillarTargets(_ cols: [Int]) {
        for (c, node) in pillarPlaques.enumerated() {
            let on = cols.contains(c)
            if on, node.action(forKey: "pt") == nil {
                node.run(.repeatForever(.sequence([
                    .fadeAlpha(to: 0.45, duration: 0.45),
                    .fadeAlpha(to: 1.0, duration: 0.45),
                ])), withKey: "pt")
            } else if !on {
                node.removeAction(forKey: "pt")
                node.alpha = 1
            }
        }
    }

    /// Outline a set of piles as tap TARGETS (revive / Phoenix pick).
    public func setActionTargets(_ targets: [Int]) {
        for (i, p) in piles.enumerated() { p.setSelected(targets.contains(i)) }
    }

    /// MAGNET curse: a persistent suit-red ring on every magnet pile while
    /// the pull is live — the "you must play HERE" face of the engine gate.
    /// Static nodes, no animation (§10: no new continuous animations).
    private var magnetRings: [Int: SKNode] = [:]
    public func setMagnetTargets(_ targets: [Int]) {
        let want = Set(targets)
        for (i, node) in magnetRings where !want.contains(i) {
            node.removeFromParent()
            magnetRings[i] = nil
        }
        for i in want where magnetRings[i] == nil {
            guard let c = pileCenters[i] else { continue }
            let box = CGSize(width: cardScale.size.width + 8, height: cardScale.size.height + 8)
            let ring = SKSpriteNode(texture: BoardFX.ringTexture(size: box, color: CRT.suitRed, weight: 2))
            ring.position = c
            ring.zPosition = Layer.card + 5
            addChild(ring)
            magnetRings[i] = ring
        }
    }

    /// DIAMOND RIPPLE consent (v6.55): a persistent phosphor ring on every
    /// pile the offer would shuffle — the board-side half of the prompt, so
    /// "shuffle these?" names piles the player can SEE (and fan-inspect).
    /// The rings are a SEPARATE idiom from tap-target selection: a board tap
    /// while the prompt is up (e.g. arming the fan) must not wipe them.
    /// Static nodes, no animation — same rule as the magnet rings.
    private var rippleRings: [Int: SKNode] = [:]
    public func setRippleTargets(_ targets: [Int]) {
        let want = Set(targets)
        for (i, node) in rippleRings where !want.contains(i) {
            node.removeFromParent()
            rippleRings[i] = nil
        }
        for i in want where rippleRings[i] == nil {
            guard let c = pileCenters[i] else { continue }
            let box = CGSize(width: cardScale.size.width + 8, height: cardScale.size.height + 8)
            let ring = SKSpriteNode(texture: BoardFX.ringTexture(size: box, color: CRT.phosphor, weight: 2))
            ring.position = c
            ring.zPosition = Layer.card + 5
            addChild(ring)
            rippleRings[i] = ring
        }
    }

    /// A two-pile offer (Donate): mark which pile GIVES and which RECEIVES, so
    /// the prompt can say "the FROM pile" instead of a pile number that maps to
    /// nothing the player can see.
    public func setDonateTargets(from: Int, to: Int) {
        for (i, p) in piles.enumerated() {
            p.setSelected(i == from || i == to, role: i == from ? .from : (i == to ? .to : .plain))
        }
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

    /// Anywhere on the deck band (suit counts + histogram, NOT the deck stack
    /// — that has its own tap/hold). Drives the band's hold-for-help.
    public func isDeckBand(_ p: CGPoint) -> Bool {
        guard !isDeckPanel(p) else { return false }
        let r = CGRect(x: deckPanel.position.x, y: deckPanel.position.y - DealScene.deckBandH,
                       width: size.width - 16, height: DealScene.deckBandH)
        return r.contains(p)
    }
    private static let deckBandH: CGFloat = 78

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
        applyFanSpread(animated: true)   // the piles visibly spread while armed
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
    /// The ONE size the in-deal help body uses — wrapping measures with it,
    /// so it can't drift from what actually draws.
    private let helpBodySize: CGFloat = 18

    /// The RICH overload (v6.83): the body arrives already composed — a
    /// coloured, bolded sticker name inline with its cream description (the
    /// same CardInfo grammar the popups use), baked as one wrapped sprite so
    /// the board's help reads identically to the deck view's. The plain
    /// `showHelp(title:body:)` below still serves every single-colour help
    /// (pillars, bases, HUD chips, buttons).
    public func showHelp(title: String, rich: NSAttributedString) {
        helpPanel.removeAllChildren()
        helpPanel.isHidden = false
        helpReceiptText = title + "|" + rich.string
        let w = size.width - 16
        let textW = w - 16
        let block = PixelTexture.attributedText(rich, maxWidth: textW)
        let blockH = block.size().height
        let h = max(58, 34 + blockH + 10)
        let bg = PixelTexture.panelNode(size: CGSize(width: w, height: h),
                                        face: CRT.feltMid, border: CRT.phosphor)
        bg.zPosition = 0
        helpPanel.addChild(bg)
        helpPanel.position = deckPanel.position
        let t = PixelTexture.label(title, size: 20, color: CRT.phosphor, glow: true)
        t.anchorPoint = CGPoint(x: 0, y: 1)
        t.zPosition = 1
        t.position = CGPoint(x: 8, y: -6)
        helpPanel.addChild(t)
        let body = SKSpriteNode(texture: block)
        body.size = block.size()
        body.anchorPoint = CGPoint(x: 0, y: 1)
        body.zPosition = 1
        body.position = CGPoint(x: 8, y: -34)
        helpPanel.addChild(body)
    }

    public func showHelp(title: String, body: String) {
        helpPanel.removeAllChildren()
        helpPanel.isHidden = false
        helpReceiptText = title + "|" + body
        let w = size.width - 16
        // Wrap the body by hand — one baked texture per line, no layout engine.
        // Paragraphs (sticker rows) wrap independently. The panel then GROWS to
        // fit: it used to be pinned at 78pt with a hard 3-line cap, so anything
        // longer was silently cut mid-sentence — the help would state a cost or
        // a condition and stop before saying what it applied to.
        let maxLines = 12
        var lines: [String] = []
        for para in body.split(separator: "\n", omittingEmptySubsequences: true) {
            for line in DealScene.wrap(String(para), maxWidth: w - 16, size: helpBodySize, maxLines: maxLines - lines.count) {
                lines.append(line)
            }
            if lines.count >= maxLines { break }
        }
        // HELP READS AT ARM'S LENGTH. 14/16 was the smallest type in the game
        // on the panel whose entire job is to be read.
        let lineH: CGFloat = 22
        let h = max(58, 34 + CGFloat(lines.count) * lineH + 10)
        let bg = PixelTexture.panelNode(size: CGSize(width: w, height: h), face: CRT.feltMid, border: CRT.phosphor)
        bg.zPosition = 0
        helpPanel.addChild(bg)
        helpPanel.position = deckPanel.position
        let t = PixelTexture.label(title, size: 20, color: CRT.phosphor, glow: true)
        t.anchorPoint = CGPoint(x: 0, y: 1)
        t.zPosition = 1
        t.position = CGPoint(x: 8, y: -6)
        helpPanel.addChild(t)
        for (i, line) in lines.enumerated() {
            let l = PixelTexture.label(line, size: helpBodySize, color: CRT.cardFace)
            l.anchorPoint = CGPoint(x: 0, y: 1)
            l.zPosition = 1
            l.position = CGPoint(x: 8, y: -34 - CGFloat(i) * lineH)
            helpPanel.addChild(l)
        }
    }

    public func hideHelp() { helpPanel.isHidden = true; helpPanel.removeAllChildren(); helpReceiptText = "" }
    public var isHelpVisible: Bool { !helpPanel.isHidden }

    /// `-helpReceipt 1` (SameShieldUITests, v6.96): the help panel is pure
    /// SpriteKit — invisible to the XCUITest accessibility tree — so the test
    /// hook's UIKit label mirrors the last help shown here ("title|body", ""
    /// once hidden). The HUD chip ids expose the top bar's registered chips
    /// (the empty Same-Power slot registers "samePower" like a live one).
    public private(set) var helpReceiptText = ""
    public var hudChipIDs: [String] { hud?.chips.map(\.id) ?? [] }

    /// Word-wrap to a real PIXEL width, measured in the font that will actually
    /// draw the line. The old version counted CHARACTERS against `width / 7.2`,
    /// which is only right for an all-lowercase Latin line: "◉ 12" and "♠ J"
    /// and any run of capitals measured far wider than the estimate, so lines
    /// overflowed the panel while the wrapper believed they fit.
    static func wrap(_ text: String, maxWidth: CGFloat, size: CGFloat, maxLines: Int) -> [String] {
        guard maxLines > 0, maxWidth > 0 else { return [] }
        let font = CRT.Font.of(size)
        func width(_ s: String) -> CGFloat {
            (s as NSString).size(withAttributes: [.font: font]).width
        }
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ") {
            let candidate = current.isEmpty ? String(word) : current + " " + word
            if width(candidate) <= maxWidth {
                current = candidate
                continue
            }
            if current.isEmpty {
                // A single word too wide for the panel: hard-break it rather
                // than emit one overflowing line.
                var chunk = ""
                for ch in word {
                    if width(chunk + String(ch)) > maxWidth, !chunk.isEmpty {
                        lines.append(chunk)
                        if lines.count == maxLines { return lines }
                        chunk = ""
                    }
                    chunk.append(ch)
                }
                current = chunk
            } else {
                lines.append(current)
                if lines.count == maxLines { return lines }
                current = String(word)
            }
        }
        if lines.count < maxLines, !current.isEmpty { lines.append(current) }
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

    public func floatCue(_ text: String, atPoint c: CGPoint, color: UIColor, dwell: Double = 0) {
        let n = PixelTexture.label(text, size: 18, color: color, glow: color == CRT.phosphor)
        n.position = c
        n.zPosition = Layer.float
        floatLayer.addChild(n)
        if reduceMotion {
            n.run(.sequence([.wait(forDuration: 0.6 + dwell), .removeFromParent()]))
            return
        }
        n.setScale(0.8)
        n.run(.sequence([
            .scale(to: 1.0, duration: 0.10),
            .wait(forDuration: dwell),          // the roll verdict's extra hold (v6.74)
            .group([.moveBy(x: 0, y: 30, duration: 0.9), .fadeOut(withDuration: 0.9)]),
            .removeFromParent(),
        ]))
    }

    // MARK: - Roll verdicts (v6.74)

    /// THE roll verdict: one word — "HIT" (gold) / "MISS" (muted) — floated
    /// ON the item that rolled, never on the landed card. Held a beat longer
    /// than the coin float (a 0.5s dwell over the shared 0.9s rise/fade) so
    /// the outcome registers. Transform/opacity only, self-terminating, and
    /// it rides floatLayer — one-shot SKActions pause with the scene under
    /// any overlay, so the overlay-pause contract holds by construction.
    private static let rollDwell: Double = 0.5
    private func floatRollVerdict(_ hit: Bool, atPoint c: CGPoint) {
        floatCue(hit ? "HIT" : "MISS", atPoint: c,
                 color: hit ? CRT.gold : CRT.muted, dwell: Self.rollDwell)
    }

    /// Pile-centre fallback for a roll whose item anchor is missing.
    public func rollVerdict(hit: Bool, atPile pile: Int) {
        guard let c = pileCenters[pile] else { return }
        floatRollVerdict(hit, atPoint: c)
    }

    /// A PILLAR roll's verdict, centred ON the column's pillar plaque
    /// (Second Wind, Static, Flypaper, Gambler).
    public func rollVerdictAtPillar(hit: Bool, col: Int) {
        guard col >= 0, col < pillarPlaques.count, let parent = pillarPlaques[col].parent else { return }
        let f = pillarPlaques[col].calculateAccumulatedFrame()
        let pt = parent.convert(CGPoint(x: f.midX, y: f.midY), to: self)
        floatRollVerdict(hit, atPoint: pt)
    }

    /// A STICKER roll's verdict, just right of the sticker chip on the pile's
    /// top card (Saboteur, Malfunction) — the pile centre when the card
    /// somehow shows no chip.
    public func rollVerdictAtSticker(hit: Bool, pile: Int) {
        guard pile >= 0, pile < piles.count else { return }
        let f = piles[pile].stickerBadgeFrame
        if f.isNull || f.isEmpty { rollVerdict(hit: hit, atPile: pile); return }
        let pt = piles[pile].convert(CGPoint(x: f.maxX + 12, y: f.midY), to: self)
        floatRollVerdict(hit, atPoint: pt)
    }

    /// A SAME-POWER roll's verdict, beside the HUD's Same-Power chip (Long
    /// Odds). False when no chip is showing (Zen) so the caller falls back.
    @discardableResult
    public func rollVerdictAtSamePower(hit: Bool) -> Bool {
        guard let f = hud.chipFrame("samePower") else { return false }
        let pt = CGPoint(x: hud.position.x + f.midX, y: hud.position.y + f.midY)
        floatRollVerdict(hit, atPoint: pt)
        return true
    }

    /// Pulse a column's Pillar/Base plaque when its effect fires.
    /// A small cue floated beside a column's PILLAR plaque — Second Wind's
    /// saved-or-not verdict rides this (router batch 2).
    public func floatCueAtPillar(_ text: String, col: Int, color: UIColor) {
        guard col >= 0, col < pillarPlaques.count, let parent = pillarPlaques[col].parent else { return }
        let f = pillarPlaques[col].calculateAccumulatedFrame()
        let pt = parent.convert(CGPoint(x: f.midX + f.width / 2 + 14, y: f.midY), to: self)
        floatCue(text, atPoint: pt, color: color)
    }

    public func pulseColumn(_ col: Int, base: Bool) {
        let list = base ? basePlaques : pillarPlaques
        guard col >= 0, col < list.count else { return }
        list[col].run(.sequence([.scale(to: 1.12, duration: 0.08), .scale(to: 1.0, duration: 0.12)]))
    }

    /// TUTORIAL anchors: a node's accumulated frame in VIEW coordinates, so
    /// the tour's phosphor ring can hug the REAL pile / rail button instead
    /// of an approximation.
    private func viewRect(of node: SKNode) -> CGRect? {
        guard let v = view, let parent = node.parent else { return nil }
        let f = node.calculateAccumulatedFrame()   // parent coords
        let a = v.convert(parent.convert(CGPoint(x: f.minX, y: f.minY), to: self), from: self)
        let b = v.convert(parent.convert(CGPoint(x: f.maxX, y: f.maxY), to: self), from: self)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                      width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    public func pileRectInView(_ i: Int) -> CGRect? {
        guard i < piles.count else { return nil }
        return viewRect(of: piles[i])
    }

    public func railUpRectInView() -> CGRect? {
        higherButton.map { viewRect(of: $0) } ?? nil
    }

    /// A visible CHURN on a shuffled pile — quick rock + hop, one shot.
    /// Upheaval used to fire invisibly whenever the shuffle happened to leave
    /// the same card on top (and a 1-card pile always does).
    public func shuffleChurn(at index: Int) {
        guard index < piles.count else { return }
        let rock = SKAction.sequence([
            .rotate(byAngle: 0.09, duration: 0.06),
            .rotate(byAngle: -0.18, duration: 0.10),
            .rotate(byAngle: 0.14, duration: 0.08),
            .rotate(byAngle: -0.05, duration: 0.06),
        ])
        let hop = SKAction.sequence([
            .moveBy(x: 0, y: 6, duration: 0.12),
            .moveBy(x: 0, y: -6, duration: 0.18),
        ])
        piles[index].run(.group([rock, hop]))
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
    /// `duration` overrides the draw-flight speed (the STAGED Second Wind
    /// evidence slows it so a screenshot can land mid-draw).
    /// v6.94: `stickers`/`counters` dress the flying card with its chip fan
    /// (the Second Wind killer shows what it carries) — the shared chip path.
    public func flyDraw(face: CardArt.Face, to pile: Int, stickers: [StickerRecord] = [],
                        counters: LiveCard? = nil, duration: TimeInterval? = nil,
                        onArrive: @escaping () -> Void) {
        guard !reduceMotion, let to = pileCenters[pile] else { onArrive(); return }
        let clone = BoardFX.faceUpCard(face, scale: cardScale)
        if !stickers.isEmpty, let cardNode = clone as? CardNode {
            let chips = SKNode()
            // The clone anchors at its centre; the fan lays out from the card
            // box's top-left corner (the texture's top-left — shadow bleeds
            // down-right).
            chips.position = CGPoint(x: -cardNode.size.width / 2, y: cardNode.size.height / 2)
            chips.zPosition = 1
            StickerChipLayout.addBadges(records: stickers, counters: counters,
                                        cardWidth: cardScale.size.width, to: chips)
            cardNode.addChild(chips)
        }
        floatLayer.addChild(clone)
        BoardFX.fly(clone, from: deckSourcePoint(), to: to,
                    duration: duration ?? Double(BoardFX.drawFlightMS) / 1000, onArrive: onArrive)
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

    /// The reshuffle gather: before a re-deal, every visible pile card lifts
    /// off its pile and flies back to the deck character, staggered — the
    /// shuffle is SEEN, then the fresh deal cascades out. Self-terminating
    /// tweens; reduceMotion completes instantly.
    public func gatherToDeck(completion: @escaping () -> Void) {
        guard !reduceMotion else { completion(); return }
        let live = (0..<piles.count).filter { !piles[$0].isDead && pileCenters[$0] != nil }
        guard !live.isEmpty else { completion(); return }
        var landed = 0
        var finished = false
        let finish = {
            if !finished { finished = true; completion() }
        }
        for (k, i) in live.enumerated() {
            let from = pileCenters[i]!
            run(.sequence([.wait(forDuration: Double(k) * 0.05), .run { [weak self] in
                guard let self else { return }
                self.piles[i].setContentHidden(true)   // the clone takes over
                let clone = BoardFX.faceDownCard(scale: self.cardScale, deckId: self.deckId)
                self.floatLayer.addChild(clone)
                BoardFX.fly(clone, from: from, to: self.deckSourcePoint(), duration: 0.28) {
                    landed += 1
                    if landed == live.count { finish() }
                }
            }]), withKey: "gather-\(i)")
        }
        // Safety net: completion even if a flight is lost to a relayout.
        run(.sequence([
            .wait(forDuration: Double(live.count) * 0.05 + 0.28 + 0.3),
            .run { finish() },
        ]), withKey: "gather-done")
    }

    /// A pile's cards were shuffled in place (Shuffle action, Diamond Ripple,
    /// Shuffler Pillar): a quick back-and-forth rattle the player can see.
    public func shuffleWiggle(at index: Int) {
        guard index < piles.count, !reduceMotion else { return }
        piles[index].playShuffle()
    }

    /// When a deal begins the board reads BLANK for a beat, then a card flies
    /// out of the deck character to each pile ONE BY ONE, revealing each pile's
    /// real card as its clone lands. Ported timings: 150ms blank, 80ms step,
    /// 230ms per flight.
    public func dealCascade(tops: [CardArt.Face?], completion: @escaping () -> Void) {
        guard !reduceMotion, !piles.isEmpty else {
            // No cascade to run — but the reveal may have emptied the board on
            // its way in, so put the cards back before handing over. Skipping
            // this left a permanently blank board under reduced motion.
            for p in piles { p.setContentHidden(false) }
            completion()
            return
        }
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
                    // Every card that LANDS makes the paper-on-felt thwip.
                    Sound.shared.place()
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

    /// DEAL REVEAL: the full deck fans out as face-down backs, the sitting-out
    /// portion dims, over the deal's composition count. Anonymity total —
    /// every back is blank, so this conveys PROPORTION + COUNT and never which
    /// cards are in play.
    ///
    /// It runs before EVERY deal, not only the subset ones. It used to fire
    /// only once the deck had grown enough for subset deals to kick in (stage
    /// 2-ish), which made it read as a rare warning rather than as the deal's
    /// composition. A full-deck deal gets its own line — there is no "of Y"
    /// to state when nothing sits out.
    ///
    /// It also used to play OVER the deal cascade, so the count and the piles
    /// competed for the eye. The cascade now waits: `onDone` fires when the
    /// reveal has cleared, and the caller deals into the empty board. Because
    /// it gates every deal it is kept SHORT (~0.9s); reduced motion holds a
    /// static frame instead of fanning.
    public func playDealReveal(inPlay: Int, total: Int, onDone: (() -> Void)? = nil) {
        guard total > 0, inPlay >= 0 else { onDone?(); return }
        // Empty the board NOW. The caller has already painted the piles, so
        // without this the reveal floated over a fully dealt board, the cards
        // vanished when it cleared, and the cascade dealt them a second time.
        for p in piles { p.setContentHidden(true) }
        let holder = SKNode()
        holder.zPosition = Layer.overlay
        // Centre it on the BOARD, not the screen. The guess rail owns the left
        // edge, so screen-centre sits left of where the piles actually are and
        // the count read as off-kilter against them.
        holder.position = boardRect.isEmpty
            ? CGPoint(x: size.width / 2, y: -size.height * 0.42)
            : CGPoint(x: boardRect.midX, y: boardRect.midY)
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
            holder.addChild(back)
            let lit = i < litN
            if reduceMotion {
                back.alpha = lit ? 1 : 0.28       // the finished frame, no fan
                continue
            }
            back.alpha = 0
            back.setScale(0.8)
            back.run(.sequence([
                .wait(forDuration: Double(i) * 0.003),
                .group([.fadeAlpha(to: 1, duration: 0.10), .scale(to: 1, duration: 0.10)]),
                .wait(forDuration: 0.25),
                .fadeAlpha(to: lit ? 1 : 0.28, duration: 0.15),
            ]))
        }
        // FULL DECK: nothing sits out, so "X of Y in play" would state a split
        // that isn't there. It gets its own line and no explainer.
        let whole = inPlay >= total
        let label = PixelTexture.label(whole ? "Full deck · \(total) cards"
                                             : "\(inPlay) of \(total) cards in play",
                                       size: 20, color: CRT.phosphor, glow: true)
        label.position = CGPoint(x: 0, y: -74)
        label.zPosition = 1
        holder.addChild(label)
        if !whole {
            let sub = PixelTexture.label("A random hand from your deck. The rest sit this one out",
                                         size: 14, color: CRT.muted)
            sub.position = CGPoint(x: 0, y: -94)
            sub.zPosition = 1
            holder.addChild(sub)
        }
        let hold = reduceMotion ? 0.50 : 0.68
        let fade = reduceMotion ? 0.10 : 0.20
        holder.run(.sequence([.wait(forDuration: hold), .fadeOut(withDuration: fade), .removeFromParent()]))
        // The hand-off runs on the SCENE, not the holder: a node that has
        // removed itself never reaches a trailing action, which would strand
        // the deal with an empty board and no cascade.
        run(.sequence([.wait(forDuration: hold + fade), .run { onDone?() }]), withKey: "deal-reveal")
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

    /// THE shared CURSE-FIRED indicator — savedIndicator's evil twin: a
    /// suit-red ring sweep + the curse's verdict floated in red. One idiom
    /// for every curse, so "red ring = a curse just did that" reads at a
    /// glance.
    public func curseIndicator(at pile: Int, label: String) {
        guard let c = pileCenters[pile] else { return }
        floatCue(label, at: pile, color: CRT.suitRed)
        guard !reduceMotion else { return }
        let box = CGSize(width: cardScale.size.width + 6, height: cardScale.size.height + 6)
        let ring = SKSpriteNode(texture: BoardFX.ringTexture(size: box, color: CRT.suitRed, weight: 3))
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

    /// "Shoulda said same" — the taunt over a pile that died on a tie. It is
    /// meant to be OBNOXIOUS: a gold-rimmed pill that pops in oversized and
    /// WAGS side to side (the wordmark's own mocking swivel) before it
    /// saunters off. Bigger text, longer linger, zero sympathy.
    public func shouldaNudge(at pile: Int) {
        guard let c = pileCenters[pile] else { return }
        let label = PixelTexture.label("Shoulda said same", size: 16, color: CRT.gold)
        let pad: CGFloat = 10
        let box = CGSize(width: label.size.width + pad * 2, height: label.size.height + 10)
        let holder = SKNode()
        holder.position = CGPoint(x: c.x - box.width / 2, y: c.y + box.height / 2)
        holder.zPosition = Layer.float + 1
        let bg = PixelTexture.panelNode(size: box, face: CRT.feltMid, border: CRT.gold, shadowOffset: 2)
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
        // The wag pivots around the pill's CENTRE (the holder's origin is its
        // top-left corner, so the rotation rides a centred child instead).
        let pivot = SKNode()
        pivot.position = CGPoint(x: box.width / 2, y: -box.height / 2)
        bg.removeFromParent(); label.removeFromParent()
        bg.position = CGPoint(x: -box.width / 2, y: box.height / 2)
        label.position = .zero
        pivot.addChild(bg)
        pivot.addChild(label)
        holder.addChild(pivot)
        let wag = SKAction.sequence([
            .rotate(toAngle: -0.09, duration: 0.09),
            .rotate(toAngle: 0.08, duration: 0.11),
            .rotate(toAngle: -0.09, duration: 0.11),
            .rotate(toAngle: 0.06, duration: 0.10),
            .rotate(toAngle: -0.04, duration: 0.09),
            .rotate(toAngle: 0, duration: 0.08),
        ])
        holder.setScale(0.7)
        holder.run(.sequence([
            .wait(forDuration: Double(BoardFX.deathFlashDelayMS) / 1000),
            // Pop in OVER size, settle, then wag like it's very pleased.
            .group([.fadeIn(withDuration: 0.14), .scale(to: 1.18, duration: 0.14),
                    .moveBy(x: 0, y: 9, duration: 0.14)]),
            .scale(to: 1.0, duration: 0.10),
            .run { pivot.run(wag) },
            .wait(forDuration: 1.0),
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
                        size: 14, color: CRT.phosphor)
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

    /// A chip's frame in bar-local space (v6.74: the roll verdict anchors to
    /// the Same-Power chip). nil when that chip isn't showing.
    func chipFrame(_ id: String) -> CGRect? {
        chips.first { $0.id == id }?.frame
    }

    func sync(phaseIndex: Int, altSuits: Bool, phasesTotal: Int, showTrack: Bool,
              sameCharged: Bool, samePower: String?, coins: Int, score: Int,
              best: Int, menuShown: Bool, zen: Bool = false) {
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
                    let base: UIColor = CRT.suitColor(s, onFelt: true)
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
        } else {
            // v6.96: no power equipped → the EMPTY-SLOT idiom the pillar/base
            // rows use (a small dashed gold box). The chip still registers,
            // so a tap or hold on it answers "None equipped".
            let img = PixelTexture.image(size: CGSize(width: 18, height: 18)) { cg in
                cg.setStrokeColor(CRT.gold.withAlphaComponent(0.35).cgColor)
                cg.setLineWidth(1)
                cg.setLineDash(phase: 0, lengths: [4, 4])
                cg.stroke(CGRect(x: 0.5, y: 0.5, width: 17, height: 17))
            }
            let slot = SKSpriteNode(texture: PixelTexture.texture(from: img))
            slot.anchorPoint = CGPoint(x: 0, y: 0.5)
            slot.position = CGPoint(x: scoreX, y: midY)
            content.addChild(slot)
            chips.append(("samePower", CGRect(x: scoreX - 4, y: -height + 4,
                                              width: 26, height: height - 8)))
        }
        scoreX += 26

        // Measure the coin block FIRST — it owns the right edge, and the HI
        // chip may only use what is left over.
        let coinNum = PixelTexture.label("\(coins)", size: 20, color: CRT.gold)
        var coinW = coinNum.size.width
        var coinIcon: SKSpriteNode?
        if let img = ArtBundle.image("pxi-coin") {
            let t = PixelTexture.texture(from: img)
            let sp = SKSpriteNode(texture: t)
            let ch: CGFloat = 15
            sp.size = CGSize(width: ch * t.size().width / max(1, t.size().height), height: ch)
            coinIcon = sp
            coinW += sp.size.width + 4
        }

        // SCORE: the one phosphor element in the bar (glow baked), muted label.
        let lab = PixelTexture.label("SCORE ", size: 14, color: CRT.muted)
        lab.anchorPoint = CGPoint(x: 0, y: 0.5)
        lab.position = CGPoint(x: scoreX, y: midY)
        content.addChild(lab)
        let val = PixelTexture.label("\(score)", size: 20, color: CRT.phosphor, glow: true)
        val.anchorPoint = CGPoint(x: 0, y: 0.5)
        val.position = CGPoint(x: scoreX + lab.size.width, y: midY)
        content.addChild(val)
        chips.append(("score", CGRect(x: scoreX - 4, y: -height + 4,
                                      width: lab.size.width + val.size.width + 8, height: height - 8)))

        // HI: the lifetime best, right beside it, so the climb reads against
        // the record. Gold (a record, not a live value) and never glowing —
        // phosphor's glow stays reserved for the ONE live element.
        if best > 0 {
            let hiX = scoreX + lab.size.width + val.size.width + 10
            // CREAM, not gold (v6.36): gold beside gold coins made the two
            // numbers read as one family. The record now has its own colour.
            let hiLab = PixelTexture.label("HI ", size: 14, color: CRT.muted)
            let hiVal = PixelTexture.label("\(best)", size: 16, color: CRT.cardFace)
            // Only when it clears the coins — a long climb score must never
            // push HI under them. It simply drops out instead.
            if hiX + hiLab.size.width + hiVal.size.width <= width - 14 - coinW {
                hiLab.anchorPoint = CGPoint(x: 0, y: 0.5)
                hiLab.position = CGPoint(x: hiX, y: midY)
                content.addChild(hiLab)
                hiVal.anchorPoint = CGPoint(x: 0, y: 0.5)
                hiVal.position = CGPoint(x: hiX + hiLab.size.width, y: midY)
                content.addChild(hiVal)
                chips.append(("hiScore", CGRect(x: hiX - 4, y: -height + 4,
                                                width: hiLab.size.width + hiVal.size.width + 8,
                                                height: height - 8)))
            }
        }

        // Coins, far right (measured above).
        let num = coinNum
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
