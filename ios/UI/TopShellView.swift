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
    /// The Same-Power slot (v6.97): the deal HUD's chip, mirrored here — the
    /// equipped power's mark, or the empty-slot dashed gold box. Tap answers
    /// the Same Shield / Same Power help through the band takeover, the same
    /// idiom the deal's chips use.
    private let samePowerView = UIImageView()
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
        // The Same mark: the equals-synapse logo. It is LIT when a shield is
        // banked and dim when it isn't — `sync` drives it, matching the deal
        // HUD's own mark. It used to be pinned dim here, so a shield banked
        // outside a deal (the Old Joker's Insurance) read as "still empty"
        // until a deal opened and the HUD drew the truth.
        sameView.image = MapArt.menuLogo(width: 24)
        sameView.contentMode = .scaleAspectFit
        sameView.alpha = 0.4
        sameView.isUserInteractionEnabled = true
        sameView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(sameShieldTapped)))
        hudBar.addSubview(sameView)
        samePowerView.contentMode = .scaleAspectFit
        samePowerView.isUserInteractionEnabled = true
        samePowerView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(samePowerTapped)))
        hudBar.addSubview(samePowerView)
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
        // The deck band is a compound view — without an explicit label the UI
        // tests (and VoiceOver) can't find it.
        band.isAccessibilityElement = true
        band.accessibilityLabel = "DECK"
        band.accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    @objc private func bandTapped() { onDeckTap?() }

    /// The Same chips answer TAP (the deal bar's v6.96 idiom): help takes
    /// over the band, so nothing on screen moves.
    @objc private func sameShieldTapped() {
        showHelp(title: "Same Shield",
                 body: "Charges by a correct same call. Auto-saves a pile")
    }

    @objc private func samePowerTapped() {
        if let pid = lastCampaign?.getSamePower(),
           let def = GameData.shared.samePowerTypes.get(pid) {
            showHelp(title: def.label, body: lastCampaign?.itemDescription(def) ?? def.description)
        } else {
            showHelp(title: "Same Power", body: "None equipped")
        }
    }

    /// The v6.96 empty-slot placeholder: a small dashed gold box, the same
    /// idiom the deal HUD and the pillar/base rows use.
    private static let emptyPowerSlot: UIImage = PixelTexture.image(size: CGSize(width: 18, height: 18)) { cg in
        cg.setStrokeColor(CRT.gold.withAlphaComponent(0.35).cgColor)
        cg.setLineWidth(1)
        cg.setLineDash(phase: 0, lengths: [4, 4])
        cg.stroke(CGRect(x: 0.5, y: 0.5, width: 17, height: 17))
    }

    // MARK: - Hold-for-help band takeover

    /// Help TAKES OVER the band, exactly like the deal board's (DealScene
    /// .showHelp): the baked band art hides and a phosphor-bordered panel fills
    /// the same rect, so nothing on screen moves. The map used to answer a hold
    /// with the bottom prompt bar, which read as a different idiom entirely.
    private let bandHelp = PixelPanelView(face: CRT.feltMid, border: CRT.phosphor)
    private let bandHelpTitle = UILabel()
    private let bandHelpBody = UILabel()

    public var isHelpVisible: Bool { !bandHelp.isHidden }

    public func showHelp(title: String, body: String) {
        if bandHelp.superview == nil {
            bandHelp.isUserInteractionEnabled = false
            // Help must WRAP, not clip — a long node or item description was
            // being cut at three lines with no way to see the rest.
            bandHelpTitle.numberOfLines = 2
            bandHelpBody.numberOfLines = 0
            bandHelp.addSubview(bandHelpTitle)
            bandHelp.addSubview(bandHelpBody)
            band.addSubview(bandHelp)
        }
        bandHelpTitle.attributedText = CRTKit.attributed(title, size: 18, color: CRT.phosphor, glow: true)
        bandHelpBody.attributedText = CRTKit.attributed(body, size: 16, color: CRT.cardFace)
        bandArt.isHidden = true
        bandHelp.isHidden = false
        band.bringSubviewToFront(bandHelp)
        setNeedsLayout()
    }

    public func hideHelp() {
        guard !bandHelp.isHidden else { return }
        bandHelp.isHidden = true
        bandArt.isHidden = false
    }

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
        // The score block carries SCORE **and** HI now, so the bar is packed
        // left-to-right instead of hanging the score off the centre: the suit
        // track and the coin chip each give up some slack so the two numbers
        // fit side by side on a 390pt phone.
        trackView.frame = CGRect(x: 44, y: 0, width: 92, height: TopShellView.hudH)
        sameView.frame = CGRect(x: 142, y: 8, width: 24, height: 24)
        samePowerView.frame = CGRect(x: 170, y: 9, width: 22, height: 22)
        coinLabel.frame = CGRect(x: hw - 74, y: 8, width: 64, height: 24)
        scoreLabel.frame = CGRect(x: 198, y: 8, width: max(48, hw - 74 - 8 - 198), height: 24)
        bandArt.frame = band.bounds
        bandHelp.frame = band.bounds
        // The title got bigger, so it needs the height to match — 18pt in an
        // 18pt box clipped its descenders.
        let titleH: CGFloat = 24
        bandHelpTitle.frame = CGRect(x: 10, y: 5, width: band.bounds.width - 20, height: titleH)
        bandHelpBody.frame = CGRect(x: 10, y: 5 + titleH + 2, width: band.bounds.width - 20,
                                    height: max(18, band.bounds.height - titleH - 12))
        if abs(bounds.width - 16 - lastBakeWidth) > 1 { bakeBand() }
    }

    public func sync(campaign: CampaignState) {
        trackView.image = TopShellView.trackerImage(campaign: campaign)
        // The banked Same shield, live everywhere the shell is up.
        sameView.alpha = campaign.getSameCharge() ? 1 : 0.4
        // The Same-Power slot beside it (v6.97): the equipped power's mark,
        // or the empty-slot placeholder when nothing is equipped.
        if let pid = campaign.getSamePower(),
           let def = GameData.shared.samePowerTypes.get(pid) {
            samePowerView.image = ItemArt.samePower(def, width: 22, height: 22)
        } else {
            samePowerView.image = TopShellView.emptyPowerSlot
        }
        // ONE continuous score (v6.47): the chip keeps its ENDLESS label as a
        // phase marker after the bank, but the number never resets or splits.
        let banked = campaign.runWonBanked
        let lab = banked ? "ENDLESS " : "SCORE "
        let val = campaign.getRunScore()
        let score = NSMutableAttributedString(
            string: lab, attributes: [.font: CRT.Font.of(14), .foregroundColor: CRT.muted])
        score.append(NSAttributedString(
            string: "\(val)", attributes: [.font: CRT.Font.of(18), .foregroundColor: CRT.phosphor]))
        // …and the lifetime best beside it, so the record is visible at every
        // point of a climb, not just inside a deal. Gold and un-glowing — the
        // phosphor glow stays reserved for the ONE live value.
        let best = campaign.stats.get()
            .deckTierBest["\(campaign.deckId).\(campaign.difficultyTier)"] ?? 0
        if best > 0 {
            score.append(NSAttributedString(
                string: "  HI ", attributes: [.font: CRT.Font.of(14), .foregroundColor: CRT.muted]))
            score.append(NSAttributedString(
                string: "\(best)", attributes: [.font: CRT.Font.of(14), .foregroundColor: CRT.cardFace]))
        }
        scoreLabel.attributedText = score
        let coins = NSMutableAttributedString()
        coins.append(NSAttributedString(
            string: "◉ ", attributes: [.font: CRT.Font.of(20), .foregroundColor: CRT.gold]))
        coins.append(NSAttributedString(
            string: "\(campaign.coins)", attributes: [.font: CRT.Font.of(20), .foregroundColor: CRT.gold]))
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
        return UIGraphicsImageRenderer(size: CGSize(width: 108, height: 30), format: fmt).image { ctx in
            // The game's OWN pixel suit marks (suit-glyph sweep 2): the old
            // NSString draw fell through to the system font — neither game
            // font carries ♠♥♦♣ — so the tracker wore smooth foreign suits
            // while every substituted label wore the PixelGlyph ones.
            ctx.cgContext.interpolationQuality = .none
            var x: CGFloat = 0
            for s in order {
                let ph = phaseOf[s] ?? 0
                let done = ph < 0 || pi > ph, active = pi == ph
                let alpha: CGFloat = done || active ? 1 : 0.26
                let color = CRT.suitColor(s, onFelt: true)
                guard let rows = PixelGlyph.suits[s] else { continue }
                // Active phase steps UP an integer pixel scale (was 25pt vs
                // 20pt text) — the grid stays square either way.
                let img = PixelGlyph.image(rows, color: color,
                                           scale: active ? 3 : 2, shadow: false)
                img.draw(at: CGPoint(x: x, y: 15 - img.size.height / 2),
                         blendMode: .normal, alpha: alpha)
                x += img.size.width + 6
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
            // All four suit glyphs read CREAM (v6.36): red-on-felt was the
            // hardest text in the bar. Only the ★ keeps its gold.
            let cells: [(String, UIColor)] = [("♥", CRT.cardFace), ("♦", CRT.cardFace),
                                              ("♣", CRT.cardFace), ("♠", CRT.cardFace),
                                              ("★", CRT.gold)]
            // Suit cells draw the game's own pixel marks (suit-glyph sweep 2):
            // the raw NSAttributedString draw bypassed PixelGlyph.substituteSuits,
            // so this chart wore the system font's smooth suits while the deal
            // HUD's identical tallies wore the pixel ones. Centred against the
            // 16pt cap band exactly the way the substitution centres inline
            // marks; self-tinting suits keep their own colour there (v6.96:
            // Colorful Cards' ♦ blue / ♣ green included).
            let cellFont = CRT.Font.of(16)
            for (i, cell) in cells.enumerated() {
                let col = i % 2, row = i / 2
                let x = 10 + CGFloat(col) * 62
                let y = 8 + CGFloat(row) * 19
                let n = cell.0 == "★" ? jokers : (suits[cell.0] ?? 0)
                if let mark = PixelGlyph.suitImage(cell.0, size: 16, color: cell.1) {
                    cg.interpolationQuality = .none
                    let capTop = y + (cellFont.ascender - cellFont.capHeight)
                    mark.draw(at: CGPoint(x: x, y: capTop + (cellFont.capHeight - mark.size.height) / 2))
                } else {
                    let glyph = NSAttributedString(string: cell.0,
                                                   attributes: [.font: cellFont, .foregroundColor: cell.1])
                    glyph.draw(at: CGPoint(x: x, y: y))
                }
                let num = NSMutableAttributedString(
                    string: "\(n)", attributes: [.font: CRT.Font.of(16), .foregroundColor: CRT.cardFace])
                num.append(NSAttributedString(
                    string: "/\(n)", attributes: [.font: CRT.Font.of(16), .foregroundColor: CRT.muted]))
                num.draw(at: CGPoint(x: x + 16, y: y + 1))
            }
            // Store variant: the deck-stack chip at the right edge — the deck
            // character over the gold-framed count plaque (tap = inspect).
            var right: CGFloat = 10
            if deckStack {
                right = 66
                let char = DeckCharacter.image(deckId: campaign.deckId, mood: .idle,
                                               scale: 2, tier: campaign.difficultyTier)
                // Centre the 44pt DRAW RECT in its 50pt slot — this centred the
                // 64px SOURCE image instead, pushing the mascot 7pt left and a
                // pixel past the histogram's reserve.
                let cx = width - 10 - 50 + (50 - 44) / 2
                cg.interpolationQuality = .none   // pixel art is never smoothed
                char.draw(in: CGRect(x: cx, y: 3, width: 44, height: 44))
                let plaque = CGRect(x: width - 10 - 44, y: H - 24, width: 40, height: 18)
                cg.setFillColor(CRT.cardFace.cgColor)
                cg.fill(plaque)
                cg.setStrokeColor(CRT.gold.cgColor)
                cg.setLineWidth(2)
                cg.stroke(plaque.insetBy(dx: 1, dy: 1))
                let count = NSAttributedString(
                    string: "\(campaign.deckSize())",
                    attributes: [.font: CRT.Font.of(16), .foregroundColor: CRT.ink])
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
                    attributes: [.font: CRT.Font.of(14),
                                 .foregroundColor: col.0 == "★" ? CRT.gold : CRT.muted])
                let size = lab.size()
                lab.draw(at: CGPoint(x: x + (colW - size.width) / 2, y: baseY + 4))
            }
        }
    }
}
