import UIKit
import GameCore

/// The deck inspection modal — the full campaign deck laid out card by card,
/// with the rank histogram and per-suit counts above it. Read-only; opened
/// from the deck chip on the map/store and the deck stack in a deal.
public final class DeckInspectViewController: UIViewController {

    private let campaign: CampaignState
    /// Live-deal context (nil off-deal): which cards are still in the draw
    /// pile, so the histogram shows remaining-vs-full and dealt-away cards
    /// render shadowed.
    private let remainingIds: Set<Int>?
    /// SUBSET-DEAL boundary (v6.78): the ids actually IN the live deal. A
    /// card outside it (a subset deal's benched cards) is never shadowed —
    /// the page shows the full deck un-greyed, matching the histogram; only
    /// a card dealt AWAY within the deal shadows out.
    private let dealIds: Set<Int>?
    private let remainingRanks: [Int: Int]?
    private let scroll = UIScrollView()
    private let content = UIView()
    private let crt = CRTOverlayUIView()
    private let closeButton = PixelButtonView("✕", role: .plain, fontSize: 16)
    /// THE STORE-STYLE INSPECT POPUP (v6.81): tapping (or holding) any card
    /// or equipped item opens the same centered detail panel the store uses
    /// — art, name, description, a card's sticker rows — minus the buy/sell
    /// buttons. It replaces the old top-banner help strip.
    private var inspectDetail: StoreDetailView?

    public init(campaign: CampaignState,
                remainingIds: Set<Int>? = nil,
                dealIds: Set<Int>? = nil,
                remainingRanks: [Int: Int]? = nil) {
        self.campaign = campaign
        self.remainingIds = remainingIds
        self.dealIds = dealIds
        self.remainingRanks = remainingRanks
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    public override var prefersStatusBarHidden: Bool { true }

    @objc private func backEdgePanned(_ g: UIScreenEdgePanGestureRecognizer) {
        guard g.state == .ended else { return }
        let t = g.translation(in: view), v = g.velocity(in: view)
        guard t.x > 40 || v.x > 320 else { return }
        dismiss(animated: false)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = CRT.feltDeep
        let tissue = TissueView()
        tissue.frame = view.bounds
        tissue.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(tissue)
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)
        scroll.addSubview(content)
        crt.isUserInteractionEnabled = false
        view.addSubview(crt)
        build()
        closeButton.onTap = { [weak self] in self?.dismiss(animated: false) }
        closeButton.frame = CGRect(x: view.bounds.width - 50, y: 54, width: 38, height: 32)  // real y: viewDidLayoutSubviews
        view.addSubview(closeButton)
        // Left-edge swipe closes, same as ✕ (this is a full-screen modal, so
        // there is no system pop gesture to inherit).
        let edge = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(backEdgePanned))
        edge.edges = .left
        view.addGestureRecognizer(edge)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scroll.frame = view.bounds
        crt.frame = view.bounds
        // build() runs at viewDidLoad (insets still 0) with a fixed 56pt title
        // top — on notched phones that's INSIDE the Dynamic Island zone. Lift
        // the whole content via the scroll inset so the title clears it.
        scroll.contentInset = UIEdgeInsets(
            top: max(0, view.safeAreaInsets.top + 8 - 56),
            left: 0,
            bottom: max(view.safeAreaInsets.bottom, 12),
            right: 0)
        // Web .nav-btn: always just BELOW the safe-area inset (insets are 0
        // at viewDidLoad, so the floating ✕ lands here).
        closeButton.frame = CGRect(x: view.bounds.width - 50, y: view.safeAreaInsets.top + 4,
                                   width: 38, height: 32)
        inspectDetail?.frame = view.bounds
    }

    // MARK: - Tap / hold → the store-style inspect popup (v6.81)

    @objc private func cardHeld(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let iv = g.view,
              let c = helpCards[ObjectIdentifier(iv)] else { return }
        presentInspect(StoreDetailView(campaign: campaign, inspectCard: c))
    }

    @objc private func cardTapped(_ g: UITapGestureRecognizer) {
        guard let iv = g.view, let c = helpCards[ObjectIdentifier(iv)] else { return }
        presentInspect(StoreDetailView(campaign: campaign, inspectCard: c))
    }

    /// Equipped items answer the SAME tap/hold idiom as the cards (v6.56).
    @objc private func itemHeld(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let iv = g.view,
              let item = helpItems[ObjectIdentifier(iv)] else { return }
        presentInspect(StoreDetailView(campaign: campaign, inspectKind: item.kind, id: item.id))
    }

    @objc private func itemTapped(_ g: UITapGestureRecognizer) {
        guard let iv = g.view, let item = helpItems[ObjectIdentifier(iv)] else { return }
        presentInspect(StoreDetailView(campaign: campaign, inspectKind: item.kind, id: item.id))
    }

    /// The one presenter: full-bounds (the detail self-scrims), below the
    /// CRT overlay, ✕ and tap-away close — exactly the store's idiom.
    private func presentInspect(_ d: StoreDetailView) {
        inspectDetail?.removeFromSuperview()
        Sound.shared.tap()
        d.onClose = { [weak self] in
            self?.inspectDetail?.removeFromSuperview()
            self?.inspectDetail = nil
        }
        d.frame = view.bounds
        view.insertSubview(d, belowSubview: crt)
        inspectDetail = d
    }

    /// Card lookup for the tap/hold recognizers (views don't carry models).
    private var helpCards: [ObjectIdentifier: CardSpec] = [:]
    /// Equipped-item lookup for the same recognizers (v6.56 → popup v6.81).
    private var helpItems: [ObjectIdentifier: (kind: String, id: String)] = [:]

    private func build() {
        let deck = campaign.getRunDeck().sorted { a, b in
            if a.currentRank != b.currentRank { return a.currentRank > b.currentRank }
            let order: [String: Int] = ["♠": 0, "♥": 1, "♣": 2, "♦": 3]
            return (order[a.suit] ?? 4) < (order[b.suit] ?? 4)
        }
        var y: CGFloat = 56
        let w = view.bounds.width

        let title = CRTKit.label("YOUR DECK · \(deck.count) CARDS", size: 14,
                                 color: CRT.phosphor, display: true, glow: true)
        title.frame = CGRect(x: 16, y: y, width: w - 80, height: 22)
        content.addSubview(title)
        y += 34

        // Rank histogram.
        var counts: [Int: Int] = [:]
        var suits: [String: Int] = [:]
        var jokers = 0
        for c in deck {
            if c.joker { jokers += 1; continue }
            counts[c.currentRank, default: 0] += 1
            suits[c.suit, default: 0] += 1
        }
        let histH: CGFloat = 64
        let barW = (w - 40 - CGFloat(DeckManager.ranks.count - 1) * 3) / CGFloat(DeckManager.ranks.count)
        let maxCount = max(1, counts.values.max() ?? 1)
        for (i, r) in DeckManager.ranks.enumerated() {
            let n = counts[r.value] ?? 0
            let rem = remainingRanks?[r.value] ?? n   // off-deal: remaining == full
            let h = n == 0 ? 2 : max(4, CGFloat(n) / CGFloat(maxCount) * histH)
            let bx = 20 + CGFloat(i) * (barW + 3)
            // Web renderHistogram: the track reads felt-mid; the recessed
            // felt-deep ghost is the FULL-deck count and the cream bar the
            // REMAINING count (inside a live deal; off-deal they coincide).
            let track = UIView(frame: CGRect(x: bx, y: y, width: barW, height: histH))
            track.backgroundColor = CRT.feltMid
            content.addSubview(track)
            let ghost = UIView(frame: CGRect(x: bx, y: y + histH - h, width: barW, height: h))
            ghost.backgroundColor = CRT.feltDeep
            content.addSubview(ghost)
            if rem > 0 {
                let rh = max(4, CGFloat(rem) / CGFloat(maxCount) * histH)
                let bar = UIView(frame: CGRect(x: bx, y: y + histH - rh, width: barW, height: rh))
                bar.backgroundColor = CRT.cardFace
                content.addSubview(bar)
            }
            let tick = CRTKit.label(r.label, size: 14, color: CRT.muted)
            tick.textAlignment = .center
            tick.frame = CGRect(x: bx, y: y + histH + 2, width: barW, height: 14)
            content.addSubview(tick)
        }
        y += histH + 22

        // Suit counts + jokers.
        var line = ["♥", "♦", "♣", "♠"].map { "\($0) \(suits[$0] ?? 0)" }.joined(separator: "   ")
        if jokers > 0 { line += "   ★ \(jokers)" }
        let suitLabel = CRTKit.label(line, size: 16, color: CRT.cardFace)
        suitLabel.textAlignment = .center
        suitLabel.frame = CGRect(x: 16, y: y, width: w - 32, height: 20)
        content.addSubview(suitLabel)
        y += 30

        // The cards — sticker chips ride ON the card face (bottom edge, like
        // the board's badges), one chip per sticker instance. Cards no longer
        // in the draw pile (live deal only) render shadowed. Hold a card for
        // its help: the card name + every sticker's registry description.
        let cw: CGFloat = 50, ch: CGFloat = 74
        let cols = max(1, Int((w - 24) / (cw + 8)))
        let rowW = CGFloat(cols) * (cw + 8) - 8
        let x0 = (w - rowW) / 2
        // 15 → 18 (v6.52) → canonical 22 (v6.72) → baked (v6.81): the chips
        // are why you open this screen. Size + fan come from the one shared
        // rule (StickerChipLayout master comment in PileNode.swift), baked
        // into each card image by CardComposite.
        let pitch = (ch - 7) + 8
        helpCards.removeAll()
        helpItems.removeAll()
        for (i, c) in deck.enumerated() {
            let row = i / cols, col = i % cols
            // ONE renderer (v6.81): face + full chip fan baked into a single
            // image by CardComposite — the deal-board idiom, flattened. The
            // old code hand-placed chip views beside the card faces with
            // negative zPositions, which UIKit sank BENEATH every sibling
            // card face: only the first sticker ever showed (the recurring
            // "one sticker in the corner" bug, root-caused at last). A baked
            // image has no z to get wrong — and the dealt-away shadow now
            // dims the chips with their card instead of leaving them bright.
            let iv = UIImageView(image: CardComposite.image(c))
            iv.contentMode = .scaleAspectFit
            iv.layer.magnificationFilter = .nearest
            iv.frame = CGRect(x: x0 + CGFloat(col) * (cw + 8), y: y + CGFloat(row) * pitch,
                              width: cw + StickerChipLayout.rightOverhang,
                              height: (ch - 7) + StickerChipLayout.topRaise)
            // Dealt-away cards shadow out (only with live-deal context).
            // v6.78: a card outside a SUBSET deal is not "dealt away" — it
            // never shadows; only in-deal cards that left the draw pile do.
            if let ids = remainingIds, !ids.contains(c.id),
               dealIds?.contains(c.id) ?? true { iv.alpha = 0.28 }
            content.addSubview(iv)
            // Tap OR hold for help on every card (v6.52).
            iv.isUserInteractionEnabled = true
            helpCards[ObjectIdentifier(iv)] = c
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(cardHeld(_:)))
            hold.minimumPressDuration = 0.4
            iv.addGestureRecognizer(hold)
            iv.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(cardTapped(_:))))
        }
        let rows = (deck.count + cols - 1) / cols
        y += CGFloat(rows) * pitch + 28

        // EQUIPPED — the loadout, one labelled row per FAMILY (v6.39):
        // PILLARS (banner shapes), BASES (plate shapes), then SAME POWER on
        // its own row below. Each item draws in its own silhouette; an empty
        // slot shows the family shape as a dashed outline.
        let eqTitle = CRTKit.label("EQUIPPED", size: 14, color: CRT.phosphor,
                                   display: true, glow: true)
        eqTitle.frame = CGRect(x: 16, y: y, width: w - 32, height: 20)
        content.addSubview(eqTitle)
        y += 26
        let eqGap: CGFloat = 10
        let eqW = (w - 32 - eqGap * 2) / 3
        func rowCaption(_ text: String) {
            let cap = CRTKit.label(text, size: 14, color: CRT.muted)
            cap.frame = CGRect(x: 16, y: y, width: w - 32, height: 15)
            content.addSubview(cap)
            y += 18
        }
        /// One family-shaped cell: the item's own art (its silhouette IS the
        /// shape) or a dashed outline of the family size when the slot is empty.
        /// A filled cell answers tap OR hold with the item's registry help
        /// (v6.56) — the same idiom the cards above use.
        func shapeCell(kind: String, id: String?, x: CGFloat, artSize: CGSize, rowH: CGFloat) {
            let ax = x + (eqW - artSize.width) / 2
            if let id, let def = (kind == "pillar" ? GameData.shared.pillarTypes.get(id)
                                  : kind == "base" ? GameData.shared.baseTypes.get(id)
                                  : GameData.shared.samePowerTypes.get(id)) {
                let art = UIImageView(image: ItemArt.forSlot(kind: kind, id: id,
                                                             card: nil, deckId: campaign.deckId))
                art.contentMode = .scaleAspectFit
                art.layer.magnificationFilter = .nearest
                art.frame = CGRect(x: ax, y: y, width: artSize.width, height: artSize.height)
                art.isUserInteractionEnabled = true
                _ = def   // identity comes from the registry at popup time
                helpItems[ObjectIdentifier(art)] = (kind: kind, id: id)
                let hold = UILongPressGestureRecognizer(target: self, action: #selector(itemHeld(_:)))
                hold.minimumPressDuration = 0.4
                art.addGestureRecognizer(hold)
                art.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(itemTapped(_:))))
                art.isAccessibilityElement = true
                art.accessibilityTraits = .button
                art.accessibilityIdentifier = "deckItem-\(kind)-\(id)"
                art.accessibilityLabel = def.label
                art.accessibilityHint = "Tap or hold for help"
                content.addSubview(art)
                let name = CRTKit.label(def.label, size: 14, color: CRT.cardFace)
                name.textAlignment = .center
                name.adjustsFontSizeToFitWidth = true
                name.minimumScaleFactor = 0.7
                name.frame = CGRect(x: x + 1, y: y + artSize.height + 2, width: eqW - 2, height: 14)
                content.addSubview(name)
            } else {
                let box = UIView(frame: CGRect(x: ax, y: y, width: artSize.width,
                                               height: artSize.height))
                let dash = CAShapeLayer()
                dash.strokeColor = CRT.cardFace.withAlphaComponent(0.3).cgColor
                dash.fillColor = nil
                dash.lineWidth = 2
                dash.lineDashPattern = [4, 3]
                dash.path = UIBezierPath(rect: box.bounds.insetBy(dx: 1, dy: 1)).cgPath
                box.layer.addSublayer(dash)
                content.addSubview(box)
                let e = CRTKit.label("empty", size: 14, color: CRT.disabledText)
                e.textAlignment = .center
                e.frame = CGRect(x: x, y: y + artSize.height + 2, width: eqW, height: 14)
                content.addSubview(e)
            }
            _ = rowH
        }
        rowCaption("PILLARS")
        // Icon scale (v6.56): the old 42×52/64×34/44×44 read as smudges.
        // These match how items read elsewhere — the shelf's per-kind caps
        // (pillar 100 tall, base 46, Same-Power 84) and the result well's
        // 64pt item tile — sized to the ~112pt cell so the silhouette and
        // glyph are legible at a glance without crowding the name line.
        for c in 0..<3 {
            shapeCell(kind: "pillar", id: campaign.columnPillar(c),
                      x: 16 + CGFloat(c) * (eqW + eqGap),
                      artSize: CGSize(width: 56, height: 70), rowH: 88)
        }
        y += 70 + 18 + 8
        rowCaption("BASES")
        for c in 0..<3 {
            shapeCell(kind: "base", id: campaign.columnBase(c),
                      x: 16 + CGFloat(c) * (eqW + eqGap),
                      artSize: CGSize(width: 88, height: 46), rowH: 64)
        }
        y += 46 + 18 + 8
        rowCaption("SAME POWER")
        shapeCell(kind: "samepower", id: campaign.getSamePower(), x: 16,
                  artSize: CGSize(width: 60, height: 60), rowH: 78)
        y += 60 + 18 + 32

        content.frame = CGRect(x: 0, y: 0, width: w, height: y)
        scroll.contentSize = CGSize(width: w, height: y)
    }
}
