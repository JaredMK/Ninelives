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
        case "spadePeek":         return !alive.isEmpty && alive.allSatisfy { topIsSuit($0, "♠") }
        case "shuffleColumn":     return !alive.isEmpty
        case "reviveBase":        return !colDeadPiles(col).isEmpty
        case "randomSticker":     return alive.contains { !wildStickerPoolFor(board.top($0)).isEmpty }
        case "evenOut":           return alive.count >= 2
        case "setValue":          return !alive.isEmpty
        // SUIT SETTER (v6.52): green only when it can CHANGE something —
        // more than one alive pile AND at least two different printed suits
        // among their tops. One pile, or an already-uniform column, is amber.
        case "setSuit":
            let tops = alive.compactMap { board.top($0) }.filter { !$0.joker }
            return alive.count > 1 && Set(tops.map(\.suit)).count > 1
        // STICKER HARVEST (v6.57 batch): green only when there is actually
        // something to harvest — a stickered top card in ITS column. A bare
        // column is amber (charged, nothing to peel), spent stays red.
        case "stickerHarvest":
            return alive.contains { !(board.top($0)?.stickers.isEmpty ?? true) }
        case "refreshBases":      return !refreshableBaseColumns(col).isEmpty
        case "suitDig":           return !deck.isEmpty && alive.contains { topIsSuit($0, base.suit ?? "") }
        case "lonePeek":          return run.samePower == nil && !deck.isEmpty
        case "clubTell":          return !deck.isEmpty && alive.contains { topIsSuit($0, "♣") }
        case "lastResort":        return !runConfig.isBoss && !deck.isEmpty && !alive.isEmpty
        case "emptyPurse":        return !deck.isEmpty
        case "sameTell":          return !deck.isEmpty && !alive.isEmpty
        // ESCAPE HATCH: an ambush and nothing else. Outside one it is charged
        // but unusable — which is what its red light says.
        case "ambushWin":         return runConfig.isAmbush && status == "playing"
        case "demolish":
            // Own column ONLY (v6.51): charged but unavailable while THIS
            // column carries no Pillar — there is no target pick anymore.
            guard let col else { return false }
            return (run.pillars?[safe: col] ?? nil) != nil
        case "heartDemolish":     return alive.contains { topIsSuit($0, "♥") }
        case "tax":               return colHearts > 0
        // Recharge Cell: only when a charge can actually be banked.
        case "rechargeSameShield": return !sameCharge
        // Power Surge: needs a Same-Power equipped AND an alive pile to fire on.
        case "activateSamePower":  return run.samePower != nil && !alive.isEmpty
        // ── v6.76 archetype batch ─────────────────────────────────────────
        // PURGE COUPON: a store-side lever — always fireable, nothing in-deal.
        case "purgeDiscount":     return true
        // TRANSMUTE fires at PURCHASE, never in a deal (stays amber forever).
        case "transmute":         return false
        case "sacrifice":         return !alive.isEmpty
        // DEVIL'S DEAL: needs an alive pile to point at — an un-CURSABLE pick
        // re-picks seeded at fire time, so the gate is just an alive pile
        // (the web's `alive.length > 0`).
        case "devilsDeal":        return !alive.isEmpty
        case "cleanseColumn":     return alive.contains {
            board.top($0)?.stickers.contains(where: { stickerTypes.get($0.type)?.cursed == true }) ?? false
        }
        case "chorus":            return !alive.isEmpty
        case "diamondBoost":      return alive.contains { matchesSuit(board.top($0), "♦") }
        default:                   return false
        }
    }

    /// What column `col`'s Base would yield if it were fired RIGHT NOW — the
    /// web's `baseLiveCounter` (index.html), which drives the `.base-count-badge`
    /// chip on the plaque. nil for a Base with no countable "if activated now"
    /// figure. Pure — no state change.
    ///
    /// This is the read-only twin of the branches in `baseActivate`, reading the
    /// same registry knobs so a retune in items.js moves the badge and the real
    /// payout together.
    public func baseLiveCounter(_ col: Int?) -> Int? {
        guard let base = baseForColumn(col) else { return nil }
        let alive = colAlivePiles(col)
        func topCount(_ s: String) -> Int { alive.filter { matchesSuit(board.top($0), s) }.count }
        switch base.effect {
        case "tax":
            // Coins: +coinPerCard per ♥ card (top AND buried) in alive piles.
            let hearts = alive.reduce(0) {
                $0 + board.piles[$1].cards.filter { matchesSuit($0, "♥") }.count
            }
            return Int(Double(hearts) * base.num("coinPerCard", 1))
        case "heartDemolish":
            // Coins: +coinPerPile per alive ♥-topped pile in the column.
            return Int(base.num("coinPerPile", 7) * Double(topCount("♥")))
        case "spadePeek":
            // Always exactly one peek (all-♠ column is the GATE, not a scale).
            return 1
        case "suitDig":
            // Cards buried — only Club Dig ships in the roster.
            guard base.suit == "♣" else { return nil }
            return topCount("♣") * max(1, base.int("digCount", 1))
        default:
            return nil
        }
    }

    /// WHY a charged Base can't fire right now (nil when it can, or when the
    /// reason has no better words than the generic notice). The amber tap
    /// notice names THIS instead of a shrug — "can't do anything right now"
    /// made a boss-sealed Last Resort indistinguishable from a broken one
    /// (v6.52, from a field report that couldn't be diagnosed).
    public func baseUnavailableReason(_ col: Int?) -> String? {
        guard let base = baseForColumn(col), !baseCanActivate(col) else { return nil }
        let alive = colAlivePiles(col)
        switch base.effect {
        case "lastResort":
            if runConfig.isBoss { return "Sealed during a boss deal." }
            if alive.isEmpty { return "No alive pile in this column to bury under." }
            if deck.isEmpty { return "No deck cards left to bury." }
        case "setSuit":
            if alive.count <= 1 { return "Needs more than one alive pile in this column." }
            return "The pile cards here already share one suit."
        case "setValue":
            if alive.isEmpty { return "No alive pile in this column." }
        case "clubTell":
            if deck.isEmpty { return "The deck is empty." }
            return "Needs a ♣ on top of a pile in this column."
        case "stickerHarvest":
            return "No pile card in this column carries a sticker to harvest."
        case "suitDig":
            return "Needs a \(base.suit ?? "matching") on top of a pile in this column."
        case "spadePeek":
            return "Fires only when EVERY pile in this column has a ♠ on top."
        case "heartDemolish":
            return "No ♥-topped pile in this column."
        case "tax":
            return "No ♥ cards in this column."
        case "demolish":
            return "No Pillar on this column to demolish."
        case "reviveBase":
            return "No dead pile in this column to revive."
        case "rechargeSameShield":
            return "The Same Charge is already banked."
        case "activateSamePower":
            if run.samePower == nil { return "No Same-Power equipped." }
        case "lonePeek":
            if run.samePower != nil { return "Works only while NO Same-Power is equipped." }
        // ── v6.76 archetype batch ─────────────────────────────────────────
        case "transmute":
            return "Fires at purchase — never during a deal."
        case "sacrifice", "chorus", "devilsDeal":
            return "No alive pile in this column."
        case "cleanseColumn":
            return "No curses on this column's top cards."
        case "diamondBoost":
            return "Needs a ♦ on top of a pile in this column."
        default: break
        }
        return nil
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

    /// Activate the Base on column `col`. `targetIndex` is the chosen pile for
    /// pile-target Bases (Sticker Harvest); ignored by the whole-column Bases.
    /// `purseCoins` threads the CAMPAIGN purse into the one Base that prices
    /// off it (Empty Purse, v6.74) — coins are not engine state, so the
    /// caller reads them and drains them again on the result (`purseSpent`).
    /// Spends the charge and fires the effect.
    @discardableResult
    public func baseActivate(col: Int, targetIndex: Int? = nil, purseCoins: Int = 0) -> BaseResult? {
        guard baseAvailable(col), let base = baseForColumn(col) else { return nil }
        // Validate the target for pile-target Bases (column-scoped). Demolish
        // lost its target pick in v6.51 — it destroys its OWN column's Pillar.
        if base.target == "pile" {
            guard let targetIndex else { return nil }
            guard board.isActive(targetIndex), run.pileColumns?[targetIndex] == col else { return nil }
            // DIAMOND BOOST (v6.76) further requires a ♦ top on the pick —
            // a bad target refuses WITHOUT spending the charge.
            if base.effect == "diamondBoost", !matchesSuit(board.top(targetIndex), "♦") { return nil }
        }

        var res = BaseResult(col: col, effect: base.effect ?? "", label: base.label)
        let coinsBefore = run.bonusCoins
        fireContext = "\(base.label) activated · column \(col + 1)"
        logBegin(base.label)

        switch base.effect {
        case "kamikaze":
            // Auto-pick a RANDOM alive ♠-topped pile in the BASE's own column.
            let pk = base.int("peekCount", 3)
            guard let kill = pick(colAlivePiles(col).filter { matchesSuit(board.top($0), "♠") }) else { break }
            board.kill(kill)
            emit(.pileKilled(index: kill))
            run.tellPiles.remove(kill)                 // dead pile drops any Tell hint
            run.whisperPiles.remove(kill)              // …and any whisper
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
            // Reworked (router batch 2): fires only when EVERY alive pile in
            // this column wears a ♠ top (the availability gate) — one peek.
            run.kamikazeRevealLeft = max(run.kamikazeRevealLeft, 1)
            res.peekCount = 1
            res.cards = deck.peek(1)
            logLine("all-♠ column: peeking the next upcoming card")

        case "lonePeek":
            // The Lone Eye: a plain single peek, gated (in availability) on
            // the Same-Power slot being EMPTY.
            run.kamikazeRevealLeft = max(run.kamikazeRevealLeft, 1)
            res.peekCount = 1
            res.cards = deck.peek(1)
            logLine("\(base.label): peeking the next upcoming card (no Same-Power equipped)")

        case "lastResort":
            // LAST RESORT: the whole remaining deck goes UNDER one pile in
            // this column, and the deal ends — through the engine's own end
            // check, so the win, payout and score (alive × smallest, on the
            // final board incl. the mega-pile) are exactly a normal win's.
            guard let target = pick(colAlivePiles(col)) else { break }
            let n = deck.remaining()
            let buried = buryTribute(target, n, base.label)
            res.index = target
            res.buried = buried
            logLine("\(base.label): buried the remaining \(buried) card\(buried == 1 ? "" : "s") under pile \(target + 1) — the deal is over")
            evaluateEnd()

        case "emptyPurse":
            // EMPTY PURSE (v6.74 rework): 1 peek BASELINE + 1 more per 10
            // coins in the purse when triggered — 0 coins still peeks 1.
            // The purse lives with the campaign: the caller threads the
            // count in (`purseCoins`) and drains exactly `res.purseSpent` on
            // this result (coins are not engine state). Fires regardless of
            // the purse's size.
            let purse = max(0, purseCoins)
            let peeks = 1 + purse / 10
            run.kamikazeRevealLeft = max(run.kamikazeRevealLeft, peeks)
            res.peekCount = peeks
            res.purseSpent = purse
            res.cards = deck.peek(peeks)
            logLine("\(base.label): \(purse) coins spent to peek \(peeks) card\(peeks == 1 ? "" : "s") ahead")

        case "sameTell":
            // SAME TELL: one question, one answer. A rank match with a top
            // card here gets the = mark on that pile for the next draw; no
            // match says nothing at all (and the silence is the answer).
            guard let next = deck.peek(1).first else { break }
            // v6.62: board-WIDE — the mark lands on the first matching top
            // anywhere on the board, not just this column.
            if let match = allAlivePiles().first(where: {
                guard let t = board.top($0) else { return false }
                // A ★ on either side IS a same (always safe) — v6.52: a joker
                // hint never shows an arrow, only the = mark.
                return next.joker || t.joker || t.value == next.value
            }) {
                run.tellDrawsLeft += 1
                run.whisperPiles.insert(match)
                res.tellPile = match
                res.tellDirection = .same
                logLine("\(base.label): the next card matches pile \(match + 1)'s top — marked =")
            } else {
                logLine("\(base.label): no match. It says nothing")
            }

        case "clubTell":
            // The Club Oracle (v6.52): put a TELL MARKER on every alive
            // ♣-topped pile in this column — the same armed-pile hint chip the
            // Tell sticker uses (run.tellPiles → pileHint), live until the
            // next draw consumes it. v6.51 computed the directions but only
            // FLOATED them for a blink, which read as the base doing nothing;
            // the armed chip repaints on every board refresh, so the verdict
            // stays on screen until the player actually uses it.
            let clubs = colAlivePiles(col).filter { matchesSuit(board.top($0), "♣") }
            guard let next = deck.peek(1).first, !clubs.isEmpty else { break }
            var tells: [(pile: Int, direction: Guess)] = []
            for pileIdx in clubs {
                guard let top = board.top(pileIdx) else { continue }
                // A Joker on either side reads SAME (v6.52) — a ★ can't be
                // compared, and any call against one is safe.
                let dir: Guess = (next.joker || top.joker) ? .same
                              : next.value > top.value ? .higher
                              : next.value < top.value ? .lower : .same
                tells.append((pile: pileIdx, direction: dir))
                run.tellPiles.insert(pileIdx)
                logLine("\(base.label): marked pile \(pileIdx + 1) — the next card runs \(dir.rawValue) than its \(cardName(top))")
            }
            res.tells = tells

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

        case "ambushWin":
            // Empty the draw pile and run the engine's OWN end check — so the
            // win, the payout, the stats and the end presentation all behave
            // exactly as a real clear does. Nothing bespoke to keep in sync.
            _ = deck.drain()
            logLine("\(base.label): the ambush is over")
            res.index = col
            evaluateEnd()

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
            // Own column ONLY (v6.51): no target pick. The rubble reveals the
            // road ahead: peek the next `peekCount` cards.
            let pk = base.int("peekCount", 2)
            let destroyedId = run.pillars![col]
            run.pillars![col] = nil                     // stop its effect immediately
            run.kamikazeRevealLeft = max(run.kamikazeRevealLeft, pk)
            res.demolishedCol = col
            res.demolishedPillar = destroyedId
            res.peekCount = pk
            res.cards = deck.peek(pk)
            logLine("destroyed the Pillar on column \(col + 1), peeking the next \(pk) upcoming cards")

        case "heartDemolish":
            // Destroy every alive ♥-topped pile in this column; +coinPerPile each.
            let targets = colAlivePiles(col).filter { matchesSuit(board.top($0), "♥") }
            for i in targets {
                board.kill(i)
                emit(.pileKilled(index: i))
                run.tellPiles.remove(i)
                run.whisperPiles.remove(i)
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

        // ── v6.76 archetype batch ─────────────────────────────────────────

        case "purgeDiscount":
            // PURGE COUPON: a store-side lever carried on a base. The engine
            // only REPORTS the activation (coins/pricing are campaign state) —
            // the flow applies it via `CampaignState.addPurgeDiscount`.
            res.purgePriceCut = base.int("value", 3)
            res.purgePriceFloor = base.int("min", 5)
            logLine("\(base.label): the store's Purge costs \(res.purgePriceCut!) less (never below \(res.purgePriceFloor!)) for the rest of the climb")

        case "sacrifice":
            // SACRIFICE: the chosen pile's TOP card is purged from the game
            // entirely (the flow removes that identity from the campaign deck
            // via `purgedCardId`) and the pile dies with the rest of its cards.
            guard let ti = targetIndex, let top = board.top(ti) else { break }
            board.piles[ti].cards.removeLast()          // purged — never returns
            board.kill(ti)
            run.tellPiles.remove(ti)
            run.whisperPiles.remove(ti)
            if run.lastLandedPile == ti { run.lastLandedPile = nil }
            emit(.pileKilled(index: ti))
            // Last Rites on the sacrifice, like every other pile death.
            if let dd = resolvePillarDef(col), dd.effect == "lastRites" { peekPillar(col, dd) }
            res.index = ti
            res.purgedCardId = top.id
            logLine("sacrificed pile \(ti + 1) — \(cardName(top)) purged from the deck; the pile dies")

        case "devilsDeal":
            // DEVIL'S DEAL: double this deal's bonus tally (the delta is
            // exactly the pre-deal tally), then inflict a curse on a top card
            // in this column. The base carries NO `target` — the curse lands
            // on a SEEDED pick among the column's cursable tops (the
            // Kamikaze random-pile precedent; the web's behavior). A supplied
            // pick is honored only when valid (alive, in-column), else it
            // folds to the same seeded re-pick; an un-CURSABLE pick
            // (joker/blank/full/no eligible curse) also re-picks — one seeded
            // draw either way. With no cursable top at all the deal still
            // just doubles.
            let boost = run.bonusCoins
            if boost > 0 { addBonus(base.label, boost) }
            res.gained = boost
            var ti = targetIndex
            if let t = ti, !(board.isActive(t) && run.pileColumns?[t] == col) { ti = nil }
            if ti == nil || cursedStickerPoolFor(board.top(ti!)).isEmpty {
                let cands = colAlivePiles(col).filter { !cursedStickerPoolFor(board.top($0)).isEmpty }
                ti = cands.isEmpty ? nil : cands[rng.index(cands.count)]
            }
            if let t = ti, let top = board.top(t), let curse = rollCursedStickerType(top) {
                top.stickers.append(StickerRecord(type: curse.id))
                res.index = t
                res.stickerApplied = (pileIndex: t, cardId: top.id, typeId: curse.id)
                logLine("\(base.label): the bonus tally doubles (+\(jsNum(boost))); \(curse.label) curses pile \(t + 1)'s \(cardName(top))")
            } else {
                logLine("\(base.label): the bonus tally doubles (+\(jsNum(boost))) — no cursable top in the column")
            }

        case "cleanseColumn":
            // CLEANSE: strip every CURSE off this column's top cards. The
            // `.cursePeeled` event per card makes the peel permanent on the
            // campaign identity (the Peeler contract).
            var peeledTotal = 0
            for i in colAlivePiles(col) {
                guard let top = board.top(i) else { continue }
                let curses = top.stickers.filter { stickerTypes.get($0.type)?.cursed == true }
                if curses.isEmpty { continue }
                top.stickers.removeAll { stickerTypes.get($0.type)?.cursed == true }
                peeledTotal += curses.count
                emit(.cursePeeled(index: i, cardId: top.id, types: curses.map(\.type)))
                logLine("cleansed \(curses.count) curse\(curses.count == 1 ? "" : "s") off pile \(i + 1)'s \(cardName(top))")
            }
            res.cleansed = peeledTotal

        case "chorus":
            // CHORUS: every top card in the column takes the rank the FULL
            // deck holds the most copies of (ties → the lowest rank). Joker /
            // Removal tops are rankless and stay untouched. Durable for the
            // run — `valueApplied` rides the Base write-back contract.
            guard let rank = mostCopiedRank() else { break }
            let rk = DeckManager.ranks.first { $0.value == rank }
            var applied: [(cardId: Int, value: Int)] = []
            for i in colAlivePiles(col) {
                guard let top = board.top(i), !top.joker, !top.blank, top.value != rank else { continue }
                top.value = rank
                if let rk { top.label = rk.label }
                applied.append((cardId: top.id, value: rank))
            }
            res.valueApplied = applied
            res.sourceValue = rank
            logLine("set \(applied.count) top card\(applied.count == 1 ? "" : "s") to \(rk?.label ?? "?") — the full deck's most-copied rank")

        case "diamondBoost":
            // DIAMOND BOOST: +value pile size to the chosen ♦-topped pile
            // (target validated above, before the charge is spent).
            guard let ti = targetIndex else { break }
            let boost = base.int("value", 3)
            board.addSizeBonus(ti, boost)
            res.index = ti
            logLine("pile \(ti + 1) gains +\(boost) pile size")

        default:
            currentEntry = nil
            fireContext = nil
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
        // v6.76 archetype batch.
        if let va = res.valueApplied, !va.isEmpty { imp["ranked"] = Double(va.count) }
        if res.purgedCardId != nil { imp["purged"] = 1; imp["killed"] = 1 }
        if let cl = res.cleansed, cl != 0 { imp["peeled"] = Double(cl) }
        if base.effect == "purgeDiscount", res.purgePriceCut != nil { imp["fires"] = 1 }
        if base.effect == "diamondBoost", res.index != nil { imp["size"] = Double(base.int("value", 3)) }
        recT("base", base.id, base.label, imp)

        currentEntry = nil
        fireContext = nil
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
    /// TEST HOOK: fire the equipped Same-Power on `hub` directly, without
    /// staging a correct Same call first.
    public func debugFireSamePower(_ hub: Int) { fireSamePower(hub) }

    func fireSamePower(_ hub: Int) {
        guard let run, let id = run.samePower, let def = samePowerTypes.get(id) else { return }
        var result = SamePowerResult(power: def.id, label: def.label, hub: hub, effect: def.effect ?? "")
        switch def.effect {
        case "linkBury":
            // Bury `value` card(s) under every alive pile whose TOP wears the
            // climb's rolled suit (v6.38; Wild Suit counts). No variant on an
            // old save → every alive pile, the pre-roll behaviour.
            let suit = run.samePowerVariant
            let targets = powerPiles("alive").filter { j in
                guard let s = suit else { return true }
                return CardRules.matchesSuit(board.top(j), s, data: data)
            }
            var buried = 0
            let n = def.int("value", 0) != 0 ? def.int("value", 0) : 1
            for j in targets { buried += buryTribute(j, n, def.label) }
            if buried > 0 { recT("samePower", def.id, def.label, ["buried": Double(buried)]) }
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
                recT("samePower", def.id, def.label, ["revived": 1])
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
            if !targets.isEmpty { recT("samePower", def.id, def.label, ["shuffled": Double(targets.count)]) }
            result.targets = targets
            result.amount = targets.count

        case "samePeek":
            // Peek the next upcoming card (deck-reveal treatment, like Scout).
            run.revealNextActive = true
            recT("samePower", def.id, def.label, ["peeks": 1])
            result.amount = 1

        case "linkTell":
            // A hint on the next card per ALIVE PILE — a wide board buys a
            // long look ahead, a board down to one pile buys almost nothing.
            // The window length is the counted-pile tally; the hint itself
            // shows only on the most recently landed top card (v6.58).
            // X counts only the alive piles whose top wears the climb's
            // rolled COLOUR (v6.38; Wild Suit counts as both). No variant on
            // an old save → every alive pile, the pre-roll behaviour.
            let colour = run.samePowerVariant
            let alive = powerPiles("alive").filter { j in
                guard let colour, let top = board.top(j) else { return colour == nil }
                if CardRules.isWildSuit(top, data: data) { return true }
                let red = top.suit == "♥" || top.suit == "♦"
                return colour == "red" ? red : !red
            }
            if !alive.isEmpty {
                // v6.58: Second Sight rides its OWN window (sightDrawsLeft),
                // and the hint shows on ONE pile only — the most recently
                // landed top card — never on every counted pile at once.
                // The fire still RESETS rather than stacks (the v6.52 rule).
                run.sightDrawsLeft = alive.count
                recT("samePower", def.id, def.label, ["hints": Double(alive.count)])
            }
            result.targets = alive
            result.amount = alive.count

        case "linkSticker":
            // A random sticker onto EVERY top card in the CALLED pile's column
            // — a column-wide spray rather than a scatter across the board, so
            // it rewards a built-up column the way the other column items do.
            let col = run.pileColumns?[safe: hub] ?? nil
            let inCol = col.map { c in powerPiles("alive").filter { run.pileColumns?[$0] == c } }
                ?? powerPiles("alive")
            var hit: [Int] = []
            for j in inCol {
                guard let top = board.top(j),
                      let typeId = pick(wildStickerPoolFor(top).map(\.id)) else { continue }
                projectStickerOntoCard(top, typeId)
                hit.append(j)
                // The DURABLE copy: the engine marks the live card, the flow
                // writes it onto the campaign's card (same contract a Base's
                // stickerApplied uses). Without this the spray lasted one deal.
                result.stickersApplied.append((cardId: top.id, typeId: typeId))
                logLine("\(def.label): \(stickerTypes.get(typeId)?.label ?? typeId) onto pile \(j + 1)")
            }
            if !hit.isEmpty { recT("samePower", def.id, def.label, ["applied": Double(hit.count)]) }
            result.targets = hit
            result.amount = hit.count

        case "linkPurge":
            // A CHANCE to burn one card out of the rest of the deck. Nothing
            // on the board is touched — this only shortens what is coming.
            // The roll reports its HIT/MISS (v6.57).
            let odds = def.num("chance", 0.25)
            if rollChance("samePower", def.id, def.label, odds, index: hub),
               let gone = deck.removeRandomRemaining(rng) {
                result.amount = 1
                logLine("\(def.label): purged \(cardName(gone)) from the deck")
                recT("samePower", def.id, def.label, ["purged": 1])
            } else {
                logLine("\(def.label): the deck kept its card")
            }

        case "linkHeavy":
            // +value pile size to EVERY alive pile, plus hubValue on top for the
            // CALLED pile itself (both persistent this deal).
            let targets = powerPiles("alive")
            let per = def.int("value", 0) != 0 ? def.int("value", 0) : 5
            for j in targets { board.addSizeBonus(j, per) }
            let hubBonus = def.int("hubValue", 5)
            board.addSizeBonus(hub, hubBonus)
            recT("samePower", def.id, def.label, ["fires": 1])
            result.targets = targets
            result.amount = per * targets.count + hubBonus

        case "rankFlood":
            // RANK FLOOD (v6.76): every ALIVE pile's top takes the CALLED
            // card's rank, permanently (rankApplied rides the durable
            // write-back contract a Base's valueApplied uses). The called
            // card is the hub's top; "a Joker on either side ranks them by
            // the RANKED card" — the card BENEATH the top is the other side
            // of the Same — "and Joker-on-Joker makes Aces". Joker/Removal
            // tops are rankless wildcards and stay untouched.
            let hubCards = board.piles[hub].cards
            let topCard = hubCards.last
            let beneath = hubCards.count >= 2 ? hubCards[hubCards.count - 2] : nil
            let rank: Int
            if let t = topCard, !t.joker, !t.blank {
                rank = t.value
            } else if let b = beneath, !b.joker, !b.blank {
                rank = b.value
            } else {
                rank = maxRank          // Joker-on-Joker → Aces
            }
            let rk = DeckManager.ranks.first { $0.value == rank }
            var hit: [Int] = []
            var applied: [(cardId: Int, value: Int)] = []
            for j in powerPiles("alive") {
                guard let t = board.top(j), !t.joker, !t.blank else { continue }
                t.value = rank
                if let rk { t.label = rk.label }
                hit.append(j)
                applied.append((cardId: t.id, value: rank))
            }
            result.targets = hit
            result.amount = hit.count
            result.rankApplied = applied
            if !hit.isEmpty {
                logLine("\(def.label): \(hit.count) pile top\(hit.count == 1 ? "" : "s") become \(rk?.label ?? "?")")
                recT("samePower", def.id, def.label, ["fires": 1, "ranked": Double(hit.count)])
            }

        default: break
        }
        logLine("\(def.label) (Same-Power): \(result.targets.count) pile(s)")
        emit(.samePower(result))
    }
}
