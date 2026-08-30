import Foundation

// The campaign checkpoint. A plain, JSON-safe snapshot of ALL campaign-level
// state — the only thing that persists between deals. Storage-agnostic: the
// caller hands it to whatever SaveStore is wired. `schema` guards against
// restoring an incompatible older save.
//
// The map is NOT serialized: it is deterministic from (runSeed, stageEntryDecks,
// genV), so restore regenerates it. `genV` is the map-generator version this run
// was BUILT with — regenerating a v1/v2 save through the v3 path would swap the
// map out mid-run, so restore replays the saved version.
extension CampaignState {
    public static let saveSchema = 2

    public func serialize() -> [String: JSONValue] {
        func nums(_ a: [Int]) -> JSONValue { .array(a.map { .number(Double($0)) }) }
        func strs(_ a: [String?]) -> JSONValue { .array(a.map { $0.map(JSONValue.string) ?? .null }) }
        func counts(_ d: [String: Int]) -> JSONValue { .object(d.mapValues { .number(Double($0)) }) }

        var out: [String: JSONValue] = [
            "schema": .number(Double(Self.saveSchema)),
            "deckId": .string(deckId),
            "difficultyTier": .string(difficultyTier),
            "phaseIndex": .number(Double(phaseIndex)),
            "runSeed": .number(Double(runSeed)),
            "nodePos": nodePos.map { .number(Double($0)) } ?? .null,
            "genV": .number(Double(savedGenVersion)),
            "exhibition": .bool(exhibition),
            "actionCounter": .number(Double(actionCounter)),
            "stageEntryDecks": .array(stageEntryDecks.map { $0.map { .number(Double($0)) } ?? .null }),
            "ownedIds": nums(ownedIds),
            "clearedNodes": nums(clearedNodes),
            "revealedNodes": nums(revealedNodes),
            "mystMigrated": .bool(mystMigrated),
            "nodeCards": .object(Dictionary(uniqueKeysWithValues:
                nodeCards.map { (String($0.key), JSONValue.number(Double($0.value))) })),
            "packCards": .object(Dictionary(uniqueKeysWithValues:
                packCards.map { (String($0.key), nums($0.value)) })),
            "currentStage": .number(Double(currentStage)),
            "currentRunIndex": .number(Double(currentRunIndex)),
            "totalCorrectGuesses": .number(Double(totalCorrectGuesses)),
            "runsCompleted": .number(Double(runsCompleted)),
            "totalCardsFlipped": .number(Double(totalCardsFlipped)),
            "totalCoinsEarned": .number(Double(totalCoinsEarned)),
            "allGuessesCorrect": .number(Double(allGuessesCorrect)),
            "allGuessesTotal": .number(Double(allGuessesTotal)),
            "coins": .number(Double(coins)),
            "playedCounted": .bool(playedCounted),
            "runWonBanked": .bool(runWonBanked),
            "cardsFlippedBanked": .number(Double(cardsFlippedBanked)),
            "runScore": .number(Double(runScore)),
            "scoreBanked": .number(Double(scoreBanked)),
            "endless": .bool(endless),
            "sameCharge": .bool(sameCharge),
            "removalsBought": .number(Double(removalsBought)),
            "pillarRankVariants": .object(pillarRankVariants.reduce(into: [:]) { $0[$1.key] = .number(Double($1.value)) }),
            "purgeDiscount": .number(Double(purgeDiscount)),
            "purgeStepBonus": .number(Double(purgeStepBonus)),
            // v6.76 — SHARED with the web save (exact names + shapes):
            // `purgePriceCut` is the Coupon's accumulated cut (a bare number);
            // `shopRolls` is a FLAT map — the first axis rides the bare id,
            // the second "id#2", and a value is a bare rank NUMBER or suit
            // STRING, never a wrapper.
            "purgePriceCut": .number(Double(purgePriceCut)),
            "shopRolls": .object(shopRolls.reduce(into: [:]) { out, kv in
                let def = data.pillarTypes.get(kv.key) ?? data.baseTypes.get(kv.key)
                // Axis kind tells where each field lands; the catalog's first
                // axis is the item's `shopRoll`, its second `shopRoll2`.
                func put(_ key: String, _ axis: String?) {
                    switch axis {
                    case "rank": if let r = kv.value.rank { out[key] = .number(Double(r)) }
                    case "suit": if let s = kv.value.suit { out[key] = .string(s) }
                    default: break
                    }
                }
                if def != nil {
                    put(kv.key, def?.shopRoll)
                    put(kv.key + "#2", def?.shopRoll2)
                } else {
                    // Def left the catalog: keep the values rather than drop
                    // them (rank at the bare id, suit at "#2" — no catalog
                    // item carries two same-kind axes).
                    if let r = kv.value.rank { out[kv.key] = .number(Double(r)) }
                    if let s = kv.value.suit { out[kv.key + "#2"] = .string(s) }
                }
            }),
            "jokerDebt": .number(Double(jokerDebt)),
            "freeShopPending": .bool(freeShopPending),
            "jokerThirstPending": .bool(jokerThirstPending),
            "jokerThirstCoins": .number(Double(jokerThirstCoins)),
            "freeRerollPending": .bool(freeRerollPending),
            "freeRedealPending": .bool(freeRedealPending),
            "storePriceModPending": storePriceModPending.map { .string($0) } ?? .null,
            "storePriceModActive": storePriceModActive.map { .string($0) } ?? .null,
            "stickerInventory": counts(stickerInventory),
            "pillarInventory": counts(pillarInventory),
            "baseInventory": counts(baseInventory),
            "columnPillars": strs(columnPillars),
            "columnBases": strs(columnBases),
            "samePowerInventory": counts(samePowerInventory),
            "equippedSamePower": equippedSamePower.map(JSONValue.string) ?? .null,
            "baseDeck": .array(baseDeck.map(Self.encodeCard)),
            "packTray": .array(packTray.map(Self.encodeCard)),
            "nextCardId": .number(Double(nextCardId)),
        ]
        out["storeOffer"] = storeOffer.map(Self.encodeOffer) ?? .null
        return out
    }

    static func encodeCard(_ c: CardSpec) -> JSONValue {
        var o: [String: JSONValue] = [
            "id": .number(Double(c.id)),
            "suit": .string(c.suit),
            "originalRank": .number(Double(c.originalRank)),
            "currentRank": .number(Double(c.currentRank)),
            "compoundHits": .number(Double(c.compoundHits)),
            "stickers": .array(c.stickers.map { r in
                var o: [String: JSONValue] = ["type": .string(r.type)]
                if let f = r.convertedFrom { o["convertedFrom"] = .string(f) }
                return .object(o)
            }),
            "modifications": .array(c.modifications.map {
                .object(["op": .string($0.op), "from": $0.from, "to": $0.to])
            }),
        ]
        if c.snowball != 0 { o["snowball"] = .number(Double(c.snowball)) }
        if c.joker { o["joker"] = .bool(true) }
        if c.blank { o["blank"] = .bool(true) }
        return .object(o)
    }

    static func decodeCard(_ v: JSONValue) -> CardSpec? {
        guard let o = v.asObject, let id = o["id"]?.asNumber else { return nil }
        var c = CardSpec(id: Int(id),
                         suit: o["suit"]?.asString ?? "♦",
                         originalRank: Int(o["originalRank"]?.asNumber ?? 2),
                         currentRank: Int(o["currentRank"]?.asNumber ?? 2))
        c.compoundHits = Int(o["compoundHits"]?.asNumber ?? 0)
        c.snowball = Int(o["snowball"]?.asNumber ?? 0)
        c.joker = o["joker"]?.asBool ?? false
        c.blank = o["blank"]?.asBool ?? false
        c.stickers = (o["stickers"]?.asArray ?? []).compactMap { rec in
            rec["type"]?.asString.map {
                StickerRecord(type: $0, convertedFrom: rec["convertedFrom"]?.asString)
            }
        }
        c.modifications = (o["modifications"]?.asArray ?? []).compactMap { m in
            guard let op = m["op"]?.asString else { return nil }
            return CardModification(op: op, from: m["from"] ?? .null, to: m["to"] ?? .null)
        }
        return c
    }

    static func encodeOffer(_ o: StoreOffer) -> JSONValue {
        var d: [String: JSONValue] = [
            "rerollCost": .number(o.rerollCost),
            "freeSlot": o.freeSlot.map { .number(Double($0)) } ?? .null,
            "slots": .array(o.slots.map { s in
                guard let s else { return .null }
                var sd: [String: JSONValue] = ["kind": .string(s.kind), "id": .string(s.id)]
                if s.mystery { sd["mystery"] = .bool(true) }
                if let card = s.card { sd["card"] = encodeCard(card) }
                // v6.76 (only when set, like slot `mystery`): the shop-rolled
                // values ride the slot as the web's `shopRolled`/`shopRolled2`
                // — a bare rank NUMBER or suit STRING. The catalog's one
                // dual-axis item (Transmute) is rank-then-suit; everything
                // else carries a single axis.
                if let r = s.rollRank, let s2 = s.rollSuit {
                    sd["shopRolled"] = .number(Double(r))
                    sd["shopRolled2"] = .string(s2)
                } else if let r = s.rollRank {
                    sd["shopRolled"] = .number(Double(r))
                } else if let s2 = s.rollSuit {
                    sd["shopRolled"] = .string(s2)
                }
                return .object(sd)
            }),
        ]
        // v6.52 (only when set, like slot `mystery`): the NODE this offer was
        // rolled for — the store screen rerolls when it opens for a different
        // node, so a leftover shelf (and the per-visit price mod scoped by
        // openStore) can never follow the player into another shop.
        if let n = o.offerNode { d["offerNode"] = .number(Double(n)) }
        return .object(d)
    }

    static func decodeOffer(_ v: JSONValue?) -> StoreOffer? {
        guard let o = v?.asObject, let slots = o["slots"]?.asArray else { return nil }
        return StoreOffer(
            slots: slots.map { s in
                guard let d = s.asObject, let kind = d["kind"]?.asString, let id = d["id"]?.asString else { return nil }
                // `mystery` is absent in pre-v6.51 saves — a legacy CONCRETE
                // same-power slot decodes as concrete and stays buyable.
                // `shopRolled`/`shopRolled2` are absent in pre-v6.76 saves —
                // a legacy shopRoll slot re-rolls (and locks) at purchase.
                // A numeric shopRolled is a rank, a string one a suit.
                let rolled = d["shopRolled"], rolled2 = d["shopRolled2"]
                return StoreSlot(kind: kind, id: id, mystery: d["mystery"]?.asBool ?? false,
                                 card: d["card"].flatMap(decodeCard),
                                 rollRank: rolled?.asNumber.map(Int.init) ?? rolled2?.asNumber.map(Int.init),
                                 rollSuit: rolled?.asString ?? rolled2?.asString)
            },
            rerollCost: o["rerollCost"]?.asNumber ?? 0,
            freeSlot: o["freeSlot"]?.asNumber.map(Int.init),
            // Absent in pre-v6.52 saves: an unknown owner node keeps legacy
            // behaviour (the offer survives until openStore replaces it).
            offerNode: o["offerNode"]?.asNumber.map(Int.init))
    }

    /// Restore from a `serialize()` snapshot. Returns true on success; false
    /// (leaving state untouched) if the snapshot is missing/incompatible —
    /// callers then fall back to a fresh campaign.
    @discardableResult
    public func restore(_ s: [String: JSONValue]?) -> Bool {
        guard let s, Int(s["schema"]?.asNumber ?? 0) == Self.saveSchema else { return false }
        // The universe GROWS with pack mints and SHRINKS with removals
        // (v6.49: a removed card leaves baseDeck so it can never be drafted
        // again) — so a fixed ≥52 floor now rejects honest saves. The real
        // corruption tripwire is below: every OWNED id must exist in the
        // decoded universe.
        guard let deckArr = s["baseDeck"]?.asArray, !deckArr.isEmpty else { return false }

        deckId = data.meta.deckRules[s["deckId"]?.asString ?? ""] != nil ? s["deckId"]!.asString! : "pink"
        let tier = s["difficultyTier"]?.asString ?? ""
        difficultyTier = DifficultyData.tierIds.contains(tier) ? tier : "regular"
        map.setDifficultyTier(difficultyTier)

        baseDeck = deckArr.compactMap(Self.decodeCard)
        nextCardId = Int(s["nextCardId"]?.asNumber ?? 52)
        // Never hand out an id already in use, whatever the save claimed.
        let maxBaseId: Int = baseDeck.map(\.id).max() ?? 51
        let trayIds: [Int] = (s["packTray"]?.asArray ?? []).compactMap { $0["id"]?.asInt }
        let maxTrayId: Int = trayIds.max() ?? 51
        let maxId = max(maxBaseId, maxTrayId)
        if nextCardId <= maxId { nextCardId = maxId + 1 }

        phaseIndex = Int(s["phaseIndex"]?.asNumber ?? 0)
        runSeed = UInt32(truncatingIfNeeded: Int(s["runSeed"]?.asNumber ?? 0))
        savedGenVersion = Int(s["genV"]?.asNumber ?? 1)   // pre-mapgen1 saves default to 1
        exhibition = s["exhibition"]?.asBool ?? false
        actionCounter = Int(s["actionCounter"]?.asNumber ?? 0)
        stageEntryDecks = (s["stageEntryDecks"]?.asArray ?? []).map { $0.isNull ? nil : $0.asNumber.map(Int.init) }
        if stageEntryDecks.isEmpty { stageEntryDecks = [map.config.startDeckSize, nil, nil] }
        ownedIds = s["ownedIds"]?.asArray?.compactMap { $0.asNumber.map(Int.init) } ?? []
        // Integrity: a run deck referencing a card the universe doesn't hold
        // is a corrupt save — exactly what the old ≥52 floor tried to catch.
        let universe = Set(baseDeck.map(\.id))
        guard !ownedIds.isEmpty, ownedIds.allSatisfy({ universe.contains($0) }) else { return false }
        clearedNodes = s["clearedNodes"]?.asArray?.compactMap { $0.asNumber.map(Int.init) } ?? []
        revealedNodes = s["revealedNodes"]?.asArray?.compactMap { $0.asNumber.map(Int.init) } ?? []
        mystMigrated = s["mystMigrated"]?.asBool ?? false
        nodeCards = [:]
        for (k, v) in s["nodeCards"]?.asObject ?? [:] {
            if let key = Int(k), let n = v.asNumber { nodeCards[key] = Int(n) }
        }
        packCards = [:]
        for (k, v) in s["packCards"]?.asObject ?? [:] {
            if let key = Int(k) { packCards[key] = v.asArray?.compactMap { $0.asNumber.map(Int.init) } ?? [] }
        }
        currentStage = Int(s["currentStage"]?.asNumber ?? 1)
        currentRunIndex = Int(s["currentRunIndex"]?.asNumber ?? 1)
        totalCorrectGuesses = Int(s["totalCorrectGuesses"]?.asNumber ?? 0)
        runsCompleted = Int(s["runsCompleted"]?.asNumber ?? 0)
        totalCardsFlipped = Int(s["totalCardsFlipped"]?.asNumber ?? 0)
        totalCoinsEarned = Int(s["totalCoinsEarned"]?.asNumber ?? 0)
        allGuessesCorrect = Int(s["allGuessesCorrect"]?.asNumber ?? 0)
        allGuessesTotal = Int(s["allGuessesTotal"]?.asNumber ?? 0)
        coins = Int(s["coins"]?.asNumber ?? 0)
        playedCounted = s["playedCounted"]?.asBool ?? false
        runWonBanked = s["runWonBanked"]?.asBool ?? false
        cardsFlippedBanked = Int(s["cardsFlippedBanked"]?.asNumber ?? 0)
        runScore = Int(s["runScore"]?.asNumber ?? 0)
        scoreBanked = Int(s["scoreBanked"]?.asNumber ?? 0)
        endless = s["endless"]?.asBool ?? false
        sameCharge = s["sameCharge"]?.asBool ?? false
        // Absent in pre-v5.82 saves — an old climb simply restarts the ladder.
        removalsBought = Int(s["removalsBought"]?.asNumber ?? 0)
        pillarRankVariants = (s["pillarRankVariants"]?.asObject ?? [:])
            .compactMapValues { $0.asNumber.map(Int.init) }
        purgeDiscount = Int(s["purgeDiscount"]?.asNumber ?? 0)
        purgeStepBonus = Int(s["purgeStepBonus"]?.asNumber ?? 0)
        // v6.76, SHARED keys (absent in pre-v6.76 saves → the defaults the web
        // restore uses: 0 cut, empty map; they roll at the next shelf visit).
        purgePriceCut = max(0, Int(s["purgePriceCut"]?.asNumber ?? 0))
        // The web's FLAT shape: id / "id#2" → bare rank number or suit string.
        // Numbers fold to the rank axis, strings to the suit axis — lossless
        // for the catalog (no item rolls two same-kind axes).
        var rolls: [String: ShopRoll] = [:]
        for (k, v) in s["shopRolls"]?.asObject ?? [:] {
            let id = k.hasSuffix("#2") ? String(k.dropLast(2)) : k
            var roll = rolls[id] ?? ShopRoll()
            if let n = v.asNumber { roll.rank = Int(n) }
            else if let str = v.asString { roll.suit = str }
            rolls[id] = roll
        }
        shopRolls = rolls
        // Absent in pre-Old-Joker saves — an old climb simply owes nothing.
        jokerDebt = Int(s["jokerDebt"]?.asNumber ?? 0)
        freeShopPending = s["freeShopPending"]?.asBool ?? false
        jokerThirstPending = s["jokerThirstPending"]?.asBool ?? false
        jokerThirstCoins = Int(s["jokerThirstCoins"]?.asNumber ?? 0)
        freeRerollPending = s["freeRerollPending"]?.asBool ?? false
        freeRedealPending = s["freeRedealPending"]?.asBool ?? false
        storePriceModPending = s["storePriceModPending"]?.asString
        storePriceModActive = s["storePriceModActive"]?.asString

        func counts(_ v: JSONValue?) -> [String: Int] {
            var out: [String: Int] = [:]
            for (k, n) in v?.asObject ?? [:] { if let d = n.asNumber, d > 0 { out[k] = Int(d) } }
            return out
        }
        stickerInventory = counts(s["stickerInventory"])
        pillarInventory = counts(s["pillarInventory"])
        baseInventory = counts(s["baseInventory"])
        samePowerInventory = counts(s["samePowerInventory"])
        func slotArray(_ v: JSONValue?, _ n: Int) -> [String?] {
            var out = (v?.asArray ?? []).map { $0.asString }
            while out.count < n { out.append(nil) }
            return Array(out.prefix(n))
        }
        columnPillars = slotArray(s["columnPillars"], CampaignLayout.columnSlots)
        columnBases = slotArray(s["columnBases"], CampaignLayout.columnSlots)
        equippedSamePower = s["equippedSamePower"]?.asString
        // RETIRED-ITEM STRIP (v6.78, the Fibonacci removal): an old save may
        // still equip or hold an item id the registry no longer knows. Drop
        // it quietly — the alternative is a raw id on a plaque and a nil def
        // everywhere the column fires. Registry-driven, so any future
        // retirement rides the same path.
        stickerInventory = stickerInventory.filter { data.stickerTypes.get($0.key) != nil }
        pillarInventory = pillarInventory.filter { data.pillarTypes.get($0.key) != nil }
        baseInventory = baseInventory.filter { data.baseTypes.get($0.key) != nil }
        samePowerInventory = samePowerInventory.filter { data.samePowerTypes.get($0.key) != nil }
        columnPillars = columnPillars.map { $0.flatMap { data.pillarTypes.get($0) != nil ? $0 : nil } }
        columnBases = columnBases.map { $0.flatMap { data.baseTypes.get($0) != nil ? $0 : nil } }
        if let sp = equippedSamePower, data.samePowerTypes.get(sp) == nil { equippedSamePower = nil }
        storeOffer = Self.decodeOffer(s["storeOffer"])
        packTray = (s["packTray"]?.asArray ?? []).compactMap(Self.decodeCard)

        // Regenerate the map from the SAVED generator version, then re-lock the
        // pickup/pack faces (nodeCards/packCards were restored above, so the
        // locks are re-asserted, never re-rolled) and re-clear the guaranteed
        // Joker's mystery flag (the flag itself re-rolls on regeneration).
        runMap = map.generateRun(seed: runSeed, entryDecks: stageEntryDecks,
                                 opts: RunMap.GenOptions(genVersion: savedGenVersion,
                                                         postBossJokerStages: fixedJokerStages() ?? []))
        let pos = s["nodePos"]
        nodePos = (pos == nil || pos!.isNull) ? nil : pos!.asNumber.map(Int.init)
        lockAllPickupCards()
        ensureGuaranteedJoker()
        return true
    }
}
