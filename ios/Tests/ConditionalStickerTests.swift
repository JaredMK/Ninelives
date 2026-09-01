import XCTest
@testable import GameCore

/// THE STICKER CONDITIONAL REWORK (v6.85). One shared contract under test:
/// a conditional sticker checked at its carrier's landing either FIRES
/// (another alive pile's top matches the carrier's suit), CONVERTS into a
/// pathway-rolled curse (no match), or is EXEMPT (no other alive pile at
/// all). Conversions are DORMANT for the landing
/// that created them. Retired (`inactive`) stickers leave every acquisition
/// pool but keep working from old saves. (v6.95: the Payout/Anchor cover
/// punish is gone — both are pure deal-end stickers now.)
final class ConditionalStickerTests: XCTestCase {
    private let data = GameData.shared

    private func spec(_ id: Int, _ rank: Int, _ suit: String = "♠",
                      _ stickers: [String] = []) -> CardSpec {
        IV.spec(id, rank, suit, stickers)
    }

    // MARK: - Same-Safe (v6.86): the rank conditional goes live — the
    //   behavior must MATCH the two-row text: "If another pile's top card
    //   matches this rank → Safe / If no pile's top card matches this rank
    //   → Sticker becomes cursed".

    func testSameSafeTieSavesOnlyWhenAnotherTopShowsTheRank() {
        // FED: pile 3's 7♦ shows the rank → the tie is safe, sticker stays.
        let fed = IV.engine(tops: [spec(1, 7, "♠"), spec(2, 6, "♥"), spec(3, 7, "♦")],
                            deckOrder: [spec(50, 7, "♥", ["tieSafe"]), spec(51, 2)])
        var saved = false
        fed.on { if case .tieSafeSaved = $0 { saved = true } }
        fed.guess(0, .higher)
        XCTAssertTrue(fed.board.isActive(0), "another 7 top feeds the save")
        XCTAssertTrue(saved, "the save announces itself")
        XCTAssertTrue(fed.board.top(0)!.stickers.contains { $0.type == "tieSafe" },
                      "a fed bet keeps the sticker")
        // UNFED: no other 7 → the tie kills AND the carrier converts.
        let unfed = IV.engine(tops: [spec(1, 7, "♠"), spec(2, 6, "♥"), spec(3, 6, "♦")],
                              deckOrder: [spec(50, 7, "♥", ["tieSafe"]), spec(51, 2)])
        unfed.guess(0, .higher)
        XCTAssertFalse(unfed.board.isActive(0), "an unfed Same-Safe saves nothing")
        let buried = unfed.board.piles[0].cards.last!
        XCTAssertFalse(buried.stickers.contains { $0.type == "tieSafe" }, "converted")
        XCTAssertEqual(buried.stickers.filter { data.stickerTypes.get($0.type)?.cursed == true }.count, 1,
                       "one curse took its place, even on the fatal landing")
    }

    func testSameSafeConvertsOnAnyUnfedLandingOfTheCarrier() {
        // Row two of the text names NO tie: ANY landing with no rank match
        // converts — here a plain correct one.
        let e = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 9, "♦")],
                          deckOrder: [spec(50, 7, "♥", ["tieSafe"]), spec(51, 2)])
        e.guess(0, .higher)   // 7 on 5: correct — but no other 7 top anywhere
        XCTAssertTrue(e.board.isActive(0))
        let top = e.board.top(0)!
        XCTAssertFalse(top.stickers.contains { $0.type == "tieSafe" }, "converted")
        XCTAssertFalse(top.tieSafe, "the projected flag re-derived — no more free ties")
    }

    func testSameSafePersistsOnAFedLanding() {
        let e = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 7, "♥"), spec(3, 9, "♦")],
                          deckOrder: [spec(50, 7, "♥", ["tieSafe"]), spec(51, 2)])
        e.guess(0, .higher)   // correct, and pile 2 shows a 7
        XCTAssertTrue(e.board.top(0)!.stickers.contains { $0.type == "tieSafe" },
                      "a fed landing fires (persists) — no conversion")
    }

    func testSameSafeIsExemptOnTheLastPile() {
        let e = IV.engine(tops: [spec(1, 7, "♠"), nil, nil],
                          deckOrder: [spec(50, 7, "♥", ["tieSafe"]), spec(51, 2)])
        e.guess(0, .higher)   // a tie on the last alive pile
        XCTAssertFalse(e.board.isActive(0), "exempt saves nothing — the tie kills (the Guard rule)")
        let buried = e.board.piles[0].cards.last!
        XCTAssertTrue(buried.stickers.contains { $0.type == "tieSafe" },
                      "…and exempt converts nothing either")
    }

    // MARK: - 1. A failed bet converts: sticker out, ONE curse in, dormant

    func testFailedConditionConvertsToOneDormantCurse() {
        // Carrier 3♠ wearing Tell lands correctly on the 5♠ pile; the OTHER
        // piles top ♥ and ♦ — no ♠ anywhere else, the bet fails.
        let e = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 7, "♦")],
                          deckOrder: [spec(50, 3, "♠", ["tell"]), spec(51, 4, "♥")])
        var converted: (from: String, to: String?)?
        var curseFiredThisLanding = false
        e.on { ev in
            if case .stickerConverted(_, _, let from, let to) = ev { converted = (from, to) }
            if case .curseFired = ev { curseFiredThisLanding = true }
        }
        let coinsBefore = e.run.bonusCoins
        e.guess(0, .lower)                      // 3 on 5: correct — the carrier lands
        let top = e.board.top(0)!
        XCTAssertEqual(top.id, 50)
        XCTAssertEqual(converted?.from, "tell", "the failed bet converted")
        XCTAssertFalse(top.stickers.contains { $0.type == "tell" }, "the sticker is gone")
        XCTAssertEqual(top.stickers.count, 1, "exactly ONE curse took its place")
        let curse = data.stickerTypes.get(top.stickers[0].type)
        XCTAssertEqual(curse?.cursed, true)
        XCTAssertEqual(top.stickers[0].type, converted?.to)
        // …and it did NOT fire on the landing that created it.
        XCTAssertFalse(curseFiredThisLanding, "the new curse is dormant this landing")
        XCTAssertEqual(e.run.bonusCoins, coinsBefore,
                       "no coin toll this landing even when the roll is a Leech")
        XCTAssertFalse(e.run.tellPiles.contains(0), "and the Tell itself never fired")
    }

    // MARK: - 2. …and the curse IS live on the card's next landing

    func testConvertedCurseFiresOnTheNextLanding() throws {
        // Scan seeds until the conversion rolls LEECH (weight 10 — common),
        // whose toll is a crisp observable: −3 bonus coins when its card
        // lands. Then re-land the converted card and demand the toll.
        for seed: UInt32 in 1...300 {
            let e = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 7, "♦")],
                              deckOrder: [spec(50, 3, "♠", ["tell"]), spec(51, 8, "♥"), spec(52, 9, "♥")],
                              seed: seed)
            e.guess(0, .lower)                  // converts (no other ♠ top)
            guard let top = e.board.top(0), top.id == 50,
                  top.stickers.first?.type == "leech" else { continue }
            let tollBefore = e.run.bonusCoins
            // Re-stage the converted card as the NEXT draw (its "next
            // landing"): lift it off the pile, put it on the deck front.
            let lifted = e.board.piles[0].cards.removeLast()
            e.deck.restoreSnapshot(cards: [lifted] + e.deck.snapshotCards(),
                                   drawn: e.deck.drawn())
            e.guess(1, .lower)                  // 3♠ on 6♥: correct — it lands again
            XCTAssertEqual(e.board.top(1)?.id, 50)
            XCTAssertEqual(e.run.bonusCoins, tollBefore - (data.stickerTypes.get("leech")?.value ?? 3),
                           "the Leech tolls on the card's NEXT landing")
            return
        }
        XCTFail("no seed in 1...300 rolled a Leech conversion — widen the scan")
    }

    // MARK: - 3. The "sticker" pathway never yields the severe band

    func testSaboteurNeverRollsFromTheStickerPathway() {
        // Data-level: the pathway pool itself excludes it…
        XCTAssertFalse(data.stickerTypes.cursePool(path: "sticker").contains { $0.id == "saboteur" },
                       "saboteur must carry the \"sticker\" curseExclude")
        // …and a wide sweep of live rolls never produces it.
        for seed: UInt32 in 1...200 {
            let e = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 7, "♦")],
                              deckOrder: [spec(50, 3, "♠", ["tell"]), spec(51, 4, "♥")],
                              seed: seed)
            e.guess(0, .lower)
            if let curse = e.board.top(0)?.stickers.first?.type {
                XCTAssertNotEqual(curse, "saboteur", "seed \(seed) rolled the severe band")
            }
        }
    }

    // MARK: - 4. The no-other-pile exemption

    func testLastPileStandingNeitherFiresNorConverts() {
        // One alive pile: the check is exempt — the sticker survives AND
        // does not fire.
        let e = IV.engine(tops: [spec(1, 5, "♠")],
                          deckOrder: [spec(50, 3, "♠", ["tell"]), spec(51, 4, "♥")])
        e.guess(0, .lower)
        let top = e.board.top(0)!
        XCTAssertEqual(top.stickers.map(\.type), ["tell"], "the sticker survives, unconverted")
        XCTAssertFalse(e.run.tellPiles.contains(0), "…and it did not fire either")
    }

    // MARK: - 5. The condition reads the CARRIER's suit

    func testConditionReadsTheCarriersOwnSuit() {
        // Identical board (tops ♠/♥/♦). A ♥ carrier fires (the ♥ top
        // matches IT); a ♣ carrier converts (nothing matches).
        let fire = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 7, "♦")],
                             deckOrder: [spec(50, 3, "♥", ["quickBury"]), spec(51, 4, "♥"),
                                         spec(52, 8, "♣"), spec(53, 9, "♣")])
        let sizeBefore = fire.board.piles[0].cards.count
        fire.guess(0, .lower)
        XCTAssertEqual(fire.board.top(0)?.stickers.map(\.type), ["quickBury"],
                       "♥ carrier with a ♥ top elsewhere: the bet holds")
        XCTAssertEqual(fire.board.piles[0].cards.count, sizeBefore + 2,
                       "…and Quick Bury fired (landing + 1 buried)")

        let convert = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 7, "♦")],
                                deckOrder: [spec(50, 3, "♣", ["quickBury"]), spec(51, 4, "♥"),
                                            spec(52, 8, "♣"), spec(53, 9, "♣")])
        convert.guess(0, .lower)
        let top = convert.board.top(0)!
        XCTAssertFalse(top.stickers.contains { $0.type == "quickBury" },
                       "♣ carrier on the same board: the bet fails and converts")
        XCTAssertEqual(top.stickers.count, 1)
        XCTAssertEqual(data.stickerTypes.get(top.stickers[0].type)?.cursed, true)
    }

    // MARK: - 6. v6.95: the cover punish is GONE — Payout/Anchor are pure deal-end

    func testCoveringPayoutOrAnchorCursesNothing() {
        for sticker in ["extraCoin", "anchor"] {
            let e = IV.engine(tops: [spec(1, 5, "♠", [sticker]), spec(2, 6, "♥"), spec(3, 7, "♦")],
                              deckOrder: [spec(50, 3, "♥"), spec(51, 4, "♥")])
            e.guess(0, .lower)                     // 3♥ lands ON the carrier
            let top = e.board.top(0)!
            XCTAssertEqual(top.id, 50)
            XCTAssertTrue(top.stickers.isEmpty,
                          "\(sticker): the covering card gains nothing — no curse")
            // The carrier itself is untouched beneath, keeping its deal-end effect.
            let beneath = e.board.piles[0].cards[e.board.piles[0].cards.count - 2]
            XCTAssertEqual(beneath.stickers.map(\.type), [sticker],
                           "\(sticker): the carrier keeps its sticker")
        }
    }

    // MARK: - 7. Retired items leave EVERY acquisition pool

    func testInactiveStickersNeverAppearFromAnyAcquisitionPath() {
        let inactiveIds = Set(data.items.stickers.filter(\.inactive).map(\.id))
        XCTAssertEqual(inactiveIds.count, 21, "the v6.85 retirement set + v6.94 Heavy")
        // The one chokepoint every pool flows through…
        XCTAssertFalse(data.stickerTypes.grantableBase().contains { inactiveIds.contains($0.id) })
        // …and the live paths on top of it. Store shelves:
        for seed: UInt32 in 1...120 {
            let rng = RNG(seed: seed)
            var scratch: [String: ShopRoll] = [:]
            let slots = StoreRoll.rollUnifiedSlots(rng, count: 12, data: data,
                                                   isUnlocked: { _ in true }, genCard: nil,
                                                   shopRolls: &scratch)
            for s in slots.compactMap({ $0 }) where s.kind == "sticker" {
                XCTAssertFalse(inactiveIds.contains(s.id), "seed \(seed): shelf rolled retired '\(s.id)'")
            }
        }
        // Pack reveals + minted pack cards' sticker rolls:
        for seed: UInt32 in [11, 4242, 777_777] {
            let c = CampaignState(store: MemoryStore())
            c.setDeck("pink"); c.setTier("regular"); c.setSeedOverride(seed); c.reset()
            for packId in data.packTypes.ids {
                let out = c.revealPack(packId, rng: RNG(seed: seed ^ 0xabcdef))
                for sid in out.stickers {
                    XCTAssertFalse(inactiveIds.contains(sid), "pack \(packId) revealed retired '\(sid)'")
                }
                for card in out.cards {
                    for st in card.stickers {
                        XCTAssertFalse(inactiveIds.contains(st.type),
                                       "pack card minted retired '\(st.type)'")
                    }
                }
            }
            // The campaign grant pool (mystery Imprint, map grants):
            XCTAssertFalse(c.grantableStickers().contains { inactiveIds.contains($0.id) })
        }
        // The engine's Wild Sticker / Sticker Spray / Flypaper pool:
        let e = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥")],
                          deckOrder: [spec(50, 9, "♠")])
        for def in e.wildStickerPoolFor(e.board.top(0)) {
            XCTAssertFalse(inactiveIds.contains(def.id), "wild pool offered retired '\(def.id)'")
        }
    }

    // MARK: - 8. …but an old save's retired sticker survives and still works

    func testInactiveStickerSurvivesRestoreAndStillFires() {
        // Restore half: a save whose deck card wears retired Spade Whispers.
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular"); c.setSeedOverride(9); c.reset()
        let cardId = c.getRunDeck().first(where: { $0.suit == "♠" })!.id
        XCTAssertTrue(c.applyStickerDirect(cardId, "spadeWhispers"),
                      "an old save's retired sticker still applies directly")
        let c2 = CampaignState(store: MemoryStore())
        XCTAssertTrue(c2.restore(c.serialize()))
        XCTAssertTrue(c2.findById(cardId)!.stickers.contains { $0.type == "spadeWhispers" },
                      "the retired sticker survives the round-trip")
        // Engine half: the retired sticker's effect still fires.
        let e = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♠"), spec(3, 7, "♥")],
                          deckOrder: [spec(50, 3, "♠", ["spadeWhispers"]), spec(51, 4, "♥")])
        e.guess(0, .lower)
        XCTAssertTrue(e.run.whisperPiles.contains(0),
                      "Spade Whispers still fires for its old-save carrier")
    }

    // MARK: - 9. New run state round-trips the mid-deal snapshot

    func testSuitRippleOfferRoundTripsTheSnapshot() {
        let build = {
            IV.engine(tops: [self.spec(1, 5, "♠"), self.spec(2, 6, "♥"), self.spec(3, 7, "♦")],
                      deckOrder: [self.spec(50, 3, "♥", ["diamondSnob"]), self.spec(51, 4, "♥"),
                                  self.spec(52, 8, "♣")])
        }
        let e = build()
        e.guess(0, .lower)                     // ♥ carrier + ♥ top: the offer queues
        XCTAssertEqual(e.run.pendingActions.first?.kind, "suitRipple")
        let twin = build()
        XCTAssertTrue(twin.restoreSnapshot(e.snapshot()))
        XCTAssertEqual(twin.run.pendingActions.first?.kind, "suitRipple",
                       "the Ripple offer survives a mid-deal kill")
        XCTAssertEqual(twin.run.pendingActions.first?.index, 0)
        // …and answering it after the restore shuffles the matching piles.
        twin.answerAction(true)
        XCTAssertTrue(twin.run.pendingActions.isEmpty)
    }

    // MARK: - 10. The Same stickers join the rank conditional (v6.90)

    func testRechargeShieldFiresOnRankMatchAndConvertsOnMiss() {
        // FED: pile 2's 9♥ shows the carrier's rank → the charge banks.
        let fed = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 9, "♥"), spec(3, 6, "♦")],
                            deckOrder: [spec(50, 9, "♠", ["rechargeSameShield"]), spec(51, 2)])
        fed.guess(0, .higher)
        XCTAssertTrue(fed.sameCharge, "another 9 top → the charge banks")
        XCTAssertTrue(fed.board.top(0)!.stickers.contains { $0.type == "rechargeSameShield" },
                      "a fed bet keeps the sticker")
        // UNFED: no other 9 → converts (one curse, dormant this landing).
        let unfed = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 7, "♥"), spec(3, 6, "♦")],
                              deckOrder: [spec(50, 9, "♠", ["rechargeSameShield"]), spec(51, 2)])
        var curseFiredThisLanding = false
        unfed.on { if case .curseFired = $0 { curseFiredThisLanding = true } }
        let coins = unfed.run.bonusCoins
        unfed.guess(0, .higher)
        XCTAssertFalse(unfed.sameCharge, "no 9 anywhere else → nothing banks")
        let top = unfed.board.top(0)!
        XCTAssertFalse(top.stickers.contains { $0.type == "rechargeSameShield" }, "converted")
        XCTAssertEqual(top.stickers.filter { data.stickerTypes.get($0.type)?.cursed == true }.count, 1,
                       "exactly ONE curse took its place")
        XCTAssertFalse(curseFiredThisLanding, "the new curse is dormant this landing")
        XCTAssertEqual(unfed.run.bonusCoins, coins, "no toll this landing even when the roll is a Leech")
    }

    func testTapPowerFiresOnRankMatchAndConvertsOnMiss() {
        let fed = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 9, "♥"), spec(3, 6, "♦")],
                            deckOrder: [spec(50, 9, "♠", ["activateSamePower"]), spec(51, 2)],
                            samePower: "linkCoins")
        let before = fed.run.bonusCoins
        fed.guess(0, .higher)
        XCTAssertGreaterThan(fed.run.bonusCoins, before, "the fed bet fired Link Coins")
        XCTAssertTrue(fed.board.top(0)!.stickers.contains { $0.type == "activateSamePower" },
                      "a fed bet keeps the sticker")
        let unfed = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 7, "♥"), spec(3, 6, "♦")],
                              deckOrder: [spec(50, 9, "♠", ["activateSamePower"]), spec(51, 2)],
                              samePower: "linkCoins")
        let b2 = unfed.run.bonusCoins
        unfed.guess(0, .higher)
        XCTAssertEqual(unfed.run.bonusCoins, b2, "a missed bet fires nothing")
        let top = unfed.board.top(0)!
        XCTAssertFalse(top.stickers.contains { $0.type == "activateSamePower" }, "converted")
        XCTAssertEqual(top.stickers.filter { data.stickerTypes.get($0.type)?.cursed == true }.count, 1)
    }

    func testSameStickersAreExemptOnTheLastPile() {
        for sid in ["rechargeSameShield", "activateSamePower"] {
            let e = IV.engine(tops: [spec(1, 5, "♠"), nil, nil],
                              deckOrder: [spec(50, 9, "♠", [sid]), spec(51, 2)],
                              samePower: "linkCoins")
            let coins = e.run.bonusCoins
            e.guess(0, .higher)
            let top = e.board.top(0)!
            XCTAssertTrue(top.stickers.contains { $0.type == sid },
                          "\(sid): exempt on the last alive pile — no conversion")
            XCTAssertFalse(e.sameCharge, "\(sid): …and no fire either")
            XCTAssertEqual(e.run.bonusCoins, coins, "\(sid): no power fire either")
        }
    }

    // MARK: - 11. The validator accepts `inactive`

    func testValidatorAcceptsInactiveAndTheNewPathway() {
        // The shipped registry loaded with 20 inactive stickers and the
        // saboteur "sticker" exclusion — had either been rejected, GameData
        // would have failed loud at boot and no test would run.
        XCTAssertEqual(data.stickerTypes.get("wildSuit")?.inactive, true)
        XCTAssertEqual(data.stickerTypes.get("quickBury")?.inactive, false)
        XCTAssertTrue(data.stickerTypes.get("saboteur")?.curseExclude.contains("sticker") == true)
        // And the exemption's mirror: every NON-severe curse stays rollable
        // from the sticker pathway.
        let pathway = Set(data.stickerTypes.cursePool(path: "sticker").map(\.id))
        XCTAssertTrue(pathway.contains("leech"))
        XCTAssertTrue(pathway.contains("mute"))
        XCTAssertFalse(pathway.contains("saboteur"))
    }
}
