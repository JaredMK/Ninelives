import UIKit
import GameCore

/// The store's focused detail popup — buy view for an offered slot (with the
/// place-then-confirm chooser + old-vs-new comparison for pillars, bases and
/// Same-Powers) or the read-only equipped view (with Sell).
final class StoreDetailView: UIView {

    private let campaign: CampaignState
    private let panel = PixelPanelView(face: CRT.feltMid, border: CRT.ink)
    private let objView = UIImageView()
    private let tierLabel = UILabel()
    private let nameLabel = UILabel()
    private let descLabel = UILabel()
    private let placeHeader = UILabel()
    private var colButtons: [PixelButtonView] = []
    private let compareLabel = UILabel()
    private let questionLabel = UILabel()
    private let buyButton = PixelButtonView("BUY", role: .cta, fontSize: 16)
    private let sellButton = PixelButtonView("SELL", role: .danger, fontSize: 15)
    private let closeButton = PixelButtonView("✕", role: .plain, fontSize: 15)

    var onClose: (() -> Void)?
    /// Buy confirmed; the chosen column (nil for kinds without placement).
    var onBuy: ((Int?) -> Void)?
    var onSell: (() -> Void)?

    private var kind: String
    private var itemId: String
    private var price = 0
    private var placeCol: Int?
    private let isEquippedView: Bool
    private let card: CardSpec?

    /// Offer detail.
    init(campaign: CampaignState, slot: Int, storeSlot s: StoreSlot) {
        self.campaign = campaign
        self.kind = s.kind
        self.itemId = s.id
        self.card = s.card
        self.isEquippedView = false
        super.init(frame: .zero)
        price = Int(campaign.priceOfMixed(slot))
        if kind == "samepower" { placeCol = 0 }
        common()
        refresh()
    }

    /// Equipped (read-only + Sell) detail.
    init(campaign: CampaignState, equippedKind: String, id: String, col: Int?) {
        self.campaign = campaign
        self.kind = equippedKind
        self.itemId = id
        self.card = nil
        self.isEquippedView = true
        super.init(frame: .zero)
        common()
        refresh()
        sellButton.isHidden = false
        buyButton.isHidden = true
        placeHeader.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    private func common() {
        backgroundColor = CRT.ink.withAlphaComponent(0.5)
        let outside = UITapGestureRecognizer(target: self, action: #selector(outsideTapped(_:)))
        addGestureRecognizer(outside)
        addSubview(panel)
        objView.contentMode = .scaleAspectFit
        objView.layer.magnificationFilter = .nearest
        panel.addSubview(objView)
        for l in [tierLabel, nameLabel, descLabel, placeHeader, compareLabel, questionLabel] {
            l.numberOfLines = 0
            panel.addSubview(l)
        }
        buyButton.onTap = { [weak self] in
            guard let self else { return }
            self.onBuy?(self.placeCol)
        }
        panel.addSubview(buyButton)
        sellButton.isHidden = true
        sellButton.onTap = { [weak self] in self?.onSell?() }
        panel.addSubview(sellButton)
        closeButton.onTap = { [weak self] in self?.onClose?() }
        panel.addSubview(closeButton)
    }

    @objc private func outsideTapped(_ g: UITapGestureRecognizer) {
        if !panel.frame.contains(g.location(in: self)) { onClose?() }
    }

    private func def() -> ItemDef? {
        let data = GameData.shared
        switch kind {
        case "pillar": return data.pillarTypes.get(itemId)
        case "base": return data.baseTypes.get(itemId)
        case "pack": return data.packTypes.get(itemId)
        case "samepower": return data.samePowerTypes.get(itemId)
        case "sticker": return data.stickerTypes.get(itemId)
        default: return nil
        }
    }

    private func refresh() {
        let data = GameData.shared
        // Object + identity.
        switch kind {
        case "card":
            objView.image = card.map { CardArt.image(CardArt.Face($0), scale: .three) }
            let name: String
            if let c = card {
                name = c.joker ? "★ Joker"
                    : "\(DeckManager.ranks.first { r in r.value == c.currentRank }?.label ?? "?") \(c.suit)"
            } else {
                name = "Card"
            }
            nameLabel.attributedText = CRTKit.attributed(name, size: 19, color: CRT.cardFace)
            tierLabel.attributedText = nil
            var desc = card?.joker == true
                ? "A Joker — always safe on any guess. Buy it to swap it into your deck, replacing a card of your choice."
                : data.items.store.card.description
            if let stks = card?.stickers, !stks.isEmpty {
                let names = stks.compactMap { data.stickerTypes.get($0.type)?.label }.joined(separator: ", ")
                desc += " Comes with \(names)."
            }
            descLabel.attributedText = CRTKit.attributed(desc, size: 14, color: CRT.muted)
        case "removal":
            objView.image = ItemArt.removal(width: 58, height: 76)
            nameLabel.attributedText = CRTKit.attributed(data.items.store.removal.label, size: 19, color: CRT.cardFace)
            tierLabel.attributedText = nil
            descLabel.attributedText = CRTKit.attributed(data.items.store.removal.description, size: 14, color: CRT.muted)
        default:
            guard let d = def() else { return }
            objView.image = ItemArt.forSlot(kind: kind, id: itemId, card: nil, deckId: campaign.deckId)
            nameLabel.attributedText = CRTKit.attributed(d.label, size: 19, color: CRT.cardFace)
            tierLabel.attributedText = CRTKit.attributed(d.tier.uppercased(), size: 12,
                                                         color: ItemArt.tierColor(d.tier))
            descLabel.attributedText = CRTKit.attributed(d.description, size: 14, color: CRT.muted)
        }

        // Placement chooser.
        colButtons.forEach { $0.removeFromSuperview() }
        colButtons.removeAll()
        let placement = !isEquippedView && (kind == "pillar" || kind == "base" || kind == "samepower")
        placeHeader.isHidden = !placement
        if placement {
            if kind == "samepower" {
                placeHeader.attributedText = CRTKit.attributed("Equip to the Same (=) button", size: 14, color: CRT.cardFace)
                let cur = campaign.getSamePower().flatMap { GameData.shared.samePowerTypes.get($0)?.label }
                let b = PixelButtonView("SAME · \(cur ?? "empty")", role: .charged, fontSize: 13)
                b.onTap = { [weak self] in self?.pick(col: 0) }
                panel.addSubview(b)
                colButtons.append(b)
            } else {
                placeHeader.attributedText = CRTKit.attributed("Choose a column", size: 14, color: CRT.cardFace)
                let occ = kind == "pillar" ? campaign.columnPillars : campaign.columnBases
                let reg = kind == "pillar" ? GameData.shared.pillarTypes : GameData.shared.baseTypes
                for c in 0..<occ.count {
                    let cur = occ[c].flatMap { reg.get($0)?.label }
                    let b = PixelButtonView("C\(c + 1)·\(cur.map { String($0.prefix(6)) } ?? "empty")",
                                            role: placeCol == c ? .charged : .plain, fontSize: 12)
                    b.onTap = { [weak self] in self?.pick(col: c) }
                    panel.addSubview(b)
                    colButtons.append(b)
                }
            }
        }
        refreshCompare()
        refreshBuy()
        setNeedsLayout()
    }

    private func pick(col: Int) {
        placeCol = col
        refresh()
    }

    /// The id the current pick would DISPLACE (occupied slot / equipped Same).
    private func replacingOldId() -> String? {
        if kind == "samepower" {
            let cur = campaign.getSamePower()
            return cur != itemId ? cur : nil
        }
        guard kind == "pillar" || kind == "base", let c = placeCol else { return nil }
        let occ = kind == "pillar" ? campaign.columnPillar(c) : campaign.columnBase(c)
        return occ
    }

    private func refreshCompare() {
        let placement = !isEquippedView && (kind == "pillar" || kind == "base" || kind == "samepower")
        guard placement, kind == "samepower" || placeCol != nil, let nt = def() else {
            compareLabel.attributedText = nil
            questionLabel.attributedText = nil
            return
        }
        let reg = kind == "pillar" ? GameData.shared.pillarTypes
            : kind == "base" ? GameData.shared.baseTypes : GameData.shared.samePowerTypes
        let old = replacingOldId().flatMap { reg.get($0) }
        if let old {
            compareLabel.attributedText = CRTKit.attributed(
                "NOW: \(old.label) — \(old.description)", size: 12, color: CRT.muted)
            questionLabel.attributedText = CRTKit.attributed(
                kind == "samepower"
                    ? "Replace \(old.label) with \(nt.label) as your Same-Power?"
                    : "Replace \(old.label) with \(nt.label) on column \((placeCol ?? 0) + 1)?",
                size: 14, color: CRT.cardFace)
        } else {
            compareLabel.attributedText = CRTKit.attributed("That slot is empty.", size: 12, color: CRT.muted)
            questionLabel.attributedText = CRTKit.attributed(
                kind == "samepower" ? "Equip \(nt.label) as your Same-Power?"
                    : "Place \(nt.label) on column \((placeCol ?? 0) + 1)?",
                size: 14, color: CRT.cardFace)
        }
    }

    private func refreshBuy() {
        guard !isEquippedView else { return }
        let afford = campaign.getCoins() >= price
        let needSlot = (kind == "pillar" || kind == "base") && placeCol == nil
        buyButton.isEnabled = afford && !needSlot
        let label: String
        if !afford { label = "NEED ◉\(price)" }
        else if needSlot { label = "PICK A COLUMN" }
        else if replacingOldId() != nil { label = "BUY & REPLACE · ◉\(price)" }
        else if kind == "samepower" { label = "BUY & EQUIP · ◉\(price)" }
        else if kind == "pillar" || kind == "base" { label = "BUY & PLACE · ◉\(price)" }
        else if kind == "removal" { label = "REMOVE A CARD · ◉\(price)" }
        else if kind == "card" { label = "BUY & SWAP IN · ◉\(price)" }
        else if kind == "sticker" { label = "PLACE STICKER · ◉\(price)" }
        else { label = "BUY · ◉\(price)" }
        buyButton.setTitle(label)
    }

    /// The equipped view's sell price rides its own button.
    func setSellValue(_ v: Int) {
        sellButton.setTitle("SELL FOR ◉\(v)")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w: CGFloat = min(340, bounds.width - 28)
        let x = (bounds.width - w) / 2
        var y: CGFloat = 14
        let objH: CGFloat = 92
        objView.frame = CGRect(x: (w - 110) / 2, y: y, width: 110, height: objH)
        closeButton.frame = CGRect(x: w - 44, y: 8, width: 36, height: 30)
        y += objH + 6
        tierLabel.frame = CGRect(x: 14, y: y, width: w - 28, height: tierLabel.attributedText == nil ? 0 : 14)
        y = tierLabel.frame.maxY + 2
        nameLabel.frame = CGRect(x: 14, y: y, width: w - 28, height: 24)
        y += 26
        let descH = heightOf(descLabel, width: w - 28)
        descLabel.frame = CGRect(x: 14, y: y, width: w - 28, height: descH)
        y += descH + 8
        if !placeHeader.isHidden {
            placeHeader.frame = CGRect(x: 14, y: y, width: w - 28, height: 18)
            y += 22
            let bw = (w - 28 - CGFloat(max(0, colButtons.count - 1)) * 8) / CGFloat(max(1, colButtons.count))
            for (i, b) in colButtons.enumerated() {
                b.frame = CGRect(x: 14 + CGFloat(i) * (bw + 8), y: y, width: bw, height: 40)
            }
            y += 48
            let cmpH = heightOf(compareLabel, width: w - 28)
            compareLabel.frame = CGRect(x: 14, y: y, width: w - 28, height: cmpH)
            y += cmpH + 4
            let qH = heightOf(questionLabel, width: w - 28)
            questionLabel.frame = CGRect(x: 14, y: y, width: w - 28, height: qH)
            y += qH + 8
        }
        if !buyButton.isHidden {
            buyButton.frame = CGRect(x: 14, y: y, width: w - 28, height: 46)
            y += 54
        }
        if !sellButton.isHidden {
            sellButton.frame = CGRect(x: 14, y: y, width: w - 28, height: 42)
            y += 50
        }
        let h = y + 8
        panel.frame = CGRect(x: x, y: max(40, (bounds.height - h) / 2 - 30), width: w, height: h)
    }

    private func heightOf(_ l: UILabel, width: CGFloat) -> CGFloat {
        guard let t = l.attributedText, t.length > 0 else { return 0 }
        return ceil(t.boundingRect(with: CGSize(width: width, height: 600),
                                   options: .usesLineFragmentOrigin, context: nil).height)
    }
}
