import Foundation

/// MID-DEAL PERSISTENCE (anti-savescum) — the exact-resume snapshot.
///
/// `snapshot()` captures EVERYTHING a deal is: the remaining deck in order,
/// every pile's cards, every live card's full state (rank, suit, stickers,
/// counters — jokers included), the whole RunState, the Same charge, the
/// status, and the RNG's position. `restoreSnapshot(_:)` reproduces it all,
/// so a relaunched deal CONTINUES — same draws coming, same charges, same
/// tallies — instead of re-rolling.
///
/// PERFORMANCE: `snapshot()` is main-thread cheap by design — it builds a
/// plain JSONValue tree (integers and short strings; a 52-card deal is a few
/// KB) and does NO encoding and NO I/O. The flow encodes + writes it on a
/// background queue with latest-wins coalescing (see GameFlowController).
extension GameEngine {

    static let snapshotSchema = 1

    // MARK: - Capture

    public func snapshot() -> [String: JSONValue] {
        func card(_ c: LiveCard) -> JSONValue {
            var d: [String: JSONValue] = [
                "id": .number(Double(c.id)),
                "v": .number(Double(c.value)),
                "s": .string(c.suit),
            ]
            if c.joker { d["j"] = .bool(true) }
            if c.blank { d["b"] = .bool(true) }
            if !c.stickers.isEmpty { d["stk"] = .array(c.stickers.map { .string($0.type) }) }
            if c.compoundHits != 0 { d["ch"] = .number(Double(c.compoundHits)) }
            if c.snowball != 0 { d["sn"] = .number(Double(c.snowball)) }
            return .object(d)
        }
        func intArr(_ a: [Int]?) -> JSONValue { a.map { .array($0.map { .number(Double($0)) }) } ?? .null }
        func boolArr(_ a: [Bool]?) -> JSONValue { a.map { .array($0.map { .bool($0) }) } ?? .null }
        func strArr(_ a: [String?]?) -> JSONValue {
            a.map { .array($0.map { $0.map { .string($0) } ?? .null }) } ?? .null
        }

        var out: [String: JSONValue] = [
            "schema": .number(Double(Self.snapshotSchema)),
            "status": .string(status),
            "sameCharge": .bool(sameCharge),
            "rng": .number(Double(rng.state)),
            "deck": .array(deck.snapshotCards().map(card)),
            "drawn": .number(Double(deck.drawn())),
            "piles": .array(board.piles.map { p in
                .object(["cards": .array(p.cards.map(card)),
                         "dead": .bool(p.dead),
                         "sizeBonus": .number(Double(p.sizeBonus))])
            }),
        ]
        let r: RunState = run
        var rd: [String: JSONValue] = [
            "phase": .string(r.phase),
            "seed": .number(Double(r.seed)),
            "correct": .number(Double(r.correctGuesses)),
            "total": .number(Double(r.totalGuesses)),
            "dealDraws": .number(Double(r.dealDraws)),
            "cardsDrawn": .number(Double(r.cardsDrawn)),
            "started": .bool(r.started),
            "stickerWindow": .bool(r.stickerWindow),
            "cols": intArr(r.cols),
            "pileColumns": intArr(r.pileColumns),
            "pillars": strArr(r.pillars),
            "bases": strArr(r.bases),
            "basesUsed": boolArr(r.basesUsed),
            "suitBountyHits": intArr(r.suitBountyHits),
            "eightTributesUsed": intArr(r.eightTributesUsed),
            "sameTributesUsed": intArr(r.sameTributesUsed),
            "denseBuryUsed": intArr(r.denseBuryUsed),
            "reviveUsed": boolArr(r.reviveUsed),
            "colStreak": intArr(r.colStreak),
            "secondWindUsed": boolArr(r.secondWindUsed),
            "gamblerFlips": r.gamblerFlips.map { flips in
                .object(flips.reduce(into: [:]) { $0["\($1.key)"] = .bool($1.value) })
            } ?? .null,
            // v6.76: the shop-rolled climb locks handed in at deal creation
            // (item id → {"r"/"s"}) and each Daily Suit column's rolled suit.
            "shopRolls": .object(r.shopRolls.reduce(into: [:]) { out, kv in
                var d: [String: JSONValue] = [:]
                if let rank = kv.value.rank { d["r"] = .number(Double(rank)) }
                if let suit = kv.value.suit { d["s"] = .string(suit) }
                out[kv.key] = .object(d)
            }),
            "dailySuits": r.dailySuits.map { suits in
                .object(suits.reduce(into: [:]) { $0["\($1.key)"] = .string($1.value) })
            } ?? .null,
            "kamikazeRevealLeft": .number(Double(r.kamikazeRevealLeft)),
            "bonusCoins": .number(r.bonusCoins),
            "bonusEvents": .array(r.bonusEvents.pairs.map {
                .object(["k": .string($0.label), "v": .number($0.amount)])
            }),
            "revealNextActive": .bool(r.revealNextActive),
            "tellPiles": .array(r.tellPiles.sorted().map { .number(Double($0)) }),
            "whisperPiles": .array(r.whisperPiles.sorted().map { .number(Double($0)) }),
            "tellDrawsLeft": .number(Double(r.tellDrawsLeft)),
            "sightDrawsLeft": .number(Double(r.sightDrawsLeft)),
            "lastLandedPile": r.lastLandedPile.map { .number(Double($0)) } ?? .null,
            "compoundUpdates": .object(r.compoundUpdates.reduce(into: [:]) { $0["\($1.key)"] = .number(Double($1.value)) }),
            "snowballUpdates": .object(r.snowballUpdates.reduce(into: [:]) { $0["\($1.key)"] = .number(Double($1.value)) }),
            "stickerPeels": .object(r.stickerPeels.reduce(into: [:]) { $0["\($1.key)"] = .number(Double($1.value)) }),
            "pendingTributes": .array(r.pendingTributes.map {
                .object(["index": .number(Double($0.index)), "count": .number(Double($0.count)),
                         "cost": .number($0.cost), "label": .string($0.label), "type": .string($0.type)])
            }),
            "pendingActions": .array(r.pendingActions.map {
                .object(["kind": .string($0.kind), "index": .number(Double($0.index)),
                         "target": $0.target.map { .number(Double($0)) } ?? .null])
            }),
        ]
        if let result = r.result { rd["result"] = .string(result) }
        if let br = r.baseRandom {
            rd["baseRandom"] = .object(["value": .number(Double(br.value)),
                                        "suit": br.suit.map { .string($0) } ?? .null])
        }
        if let pr = r.pendingRipple {
            rd["pendingRipple"] = .object(["piles": .array(pr.piles.map { .number(Double($0)) }),
                                           "col": pr.col.map { .number(Double($0)) } ?? .null])
        }
        // v6.55 consent pendings: a kill with a choice still open must resume
        // INTO the prompt. The Second Wind killing card lives ONLY here while
        // parked (not in the deck, not on a pile), so it rides the blob as a
        // full card record; the pile's top is still the guess's `current`.
        if let sw = r.pendingSecondWind {
            rd["pendingSecondWind"] = .object([
                "index": .number(Double(sw.index)), "col": .number(Double(sw.col)),
                "guess": .string(sw.guess.rawValue),
                "recycleCount": .number(Double(sw.recycleCount)),
                "killing": card(sw.killingCard),
            ])
        }
        if let ps = r.pendingPowerShuffle {
            rd["pendingPowerShuffle"] = .number(Double(ps))
        }
        out["run"] = .object(rd)
        return out
    }

    // MARK: - Exact resume

    /// Rebuild the deal from a snapshot. The engine must have been created
    /// with the SAME RunConfig (cols / samePower / variants / flags) — those
    /// are re-derived from the restored campaign, exactly as a fresh boot
    /// derives them. Returns false (engine untouched) on a bad blob.
    @discardableResult
    public func restoreSnapshot(_ blob: [String: JSONValue]) -> Bool {
        guard Int(blob["schema"]?.asNumber ?? 0) == Self.snapshotSchema,
              let statusStr = blob["status"]?.asString,
              let rngState = blob["rng"]?.asNumber,
              let deckArr = blob["deck"]?.asArray,
              let pilesArr = blob["piles"]?.asArray,
              let rd = blob["run"]?.asObject,
              let seed = rd["seed"]?.asNumber
        else { return false }

        func card(_ v: JSONValue) -> LiveCard? {
            guard let d = v.asObject, let id = d["id"]?.asNumber,
                  let val = d["v"]?.asNumber, let suit = d["s"]?.asString else { return nil }
            // Rebuild through the SAME projection a fresh deal uses (toCard),
            // so sticker-derived flags (tieSafe / wild / guards…) can never
            // drift from the sticker list; the live counters ride on after.
            var spec: CardSpec
            if d["j"]?.asBool == true {
                spec = CardSpec.joker(id: Int(id))
            } else if d["b"]?.asBool == true {
                spec = CardSpec.blank(id: Int(id))
            } else {
                spec = CardSpec(id: Int(id), suit: suit,
                                originalRank: Int(val), currentRank: Int(val))
                spec.stickers = (d["stk"]?.asArray ?? []).compactMap {
                    $0.asString.map { StickerRecord(type: $0) }
                }
            }
            let live = DeckManager.toCard(spec, data: data)
            live.compoundHits = Int(d["ch"]?.asNumber ?? 0)
            live.snowball = Int(d["sn"]?.asNumber ?? 0)
            return live
        }

        let deckCards = deckArr.compactMap(card)
        guard deckCards.count == deckArr.count else { return false }
        var pileCards: [[LiveCard]] = []
        var pileDead: [Bool] = []
        var pileBonus: [Int] = []
        for pv in pilesArr {
            guard let pd = pv.asObject, let cs = pd["cards"]?.asArray else { return false }
            let cards = cs.compactMap(card)
            guard cards.count == cs.count else { return false }
            pileCards.append(cards)
            pileDead.append(pd["dead"]?.asBool ?? false)
            pileBonus.append(Int(pd["sizeBonus"]?.asNumber ?? 0))
        }
        guard pileCards.count == board.piles.count else { return false }

        // Everything validated — mutate.
        deck.restoreSnapshot(cards: deckCards, drawn: Int(blob["drawn"]?.asNumber ?? 0))
        for (i, p) in board.piles.enumerated() {
            p.cards = pileCards[i]
            p.dead = pileDead[i]
            p.sizeBonus = pileBonus[i]
        }
        status = statusStr
        sameCharge = blob["sameCharge"]?.asBool ?? false
        rng.state = UInt32(rngState)

        func ints(_ v: JSONValue?) -> [Int]? { v?.asArray?.compactMap { $0.asNumber.map(Int.init) } }
        func bools(_ v: JSONValue?) -> [Bool]? { v?.asArray?.compactMap(\.asBool) }
        func optStrings(_ v: JSONValue?) -> [String?]? { v?.asArray?.map { $0.asString } }
        func intDict(_ v: JSONValue?) -> [Int: Int] {
            (v?.asObject ?? [:]).reduce(into: [:]) { out, kv in
                if let k = Int(kv.key), let n = kv.value.asNumber { out[k] = Int(n) }
            }
        }
        /// column → flip-won for Gambler memos; nil when the blob says null
        /// (column-agnostic run), like the `ints`/`bools` helpers.
        func boolDict(_ v: JSONValue?) -> [Int: Bool]? {
            guard let o = v?.asObject else { return nil }
            return o.reduce(into: [:]) { out, kv in
                if let k = Int(kv.key), let b = kv.value.asBool { out[k] = b }
            }
        }

        let r: RunState = run
        r.phase = rd["phase"]?.asString ?? "active"
        r.seed = UInt32(seed)
        r.result = rd["result"]?.asString
        r.correctGuesses = Int(rd["correct"]?.asNumber ?? 0)
        r.totalGuesses = Int(rd["total"]?.asNumber ?? 0)
        r.dealDraws = Int(rd["dealDraws"]?.asNumber ?? 0)
        r.cardsDrawn = Int(rd["cardsDrawn"]?.asNumber ?? 0)
        r.started = rd["started"]?.asBool ?? true
        r.stickerWindow = rd["stickerWindow"]?.asBool ?? false
        r.cols = ints(rd["cols"])
        r.pileColumns = ints(rd["pileColumns"])
        r.pillars = optStrings(rd["pillars"])
        r.bases = optStrings(rd["bases"])
        r.basesUsed = bools(rd["basesUsed"])
        r.suitBountyHits = ints(rd["suitBountyHits"])
        r.eightTributesUsed = ints(rd["eightTributesUsed"])
        r.sameTributesUsed = ints(rd["sameTributesUsed"])
        r.denseBuryUsed = ints(rd["denseBuryUsed"])
        r.reviveUsed = bools(rd["reviveUsed"])
        r.colStreak = ints(rd["colStreak"])
        r.secondWindUsed = bools(rd["secondWindUsed"])
        r.gamblerFlips = boolDict(rd["gamblerFlips"])
        // v6.76: absent in older blobs — keep what RunConfig handed in at deal
        // creation rather than wiping to empty (the dailySuits guard below
        // follows the same rule).
        if let sr = rd["shopRolls"]?.asObject {
            r.shopRolls = sr.reduce(into: [:]) { out, kv in
                guard let d = kv.value.asObject else { return }
                out[kv.key] = ShopRoll(rank: d["r"]?.asNumber.map(Int.init), suit: d["s"]?.asString)
            }
        }
        if let ds = rd["dailySuits"]?.asObject {
            r.dailySuits = ds.reduce(into: [:]) { out, kv in
                if let k = Int(kv.key), let s = kv.value.asString { out[k] = s }
            }
        }
        r.kamikazeRevealLeft = Int(rd["kamikazeRevealLeft"]?.asNumber ?? 0)
        r.bonusCoins = rd["bonusCoins"]?.asNumber ?? 0
        r.bonusEvents = OrderedTally()
        for e in rd["bonusEvents"]?.asArray ?? [] {
            if let d = e.asObject, let k = d["k"]?.asString, let v = d["v"]?.asNumber {
                r.bonusEvents.add(k, v)
            }
        }
        r.revealNextActive = rd["revealNextActive"]?.asBool ?? false
        r.tellPiles = Set(ints(rd["tellPiles"]) ?? [])
        r.whisperPiles = Set(ints(rd["whisperPiles"]) ?? [])
        r.tellDrawsLeft = Int(rd["tellDrawsLeft"]?.asNumber ?? 0)
        r.sightDrawsLeft = Int(rd["sightDrawsLeft"]?.asNumber ?? 0)
        r.lastLandedPile = rd["lastLandedPile"]?.asNumber.map { Int($0) }
        r.compoundUpdates = intDict(rd["compoundUpdates"])
        r.snowballUpdates = intDict(rd["snowballUpdates"])
        r.stickerPeels = intDict(rd["stickerPeels"])
        r.pendingTributes = (rd["pendingTributes"]?.asArray ?? []).compactMap { v in
            guard let d = v.asObject, let i = d["index"]?.asNumber, let c = d["count"]?.asNumber,
                  let cost = d["cost"]?.asNumber, let l = d["label"]?.asString,
                  let t = d["type"]?.asString else { return nil }
            return TributeOffer(index: Int(i), count: Int(c), cost: cost, label: l, type: t)
        }
        r.pendingActions = (rd["pendingActions"]?.asArray ?? []).compactMap { v in
            guard let d = v.asObject, let k = d["kind"]?.asString,
                  let i = d["index"]?.asNumber else { return nil }
            return PendingAction(kind: k, index: Int(i),
                                 target: d["target"]?.asNumber.map(Int.init))
        }
        if let br = rd["baseRandom"]?.asObject, let v = br["value"]?.asNumber {
            r.baseRandom = (value: Int(v), suit: br["suit"]?.asString)
        }
        if let pr = rd["pendingRipple"]?.asObject, let ps = pr["piles"]?.asArray {
            r.pendingRipple = (piles: ps.compactMap { $0.asNumber.map(Int.init) },
                               col: pr["col"]?.asNumber.map(Int.init))
        }
        if let sw = rd["pendingSecondWind"]?.asObject, let i = sw["index"]?.asNumber,
           let kc = sw["killing"].flatMap({ card($0) }) {
            r.pendingSecondWind = PendingSecondWind(
                index: Int(i), col: Int(sw["col"]?.asNumber ?? 0),
                guess: Guess(rawValue: sw["guess"]?.asString ?? "") ?? .higher,
                killingCard: kc,
                recycleCount: Int(sw["recycleCount"]?.asNumber ?? 0))
        }
        if let ps = rd["pendingPowerShuffle"]?.asNumber {
            r.pendingPowerShuffle = Int(ps)
        }
        return true
    }
}
