import Foundation

/// CURSE BEHAVIORS (v6.48) — the engine half of the curse overhaul. Every
/// cursed sticker's board effect lives here; the landing-time ones run from
/// ONE chokepoint (`curseTouch`) called wherever a drawn card physically
/// lands on a pile top (correct landing, Same-Charge save, death landing),
/// so "on landing" means the same thing for every curse. State-reading
/// curses (mute / magnet / jammer / flatline / shrink) are pure queries the
/// rules and the UI both ask.
extension GameEngine {

    func hasCurse(_ card: LiveCard?, _ behavior: String) -> Bool {
        guard let card else { return false }
        return card.stickers.contains { stickerTypes.get($0.type)?.behavior == behavior }
    }

    // MARK: - The shared weighted curse roll (v6.76 Devil's Deal)

    /// Every cursed sticker that can stick on THIS card: the GLOBAL
    /// sticker-application gate (Joker/Blank, the sticker cap, no duplicate
    /// type, suit restrictions) minus any curse whose `curseExclude` names one
    /// of the card's EXISTING sticker types (the web's
    /// `cursedStickerPoolFor`).
    func cursedStickerPoolFor(_ card: LiveCard?) -> [ItemDef] {
        guard let card else { return [] }
        return data.items.stickers.filter { t in
            guard t.cursed, CardRules.stickerEligible(card, t.id, data: data) else { return false }
            return !card.stickers.contains { t.curseExclude.contains($0.type) }
        }
    }

    /// ONE seeded draw over the card's curse pool, weighted by `curseWeight`
    /// (default 1). nil when nothing can stick (the web's
    /// `rollCursedStickerType`).
    func rollCursedStickerType(_ card: LiveCard?) -> ItemDef? {
        let pool = cursedStickerPoolFor(card)
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

    // MARK: - Top-card state curses

    /// MUTE: Same cannot be called on a pile whose top carries it.
    public func pileMuted(_ index: Int) -> Bool {
        board.isActive(index) && hasCurse(board.top(index), "mute")
    }

    /// MAGNET: alive piles whose top is a magnet. While nonempty, the next
    /// guess must target one of them. RULE (two magnets up at once): the
    /// player chooses among the magnet piles — any one satisfies the pull.
    /// Dead piles drop out; an empty set means no constraint.
    public func magnetPiles() -> [Int] {
        (0..<board.size).filter { board.isActive($0) && hasCurse(board.top($0), "magnet") }
    }

    /// JAMMER: a jammer top on any ALIVE pile in the column knocks the
    /// column's pillar out. resolvePillarDef gates on this, so every pillar
    /// read (fires, payout, size hooks) shares one truth.
    func columnJammed(_ col: Int?) -> Bool {
        guard let col else { return false }
        return colAlivePiles(col).contains { hasCurse(board.top($0), "jammer") }
    }

    // MARK: - Landing-time curses

    /// The one landing chokepoint: `drawn` just landed on `current` at
    /// `index`. Runs the touch curses (both directions) and the on-landing
    /// drains. Called AFTER the push, from the CORRECT landing branches only
    /// (the plain correct guess and the malfunction kill, whose guess was
    /// correct). v6.52: the fatal and Same-Charge-save branches no longer
    /// call it — landing effects fire only when the card lands correctly.
    func curseTouch(index: Int, current: LiveCard, drawn: LiveCard) {
        // PEELER (v6.91, cover-only): the card that LANDS ON a peeler loses
        // its stickers, curses included. A landing peeler strips nothing —
        // the bidirectional clause retired with the rework.
        if hasCurse(current, "peeler") { peelAll(index: index, from: drawn) }

        // SHIELD DRAIN: the banked Same Charge empties (no charge, no effect).
        if hasCurse(drawn, "drainShield"), sameCharge {
            sameCharge = false
            logLine("Shield Drain: the Same Shield empties")   // v6.96 rename
            emit(.curseFired(index: index, curse: "drainShield", label: "Shield Drain",
                             detail: "SHIELD DRAINED"))
            recT("sticker", "drainShield", "Shield Drain", ["fires": 1])
        }

        // BASE DRAIN: the column's charged Base is spent for the deal.
        if hasCurse(drawn, "drainBase"), let col = run.pileColumns?[index],
           run.bases?[safe: col] ?? nil != nil, run.basesUsed?[safe: col] == false {
            run.basesUsed?[col] = true
            logLine("Base Drain: the column's Base is spent")
            emit(.curseFired(index: index, curse: "drainBase", label: "Base Drain",
                             detail: "BASE DRAINED"))
            recT("sticker", "drainBase", "Base Drain", ["fires": 1])
        }

        // SPOILER: bonus coins earned this deal reset to 0. The wipe is an
        // itemized negative line, so the tally still sums truthfully.
        if hasCurse(drawn, "spoiler"), run.bonusCoins > 0 {
            let wiped = run.bonusCoins
            run.bonusCoins = 0
            run.bonusEvents.add("Spoiler", -wiped)
            logLine("Spoiler: \(jsNum(wiped)) bonus coins rot away")
            emit(.curseFired(index: index, curse: "spoiler", label: "Spoiler",
                             detail: "BONUS SPOILED"))
            recT("sticker", "spoiler", "Spoiler", ["coins": -wiped])
        }

        // SABOTEUR: `chance` to destroy the column's Base or Pillar (random
        // between whichever exist). The engine clears its own copy and emits;
        // the flow makes it stick on the campaign, like static volatility.
        // The roll only happens while a target exists, and reports its
        // HIT/MISS (v6.57).
        if hasCurse(drawn, "saboteur"), let col = run.pileColumns?[index] {
            let t = stickerTypes.all().first { $0.behavior == "saboteur" }
            var targets: [(kind: String, id: String)] = []
            if let pid = run.pillars?[safe: col] ?? nil { targets.append(("pillar", pid)) }
            if let bid = run.bases?[safe: col] ?? nil { targets.append(("base", bid)) }
            if !targets.isEmpty,
               rollChance("sticker", t?.id ?? "saboteur", t?.label ?? "Saboteur",
                          t?.num("chance", 0.1) ?? 0.1, index: index, col: col) {
                let victim = targets[rng.index(targets.count)]
                if victim.kind == "pillar" { run.pillars?[col] = nil }
                else { run.bases?[col] = nil }
                logLine("Saboteur: the column's \(victim.kind) is destroyed")
                emit(.sabotaged(col: col, kind: victim.kind, itemId: victim.id))
                recT("sticker", "saboteur", "Saboteur", ["destroyed": 1])
            }
        }
    }

    /// Strip every sticker from a live card and reset the flags they
    /// projected. The flow hears `.cursePeeled` and removes the same
    /// stickers from the card's campaign identity, so the peel is permanent.
    private func peelAll(index: Int, from card: LiveCard) {
        guard !card.stickers.isEmpty else { return }
        let types = card.stickers.map(\.type)
        card.stickers = []
        card.tieSafe = false
        card.wildSuit = false
        card.revealNext = false
        card.suitGuards = []
        logLine("Peeler: \(types.count) sticker\(types.count == 1 ? "" : "s") torn off \(cardName(card))")
        emit(.cursePeeled(index: index, cardId: card.id, types: types))
        recT("sticker", "peeler", "Peeler", ["peeled": Double(types.count)])
    }

    /// MALFUNCTION: guessing correctly AGAINST a malfunction top card rolls
    /// `chance` that the card blows the pile anyway. The guess stays counted
    /// as correct (it was); the pile still dies, past every save. The roll
    /// reports its HIT/MISS (v6.57).
    /// MALFUNCTION (v6.99): rolls when the CARRIER lands — the sticker
    /// template's rule (an effect belongs to the card that wears it), not
    /// the old landed-upon read. A curse a conversion appended DURING this
    /// landing is dormant (the freshCurses ledger — Leech/Trapdoor's rule);
    /// pre-existing duplicates each roll once.
    func malfunctionTriggers(drawn: LiveCard, index: Int, col: Int?) -> Bool {
        guard let t = stickerTypes.all().first(where: { $0.behavior == "malfunction" }) else { return false }
        var fresh = run.freshCurses
        var rolls = 0
        for s in drawn.stickers where stickerTypes.get(s.type)?.behavior == "malfunction" {
            if let at = fresh.firstIndex(where: { $0.cardId == drawn.id && $0.type == s.type }) {
                fresh.remove(at: at)   // dormant on the landing that created it
                continue
            }
            rolls += 1
        }
        for _ in 0..<rolls {
            if rollChance("sticker", t.id, t.label, t.num("chance", 0.1),
                          index: index, col: col) { return true }
        }
        return false
    }
}
