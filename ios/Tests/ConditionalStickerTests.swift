import XCTest
@testable import GameCore

/// THE KILL→CURSE MODEL (v7.07, replacing the v6.85 condition-failure
/// conversion). ONE shared trigger: a sticker flagged `killCurse` in
/// items.js converts into a pathway-rolled curse when its CARRIER KILLS ITS
/// PILE — a wrong guess that dies, or a Malfunction self-destruct. Failing
/// a board condition converts NOTHING any more: the keepers (Same-Safe,
/// Guard, the Scouts) simply don't fire; the droppers (Bonus Coin, Donate,
/// Quick Bury, Ripple, Tell, Twin Spark, the Same stickers) fire on every
/// landing. Conversions stay DORMANT for the landing that created them.
/// Retired (`inactive`) stickers leave every acquisition pool but keep
/// working from old saves.
final class ConditionalStickerTests: XCTestCase {
    private let data = GameData.shared

    private func spec(_ id: Int, _ rank: Int, _ suit: String = "♠",
                      _ stickers: [String] = []) -> CardSpec {
        IV.spec(id, rank, suit, stickers)
    }

    /// THE CANONICAL KILL: a 3♠ carrier called HIGHER onto a 5♠ — wrong, no
    /// other ♠ top for a Guard, no charge → the pile dies wearing it.
    private func killEngine(_ stickers: [String], seed: UInt32 = 7,
                            samePower: String? = nil) -> GameEngine {
        IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 7, "♦")],
                  deckOrder: [spec(50, 3, "♠", stickers), spec(51, 4, "♥"), spec(52, 8, "♥")],
                  samePower: samePower, seed: seed)
    }
    private func curses(_ card: LiveCard) -> [String] {
        card.stickers.filter { data.stickerTypes.get($0.type)?.cursed == true }.map(\.type)
    }

    // MARK: - Same-Safe KEEPS its condition; converts only on a kill

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
        // UNFED: no other 7 → the tie KILLS — and a kill is the one thing
        // that converts (v7.07).
        let unfed = IV.engine(tops: [spec(1, 7, "♠"), spec(2, 6, "♥"), spec(3, 6, "♦")],
                              deckOrder: [spec(50, 7, "♥", ["tieSafe"]), spec(51, 2)])
        unfed.guess(0, .higher)
        XCTAssertFalse(unfed.board.isActive(0), "an unfed Same-Safe saves nothing")
        let buried = unfed.board.piles[0].cards.last!
        XCTAssertFalse(buried.stickers.contains { $0.type == "tieSafe" }, "the carrier KILLED its pile → converted")
        XCTAssertEqual(curses(buried).count, 1, "one curse took its place, buried with the card")
        XCTAssertFalse(buried.tieSafe, "the projected tie-safe flag re-derived off the converted carrier")
    }

    func testSameSafeKeepsItsStickerOnAnUnfedCorrectLanding() {
        // v7.07: a CORRECT landing with no rank twin is a missed bet that
        // simply didn't fire — it converts nothing.
        let e = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 9, "♦")],
                          deckOrder: [spec(50, 7, "♥", ["tieSafe"]), spec(51, 2)])
        e.guess(0, .higher)   // 7 on 5: correct — but no other 7 top anywhere
        XCTAssertTrue(e.board.isActive(0))
        let top = e.board.top(0)!
        XCTAssertEqual(top.stickers.map(\.type), ["tieSafe"], "the sticker stays — no condition failure converts")
        XCTAssertTrue(top.tieSafe, "…and it still projects the tie-safe flag")
    }

    func testSameSafePersistsOnAFedLanding() {
        let e = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 7, "♥"), spec(3, 9, "♦")],
                          deckOrder: [spec(50, 7, "♥", ["tieSafe"]), spec(51, 2)])
        e.guess(0, .higher)   // correct, and pile 2 shows a 7
        XCTAssertTrue(e.board.top(0)!.stickers.contains { $0.type == "tieSafe" },
                      "a fed landing fires (persists) — no conversion")
    }

    func testSameSafeConvertsOnTheLastPileToo() {
        // v7.07: the kill rule has NO last-pile exemption — an unfed tie on
        // the last alive pile kills it, and the carrier converts.
        let e = IV.engine(tops: [spec(1, 7, "♠"), nil, nil],
                          deckOrder: [spec(50, 7, "♥", ["tieSafe"]), spec(51, 2)])
        e.guess(0, .higher)
        XCTAssertFalse(e.board.isActive(0), "no other alive pile — the tie kills")
        let buried = e.board.piles[0].cards.last!
        XCTAssertFalse(buried.stickers.contains { $0.type == "tieSafe" }, "…and the kill converts")
        XCTAssertEqual(curses(buried).count, 1)
    }

    // MARK: - 1. A kill converts: sticker out, ONE curse in, dormant

    func testKillConvertsToOneDormantCurse() {
        let e = killEngine(["tell"])
        var converted: (from: String, to: String?)?
        var curseFiredThisLanding = false
        e.on { ev in
            if case .stickerConverted(_, _, let from, let to) = ev { converted = (from, to) }
            if case .curseFired = ev { curseFiredThisLanding = true }
        }
        let coinsBefore = e.run.bonusCoins
        e.guess(0, .higher)                     // 3 on 5: wrong — the carrier kills its pile
        XCTAssertFalse(e.board.isActive(0))
        let buried = e.board.piles[0].cards.last!
        XCTAssertEqual(buried.id, 50)
        XCTAssertEqual(converted?.from, "tell", "the kill converted")
        XCTAssertFalse(buried.stickers.contains { $0.type == "tell" }, "the sticker is gone")
        XCTAssertEqual(buried.stickers.count, 1, "exactly ONE curse took its place")
        let curse = data.stickerTypes.get(buried.stickers[0].type)
        XCTAssertEqual(curse?.cursed, true)
        XCTAssertEqual(buried.stickers[0].type, converted?.to)
        // …and it did NOT fire on the landing that created it.
        XCTAssertFalse(curseFiredThisLanding, "the new curse is dormant this landing")
        XCTAssertEqual(e.run.bonusCoins, coinsBefore,
                       "no coin toll this landing even when the roll is a Leech")
        XCTAssertFalse(e.run.tellPiles.contains(0), "and the Tell never armed a dead pile")
    }

    // MARK: - 2. …and the curse IS live on the card's next landing

    func testConvertedCurseFiresOnTheNextLanding() throws {
        // Scan seeds until the kill conversion rolls LEECH (weight 10 —
        // common), whose toll is a crisp observable: −3 bonus coins when its
        // card lands. Then re-land the converted card and demand the toll.
        for seed: UInt32 in 1...300 {
            let e = killEngine(["tell"], seed: seed)
            e.guess(0, .higher)                 // kills → converts
            let buried = e.board.piles[0].cards.last!
            guard buried.id == 50, buried.stickers.first?.type == "leech" else { continue }
            let tollBefore = e.run.bonusCoins
            // Re-stage the converted card as the NEXT draw (its "next
            // landing"): lift it off the dead pile, put it on the deck front.
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
        // …and a wide sweep of live kill conversions never produces it.
        for seed: UInt32 in 1...200 {
            let e = killEngine(["tell"], seed: seed)
            e.guess(0, .higher)
            if let curse = e.board.piles[0].cards.last?.stickers.first?.type {
                XCTAssertNotEqual(curse, "saboteur", "seed \(seed) rolled the severe band")
            }
        }
    }

    // MARK: - 4. Failing a board condition converts NOTHING (the keepers)

    func testConditionFailureNeverConverts() {
        // Same-Safe: correct landing, no rank twin.
        let ts = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 9, "♦")],
                           deckOrder: [spec(50, 7, "♥", ["tieSafe"]), spec(51, 2)])
        ts.guess(0, .higher)
        XCTAssertEqual(ts.board.top(0)!.stickers.map(\.type), ["tieSafe"], "Same-Safe: missed bet, sticker stays")
        // Guard: correct landing, no suit twin (♣ carrier on a ♠/♥/♦ board).
        let g = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 7, "♦")],
                          deckOrder: [spec(50, 3, "♣", ["suitImmunity"]), spec(51, 4, "♥")])
        g.guess(0, .lower)
        XCTAssertEqual(g.board.top(0)!.stickers.map(\.type), ["suitImmunity"], "Guard: missed bet, sticker stays")
        // The Scouts: a FILLED slot means no peek — and no conversion.
        let ps = IV.engine(tops: [spec(1, 5), spec(2, 6), spec(3, 6)],
                           deckOrder: [spec(50, 9, "♠", ["pillarScout"]), spec(51, 2)],
                           pillars: ["prime", nil, nil])
        ps.guess(0, .higher)
        XCTAssertFalse(ps.run.revealNextActive, "Pillar Scout: a filled slot blocks the peek")
        XCTAssertEqual(ps.board.top(0)!.stickers.map(\.type), ["pillarScout"], "…and the sticker stays")
        let bs = IV.engine(tops: [spec(1, 5), spec(2, 6), spec(3, 6)],
                           deckOrder: [spec(50, 9, "♠", ["baseScout"]), spec(51, 2)],
                           bases: ["spadePeek", nil, nil])
        bs.guess(0, .higher)
        XCTAssertFalse(bs.run.revealNextActive, "Base Scout: a filled slot blocks the peek")
        XCTAssertEqual(bs.board.top(0)!.stickers.map(\.type), ["baseScout"], "…and the sticker stays")
    }

    // MARK: - 5. The droppers fire on ANY landing (no suit/rank bet left)

    func testDroppersFireOnAMismatchedBoardAndKeepTheirSticker() {
        // A ♠3 carrier on a ♥/♦/♣ board with no 3 anywhere: every old bet
        // would have missed. v7.07: each fires and stays.
        func land(_ sticker: String, samePower: String? = nil) -> GameEngine {
            let e = IV.engine(tops: [spec(1, 5, "♥"), spec(2, 6, "♦"), spec(3, 7, "♣")],
                              deckOrder: [spec(50, 3, "♠", [sticker]), spec(51, 4, "♥"), spec(52, 8, "♥")],
                              samePower: samePower)
            e.guess(0, .lower)   // 3 on 5: correct
            XCTAssertTrue(e.board.top(0)!.stickers.contains { $0.type == sticker }, "\(sticker): stays")
            XCTAssertTrue(curses(e.board.top(0)!).isEmpty, "\(sticker): no curse")
            return e
        }
        let coin = data.stickerTypes.get("gainCoin")!.value
        XCTAssertEqual(land("gainCoin").run.bonusCoins, coin, "Bonus Coin: flat +\(Int(coin))")
        XCTAssertEqual(land("quickBury").board.piles[0].cards.count, 3, "Quick Bury: landing + 1 buried")
        XCTAssertTrue(land("tell").run.tellPiles.contains(0), "Tell: armed")
        XCTAssertTrue(land("twinSpark").run.revealNextActive, "Twin Spark: peeked")
        XCTAssertTrue(land("rechargeSameShield").sameCharge, "Recharge Shield: banked")
        XCTAssertGreaterThan(land("activateSamePower", samePower: "linkCoins").run.bonusCoins, 0, "Tap Power: fired Link Coins")
        XCTAssertEqual(land("diamondSnob").run.pendingActions.map(\.kind), ["suitRipple"], "Ripple: offered")
        _ = land("donate")   // equalises (nothing to move on a flat board) — stays, no curse
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
        XCTAssertEqual(inactiveIds.count, 20, "the v6.85 retirement set + v6.94 Heavy, minus Snowball Bury (un-retired v7.07)")
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
        e.guess(0, .lower)                     // the Ripple offer queues on every landing (v7.07)
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

    // MARK: - 10. The Same stickers: unconditional fire, kill conversion

    func testRechargeShieldAndTapPowerFireOnAnyLandingAndConvertOnAKill() {
        // No other 9 anywhere — the old rank bet would have missed.
        let rs = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 7, "♥"), spec(3, 6, "♦")],
                           deckOrder: [spec(50, 9, "♠", ["rechargeSameShield"]), spec(51, 2)])
        rs.guess(0, .higher)
        XCTAssertTrue(rs.sameCharge, "Recharge Shield banks on any landing")
        XCTAssertEqual(rs.board.top(0)!.stickers.map(\.type), ["rechargeSameShield"], "…and stays")
        let tp = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 7, "♥"), spec(3, 6, "♦")],
                           deckOrder: [spec(50, 9, "♠", ["activateSamePower"]), spec(51, 2)],
                           samePower: "linkCoins")
        let before = tp.run.bonusCoins
        tp.guess(0, .higher)
        XCTAssertGreaterThan(tp.run.bonusCoins, before, "Tap Power fires Link Coins on any landing")
        XCTAssertEqual(tp.board.top(0)!.stickers.map(\.type), ["activateSamePower"], "…and stays")
        // A kill converts both, per instance, dormant.
        for sid in ["rechargeSameShield", "activateSamePower"] {
            let k = killEngine([sid], samePower: "linkCoins")
            var curseFiredThisLanding = false
            k.on { if case .curseFired = $0 { curseFiredThisLanding = true } }
            k.guess(0, .higher)
            let buried = k.board.piles[0].cards.last!
            XCTAssertFalse(buried.stickers.contains { $0.type == sid }, "\(sid): converted on the kill")
            XCTAssertEqual(curses(buried).count, 1, "\(sid): exactly ONE curse took its place")
            XCTAssertFalse(curseFiredThisLanding, "\(sid): the new curse is dormant this landing")
        }
    }

    func testSameStickersFireOnTheLastPileToo() {
        // v7.07: no exemption — nothing to be exempt FROM.
        for sid in ["rechargeSameShield", "activateSamePower"] {
            let e = IV.engine(tops: [spec(1, 5, "♠"), nil, nil],
                              deckOrder: [spec(50, 9, "♠", [sid]), spec(51, 2)],
                              samePower: "linkCoins")
            let coins = e.run.bonusCoins
            e.guess(0, .higher)
            XCTAssertTrue(e.board.top(0)!.stickers.contains { $0.type == sid }, "\(sid): stays")
            if sid == "rechargeSameShield" { XCTAssertTrue(e.sameCharge, "\(sid): banked on the last pile") }
            else { XCTAssertGreaterThan(e.run.bonusCoins, coins, "\(sid): fired on the last pile") }
        }
    }

    // MARK: - 11. The validator accepts `inactive` and the kill flag

    func testValidatorAcceptsInactiveAndTheNewPathway() {
        // The shipped registry loaded with 20 inactive stickers and the
        // saboteur "sticker" exclusion — had either been rejected, GameData
        // would have failed loud at boot and no test would run.
        XCTAssertEqual(data.stickerTypes.get("wildSuit")?.inactive, true)
        XCTAssertEqual(data.stickerTypes.get("quickBury")?.inactive, false)
        XCTAssertEqual(data.stickerTypes.get("snowball")?.inactive, false, "Snowball Bury is back (v7.07)")
        XCTAssertTrue(data.stickerTypes.get("saboteur")?.curseExclude.contains("sticker") == true)
        // And the exemption's mirror: every NON-severe curse stays rollable
        // from the sticker pathway.
        let pathway = Set(data.stickerTypes.cursePool(path: "sticker").map(\.id))
        XCTAssertTrue(pathway.contains("leech"))
        XCTAssertTrue(pathway.contains("mute"))
        XCTAssertFalse(pathway.contains("saboteur"))
        // The kill flag reaches the engine through `raw` (v7.07).
        XCTAssertEqual(data.stickerTypes.get("tell")?.raw["killCurse"]?.asBool, true)
        XCTAssertNil(data.stickerTypes.get("anchor")?.raw["killCurse"], "an unflagged sticker carries no flag")
    }
}
