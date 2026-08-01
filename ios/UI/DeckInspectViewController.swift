import UIKit
import GameCore

/// The deck inspection modal — the full campaign deck laid out card by card,
/// with the rank histogram and per-suit counts above it. Read-only; opened
/// from the deck chip on the map/store and the deck stack in a deal.
public final class DeckInspectViewController: UIViewController {

    private let campaign: CampaignState
    private let scroll = UIScrollView()
    private let content = UIView()
    private let crt = CRTOverlayUIView()

    public init(campaign: CampaignState) {
        self.campaign = campaign
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
        let tapClose = PixelButtonView("✕", role: .plain, fontSize: 16)
        tapClose.onTap = { [weak self] in self?.dismiss(animated: false) }
        tapClose.frame = CGRect(x: view.bounds.width - 50, y: 54, width: 38, height: 32)
        tapClose.autoresizingMask = [.flexibleLeftMargin]
        view.addSubview(tapClose)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scroll.frame = view.bounds
        crt.frame = view.bounds
    }

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
            let h = n == 0 ? 2 : max(4, CGFloat(n) / CGFloat(maxCount) * histH)
            let bar = UIView(frame: CGRect(x: 20 + CGFloat(i) * (barW + 3), y: y + histH - h,
                                           width: barW, height: h))
            bar.backgroundColor = n == 0 ? CRT.feltMid : CRT.cardFace
            content.addSubview(bar)
            let tick = CRTKit.label(r.label, size: 12, color: CRT.muted)
            tick.textAlignment = .center
            tick.frame = CGRect(x: 20 + CGFloat(i) * (barW + 3), y: y + histH + 2, width: barW, height: 14)
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

        // The cards.
        let cw: CGFloat = 50, ch: CGFloat = 74
        let cols = max(1, Int((w - 24) / (cw + 8)))
        let rowW = CGFloat(cols) * (cw + 8) - 8
        let x0 = (w - rowW) / 2
        for (i, c) in deck.enumerated() {
            let row = i / cols, col = i % cols
            let iv = UIImageView(image: CardArt.image(CardArt.Face(c), scale: .half))
            iv.contentMode = .scaleAspectFit
            iv.layer.magnificationFilter = .nearest
            iv.frame = CGRect(x: x0 + CGFloat(col) * (cw + 8), y: y + CGFloat(row) * (ch + 8),
                              width: cw, height: ch - 7)
            content.addSubview(iv)
            if !c.stickers.isEmpty {
                let pip = CRTKit.label(String(repeating: "▪", count: min(4, c.stickers.count)),
                                       size: 11, color: CRT.gold)
                pip.textAlignment = .center
                pip.frame = CGRect(x: iv.frame.minX, y: iv.frame.maxY - 2, width: cw, height: 10)
                content.addSubview(pip)
            }
        }
        let rows = (deck.count + cols - 1) / cols
        y += CGFloat(rows) * (ch + 8) + 40
        content.frame = CGRect(x: 0, y: 0, width: w, height: y)
        scroll.contentSize = CGSize(width: w, height: y)
    }
}
