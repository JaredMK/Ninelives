import Foundation

// BASES — an artifact class bound to the BOTTOM of a column. Unlike a Pillar's
// ongoing passive effect, a Base is an ACTIVE once-per-deal power: it arms at
// the start of each deal, the player ACTIVATES it once, and it is then SPENT
// until the next deal re-arms it.
extension GameEngine {

    /// The Base bound to column `col` (or nil). Reads the locked run binding.
    func baseForColumn(_ col: Int?) -> ItemDef? {
        guard let col, let bases = run?.bases, col >= 0, col < bases.count, let id = bases[col] else { return nil }
        return baseTypes.get(id)
    }

    /// Whether the Base on `col` is CHARGED (placed, and not yet spent this
    /// deal). Independent of any per-Base precondition.
    public func baseCharged(_ col: Int?) -> Bool {
        guard let col, let run, let bases = run.bases, let used = run.basesUsed,
              col >= 0, col < bases.count else { return false }
        return bases[col] != nil && used[col] == false
    }

    /// Per-Base precondition: can this Base's effect do anything meaningful right
    /// now? Pure check — no state change.
    public func baseCanActivate(_ col: Int?) -> Bool {
        guard let base = baseForColumn(col) else { return false }
        // Bases are column-scoped: every precondition is evaluated over this
        // column's piles only.
        let alive = colAlivePiles(col)
        func topIsSuit(_ i: Int, _ s: String) -> Bool { matchesSuit(board.top(i), s) }
        // Total ♥ cards (top + buried) across this column's alive piles.
        let colHearts = alive.reduce(0) { $0 + board.piles[$1].cards.filter { matchesSuit($0, "♥") }.count }
        switch base.effect {
        // Kamikaze needs >1 pile alive board-wide AND a ♠-top alive pile in its
        // OWN column (it auto-picks a random ♠ target there).
        case "kamikaze":          return board.aliveCount() > 1 && alive.contains { topIsSuit($0, "♠") }
        case "spadePeek":         return alive.contains { topIsSuit($0, "♠") }
        case "shuffleColumn":     return !alive.isEmpty
        case "reviveBase":        return !colDeadPiles(col).isEmpty
        case "randomSticker":     return alive.contains { !wildStickerPoolFor(board.top($0)).isEmpty }
        case "evenOut":           return alive.count >= 2
        case "setValue":          return !alive.isEmpty
        case "setSuit":           return !alive.isEmpty
        case "stickerHarvest":    return !alive.isEmpty
        case "refreshBases":      return !refreshableBaseColumns(col).isEmpty
        case "suitDig":           return !deck.isEmpty && alive.contains { topIsSuit($0, base.suit ?? "") }
        case "demolish":          return run.pillars?.contains { $0 != nil } ?? false
        case "heartDemolish":     return alive.contains { topIsSuit($0, "♥") }
        case "tax":               return colHearts > 0
        // Recharge Cell: only when a charge can actually be banked.
        case "rechargeSameShield": return !sameCharge
        // Power Surge: needs a Same-Power equipped AND an alive pile to fire on.
        case "activateSamePower":  return run.samePower != nil && !alive.isEmpty
        default:                   return false
        }
    }

    /// Whether column `col`'s Base can be activated right now.
    public func baseAvailable(_ col: Int?) -> Bool {
        guard let col, status == "playing", let run, run.started else { return false }
        guard baseCharged(col) else { return false }
        return baseCanActivate(col)
    }

    /// Columns whose (spent, non-Refresh) Base a Refresh-Bases on `col` may
    /// re-arm. (Refresh Bases never re-arms another Refresh Bases — no loop.)
    func refreshableBaseColumns(_ col: Int?) -> [Int] {
        guard let col, let run, let bases = run.bases, let used = run.basesUsed else { return [] }
        var out: [Int] = []
        for c in 0..<bases.count where c != col {
            if let b = baseTypes.get(bases[c]), b.effect != "refreshBases", used[c] == true { out.append(c) }
        }
        return out
    }

    /// Activate the Base on column `col`. `targetIndex` is the chosen pile (or,
    /// for Demolish, the chosen COLUMN) for target Bases; ignored by the
    /// whole-column Bases. Spends the charge and fires the effect.
    @discardableResult
    public func baseActivate(col: Int, targetIndex: Int? = nil) -> BaseResult? {
        guard baseAvailable(col), let base = baseForColumn(col) else { return nil }
        // Validate the target for target Bases (column-scoped).
        let needsTarget = base.target == "pile" || base.target == "pillar"
        if needsTarget {
            guard let targetIndex else { return nil }
            if base.target == "pillar" {
                // Demolish: targetIndex is the COLUMN of the Pillar to destroy.
                guard let pillars = run.pillars, targetIndex >= 0, targetIndex < pillars.count,
                      pillars[targetIndex] != nil else { return nil }
            } else {
                guard board.isActive(targetIndex), run.pileColumns?[targetIndex] == col else { return nil }
            }
        }

        var res = BaseResult(col: col, effect: base.effect ?? "", label: base.label)
        let coinsBefore = run.bonusCoins
        logBegin(base.label)

        switch base.effect {
        case "kamikaze":
            // Auto-pick a RANDOM alive ♠-topped pile in the BASE's own column.
            let pk = base.int("peekCount", 3)
            guard let kill = pick(colAlivePiles(col).filter { matchesSuit(board.top($0), "♠") }) else { break }
            board.kill(kill)
            emit(.pileKilled(index: kill))
            run.tellPiles.remove(kill)                 // dead pile drops any Tell hint
            run.kamikazeRevealLeft = pk                // peek the next `pk` draws
            // Last Rites on the SACRIFICED pile's column (any death counts).
            let kc = run.pileColumns?[kill]
            if let kd = resolvePillarDef(kc), kd.effect == "lastRites" { peekPillar(kc, kd) }
            res.index = kill
            res.cards = deck.peek(pk)                  // read-only snapshot
            logLine("killed pile \(kill + 1), peeking the next \(pk) upcoming cards")

        case "rechargeSameShield":
            sameCharge = true
            res.sameCharge = true
            logLine("banked a Same Charge")

        case "activateSamePower":
            // Fire the equipped Same-Power on a RANDOM alive pile in this column.
            // Banks no charge.
            let hub = pick(colAlivePiles(col))
            if let hub { fireSamePower(hub); res.hub = hub; res.index = hub }
            logLine("fired the equipped Same-Power on pile \(hub != nil ? String(hub! + 1) : "—")")

        case "spadePeek":
            // Peek the next X upcoming cards, X = alive ♠-topped piles here.
            let n = colAlivePiles(col).filter { matchesSuit(board.top($0), "♠") }.count
            run.kamikazeRevealLeft = max(run.kamikazeRevealLeft, n)
            res.peekCount = n
            res.cards = deck.peek(n)
            logLine("peeking the next \(n) upcoming card\(n == 1 ? "" : "s") (\(n) ♠ pile\(n == 1 ? "" : "s"))")

        case "shuffleColumn":
            // Shuffle every alive pile in the column — FREE. Composition only.
            let alive = colAlivePiles(col)
            for i in alive { board.shufflePile(i, rng) }
            res.shuffled = alive.count
            logLine("shuffled \(alive.count) piles")

        case "reviveBase":
            guard let target = pick(colDeadPiles(col)) else { break }
            board.revive(target)
            // On a wrong guess the killing card is pushed onto the pile and then
            // it dies, so the FATAL card is the dead pile's TOP. Keep it as the
            // revived pile's card; send only the cards BENEATH it back.
            var all = board.drain(target)              // [bottom … top]; top = killer
            let killer = all.popLast()
            for c in all { deck.returnCard(c) }        // the buried cards → deck (hidden)
            if let killer { board.push(target, killer) }
            if let topNow = board.top(target), topNow.revealNext { run.revealNextActive = true }
            res.index = target
            res.returnedCount = all.count
            logLine("revived pile \(target + 1) — kept the killing card as its pile card; \(all.count) buried cards shuffled into the deck")

        case "randomSticker":
            // Targets a RANDOM ELIGIBLE pile card in the column (no player choice).
            guard let target = pick(colAlivePiles(col).filter { !wildStickerPoolFor(board.top($0)).isEmpty }),
                  let top = board.top(target) else { break }
            let pool = wildStickerPoolFor(top)
            guard let typeId = pick(pool.map(\.id)) else { break }
            projectStickerOntoCard(top, typeId)
            res.index = target
            res.stickerApplied = (pileIndex: target, cardId: top.id, typeId: typeId)
            logLine("applied \(stickerTypes.get(typeId)?.label ?? typeId) to the pile card of pile \(target + 1)")

        case "evenOut":
            // SUIT-AGNOSTIC: hand a buried card from the largest pile to the
            // smallest until every pair is within 1. Composition only.
            var moves = 0
            for _ in 0..<500 {
                let alive = colAlivePiles(col)
                if alive.count < 2 { break }
                var big = alive[0], small = alive[0]
                for i in alive {
                    if board.pileSize(i) > board.pileSize(big) { big = i }
                    if board.pileSize(i) < board.pileSize(small) { small = i }
                }
                if big == small || board.pileSize(big) - board.pileSize(small) <= 1 { break }
                if board.piles[big].cards.count <= 1 { break }   // no buried card to give
                if !board.moveBottomCard(big, small) { break }
                moves += 1
            }
            res.moves = moves
            logLine("evened out the column: \(moves) buried cards moved (hidden)")

        case "setValue":
            // Copy the RANK of the column's BOTTOM alive pile onto every other
            // alive pile's top card. Durable for the rest of the run.
            let own = colPiles(col)
            let source = own.reversed().first { board.isActive($0) }
            let src = source.flatMap { board.top($0) }
            var applied: [(cardId: Int, value: Int)] = []
            if let src {
                let rk = DeckManager.ranks.first { $0.value == src.value }
                for i in colAlivePiles(col) {
                    guard let top = board.top(i), top.value != src.value else { continue }
                    top.value = src.value
                    if let rk { top.label = rk.label }
                    applied.append((cardId: top.id, value: src.value))
                }
            }
            res.valueApplied = applied
            res.sourceValue = src?.value
            logLine("set \(applied.count) pile card\(applied.count == 1 ? "" : "s") to rank \(src?.label ?? "?")")

        case "setSuit":
            // Copy the SUIT of the column's BOTTOM alive pile onto every other
            // alive pile's top card. Durable for the run.
            let own = colPiles(col)
            let source = own.reversed().first { board.isActive($0) }
            let src = source.flatMap { board.top($0) }
            var applied: [(cardId: Int, suit: String)] = []
            if let src {
                let sdef = DeckManager.suits.first { $0.symbol == src.suit }
                for i in colAlivePiles(col) {
                    guard let top = board.top(i), top.suit != src.suit else { continue }
                    top.suit = src.suit
                    if let sdef { top.red = sdef.red }
                    applied.append((cardId: top.id, suit: src.suit))
                }
            }
            res.suitApplied = applied
            res.sourceSuit = src?.suit
            logLine("set \(applied.count) pile card\(applied.count == 1 ? "" : "s") to suit \(src?.suit ?? "?")")

        case "stickerHarvest":
            guard let ti = targetIndex, let top = board.top(ti) else { break }
            let n = top.stickers.count
            let buried = n > 0 ? buryTribute(ti, n * base.int("buryPerSticker", 2), base.label) : 0
            // Peel every counted sticker + its projected flags off the live card.
            top.stickers = []
            top.tieSafe = false; top.wildSuit = false; top.revealNext = false
            top.suitGuards = []
            res.index = ti; res.harvested = n; res.buried = buried
            logLine("buried \(buried) cards and peeled \(n) sticker\(n == 1 ? "" : "s") off the pile card of pile \(ti + 1)")

        case "refreshBases":
            let cs = refreshableBaseColumns(col)
            for c in cs { run.basesUsed![c] = false }   // re-arm (never a Refresh Bases)
            res.refreshed = cs
            logLine("re-armed \(cs.count) spent Base\(cs.count == 1 ? "" : "s")")

        case "suitDig":
            // Bury digCount under EACH alive pile in this column whose pile card
            // matches the Base's suit.
            var piles = 0, buried = 0
            for i in colAlivePiles(col) {
                if deck.isEmpty { break }
                guard matchesSuit(board.top(i), base.suit ?? "") else { continue }
                let n = buryTribute(i, base.int("digCount", 0) != 0 ? base.int("digCount", 0) : 1, base.label)
                if n > 0 { piles += 1; buried += n }
            }
            res.piles = piles; res.buried = buried
            logLine("buried \(buried) cards under \(piles) \(base.suit ?? "") pile\(piles == 1 ? "" : "s")")

        case "demolish":
            // targetIndex is the column whose Pillar is destroyed. The rubble
            // reveals the road ahead: peek the next `peekCount` cards.
            guard let tc = targetIndex else { break }
            let destroyedId = run.pillars![tc]
            let pk = base.int("peekCount", 2)
            run.pillars![tc] = nil                     // stop its effect immediately
            run.kamikazeRevealLeft = max(run.kamikazeRevealLeft, pk)
            res.demolishedCol = tc
            res.demolishedPillar = destroyedId
            res.peekCount = pk
            res.cards = deck.peek(pk)
            logLine("destroyed the Pillar on column \(tc + 1), peeking the next \(pk) upcoming cards")

        case "heartDemolish":
            // Destroy every alive ♥-topped pile in this column; +coinPerPile each.
            let targets = colAlivePiles(col).filter { matchesSuit(board.top($0), "♥") }
            for i in targets {
                board.kill(i)
                emit(.pileKilled(index: i))
                run.tellPiles.remove(i)
                let dc = run.pileColumns?[i]
                if let dd = resolvePillarDef(dc), dd.effect == "lastRites" { peekPillar(dc, dd) }
            }
            let perPile = base.num("coinPerPile", 7)
            if !targets.isEmpty { addBonus(base.label, perPile * Double(targets.count)) }
            res.destroyedPiles = targets
            res.gained = perPile * Double(targets.count)
            logLine("destroyed \(targets.count) ♥ pile\(targets.count == 1 ? "" : "s") → +\(jsNum(perPile * Double(targets.count))) coins")

        case "tax":
            // Heart Tax: +coinPerCard for each ♥ card (top + buried) across this
            // column's ALIVE piles. Dead piles don't count.
            var n = 0
            for i in colAlivePiles(col) {
                n += board.piles[i].cards.filter { matchesSuit($0, "♥") }.count
            }
            let taxGain = Double(n) * base.num("coinPerCard", 1)
            if n > 0 { addBonus(base.label, taxGain) }
            res.gained = taxGain
            logLine("taxed \(n) ♥ card\(n == 1 ? "" : "s") in the column → +\(jsNum(taxGain)) coins")

        default:
            currentEntry = nil
            return nil
        }

        run.basesUsed![col] = true                     // spend the charge for this deal
        res.coins = run.bonusCoins - coinsBefore
        // Telemetry: one record per Base activation, impacts read from `res`.
        var imp: [String: Double] = [:]
        if res.coins > 0 { imp["coins"] = res.coins }
        if res.coins < 0 { imp["coinsLost"] = -res.coins }
        let bd = (res.buried ?? 0) + (res.harvested ?? 0)
        if bd != 0 { imp["buried"] = Double(bd) }
        if let s = res.shuffled, s != 0 { imp["shuffled"] = Double(s) }
        if let m = res.moves, m != 0 { imp["moved"] = Double(m) }
        if base.effect == "kamikaze", res.index != nil {
            imp["killed"] = 1
            if let c = res.cards { imp["peeks"] = Double(c.count) }
        }
        if base.effect == "spadePeek", let p = res.peekCount, p != 0 { imp["peeks"] = Double(p) }
        if base.effect == "reviveBase", res.index != nil { imp["revived"] = 1 }
        if base.effect == "demolish", res.demolishedPillar != nil { imp["destroyed"] = 1 }
        if base.effect == "heartDemolish", let d = res.destroyedPiles, !d.isEmpty { imp["destroyed"] = Double(d.count) }
        if res.stickerApplied != nil { imp["applied"] = 1 }
        if let sa = res.suitApplied, !sa.isEmpty { imp["recolored"] = Double(sa.count) }
        recT("base", base.id, base.label, imp)

        currentEntry = nil
        emit(.baseFired(res))
        evaluateEnd()
        return res
    }

    // MARK: - Same-Powers

    /// SAME-POWER TARGETS (v5.66): every Same-Power acts BOARD-WIDE — all alive
    /// piles (or all dead piles for a revive), not just the ones synapse-linked
    /// to the called pile.
    func powerPiles(_ which: String) -> [Int] {
        (0..<board.size).filter { which == "dead" ? !board.isActive($0) : board.isActive($0) }
    }

    /// A correct Same triggers the player's ONE equipped Same-Power — the only
    /// artifact a Same triggers. `hub` is the pile the Same was called on. No-op
    /// when nothing is equipped.
    func fireSamePower(_ hub: Int) {
        guard let run, let id = run.samePower, let def = samePowerTypes.get(id) else { return }
        var result = SamePowerResult(power: def.id, label: def.label, hub: hub, effect: def.effect ?? "")
        switch def.effect {
        case "linkBury":
            // Bury `value` card(s) under EVERY alive pile.
            let targets = powerPiles("alive")
            var buried = 0
            let n = def.int("value", 0) != 0 ? def.int("value", 0) : 1
            for j in targets { buried += buryTribute(j, n, def.label) }
            result.targets = targets
            result.amount = buried

        case "linkRevive":
            // Revive ONE dead pile ANYWHERE on the board, keeping its size. Pick
            // the largest dead pile (most cards saved); ties → lowest index.
            let dead = powerPiles("dead")
            var pickIdx: Int? = nil
            for j in dead where pickIdx == nil || board.pileSize(j) > board.pileSize(pickIdx!) { pickIdx = j }
            if let p = pickIdx {
                board.revive(p)
                result.targets = [p]
                result.amount = board.pileSize(p)
                logLine("\(def.label): revived pile \(p + 1) (\(board.pileSize(p)) cards kept)")
            }

        case "linkCoins":
            // +value coins for EVERY alive pile on the board.
            let targets = powerPiles("alive")
            let amt = def.num("value", 1) * Double(targets.count)
            if amt > 0 {
                addBonus(def.label, amt)
                recT("samePower", def.id, def.label, ["coins": amt])
            }
            result.targets = targets
            result.amount = Int(amt)

        case "linkShuffle":
            // Shuffle EVERY alive pile (composition only; hidden order).
            let targets = powerPiles("alive")
            for j in targets { board.shufflePile(j, rng) }
            result.targets = targets
            result.amount = targets.count

        case "samePeek":
            // Peek the next upcoming card (deck-reveal treatment, like Scout).
            run.revealNextActive = true
            result.amount = 1

        case "linkHeavy":
            // +value pile size to EVERY alive pile, plus hubValue on top for the
            // CALLED pile itself (both persistent this deal).
            let targets = powerPiles("alive")
            let per = def.int("value", 0) != 0 ? def.int("value", 0) : 5
            for j in targets { board.addSizeBonus(j, per) }
            let hubBonus = def.int("hubValue", 5)
            board.addSizeBonus(hub, hubBonus)
            result.targets = targets
            result.amount = per * targets.count + hubBonus

        default: break
        }
        logLine("\(def.label) (Same-Power): \(result.targets.count) pile(s)")
        emit(.samePower(result))
    }
}
