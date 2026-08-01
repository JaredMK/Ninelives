import UIKit
import GameCore

/// The web's persistent top shell, shown over the map and the store: the slim
/// HUD line (menu · four-suit phase tracker · the Same mark · score chip ·
/// coins) above the deck/histogram band (suit-count chart + rank histogram).
public final class TopShellView: UIView {
    public var onMenu: (() -> Void)?
    public var onDeckTap: (() -> Void)?
    /// Store variant: the deck-stack chip (character + count plaque) rides the
    /// band's right edge, compressing the histogram.
    public var showsDeckStack = false

    public static let hudH: CGFloat = 40
    public static let bandH: CGFloat = 72

    private let hudBar = PixelPanelView(face: CRT.feltMid, border: CRT.ink, shadowOffsetPx: 0)
    private let band = PixelPanelView(face: CRT.feltMid, border: CRT.ink, shadowOffsetPx: 0)
    private let menuButton = PixelButtonView("≡", role: .plain, fontSize: 16)
    private let trackView = UIImageView()
    private let sameView = UIImageView()
    private let scoreLabel = UILabel()
    private let coinLabel = UILabel()
    private let bandArt = UIImageView()
    private weak var lastCampaign: CampaignState?
    private var lastBakeWidth: CGFloat = 0

    public override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(hudBar)
        addSubview(band)
        menuButton.onTap = { [weak self] in self?.onMenu?() }
        hudBar.addSubview(menuButton)
        trackView.contentMode = .center
        hudBar.addSubview(trackView)
        // The Same mark: the equals-synapse logo, dim on the shell (the charge
        // is a per-deal resource — the web shows the empty state here).
        sameView.image = MapArt.menuLogo(width: 24)
        sameView.contentMode = .scaleAspectFit
        sameView.alpha = 0.4
        hudBar.addSubview(sameView)
        scoreLabel.numberOfLines = 1
        // The one phosphor element in the stat bar gets THE glow.
        scoreLabel.layer.shadowColor = CRT.phosphor.cgColor
        scoreLabel.layer.shadowRadius = 6
        scoreLabel.layer.shadowOpacity = 0.55
        scoreLabel.layer.shadowOffset = .zero
        hudBar.addSubview(scoreLabel)
        coinLabel.numberOfLines = 1
        coinLabel.textAlignment = .right
        hudBar.addSubview(coinLabel)
        bandArt.contentMode = .topLeft
        bandArt.layer.magnificationFilter = .nearest
        band.addSubview(bandArt)
        band.isUserInteractionEnabled = true
        band.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(bandTapped)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    @objc private func bandTapped() { onDeckTap?() }

    /// Total height below the given safe-area top.
    public static func height(safeTop: CGFloat) -> CGFloat {
        safeTop + 2 + hudH + 6 + bandH + 4
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        let top = safeAreaInsets.top + 2
        hudBar.frame = CGRect(x: 8, y: top, width: w - 16, height: TopShellView.hudH)
        band.frame = CGRect(x: 8, y: top + TopShellView.hudH + 6, width: w - 16, height: TopShellView.bandH)
        let hw = hudBar.bounds.width
        menuButton.frame = CGRect(x: 4, y: 5, width: 34, height: 30)
        trackView.frame = CGRect(x: 44, y: 0, width: 110, height: TopShellView.hudH)
        sameView.frame = CGRect(x: hw / 2 - 26, y: 8, width: 24, height: 24)
        scoreLabel.frame = CGRect(x: hw / 2 + 6, y: 8, width: hw / 2 - 100, height: 24)
        coinLabel.frame = CGRect(x: hw - 96, y: 8, width: 86, height: 24)
        bandArt.frame = band.bounds
        if abs(bounds.width - 16 - lastBakeWidth) > 1 { bakeBand() }
    }

    public func sync(campaign: CampaignState) {
        trackView.image = TopShellView.trackerImage(campaign: campaign)
        let banked = campaign.runWonBanked
        let lab = banked ? "ENDLESS " : "SCORE "
        let val = banked ? campaign.getRunScore() : campaign.getCampaignScore()
        let score = NSMutableAttributedString(
            string: lab, attributes: [.font: CRT.Font.of(12), .foregroundColor: CRT.muted])
        score.append(NSAttributedString(
            string: "\(val)", attributes: [.font: CRT.Font.of(19), .foregroundColor: CRT.phosphor]))
        scoreLabel.attributedText = score
        let coins = NSMutableAttributedString()
        if let coin = ArtBundle.image("pxi-coin") {
            let att = NSTextAttachment()
            att.image = coin
            att.bounds = CGRect(x: 0, y: -2, width: 15, height: 15)
            coins.append(NSAttributedString(attachment: att))
            coins.append(NSAttributedString(string: " "))
        }
        coins.append(NSAttributedString(
            string: "\(campaign.coins)", attributes: [.font: CRT.Font.of(19), .foregroundColor: CRT.gold]))
        coinLabel.attributedText = coins
        lastCampaign = campaign
        bakeBand()
    }

    /// The band bakes at the current width — a sync before first layout (or a
    /// rotation) re-bakes here.
    private func bakeBand() {
        guard let campaign = lastCampaign else { return }
        let w = bounds.width - 16
        guard w > 40 else { return }
        lastBakeWidth = w
        bandArt.image = TopShellView.bandImage(campaign: campaign, width: w,
                                               deckStack: showsDeckStack)
    }

    // MARK: - Baked pieces

    /// The four-suit phase tracker (♥ pre-held, ♦♣♠ by phase) — alt decks get
    /// the numbered stage squares instead.
    static func trackerImage(campaign: CampaignState) -> UIImage {
        let pi = campaign.phaseIndex
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = UIScreen.main.scale
        if campaign.rules().altSuits {
            let total = campaign.phasesTotal()
            let step: CGFloat = 29
            let w = CGFloat(total) * step
            return UIGraphicsImageRenderer(size: CGSize(width: w, height: 30), format: fmt).image { ctx in
                let cg = ctx.cgContext
                for p in 0..<total {
                    let done = pi > p, active = pi == p
                    let alpha: CGFloat = done || active ? 1 : 0.26
                    var rect = CGRect(x: CGFloat(p) * step + 2, y: 4, width: 22, height: 22)
                    if active { rect = rect.insetBy(dx: -1.5, dy: -1.5) }
                    cg.setStrokeColor(CRT.cardFace.withAlphaComponent(alpha).cgColor)
                    cg.setLineWidth(2)
                    cg.stroke(rect)
                    let s = "\(p + 1)" as NSString
                    let font = CRT.Font.of(14)
                    let size = s.size(withAttributes: [.font: font])
                    s.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2),
                           withAttributes: [.font: font,
                                            .foregroundColor: CRT.cardFace.withAlphaComponent(alpha)])
                }
            }
        }
        let order = ["♥", "♦", "♣", "♠"]
        let phaseOf: [String: Int] = ["♥": -1, "♦": 0, "♣": 1, "♠": 2]
        return UIGraphicsImageRenderer(size: CGSize(width: 108, height: 30), format: fmt).image { _ in
            var x: CGFloat = 0
            for s in order {
                let ph = phaseOf[s] ?? 0
                let done = ph < 0 || pi > ph, active = pi == ph
                let alpha: CGFloat = done || active ? 1 : 0.26
                let color = (s == "♥" || s == "♦") ? CRT.suitRed : CRT.cardFace
                let font = CRT.Font.of(active ? 25 : 20)
                let str = s as NSString
                let size = str.size(withAttributes: [.font: font])
                str.draw(at: CGPoint(x: x, y: 15 - size.height / 2),
                         withAttributes: [.font: font,
                                          .foregroundColor: color.withAlphaComponent(alpha)])
                x += size.width + 6
            }
        }
    }

    /// The deck band: suit-count chart (2-col grid + the gold ★ row) beside the
    /// rank histogram — per-rank pip stacks on a shared axis, labels beneath,
    /// the gold Joker column seated past the Ace.
    static func bandImage(campaign: CampaignState, width: CGFloat, deckStack: Bool = false) -> UIImage {
        let deck = campaign.getRunDeck()
        var rank: [Int: Int] = [:]
        var suits: [String: Int] = [:]
        var jokers = 0
        for c in deck {
            if c.joker { jokers += 1 } else {
                rank[c.currentRank, default: 0] += 1
                suits[c.suit, default: 0] += 1
            }
        }
        let H = TopShellView.bandH
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = UIScreen.main.scale
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: H), format: fmt).image { ctx in
            let cg = ctx.cgContext
            // Suit-count chart, top-left: ♥ ♦ / ♣ ♠ / ★ as "n/t".
            let cells: [(String, UIColor)] = [("♥", CRT.suitRed), ("♦", CRT.suitRed),
                                              ("♣", CRT.cardFace), ("♠", CRT.cardFace),
                                              ("★", CRT.gold)]
            for (i, cell) in cells.enumerated() {
                let col = i % 2, row = i / 2
                let x = 10 + CGFloat(col) * 62
                let y = 8 + CGFloat(row) * 19
                let n = cell.0 == "★" ? jokers : (suits[cell.0] ?? 0)
                let glyph = NSAttributedString(string: cell.0,
                                               attributes: [.font: CRT.Font.of(14), .foregroundColor: cell.1])
                glyph.draw(at: CGPoint(x: x, y: y))
                let num = NSMutableAttributedString(
                    string: "\(n)", attributes: [.font: CRT.Font.of(13), .foregroundColor: CRT.cardFace])
                num.append(NSAttributedString(
                    string: "/\(n)", attributes: [.font: CRT.Font.of(13), .foregroundColor: CRT.muted]))
                num.draw(at: CGPoint(x: x + 16, y: y + 1))
            }
            // Store variant: the deck-stack chip at the right edge — the deck
            // character over the gold-framed count plaque (tap = inspect).
            var right: CGFloat = 10
            if deckStack {
                right = 66
                let char = DeckCharacter.image(deckId: campaign.deckId, mood: .idle,
                                               scale: 2, tier: campaign.difficultyTier)
                let cx = width - 10 - 50 + (50 - char.size.width) / 2
                char.draw(in: CGRect(x: cx, y: 3, width: 44, height: 44))
                let plaque = CGRect(x: width - 10 - 44, y: H - 24, width: 40, height: 18)
                cg.setFillColor(CRT.cardFace.cgColor)
                cg.fill(plaque)
                cg.setStrokeColor(CRT.gold.cgColor)
                cg.setLineWidth(2)
                cg.stroke(plaque.insetBy(dx: 1, dy: 1))
                let count = NSAttributedString(
                    string: "\(campaign.deckSize())",
                    attributes: [.font: CRT.Font.of(14), .foregroundColor: CRT.ink])
                let cs = count.size()
                count.draw(at: CGPoint(x: plaque.midX - cs.width / 2, y: plaque.midY - cs.height / 2))
            }

            // Rank histogram: 2..A then the gold ★ column. All pips are filled
            // on the shell (the full deck is in hand between deals).
            let left: CGFloat = 138
            let cols: [(String, Int, UIColor)] = (2...14).map { v in
                let label = v == 11 ? "J" : v == 12 ? "Q" : v == 13 ? "K" : v == 14 ? "A" : "\(v)"
                return (label, rank[v] ?? 0, CRT.cardFace)
            } + [("★", jokers, CRT.gold)]
            let axisMax = max(1, cols.map(\.1).max() ?? 1)
            let colW = (width - left - right) / CGFloat(cols.count)
            let baseY: CGFloat = H - 26
            let avail: CGFloat = baseY - 8
            let slot = min(9, avail / CGFloat(axisMax))
            let pipH = max(2, slot * 0.72)
            for (i, col) in cols.enumerated() {
                let x = left + CGFloat(i) * colW
                cg.setFillColor(col.2.cgColor)
                for k in 0..<col.1 {
                    let y = baseY - CGFloat(k + 1) * slot + (slot - pipH)
                    cg.fill(CGRect(x: x + 1.5, y: y, width: colW - 4, height: pipH))
                }
                let lab = NSAttributedString(
                    string: col.0,
                    attributes: [.font: CRT.Font.of(11),
                                 .foregroundColor: col.0 == "★" ? CRT.gold : CRT.muted])
                let size = lab.size()
                lab.draw(at: CGPoint(x: x + (colW - size.width) / 2, y: baseY + 4))
            }
        }
    }
}
