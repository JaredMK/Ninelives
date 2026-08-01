import Foundation

/// The pending pack tray + permanent deck surgery — ported verbatim from the
/// web campaign's tray block. Store card buys and pack picks HOLD their cards
/// here; each is then swapped into the deck (replacing a card of the player's
/// choice), or declined. The tray cap is infinite, like the web's.
extension CampaignState {

    // MARK: - Pack tray

    public func packTrayCount() -> Int { packTray.count }

    public func getPackTray() -> [CardSpec] { packTray }

    /// Hold a revealed card-pack pick. Mirrors `addPackCard` (cap = ∞).
    @discardableResult
    public func addPackCard(_ card: CardSpec) -> Bool {
        packTray.append(card)
        return true
    }

    /// Decline a held pack card (no refund — the pack was already paid for).
    @discardableResult
    public func discardPackCard(_ index: Int) -> Bool {
        guard index >= 0, index < packTray.count else { return false }
        packTray.remove(at: index)
        return true
    }

    /// Take a held pack card OUT of the tray (pre-run replacement).
    public func takePackCard(_ index: Int) -> CardSpec? {
        guard index >= 0, index < packTray.count else { return nil }
        return packTray.remove(at: index)
    }

    /// PERMANENT deck replacement: remove `dealtId` from the campaign deck (its
    /// stickers gone forever) and put the tray card in its place. A BLANK tray
    /// card is a removal tool — it removes the chosen card and adds nothing, so
    /// the deck shrinks by one. Returns the inserted card, or nil on failure.
    @discardableResult
    public func replaceDeckCard(_ dealtId: Int, trayIndex: Int) -> CardSpec? {
        guard let di = baseDeck.firstIndex(where: { $0.id == dealtId }) else { return nil }
        guard trayIndex >= 0, trayIndex < packTray.count else { return nil }
        let packCard = packTray.remove(at: trayIndex)
        baseDeck.remove(at: di)
        if packCard.blank {
            if let oi = ownedIds.firstIndex(of: dealtId) { ownedIds.remove(at: oi) }
            return packCard
        }
        // The catalog holds the card exactly once (a store card buy may have
        // pre-registered it at purchase time).
        if !baseDeck.contains(where: { $0.id == packCard.id }) { baseDeck.append(packCard) }
        // The OWNED set follows the swap IN PLACE, so the deck view and the
        // count agree (the web's #1 bugfix).
        if let oi = ownedIds.firstIndex(of: dealtId) { ownedIds[oi] = packCard.id }
        else if !ownedIds.contains(packCard.id) { ownedIds.append(packCard.id) }
        return packCard
    }

    // MARK: - Sticker inventory grants + strips

    /// Keep a revealed STICKER-pack pick: straight into the normal inventory
    /// (no cost — the pack was already paid for).
    @discardableResult
    public func addStickerToInventory(_ id: String) -> Bool {
        guard data.stickerTypes.get(id) != nil else { return false }
        stickerInventory[id, default: 0] += 1
        return true
    }

    /// Remove ONE random sticker instance from a card (the stickerStrip
    /// mystery outcome). Randomness defaults to the ACTION stream (SEED1 —
    /// a refresh can't fish for a different sticker). Returns the removed
    /// type id, or nil when the card carries none.
    @discardableResult
    public func removeRandomStickerFrom(_ cardId: Int, rng: RNG? = nil) -> String? {
        let r = rng ?? actRng()
        guard let ci = baseDeck.firstIndex(where: { $0.id == cardId }),
              !baseDeck[ci].stickers.isEmpty else { return nil }
        let at = r.index(baseDeck[ci].stickers.count)
        let typeId = baseDeck[ci].stickers[at].type
        baseDeck[ci].stickers.remove(at: at)
        return typeId
    }

    /// Duplicate sticker: deep-copy a persistent card into the pack tray with
    /// a fresh id, fully independent of the source. Returns the copy.
    @discardableResult
    public func duplicateCard(_ cardId: Int) -> CardSpec? {
        guard let src = findById(cardId) else { return nil }
        var copy = src
        copy.id = nextCardId
        nextCardId += 1
        packTray.append(copy)
        return copy
    }

    // MARK: - Sell-and-destroy (the store's SELL1 rule)

    /// A sold item never returns to the player: these drop one inventory copy
    /// for good (the displaced-item destroy the buy-replace flow needs).
    @discardableResult
    public func discardPillarFromInventory(_ id: String) -> Bool {
        guard (pillarInventory[id] ?? 0) > 0 else { return false }
        pillarInventory[id]! -= 1
        if pillarInventory[id] == 0 { pillarInventory[id] = nil }
        return true
    }

    @discardableResult
    public func discardBaseFromInventory(_ id: String) -> Bool {
        guard (baseInventory[id] ?? 0) > 0 else { return false }
        baseInventory[id]! -= 1
        if baseInventory[id] == 0 { baseInventory[id] = nil }
        return true
    }

    @discardableResult
    public func discardSamePowerFromInventory(_ id: String) -> Bool {
        guard (samePowerInventory[id] ?? 0) > 0 else { return false }
        samePowerInventory[id]! -= 1
        if samePowerInventory[id] == 0 { samePowerInventory[id] = nil }
        return true
    }
}
