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
    /// EVERY sticker the outcome touched (Peeled tears several) — the reveal
    /// draws their chips beside the card so the loss is seen, not just named.
    public var stickerIds: [String] = []
    public var cards: [CardSpec] = []
    public var cardId: Int?
    /// Ambush shape (items.js mystery.ambush), for the deal the UI starts.
    public var ambushCards: Int?
    public var ambushPiles: Int?
    public var ambushBounty: Double?
    /// The equipped item an itemTheft took ("pillar"/"base" + registry id) —
    /// the reveal draws its art so the loss is SEEN, not just named.
    public var itemKind: String?
    public var itemId: String?
    /// Compose one directly. The mystery ROLL builds these itself, but the Old
    /// Joker's purge reuses the same reveal to show the cards his leech marked.
    public init(key: String, title: String, desc: String, amount: Int? = nil,
                stickerId: String? = nil, stickerLabel: String? = nil,
                cards: [CardSpec] = [], cardId: Int? = nil,
                ambushCards: Int? = nil, ambushPiles: Int? = nil, ambushBounty: Double? = nil,
                itemKind: String? = nil, itemId: String? = nil) {
        self.key = key; self.title = title; self.desc = desc; self.amount = amount
        self.stickerId = stickerId; self.stickerLabel = stickerLabel
        self.cards = cards; self.cardId = cardId
        self.ambushCards = ambushCards; self.ambushPiles = ambushPiles
        self.ambushBounty = ambushBounty
        self.itemKind = itemKind; self.itemId = itemId
    }

    /// True for the boon family (rim tint on the reveal).
    public var good: Bool {
        !["cursedSticker", "coinLoss", "ambush", "stickerTheft",
          "itemTheft", "priceDouble", "shieldDrain", "mammaLie", "twoGame"].contains(key)
    }
}

extension CampaignState {

    /// Apply outcome `key` for `nodeId` (detail randomness seeded by the node,
    /// so a refresh can never re-roll). Returns the UI descriptor, or nil when
    /// the outcome could not apply (the caller then treats it as a no-op).
    /// `cursePath` names the inflicting pathway for the shared curse roll —
    /// "mystery" for the ? node itself, "doors" when THE OLD JOKER's bad door
    /// chains into this outcome (each pathway has its own pool exclusions).
    public func applyMysteryEvent(_ key: String, nodeId: Int, cursePath: String = "mystery") -> MysteryOutcome? {
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
            // No caption (v6.64): the reveal's coin well already shows the
            // ◉ figure and the signed amount — a "+N coins" line under it
            // only repeated the well.
            return MysteryOutcome(key: "coinBonus", title: "Cache",
                                  desc: "", amount: amount)
        }

        DebugEventLog.shared.add("mystery: \(key) at node \(nodeId) (path \(cursePath))")
        switch key {
        case "coinBonus":
            return coinBonus()

        case "coinLoss":
            // Never show a loss to a broke player — at 0 coins the toll
            // flips to a bonus instead of reading "−0 coins" (v5.82).
            guard coins > 0 else { return coinBonus() }
            let amount = min(coins, coinAmount())   // floored at 0 — never negative
            coins -= amount
            // No caption (v6.65, the Cache's v6.64 shape): the reveal's coin
            // well already shows the ◉ figure and the signed amount — a
            // "−N coins" line under it only repeated the well.
            return MysteryOutcome(key: key, title: "Toll", desc: "", amount: amount)

        case "stickerPack":
            // Only ever offer a sticker the player can actually PLACE. Rolling
            // from the unfiltered pool used to hand over stickers no card could
            // take, which then sat in an invisible inventory forever. With
            // nothing placeable the outcome folds to coins, the same way the
            // joker cap and stickerStrip already do (v5.83).
            let pool = grantableStickersWithTarget()
            guard !pool.isEmpty else { return coinBonus() }
            let ids = StoreRoll.rollIds(pool, 1, rng, tierWeights: data.items.store.tierWeights)
            guard let sid = ids.first, let t = data.stickerTypes.get(sid) else { return coinBonus() }
            stickerInventory[sid, default: 0] += 1
            // No prose caption (v6.64): the reveal prints the sticker's NAME
            // over its registry description under the chip instead.
            return MysteryOutcome(key: key, title: "Imprint",
                                  desc: "",
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
            // No caption (v6.65): the granted cards are drawn in the well —
            // the image is the news, "N cards join your deck" only repeated it.
            return MysteryOutcome(key: key, title: "Windfall", desc: "", cards: granted)

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
                                  desc: "The store opens on the spot")

        case "freeRemoval":
            return MysteryOutcome(key: key, title: "Purge",
                                  desc: "Purge a card from the deck")

        case "stickerStrip":
            // v6.52: the Queen offers a Cleanse only when a CURSE actually
            // sits on a card — stripping ordinary stickers you paid for was
            // her "boon" removing value. No curse in the deck → fold to coins
            // at apply time (deterministic, like the joker cap).
            guard getRunDeck().contains(where: { c in
                c.stickers.contains { data.stickerTypes.get($0.type)?.cursed == true }
            }) else { return coinBonus() }
            return MysteryOutcome(key: key, title: "Cleanse",
                                  desc: "Strip the stickers from a card")

        case "cursedSticker":
            // UNGATED by design: a curse is INFLICTED, never player-acquired.
            // WHICH curse comes from the shared weighted roll (curseWeight in
            // items.js), pooled per pathway.
            guard let t = data.stickerTypes.rollCurse(path: cursePath, roll: rng.next())
            else { return nil }
            let eligible = ownedIds.compactMap { id in
                baseDeck.firstIndex(where: { $0.id == id })
            }.filter { CardRules.stickerEligible(baseDeck[$0], t.id, data: data) }
            guard !eligible.isEmpty else { return nil }
            let at = eligible[rng.index(eligible.count)]
            guard applyStickerToCard(&baseDeck[at], t.id, rng: rng) else { return nil }
            DebugEventLog.shared.add("curse: \(t.label) afflicts \(cardName(baseDeck[at])) (path \(cursePath))")
            // No prose caption (v6.65): the reveal draws the afflicted card
            // wearing ALL its stickers, and beneath it ONLY the curse's name
            // + registry description print (PhaseOverlayView's per-curse
            // captions) — "X afflicts your Y" was a third telling.
            return MysteryOutcome(key: key, title: "Cursed",
                                  desc: "",
                                  stickerId: t.id, stickerLabel: t.label,
                                  cardId: baseDeck[at].id)

        case "ambush":
            let a = data.items.mystery.ambush
            // v6.65: the terms only — the bounty figure is the deal's own
            // reward line now, not the invitation's. Numbers stay config-read.
            return MysteryOutcome(key: key, title: "Ambush",
                                  desc: "Survive a \(Int(a.cards)) card deal with \(Int(a.piles)) piles",
                                  ambushCards: Int(a.cards), ambushPiles: Int(a.piles), ambushBounty: a.bounty)

        // ── JUST A TWO's tricks ──────────────────────────────────────────────

        case "stickerTheft":
            // A RANDOM stickered card is stripped BARE (like her Cleanse, but
            // he picks the card). No target → a Toll.
            let stickered = ownedIds.compactMap { id in
                baseDeck.first { $0.id == id && !$0.stickers.isEmpty }
            }
            guard !stickered.isEmpty else { return applyMysteryEvent("coinLoss", nodeId: nodeId) }
            let victim = stickered[rng.index(stickered.count)]
            // NAME what he took — "2 stickers" told the player nothing.
            var torn: [String] = []
            var tornIds: [String] = []
            while let tid = removeRandomStickerFrom(victim.id, rng: rng) {
                torn.append(data.stickerTypes.get(tid)?.label ?? tid)
                tornIds.append(tid)
            }
            let after = baseDeck.first { $0.id == victim.id } ?? victim
            var out = MysteryOutcome(key: key, title: "Peeled",
                                     desc: "\(torn.joined(separator: " + ")) torn off your \(cardName(after))",
                                     cards: [after], cardId: after.id)
            out.stickerIds = tornIds
            return out

        case "itemTheft":
            // A RANDOM equipped Pillar or Base is repossessed — gone, not
            // pocketed. Nothing on the board → a Toll.
            var slots: [(kind: String, col: Int, id: String)] = []
            for (c, id) in columnPillars.enumerated() where id != nil { slots.append(("pillar", c, id!)) }
            for (c, id) in columnBases.enumerated() where id != nil { slots.append(("base", c, id!)) }
            guard !slots.isEmpty else { return applyMysteryEvent("coinLoss", nodeId: nodeId) }
            let pick = slots[rng.index(slots.count)]
            if pick.kind == "pillar" { columnPillars[pick.col] = nil } else { columnBases[pick.col] = nil }
            let label = labelOf(kind: pick.kind == "pillar" ? .pillar : .base, id: pick.id)
            // v6.65: "off column N" dropped — the taken item's art is in the
            // well, and the column it leaves empty is plain to see.
            return MysteryOutcome(key: key, title: "Repossessed",
                                  desc: "\(label) is taken",
                                  itemKind: pick.kind, itemId: pick.id)

        case "priceDouble":
            storePriceModPending = "double"
            return MysteryOutcome(key: key, title: "Markup",
                                  desc: "At the next shop every item costs double")

        case "shieldDrain":
            // Only lands on a CHARGED shield; empty → a Toll.
            guard sameCharge else { return applyMysteryEvent("coinLoss", nodeId: nodeId) }
            sameCharge = false
            return MysteryOutcome(key: key, title: "Punctured",
                                  desc: "Your charged Same shield is drained")

        // ── THE BEHEADED QUEEN's gifts ───────────────────────────────────────

        case "priceOne":
            storePriceModPending = "one"
            return MysteryOutcome(key: key, title: "Fire Sale",
                                  desc: "At the next shop every item costs 1 coin")

        case "freeRefresh":
            freeRerollPending = true
            return MysteryOutcome(key: key, title: "Restock",
                                  desc: "Your next deal's first restock is free")

        case "freeRedeal":
            freeRedealPending = true
            return MysteryOutcome(key: key, title: "Mulligan",
                                  desc: "Your next deal's first reshuffle is free")

        case "shieldCharge":
            // Only fills an EMPTY shield; already charged → a Cache.
            guard !sameCharge else { return applyMysteryEvent("coinBonus", nodeId: nodeId) }
            sameCharge = true
            return MysteryOutcome(key: key, title: "Charged",
                                  desc: "Your Same shield is charged")

        case "coinDouble":
            // Doubling an empty purse is nothing — fold to a Cache.
            guard coins > 0 else { return applyMysteryEvent("coinBonus", nodeId: nodeId) }
            let gained = coins
            _ = earnCoins(gained)
            // No caption (v6.64): the coin well's signed figure says it.
            return MysteryOutcome(key: key, title: "Doubled",
                                  desc: "", amount: gained)

        case "mammaLie":
            // THE CON. Nothing is taken HERE — the UI presents the offer and
            // `resolveMammaLie` collects if the player bites. Needs a ★ to
            // covet, and something to actually lose; otherwise a plain Toll.
            guard getRunDeck().contains(where: { $0.joker }),
                  coins > 0 || getRunDeck().contains(where: { $0.joker })
            else { return applyMysteryEvent("coinLoss", nodeId: nodeId) }
            return MysteryOutcome(key: key, title: "A Friend of Mamma's",
                                  desc: "It says it knows Mamma. It says it can take you to her.",
                                  amount: coins)

        case "twoGame":
            // THE TWO'S GAME (v6.65: a RED-or-BLACK call on the hidden card's
            // COLOR — the higher/lower/same pivot call is gone). It only plays
            // when there is something on the table: a CHARGED Same shield. No
            // shield → a Toll. The hidden card rolls HERE (seeded, like every
            // mystery detail); the UI presents the call and `resolveTwoGame`
            // settles it. The card is a phantom for the reveal — it never
            // joins the deck. The suit draw is one of the four standard suits
            // (`DeckManager.suits`), so a ★ Joker can never be the hidden
            // card: every roll has a color.
            guard sameCharge else { return applyMysteryEvent("coinLoss", nodeId: nodeId) }
            let suit = allSuits[rng.index(allSuits.count)]
            let rank = minRank + rng.index(maxRank - minRank + 1)
            let card = CardSpec(id: -1, suit: suit, originalRank: rank, currentRank: rank)
            return MysteryOutcome(key: key, title: "The Two's Game",
                                  desc: "",
                                  amount: rank, cards: [card])

        case "giftCard":
            // Her keepsake: a card wearing 2–3 stickers (none for Lammy), into
            // the tray to SWAP for a card of your choice — the deck never grows.
            let suits = allSuits
            let suit = suits[rng.index(suits.count)]
            let rank = minRank + rng.index(maxRank - minRank + 1)
            var card = CardSpec(id: nextCardId, suit: suit, originalRank: rank, currentRank: rank)
            nextCardId += 1
            if !rules().noStickers {
                let n = 2 + rng.index(2)
                let pool = grantableStickers().filter { CardRules.stickerEligible(card, $0.id, data: data) }
                for _ in 0..<n {
                    guard let sid = StoreRoll.rollIds(pool, 1, rng, tierWeights: data.items.store.tierWeights).first
                    else { continue }
                    applyStickerToCard(&card, sid, rng: rng, suits: suits)
                }
            }
            packTray.append(card)
            baseDeck.append(card)
            return MysteryOutcome(key: key, title: "Keepsake",
                                  desc: "Swap it in for a card of your choice",
                                  cards: [card], cardId: card.id)

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

    /// THE TWO'S GAME, settled (v6.65): `guess` is "red" / "black", called
    /// against the hidden card's COLOR (♥♦ red, ♠♣ black — `DeckManager.suits`
    /// carries each suit's color). Pure string matching: no rng is consumed
    /// here, so the seeded card roll alone decides everything. A win changes
    /// NOTHING — that is the whole joke — and a loss drains the Same shield.
    public func resolveTwoGame(suit: String, guess: String) -> Bool {
        let red = DeckManager.suits.first { $0.symbol == suit }?.red ?? false
        let won = guess == (red ? "red" : "black")
        if !won { sameCharge = false }
        return won
    }

    /// THE CON, collected. The Two takes every coin OR one ★ Joker — and
    /// gives NOTHING back; that is the entire outcome. Returns what left.
    public func resolveMammaLie(givingCoins: Bool) -> (coinsTaken: Int, jokerTaken: Bool) {
        if givingCoins {
            let taken = coins
            coins = 0
            return (taken, false)
        }
        if let joker = getRunDeck().first(where: { $0.joker }) {
            _ = removeDeckCard(joker.id)
            return (0, true)
        }
        return (0, false)
    }

    func cardName(_ c: CardSpec) -> String {
        if c.joker { return "★ Joker" }
        if c.blank { return "∅ Purge" }
        let label = DeckManager.ranks.first { $0.value == c.currentRank }?.label ?? "\(c.currentRank)"
        return "\(label)\(c.suit)"
    }
}
