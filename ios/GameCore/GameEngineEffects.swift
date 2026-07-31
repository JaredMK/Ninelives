import Foundation

// Every sticker / Pillar effect, keyed by the items.js `behavior` / `effect`
// field and reading its tunables from the item def — never a hardcoded number.
extension GameEngine {

    // MARK: - Live Pillar extras (on a correct landing)

    /// Prime / Royal Court (coins), Queen's Eye (peek), Same Spark (spray
    /// stickers in-column), Shuffler, Diamond Distribution. `pillar` is the
    /// Ditto-resolved def for the pile's column. Fibonacci is NOT here — it pays
    /// on every correct DRAW into the column (see `guess`).
    func maybeLivePillarExtras(_ index: Int, _ pillar: ItemDef?, _ drawn: LiveCard,
                               _ g: Guess, _ isTie: Bool, _ col: Int?) {
        guard let pillar, let col else { return }
        let v = drawn.value
        let isDiamond = matchesSuit(drawn, "♦")
        switch pillar.effect {
        case "prime" where v == 2 || v == 3 || v == 5 || v == 7:
            payPillar(col, "prime", pillar.label, pillar.num("value", 1) == 0 ? 1 : pillar.value)

        case "shuffler" where isDiamond:
            // A ♦ landed → shuffle every OTHER alive pile in this column.
            var n = 0
            for i in colAlivePiles(col) where i != index { board.shufflePile(i, rng); n += 1 }
            if n > 0 {
                firePillar(col, "shuffler", pillar.label, 0)
                logLine("\(pillar.label): shuffled \(n) other pile\(n == 1 ? "" : "s") in the column")
                recT("pillar", pillar.id, pillar.label, ["shuffled": Double(n)])
            }

        case "queensEye" where v >= 11 && v <= 13 && matchesSuit(drawn, "♠"):
            run.revealNextActive = true
            firePillar(col, "queensEye", pillar.label, 0)
            recT("pillar", pillar.id, pillar.label, ["peeks": 1])

        case "diamondDistribution" where isDiamond:
            // Even out the column's alive pile sizes. The net pile→pile flows
            // ride the fired signal so the UI can fly the moving cards.
            let (moved, moves) = redistributeColumn(col)
            if moved > 0 {
                firePillar(col, "diamondDistribution", pillar.label, 0, moves: moves)
                logLine("\(pillar.label): redistributed \(moved) buried card\(moved == 1 ? "" : "s") to even the column")
                recT("pillar", pillar.id, pillar.label, ["moved": Double(moved)])
            }

        default: break
        }
    }

    /// Diamond Distribution: even out the alive piles' sizes in `col`. Each pile
    /// keeps its own TOP card; the BURIED cards are pooled and dealt back as
    /// evenly as possible (a composition shift — no identities/order surfaced).
    func redistributeColumn(_ col: Int) -> (moved: Int, moves: [(from: Int, to: Int)]) {
        let idxs = colAlivePiles(col)
        if idxs.count < 2 { return (0, []) }
        var beforeBuried: [Int: Int] = [:]
        for i in idxs { beforeBuried[i] = max(0, board.piles[i].cards.count - 1) }
        var tops: [Int: LiveCard] = [:]
        var pool: [LiveCard] = []
        for i in idxs {
            if board.piles[i].cards.isEmpty { continue }
            tops[i] = board.piles[i].cards.removeLast()            // hold each pile's top aside
            while !board.piles[i].cards.isEmpty {                  // buried cards → shared pool
                pool.append(board.piles[i].cards.removeLast())
            }
        }
        let per = pool.count / idxs.count
        var extra = pool.count - per * idxs.count
        var k = 0, moved = 0
        for i in idxs {
            let want = per + (extra > 0 ? 1 : 0)
            if extra > 0 { extra -= 1 }
            var buried: [LiveCard] = []
            var j = 0
            while j < want && k < pool.count { buried.append(pool[k]); k += 1; j += 1 }
            board.piles[i].cards = buried                          // buried at the bottom …
            if let t = tops[i] { board.piles[i].cards.append(t) }   // … its own top back on top
            moved += buried.count
        }
        // NET FLOWS for the travel animation — presentation data only.
        var donors: [Int] = [], receivers: [Int] = []
        for i in idxs {
            let delta = (beforeBuried[i] ?? 0) - max(0, board.piles[i].cards.count - 1)
            if delta > 0 { donors.append(contentsOf: Array(repeating: i, count: delta)) }
            if delta < 0 { receivers.append(contentsOf: Array(repeating: i, count: -delta)) }
        }
        var moves: [(from: Int, to: Int)] = []
        for n in 0..<min(donors.count, receivers.count) { moves.append((donors[n], receivers[n])) }
        return (moved, moves)
    }

    // MARK: - Composition Tribute Pillars

    /// 8 Bury / Dense Bury: on a qualifying surviving resolution, bury deck-bottom
    /// card(s) under this pile, hidden. Uncapped — bounded only by the draw deck.
    func maybeTribute(_ index: Int, _ pillar: ItemDef?, _ drawn: LiveCard, _ isTie: Bool) {
        guard let pillar, let pc = run.pileColumns else { return }
        let col = pc[index]
        let isClub = matchesSuit(drawn, "♣")
        let nStk = drawn.stickers.count
        if pillar.effect == "clubTribute" && isClub && nStk == 0 {
            let nb = buryTribute(index, pillar.int("digCount", 1), pillar.label)
            if nb > 0 {
                firePillar(col, "clubTribute", pillar.label, 0)
                recT("pillar", pillar.id, pillar.label, ["buried": Double(nb)])
            }
        } else if pillar.effect == "denseBury" && isClub && nStk >= pillar.int("minStickers", 2) {
            let nb = buryTribute(index, pillar.int("digCount", 1), pillar.label)
            if nb > 0 {
                if run.denseBuryUsed != nil { run.denseBuryUsed![col] += 1 }
                firePillar(col, "denseBury", pillar.label, 0)
                recT("pillar", pillar.id, pillar.label, ["buried": Double(nb)])
            }
        }
    }

    // MARK: - Sticker tributes carried by the DRAWN card

    /// Bury 1 / Bury 2 bury the card(s) IMMEDIATELY, no prompt; a Leech
    /// (tributeCoin) pays a flat coin toll instead. When a sticker carries a
    /// coinCost, deduct it on the same landing — can't afford → the effect still
    /// happens and the tally goes negative. Every toll surfaces through the same
    /// negative "sticker-coins" cue.
    func maybeStickerTribute(_ index: Int, _ drawn: LiveCard) {
        let stickers = drawn.stickers
        if stickers.isEmpty { return }
        for s in stickers {
            guard let t = stickerTypes.get(s.type) else { continue }
            if t.behavior == "tributeCoin" {
                let toll = t.num("value", 1)
                if toll != 0 {
                    addBonus(t.label, -toll)
                    emit(.stickerCoins(index: index, label: t.label, amount: -toll))
                    recT("sticker", t.id, t.label, ["coins": -toll])
                }
                continue
            }
            guard t.behavior == "tribute" else { continue }
            let count = t.int("tributeCount", 0) != 0 ? t.int("tributeCount", 0) : 1
            let nb = buryTribute(index, count, t.label)
            let cost = t.num("coinCost", 0)
            if cost != 0 {
                addBonus(t.label, -cost)
                emit(.stickerCoins(index: index, label: t.label, amount: -cost))
            }
            if nb > 0 || cost != 0 {
                recT("sticker", t.id, t.label, ["buried": Double(nb), "coins": cost != 0 ? -cost : 0])
            }
        }
    }

    /// Duplicate: when the carrying card SURVIVES a correct Same — as either the
    /// drawn card or the pile card it tied — copy it (stickers and all) into the
    /// card inventory.
    func maybeDuplicate(_ index: Int, _ current: LiveCard, _ drawn: LiveCard, _ g: Guess) {
        guard g == .same else { return }
        for card in [drawn, current] where card.stickers.contains(where: { $0.type == "duplicate" }) {
            logLine("Duplicate: \(cardName(card)) survived a Same — copied to inventory")
            emit(.cardDuplicated(cardId: card.id, index: index))
            recT("sticker", "duplicate", "Duplicate", ["copies": 1])
        }
    }

    /// Immediate sticker payouts on the DRAWN card landing on a SURVIVING pile:
    /// Bonus Coin (gainCoin) and Collector (+value per OTHER sticker on the card,
    /// per Collector instance).
    func maybeLandingBonus(_ index: Int, _ drawn: LiveCard) {
        let stickers = drawn.stickers
        if stickers.isEmpty { return }
        func pay(_ label: String, _ amount: Double) {
            if amount == 0 { return }
            addBonus(label, amount)
            emit(.stickerCoins(index: index, label: label, amount: amount))
        }
        for s in stickers {
            guard let t = stickerTypes.get(s.type) else { continue }
            if t.behavior == "gainCoin" {
                pay("Bonus Coin", t.value)
                recT("sticker", t.id, t.label, ["coins": t.value])
            } else if t.behavior == "collector" {
                // Hub pays per instance: +1 for each OTHER Imprint on this card.
                let unit = t.num("value", 1) == 0 ? 1 : t.value
                let amt = unit * Double(max(0, stickers.count - 1))
                pay("Collector", amt)
                recT("sticker", t.id, t.label, ["coins": amt])
            }
        }
    }

    /// Expansion stickers carried by the DRAWN card. Order inside matters: coin
    /// payouts FIRST (Deep Pockets reads the deck before this landing's own
    /// burials), then burials, then projections, then the Scouts' peek.
    func maybeExpansionStickers(_ index: Int, _ current: LiveCard, _ drawn: LiveCard, _ col: Int?) {
        let stickers = drawn.stickers
        // The SNOB family reads the PILE TOP's stickers, so bail only when
        // NEITHER side carries a sticker (the common fast path).
        let curStickers = current.stickers
        if stickers.isEmpty && curStickers.isEmpty { return }
        func n(_ type: String) -> Int { stickers.filter { $0.type == type }.count }
        func payCoins(_ label: String, _ amount: Double, always: Bool = false) {
            if amount != 0 { addBonus(label, amount) }
            if amount != 0 || always { emit(.stickerCoins(index: index, label: label, amount: amount)) }
        }

        // --- coins ---
        let dp = n("deepPockets")
        if dp > 0 {
            let per = Int(Double(deck.remaining()) / (stickerTypes.get("deepPockets")?.num("per", 10) ?? 10))
            payCoins("Deep Pockets", Double(dp * per))
            recT("sticker", "deepPockets", "Deep Pockets", ["coins": Double(dp * per)])
        }
        let lc = n("looseChange")
        let lcMax = stickerTypes.get("looseChange")?.int("max", 3) ?? 3
        var lcSum = 0
        for _ in 0..<lc {
            let a = rng.index(lcMax + 1)                       // random 0–max
            payCoins("Loose Change", Double(a), always: true)
            lcSum += a
        }
        if lc > 0 { recT("sticker", "looseChange", "Loose Change", ["coins": Double(lcSum)]) }

        // --- the SNOB family: the snob sticker sits on the PILE TOP and fires
        // when a MATCHING-SUIT card LANDS ON it. ---
        func cn(_ type: String) -> Int { curStickers.filter { $0.type == type }.count }
        func landsOn(_ suit: String) -> Bool { matchesSuit(drawn, suit) }

        if cn("suitSnob") > 0 && landsOn("♠") {
            run.revealNextActive = true                        // peek the next upcoming card
            recT("sticker", "suitSnob", "Spade Snob", ["peeks": 1])
        }
        let hsn = cn("heartSnob")
        if hsn > 0 && landsOn("♥") {
            let amt = Double(hsn) * (stickerTypes.get("heartSnob")?.num("value", 4) ?? 4)
            payCoins("Heart Snob", amt)
            recT("sticker", "heartSnob", "Heart Snob", ["coins": amt])
        }
        if cn("diamondSnob") > 0 && landsOn("♦") {
            var sh = 0
            for i in 0..<board.size where board.isActive(i) { board.shufflePile(i, rng); sh += 1 }
            if sh > 0 {
                firePillar(col, "shuffler", "Diamond Snob", 0)
                logLine("Diamond Snob: shuffled all \(sh) piles")
                recT("sticker", "diamondSnob", "Diamond Snob", ["shuffled": Double(sh)])
            }
        }
        let csn = cn("clubSnob")
        if csn > 0 && landsOn("♣") {
            let nb = buryTribute(index, csn * (stickerTypes.get("clubSnob")?.int("digCount", 1) ?? 1), "Club Snob")
            if nb > 0 { recT("sticker", "clubSnob", "Club Snob", ["buried": Double(nb)]) }
        }

        // --- the suit-SYNERGY family: fires on EVERY landing, scaled by the
        // number of OTHER alive piles topped by its suit. ---
        func otherTops(_ suit: String) -> Int {
            var k = 0
            for i in 0..<board.size {
                if i == index || !board.isActive(i) { continue }
                if matchesSuit(board.top(i), suit) { k += 1 }
            }
            return k
        }
        let hch = n("heartChoir")
        if hch > 0 {
            let unit = stickerTypes.get("heartChoir")?.num("value", 1) ?? 1
            let amt = Double(hch) * unit * Double(otherTops("♥"))
            if amt > 0 { payCoins("Heart Choir", amt); recT("sticker", "heartChoir", "Heart Choir", ["coins": amt]) }
        }
        if n("diamondRipple") > 0 {
            var sh = 0
            for i in 0..<board.size {
                if i == index || !board.isActive(i) { continue }
                if matchesSuit(board.top(i), "♦") { board.shufflePile(i, rng); sh += 1 }
            }
            if sh > 0 {
                firePillar(col, "shuffler", "Diamond Ripple", 0)
                logLine("Diamond Ripple: shuffled \(sh) ♦-topped pile\(sh == 1 ? "" : "s")")
                recT("sticker", "diamondRipple", "Diamond Ripple", ["shuffled": Double(sh)])
            }
        }
        // Club Roots — bury under EACH OTHER alive ♣-topped pile. The landing
        // pile is EXCLUDED even if its own top is now ♣.
        let crn = n("clubRoots")
        if crn > 0 {
            let per = crn * (stickerTypes.get("clubRoots")?.int("digCount", 1) ?? 1)
            var cr = 0
            for i in 0..<board.size {
                if i == index || !board.isActive(i) { continue }
                if matchesSuit(board.top(i), "♣") { cr += buryTribute(i, per, "Club Roots") }
            }
            if cr > 0 { recT("sticker", "clubRoots", "Club Roots", ["buried": Double(cr)]) }
        }
        // Spade Whispers — the next X draws each carry a Tell-style hint.
        let swn = n("spadeWhispers")
        if swn > 0 {
            let x = swn * otherTops("♠")
            if x > 0 {
                run.tellDrawsLeft += x
                recT("sticker", "spadeWhispers", "Spade Whispers", ["hints": Double(x)])
            }
        }

        // --- burials ---
        let qb = n("quickBury")
        var qbBuried = 0
        for _ in 0..<qb { qbBuried += buryTribute(index, 1, "Quick Bury") }
        if qb > 0 { recT("sticker", "quickBury", "Quick Bury", ["buried": Double(qbBuried)]) }
        if n("snowball") > 0 {
            // Per-card counter (duplicate Snowballs share it): bury X, then grow
            // X by `step`. Persisted like compoundHits.
            let x = drawn.snowball
            var sbBuried = 0
            if x > 0 { sbBuried = buryTribute(index, x, "Snowball Bury") }
            drawn.snowball = x + (stickerTypes.get("snowball")?.int("step", 1) ?? 1)
            run.snowballUpdates[drawn.id] = drawn.snowball
            recT("sticker", "snowball", "Snowball Bury", ["buried": Double(sbBuried)])
        }

        // --- Twin Spark: peek if ANOTHER alive pile's top shares this rank. ---
        if n("twinSpark") > 0 {
            let matchRank = drawn.value
            var twin = false
            for i in 0..<board.size {
                if i == index || !board.isActive(i) { continue }
                if let top = board.top(i), top.value == matchRank { twin = true; break }
            }
            if twin {
                run.revealNextActive = true
                firePillar(col, "twinSpark", "Twin Spark", 0)
                recT("sticker", "twinSpark", "Twin Spark", ["peeks": 1])
            }
        }

        // --- scouts: only peek while THIS column has no Pillar/Base. ---
        let emptyPillarSlot = (run.pillars != nil && col != nil) ? (run.pillars![col!] == nil) : false
        let emptyBaseSlot = (run.bases != nil && col != nil) ? (run.bases![col!] == nil) : false
        let psPeek = n("pillarScout") > 0 && emptyPillarSlot
        let bsPeek = n("baseScout") > 0 && emptyBaseSlot
        if psPeek || bsPeek {
            run.revealNextActive = true
            if psPeek { recT("sticker", "pillarScout", "Pillar Scout", ["peeks": 1]) }
            if bsPeek { recT("sticker", "baseScout", "Base Scout", ["peeks": 1]) }
        }

        // --- Same-charge / Same-power stickers ---
        if n("rechargeSameShield") > 0 {
            let was = sameCharge
            sameCharge = true
            if !was { logLine("Recharge Shield: banked a Same Charge") }
            recT("sticker", "rechargeSameShield", "Recharge Shield", ["saves": was ? 0 : 1])
            emit(.sameBanked(index: index, sameCharge: sameCharge))
        }
        // Tap Power: fire the equipped Same-Power on THIS pile, once per
        // instance. It banks NO charge, and fireSamePower is a no-op when
        // nothing is equipped (intended).
        let tp = n("activateSamePower")
        for _ in 0..<tp { fireSamePower(index) }
        if tp > 0 { recT("sticker", "activateSamePower", "Tap Power", ["copies": Double(tp)]) }
    }

    /// Post-landing sticker ACTIONS. Shuffle stays an OPTIONAL offer (queued and
    /// surfaced after any prompt drains). Donate is AUTOMATIC — it moves buried
    /// card(s) to the smallest eligible pile inline on the landing.
    func maybeStickerActions(_ index: Int, _ drawn: LiveCard) {
        let stickers = drawn.stickers
        if stickers.isEmpty { return }
        for s in stickers {
            if s.type == "shuffle" {
                // Only worth offering if the pile has more than one card.
                if board.piles[index].cards.count > 1 {
                    run.pendingActions.append(PendingAction(kind: "shuffle", index: index, target: nil))
                }
            } else if s.type == "donate" {
                // Donate immediately: only when this is NOT already the smallest
                // pile and a smaller alive pile exists to receive the donation.
                if let target = smallestAlivePileExcept(index),
                   board.isActive(index), board.isActive(target),
                   board.pileSize(index) > board.pileSize(target),
                   !board.piles[index].cards.isEmpty {
                    let dn = stickerTypes.get("donate")?.int("count", 1) ?? 1
                    var moved = 0
                    for _ in 0..<dn where board.moveBottomCard(index, target) { moved += 1 }
                    if moved > 0 {
                        logLine("Donate: moved \(moved) card\(moved == 1 ? "" : "s") from pile \(index + 1) to pile \(target + 1) (hidden)")
                        recT("sticker", "donate", "Donate", ["moved": Double(moved)])
                        emit(.actionResolved(kind: "donate", index: index, target: target, accepted: true))
                    }
                }
            }
        }
    }

    // MARK: - Revive Pillar

    /// One-shot per deal: when a pile in the Pillar's column has reached
    /// `trigger` cards, offer to revive a dead pile. If no pile is dead it is
    /// skipped WITHOUT consuming the charge.
    func maybeReviveTrigger(_ col: Int?) {
        guard let col, run.pillars != nil, let used = run.reviveUsed, !used[col] else { return }
        guard let pillar = resolvePillarDef(col), pillar.effect == "revive" else { return }
        let trigger = pillar.int("trigger", 10)
        var reached = false
        if let pc = run.pileColumns {
            for i in 0..<pc.count where pc[i] == col && board.isActive(i) && board.piles[i].cards.count >= trigger {
                reached = true; break
            }
        }
        if !reached { return }
        let dead = allDeadPiles()
        if dead.isEmpty { return }   // nothing to revive → stay ready (no consume)
        firePillar(col, "revive", pillar.label, 0)
        emit(.reviveOffer(col: col, dead: dead))
    }

    /// Perform a Revive: bring a chosen DEAD pile back with one fresh top card
    /// and consume the column's one-shot charge.
    @discardableResult
    public func reviveDeadPile(col: Int?, targetIndex: Int?) -> Bool {
        guard let col, let used = run?.reviveUsed, !used[col] else { return false }
        guard let targetIndex, !board.isActive(targetIndex) else { return false }
        board.revive(targetIndex)
        if !deck.isEmpty { board.push(targetIndex, deck.draw()) }   // a fresh top
        if let fresh = board.top(targetIndex), fresh.revealNext { run.revealNextActive = true }
        run.reviveUsed![col] = true
        logAction("Revive: pile \(targetIndex + 1) brought back with a fresh card")
        emit(.revived(col: col, index: targetIndex))
        let rdef = resolvePillarDef(col)
        recT("pillar", rdef?.id ?? "revive", rdef?.label ?? "Revive", ["revived": 1])
        evaluateEnd()
        return true
    }

    // MARK: - End-of-deal Pillar payout

    /// Itemized Pillar payout for the current board state (scoring Pillars only).
    /// A pure read over run.pillars + run.pileColumns + board. The UI feeds this
    /// straight into `Economy.breakdown` so coins stay one formula.
    public func computePillarPayout() -> PillarPayout {
        var lines: [PayoutLine] = []
        var bonus: Double = 0
        guard let run, let pillars = run.pillars, let pileColumns = run.pileColumns, let cols = run.cols else {
            return PillarPayout(bonus: 0, lines: [])
        }
        func colIdxs(_ c: Int) -> [Int] { (0..<pileColumns.count).filter { pileColumns[$0] == c } }
        func allAliveInCol(_ c: Int) -> Bool {
            let a = colIdxs(c); return !a.isEmpty && a.allSatisfy { board.isActive($0) }
        }
        let pillarsOnBoard = pillars.compactMap { $0 }.count

        for col in 0..<cols.count {
            guard let t = resolvePillarDef(col), t.kind == "scoring" else { continue }
            switch t.effect {
            case "columnAllAlive":
                // +value if EVERY pile in this column survived to run end.
                let idxs = colIdxs(col)
                if !idxs.isEmpty && idxs.allSatisfy({ board.isActive($0) }) {
                    bonus += t.value
                    lines.append(PayoutLine(label: t.label, detail: "Column \(col + 1) survived", amount: t.value, col: col))
                }

            case "allSuitTop":
                // +value if EVERY surviving pile in THIS column shows the
                // matching suit on top (and the column has ≥1 survivor).
                let alive = colIdxs(col).filter { board.isActive($0) }
                if !alive.isEmpty, let suit = t.suit, alive.allSatisfy({ matchesSuit(board.top($0), suit) }) {
                    bonus += t.value
                    lines.append(PayoutLine(label: t.label, detail: "all \(suit) on top", amount: t.value, col: col))
                }

            case "heartPiles":
                // Envy: +value per ALIVE pile IN THIS COLUMN whose TOP is a ♥.
                var n = 0
                for i in colIdxs(col) where board.isActive(i) && matchesSuit(board.top(i), "♥") { n += 1 }
                let amt = Double(n) * t.value
                if amt > 0 {
                    bonus += amt
                    lines.append(PayoutLine(label: t.label, detail: "\(n) ♥ top\(n == 1 ? "" : "s")", amount: amt, col: col))
                }

            case "greedy":
                // +value only if this column fully survived AND it's the SOLE
                // Pillar on the board (a second Pillar anywhere voids it).
                if pillarsOnBoard == 1 && allAliveInCol(col) {
                    bonus += t.value
                    lines.append(PayoutLine(label: t.label, detail: "sole Pillar, column survived", amount: t.value, col: col))
                }

            case "highestHeart":
                // The TOP card only of each ALIVE pile in this column. NUMBERED
                // hearts only: 2–10 pay face value, an Ace pays 1, royals pay 0.
                var best = 0
                for i in colIdxs(col) {
                    guard board.isActive(i), let top = board.top(i), matchesSuit(top, "♥") else { continue }
                    let coin = top.value == 14 ? 1 : (top.value >= 11 ? 0 : top.value)
                    if coin > best { best = coin }
                }
                if best > 0 {
                    bonus += Double(best)
                    lines.append(PayoutLine(label: t.label, detail: "highest ♥ = \(best)", amount: Double(best), col: col))
                }

            case "insurance":
                // +value if the WHOLE board has exactly one survivor and it's here.
                if board.aliveCount() == 1 && colIdxs(col).contains(where: { board.isActive($0) }) {
                    bonus += t.value
                    lines.append(PayoutLine(label: t.label, detail: "sole survivor in this column", amount: t.value, col: col))
                }

            case "excavator":
                // +value per BURIED card in this column's LARGEST alive ♥-topped pile.
                var best = 0
                for i in colIdxs(col) {
                    guard board.isActive(i), matchesSuit(board.top(i), "♥") else { continue }
                    best = max(best, board.piles[i].cards.count)
                }
                let n = max(0, best - 1)   // cards beneath the top of that pile
                if n > 0 {
                    let unit = t.num("value", 1) == 0 ? 1 : t.value
                    let amt = Double(n) * unit
                    bonus += amt
                    lines.append(PayoutLine(label: t.label, detail: "\(n) buried (largest ♥ pile)", amount: amt, col: col))
                }

            case "gambler":
                // 50/50: +value or nothing — but ONLY if this column has an alive
                // ♥-topped pile. Always emit a line so the outcome shows.
                let hasHeart = colIdxs(col).contains { board.isActive($0) && matchesSuit(board.top($0), "♥") }
                if !hasHeart {
                    lines.append(PayoutLine(label: t.label, detail: "no ♥ top in column — no flip",
                                            amount: 0, col: col, effect: "gambler"))
                } else {
                    let won = rng.next() < t.num("chance", 0.5)
                    let amt = won ? t.value : 0
                    bonus += amt
                    lines.append(PayoutLine(label: t.label,
                                            detail: won ? "won the flip (+\(jsNum(amt)))" : "lost the flip (+0)",
                                            amount: amt, col: col, effect: "gambler"))
                }

            default: break
            }
            // NOTE: suitBounty is NOT scored here — it's paid LIVE during play.
        }
        // Tag each payout line with its resolved Pillar id (telemetry reads this).
        for i in lines.indices where lines[i].id == nil {
            if let d = resolvePillarDef(lines[i].col) { lines[i].id = d.id }
        }
        return PillarPayout(bonus: bonus, lines: lines)
    }
}
