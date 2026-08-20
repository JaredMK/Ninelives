import XCTest
@testable import GameCore

/// MAP CARD STICKERS + the loot-badge geometry (v6.68).
///
/// Stickers: every FACE-UP card on the map — a +1 pickup node's locked card
/// and each card of a revealed +2 pack's committed pair — rolls the map
/// distribution the moment it locks: 75% bare / 20% one / 4% two / 1% three,
/// and each rolled sticker is a CURSE 5% of the time (the shared weighted
/// `rollCurse` pick, path "map"). The roll rides its own keyed substream
/// (runSeed, "mapsticker", nodeId[, slot]) so a reload replays exactly.
/// Deck overrides: Mr. Garden (stickerEverything) keeps his coat — the
/// distribution never stacks on top; Rocko (noStickers) takes no stickers
/// of any kind from this feature.
///
/// Badge geometry: the two-row loot badge is hard-capped at 56pt canvas
/// width (MapArt.lootBadgeMaxWidth) versus the 60pt minimum centre-to-centre
/// spacing the map layout allows same-row nodes, so adjacent pack badges can
/// never collide. The layout invariant is re-stated and checked here against
/// real generated maps (the RenderingTests idiom: the app-target constants
/// live outside this bundle, so the test pins the rule independently).
final class MapCardStickerTests: XCTestCase {

    private func climb(_ deck: String, seed: UInt32) -> CampaignState {
        let c = CampaignState(store: MemoryStore())
        c.setDeck(deck); c.setSeedOverride(seed); c.reset()
        return c
    }

    /// Every face-up map card with a stable per-slot key: the +1 pickup
    /// nodes' locked cards and the revealed +2 packs' committed pairs.
    /// Jokers/Blanks (and the sentinel ids) carry no stickers by rule and
    /// are excluded up front.
    private func faceUpMapCards(_ c: CampaignState) -> [(key: String, card: CardSpec)] {
        guard let m = c.runMap else { return [] }
        var out: [(String, CardSpec)] = []
        for n in m.nodes where n.type == "pickup" {
            guard let card = c.previewPickupCard(n), !card.joker, !card.blank else { continue }
            out.append(("n\(n.id)", card))
        }
        for n in m.nodes where n.type == "pack" && n.addOf == 2 {
            for (slot, id) in (c.commitPackCards(n) ?? []).enumerated() {
                guard let card = c.findById(id), !card.joker, !card.blank else { continue }
                out.append(("n\(n.id)s\(slot)", card))
            }
        }
        return out
    }

    // MARK: - The distribution (pink — no deck override in play)

    func testStickerCountDistributionAndCurseShare() {
        var counts = [0, 0, 0, 0]          // cards carrying 0/1/2/3 stickers
        var rolled = 0, cursed = 0
        for i in 1...40 {
            let c = climb("pink", seed: UInt32(i * 7919 + 13))
            for (_, card) in faceUpMapCards(c) {
                counts[min(3, card.stickers.count)] += 1
                rolled += card.stickers.count
                cursed += card.stickers.filter {
                    GameData.shared.stickerTypes.get($0.type)?.cursed == true
                }.count
            }
        }
        let total = counts.reduce(0, +)
        XCTAssertGreaterThan(total, 300, "the seed sample yields a real population")
        // 75 / 20 / 4 / 1 within ±5 points. (An eligibility miss can only
        // push a card DOWN a bucket and is rare — well inside the tolerance.)
        let expect = [0.75, 0.20, 0.04, 0.01]
        for (i, e) in expect.enumerated() {
            XCTAssertEqual(Double(counts[i]) / Double(total), e, accuracy: 0.05,
                           "cards with \(i) sticker(s): \(counts[i]) of \(total)")
        }
        // ~5% of rolled stickers are curses — very wide tolerance (the
        // population of rolled stickers is only a few hundred).
        XCTAssertGreaterThan(rolled, 50, "stickers actually rolled")
        XCTAssertGreaterThan(cursed, 0, "the curse branch is reachable")
        XCTAssertEqual(Double(cursed) / Double(rolled), 0.05, accuracy: 0.045,
                       "curse share: \(cursed) of \(rolled)")
    }

    // MARK: - Determinism

    func testSameSeedRollsTheSameStickers() {
        for seed: UInt32 in [123_456, 42, 20_260_820] {
            let sig: (CampaignState) -> [String] = { c in
                self.faceUpMapCards(c).map { key, card in
                    "\(key):\(card.suit)\(card.currentRank):" + card.stickers.map(\.type).joined(separator: ",")
                }
            }
            let a = sig(climb("pink", seed: seed))
            let b = sig(climb("pink", seed: seed))
            XCTAssertFalse(a.isEmpty, "seed \(seed): face-up cards exist")
            XCTAssertEqual(a, b, "seed \(seed): a reload shows the same stickers")
        }
    }

    // MARK: - Deck overrides

    func testGardenEveryFaceUpMapCardCarriesASticker() {
        for seed: UInt32 in [7, 99, 4242] {
            let c = climb("garden", seed: seed)
            let cards = faceUpMapCards(c)
            XCTAssertFalse(cards.isEmpty, "seed \(seed): face-up cards exist")
            for (key, card) in cards {
                XCTAssertGreaterThanOrEqual(card.stickers.count, 1,
                                            "seed \(seed) \(key): Garden's coat left a map card bare")
            }
        }
    }

    func testRockoTakesNoMapStickersNotEvenCurses() {
        for seed: UInt32 in [7, 99, 4242] {
            let c = climb("rocko", seed: seed)
            let cards = faceUpMapCards(c)
            XCTAssertFalse(cards.isEmpty, "seed \(seed): face-up cards exist")
            for (key, card) in cards {
                XCTAssertTrue(card.stickers.isEmpty,
                              "seed \(seed) \(key): Rocko map card carries \(card.stickers.map(\.type))")
            }
        }
    }

    // MARK: - Badge geometry

    /// Re-states MapViewController's layout constants + buildLayout gap math
    /// (mapW 348, pad 46, minGap 60): per row, nodes sort by generator x,
    /// map to pad + x·(mapW − 2·pad), get pushed right to ≥ minGap apart,
    /// then the whole row shifts UNIFORMLY to re-centre (a uniform shift
    /// preserves every gap). The minimum adjacent centre-to-centre distance
    /// any generated map can produce is therefore exactly minGap.
    private func adjacentGaps(_ c: CampaignState) -> (all: [Double], packPack: [Double]) {
        let mapW = 348.0, pad = 46.0, minGap = 60.0
        guard let m = c.runMap else { return ([], []) }
        let usable = mapW - 2 * pad, lo = pad
        var byRow: [Int: [MapNode]] = [:]
        for n in m.nodes { byRow[n.row, default: []].append(n) }
        var all: [Double] = [], packPack: [Double] = []
        for (_, rowNodes) in byRow where rowNodes.count > 1 {
            let row = rowNodes.sorted { $0.x < $1.x }
            var px = row.map { lo + Double($0.x) * usable }
            for i in 1..<px.count where px[i] < px[i - 1] + minGap { px[i] = px[i - 1] + minGap }
            for i in 1..<px.count {
                let gap = px[i] - px[i - 1]
                all.append(gap)
                if row[i].type == "pack" && row[i - 1].type == "pack" { packPack.append(gap) }
            }
        }
        return (all, packPack)
    }

    func testLootBadgeNeverCollidesAtGeneratorSpacing() {
        // MapArt.lootBadgeMaxWidth, re-stated (the app target is outside this
        // bundle): the badge canvas — shadow included — never exceeds 56pt.
        let badgeMaxWidth = 56.0
        let minGap = 60.0
        var sawPackNeighbours = false
        var worst = Double.infinity
        for i in 1...30 {
            let c = climb("pink", seed: UInt32(i * 104_729 + 7))
            let gaps = adjacentGaps(c)
            for g in gaps.all {
                worst = min(worst, g)
                XCTAssertGreaterThanOrEqual(g + 1e-9, minGap,
                                            "layout invariant: same-row nodes ≥ minGap apart")
            }
            if !gaps.packPack.isEmpty { sawPackNeighbours = true }
            for g in gaps.packPack {
                XCTAssertGreaterThanOrEqual(g + 1e-9, badgeMaxWidth,
                                            "adjacent pack badges must clear each other")
            }
            // The badge's count row stays ≤ 3 monospace chars ("+99"), the
            // width bound the 56pt cap was computed from.
            for n in (c.runMap?.nodes ?? []) where n.type == "pack" {
                XCTAssertLessThanOrEqual(n.packCount ?? 3, 99, "count fits the badge")
                XCTAssertLessThanOrEqual(c.packSuits(for: n).count, 4, "suit marks are deduped")
            }
        }
        XCTAssertTrue(sawPackNeighbours, "the sample exercised side-by-side pack nodes")
        // The guarantee itself: worst generator-legal spacing still fits the
        // capped badge with air to spare.
        XCTAssertGreaterThanOrEqual(worst, badgeMaxWidth,
                                    "badge cap \(badgeMaxWidth) vs tightest gap \(worst)")
    }
}
