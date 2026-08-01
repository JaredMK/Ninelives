import UIKit
import GameCore

/// The pack reveal — the web's #packReveal: the pack's items dealt out with a
/// staggered pop, pick `keep` of them (or Skip — the pack is already paid for),
/// tap an item for its info in the help slot.
///
/// Modes:
///   .pick   — store pack: choose `keep`, the rest are lost
///   .show   — map pack: cards are ALREADY granted; Continue-only
public final class PackRevealViewController: UIViewController {

    public enum Content {
        case cards([CardSpec])
        case stickers([String])
    }
    public enum Mode { case pick(keep: Int), show }

    private let campaign: CampaignState
    private let content: Content
    private let mode: Mode
    private let titleText: String
    /// Picked indices (empty on skip; all indices in .show mode).
    private let completion: ([Int]) -> Void

    private let titleLabel = UILabel()
    private let msgLabel = UILabel()
    private let itemsRow = UIView()
    private let infoPanel = PixelPanelView(face: CRT.feltMid, border: CRT.ink)
    private let infoLabel = UILabel()
    private let confirmButton = PixelButtonView("TAKE", role: .cta, fontSize: 17)
    private let skipButton = PixelButtonView("SKIP", role: .plain, fontSize: 15)
    private let crt = CRTOverlayUIView()
    private var itemButtons: [UIButton] = []
    private var chosen: [Int] = []

    public init(campaign: CampaignState, title: String, content: Content, mode: Mode,
                completion: @escaping ([Int]) -> Void) {
        self.campaign = campaign
        self.titleText = title
        self.content = content
        self.mode = mode
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    public override var prefersStatusBarHidden: Bool { true }

    private var count: Int {
        switch content {
        case .cards(let c): return c.count
        case .stickers(let s): return s.count
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = CRT.feltDeep

        titleLabel.attributedText = CRTKit.attributed(titleText.uppercased(), size: 15,
                                                      color: CRT.phosphor, display: true, glow: true)
        titleLabel.textAlignment = .center
        view.addSubview(titleLabel)

        msgLabel.textAlignment = .center
        msgLabel.numberOfLines = 2
        view.addSubview(msgLabel)
        view.addSubview(itemsRow)

        infoPanel.isHidden = true
        infoLabel.numberOfLines = 0
        infoPanel.addSubview(infoLabel)
        view.addSubview(infoPanel)

        confirmButton.onTap = { [weak self] in self?.confirmTapped() }
        view.addSubview(confirmButton)
        skipButton.onTap = { [weak self] in self?.skipTapped() }
        view.addSubview(skipButton)

        crt.isUserInteractionEnabled = false
        view.addSubview(crt)

        Sound.shared.pack()
        buildItems()
        refreshChrome()
    }

    private func buildItems() {
        for i in 0..<count {
            let b = UIButton(type: .custom)
            switch content {
            case .cards(let cards):
                b.setImage(CardArt.image(CardArt.Face(cards[i]), scale: .three), for: .normal)
            case .stickers(let ids):
                if let def = GameData.shared.stickerTypes.get(ids[i]) {
                    b.setImage(ItemArt.sticker(def, size: 68), for: .normal)
                }
            }
            b.imageView?.layer.magnificationFilter = .nearest
            b.adjustsImageWhenHighlighted = false
            b.tag = i
            b.addTarget(self, action: #selector(itemTapped(_:)), for: .touchUpInside)
            itemsRow.addSubview(b)
            itemButtons.append(b)
            // The staggered deal-in pop (packDealIn: rise + overshoot).
            b.alpha = 0
            b.transform = CGAffineTransform(translationX: 0, y: 14).scaledBy(x: 0.86, y: 0.86)
            UIView.animate(withDuration: 0.36, delay: 0.055 * Double(i),
                           usingSpringWithDamping: 0.7, initialSpringVelocity: 0.4) {
                b.alpha = 1
                b.transform = .identity
            }
        }
        if case .show = mode {
            chosen = Array(0..<count)
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        titleLabel.frame = CGRect(x: 16, y: view.safeAreaInsets.top + 16, width: b.width - 32, height: 24)
        msgLabel.frame = CGRect(x: 16, y: titleLabel.frame.maxY + 6, width: b.width - 32, height: 40)
        // Items: wrap in rows of up to 4.
        let iw: CGFloat = count >= 5 ? 64 : 76, ih: CGFloat = count >= 5 ? 90 : 106
        let perRow = min(count, max(1, Int((b.width - 24) / (iw + 10))))
        let rows = (count + perRow - 1) / perRow
        let y0 = msgLabel.frame.maxY + 18
        for (i, btn) in itemButtons.enumerated() {
            let r = i / perRow, c = i % perRow
            let rowCount = min(perRow, count - r * perRow)
            let rowW = CGFloat(rowCount) * (iw + 10) - 10
            btn.frame = CGRect(x: (b.width - rowW) / 2 + CGFloat(c) * (iw + 10),
                               y: y0 + CGFloat(r) * (ih + 12), width: iw, height: ih)
        }
        itemsRow.frame = CGRect(x: 0, y: 0, width: b.width, height: y0 + CGFloat(rows) * (ih + 12))
        infoPanel.frame = CGRect(x: 16, y: itemsRow.frame.maxY + 8, width: b.width - 32, height: 108)
        infoLabel.frame = infoPanel.bounds.insetBy(dx: 10, dy: 8)
        let by = b.height - view.safeAreaInsets.bottom - 64
        confirmButton.frame = CGRect(x: (b.width - 190) / 2, y: by, width: 190, height: 48)
        skipButton.frame = CGRect(x: b.width - 96, y: by + 6, width: 80, height: 36)
        crt.frame = b
    }

    private func refreshChrome() {
        switch mode {
        case .show:
            msgLabel.attributedText = CRTKit.attributed("These cards join your deck.", size: 15, color: CRT.cardFace)
            confirmButton.setTitle("CONTINUE")
            confirmButton.isEnabled = true
            skipButton.isHidden = true
        case .pick(let keep):
            let left = keep - chosen.count
            msgLabel.attributedText = CRTKit.attributed(
                left > 0 ? "Pick \(keep == 1 ? "one" : "\(keep)") to keep — \(left) more to choose."
                         : "Ready.", size: 15, color: CRT.cardFace)
            confirmButton.setTitle(keep == 1 ? "TAKE" : "TAKE \(chosen.count)/\(keep)")
            confirmButton.isEnabled = chosen.count == keep
            skipButton.isHidden = false
        }
        for (i, b) in itemButtons.enumerated() {
            b.layer.borderWidth = chosen.contains(i) ? 3 : 0
            b.layer.borderColor = CRT.phosphor.cgColor
        }
    }

    @objc private func itemTapped(_ b: UIButton) {
        let i = b.tag
        showInfo(i)
        guard case .pick(let keep) = mode else { return }
        if let at = chosen.firstIndex(of: i) {
            chosen.remove(at: at)
        } else {
            if keep == 1 { chosen = [i] }
            else if chosen.count < keep { chosen.append(i) }
        }
        refreshChrome()
    }

    private func showInfo(_ i: Int) {
        var title = "", body = ""
        switch content {
        case .cards(let cards):
            let c = cards[i]
            if c.joker {
                title = "★ Joker"
                body = "A wild card. Any guess it's part of is SAFE — it can never be wrong. Calling Same with a Joker banks the Same Charge AND fires your Same-Power."
            } else if c.blank {
                title = "∅ Removal"
                body = "A removal tool. Swap it in over a card of your choice and that card is removed — the deck permanently shrinks by one."
            } else {
                let r = DeckManager.ranks.first { $0.value == c.currentRank }?.label ?? "?"
                title = "\(r) \(c.suit)"
                body = c.stickers.isEmpty ? "A plain card, no stickers."
                    : c.stickers.compactMap { s in
                        GameData.shared.stickerTypes.get(s.type).map { "\($0.label) — \($0.description)" }
                    }.joined(separator: "\n")
            }
        case .stickers(let ids):
            if let t = GameData.shared.stickerTypes.get(ids[i]) {
                title = t.label
                body = t.description
            }
        }
        infoPanel.isHidden = false
        infoLabel.attributedText = CRTKit.attributed("\(title)\n\(body)", size: 13, color: CRT.cardFace)
    }

    private func confirmTapped() {
        guard confirmButton.isEnabled else { return }
        dismiss(animated: false)
        completion(chosen)
    }

    private func skipTapped() {
        dismiss(animated: false)
        completion([])
    }
}
