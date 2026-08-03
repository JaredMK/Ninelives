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
    private let remainingRanks: [Int: Int]?
    private let scroll = UIScrollView()
    private let content = UIView()
    private let crt = CRTOverlayUIView()
    private let closeButton = PixelButtonView("✕", role: .plain, fontSize: 16)
    /// Hold-for-help: bottom panel naming the card + everything on it.
    private let helpPanel = PixelPanelView()
    private let helpTitle = UILabel()
    private let helpBody = UILabel()

    public init(campaign: CampaignState,
                remainingIds: Set<Int>? = nil,
                remainingRanks: [Int: Int]? = nil) {
        self.campaign = campaign
        self.remainingIds = remainingIds
        self.remainingRanks = remainingRanks
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    public override var prefersStatusBarHidden: Bool { true }

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

        // Hold-for-help panel (hidden until a card is held).
        helpPanel.isHidden = true
        helpTitle.textAlignment = .center
        helpBody.textAlignment = .center
        helpBody.numberOfLines = 0
        helpPanel.addSubview(helpTitle)
        helpPanel.addSubview(helpBody)
        view.addSubview(helpPanel)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scroll.frame = view.bounds
        crt.frame = view.bounds
        // Web .nav-btn: always just BELOW the safe-area inset (insets are 0
        // at viewDidLoad, so the floating ✕ lands here).
        closeButton.frame = CGRect(x: view.bounds.width - 50, y: view.safeAreaInsets.top + 4,
                                   width: 38, height: 32)
        let hp = helpPanel
        if !hp.isHidden {
            let w = min(view.bounds.width - 28, 400)
            let bodyH = helpBody.sizeThatFits(CGSize(width: w - 24, height: 400)).height
            let h = bodyH + 46
            hp.frame = CGRect(x: (view.bounds.width - w) / 2,
                              y: view.bounds.height - max(view.safeAreaInsets.bottom, 12) - 12 - h,
                              width: w, height: h)
            helpTitle.frame = CGRect(x: 12, y: 8, width: w - 24, height: 18)
            helpBody.frame = CGRect(x: 12, y: 30, width: w - 24, height: bodyH)
        }
    }

    // MARK: - Hold-for-help

    @objc private func cardHeld(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            guard let iv = g.view, let c = helpCards[ObjectIdentifier(iv)] else { return }
            let name: String
            if c.joker { name = "★ Joker" }
            else if c.blank { name = "∅ Removal" }
            else {
                name = (DeckManager.ranks.first { $0.value == c.currentRank }?.label
                        ?? "\(c.currentRank)") + c.suit
            }
            helpTitle.attributedText = CRTKit.attributed(name, size: 14,
                                                         color: CRT.phosphor, display: true, glow: true)
            var lines: [String] = []
            for rec in c.stickers {
                if let def = GameData.shared.stickerTypes.get(rec.type) {
                    lines.append("\(def.label) — \(def.description)")
                }
            }
            if lines.isEmpty { lines.append("No stickers on this card.") }
            helpBody.attributedText = CRTKit.attributed(lines.joined(separator: "\n"),
                                                        size: 12, color: CRT.cardFace)
            helpPanel.isHidden = false
            view.setNeedsLayout()
        case .ended, .cancelled, .failed:
            helpPanel.isHidden = true
        default: break
        }
    }

    /// Card lookup for the hold recognizers (views don't carry models).
    private var helpCards: [ObjectIdentifier: CardSpec] = [:]

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
            let tick = CRTKit.label(r.label, size: 12, color: CRT.muted)
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
        let stkSize: CGFloat = 12, stkGap: CGFloat = 1
        let stkPerRow = 3, stkMax = 6
        let pitch = (ch - 7) + 8
        helpCards.removeAll()
        for (i, c) in deck.enumerated() {
            let row = i / cols, col = i % cols
            let iv = UIImageView(image: CardArt.image(CardArt.Face(c), scale: .half))
            iv.contentMode = .scaleAspectFit
            iv.layer.magnificationFilter = .nearest
            iv.frame = CGRect(x: x0 + CGFloat(col) * (cw + 8), y: y + CGFloat(row) * pitch,
                              width: cw, height: ch - 7)
            // Dealt-away cards shadow out (only with live-deal context).
            if let ids = remainingIds, !ids.contains(c.id) { iv.alpha = 0.28 }
            content.addSubview(iv)
            // Hold-for-help on every card.
            iv.isUserInteractionEnabled = true
            helpCards[ObjectIdentifier(iv)] = c
            let hold = UILongPressGestureRecognizer(target: self, action: #selector(cardHeld(_:)))
            hold.minimumPressDuration = 0.4
            iv.addGestureRecognizer(hold)
            // Sticker chips ON the card, stacked up from its bottom edge.
            let stickers = Array(c.stickers.prefix(stkMax))
            for (s, rec) in stickers.enumerated() {
                guard let def = GameData.shared.stickerTypes.get(rec.type) else { continue }
                let sRow = s / stkPerRow, sCol = s % stkPerRow
                let inRow = min(stkPerRow, stickers.count - sRow * stkPerRow)
                let lineW = CGFloat(inRow) * stkSize + CGFloat(inRow - 1) * stkGap
                let chip = UIImageView(image: ItemArt.sticker(def, size: stkSize))
                chip.contentMode = .scaleAspectFit
                chip.layer.magnificationFilter = .nearest
                chip.frame = CGRect(x: iv.frame.minX + (cw - lineW) / 2 + CGFloat(sCol) * (stkSize + stkGap),
                                    y: iv.frame.maxY - 3 - CGFloat(sRow + 1) * (stkSize + stkGap) + stkGap,
                                    width: stkSize, height: stkSize)
                content.addSubview(chip)
            }
        }
        let rows = (deck.count + cols - 1) / cols
        y += CGFloat(rows) * pitch + 40
        content.frame = CGRect(x: 0, y: 0, width: w, height: y)
        scroll.contentSize = CGSize(width: w, height: y)
    }
}
