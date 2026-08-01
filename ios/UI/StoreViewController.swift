import UIKit
import GameCore

public protocol StoreScreenDelegate: AnyObject {
    /// GO TO MAP — the visit is over.
    func storeDone(_ store: StoreViewController)
}

/// The store — ONE fixed screen (AGENTS UX): a unified 6-slot shelf (5 rolled
/// + the permanent Removal), the reroll button with its escalating cost, the
/// equipped-loadout reference, and GO TO MAP. Sub-flows (detail, card picker,
/// pack reveal) open above it and return to the same screen.
public final class StoreViewController: UIViewController {

    private let campaign: CampaignState
    public weak var delegate: StoreScreenDelegate?

    private let headerBar = PixelPanelView(face: CRT.feltMid, border: CRT.ink, shadowOffsetPx: 0)
    private let coinsLabel = UILabel()
    private let stageLabel = UILabel()
    private let helpButton = PixelButtonView("?", role: .plain, fontSize: 16)
    private let msgLabel = UILabel()
    private let shelf = UIView()
    private var tiles: [StoreTileView] = []
    private let rerollButton = PixelButtonView("REFRESH", role: .gold, fontSize: 16)
    private let loadoutPanel = PixelPanelView(face: CRT.feltMid, border: CRT.ink)
    private let loadoutTitle = UILabel()
    private var loadoutChips: [UIView] = []
    private let goButton = PixelButtonView("GO TO MAP", role: .cta, fontSize: 18)
    private let prompt = PromptBar()
    private let crt = CRTOverlayUIView()
    private var detail: StoreDetailView?
    private var keyPanel: UIView?
    private var character = UIImageView()

    /// A mystery "store" detour keys the offer to the mystery node.
    public var offerNodeId: Int?

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

        // Fresh visit rolls a new offer; a resume keeps the saved one (a
        // refresh while shopping can never hand out a free reroll). SEED1: the
        // offer keys to the node id.
        if campaign.getStoreOffer() == nil {
            let keyId = offerNodeId ?? campaign.nodePos
            if let keyId {
                _ = campaign.openStore(rng: runRng(seed: campaign.runSeed, [.s("store"), .n(keyId)]))
            } else {
                _ = campaign.openStore()
            }
        }

        view.addSubview(headerBar)
        view.addSubview(coinsLabel)
        stageLabel.textAlignment = .right
        view.addSubview(stageLabel)
        helpButton.onTap = { [weak self] in self?.toggleKey() }
        view.addSubview(helpButton)

        character.contentMode = .scaleAspectFit
        character.layer.magnificationFilter = .nearest
        view.addSubview(character)

        msgLabel.numberOfLines = 2
        view.addSubview(msgLabel)
        view.addSubview(shelf)

        rerollButton.onTap = { [weak self] in self?.rerollTapped() }
        view.addSubview(rerollButton)

        view.addSubview(loadoutPanel)
        loadoutTitle.attributedText = CRTKit.attributed("EQUIPPED", size: 13, color: CRT.muted)
        loadoutPanel.addSubview(loadoutTitle)

        goButton.onTap = { [weak self] in self?.goTapped() }
        view.addSubview(goButton)

        crt.isUserInteractionEnabled = false
        view.addSubview(crt)
        view.addSubview(prompt)

        setMessage("Buy from the offer, refresh, then head for the map.")
        render()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        let top = view.safeAreaInsets.top + 4
        headerBar.frame = CGRect(x: 0, y: 0, width: b.width, height: top + 30)
        coinsLabel.frame = CGRect(x: 14, y: top, width: 160, height: 24)
        stageLabel.frame = CGRect(x: b.width - 174, y: top, width: 160, height: 24)
        helpButton.frame = CGRect(x: b.width - 48, y: headerBar.frame.maxY + 8, width: 38, height: 32)
        character.frame = CGRect(x: 12, y: headerBar.frame.maxY + 6, width: 36, height: 36)
        msgLabel.frame = CGRect(x: 58, y: headerBar.frame.maxY + 8, width: b.width - 116, height: 34)

        // Shelf: 3×2 grid.
        let shelfTop = msgLabel.frame.maxY + 8
        let tw = (b.width - 16 * 2 - 12 * 2) / 3
        let th: CGFloat = 116
        shelf.frame = CGRect(x: 16, y: shelfTop, width: b.width - 32, height: th * 2 + 12)
        for (i, t) in tiles.enumerated() {
            let r = i / 3, c = i % 3
            t.frame = CGRect(x: CGFloat(c) * (tw + 12), y: CGFloat(r) * (th + 12), width: tw, height: th)
        }
        rerollButton.frame = CGRect(x: (b.width - 210) / 2, y: shelf.frame.maxY + 10, width: 210, height: 40)

        let loTop = rerollButton.frame.maxY + 12
        let goH: CGFloat = 52
        let loBottom = b.height - view.safeAreaInsets.bottom - goH - 22
        loadoutPanel.frame = CGRect(x: 12, y: loTop, width: b.width - 24, height: max(90, loBottom - loTop))
        loadoutTitle.frame = CGRect(x: 10, y: 6, width: 200, height: 16)
        layoutLoadout()
        goButton.frame = CGRect(x: (b.width - 230) / 2, y: b.height - view.safeAreaInsets.bottom - goH - 12,
                                width: 230, height: goH)
        crt.frame = b
        prompt.frame = b
        detail?.frame = b
    }

    private func setMessage(_ s: String) {
        msgLabel.attributedText = CRTKit.attributed(s, size: 13, color: CRT.muted)
    }

    // MARK: - Render

    public func render() {
        coinsLabel.attributedText = CRTKit.attributed("◉ \(campaign.getCoins()) to spend", size: 17, color: CRT.gold)
        let pIdx = campaign.phaseIndex
        stageLabel.attributedText = CRTKit.attributed("STG \(min(pIdx + 1, campaign.phasesTotal())) · DECK \(campaign.deckSize())",
                                                      size: 15, color: CRT.muted)
        character.image = DeckCharacter.image(deckId: campaign.deckId, mood: .idle, scale: 2)

        // Shelf tiles.
        tiles.forEach { $0.removeFromSuperview() }
        tiles.removeAll()
        let slots = campaign.getStoreOffer()?.slots ?? []
        for (i, s) in slots.enumerated() {
            let tile = StoreTileView(slot: i)
            if let s {
                let locked = campaign.stickersLocked
                    && (s.kind == "sticker" || (s.kind == "pack" && GameData.shared.packTypes.get(s.id)?.kind == "sticker"))
                let price = Int(campaign.priceOfMixed(i))
                tile.configure(art: ItemArt.forSlot(kind: s.kind, id: s.id, card: s.card, deckId: campaign.deckId),
                               price: price,
                               affordable: campaign.getCoins() >= price,
                               tier: tierOf(s),
                               locked: locked)
                tile.onTap = { [weak self] in self?.openDetail(slot: i) }
                tile.onHold = { [weak self] in self?.showHelp(kind: s.kind, id: s.id, card: s.card) }
            } else {
                tile.configureSold()
            }
            shelf.addSubview(tile)
            tiles.append(tile)
        }
        let cost = Int(campaign.storeRerollCost())
        rerollButton.setTitle("REFRESH · ◉\(cost)")
        rerollButton.isEnabled = campaign.canReroll()

        renderLoadout()
        view.setNeedsLayout()
        PersistenceHolder.shared?.checkpoint(campaign)
    }

    private func tierOf(_ s: StoreSlot) -> String {
        let data = GameData.shared
        switch s.kind {
        case "pillar": return data.pillarTypes.get(s.id)?.tier ?? "common"
        case "base": return data.baseTypes.get(s.id)?.tier ?? "common"
        case "pack": return data.packTypes.get(s.id)?.tier ?? "common"
        case "samepower": return data.samePowerTypes.get(s.id)?.tier ?? "common"
        case "sticker": return data.stickerTypes.get(s.id)?.tier ?? "common"
        default: return ""
        }
    }

    private func renderLoadout() {
        loadoutChips.forEach { $0.removeFromSuperview() }
        loadoutChips.removeAll()
        let data = GameData.shared
        let pillars = campaign.columnPillars
        let bases = campaign.columnBases
        for c in 0..<max(pillars.count, bases.count, 3) {
            let col = makeLoadoutColumn(
                title: "COL \(c + 1)",
                rows: [
                    (pillars[safe: c].flatMap { $0 }.flatMap { data.pillarTypes.get($0) }, "pillar", c),
                    (bases[safe: c].flatMap { $0 }.flatMap { data.baseTypes.get($0) }, "base", c),
                ])
            loadoutPanel.addSubview(col)
            loadoutChips.append(col)
        }
        let sp = campaign.getSamePower().flatMap { data.samePowerTypes.get($0) }
        let sameCol = makeLoadoutColumn(title: "SAME", rows: [(sp, "samepower", nil)])
        loadoutPanel.addSubview(sameCol)
        loadoutChips.append(sameCol)
        layoutLoadout()
    }

    private func makeLoadoutColumn(title: String, rows: [(ItemDef?, String, Int?)]) -> UIView {
        let v = UIView()
        let t = CRTKit.label(title, size: 12, color: CRT.muted)
        t.frame = CGRect(x: 0, y: 0, width: 80, height: 14)
        v.addSubview(t)
        var y: CGFloat = 16
        for (def, kind, col) in rows {
            if let def {
                let b = UIButton(type: .custom)
                b.setAttributedTitle(CRTKit.attributed(String(def.label.prefix(9)), size: 13, color: CRT.cardFace), for: .normal)
                b.backgroundColor = CRT.feltDeep
                b.layer.borderWidth = 1
                b.layer.borderColor = ItemArt.tierColor(def.tier).cgColor
                b.frame = CGRect(x: 0, y: y, width: 82, height: 24)
                b.addAction(UIAction { [weak self] _ in
                    self?.openEquippedDetail(kind: kind, id: def.id, col: col)
                }, for: .touchUpInside)
                addHold(to: b) { [weak self] in self?.showHelp(kind: kind, id: def.id, card: nil) }
                v.addSubview(b)
            } else {
                let e = CRTKit.label("empty", size: 12, color: CRT.disabledText)
                e.frame = CGRect(x: 0, y: y + 4, width: 82, height: 16)
                v.addSubview(e)
            }
            y += 28
        }
        return v
    }

    private func layoutLoadout() {
        let n = loadoutChips.count
        guard n > 0 else { return }
        let w = (loadoutPanel.bounds.width - 20) / CGFloat(n)
        for (i, v) in loadoutChips.enumerated() {
            v.frame = CGRect(x: 10 + CGFloat(i) * w, y: 24, width: w - 4,
                             height: loadoutPanel.bounds.height - 30)
        }
    }

    // MARK: - Hold-for-help

    private func addHold(to v: UIView, _ show: @escaping () -> Void) {
        let g = UILongPressGestureRecognizer(target: self, action: #selector(holdFired(_:)))
        g.minimumPressDuration = 0.45
        v.addGestureRecognizer(g)
        holdActions[ObjectIdentifier(v)] = show
    }
    private var holdActions: [ObjectIdentifier: () -> Void] = [:]
    @objc private func holdFired(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let v = g.view else { return }
        holdActions[ObjectIdentifier(v)]?()
    }

    private func showHelp(kind: String, id: String, card: CardSpec?) {
        let data = GameData.shared
        var title = "", tier = "", desc = "", suitLine: String? = nil
        switch kind {
        case "card":
            title = card?.joker == true ? "★ Joker" : "Card"
            desc = "Buy it to swap into your deck, replacing a card of your choice."
        case "removal":
            title = data.items.store.removal.label
            desc = data.items.store.removal.description
        default:
            let def = kind == "pillar" ? data.pillarTypes.get(id)
                : kind == "base" ? data.baseTypes.get(id)
                : kind == "pack" ? data.packTypes.get(id)
                : kind == "samepower" ? data.samePowerTypes.get(id)
                : data.stickerTypes.get(id)
            guard let def else { return }
            title = def.label; tier = def.tier; desc = def.description
            if kind == "sticker" {
                let suits = def.suits ?? []
                suitLine = suits.isEmpty ? "Add to any card"
                    : "Add to any \(suits.joined(separator: " or ")) card"
            }
        }
        var text = title + (tier.isEmpty ? "" : " · \(tier.uppercased())")
        if let s = suitLine { text += "\n\(s)" }
        prompt.show(text, help: desc, actions: [
            .init("OK", role: .plain) { [weak self] in self?.prompt.hide() },
        ]) { [weak self] in self?.prompt.hide() }
    }

    // MARK: - Detail + buy

    private func openDetail(slot: Int) {
        guard let offer = campaign.getStoreOffer(), let s = offer.slots[safe: slot] ?? nil else { return }
        let d = StoreDetailView(campaign: campaign, slot: slot, storeSlot: s)
        d.onClose = { [weak self] in self?.closeDetail() }
        d.onBuy = { [weak self] col in self?.buy(slot: slot, storeSlot: s, placeCol: col) }
        d.frame = view.bounds
        view.insertSubview(d, belowSubview: crt)
        detail = d
    }

    private func openEquippedDetail(kind: String, id: String, col: Int?) {
        let d = StoreDetailView(campaign: campaign, equippedKind: kind, id: id, col: col)
        d.onClose = { [weak self] in self?.closeDetail() }
        d.onSell = { [weak self] in self?.sellEquipped(kind: kind, id: id, col: col) }
        let data = GameData.shared
        let def = kind == "pillar" ? data.pillarTypes.get(id)
            : kind == "base" ? data.baseTypes.get(id) : data.samePowerTypes.get(id)
        d.setSellValue(sellValue(def))
        d.frame = view.bounds
        view.insertSubview(d, belowSubview: crt)
        detail = d
    }

    private func closeDetail() {
        detail?.removeFromSuperview()
        detail = nil
    }

    private func sellValue(_ def: ItemDef?) -> Int {
        switch def?.tier {
        case "uncommon": return 2
        case "rare": return 3
        default: return 1
        }
    }

    private func sellEquipped(kind: String, id: String, col: Int?) {
        let data = GameData.shared
        let def = kind == "pillar" ? data.pillarTypes.get(id)
            : kind == "base" ? data.baseTypes.get(id)
            : data.samePowerTypes.get(id)
        guard let def else { return }
        let value = sellValue(def)
        prompt.show("Sell \(def.label) for ◉ \(value)?", help: "It won't return to your inventory.", actions: [
            .init("Cancel", role: .plain) { [weak self] in self?.prompt.hide() },
            .init("Sell", role: .danger) { [weak self] in
                guard let self else { return }
                self.prompt.hide()
                var ok = false
                if kind == "samepower", self.campaign.getSamePower() == id {
                    _ = self.campaign.unequipSamePower()
                    ok = self.campaign.discardSamePowerFromInventory(id)
                } else if kind == "pillar", let c = col, self.campaign.columnPillar(c) == id {
                    // Sell-and-destroy: empty the slot, never back to inventory.
                    self.campaign.setColumnPillar(col: c, typeId: nil)
                    ok = true
                } else if kind == "base", let c = col, self.campaign.columnBase(c) == id {
                    self.campaign.setColumnBase(col: c, typeId: nil)
                    ok = true
                }
                guard ok else { return }
                _ = self.campaign.addCoins(value)
                Haptics.purchase()
                self.setMessage("\(def.label) sold for \(value) coins.")
                self.closeDetail()
                self.render()
            },
        ]) { [weak self] in self?.prompt.hide() }
    }

    private func buy(slot: Int, storeSlot s: StoreSlot, placeCol: Int?) {
        switch s.kind {
        case "sticker":
            // Place-then-confirm-then-pay: the picker opens first; payment
            // happens on the confirmed card.
            closeDetail()
            let picker = CardPickerViewController(campaign: campaign,
                                                  mode: .buySticker(slot: slot, typeId: s.id)) { [weak self] picked in
                guard let self else { return }
                if picked != nil {
                    Haptics.purchase()
                    self.setMessage("\(GameData.shared.stickerTypes.get(s.id)?.label ?? "Sticker") applied.")
                }
                self.render()
            }
            present(picker, animated: false)

        case "removal":
            closeDetail()
            let price = Int(campaign.removalPrice())
            guard campaign.getCoins() >= price else { return }
            let picker = CardPickerViewController(campaign: campaign,
                                                  mode: .removal(price: price)) { [weak self] picked in
                guard let self else { return }
                if picked != nil {
                    Haptics.purchase()
                    self.setMessage("A card was removed — the deck is thinner.")
                }
                self.render()
            }
            present(picker, animated: false)

        case "pillar", "base", "samepower":
            guard let col = placeCol else { return }
            let res = campaign.buyMixedSlot(slot)
            guard res.ok else { return }
            let data = GameData.shared
            if s.kind == "samepower" {
                let prev = campaign.getSamePower()
                _ = campaign.equipSamePower(s.id)
                if let prev, prev != s.id {
                    _ = campaign.discardSamePowerFromInventory(prev)
                    _ = campaign.addCoins(sellValue(data.samePowerTypes.get(prev)))
                }
            } else {
                // A displaced occupant is sold (coins back) and DESTROYED —
                // placePillar/placeBase bounce it to inventory, so drop it there.
                let old = s.kind == "pillar" ? campaign.columnPillar(col) : campaign.columnBase(col)
                if s.kind == "pillar" { _ = campaign.placePillar(s.id, col: col) }
                else { _ = campaign.placeBase(s.id, col: col) }
                if let old, old != s.id {
                    let reg = s.kind == "pillar" ? data.pillarTypes : data.baseTypes
                    if s.kind == "pillar" { _ = campaign.discardPillarFromInventory(old) }
                    else { _ = campaign.discardBaseFromInventory(old) }
                    _ = campaign.addCoins(sellValue(reg.get(old)))
                }
            }
            Haptics.purchase()
            closeDetail()
            render()

        case "pack":
            let res = campaign.buyMixedSlot(slot)
            guard res.ok, let packId = res.packId else { return }
            Haptics.purchase()
            closeDetail()
            render()
            openPackReveal(packId: packId, slot: slot, keep: res.keep ?? 1)

        case "card":
            let res = campaign.buyMixedSlot(slot)
            guard res.ok, let trayIndex = res.trayIndex else { return }
            Haptics.purchase()
            closeDetail()
            render()
            startPackKeepWalk(from: trayIndex)

        default:
            break
        }
    }

    // MARK: - Packs

    private func openPackReveal(packId: String, slot: Int, keep: Int) {
        // SEED1: a pack buy's contents key to (store node, slot).
        let keyId = offerNodeId ?? campaign.nodePos ?? 0
        let rng = runRng(seed: campaign.runSeed, [.s("storepack"), .n(keyId), .n(slot)])
        let result = campaign.revealPack(packId, rng: rng)
        let title = GameData.shared.packTypes.get(packId)?.label ?? "Pack"
        if result.kind == "card" {
            let vc = PackRevealViewController(campaign: campaign, title: title,
                                              content: .cards(result.cards),
                                              mode: .pick(keep: result.keep)) { [weak self] chosen in
                guard let self else { return }
                guard !chosen.isEmpty else { self.render(); return }
                for i in chosen { _ = self.campaign.addPackCard(result.cards[i]) }
                self.render()
                self.startPackKeepWalk(from: 0)
            }
            present(vc, animated: false)
        } else {
            let vc = PackRevealViewController(campaign: campaign, title: title,
                                              content: .stickers(result.stickers),
                                              mode: .pick(keep: result.keep)) { [weak self] chosen in
                guard let self else { return }
                guard !chosen.isEmpty else { self.render(); return }
                for i in chosen { _ = self.campaign.addStickerToInventory(result.stickers[i]) }
                self.render()
                // Straight into the apply flow for the first pick.
                if let first = chosen.first {
                    self.applyOwnedSticker(result.stickers[first])
                }
            }
            present(vc, animated: false)
        }
    }

    private func applyOwnedSticker(_ typeId: String) {
        let picker = CardPickerViewController(campaign: campaign,
                                              mode: .applySticker(typeId: typeId)) { [weak self] _ in
            self?.render()
            self?.continuePendingStickers()
        }
        present(picker, animated: false)
    }

    /// Any sticker still in inventory (a pack pick) gets its apply picker,
    /// back to back, until the inventory drains.
    private func continuePendingStickers() {
        if let (typeId, n) = campaign.stickerInventory.first(where: { $0.value > 0 }), n > 0 {
            applyOwnedSticker(typeId)
        }
    }

    /// The PACK-KEEP walk: every held tray card gets a swap picker, back to
    /// back (Skip declines one), until the tray drains.
    private func startPackKeepWalk(from index: Int) {
        guard campaign.packTrayCount() > 0 else { render(); return }
        let total = campaign.packTrayCount()
        let stepNum = max(1, total - campaign.packTrayCount() + 1)
        let step = total > 1 ? " (\(stepNum) OF \(total))" : nil
        let picker = CardPickerViewController(campaign: campaign,
                                              mode: .swap(trayIndex: 0, step: step)) { [weak self] _ in
            guard let self else { return }
            self.render()
            // Chain to the next held card (the tray compacts to the front).
            if self.campaign.packTrayCount() > 0 {
                self.startPackKeepWalk(from: 0)
            }
        }
        picker.showsSkip = true
        present(picker, animated: false)
    }

    // MARK: - Reroll

    private func rerollTapped() {
        let cost = Int(campaign.storeRerollCost())
        prompt.show("Refresh the shelf for ◉ \(cost)?",
                    help: "Rerolls climb in price within a shop visit.", actions: [
            .init("Cancel", role: .plain) { [weak self] in self?.prompt.hide() },
            .init("Refresh", role: .gold) { [weak self] in
                guard let self else { return }
                self.prompt.hide()
                if self.campaign.rerollStore() {
                    Haptics.purchase()
                    self.render()
                }
            },
        ]) { [weak self] in self?.prompt.hide() }
    }

    private func goTapped() {
        // GO TO MAP locks while anything placeable is unplaced.
        if campaign.packTrayCount() > 0 {
            setMessage("Place your held cards first.")
            startPackKeepWalk(from: 0)
            return
        }
        if let (typeId, n) = campaign.stickerInventory.first(where: { $0.value > 0 }), n > 0 {
            setMessage("Apply your stickers first.")
            applyOwnedSticker(typeId)
            return
        }
        PersistenceHolder.shared?.checkpoint(campaign)
        delegate?.storeDone(self)
    }

    // MARK: - Store key legend

    private func toggleKey() {
        if let k = keyPanel { k.removeFromSuperview(); keyPanel = nil; return }
        let data = GameData.shared
        let panel = PixelPanelView(face: CRT.feltMid, border: CRT.ink)
        var rows: [(UIImage, String, String)] = []
        if let d = data.items.stickers.first { rows.append((ItemArt.sticker(d, size: 40), "Sticker", "Sticks to one card, fires on landings")) }
        if let d = data.items.pillars.first { rows.append((ItemArt.pillar(d, width: 34, height: 44), "Pillar", "Watches one column from above")) }
        if let d = data.items.bases.first { rows.append((ItemArt.base(d, width: 44, height: 30), "Base", "Charges under a column; tap to fire")) }
        if let d = data.items.packs.first { rows.append((ItemArt.pack(d, deckId: campaign.deckId, width: 34, height: 44), "Pack", "Buy, reveal, keep a pick")) }
        if let d = data.items.samePowers.first { rows.append((ItemArt.samePower(d, width: 40, height: 40), "Same-Power", "Fires on every correct Same")) }
        rows.append((ItemArt.removal(width: 34, height: 44), "Removal", "Thin your deck — always in stock"))
        var y: CGFloat = 12
        for (img, name, sub) in rows {
            let iv = UIImageView(image: img)
            iv.contentMode = .scaleAspectFit
            iv.layer.magnificationFilter = .nearest
            iv.frame = CGRect(x: 12, y: y, width: 44, height: 44)
            panel.addSubview(iv)
            let nameL = CRTKit.label(name, size: 15, color: CRT.cardFace)
            nameL.frame = CGRect(x: 66, y: y + 4, width: 220, height: 18)
            panel.addSubview(nameL)
            let subL = CRTKit.label(sub, size: 12, color: CRT.muted)
            subL.frame = CGRect(x: 66, y: y + 22, width: 224, height: 16)
            panel.addSubview(subL)
            y += 50
        }
        panel.frame = CGRect(x: (view.bounds.width - 310) / 2, y: view.safeAreaInsets.top + 60,
                             width: 310, height: y + 8)
        view.insertSubview(panel, belowSubview: crt)
        keyPanel = panel
        panel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(closeKey)))
    }

    @objc private func closeKey() {
        keyPanel?.removeFromSuperview()
        keyPanel = nil
    }
}

// MARK: - Shelf tile

/// One shelf tile: the object itself (slight per-slot tilt — merchandise laid
/// on a surface) + a price chip. Disabled grey when unaffordable; Lammy's
/// sticker items render locked.
final class StoreTileView: UIControl {
    private let art = UIImageView()
    private let priceLabel = UILabel()
    private let panel = PixelPanelView(face: CRT.feltMid, border: CRT.ink, shadowOffsetPx: 2)
    var onTap: (() -> Void)?
    var onHold: (() -> Void)?
    private static let tilts: [CGFloat] = [-4, 3, -2.5, 2.5, -3, 4]

    init(slot: Int) {
        super.init(frame: .zero)
        panel.isUserInteractionEnabled = false
        addSubview(panel)
        art.contentMode = .scaleAspectFit
        art.layer.magnificationFilter = .nearest
        art.transform = CGAffineTransform(rotationAngle: Self.tilts[slot % Self.tilts.count] * .pi / 180)
        art.isUserInteractionEnabled = false
        addSubview(art)
        priceLabel.textAlignment = .center
        addSubview(priceLabel)
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.45
        addGestureRecognizer(hold)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    @objc private func tapped() { if isEnabled { onTap?() } }
    @objc private func held(_ g: UILongPressGestureRecognizer) {
        if g.state == .began { onHold?() }
    }

    func configure(art image: UIImage, price: Int, affordable: Bool, tier: String, locked: Bool) {
        art.image = image
        priceLabel.attributedText = CRTKit.attributed("◉\(price)", size: 15,
                                                      color: affordable ? CRT.gold : CRT.disabledText)
        alpha = locked ? 0.35 : (affordable ? 1 : 0.55)
        isEnabled = !locked
    }

    func configureSold() {
        art.image = nil
        priceLabel.attributedText = CRTKit.attributed("—", size: 17, color: CRT.disabledText)
        alpha = 0.4
        isEnabled = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        panel.frame = bounds
        art.frame = CGRect(x: 6, y: 4, width: bounds.width - 12, height: bounds.height - 32)
        priceLabel.frame = CGRect(x: 0, y: bounds.height - 24, width: bounds.width, height: 20)
    }
}

/// Placeholder haptics hook — the real engine arrives with Chunk E's sound
/// pass; buys already feel right once it lands.
enum Haptics {
    static func purchase() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
