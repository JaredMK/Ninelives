import XCTest
@testable import GameCore

/// PACK CARD STICKERS + STARTING-DECK PURITY + the loot-badge geometry.
///
/// Stickers (v6.73): NOTHING on the map dresses — +1 pickup faces and
/// revealed +2 pairs ride bare. Only a SEALED pack's contents roll as they
/// are granted, off the items.js `packStickerOdds` table (75% bare / 20% one
/// / 4% two / 1% three — v6.74: read from the data file, not hardcoded), and
/// each rolled sticker is a CURSE 5% of the time (the shared weighted
/// `rollCurse` pick, path "map"). The roll rides its own keyed substream
/// (runSeed, "packsticker", nodeId, slot) so a reload replays exactly.
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

    private func climb(_ deck: String, tier: String, seed: UInt32) -> CampaignState {
        let c = CampaignState(store: MemoryStore())
        c.setDeck(deck); c.setTier(tier); c.setSeedOverride(seed); c.reset()
        return c
    }

    /// v6.73 SPLIT: MAP cards (+1 pickup nodes) carry NO stickers — that roll
    /// was reverted; PACK CONTENTS (the revealed +2 committed pairs) keep the
    /// 75/20/4/1 distribution. Jokers/Blanks (and the sentinel ids) carry no
    /// stickers by rule and are excluded up front.
    private func mapPickupCards(_ c: CampaignState) -> [(key: String, card: CardSpec)] {
        guard let m = c.runMap else { return [] }
        var out: [(String, CardSpec)] = []
        for n in m.nodes where n.type == "pickup" {
            guard let card = c.previewPickupCard(n), !card.joker, !card.blank else { continue }
            out.append(("n\(n.id)", card))
        }
        return out
    }

    private func packPairCards(_ c: CampaignState) -> [(key: String, card: CardSpec)] {
        guard let m = c.runMap else { return [] }
        var out: [(String, CardSpec)] = []
        for n in m.nodes where n.type == "pack" && n.addOf == 2 {
            for (slot, id) in (c.commitPackCards(n) ?? []).enumerated() {
                guard let card = c.findById(id), !card.joker, !card.blank else { continue }
                out.append(("n\(n.id)s\(slot)", card))
            }
        }
        return out
    }

    /// SEALED packs (+3/+4/+5) grant their contents at resolution — this is
    /// where the 75/20/4/1 roll lives now (nothing on the map is dressed).
    private func sealedPackGrants(_ c: CampaignState) -> [(key: String, card: CardSpec)] {
        guard let m = c.runMap else { return [] }
        var out: [(String, CardSpec)] = []
        for n in m.nodes where n.type == "pack" && n.addOf > 2 {
            for (i, card) in c.resolvePack(n).enumerated() where !card.joker && !card.blank {
                out.append(("n\(n.id)g\(i)", card))
            }
        }
        return out
    }

    /// Both kinds, for the deck-override checks (Garden's coat covers all).
    private func faceUpMapCards(_ c: CampaignState) -> [(key: String, card: CardSpec)] {
        mapPickupCards(c) + packPairCards(c)
    }

    // MARK: - v6.73 revert: MAP cards ride bare

    func testMapPickupCardsCarryNoStickersOrCurses() {
        for seed: UInt32 in [11, 4242, 987_654] {
            let c = climb("pink", seed: seed)
            let cards = faceUpMapCards(c)   // +1 faces AND revealed +2 pairs
            XCTAssertFalse(cards.isEmpty, "seed \(seed): face-up map cards exist")
            for (key, card) in cards {
                XCTAssertTrue(card.stickers.isEmpty,
                              "seed \(seed) \(key): a MAP card carries stickers (the v6.71 roll was reverted)")
            }
        }
    }

    /// v6.86 (batch item 11): sealed-pack cards may arrive DRESSED — but
    /// never with an identity-MUTATING sticker (suit changers, ±rank,
    /// random rank). Wild Suit and plain stickers stay possible.
    func testSealedPackCardsNeverPreCarryMutatingStickers() {
        for seed: UInt32 in [11, 4242, 987_654] {
            let c = climb("pink", seed: seed)
            for (key, card) in sealedPackGrants(c) {
                let dressed = c.baseDeck.first { $0.id == card.id } ?? card
                for s in dressed.stickers {
                    XCTAssertFalse(GameData.shared.stickerTypes.get(s.type)?.mutatesCardIdentity ?? false,
                                   "seed \(seed) \(key): pack card pre-carried mutating '\(s.type)'")
                }
            }
        }
    }

    /// …and the draft POOL stays clean at generation: the pre-v6.73 bug rolled
    /// stickers onto unclaimed baseDeck cards while committing +2 pairs, so a
    /// fresh Pinky climb opened with a stickered pool.
    func testGenerationLeavesTheDraftPoolClean() {
        for seed: UInt32 in [1, 555, 4242] {
            let c = climb("pink", seed: seed)
            for card in c.baseDeck {
                XCTAssertTrue(card.stickers.isEmpty,
                              "seed \(seed): pool card \(card.id) dressed at generation")
            }
        }
    }

    // MARK: - The distribution (pink — no deck override in play)

    func testStickerCountDistributionAndCurseShare() {
        var counts = [0, 0, 0, 0]          // cards carrying 0/1/2/3 stickers
        var rolled = 0, cursed = 0
        // v6.73: the distribution lives on PACK CONTENTS only — the pair
        // population is smaller than the old pickups+pairs sweep, so more
        // seeds keep the sample honest.
        for i in 1...90 {
            let c = climb("pink", seed: UInt32(i * 7919 + 13))
            for (_, card) in sealedPackGrants(c) {
                counts[min(3, card.stickers.count)] += 1
                rolled += card.stickers.count
                cursed += card.stickers.filter {
                    GameData.shared.stickerTypes.get($0.type)?.cursed == true
                }.count
            }
        }
        let total = counts.reduce(0, +)
        XCTAssertGreaterThan(total, 250, "the seed sample yields a real population")
        // 75 / 20 / 4 / 1 within ±5 points. (An eligibility miss can only
        // push a card DOWN a bucket and is rare — well inside the tolerance.)
        let expect = [0.75, 0.20, 0.04, 0.01]
        for (i, e) in expect.enumerated() {
            XCTAssertEqual(Double(counts[i]) / Double(total), e, accuracy: 0.05,
                           "cards with \(i) sticker(s): \(counts[i]) of \(total)")
        }
        // ~5% of rolled stickers are curses — very wide tolerance (the
        // population of rolled stickers is only a few hundred).
        XCTAssertGreaterThan(rolled, 40, "stickers actually rolled")
        XCTAssertGreaterThan(cursed, 0, "the curse branch is reachable")
        XCTAssertEqual(Double(cursed) / Double(rolled), 0.05, accuracy: 0.05,
                       "curse share: \(cursed) of \(rolled)")
    }

    // MARK: - Determinism

    func testSameSeedRollsTheSameStickers() {
        for seed: UInt32 in [123_456, 42, 20_260_820] {
            let sig: (CampaignState) -> [String] = { c in
                self.sealedPackGrants(c).map { key, card in
                    "\(key):\(card.suit)\(card.currentRank):" + card.stickers.map(\.type).joined(separator: ",")
                }
            }
            let a = sig(climb("pink", seed: seed))
            let b = sig(climb("pink", seed: seed))
            XCTAssertFalse(a.isEmpty, "seed \(seed): sealed packs exist")
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

    // MARK: - Starting-deck purity (v6.74) — per character, both tiers, seed sweep

    /// The v6.73 map-card leak is gone: a FRESH climb's starting hand must
    /// open exactly as the deck's rules say — and no deck's rules dress the
    /// starting hand except Mr. Garden's coat. Swept per character × tier ×
    /// seed so a leak that needs a specific roll can't slip through.
    private let startingDeckSeeds: [UInt32] = [1, 7, 42, 555, 4242, 987_654, 20_260_820, 3_000_000_001]
    private let bothTiers = ["regular", "legendary"]

    func testPlainDecksStartWithZeroStickersAndZeroCurses() {
        for deck in ["pink", "mamma", "slyrex", "rocko"] {
            for tier in bothTiers {
                for seed in startingDeckSeeds {
                    let c = climb(deck, tier: tier, seed: seed)
                    let hand = c.getRunDeck()
                    XCTAssertFalse(hand.isEmpty, "\(deck)/\(tier) seed \(seed): no starting hand")
                    for card in hand {
                        XCTAssertTrue(card.stickers.isEmpty,
                                      "\(deck)/\(tier) seed \(seed): starting card \(card.id) "
                                      + "carries \(card.stickers.map(\.type))")
                    }
                    // The draft POOL behind the hand stays clean too — the
                    // pre-v6.73 leak dressed unclaimed pool cards at
                    // generation, which is how a stickered start happened.
                    for card in c.baseDeck {
                        XCTAssertTrue(card.stickers.isEmpty,
                                      "\(deck)/\(tier) seed \(seed): pool card \(card.id) dressed at generation")
                    }
                }
            }
        }
    }

    /// MR. GARDEN's override: `stickerEverything` dresses the ENTIRE draft
    /// pool at generation (v6.67, by design) — so every card of his starting
    /// hand wears a sticker. The coat draws from grantableStickers only, so
    /// a curse can never be part of it.
    func testGardenStartsEveryCardStickeredNeverCursed() {
        for tier in bothTiers {
            for seed in startingDeckSeeds {
                let c = climb("garden", tier: tier, seed: seed)
                let hand = c.getRunDeck()
                XCTAssertFalse(hand.isEmpty, "garden/\(tier) seed \(seed): no starting hand")
                for card in hand {
                    XCTAssertGreaterThanOrEqual(card.stickers.count, 1,
                                                "garden/\(tier) seed \(seed): the coat left card \(card.id) bare")
                    for s in card.stickers {
                        XCTAssertNotEqual(GameData.shared.stickerTypes.get(s.type)?.cursed, true,
                                          "garden/\(tier) seed \(seed): the coat inflicted a curse (\(s.type))")
                    }
                }
            }
        }
    }

    /// ROCKO vs the Two (v6.74 — pins the rule as it stands): `noStickers`
    /// bars sticker ACQUISITION only (grants, packs, the store, his starting
    /// hand) — an INFLICTED curse is not an acquisition. The mystery
    /// "cursedSticker" outcome applies through the low-level applier by
    /// design ("UNGATED … a curse is INFLICTED"), so Rocko CAN be cursed by
    /// the Two; that is his only curse source.
    func testRockoCanBeCursedByTheMysteryCurseOutcome() {
        var successes = 0
        for nodeId in 1...20 {
            let c = climb("rocko", tier: "regular", seed: UInt32(9_001 + nodeId))
            // Precondition: the starting hand is bare (the purity tests pin
            // this sweep-wide; re-checked so this test stands alone).
            XCTAssertTrue(c.getRunDeck().allSatisfy { $0.stickers.isEmpty })
            guard let out = c.applyMysteryEvent("cursedSticker", nodeId: nodeId) else { continue }
            XCTAssertEqual(out.key, "cursedSticker")
            successes += 1
            let cursed = c.getRunDeck().flatMap(\.stickers).filter {
                GameData.shared.stickerTypes.get($0.type)?.cursed == true
            }
            XCTAssertFalse(cursed.isEmpty,
                           "rocko node \(nodeId): the outcome reported a curse but no card wears one")
        }
        XCTAssertGreaterThan(successes, 0,
                             "rocko: the mystery curse outcome never applied across 20 seeded nodes")
    }

    /// …but every ACQUISITION path stays shut for him: the grant pool he can
    /// be offered is empty, and a direct buy refuses.
    func testRockoCannotAcquireStickers() {
        for tier in bothTiers {
            let c = climb("rocko", tier: tier, seed: 4242)
            XCTAssertTrue(c.grantableStickersWithTarget().isEmpty,
                          "rocko/\(tier): the placeable-grant pool must be empty")
            if let any = GameData.shared.stickerTypes.all().first {
                XCTAssertFalse(c.buySticker(any.id),
                               "rocko/\(tier): buying a sticker must refuse")
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
