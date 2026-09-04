import Foundation

// Every sticker / Pillar effect, keyed by the items.js `behavior` / `effect`
// field and reading its tunables from the item def — never a hardcoded number.
extension GameEngine {

    // MARK: - Same-Tolerance + landing shields (v6.76 archetype batch, R1)

    /// Does the column's pillar make this otherwise-WRONG call safe? Returns
    /// the effect key that saved it (for the fired pulse), nil for no save.
    /// ONE shared resolution for the whole sameTolerance family: a tolerated
    /// Same is promoted to a FULL correct Same by the caller, so it charges
    /// the Same Shield, fires the equipped Same-Power and counts as a correct
    /// Same in the stats. The `sameSuit` tolerance additionally shields ANY
    /// call on a same-suit landing, not just a Same call. The shield pillars (Royal Sanctuary,
    /// Rank Shield, Majority Rule, Daily Suit) read their composition
    /// conditions against the FULL deck, live, here (R3).
    func landingSave(pillar: ItemDef, g: Guess, current: LiveCard, drawn: LiveCard, col: Int) -> String? {
        switch pillar.effect {
        case "sameTolerance":
            switch pillar.tol {
            case "near":
                // ±1 in value survives a Same call.
                guard g == .same, abs(drawn.value - current.value) == 1 else { return nil }
            case "royalPair":
                // A royal landing on a royal survives a Same call.
                guard g == .same,
                      (11...13).contains(drawn.value), (11...13).contains(current.value) else { return nil }
            case "sum10":
                // Ranks summing to 10 survive a Same call.
                guard g == .same, drawn.value + current.value == 10 else { return nil }
            case "sameSuit":
                // SAME SUIT SAFE: a card landing on its own suit is safe on
                // ANY call, Same included (Wild Suit on either side counts as
                // every suit).
                guard matchesSuit(drawn, current.suit) || matchesSuit(current, drawn.suit) else { return nil }
            default: return nil
            }
            return "sameTolerance"
        case "royalSafeNoTwos":
            // ROYAL SANCTUARY: no 2s anywhere in the full deck → a royal
            // (J/Q/K) landing in this column is always safe.
            guard (11...13).contains(drawn.value),
                  (fullDeckRankCounts()[minRank] ?? 0) == 0 else { return nil }
            return "royalSafeNoTwos"
        case "rankShield":
            // RANK SHIELD: the shop-rolled rank landing here is always safe.
            guard let rank = run.shopRolls[pillar.id]?.rank, drawn.value == rank else { return nil }
            return "rankShield"
        case "suitMajoritySafe":
            // MAJORITY RULE: half or more of the full deck's RANKED cards
            // wear the rolled suit → that suit's landings here are safe.
            // WEB-EXACT (v6.78 parity fix): jokers/blanks are outside BOTH
            // sides of the ratio (a Joker is no suit's majority fodder), a
            // Wild Suit card counts toward every suit, and there is no
            // in-flight adjustment — the full-deck hook already holds the
            // whole collection (the old +1 predates the hook).
            guard let suit = run.shopRolls[pillar.id]?.suit, matchesSuit(drawn, suit) else { return nil }
            var suited = 0, total = 0
            for c in fullDeckCards() where !c.joker && !c.blank {
                total += 1
                if matchesSuit(c, suit) { suited += 1 }
            }
            guard total > 0, suited * 2 >= total else { return nil }
            return "suitMajoritySafe"
        case "suitShieldDaily":
            // DAILY SUIT: the suit rolled at Start Run (run.dailySuits) is
            // safe when it lands in this column.
            guard let suit = run.dailySuits?[col], matchesSuit(drawn, suit) else { return nil }
            return "suitShieldDaily"
        case "pauperHeartSafe":
            // PAUPER'S HEART (v6.98): a ♥ landing is safe while the purse is
            // under the ceiling — read LIVE, the family rule. (The flat-broke
            // peek rides the correct-landing extras, not the save.)
            guard matchesSuit(drawn, "♥"), purseBelow(pillar) else { return nil }
            return "pauperHeartSafe"
        case "rankGapSafe":
            // RANK GAP (v6.98): safe when the full deck holds ZERO copies of
            // the rank ABOVE or BELOW the landing card. EDGE RULE (documented
            // in items.js): the rank line does NOT wrap and a non-existent
            // boundary neighbour is NOT "absent" — a 2 qualifies only via its
            // 3s, an Ace only via its Kings. Jokers/Blanks are rankless and
            // never qualify.
            guard !drawn.joker, !drawn.blank else { return nil }
            let counts = fullDeckRankCounts()
            let above = drawn.value + 1, below = drawn.value - 1
            let gapAbove = above <= maxRank && (counts[above] ?? 0) == 0
            let gapBelow = below >= minRank && (counts[below] ?? 0) == 0
            guard gapAbove || gapBelow else { return nil }
            return "rankGapSafe"
        default:
            return nil
        }
    }

    // MARK: - Conditional stickers (v6.85)

    /// THE CONDITIONAL-STICKER CHECK — the shared read every v6.85 rework
    /// sticker uses. nil = EXEMPT: there is no OTHER alive pile, so the
    /// sticker neither fires nor converts (11.7% of real landings — without
    /// the exemption the endgame is a guaranteed curse mill). Otherwise the
    /// OTHER alive piles whose top matches the CARRIER's suit (Wild Suit
    /// tops count, the shared matchesSuit rule).
    func conditionalSuitMatches(_ index: Int, _ carrier: LiveCard) -> [Int]? {
        guard !carrier.joker, !carrier.blank else { return [] }
        let others = (0..<board.size).filter { $0 != index && board.isActive($0) }
        guard !others.isEmpty else { return nil }
        return others.filter { matchesSuit(board.top($0), carrier.suit) }
    }

    /// The RANK twin (v6.86 — Same-Safe goes live as the first of the
    /// held-back rank conditionals): the OTHER alive piles whose top shows
    /// the CARRIER's rank. Same exemption contract: nil = no other alive
    /// pile, the sticker neither fires nor converts. A joker top has no
    /// rank to match (value 0).
    func conditionalRankMatches(_ index: Int, _ carrier: LiveCard) -> [Int]? {
        guard !carrier.joker, !carrier.blank else { return [] }
        let others = (0..<board.size).filter { $0 != index && board.isActive($0) }
        guard !others.isEmpty else { return nil }
        return others.filter { board.top($0)?.value == carrier.value }
    }

    /// One weighted draw from the curse pool via the "sticker" PATHWAY —
    /// the severe band is excluded by its curseExclude, so a missed suit
    /// read can never destroy a Pillar or Base. Filtered to curses that can
    /// legally stick on `card`; nil when nothing can.
    func rollStickerPathCurse(for card: LiveCard) -> ItemDef? {
        let pool = stickerTypes.cursePool(path: "sticker").filter {
            CardRules.stickerEligible(card, $0.id, data: data)
        }
        let total = pool.reduce(0.0) { $0 + $1.num("curseWeight", 1) }
        guard total > 0 else { return nil }
        var r = rng.next() * total
        var pick = pool.last
        for t in pool {
            r -= t.num("curseWeight", 1)
            if r < 0 { pick = t; break }
        }
        return pick
    }

    /// THE CONVERSION — a conditional sticker's failed bet: remove ONE
    /// instance of `type` from the card and put a rolled curse in its
    /// place. The curse is appended AFTER this landing's curseTouch already
    /// ran, so it is NOT live on this landing — it first participates when
    /// the card lands again (the deferred-activation rule). The durable
    /// campaign write rides the `.stickerConverted` event.
    func convertStickerToCurse(_ index: Int, _ card: LiveCard, _ type: ItemDef) {
        guard let at = card.stickers.firstIndex(where: { $0.type == type.id }) else { return }
        // CURSE WARD (v6.88): a warded column never converts — the sticker
        // stays put and simply didn't fire. resolvePillarDef keeps the
        // shared rules (Ditto mirrors the ward, a Jammer blocks it).
        if let wcol = run.pileColumns?[index],
           let ward = resolvePillarDef(wcol), ward.effect == "stickerCurseWard" {
            firePillar(wcol, "stickerCurseWard", ward.label, 0)
            recT("pillar", ward.id, ward.label, ["warded": 1])
            logLine("\(ward.label): \(type.label) kept its place on \(cardName(card)) — no curse")
            return
        }
        card.stickers.remove(at: at)
        if let curse = rollStickerPathCurse(for: card) {
            card.stickers.append(StickerRecord(type: curse.id, convertedFrom: type.id))
            run.freshCurses.append((cardId: card.id, type: curse.id))
            logLine("\(type.label) fizzled on \(cardName(card)) — \(curse.label) takes its place")
            emit(.stickerConverted(index: index, cardId: card.id, from: type.id, to: curse.id))
        } else {
            logLine("\(type.label) fizzled on \(cardName(card)) — nothing could stick")
            emit(.stickerConverted(index: index, cardId: card.id, from: type.id, to: nil))
        }
        recT("sticker", type.id, type.label, ["converted": 1])
    }

    /// Donate's v6.85 fire: equalise EVERY alive pile (the board-wide twin
    /// of Ballast's column walk — hand a buried card from the biggest pile
    /// to the smallest until every pair is within 1). The move list is for
    /// the travel animation — presentation data only, identities hidden.
    func equalizeAllPiles() -> (moved: Int, moves: [(from: Int, to: Int)]) {
        var moves: [(from: Int, to: Int)] = []
        for _ in 0..<500 {
            let alive = (0..<board.size).filter { board.isActive($0) }
            if alive.count < 2 { break }
            var big = alive[0], small = alive[0]
            for i in alive {
                if board.pileSize(i) > board.pileSize(big) { big = i }
                if board.pileSize(i) < board.pileSize(small) { small = i }
            }
            if big == small || board.pileSize(big) - board.pileSize(small) <= 1 { break }
            if board.piles[big].cards.count <= 1 { break }
            if !board.moveBottomCard(big, small) { break }
            moves.append((from: big, to: small))
        }
        return (moves.count, moves)
    }

    // MARK: - Board-wide size replacements (v6.76)

    /// PAUPER'S DIAMOND / DIAMOND LIFELINE: a ♦ landing ANYWHERE on the board
    /// can count as MORE than 1 toward its pile's size. The condition (purse
    /// for the pauper; a size-1 pile in the pillar's column for the lifeline)
    /// is read LIVE at the landing and the difference latches as a per-pile
    /// size bonus — the Same Heavy mechanism. Pillar landing effect, so it
    /// fires on CORRECT landings only (the fatal-landing audit's rule), like
    /// every other pillar in this branch.
    func maybeBoardWideSizeEffects(_ index: Int, _ drawn: LiveCard) {
        guard matchesSuit(drawn, "♦"), let cols = run.cols else { return }
        for c in 0..<cols.count {
            guard let def = resolvePillarDef(c) else { continue }
            let qualifies: Bool
            switch def.effect {
            case "pauperDiamondSize":
                qualifies = purseBelow(def)
            case "sizeOneDiamonds":
                qualifies = colAlivePiles(c).contains { board.pileSize($0) == 1 }
            default:
                continue
            }
            guard qualifies else { continue }
            let value = max(1, def.int("value", 2))
            let extra = value - 1          // the card already counts 1
            guard extra > 0 else { continue }
            board.addSizeBonus(index, extra)
            firePillar(c, def.effect ?? "", def.label, 0)
            recT("pillar", def.id, def.label, ["fires": 1, "size": Double(extra)])
            logLine("\(def.label): the ♦ counts \(value) toward pile \(index + 1)'s size")
        }
    }

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

        case "flypaper" where rollChance("pillar", pillar.id, pillar.label,
                                         pillar.num("chance", 0.05), index: index, col: col):
            // Flypaper: the landed card picks up a random sticker, permanent.
            let pool = wildStickerPoolFor(drawn)
            if let typeId = pick(pool.map(\.id)) {
                projectStickerOntoCard(drawn, typeId)
                firePillar(col, "flypaper", pillar.label, 0)
                emit(.pillarSticker(col: col, pileIndex: index, cardId: drawn.id, typeId: typeId))
                recT("pillar", pillar.id, pillar.label, ["applied": 1])
                logLine("\(pillar.label): \(stickerTypes.get(typeId)?.label ?? typeId) stuck to \(cardName(drawn))")
            }

        case "rankCoin" where v == run.pillarRankVariants[pillar.id]:
            // Crowd Favorite: the climb-locked rank landed → flat coins.
            payPillar(col, "rankCoin", pillar.label, pillar.num("value", 2) == 0 ? 2 : pillar.value)

        case "rankBury" where v == run.pillarRankVariants[pillar.id]:
            // Underdog: the climb-locked rank landed → bury under the pile.
            let nb = buryTribute(index, pillar.int("digCount", 1), pillar.label)
            if nb > 0 {
                firePillar(col, "rankBury", pillar.label, 0)
                recT("pillar", pillar.id, pillar.label, ["buried": Double(nb)])
            }

        case "shuffler" where isDiamond:
            // SHUFFLER (v6.91 offer; v6.99 scope): the card LANDS first, then
            // the shuffle is OFFERED — the player can decline (or tap away).
            // It now shuffles EVERY alive pile in the column, the landing
            // pile included. Offered only when some pile actually has an
            // order to hide (2+ cards) — an all-singles column is a no-op.
            if colAlivePiles(col).contains(where: { board.piles[$0].cards.count > 1 }) {
                run.pendingActions.append(PendingAction(kind: "pillarShuffle", index: index, target: col))
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

        // ── v6.76 archetype batch ─────────────────────────────────────────

        case "eightTell" where v == 8:
            // EIGHT BALL (v6.97): an 8 landing here arms a TELL on the
            // landing pile (the next draw's direction chip — Pauper's
            // Heart's shape). The peek retired with the `eightPeek` key.
            run.tellPiles.insert(index)
            firePillar(col, "eightTell", pillar.label, 0)
            recT("pillar", pillar.id, pillar.label, ["tells": 1])
            logLine("\(pillar.label): a tell arms on pile \(index + 1)")

        case "curseBuryPeek" where drawn.stickers.contains(where: { st in
            guard stickerTypes.get(st.type)?.cursed == true else { return false }
            // v6.91 TRIGGER PRECISION: only a card that landed ALREADY
            // cursed fires the Harvest — a sticker that converted DURING
            // this landing (the freshCurses ledger) is not a cursed
            // landing, it's a cursed departure. Same dormancy rule as
            // Leech's toll and Trapdoor's drop.
            return !run.freshCurses.contains { $0.cardId == drawn.id && $0.type == st.type }
        }):
            // CURSE HARVEST: a CURSED card landing here buries digCount, then
            // peeks the next card.
            let nb = buryTribute(index, pillar.int("digCount", 1), pillar.label)
            run.revealNextActive = true
            firePillar(col, "curseBuryPeek", pillar.label, 0)
            recT("pillar", pillar.id, pillar.label, ["buried": Double(nb), "peeks": 1])
            logLine("\(pillar.label): a cursed landing — buried \(nb), peeking the next card")

        case "pauperHeartSafe" where matchesSuit(drawn, "♥") && purseBroke():
            // PAUPER'S HEART (v6.98): the SAFE half lives in landingSave —
            // this is the deeper tier: a flat-broke purse (exactly 0) also
            // peeks the next card on the ♥ landing. The v6.96 tell key
            // retired with the tell.
            run.revealNextActive = true
            firePillar(col, "pauperHeartSafe", pillar.label, 0)
            recT("pillar", pillar.id, pillar.label, ["peeks": 1])
            logLine("\(pillar.label): flat broke — peeking the next card")

        case "heartZeroRanksCoin" where drawn.value == mostCopiedRank():
            // EMPTY RANKS COINS (v6.98 retrigger): `value` coins per
            // zero-copy rank when the MOST-HELD rank lands (live, ties →
            // lowest — the shared mostCopiedRank rule). The effect key is
            // stable; only the trigger moved off ♥.
            let empties = zeroCopyRankCount()
            if empties > 0 {
                payPillar(col, "heartZeroRanksCoin", pillar.label,
                          pillar.num("value", 2) * Double(empties))
            }

        case "diamondZeroRanksSize" where isDiamond:
            // EMPTY RANKS HEAVY (v6.87): the size leg — `value` pile size per
            // zero-copy rank, latched on the landing pile (Diamond Echo's
            // addSizeBonus mechanism).
            let empties = zeroCopyRankCount()
            if empties > 0 {
                let add = pillar.int("value", 1) * empties
                board.addSizeBonus(index, add)
                firePillar(col, "diamondZeroRanksSize", pillar.label, 0)
                recT("pillar", pillar.id, pillar.label, ["fires": 1, "size": Double(add)])
                logLine("\(pillar.label): \(empties) empty rank\(empties == 1 ? "" : "s") → +\(add) pile size")
            }

        case "pauperSpadeTell" where matchesSuit(drawn, "♠") && purseBelow(pillar):
            // PAUPER'S SPADE: a ♠ landing while broke arms a TELL on this pile
            // (the Tell sticker's armed-pile chip — the next draw's direction).
            // v6.98 deeper tier: flat broke (exactly 0) arms EVERY alive pile.
            if purseBroke() {
                for i in 0..<board.size where board.isActive(i) { run.tellPiles.insert(i) }
                logLine("\(pillar.label): flat broke — a tell arms on every alive pile")
            } else {
                run.tellPiles.insert(index)
                logLine("\(pillar.label): a tell arms on pile \(index + 1)")
            }
            firePillar(col, "pauperSpadeTell", pillar.label, 0)
            recT("pillar", pillar.id, pillar.label, ["tells": 1])

        case "mostHeldRankTell" where v == mostCopiedRank():
            // MOST-HELD TELL (v6.98, Rank Focus bench): the most-held rank
            // landing arms a tell on its pile; a deck already missing
            // `missingForPeek`+ ranks upgrades the same landing with a peek.
            run.tellPiles.insert(index)
            var vals: [String: Double] = ["tells": 1]
            if zeroCopyRankCount() >= pillar.int("missingForPeek", 3) {
                run.revealNextActive = true
                vals["peeks"] = 1
                logLine("\(pillar.label): a tell arms on pile \(index + 1) — and 3+ ranks missing peeks the next card")
            } else {
                logLine("\(pillar.label): a tell arms on pile \(index + 1)")
            }
            firePillar(col, "mostHeldRankTell", pillar.label, 0)
            recT("pillar", pillar.id, pillar.label, vals)

        case "pauperDiamondEqualize" where isDiamond && purseBelow(pillar):
            // PAUPER'S DIAMOND (v6.98 — a NEW item; the pile-size one stays
            // retired): while under the purse ceiling a ♦ landing equalises
            // EVERY alive pile (Donate's board-wide walk). Flat broke
            // (exactly 0) ALSO offers an optional board-wide purge — the
            // player may pick any alive pile and its top card leaves the
            // deck for good (surfaced through the pending-action queue, so
            // dialogs never stack; decline is free).
            let eq = equalizeAllPiles()
            if eq.moved > 0 {
                firePillar(col, "pauperDiamondEqualize", pillar.label, 0, moves: eq.moves)
                logLine("\(pillar.label): equalised the board — \(eq.moved) buried card\(eq.moved == 1 ? "" : "s") moved (hidden)")
            } else {
                firePillar(col, "pauperDiamondEqualize", pillar.label, 0)
            }
            recT("pillar", pillar.id, pillar.label, ["moved": Double(eq.moved)])
            if purseBroke() {
                run.pendingActions.append(PendingAction(kind: "pauperPurge", index: index, target: col))
            }

        case "diamondDupeSize" where isDiamond:
            // DIAMOND ECHO: +1 pile size per DUPLICATE of the landed rank in
            // the full deck (copies beyond the one that landed — derived, no
            // knob). Latched as a per-pile size bonus.
            let dupes = max(0, (fullDeckRankCounts()[v] ?? 0) - 1)
            if dupes > 0 {
                board.addSizeBonus(index, dupes)
                firePillar(col, "diamondDupeSize", pillar.label, 0)
                recT("pillar", pillar.id, pillar.label, ["fires": 1, "size": Double(dupes)])
                logLine("\(pillar.label): \(dupes) duplicate\(dupes == 1 ? "" : "s") of \(cardName(drawn)) → +\(dupes) pile size")
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
        } else if pillar.effect == "clubZeroRanksBury" && isClub {
            // EMPTY RANKS BURY (v6.76): bury 1 per rank with ZERO copies in
            // the full deck — derived live at the landing (R3), no count
            // knob. v6.87: the condition is shared by the family's coin and
            // size legs (zeroCopyRankCount), the effects are not.
            let empties = zeroCopyRankCount()
            if empties > 0 {
                let nb = buryTribute(index, empties, pillar.label)
                if nb > 0 {
                    firePillar(col, "clubZeroRanksBury", pillar.label, 0)
                    recT("pillar", pillar.id, pillar.label, ["buried": Double(nb)])
                }
            }
        } else if pillar.effect == "absentSuitClubBury" && isClub {
            // VOID TRIBUTE (v6.76): the full deck holds NONE of the
            // shop-rolled suit (live check) → a ♣ landing buries buryCount.
            if let suit = run.shopRolls[pillar.id]?.suit,
               (fullDeckSuitCounts()[suit] ?? 0) == 0 {
                let nb = buryTribute(index, pillar.int("buryCount", 2), pillar.label)
                if nb > 0 {
                    firePillar(col, "absentSuitClubBury", pillar.label, 0)
                    recT("pillar", pillar.id, pillar.label, ["buried": Double(nb)])
                }
            }
        } else if pillar.effect == "pauperClubBury" && isClub && purseBelow(pillar) {
            // PAUPER'S CLUB (v6.76): a ♣ landing while broke buries digCount.
            // v6.98 deeper tier: flat broke (exactly 0) buries digCountBroke
            // INSTEAD (the stated total, not a stack).
            let n = purseBroke() ? pillar.int("digCountBroke", 3) : pillar.int("digCount", 1)
            let nb = buryTribute(index, n, pillar.label)
            if nb > 0 {
                firePillar(col, "pauperClubBury", pillar.label, 0)
                recT("pillar", pillar.id, pillar.label, ["buried": Double(nb)])
            }
        } else if pillar.effect == "mostHeldRankBury" && drawn.value == mostCopiedRank() {
            // MOST-HELD BURY (v6.98, Rank Focus bench): the most-held rank
            // landing buries 1 per zero-copy rank — the Empty Ranks scale on
            // the most-held trigger. Live reads, ties → lowest, uncapped
            // (the scaling model is in the batch report).
            let empties = zeroCopyRankCount()
            if empties > 0 {
                let nb = buryTribute(index, empties, pillar.label)
                if nb > 0 {
                    firePillar(col, "mostHeldRankBury", pillar.label, 0)
                    recT("pillar", pillar.id, pillar.label, ["buried": Double(nb)])
                }
            }
        } else if pillar.effect == "clubThin" && isClub {
            // CLUB THIN (v6.76): bury digCount per full `per`-card step of the
            // REMAINING deck (read after this landing's draw).
            let per = max(1, pillar.int("per", 25))
            let n = (deck.remaining() / per) * max(1, pillar.int("digCount", 1))
            if n > 0 {
                let nb = buryTribute(index, n, pillar.label)
                if nb > 0 {
                    firePillar(col, "clubThin", pillar.label, 0)
                    recT("pillar", pillar.id, pillar.label, ["buried": Double(nb)])
                }
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
        // v6.85: curses appended DURING this landing stay dormant — consume
        // one ledger entry per skipped instance so pre-existing duplicates
        // still toll.
        var fresh = run.freshCurses
        for s in stickers {
            guard let t = stickerTypes.get(s.type) else { continue }
            if let at = fresh.firstIndex(where: { $0.cardId == drawn.id && $0.type == s.type }) {
                fresh.remove(at: at)
                continue
            }
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
                // v6.85 CONDITIONAL: pays per matching-top pile (the
                // carrier's own included); a missed bet converts.
                if let m = conditionalSuitMatches(index, drawn) {
                    if m.isEmpty { convertStickerToCurse(index, drawn, t) }
                    else {
                        let amt = t.value * Double(m.count + 1)
                        pay("Bonus Coin", amt)
                        recT("sticker", t.id, t.label, ["coins": amt])
                    }
                }
            } else if t.behavior == "collector" {
                // Hub pays per instance: +1 for each OTHER Imprint on this card.
                let unit = t.num("value", 1) == 0 ? 1 : t.value
                let amt = unit * Double(max(0, stickers.count - 1))
                pay("Collector", amt)
                recT("sticker", t.id, t.label, ["coins": amt])
            }
        }
    }

    /// Expansion stickers carried by the DRAWN card (plus the pile-top readers:
    /// the Snob family and Quick Bury fire off `current`, the PRE-LANDING top).
    /// Order inside matters: coin payouts FIRST (Deep Pockets reads the deck
    /// before this landing's own burials), then burials, then projections,
    /// then the Scouts' peek.
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
        // (v6.89: the stale v6.51 bidirectional Diamond Snob auto-shuffle is
        // GONE — Ripple fires ONLY at its CARRIER's landing, through the
        // v6.85 conditional offer in maybeStickerActions. A ♦ landing ON a
        // Ripple carrier fires nothing.)
        let csn = cn("clubSnob")
        if csn > 0 && landsOn("♣") {
            let nb = buryTribute(index, csn * (stickerTypes.get("clubSnob")?.int("digCount", 1) ?? 1), "Club Snob")
            if nb > 0 { recT("sticker", "clubSnob", "Club Snob", ["buried": Double(nb)]) }
        }

        // --- REVERSE snobs (v6.51): a snob carried by the DRAWN card fires
        // when the pile it lands on is TOPPED by the snob's suit. Both
        // directions may fire on one placement. `current` is the pre-landing
        // top — the card being landed ON. ---
        func topWears(_ suit: String) -> Bool { matchesSuit(current, suit) }

        if n("suitSnob") > 0 && topWears("♠") {
            run.revealNextActive = true                        // peek the next upcoming card
            recT("sticker", "suitSnob", "Spade Snob", ["peeks": 1])
        }
        let rhsn = n("heartSnob")
        if rhsn > 0 && topWears("♥") {
            let amt = Double(rhsn) * (stickerTypes.get("heartSnob")?.num("value", 4) ?? 4)
            payCoins("Heart Snob", amt)
            recT("sticker", "heartSnob", "Heart Snob", ["coins": amt])
        }
        // (v6.89: the reverse-direction auto-shuffle is gone with it — it
        // double-fired beside the carrier's own conditional offer.)
        let rcsn = n("clubSnob")
        if rcsn > 0 && topWears("♣") {
            let nb = buryTribute(index, rcsn * (stickerTypes.get("clubSnob")?.int("digCount", 1) ?? 1), "Club Snob")
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
            var targets: [Int] = []
            for i in 0..<board.size {
                if i == index || !board.isActive(i) { continue }
                if matchesSuit(board.top(i), "♦") { targets.append(i) }
            }
            if !targets.isEmpty {
                if run.rippleNeedsConsent {
                    // Consent mode (iOS): hold the shuffle until the player
                    // answers — the UI prompts, `answerRipple` applies/discards.
                    run.pendingRipple = (piles: targets, col: col)
                } else {
                    shuffleRipple(targets, col: col)
                }
            }
        }
        // Rank Roots (renamed from Club Roots, rank-match v6.78) — bury under
        // EACH OTHER alive pile whose TOP matches the landing card's RANK.
        // The landing pile is EXCLUDED (the synergy-family rule); a rankless
        // top (★/Removal) never matches.
        let crn = n("clubRoots")
        if crn > 0, !drawn.joker, !drawn.blank {
            let per = crn * (stickerTypes.get("clubRoots")?.int("digCount", 1) ?? 1)
            var cr = 0
            for i in 0..<board.size {
                if i == index || !board.isActive(i) { continue }
                guard let top = board.top(i), !top.joker, !top.blank,
                      top.value == drawn.value else { continue }
                cr += buryTribute(i, per, "Rank Roots")
            }
            if cr > 0 { recT("sticker", "clubRoots", "Rank Roots", ["buried": Double(cr)]) }
        }
        // Spade Whispers — the next X draws each carry a Tell-style hint.
        let swn = n("spadeWhispers")
        if swn > 0 {
            let x = swn * otherTops("♠")
            if x > 0 {
                run.tellDrawsLeft += x
                // The whisper belongs to THIS card's pile. It used to light
                // every pile on the board for the duration, which read as a
                // board-wide oracle rather than one card's hint.
                run.whisperPiles.insert(index)
                recT("sticker", "spadeWhispers", "Spade Whispers", ["hints": Double(x)])
            }
        }

        // --- burials ---
        // Quick Bury (CONDITIONAL, v6.85): fires on the carrier's landing
        // when another alive pile's top matches the carrier's suit — bury 1
        // per instance under this pile. A missed bet converts; no other
        // alive pile is exempt (the shared v6.85 rule).
        let qb = n("quickBury")
        if qb > 0, let qdef = stickerTypes.get("quickBury"),
           let qm = conditionalSuitMatches(index, drawn) {
            if qm.isEmpty {
                for _ in 0..<qb { convertStickerToCurse(index, drawn, qdef) }
            } else {
                var qbBuried = 0
                for _ in 0..<qb { qbBuried += buryTribute(index, 1, "Quick Bury") }
                recT("sticker", "quickBury", qdef.label, ["buried": Double(qbBuried)])
            }
        }
        // Heavy (CONDITIONAL, v6.85): a LANDING effect now — +value latched
        // pile size (the Same Heavy sizeBonus mechanism) to every
        // matching-top alive pile, the carrier's own included. The old
        // passive per-card weight retired with the rework (Shrink keeps
        // its); old-save Massive carriers share this behavior key and fire
        // the same way at their own value.
        let heavies = stickers.compactMap { st -> ItemDef? in
            guard let t = stickerTypes.get(st.type), t.behavior == "heavy" else { return nil }
            return t
        }
        if !heavies.isEmpty, let hm = conditionalSuitMatches(index, drawn) {
            for t in heavies {
                if hm.isEmpty { convertStickerToCurse(index, drawn, t) }
                else {
                    let v = max(1, t.int("value", 1))
                    for i in hm { board.addSizeBonus(i, v) }
                    board.addSizeBonus(index, v)
                    recT("sticker", t.id, t.label, ["size": Double(v * (hm.count + 1))])
                }
            }
        }
        // Guard (CONDITIONAL, v6.85): the SAVE lives in the guess path —
        // HERE the failed bet converts: a carrier that landed with no
        // matching other top loses its Guard to the curse pool.
        let guards = stickers.compactMap { st -> ItemDef? in
            guard let t = stickerTypes.get(st.type), t.behavior == "suitImmunity" else { return nil }
            return t
        }
        if !guards.isEmpty, let gm = conditionalSuitMatches(index, drawn), gm.isEmpty {
            for t in guards { convertStickerToCurse(index, drawn, t) }
        }
        // Same-Safe (CONDITIONAL, v6.86): the SAVE lives in the tie
        // resolution — HERE the failed bet converts: a carrier that landed
        // with no other top showing its rank loses Same-Safe to the curse
        // pool. The projected LiveCard flag re-derives afterward (Peeler's
        // idiom) so a converted carrier stops saving ties immediately.
        let tieSafes = stickers.compactMap { st -> ItemDef? in
            guard let t = stickerTypes.get(st.type), t.behavior == "tieSafe" else { return nil }
            return t
        }
        if !tieSafes.isEmpty, let rm = conditionalRankMatches(index, drawn), rm.isEmpty {
            for t in tieSafes { convertStickerToCurse(index, drawn, t) }
            drawn.tieSafe = drawn.stickers.contains {
                stickerTypes.get($0.type)?.behavior == "tieSafe"
            }
        }
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

        // --- Twin Spark (CONDITIONAL, v6.97): the last held-back sticker
        // joins the shared template on the RANK axis — peek on a rank twin
        // among the OTHER alive tops, convert on a miss (per instance),
        // exempt with no other alive pile.
        let ts = n("twinSpark")
        if ts > 0, let tdef = stickerTypes.get("twinSpark") {
            if let tm = conditionalRankMatches(index, drawn) {
                if tm.isEmpty {
                    for _ in 0..<ts { convertStickerToCurse(index, drawn, tdef) }
                } else {
                    run.revealNextActive = true
                    firePillar(col, "twinSpark", "Twin Spark", 0)
                    recT("sticker", "twinSpark", "Twin Spark", ["peeks": 1])
                }
            }
        }

        // --- scouts: only peek while THIS column has no Pillar/Base. ---
        // Pillar/Base Scout (v6.85): the failure branch CONVERTS — landing
        // in a column that HAS the item costs the sticker. Column-agnostic
        // runs (zen, bare engines) can't answer the question and are exempt.
        let psCount = n("pillarScout"), bsCount = n("baseScout")
        if psCount > 0, run.pillars != nil, let c = col, let pdef = stickerTypes.get("pillarScout") {
            if run.pillars![c] == nil {
                run.revealNextActive = true
                recT("sticker", "pillarScout", pdef.label, ["peeks": 1])
            } else {
                for _ in 0..<psCount { convertStickerToCurse(index, drawn, pdef) }
            }
        }
        if bsCount > 0, run.bases != nil, let c = col, let bdef = stickerTypes.get("baseScout") {
            if run.bases![c] == nil {
                run.revealNextActive = true
                recT("sticker", "baseScout", bdef.label, ["peeks": 1])
            } else {
                for _ in 0..<bsCount { convertStickerToCurse(index, drawn, bdef) }
            }
        }

        // --- Same-charge / Same-power stickers (CONDITIONAL, v6.90) ---
        // The last two held-back rank conditionals, on the shared template:
        // fire on a rank match among the OTHER alive tops, convert on a
        // miss (per instance), exempt with no other alive pile.
        let rc = n("rechargeSameShield")
        if rc > 0, let rdef = stickerTypes.get("rechargeSameShield") {
            if let rm = conditionalRankMatches(index, drawn) {
                if rm.isEmpty {
                    for _ in 0..<rc { convertStickerToCurse(index, drawn, rdef) }
                } else {
                    let was = sameCharge
                    sameCharge = true
                    if !was { logLine("Recharge Shield: banked a Same Shield") }   // v6.96 rename
                    recT("sticker", "rechargeSameShield", "Recharge Shield", ["saves": was ? 0 : 1])
                    emit(.sameBanked(index: index, sameCharge: sameCharge))
                }
            }
        }
        // Tap Power: fire the equipped Same-Power on THIS pile, once per
        // instance. It banks NO charge, and fireSamePower is a no-op when
        // nothing is equipped (a fed bet with no power is a quiet no-op —
        // the sticker persists).
        let tp = n("activateSamePower")
        if tp > 0, let tdef = stickerTypes.get("activateSamePower") {
            if let tm = conditionalRankMatches(index, drawn) {
                if tm.isEmpty {
                    for _ in 0..<tp { convertStickerToCurse(index, drawn, tdef) }
                } else {
                    for _ in 0..<tp { fireSamePower(index) }
                    recT("sticker", "activateSamePower", "Tap Power", ["copies": Double(tp)])
                }
            }
        }
    }

    /// SAVED-LANDING stickers (v6.57) — the complement of the v6.52/53
    /// fatal-landing audit. A card that lands WRONG but whose pile is SAVED by
    /// the Same-Charge backstop physically LANDS (it becomes the new pile top),
    /// so its own beneficial landing stickers fire — the same set, in the same
    /// relative order, as the correct-landing branch. Deliberately EXCLUDED:
    ///   - curses (`curseTouch`) and Trapdoor stay CORRECT-only — the audit's
    ///     rule; a wrong guess never springs them, saved or not;
    ///   - Pillar landing effects (maybeTribute / maybeLivePillarExtras) are
    ///     the column's reward for a CORRECT landing, not the card's stickers;
    ///   - Duplicate needs a correct Same by definition.
    /// The OTHER saves never reach here: a Guard return and a Second Wind
    /// recycle take the card back into the deck — it never lands at all.
    func fireSavedLandingStickers(index: Int, current: LiveCard, drawn: LiveCard, col: Int?) {
        // Scout: the placed card reveals the next deck card (display-only).
        if drawn.revealNext { run.revealNextActive = true; recT("sticker", "revealNext", "Scout", ["peeks": 1]) }
        // Tell (CONDITIONAL, v6.85): the carrier's suit is the bet.
        maybeConditionalTell(index, drawn)
        maybeLandingBonus(index, drawn)
        maybeExpansionStickers(index, current, drawn, col)
        maybeStickerTribute(index, drawn)
        maybeStickerActions(index, drawn)
        // CROWD FAVORITE (v6.99): the locked rank PAID only on a correct
        // guess; the spec is "whenever its rank lands in the pile" — and a
        // Same-Charge-saved landing is a real landing (the card became the
        // pile's top). The other landing pillars stay correct-only pending
        // the surviving-landing sweep report (v6.99 batch, item 3).
        if let col, let pillar = resolvePillarDef(col), pillar.effect == "rankCoin",
           drawn.value == run.pillarRankVariants[pillar.id] {
            payPillar(col, "rankCoin", pillar.label, pillar.num("value", 2) == 0 ? 2 : pillar.value)
        }
    }

    /// Post-landing sticker ACTIONS. Shuffle stays an OPTIONAL offer (queued and
    /// surfaced after any prompt drains). Donate is AUTOMATIC — it moves buried
    /// card(s) to the smallest eligible pile inline on the landing.
    func maybeStickerActions(_ index: Int, _ drawn: LiveCard) {
        let stickers = drawn.stickers
        if stickers.isEmpty { return }
        for s in stickers {
            if s.type == "shuffle" {
                // RETIRED (v6.85) — but a carrier from an old save keeps its
                // optional offer.
                if board.piles[index].cards.count > 1 {
                    run.pendingActions.append(PendingAction(kind: "shuffle", index: index, target: nil))
                }
            } else if s.type == "donate" {
                // Donate (CONDITIONAL, v6.85): a hit equalises EVERY alive
                // pile, automatically; a missed bet converts.
                guard let ddef = stickerTypes.get("donate") else { continue }
                if let m = conditionalSuitMatches(index, drawn) {
                    if m.isEmpty { convertStickerToCurse(index, drawn, ddef) }
                    else {
                        let eq = equalizeAllPiles()
                        logLine("Donate: evened the board — \(eq.moved) buried card\(eq.moved == 1 ? "" : "s") moved (hidden)")
                        recT("sticker", "donate", ddef.label, ["moved": Double(eq.moved)])
                        emit(.donateEqualized(index: index, moves: eq.moves))
                    }
                }
            } else if s.type == "diamondSnob" {
                // Ripple (CONDITIONAL, v6.85): a hit OFFERS a shuffle of the
                // matching piles; a missed bet converts.
                guard let rdef = stickerTypes.get("diamondSnob") else { continue }
                if let m = conditionalSuitMatches(index, drawn) {
                    if m.isEmpty { convertStickerToCurse(index, drawn, rdef) }
                    else {
                        run.pendingActions.append(PendingAction(kind: "suitRipple", index: index, target: nil))
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
        fireContext = "Revive · pile \(targetIndex + 1)"
        logAction("Revive: pile \(targetIndex + 1) brought back with a fresh card")
        emit(.revived(col: col, index: targetIndex))
        let rdef = resolvePillarDef(col)
        recT("pillar", rdef?.id ?? "revive", rdef?.label ?? "Revive", ["revived": 1])
        fireContext = nil
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

            case "columnNoneAlive":
                // LAST LICKS: the mirror of Guardian — +value if the column is
                // WIPED OUT at deal end. A consolation you build around, not a
                // reward for winning, so an empty column is never checked for
                // survivors (an empty layout column can't "die").
                let idxs = colIdxs(col)
                if !idxs.isEmpty && idxs.allSatisfy({ !board.isActive($0) }) {
                    bonus += t.value
                    lines.append(PayoutLine(label: t.label, detail: "Column \(col + 1) wiped out", amount: t.value, col: col))
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
                // v6.93: the fat-deck / empty-loadout piece — +value per
                // `perCards` cards in the FULL OWNED deck (the composition
                // hook's read), but ONLY while it's the sole Pillar on the
                // board (a second Pillar anywhere — even another Greedy —
                // voids it). No survival condition.
                if pillarsOnBoard == 1 {
                    let per = max(1, t.int("perCards", 5))
                    let cards = fullDeckCards().count
                    let amt = Double(cards / per) * t.value
                    if amt > 0 {
                        bonus += amt
                        lines.append(PayoutLine(label: t.label, detail: "\(cards) cards · only Pillar on the board", amount: amt, col: col))
                    }
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
                // +value if the WHOLE board has exactly one surviving pile
                // (any column — no longer requires the survivor to be here).
                if board.aliveCount() == 1 {
                    bonus += t.value
                    lines.append(PayoutLine(label: t.label, detail: "only one pile alive", amount: t.value, col: col))
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
                // The flip is memoized at Start Run (run.gamblerFlips) — this
                // read NEVER re-rolls, so a projection and the deal end can't
                // disagree. Fallback (no memo: the column was jammed at Start
                // Run): roll on the first payout read, then memoize. Always
                // emit a line so the outcome shows.
                let won: Bool
                if let memo = run.gamblerFlips?[col] {
                    won = memo
                } else {
                    won = rollChance("pillar", t.id, t.label, t.num("chance", 0.5), col: col)
                    run.gamblerFlips?[col] = won
                }
                let amt = won ? t.value : 0
                bonus += amt
                lines.append(PayoutLine(label: t.label,
                                        detail: won ? "won the flip (+\(jsNum(amt)))" : "lost the flip (+0)",
                                        amount: amt, col: col, effect: "gambler"))

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

    // MARK: - Diamond Ripple consent (iOS opt-in seam)

    /// The actual Diamond Ripple shuffle + its fired pulse/log/telemetry —
    /// shared by the auto path (default, web parity) and a consented accept.
    func shuffleRipple(_ piles: [Int], col: Int?) {
        var sh = 0
        for i in piles where board.isActive(i) { board.shufflePile(i, rng); sh += 1 }
        if sh > 0 {
            firePillar(col, "shuffler", "Diamond Ripple", 0)
            logLine("Diamond Ripple: shuffled \(sh) ♦-topped pile\(sh == 1 ? "" : "s")")
            recT("sticker", "diamondRipple", "Diamond Ripple", ["shuffled": Double(sh)])
        }
    }

    /// Resolve a consent-mode Diamond Ripple: accept shuffles the piles captured
    /// at the landing; decline discards the pending decision. A no-op with
    /// nothing pending.
    public func answerRipple(_ accept: Bool) {
        guard let run, let pending = run.pendingRipple else { return }
        run.pendingRipple = nil
        if accept { shuffleRipple(pending.piles, col: pending.col) }
    }

    // MARK: - Screenshot staging (EventCaptureUITests' `-demoPrompt …` hooks)

    /// Stage the EXACT parked state a consented Diamond Ripple produces, without
    /// needing a diamondRipple landing on cue: the current ♦-topped alive piles
    /// become the offer. If no pile wears a ♦, one is swapped in from the deck
    /// (the arrangeTutorialOpening swap idiom — counts and composition stay
    /// true). Returns the offered piles; empty when nothing could be staged.
    @discardableResult
    public func debugStageRipplePending() -> [Int] {
        guard let run, status == "playing" else { return [] }
        var targets = allAlivePiles().filter { matchesSuit(board.top($0), "♦") }
        if targets.isEmpty, let d = deck.takeFirst(where: { $0.suit == "♦" }),
           let host = allAlivePiles().first, let old = board.piles[host].cards.popLast() {
            board.piles[host].cards.append(d)
            deck.returnCard(old)
            targets = [host]
        }
        guard !targets.isEmpty else { return [] }
        run.pendingRipple = (piles: targets, col: nil)
        return targets
    }

    /// Stage the parked Second Wind choice: a REAL card drawn from the deck is
    /// held as the killer, so answering runs the genuine save/death paths.
    public func debugStageSecondWindPending() {
        guard let run, status == "playing",
              let idx = allAlivePiles().first, board.top(idx) != nil,
              !deck.isEmpty, let killing = deck.draw() else { return }
        run.pendingSecondWind = PendingSecondWind(
            index: idx, col: run.pileColumns?[idx] ?? 0, guess: .higher,
            killingCard: killing, recycleCount: board.pileSize(idx))
    }

    /// Stage the parked Link Shuffler confirm on the first alive pile (the hub).
    /// The power itself must be equipped (`-dealSamePower linkShuffle`).
    public func debugStagePowerShufflePending() {
        guard let run, status == "playing", run.samePower != nil,
              let hub = allAlivePiles().first else { return }
        run.pendingPowerShuffle = hub
    }

    /// Stage the Revive pillar's targeting offer (v6.56; EventCaptureUITests'
    /// `-demoPrompt revive`): the LAST pile dies for real and a pile in the
    /// pillar's column grows to the `trigger` count with REAL deck draws
    /// (composition stays true), then the genuine `maybeReviveTrigger` runs,
    /// so the emitted `.reviveOffer` is the real one. The pillar itself must
    /// be equipped (`-dealPillar revive`). Returns the dead targets; empty
    /// when nothing could be staged.
    @discardableResult
    public func debugStageReviveOffer() -> [Int] {
        guard let run, status == "playing" else { return [] }
        let col = 0   // -dealPillar pins the pillar to column 0
        guard let def = resolvePillarDef(col), def.effect == "revive" else { return [] }
        let trigger = def.int("trigger", 10)
        let victim = board.size - 1
        if board.isActive(victim) { board.kill(victim) }
        guard let host = (0..<board.size).first(where: {
            run.pileColumns?[$0] == col && board.isActive($0)
        }) else { return [] }
        while board.piles[host].cards.count < trigger, let drawn = deck.draw() {
            board.piles[host].cards.append(drawn)
        }
        guard board.piles[host].cards.count >= trigger else { return [] }
        maybeReviveTrigger(col)
        return allDeadPiles()
    }
}
