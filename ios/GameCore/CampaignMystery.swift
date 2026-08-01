import Foundation

/// The mystery ("?") node's outcome APPLICATION — `applyMysteryEvent`, ported
/// verbatim. The state half (coins / grants / curses) mutates here; the UI
/// announces the descriptor and runs any continuation flow (picker / store
/// detour / ambush deal).
public struct MysteryOutcome {
    public var key: String
    public var title: String
    public var desc: String
    public var amount: Int?
    public var stickerId: String?
    public var stickerLabel: String?
    public var cards: [CardSpec] = []
    public var cardId: Int?
    /// Ambush shape (items.js mystery.ambush), for the deal the UI starts.
    public var ambushCards: Int?
    public var ambushPiles: Int?
    public var ambushBounty: Double?
    /// True for the boon family (rim tint on the reveal).
    public var good: Bool {
        !["cursedSticker", "coinLoss", "ambush"].contains(key)
    }
}

extension CampaignState {

    /// Apply outcome `key` for `nodeId` (detail randomness seeded by the node,
    /// so a refresh can never re-roll). Returns the UI descriptor, or nil when
    /// the outcome could not apply (the caller then treats it as a no-op).
    public func applyMysteryEvent(_ key: String, nodeId: Int) -> MysteryOutcome? {
        let rng = RNG(seed: mysterySeed(seed: runSeed, nodeId: nodeId, salt: mysteryDetailSalt))
        let m = data.items.mystery
        let stageIdx = min(phaseIndex, max(0, m.coinRangeByStage.count - 1))
        let range = m.coinRangeByStage[safe: stageIdx] ?? [1, 3]
        func coinAmount() -> Int {
            let lo = Int(range[0]), hi = Int(range[safe: 1] ?? range[0])
            return lo + rng.index(hi - lo + 1)
        }
        func coinBonus() -> MysteryOutcome {
            let amount = coinAmount()
            _ = earnCoins(amount)
            return MysteryOutcome(key: "coinBonus", title: "Cache",
                                  desc: "+\(amount) coins", amount: amount)
        }

        switch key {
        case "coinBonus":
            return coinBonus()

        case "coinLoss":
            let amount = min(coins, coinAmount())   // floored at 0 — never negative
            coins -= amount
            return MysteryOutcome(key: key, title: "Toll", desc: "−\(amount) coins", amount: amount)

        case "stickerPack":
            let pool = grantableStickers()
            let ids = StoreRoll.rollIds(pool, 1, rng, tierWeights: data.items.store.tierWeights)
            guard let sid = ids.first, let t = data.stickerTypes.get(sid) else { return nil }
            stickerInventory[sid, default: 0] += 1
            return MysteryOutcome(key: key, title: "Imprint",
                                  desc: "A \(t.label) sticker joins your inventory",
                                  stickerId: sid, stickerLabel: t.label)

        case "cards":
            let gr = data.items.mystery.cardGrantRange
            let lo = gr[safe: 0] ?? 1, hi = gr[safe: 1] ?? lo
            let n = lo + rng.index(hi - lo + 1)
            let anySuit = rules().altSuits || phaseIndex >= phaseSuits.count
            var granted: [CardSpec] = []
            for _ in 0..<n {
                let slotSuit = anySuit ? allSuits[rng.index(allSuits.count)] : phaseSuit()
                let id = pickSuitDraftId(slotSuit, rng: rng)
                ownedIds.append(id)
                if let i = baseDeck.firstIndex(where: { $0.id == id }) {
                    rollGrantStickers(at: i, rng: rng)
                    granted.append(baseDeck[i])
                }
            }
            guard !granted.isEmpty else { return nil }
            let desc = granted.count == 1
                ? "\(cardName(granted[0])) joins your deck"
                : "\(granted.count) cards join your deck"
            return MysteryOutcome(key: key, title: "Windfall", desc: desc, cards: granted)

        case "joker":
            // HELD-vs-CAP gate: at cap the roll deterministically folds to coins.
            guard jokersHeld() < jokerCapFor() else { return coinBonus() }
            let jid = mintJokerId()
            ownedIds.append(jid)
            let card = findById(jid)
            return MysteryOutcome(key: key, title: "Wild Card",
                                  desc: "A ★ Joker joins your deck",
                                  cards: card.map { [$0] } ?? [], cardId: jid)

        case "store":
            return MysteryOutcome(key: key, title: "Detour",
                                  desc: "The store opens on the spot — the node waits for you")

        case "freeRemoval":
            return MysteryOutcome(key: key, title: "Purge",
                                  desc: "Remove a card from your deck — free")

        case "stickerStrip":
            return MysteryOutcome(key: key, title: "Cleanse",
                                  desc: "Strip a sticker from a card — free")

        case "cursedSticker":
            // UNGATED by design: a curse is INFLICTED, never player-acquired.
            let cursedTypes = data.items.stickers.filter(\.cursed)
            guard !cursedTypes.isEmpty else { return nil }
            let t = cursedTypes[rng.index(cursedTypes.count)]
            let eligible = ownedIds.compactMap { id in
                baseDeck.firstIndex(where: { $0.id == id })
            }.filter { CardRules.stickerEligible(baseDeck[$0], t.id, data: data) }
            guard !eligible.isEmpty else { return nil }
            let at = eligible[rng.index(eligible.count)]
            guard applyStickerToCard(&baseDeck[at], t.id, rng: rng) else { return nil }
            return MysteryOutcome(key: key, title: "Cursed",
                                  desc: "\(t.label) afflicts your \(cardName(baseDeck[at]))",
                                  stickerId: t.id, stickerLabel: t.label,
                                  cardId: baseDeck[at].id)

        case "ambush":
            let a = data.items.mystery.ambush
            return MysteryOutcome(key: key, title: "Ambush",
                                  desc: "Survive a \(Int(a.cards))-card deal on \(Int(a.piles)) piles → +\(Int(a.bounty)) coins",
                                  ambushCards: Int(a.cards), ambushPiles: Int(a.piles), ambushBounty: a.bounty)

        default:
            return nil
        }
    }

    /// MR. SMITH: map grants may carry stickers exactly like his pack cards.
    func rollGrantStickers(at index: Int, rng: RNG) {
        guard rules().startStickers else { return }
        let card = baseDeck[index]
        guard !card.joker, !card.blank else { return }
        let n = StoreRoll.packStickerCount(rng.next(), data: data)
        guard n > 0 else { return }
        let pool = grantableStickers().filter { CardRules.stickerEligible(card, $0.id, data: data) }
        guard !pool.isEmpty else { return }
        for _ in 0..<n {
            let ids = StoreRoll.rollIds(pool, 1, rng, tierWeights: data.items.store.tierWeights)
            if let sid = ids.first { _ = applyStickerToCard(&baseDeck[index], sid, rng: rng) }
        }
    }

    func cardName(_ c: CardSpec) -> String {
        if c.joker { return "★ Joker" }
        if c.blank { return "∅ Removal" }
        let label = DeckManager.ranks.first { $0.value == c.currentRank }?.label ?? "\(c.currentRank)"
        return "\(label)\(c.suit)"
    }
}
