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
    /// Same in the stats. The `sameRank` tolerance additionally shields ANY
    /// call on a rank match (a tie), not just a Same call. The shield pillars (Royal Sanctuary,
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
            case "sameRank":
                // SUPER SAME SAFE (v6.82, replacing the sameSuit tolerance):
                // a card landing on its own RANK is safe on ANY call, Same
                // included. A rankless ★/Removal on either side never
                // matches — the Joker rule already made those calls safe
                // upstream, so this never has to consider them.
                guard !drawn.joker, !drawn.blank, !current.joker, !current.blank,
                      drawn.value == current.value else { return nil }
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
        default:
            return nil
        }
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

        // ── v6.76 archetype batch ─────────────────────────────────────────

        case "eightPeek" where v == 8:
            // EIGHT BALL: an 8 landing here peeks the next card.
            peekPillar(col, pillar)

        case "curseBuryPeek" where drawn.stickers.contains(where: { stickerTypes.get($0.type)?.cursed == true }):
            // CURSE HARVEST: a CURSED card landing here buries digCount, then
            // peeks the next card.
            let nb = buryTribute(index, pillar.int("digCount", 1), pillar.label)
            run.revealNextActive = true
            firePillar(col, "curseBuryPeek", pillar.label, 0)
            recT("pillar", pillar.id, pillar.label, ["buried": Double(nb), "peeks": 1])
            logLine("\(pillar.label): a cursed landing — buried \(nb), peeking the next card")

        case "pauperHeart" where matchesSuit(drawn, "♥") && purseBelow(pillar):
            // PAUPER'S HEART: a ♥ landing while broke pays value, live.
            payPillar(col, "pauperHeart", pillar.label, pillar.num("value", 3))

        case "pauperSpadeTell" where matchesSuit(drawn, "♠") && purseBelow(pillar):
            // PAUPER'S SPADE: a ♠ landing while broke arms a TELL on this pile
            // (the Tell sticker's armed-pile chip — the next draw's direction).
            run.tellPiles.insert(index)
            firePillar(col, "pauperSpadeTell", pillar.label, 0)
            recT("pillar", pillar.id, pillar.label, ["peeks": 1])
            logLine("\(pillar.label): a tell arms on pile \(index + 1)")

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
            // EMPTY RANKS (v6.76): bury 1 per rank with ZERO copies in the
            // full deck — derived live at the landing (R3), no count knob.
            let counts = fullDeckRankCounts()
            let empties = (minRank...maxRank).filter { (counts[$0] ?? 0) == 0 }.count
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
            let nb = buryTribute(index, pillar.int("digCount", 1), pillar.label)
            if nb > 0 {
                firePillar(col, "pauperClubBury", pillar.label, 0)
                recT("pillar", pillar.id, pillar.label, ["buried": Double(nb)])
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
        if cn("diamondSnob") > 0 && landsOn("♦") {
            // ♦ PILES ONLY. Shuffling the whole board made this the single
            // most disruptive sticker in the game and gave the player no way
            // to plan around it; scoped to its own suit it's a ♦ effect that
            // rewards a ♦-topped board.
            var sh = 0
            for i in 0..<board.size where board.isActive(i) && matchesSuit(board.top(i), "♦") {
                board.shufflePile(i, rng); sh += 1
            }
            if sh > 0 {
                firePillar(col, "shuffler", "Diamond Snob", 0)
                logLine("Diamond Snob: shuffled \(sh) ♦-topped pile(s)")
                recT("sticker", "diamondSnob", "Diamond Snob", ["shuffled": Double(sh)])
            }
        }
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
        if n("diamondSnob") > 0 && topWears("♦") {
            // Same scoping as the forward direction: ♦-topped piles only.
            var sh = 0
            for i in 0..<board.size where board.isActive(i) && matchesSuit(board.top(i), "♦") {
                board.shufflePile(i, rng); sh += 1
            }
            if sh > 0 {
                firePillar(col, "shuffler", "Diamond Snob", 0)
                logLine("Diamond Snob: shuffled \(sh) ♦-topped pile(s)")
                recT("sticker", "diamondSnob", "Diamond Snob", ["shuffled": Double(sh)])
            }
        }
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
        // Quick Bury (LANDING-FIRED, v6.78 — reverses the v6.75 pile-top
        // rule): the sticker rides the LANDING card (`drawn`) and fires the
        // moment its carrier lands — bury 1 deck card per instance under
        // this pile. A card landing ON a Quick Bury top fires nothing; a
        // saved landing still lands the carrier (the v6.57 rule) so it
        // fires; a fatal landing never reaches here.
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
        // Tell: arm a DIRECTIONAL hint for the NEXT draw on this pile.
        if drawn.stickers.contains(where: { $0.type == "tell" }) {
            run.tellPiles.insert(index)
            recT("sticker", "tell", "Tell", ["peeks": 1])
        }
        maybeLandingBonus(index, drawn)
        maybeExpansionStickers(index, current, drawn, col)
        maybeStickerTribute(index, drawn)
        maybeStickerActions(index, drawn)
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
                // +value if it's the SOLE Pillar on the board (a second
                // Pillar anywhere — even another Greedy — voids it). No
                // survival condition.
                if pillarsOnBoard == 1 {
                    bonus += t.value
                    lines.append(PayoutLine(label: t.label, detail: "only Pillar on the board", amount: t.value, col: col))
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
            killingCard: killing, recycleCount: board.pileSize(idx) + 1)
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
