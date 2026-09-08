import XCTest
@testable import GameCore

/// v7.07 BATCH — the kill→curse sticker model (item 1), the Snowballs (2, 3),
/// the three flag-reversible Same-Power experiments (4), Scarce Suit ties
/// (5), and the small-revealed-packs debug toggle (8).
final class V707BatchTests: XCTestCase {
    private let data = GameData.shared

    private func spec(_ id: Int, _ rank: Int, _ suit: String = "♠",
                      _ stickers: [String] = []) -> CardSpec {
        IV.spec(id, rank, suit, stickers)
    }
    private func curses(_ card: LiveCard) -> [String] {
        card.stickers.filter { data.stickerTypes.get($0.type)?.cursed == true }.map(\.type)
    }
    /// THE CANONICAL KILL: 3♠ called HIGHER onto a 5♠ — wrong, no other ♠
    /// top for a Guard, no charge → the pile dies wearing the carrier.
    private func killEngine(_ stickers: [String], seed: UInt32 = 7,
                            samePower: String? = nil) -> GameEngine {
        IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 7, "♦")],
                  deckOrder: [spec(50, 3, "♠", stickers), spec(51, 4, "♥"), spec(52, 8, "♥")],
                  samePower: samePower, seed: seed)
    }

    // MARK: - 1. Kill → curse, for EVERY flagged sticker; nothing else

    func testEveryKillCurseStickerConvertsWhenItsCarrierKillsThePile() {
        let flagged = data.stickerTypes.all().filter { $0.raw["killCurse"]?.asBool == true }.map(\.id)
        XCTAssertEqual(Set(flagged), [
            "tieSafe", "suitImmunity", "baseScout", "pillarScout", "gainCoin", "donate",
            "quickBury", "diamondSnob", "tell", "twinSpark", "rechargeSameShield",
            "activateSamePower", "snowball", "snowballCoins",
            // retired, flagged so old-save carriers follow the model:
            "heavy", "massive", "heartGuard", "diamondGuard", "clubGuard",
        ], "the flag set is exactly the spec's 12 + the two Snowballs + the retired conditionals")
        for id in flagged {
            let e = killEngine([id], samePower: "linkCoins")
            e.guess(0, .higher)
            XCTAssertFalse(e.board.isActive(0), "\(id): the carrier killed its pile")
            let buried = e.board.piles[0].cards.last!
            XCTAssertFalse(buried.stickers.contains { $0.type == id }, "\(id): converted on the kill")
            XCTAssertEqual(curses(buried).count, 1, "\(id): exactly ONE curse took its place")
        }
    }

    func testUnflaggedStickersSurviveAKillUntouched() {
        // Deal-end / passive stickers and the identity changers: never converted.
        let plain = killEngine(["anchor", "extraCoin", "revealNext"])
        plain.guess(0, .higher)
        let buried = plain.board.piles[0].cards.last!
        XCTAssertEqual(Set(buried.stickers.map(\.type)), ["anchor", "extraCoin", "revealNext"])
        XCTAssertTrue(curses(buried).isEmpty, "no kill clause on an unflagged sticker")
        let changers = killEngine(["rankUp", "changeSuitSpade"])   // 3♠ → 4♠: still wrong on 5
        changers.guess(0, .higher)
        let b2 = changers.board.piles[0].cards.last!
        XCTAssertEqual(Set(b2.stickers.map(\.type)), ["rankUp", "changeSuitSpade"],
                       "rank/suit changers carry no kill clause")
        XCTAssertTrue(curses(b2).isEmpty)
    }

    func testASavedWrongLandingConvertsNothing() {
        // The Same Shield saves the pile: the carrier did NOT kill it.
        let e = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 7, "♦")],
                          deckOrder: [spec(50, 3, "♠", ["tell", "gainCoin"]), spec(51, 4, "♥")],
                          sameCharge: true)
        e.guess(0, .higher)   // wrong — the shield eats it, the card lands
        XCTAssertTrue(e.board.isActive(0), "saved")
        XCTAssertEqual(Set(e.board.top(0)!.stickers.map(\.type)), ["tell", "gainCoin"], "no kill, no conversion")
    }

    func testMalfunctionSelfDestructConvertsTheCarriersStickersToo() {
        // The user's call: a Malfunction that blows the carrier's OWN pile is
        // a kill — its killCurse stickers convert (the curse itself stays).
        let mal = data.stickerTypes.all().first { $0.behavior == "malfunction" }!.id
        for seed: UInt32 in 1...400 {
            let e = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 7, "♦")],
                              deckOrder: [spec(50, 9, "♠", [mal, "tell"]), spec(51, 4)], seed: seed)
            e.guess(0, .higher)   // 9 on 5: correct — the roll may blow the pile
            guard !e.board.isActive(0) else { continue }
            let buried = e.board.piles[0].cards.last!
            XCTAssertEqual(buried.id, 50)
            XCTAssertFalse(buried.stickers.contains { $0.type == "tell" },
                           "seed \(seed): the self-destruct KILLED the pile — Tell converted")
            XCTAssertTrue(buried.stickers.contains { $0.type == mal }, "the Malfunction curse itself stays")
            return
        }
        XCTFail("no seed in 1...400 triggered a Malfunction — widen the scan")
    }

    // MARK: - 2/3. The Snowballs: one per-card X, grows / resets / kills

    func testSnowballBuryIsBackOnTheFlatSchemeWithNoSuitLock() {
        let sb = data.stickerTypes.get("snowball")!
        XCTAssertFalse(sb.inactive, "un-retired")
        XCTAssertNil(sb.suits, "the ♣ lock is gone")
        XCTAssertEqual(sb.tier, "uncommon"); XCTAssertEqual(sb.price, 3)
        let sc = data.stickerTypes.get("snowballCoins")!
        XCTAssertFalse(sc.inactive); XCTAssertNil(sc.suits)
        XCTAssertEqual(sc.tier, "uncommon"); XCTAssertEqual(sc.price, 3)
        XCTAssertTrue(data.stickerTypes.grantableBase().contains { $0.id == "snowball" }, "back in the pools")
    }

    func testSnowballCoinsPaysXThenGrowsAndAWrongPlacementResets() {
        let e = IV.engine(tops: [spec(1, 5), spec(2, 6), spec(3, 6)],
                          deckOrder: [spec(50, 9, "♠", ["snowballCoins"]), spec(51, 2)])
        e.deck.snapshotCards().first { $0.id == 50 }!.snowball = 2
        let before = e.run.bonusCoins
        e.guess(0, .higher)                      // lands correctly
        XCTAssertEqual(e.run.bonusCoins, before + 2, "+X (2) coins on landing")
        XCTAssertEqual(e.run.snowballUpdates[50], 3, "X grew by the step")
        // A SAVED wrong placement of the card resets X — and converts nothing.
        let s = IV.engine(tops: [spec(1, 9), spec(2, 6), spec(3, 6)],
                          deckOrder: [spec(50, 2, "♠", ["snowballCoins"]), spec(51, 3)],
                          sameCharge: true)
        s.deck.snapshotCards().first { $0.id == 50 }!.snowball = 3
        s.guess(0, .higher)                      // wrong — the shield saves the pile
        XCTAssertTrue(s.board.isActive(0))
        XCTAssertEqual(s.run.snowballUpdates[50], 0, "reset to 0 — and a saved WRONG placement never grows it")
        XCTAssertTrue(s.board.top(0)!.stickers.contains { $0.type == "snowballCoins" }, "saved → stays")
    }

    func testBothSnowballsShareOneXAndGrowItOnce() {
        let e = IV.engine(tops: [spec(1, 5), spec(2, 6), spec(3, 6)],
                          deckOrder: [spec(50, 9, "♠", ["snowball", "snowballCoins"]), spec(51, 2), spec(52, 3), spec(53, 4)])
        e.deck.snapshotCards().first { $0.id == 50 }!.snowball = 2
        let coins = e.run.bonusCoins, size = e.board.piles[0].cards.count
        e.guess(0, .higher)
        XCTAssertEqual(e.board.piles[0].cards.count, size + 1 + 2, "Bury: landing + X (2) buried")
        XCTAssertEqual(e.run.bonusCoins, coins + 2, "Coins: +X (2)")
        XCTAssertEqual(e.run.snowballUpdates[50], 3, "X grew ONCE for the landing, not per twin")
    }

    // MARK: - 4. The Same-Power experiments, each behind ONE data flag

    func testBurrowBuriesUnderEveryAlivePileWhenFlagged() {
        XCTAssertEqual(data.samePowerTypes.get("linkBury")?.raw["allPiles"]?.asBool, true, "the experiment flag is on")
        let e = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 7, "♦")],
                          deckOrder: [spec(50, 9), spec(51, 9), spec(52, 9), spec(53, 9)],
                          samePower: "linkBury", samePowerVariant: "♥")
        let before = (0..<3).map { e.board.piles[$0].cards.count }
        e.debugFireSamePower(0)
        for i in 0..<3 {
            XCTAssertEqual(e.board.piles[i].cards.count, before[i] + 1,
                           "pile \(i + 1): buried under EVERY alive pile, not just the ♥ top")
        }
    }

    func testStickerSprayHitsEveryTopOnTheBoardWhenFlagged() {
        XCTAssertEqual(data.samePowerTypes.get("linkSticker")?.raw["allPiles"]?.asBool, true, "the experiment flag is on")
        let e = IV.engine(tops: [spec(1, 5, "♠"), spec(2, 6, "♥"), spec(3, 7, "♦")],
                          deckOrder: [spec(50, 9)], cols: [1, 1, 1], samePower: "linkSticker")
        e.debugFireSamePower(0)   // hub in column 1 — the old scope was that column only
        for i in 0..<3 {
            XCTAssertFalse(e.board.top(i)!.stickers.isEmpty,
                           "pile \(i + 1) (its own column) got a sticker — every top on the board")
        }
    }

    func testLongOddsQueuesOnePurgePerSameAndCarriesItToTheCampaign() {
        XCTAssertEqual(data.samePowerTypes.get("linkPurge")?.raw["deferred"]?.asBool, true, "the experiment flag is on")
        let build = {
            IV.engine(tops: [self.spec(1, 5, "♠"), self.spec(2, 6, "♥"), self.spec(3, 7, "♦")],
                      deckOrder: [self.spec(50, 9), self.spec(51, 9), self.spec(52, 9)], samePower: "linkPurge")
        }
        let e = build()
        let deckBefore = e.deck.remaining()
        e.debugFireSamePower(0); e.debugFireSamePower(1)
        XCTAssertEqual(e.run.pendingPurges, 2, "one purge queued per correct Same")
        XCTAssertEqual(e.deck.remaining(), deckBefore, "nothing is purged NOW — it resolves at deal end")
        let twin = build()
        XCTAssertTrue(twin.restoreSnapshot(e.snapshot()))
        XCTAssertEqual(twin.run.pendingPurges, 2, "the queue survives a mid-deal kill")
        // The campaign banks the count, serializes it, drains it per pick,
        // and a new climb owes nothing.
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular"); c.setSeedOverride(7); c.reset()
        c.addPendingPurges(e.run.pendingPurges)
        XCTAssertEqual(c.pendingPurges, 2)
        let c2 = CampaignState(store: MemoryStore())
        XCTAssertTrue(c2.restore(c.serialize()))
        XCTAssertEqual(c2.pendingPurges, 2, "owed purges survive the campaign save")
        c2.consumePendingPurge()
        XCTAssertEqual(c2.pendingPurges, 1)
        c2.setSeedOverride(8); c2.reset()
        XCTAssertEqual(c2.pendingPurges, 0, "a new climb owes nothing")
    }

    // MARK: - 5. Scarce Suit: ties → every tied suit is safe

    func testScarceSuitTiesShieldEveryTiedSuit() {
        // Full deck ♠2 ♥1 ♦2 ♣1 → ♥ and ♣ tie for fewest.
        let e = IV.engine(tops: [spec(1, 9, "♠"), spec(2, 6, "♠"), spec(3, 7, "♥")],
                          deckOrder: [spec(50, 2, "♣"), spec(51, 9, "♦"), spec(52, 9, "♦")],
                          pillars: ["suitShield", nil, nil])
        XCTAssertEqual(Set((e.run.dailySuits?[0] ?? "").map(String.init)), ["♥", "♣"],
                       "both tied suits are shielded")
        e.guess(0, .higher)   // 2♣ on 9♠: wrong — but ♣ is a scarce suit → safe
        XCTAssertTrue(e.board.isActive(0), "a tied scarce suit is safe in the column")
        // Same composition, a ♦ carrier: not scarce → the wrong call kills.
        let d = IV.engine(tops: [spec(1, 9, "♠"), spec(2, 6, "♠"), spec(3, 7, "♥")],
                          deckOrder: [spec(50, 2, "♦"), spec(51, 9, "♦"), spec(52, 9, "♣")],
                          pillars: ["suitShield", nil, nil])
        XCTAssertEqual(Set((d.run.dailySuits?[0] ?? "").map(String.init)), ["♥", "♣"])
        d.guess(0, .higher)
        XCTAssertFalse(d.board.isActive(0), "a non-scarce suit gets no shield")
    }

    // MARK: - 8. Debug: small, fully revealed packs

    func testDebugSmallRevealedPacksCapAtThreeAndCommitEveryPack() {
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular")
        c.setDebugSmallRevealedPacks(true)
        c.setSeedOverride(4242); c.reset()
        let packs = c.runMap!.nodes.filter { $0.type == "pack" }
        XCTAssertFalse(packs.isEmpty, "the map has packs to check")
        for n in packs {
            XCTAssertLessThanOrEqual(n.addOf, 3, "node \(n.id): pickups cap at +3")
            XCTAssertEqual(c.packNodeCards(n).count, n.addOf, "node \(n.id): every pack is face-up (no sealed packs)")
        }
        for n in c.runMap!.nodes where n.type == "pickup" {
            XCTAssertLessThanOrEqual(n.addOf, 3)
        }
        if let p3 = packs.first(where: { $0.addOf == 3 }) {
            let shown = c.packNodeCards(p3).map(\.id)
            XCTAssertEqual(c.resolvePack(p3).map(\.id), shown, "a revealed +3 grants exactly what it showed")
        }
        // Flag off: the next climb seals +3 packs again and can roll +4/+5.
        c.setDebugSmallRevealedPacks(false)
        c.setSeedOverride(4242); c.reset()
        let sealed = c.runMap!.nodes.filter { $0.type == "pack" && $0.addOf >= 3 && c.packNodeCards($0).isEmpty }
        XCTAssertFalse(sealed.isEmpty, "flag off: big packs are sealed again")
    }

    // MARK: - Review pins: per-instance conversion; iconSuit is a real suit

    func testDuplicateInstancesConvertPerInstanceOnAKill() {
        let e = killEngine(["tell", "tell"])
        e.guess(0, .higher)
        let buried = e.board.piles[0].cards.last!
        XCTAssertFalse(buried.stickers.contains { $0.type == "tell" }, "both instances converted")
        XCTAssertEqual(curses(buried).count, 2, "one curse per instance")
    }

    func testEveryIconSuitIsARealSuitSymbol() {
        // ItemArt.drawIconSuitBadge draws NOTHING for an unknown symbol, so a
        // typo in items.js would fail silently without this pin.
        let symbols = Set(DeckManager.suits.map(\.symbol))
        var badged = 0
        for def in data.pillarTypes.all() + data.baseTypes.all() {
            guard let s = def.raw["iconSuit"]?.asString else { continue }
            badged += 1
            XCTAssertTrue(symbols.contains(s), "\(def.id): iconSuit '\(s)' is not a suit symbol")
        }
        XCTAssertEqual(badged, 17, "the v7.07 sweep badged 17 pillars/bases")
    }
}
