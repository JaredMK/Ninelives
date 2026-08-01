import UIKit
import GameCore

/// The card picker modal — the web's #stickerApplyModal, all five modes:
///   .applySticker(typeId)      — apply an owned sticker (inventory)
///   .buySticker(slot, typeId)  — store buy: place-then-confirm-THEN-pay
///   .removal(paid:)            — pick a card to permanently remove
///   .strip                     — mystery Cleanse: pick a stickered card
///   .swap(trayIndex)           — swap a held pack card into the deck
///
/// One fixed-shell screen: banner (what you're placing), the deck grid,
/// composition strip, confirm via the shared prompt bar.
public final class CardPickerViewController: UIViewController {

    public enum Mode {
        case applySticker(typeId: String)
        case buySticker(slot: Int, typeId: String)
        case removal(price: Int)
        case strip
        case swap(trayIndex: Int, step: String?)
    }

    private let campaign: CampaignState
    private let mode: Mode
    /// (completedCardId or nil on skip/close)
    private let completion: (Int?) -> Void
    /// Forced flows (mystery strip/removal) hide ✕ — no dismiss without choosing.
    public var forced = false
    /// Show a Skip button (pack-keep walk: decline this card).
    public var showsSkip = false

    private let headerLabel = UILabel()
    private let bannerPanel = PixelPanelView(face: CRT.feltMid, border: CRT.ink)
    private let bannerIcon = UIImageView()
    private let bannerText = UILabel()
    private let hintLabel = UILabel()
    private let scroll = UIScrollView()
    private let grid = UIView()
    private let closeButton = PixelButtonView("✕", role: .plain, fontSize: 16)
    private let skipButton = PixelButtonView("SKIP", role: .plain, fontSize: 14)
    private let prompt = PromptBar()
    private let crt = CRTOverlayUIView()
    private var cardViews: [Int: UIButton] = [:]
    private var selectedId: Int?
    private var busy = false

    public init(campaign: CampaignState, mode: Mode, completion: @escaping (Int?) -> Void) {
        self.campaign = campaign
        self.mode = mode
        self.completion = completion
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

        headerLabel.attributedText = CRTKit.attributed(headerText(), size: 15, color: CRT.phosphor,
                                                       display: true, glow: true)
        view.addSubview(headerLabel)

        view.addSubview(bannerPanel)
        bannerIcon.contentMode = .scaleAspectFit
        bannerIcon.layer.magnificationFilter = .nearest
        bannerPanel.addSubview(bannerIcon)
        bannerText.numberOfLines = 0
        bannerPanel.addSubview(bannerText)
        configureBanner()

        hintLabel.numberOfLines = 0
        hintLabel.attributedText = CRTKit.attributed(hintText(), size: 14, color: CRT.muted)
        view.addSubview(hintLabel)

        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)
        scroll.addSubview(grid)

        closeButton.onTap = { [weak self] in self?.closeTapped() }
        closeButton.isHidden = forced
        view.addSubview(closeButton)
        skipButton.onTap = { [weak self] in self?.skipTapped() }
        skipButton.isHidden = !showsSkip
        view.addSubview(skipButton)

        crt.isUserInteractionEnabled = false
        view.addSubview(crt)
        view.addSubview(prompt)

        renderGrid()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        let top = view.safeAreaInsets.top + 8
        headerLabel.frame = CGRect(x: 16, y: top, width: b.width - 110, height: 22)
        closeButton.frame = CGRect(x: b.width - 48, y: top, width: 38, height: 32)
        skipButton.frame = CGRect(x: b.width - 118, y: top, width: 62, height: 32)
        bannerPanel.frame = CGRect(x: 12, y: top + 30, width: b.width - 24, height: 72)
        bannerIcon.frame = CGRect(x: 10, y: 8, width: 52, height: 56)
        bannerText.frame = CGRect(x: 72, y: 6, width: bannerPanel.frame.width - 84, height: 60)
        hintLabel.frame = CGRect(x: 16, y: bannerPanel.frame.maxY + 6, width: b.width - 32, height: 34)
        scroll.frame = CGRect(x: 0, y: hintLabel.frame.maxY + 4, width: b.width,
                              height: b.height - hintLabel.frame.maxY - 4)
        crt.frame = b
        prompt.frame = b
        layoutGrid()
    }

    private func headerText() -> String {
        switch mode {
        case .applySticker(let t), .buySticker(_, let t):
            return "APPLY \(GameData.shared.stickerTypes.get(t)?.label.uppercased() ?? "STICKER")"
        case .removal: return "REMOVE A CARD"
        case .strip: return "CLEANSE"
        case .swap(_, let step): return "SWAP IN" + (step ?? "")
        }
    }

    private func configureBanner() {
        switch mode {
        case .applySticker(let t), .buySticker(_, let t):
            if let def = GameData.shared.stickerTypes.get(t) {
                bannerIcon.image = ItemArt.sticker(def)
                bannerText.attributedText = CRTKit.attributed(
                    "\(def.label)\n\(def.description)", size: 13, color: CRT.cardFace)
            }
        case .removal(let price):
            bannerIcon.image = ItemArt.removal()
            bannerText.attributedText = CRTKit.attributed(
                price > 0 ? "Pick a card to permanently remove (◉\(price)). Its stickers are destroyed."
                          : "Pick a card to permanently remove. Its stickers are destroyed.",
                size: 13, color: CRT.cardFace)
        case .strip:
            bannerIcon.image = ItemArt.removal()
            bannerText.attributedText = CRTKit.attributed(
                "Pick a stickered card — ONE random sticker is stripped from it, destroyed.",
                size: 13, color: CRT.cardFace)
        case .swap(let trayIndex, _):
            let tray = campaign.getPackTray()
            if trayIndex < tray.count {
                let c = tray[trayIndex]
                bannerIcon.image = CardArt.image(CardArt.Face(c), scale: .half)
                let name = c.joker ? "★ Joker" : (c.blank ? "∅ Removal" : "\(rankLabel(c)) \(c.suit)")
                bannerText.attributedText = CRTKit.attributed(
                    "\(name)\nPick a card to replace with this one — the old card is removed for good.",
                    size: 13, color: CRT.cardFace)
            }
        }
    }

    private func hintText() -> String {
        switch mode {
        case .applySticker, .buySticker: return "Tap an eligible card. Dimmed cards can't take this sticker."
        case .removal: return "Tap the card to remove."
        case .strip: return "Tap a card with at least one sticker."
        case .swap: return showsSkip ? "Tap the card to replace — or Skip to decline this card." : "Tap the card to replace."
        }
    }

    private func rankLabel(_ c: CardSpec) -> String {
        DeckManager.ranks.first { $0.value == c.currentRank }?.label ?? "\(c.currentRank)"
    }

    private func eligible(_ c: CardSpec) -> Bool {
        switch mode {
        case .applySticker(let t), .buySticker(_, let t): return campaign.canApplySticker(c, t)
        case .removal: return true
        case .strip: return !c.stickers.isEmpty
        case .swap: return true
        }
    }

    // MARK: - Grid

    private var deck: [CardSpec] = []

    private func renderGrid() {
        deck = campaign.getRunDeck().sorted { a, b in
            if a.currentRank != b.currentRank { return a.currentRank > b.currentRank }
            let order: [String: Int] = ["♠": 0, "♥": 1, "♣": 2, "♦": 3]
            return (order[a.suit] ?? 4) < (order[b.suit] ?? 4)
        }
        grid.subviews.forEach { $0.removeFromSuperview() }
        cardViews.removeAll()
        for c in deck {
            let b = UIButton(type: .custom)
            b.setImage(CardArt.image(CardArt.Face(c), scale: .half), for: .normal)
            b.imageView?.layer.magnificationFilter = .nearest
            b.adjustsImageWhenHighlighted = false
            b.tag = c.id
            b.addTarget(self, action: #selector(cardTapped(_:)), for: .touchUpInside)
            let ok = eligible(c)
            b.alpha = ok ? 1 : 0.35
            b.isEnabled = ok
            // Sticker count pips under the card.
            if !c.stickers.isEmpty {
                let pip = CRTKit.label(String(repeating: "▪", count: min(4, c.stickers.count)),
                                       size: 12, color: CRT.gold)
                pip.frame = CGRect(x: 0, y: 68, width: 50, height: 12)
                pip.textAlignment = .center
                b.addSubview(pip)
            }
            grid.addSubview(b)
            cardViews[c.id] = b
        }
        layoutGrid()
    }

    private func layoutGrid() {
        guard view.bounds.width > 0 else { return }
        let cw: CGFloat = 50, ch: CGFloat = 82
        let cols = max(1, Int((view.bounds.width - 16) / (cw + 8)))
        let rowW = CGFloat(cols) * (cw + 8) - 8
        let x0 = (view.bounds.width - rowW) / 2
        for (i, c) in deck.enumerated() {
            guard let b = cardViews[c.id] else { continue }
            let row = i / cols, col = i % cols
            b.frame = CGRect(x: x0 + CGFloat(col) * (cw + 8), y: 8 + CGFloat(row) * (ch + 6),
                             width: cw, height: ch)
        }
        let rows = (deck.count + max(1, Int((view.bounds.width - 16) / (cw + 8))) - 1)
            / max(1, Int((view.bounds.width - 16) / (cw + 8)))
        let h = 16 + CGFloat(rows) * (ch + 6)
        grid.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: h)
        scroll.contentSize = CGSize(width: view.bounds.width,
                                    height: h + (view.safeAreaInsets.bottom + 20))
    }

    // MARK: - Selection + confirm

    @objc private func cardTapped(_ b: UIButton) {
        guard !busy else { return }
        let id = b.tag
        guard let card = deck.first(where: { $0.id == id }) else { return }
        selectedId = id
        highlight(id)
        let name = card.joker ? "★ Joker" : "\(rankLabel(card))\(card.suit)"
        let stickerWarn = card.stickers.isEmpty ? "" :
            " \(name) carries \(card.stickers.count) sticker\(card.stickers.count > 1 ? "s" : ""), destroyed forever."
        switch mode {
        case .applySticker(let t), .buySticker(_, let t):
            let label = GameData.shared.stickerTypes.get(t)?.label ?? t
            var text = "Apply \(label) to \(name)?"
            if case .buySticker = mode {
                text = "Buy \(label) for ◉\(Int(campaign.priceOf(t))) and apply to \(name)?"
            }
            prompt.show(text, help: "Stickers are permanent.", actions: [
                .init("Cancel", role: .plain) { [weak self] in self?.cancelChoice() },
                .init("Apply", role: .cta) { [weak self] in self?.confirm() },
            ]) { [weak self] in self?.cancelChoice() }
        case .removal(let price):
            prompt.show("Permanently REMOVE \(name) from your deck?",
                        help: "Your deck shrinks by one card.\(stickerWarn)" + (price > 0 ? " Costs ◉\(price)." : ""),
                        actions: [
                .init("Cancel", role: .plain) { [weak self] in self?.cancelChoice() },
                .init("Remove", role: .danger) { [weak self] in self?.confirm() },
            ]) { [weak self] in self?.cancelChoice() }
        case .strip:
            prompt.show("Strip one random sticker from \(name)?",
                        help: "The sticker is destroyed for good.", actions: [
                .init("Cancel", role: .plain) { [weak self] in self?.cancelChoice() },
                .init("Strip", role: .cta) { [weak self] in self?.confirm() },
            ]) { [weak self] in self?.cancelChoice() }
        case .swap(let trayIndex, _):
            let tray = campaign.getPackTray()
            guard trayIndex < tray.count else { return }
            let tc = tray[trayIndex]
            if tc.blank {
                prompt.show("Permanently REMOVE \(name) from your deck?",
                            help: "Your deck shrinks by one card.\(stickerWarn)", actions: [
                    .init("Cancel", role: .plain) { [weak self] in self?.cancelChoice() },
                    .init("Remove", role: .danger) { [weak self] in self?.confirm() },
                ]) { [weak self] in self?.cancelChoice() }
            } else {
                let packName = tc.joker ? "★ Joker" : "\(rankLabel(tc))\(tc.suit)"
                prompt.show("Permanently swap \(name) for \(packName) in your deck?",
                            help: "A permanent campaign-deck change.\(stickerWarn)", actions: [
                    .init("Cancel", role: .plain) { [weak self] in self?.cancelChoice() },
                    .init("Replace", role: .cta) { [weak self] in self?.confirm() },
                ]) { [weak self] in self?.cancelChoice() }
            }
        }
    }

    private func highlight(_ id: Int?) {
        for (cid, b) in cardViews {
            b.layer.borderWidth = cid == id ? 3 : 0
            b.layer.borderColor = CRT.phosphor.cgColor
        }
    }

    private func cancelChoice() {
        selectedId = nil
        highlight(nil)
        prompt.hide()
    }

    private func confirm() {
        guard let id = selectedId, !busy else { return }
        prompt.hide()
        busy = true
        var ok = false
        switch mode {
        case .applySticker(let t):
            // applySticker consumes the inventory copy itself.
            ok = campaign.applySticker(id, t)
        case .buySticker(let slot, let t):
            // Place-then-confirm-THEN-pay: buyOfferedSticker charges + banks
            // one to inventory; applySticker consumes that one.
            if campaign.buyOfferedSticker(slot) {
                ok = campaign.applySticker(id, t)
            }
        case .removal(let price):
            ok = price > 0 ? campaign.buyRemoval(id) : campaign.removeDeckCard(id)
        case .strip:
            ok = campaign.removeRandomStickerFrom(id) != nil
        case .swap(let trayIndex, _):
            ok = campaign.replaceDeckCard(id, trayIndex: trayIndex) != nil
        }
        guard ok else { busy = false; return }
        switch mode {
        case .applySticker, .buySticker: Sound.shared.sticker()
        default: Sound.shared.purchase()
        }
        PersistenceHolder.shared?.checkpoint(campaign)
        // The chosen card flashes (dissolves for removal/swap), then close.
        let flash = cardViews[id]
        UIView.animate(withDuration: 0.3, animations: {
            switch self.mode {
            case .removal, .swap, .strip:
                flash?.alpha = 0
                flash?.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
            default:
                flash?.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
            }
        }) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.dismiss(animated: false)
                self.completion(id)
            }
        }
    }

    private func closeTapped() {
        guard !busy else { return }
        dismiss(animated: false)
        completion(nil)
    }

    /// Autopilot: select the first eligible card and confirm straight through.
    func autopilotConfirm() {
        guard !busy else { return }
        guard let card = deck.first(where: { eligible($0) }) else {
            dismiss(animated: false)
            completion(nil)
            return
        }
        selectedId = card.id
        prompt.hide()
        confirm()
    }

    private func skipTapped() {
        guard !busy else { return }
        // Pack-keep walk decline: drop the tray card (no refund) and advance.
        if case .swap(let trayIndex, _) = mode { _ = campaign.discardPackCard(trayIndex) }
        dismiss(animated: false)
        completion(nil)
    }
}

/// A hook the flows use to checkpoint after a mutation. Chunk D's campaign
/// shell installs the real persistence; screens call through this so they
/// never need to know whether a save layer exists yet.
public protocol CampaignCheckpointing: AnyObject {
    func checkpoint(_ campaign: CampaignState)
}
public enum PersistenceHolder {
    public static weak var shared: CampaignCheckpointing?
}
