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

    private let shell = TopShellView()
    private let titleLabel = UILabel()
    private let balanceLabel = UILabel()
    private let helpButton = PixelButtonView("?", role: .plain, fontSize: 16)
    private let msgLabel = UILabel()
    private let shelf = UIView()
    private var tiles: [StoreTileView] = []
    private let rerollButton = PixelButtonView("REFRESH", role: .gold, fontSize: 13)
    private let loadoutPanel = PixelPanelView(face: CRT.feltMid, border: CRT.ink)
    private let loadoutTitle = UILabel()
    private var loadoutChips: [UIView] = []
    private let goButton = PixelButtonView("GO TO MAP", role: .cta, fontSize: 18)
    private let prompt = PromptBar()
    private let crt = CRTOverlayUIView()
    private let tissue = TissueView()
    private var detail: StoreDetailView?
    private var keyPanel: UIView?

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
        tissue.frame = view.bounds
        tissue.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(tissue)          // #tissue atmosphere, bottommost

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

        // The persistent top shell (HUD line + deck band), same as the map.
        shell.showsDeckStack = true
        shell.onDeckTap = { [weak self] in
            guard let self else { return }
            self.present(DeckInspectViewController(campaign: self.campaign), animated: false)
        }
        view.addSubview(shell)

        // "Shop" + the balance beneath; Refresh + ? clustered on the right.
        titleLabel.attributedText = CRTKit.attributed("Shop", size: 22, color: CRT.cardFace, display: true)
        view.addSubview(titleLabel)
        view.addSubview(balanceLabel)
        helpButton.onTap = { [weak self] in self?.toggleKey() }
        view.addSubview(helpButton)

        msgLabel.isHidden = true
        view.addSubview(msgLabel)
        view.addSubview(shelf)

        rerollButton.onTap = { [weak self] in self?.rerollTapped() }
        view.addSubview(rerollButton)

        view.addSubview(loadoutPanel)
        loadoutTitle.attributedText = CRTKit.attributed("EQUIPPED", size: 12, color: CRT.muted, display: true)
        loadoutPanel.addSubview(loadoutTitle)

        goButton.onTap = { [weak self] in self?.goTapped() }
        view.addSubview(goButton)

        crt.isUserInteractionEnabled = false
        view.addSubview(crt)
        view.addSubview(prompt)

        setMessage("Buy from the offer, refresh, then head for the map.")
        render()
        // Autopilot: browse a beat, then GO TO MAP (buys are exercised by the
        // picker flows the mystery outcomes drive).
        if UserDefaults.standard.integer(forKey: "autoCampaign") > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.goTapped()
            }
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        let shellH = TopShellView.height(safeTop: view.safeAreaInsets.top)
        shell.frame = CGRect(x: 0, y: 0, width: b.width, height: shellH)

        // Title row: Shop + balance left; Refresh + ? right.
        titleLabel.frame = CGRect(x: 12, y: shellH + 8, width: 160, height: 26)
        balanceLabel.frame = CGRect(x: 12, y: shellH + 36, width: 200, height: 18)
        helpButton.frame = CGRect(x: b.width - 42, y: shellH + 16, width: 32, height: 32)
        rerollButton.frame = CGRect(x: b.width - 42 - 8 - 130, y: shellH + 14, width: 130, height: 36)

        // The shelf GROWS to fill everything between the title row and the
        // equipped panel — tall tiles, the merchandise breathes (web parity).
        let goH: CGFloat = 46
        let loH: CGFloat = 96
        let goTop = b.height - view.safeAreaInsets.bottom - goH - 10
        let loTop = goTop - loH - 8
        let shelfTop = shellH + 60
        let tw = (b.width - 12 * 2 - 11 * 2) / 3
        let th = (loTop - 8 - shelfTop - 11) / 2
        shelf.frame = CGRect(x: 12, y: shelfTop, width: b.width - 24, height: th * 2 + 11)
        for (i, t) in tiles.enumerated() {
            let r = i / 3, c = i % 3
            t.frame = CGRect(x: CGFloat(c) * (tw + 11), y: CGFloat(r) * (th + 11), width: tw, height: th)
        }
        loadoutPanel.frame = CGRect(x: 12, y: loTop, width: b.width - 24, height: loH)
        loadoutTitle.frame = CGRect(x: 10, y: 6, width: 200, height: 16)
        layoutLoadout()
        goButton.frame = CGRect(x: 12, y: goTop, width: b.width - 24, height: goH)
        crt.frame = b
        tissue.frame = b
        prompt.frame = b
        detail?.frame = b
    }

    private func setMessage(_ s: String) {
        msgLabel.attributedText = CRTKit.attributed(s, size: 13, color: CRT.muted)
    }

    // MARK: - Render

    public func render() {
        shell.sync(campaign: campaign)
        let bal = NSMutableAttributedString(
            string: "\(campaign.getCoins()) ", attributes: [.font: CRT.Font.of(17), .foregroundColor: CRT.gold])
        bal.append(NSAttributedString(
            string: "◉ to spend", attributes: [.font: CRT.Font.of(13), .foregroundColor: CRT.muted]))
        balanceLabel.attributedText = bal

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
                // Web `.ti-obj.obj-removal`: the shelf removal object is the
                // bare torn card — its "REMOVAL" caption (.ro-lab) is LIVE text
                // under the art (the tile caption below), never baked in.
                let art = s.kind == "removal"
                    ? ItemArt.removal(width: 52, height: 66)
                    : ItemArt.forSlot(kind: s.kind, id: s.id, card: s.card, deckId: campaign.deckId)
                // Only packs (.pf-name) and Removal (.ro-lab) carry a NAME on
                // the web shelf — pillar/base/sticker tiles are art + price
                // only. The label always comes from the registry.
                let caption = s.kind == "pack" ? GameData.shared.packTypes.get(s.id)?.label
                    : s.kind == "removal" ? GameData.shared.items.store.removal.label : nil
                tile.configure(art: art, kind: s.kind, caption: caption,
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
        rerollButton.setTitle("↻ REFRESH · ◉\(cost)")
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
        let t = CRTKit.label(title, size: 11, color: CRT.muted)
        t.alpha = 0.7
        t.textAlignment = .center
        t.frame = CGRect(x: 0, y: 0, width: 82, height: 14)
        v.addSubview(t)
        var y: CGFloat = 17
        for (def, kind, col) in rows {
            // Web `.lo-chip`: a recessed deep-felt slab, ink border; class
            // identity by TEXT colour — pillar gold · base cream · Same phosphor.
            let tint: UIColor = kind == "pillar" ? CRT.gold
                : kind == "samepower" ? CRT.phosphor : CRT.cardFace
            if let def {
                let b = UIButton(type: .custom)
                b.setAttributedTitle(CRTKit.attributed(String(def.label.prefix(9)), size: 12, color: tint), for: .normal)
                b.backgroundColor = CRT.feltDeep
                b.layer.borderWidth = 1
                b.layer.borderColor = CRT.ink.cgColor
                b.frame = CGRect(x: 0, y: y, width: 82, height: 24)
                b.addAction(UIAction { [weak self] _ in
                    self?.openEquippedDetail(kind: kind, id: def.id, col: col)
                }, for: .touchUpInside)
                addHold(to: b) { [weak self] in self?.showHelp(kind: kind, id: def.id, card: nil) }
                v.addSubview(b)
            } else {
                let e = CRTKit.label("empty", size: 12, color: CRT.disabledText)
                e.textAlignment = .center
                e.backgroundColor = CRT.feltDeep
                e.layer.borderWidth = 1
                e.layer.borderColor = CRT.ink.cgColor
                e.frame = CGRect(x: 0, y: y, width: 82, height: 24)
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
                    Sound.shared.refresh()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
        panel.frame = CGRect(x: (view.bounds.width - 310) / 2,
                             y: TopShellView.height(safeTop: view.safeAreaInsets.top) + 52,
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

/// One shelf tile, web `.store-tile`: a pixel plaque (felt-mid face, ink
/// border, hard shadow) with a 4px rarity strip under the top edge
/// (common = quiet cream · uncommon = gold · rare = phosphor), the object
/// SMALL and centred on the shelf (web caps it per kind — sticker ≤68px,
/// base ≤46px, pack ≈100px, …), an optional name caption (packs + Removal
/// ONLY, web `.pf-name` / `.ro-lab`), and the gold-on-ink price chip — the
/// art/caption/price stack centres as one group. Unaffordable dims but stays
/// tappable.
final class StoreTileView: UIControl {
    private let art = UIImageView()
    private let captionLabel = UILabel()
    private let priceLabel = UILabel()
    private let panel = PixelPanelView(face: CRT.feltMid, border: CRT.ink, shadowOffsetPx: 4)
    private let tierStrip = UIView()
    /// Web `.ti-obj` per-kind height caps (the object never fills the tile).
    private var artCap: CGFloat = 90
    var onTap: (() -> Void)?
    var onHold: (() -> Void)?

    init(slot: Int) {
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "shelf-\(slot)"
        panel.isUserInteractionEnabled = false
        addSubview(panel)
        tierStrip.isUserInteractionEnabled = false
        panel.addSubview(tierStrip)
        art.contentMode = .scaleAspectFit
        art.layer.magnificationFilter = .nearest
        art.isUserInteractionEnabled = false
        addSubview(art)
        captionLabel.textAlignment = .center
        captionLabel.isUserInteractionEnabled = false
        captionLabel.isHidden = true
        addSubview(captionLabel)
        priceLabel.textAlignment = .center
        priceLabel.backgroundColor = CRT.ink
        priceLabel.layer.borderWidth = 1
        priceLabel.layer.borderColor = CRT.gold.withAlphaComponent(0.4).cgColor
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

    func configure(art image: UIImage, kind: String, caption: String?, price: Int,
                   affordable: Bool, tier: String, locked: Bool) {
        art.image = image
        switch kind {
        case "sticker": artCap = 68
        case "base": artCap = 46
        case "pack": artCap = 100
        case "pillar": artCap = 100
        case "removal": artCap = 66
        case "card": artCap = 68
        case "samepower": artCap = 84
        default: artCap = 90
        }
        if let caption {
            // Web `.pf-name` is bright cream; `.ro-lab` hangs dimmer.
            let dim = kind == "removal"
            captionLabel.attributedText = CRTKit.attributed(
                caption.uppercased(), size: 12,
                color: CRT.cardFace.withAlphaComponent(dim ? 0.6 : 1))
            captionLabel.isHidden = false
        } else {
            captionLabel.attributedText = nil
            captionLabel.isHidden = true
        }
        switch tier {
        case "uncommon": tierStrip.backgroundColor = CRT.gold
        case "rare": tierStrip.backgroundColor = CRT.phosphor
        default: tierStrip.backgroundColor = CRT.cardFace.withAlphaComponent(0.30)
        }
        tierStrip.isHidden = false
        priceLabel.attributedText = CRTKit.attributed("◉ \(price)", size: 13,
                                                      color: affordable ? CRT.gold : CRT.disabledText)
        priceLabel.isHidden = false
        alpha = locked ? 0.32 : (affordable ? 1 : 0.5)
        isEnabled = !locked
    }

    func configureSold() {
        art.image = nil
        captionLabel.attributedText = nil
        captionLabel.isHidden = true
        tierStrip.isHidden = true
        priceLabel.isHidden = true
        alpha = 0.4
        isEnabled = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        panel.frame = bounds
        tierStrip.frame = CGRect(x: CRT.px, y: CRT.px, width: bounds.width - CRT.px * 2, height: 4)
        // The web tile is a centred flex column: object (capped), optional name
        // caption, price chip — the STACK centres as a group inside the plaque.
        let capH: CGFloat = captionLabel.isHidden ? 0 : 14
        let priceH: CGFloat = 20
        let gap: CGFloat = 6
        var stack = capH > 0 ? capH + gap : 0
        let availArt = bounds.height - 16 - priceH - gap - stack
        let artH = max(24, min(artCap, availArt))
        stack += artH + gap + priceH
        var y = (bounds.height - stack) / 2
        art.frame = CGRect(x: 6, y: y, width: bounds.width - 12, height: artH)
        y += artH + gap
        if capH > 0 {
            captionLabel.frame = CGRect(x: 2, y: y, width: bounds.width - 4, height: capH)
            y += capH + gap
        }
        let pw: CGFloat = 54
        priceLabel.frame = CGRect(x: (bounds.width - pw) / 2, y: y, width: pw, height: priceH)
    }
}

/// Purchase feedback: the warm cha-ching + a medium haptic thump together.
enum Haptics {
    static func purchase() {
        Sound.shared.purchase()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
