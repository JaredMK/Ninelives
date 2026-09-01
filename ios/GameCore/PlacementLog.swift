import Foundation

/// THE PLACEMENT-DECISION LOG (v6.84) — dev tooling only, like the
/// DebugEventLog beside it. Records every PLAYER sticker placement (the
/// picker flows through `CampaignState.applySticker` — engine-side random
/// grants choose nothing and are not decisions) so playtests can answer:
/// which stickers ever involve a real choice of card, and which are placed
/// on autopilot because every eligible home is the same?
///
/// GATING: every entry point checks `isOn` (the debug-access flag the 🐞
/// panel toggles, persisted under "debugAccess"). Off — the shipping
/// default — nothing is computed, nothing is written, no file exists.
/// NEUTRALITY: recording is a pure READ of campaign state (no rng draw, no
/// mutation), called before the apply mutates the card, so gameplay is
/// byte-identical with the log on or off (pinned by PlacementLogTests).
///
/// WHERE IT WRITES, in two forms per placement:
/// - One human-readable `PLACE|k=v|…` line into the on-screen DebugEventLog
///   (visible/copyable in the 🐞 panel's Event log box).
/// - One JSON object per line (NDJSON) appended to
///   `Documents/placement-log.ndjson` — durable ACROSS runs and app
///   launches, sized for many playtests. Pull it from the 🐞 panel's COPY
///   button, or Xcode ▸ Window ▸ Devices ▸ (device) ▸ Download Container.
///
/// THE "meaningful" HEURISTIC, transparent by design: a placement offered a
/// real choice iff some AXIS the sticker or an equipped item cares about
/// DIFFERS across the eligible cards. Axes are derived mechanically:
/// - The sticker's own axis: rank stickers (kind "rank", Random Rank,
///   Same-Safe) care about RANK; suit-changers (Change to X, Random Suit,
///   Wild Suit) care about the card's current SUIT; Collector cares about
///   the card's STICKER LOAD. Other stickers fire identically wherever they
///   ride — no intrinsic axis.
/// - Equipped pillars/bases/Same-Power add axes: an item whose effect keys
///   on rank (Rank Shield, Crazy Eights, Prime…) adds RANK; one keyed on a
///   suit (Heart Bonus, Scarce Suit, Diamond Boost…) adds SUIT. The tables
///   below are the whole judgment — auditable, and every record logs which
///   item contributed each axis plus the distinct-value counts, so the
///   verdict can be re-derived by hand from its own inputs.
/// Unknown effects contribute no axis (conservative: the log under-claims
/// meaningfulness rather than inventing it).
public enum PlacementLog {

    public static var isOn: Bool { UserDefaults.standard.bool(forKey: "debugAccess") }

    // MARK: - Origin notes (debug-only, transient — never persisted)

    /// Last-known acquisition source per sticker type ("store", "pack",
    /// "mystery", "joker", "debug"). Best-effort: with two copies of one
    /// type from different sources the later note wins — the record says so
    /// by prefixing "~" when more than one copy was noted.
    private static var origins: [String: (source: String, copies: Int)] = [:]

    public static func noteOrigin(_ typeId: String, _ source: String) {
        guard isOn else { return }
        let prior = origins[typeId]
        origins[typeId] = (source, (prior?.copies ?? 0) + 1)
    }

    static func originLabel(_ typeId: String) -> String {
        guard let o = origins[typeId] else { return "unknown" }
        return o.copies > 1 ? "~\(o.source)" : o.source
    }

    // MARK: - The record

    /// Called from `CampaignState.applySticker` AFTER its guards pass and
    /// BEFORE the card mutates — so the eligible set and the chosen card's
    /// sticker list are the pre-placement truth the player actually saw.
    static func record(campaign: CampaignState, typeId: String, chosenId: Int,
                       source: String?) {
        guard isOn, let def = GameData.shared.stickerTypes.get(typeId) else { return }
        let deck = campaign.getRunDeck()
        let eligible = deck.filter { campaign.canApplySticker($0, typeId) }
        guard let chosen = eligible.first(where: { $0.id == chosenId }) else { return }

        // Equipped loadout at the moment of choice.
        let pillars = campaign.columnPillars.map { $0 ?? "-" }
        let bases = campaign.columnBases.map { $0 ?? "-" }
        let power = campaign.getSamePower() ?? "-"

        // Axes + verdict.
        var axes: [(axis: String, from: String)] = stickerAxes(def)
        for id in (campaign.columnPillars.compactMap { $0 }) {
            if let d = GameData.shared.pillarTypes.get(id) { axes += equippedAxes(d) }
        }
        for id in (campaign.columnBases.compactMap { $0 }) {
            if let d = GameData.shared.baseTypes.get(id) { axes += equippedAxes(d) }
        }
        if let d = GameData.shared.samePowerTypes.get(campaign.getSamePower() ?? "") {
            axes += equippedAxes(d)
        }
        let ranks = Set(eligible.filter { !$0.joker && !$0.blank }.map(\.currentRank))
        let suits = Set(eligible.filter { !$0.joker && !$0.blank }.map(\.suit))
        let loads = Set(eligible.map { $0.stickers.count })
        let activeAxes = Set(axes.map(\.axis))
        var reasons: [String] = []
        if activeAxes.contains("rank"), ranks.count > 1 { reasons.append("rank differs (\(ranks.count) ranks)") }
        if activeAxes.contains("suit"), suits.count > 1 { reasons.append("suit differs (\(suits.count) suits)") }
        if activeAxes.contains("load"), loads.count > 1 { reasons.append("sticker load differs") }
        let meaningful = !reasons.isEmpty
        let why = meaningful ? reasons.joined(separator: "; ")
            : activeAxes.isEmpty ? "no axis cared (sticker fires the same anywhere; no equipped item keys on rank/suit)"
            : "cared axes (\(activeAxes.sorted().joined(separator: ","))) uniform across eligible"

        func cardTag(_ c: CardSpec) -> String {
            let r = c.joker ? "★" : c.blank ? "∅"
                : (DeckManager.ranks.first { $0.value == c.currentRank }?.label ?? "\(c.currentRank)")
            let stk = c.stickers.map(\.type).joined(separator: ",")
            return "\(c.id):\(r)\(c.joker || c.blank ? "" : c.suit)[\(stk)]"
        }

        // The on-screen line (compact, one line, pipe-delimited).
        let src = source ?? originLabel(typeId)
        let axesText = axes.isEmpty ? "-" : axes.map { "\($0.axis)<\($0.from)" }.joined(separator: "+")
        DebugEventLog.shared.add(
            "PLACE|sticker=\(typeId)|name=\(def.label)|source=\(src)"
            + "|chosen=\(cardTag(chosen))"
            + "|eligible=\(eligible.map(cardTag).joined(separator: ";"))"
            + "|pillars=\(pillars.joined(separator: ","))|bases=\(bases.joined(separator: ","))|power=\(power)"
            + "|axes=\(axesText)|ranks=\(ranks.count)|suits=\(suits.count)|loads=\(loads.count)"
            + "|meaningful=\(meaningful ? "yes" : "no")|why=\(why)")

        // The durable NDJSON record.
        var obj: [String: JSONValue] = [
            "t": .string(Self.stamp.string(from: Date())),
            "sticker": .string(typeId), "name": .string(def.label),
            "source": .string(src),
            "chosen": cardJSON(chosen),
            "eligible": .array(eligible.map(cardJSON)),
            "pillars": .array(pillars.map { .string($0) }),
            "bases": .array(bases.map { .string($0) }),
            "power": .string(power),
            "axes": .array(axes.map { .object(["axis": .string($0.axis), "from": .string($0.from)]) }),
            "distinctRanks": .number(Double(ranks.count)),
            "distinctSuits": .number(Double(suits.count)),
            "distinctLoads": .number(Double(loads.count)),
            "eligibleCount": .number(Double(eligible.count)),
            "meaningful": .bool(meaningful),
        ]
        obj["why"] = .string(why)
        appendToFile(obj)
    }

    private static func cardJSON(_ c: CardSpec) -> JSONValue {
        .object(["id": .number(Double(c.id)),
                 "rank": .number(Double(c.currentRank)),
                 "suit": .string(c.joker ? "★" : c.blank ? "∅" : c.suit),
                 "stickers": .array(c.stickers.map { .string($0.type) })])
    }

    // MARK: - The axis tables (the whole heuristic, in one auditable place)

    /// The sticker's OWN axis, from its def.
    static func stickerAxes(_ def: ItemDef) -> [(axis: String, from: String)] {
        if def.kind == "rank" { return [("rank", "sticker:\(def.id)")] }
        switch def.behavior {
        case "randomFixedValue", "tieSafe": return [("rank", "sticker:\(def.id)")]
        case "changeSuitTo", "changeSuitRandom", "wildSuit": return [("suit", "sticker:\(def.id)")]
        case "collector": return [("load", "sticker:\(def.id)")]
        // v6.85 CONDITIONALS: the carrier's suit IS the bet, so placement
        // reads the suit axis by definition.
        case "quickBury", "gainCoin", "donate", "heavy", "diamondSnob", "tell", "suitImmunity":
            return [("suit", "sticker:\(def.id)")]
        // v6.90: the Same stickers joined the RANK conditional — placement
        // reads the rank axis by definition now.
        case "rechargeSameShield", "activateSamePower":
            return [("rank", "sticker:\(def.id)")]
        default: return []
        }
    }

    /// Rank-keyed equipped effects: the item's behavior depends on card RANKS,
    /// so a rank sticker's home (or a card's rank) interacts with it.
    private static let rankEffects: Set<String> = [
        "rankShield", "startPileSizeEight", "eightTell", "royalSafeNoTwos",
        "rankBury", "rankCoin", "prime", "wildAces", "purgeRank", "chorus",
        "rankFlood", "setValue", "clubZeroRanksBury", "diamondDupeSize",
        "highestHeart", "queensEye", "heartZeroRanksCoin", "diamondZeroRanksSize",
    ]
    /// Suit-keyed equipped effects (plus any def carrying a `suit` field).
    private static let suitEffects: Set<String> = [
        "suitShieldDaily", "suitMajoritySafe", "absentSuitClubBury",
        "heavyDiamond", "diamondAnchor", "diamondDistribution",
        "diamondDupeSize", "shuffler", "clubTribute", "clubThin",
        "clubZeroRanksBury", "excavator", "highestHeart", "heartPiles",
        "allSuitTop", "kamikaze", "spadePeek", "clubTell", "heartDemolish",
        "diamondBoost", "setSuit", "suitDig", "curseBuryPeek", "queensEye",
        "linkBury", "pauperHeartTell", "heartZeroRanksCoin", "diamondZeroRanksSize",
    ]

    static func equippedAxes(_ def: ItemDef) -> [(axis: String, from: String)] {
        var out: [(String, String)] = []
        let e = def.effect ?? ""
        // The sameTolerance family splits by its `tol` rule.
        if e == "sameTolerance" {
            if def.tol == "sameSuit" { out.append(("suit", "equipped:\(def.id)")) }
            else { out.append(("rank", "equipped:\(def.id)")) }
            return out
        }
        if rankEffects.contains(e) { out.append(("rank", "equipped:\(def.id)")) }
        if suitEffects.contains(e) || def.suit != nil { out.append(("suit", "equipped:\(def.id)")) }
        return out
    }

    // MARK: - The durable file

    public static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("placement-log.ndjson")
    }

    private static func appendToFile(_ obj: [String: JSONValue]) {
        guard let data = try? JSONEncoder().encode(JSONValue.object(obj)) else { return }
        var line = data
        line.append(0x0A)
        let url = fileURL
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: url)
        }
    }

    public static func fileText() -> String {
        (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }
    public static func recordCount() -> Int {
        fileText().split(separator: "\n", omittingEmptySubsequences: true).count
    }
    public static func clearFile() {
        try? FileManager.default.removeItem(at: fileURL)
    }
    /// Test hook: forget the transient origin notes.
    public static func resetOrigins() { origins = [:] }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
}
