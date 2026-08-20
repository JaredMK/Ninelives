import XCTest
@testable import GameCore

/// THE CAST'S OWN MYSTERY OUTCOMES — the Beheaded Queen's gifts and Just a
/// Two's tricks, added natively. One section per outcome: what it does, its
/// fold when inapplicable, and (for the pending flags) the full arm → apply →
/// clear lifecycle including a save round-trip.
final class MysteryCastOutcomeTests: XCTestCase {

    private let data = GameData.shared

    private func campaign(seed: UInt32 = 4242, deck: String = "pink") -> CampaignState {
        let c = CampaignState()
        c.setDeck(deck); c.setSeedOverride(seed); c.reset()
        return c
    }

    // MARK: - Just a Two

    func testStickerTheftStripsARandomCardBare() {
        let c = campaign()
        // Sticker two cards so the roll has a real pool.
        for id in c.getRunDeck().prefix(2).map(\.id) {
            XCTAssertTrue(c.applyStickerDirect(id, "rankUp"), "setup: sticker card \(id)")
        }
        let stickeredBefore = c.getRunDeck().filter { !$0.stickers.isEmpty }.count
        guard stickeredBefore > 0 else { return XCTFail("setup failed to sticker any card") }
        let o = c.applyMysteryEvent("stickerTheft", nodeId: 3)
        XCTAssertEqual(o?.key, "stickerTheft")
        XCTAssertEqual(c.getRunDeck().filter { !$0.stickers.isEmpty }.count, stickeredBefore - 1,
                       "exactly one card is stripped BARE")
        if let cid = o?.cardId {
            XCTAssertEqual(c.getRunDeck().first { $0.id == cid }?.stickers.count, 0)
        }
    }

    func testStickerTheftFoldsToATollWithNothingToSteal() {
        let c = campaign()
        c.addCoins(5)
        let o = c.applyMysteryEvent("stickerTheft", nodeId: 3)
        XCTAssertEqual(o?.key, "coinLoss", "no stickered card → the Toll")
    }

    func testItemTheftTakesARandomEquippedPillarOrBase() {
        let c = campaign()
        c.setColumnPillar(col: 0, typeId: data.items.pillars[0].id)
        c.setColumnBase(col: 1, typeId: data.items.bases[0].id)
        let before = c.equippedHoldings().filter { $0.kind != .sticker }.count
        let o = c.applyMysteryEvent("itemTheft", nodeId: 4)
        XCTAssertEqual(o?.key, "itemTheft")
        XCTAssertNotNil(o?.itemKind); XCTAssertNotNil(o?.itemId)
        XCTAssertEqual(c.equippedHoldings().filter { $0.kind != .sticker }.count, before - 1,
                       "one equipped item is gone — not pocketed, gone")
    }

    func testItemTheftFoldsToATollWithNothingEquipped() {
        let c = campaign()
        c.addCoins(5)
        XCTAssertEqual(c.applyMysteryEvent("itemTheft", nodeId: 4)?.key, "coinLoss")
    }

    func testShieldDrainEmptiesAChargedShieldAndFoldsOtherwise() {
        let c = campaign()
        c.setSameCharge(true)
        XCTAssertEqual(c.applyMysteryEvent("shieldDrain", nodeId: 5)?.key, "shieldDrain")
        XCTAssertFalse(c.getSameCharge(), "the charge is drained")
        c.addCoins(5)
        XCTAssertEqual(c.applyMysteryEvent("shieldDrain", nodeId: 6)?.key, "coinLoss",
                       "an empty shield folds to the Toll")
    }

    func testPriceDoubleAndPriceOneRideTheNextShopUntilARefresh() {
        for (key, expect): (String, (Double) -> Double) in
            [("priceDouble", { $0 * 2 }), ("priceOne", { min($0, 1) })] {
            let c = campaign()
            c.addCoins(200)
            let sticker = data.items.stickers.first { !$0.cursed }!
            let normal = c.shopPrice(sticker.price)
            XCTAssertEqual(c.applyMysteryEvent(key, nodeId: 7)?.key, key)
            XCTAssertEqual(c.priceOf(sticker.id), normal,
                           "\(key): armed but NOT live before the shop opens")
            _ = c.openStore()
            XCTAssertEqual(c.priceOf(sticker.id), expect(normal), "\(key): live in the shop")
            XCTAssertTrue(c.rerollStore(), "\(key): the refresh must be affordable")
            XCTAssertEqual(c.priceOf(sticker.id), normal, "\(key): a refresh clears it")
            _ = c.applyMysteryEvent(key, nodeId: 9)
            _ = c.openStore()
            _ = c.openStore()
            // A SECOND shop must not inherit the twist: pending was consumed
            // by the first open, and the reopen arms nothing.
            XCTAssertEqual(c.priceOf(sticker.id), normal, "\(key): one shop only")
        }
    }

    // MARK: - The Beheaded Queen

    func testShieldChargeFillsAnEmptyShieldAndFoldsOtherwise() {
        let c = campaign()
        XCTAssertEqual(c.applyMysteryEvent("shieldCharge", nodeId: 5)?.key, "shieldCharge")
        XCTAssertTrue(c.getSameCharge(), "the shield is charged, on her")
        XCTAssertEqual(c.applyMysteryEvent("shieldCharge", nodeId: 6)?.key, "coinBonus",
                       "an already-charged shield folds to the Cache")
    }

    func testCoinDoubleMatchesThePurseAndFoldsAtZero() {
        let c = campaign()
        c.spendCoins(c.getCoins())
        XCTAssertEqual(c.applyMysteryEvent("coinDouble", nodeId: 5)?.key, "coinBonus",
                       "an empty purse folds to the Cache")
        let c2 = campaign()
        c2.spendCoins(c2.getCoins())
        c2.addCoins(7)
        let o = c2.applyMysteryEvent("coinDouble", nodeId: 5)
        XCTAssertEqual(o?.key, "coinDouble")
        XCTAssertEqual(c2.getCoins(), 14, "the purse is matched")
    }

    func testGiftCardMintsAStickeredTrayCard() {
        let c = campaign()
        let trayBefore = c.getPackTray().count
        let deckBefore = c.deckSize()
        let o = c.applyMysteryEvent("giftCard", nodeId: 8)
        XCTAssertEqual(o?.key, "giftCard")
        XCTAssertEqual(c.getPackTray().count, trayBefore + 1, "the keepsake waits in the tray")
        XCTAssertEqual(c.deckSize(), deckBefore, "…and the OWNED deck hasn't grown (swap, not gift)")
        let card = c.getPackTray().last!
        XCTAssertFalse(card.joker); XCTAssertFalse(card.blank)
        XCTAssertTrue((2...3).contains(card.stickers.count),
                      "her keepsake wears 2–3 stickers (got \(card.stickers.count))")
    }

    func testGiftCardForRockoComesClean() {
        let c = campaign(deck: "rocko")
        guard c.rules().noStickers else { return }   // only meaningful for the no-sticker deck
        let o = c.applyMysteryEvent("giftCard", nodeId: 8)
        XCTAssertEqual(o?.key, "giftCard")
        XCTAssertEqual(c.getPackTray().last?.stickers.count, 0, "Rocko's keepsake takes no stickers")
    }

    func testFreeRefreshCompsTheNextShopsFirstRefreshOnly() {
        let c = campaign()
        c.addCoins(100)
        XCTAssertEqual(c.applyMysteryEvent("freeRefresh", nodeId: 7)?.key, "freeRefresh")
        XCTAssertTrue(c.freeRerollPending)
        _ = c.openStore()
        XCTAssertEqual(c.storeRerollCost(), 0, "the first refresh is free")
        XCTAssertFalse(c.freeRerollPending, "…and the boon is spent on this visit")
        let coinsBefore = c.getCoins()
        XCTAssertTrue(c.rerollStore())
        XCTAssertEqual(c.getCoins(), coinsBefore, "the free refresh charged nothing")
        let base = data.items.store.reroll.baseCost, step = data.items.store.reroll.step
        XCTAssertEqual(c.storeRerollCost(), base + step,
                       "the ladder continues as if the free rung was bought — never a duplicate shelf index")
    }

    func testFreeRedealArmsOnceAndSurvivesASave() {
        let c = campaign()
        XCTAssertEqual(c.applyMysteryEvent("freeRedeal", nodeId: 7)?.key, "freeRedeal")
        XCTAssertTrue(c.freeRedealPending)
        // The flag must survive a relaunch between the node and the deal.
        let c2 = campaign()
        XCTAssertTrue(c2.restore(c.serialize()))
        XCTAssertTrue(c2.freeRedealPending)
        XCTAssertTrue(c2.consumeFreeRedeal(), "the next deal claims it")
        XCTAssertFalse(c2.consumeFreeRedeal(), "…exactly once")
    }

    /// v6.64: her Cleanse strips the chosen card BARE — every sticker, not
    /// one random one (the picker copy always said "strip the stickers").
    func testStripAllStickersFromLeavesTheCardBare() {
        let c = campaign()
        guard let card = c.getRunDeck().first(where: { !$0.joker && !$0.blank }) else {
            return XCTFail("setup: no plain card in the deck")
        }
        // Two distinct unrestricted, non-cursed stickers, so "all" > 1.
        let open = data.stickerTypes.all().filter { !$0.cursed && ($0.suits ?? []).isEmpty }
        guard open.count >= 2 else { return XCTFail("setup: need two unrestricted sticker types") }
        XCTAssertTrue(c.applyStickerDirect(card.id, open[0].id), "setup: sticker one")
        XCTAssertTrue(c.applyStickerDirect(card.id, open[1].id), "setup: sticker two")
        XCTAssertEqual(c.getRunDeck().first { $0.id == card.id }?.stickers.count, 2,
                       "setup: the card carries two stickers")
        let removed = c.stripAllStickersFrom(card.id)
        XCTAssertEqual(Set(removed), Set([open[0].id, open[1].id]),
                       "EVERY sticker goes, and the removed ids are reported")
        XCTAssertEqual(c.getRunDeck().first { $0.id == card.id }?.stickers.count, 0,
                       "the chosen card comes back bare")
        XCTAssertTrue(c.stripAllStickersFrom(card.id).isEmpty,
                      "a bare card has nothing to strip")
    }

    func testPriceModsSurviveASaveInBothStates() {
        let c = campaign()
        _ = c.applyMysteryEvent("priceDouble", nodeId: 7)
        let armed = campaign()
        XCTAssertTrue(armed.restore(c.serialize()))
        XCTAssertEqual(armed.storePriceModPending, "double")
        _ = armed.openStore()
        let live = campaign()
        XCTAssertTrue(live.restore(armed.serialize()))
        XCTAssertNil(live.storePriceModPending)
        XCTAssertEqual(live.storePriceModActive, "double",
                       "a relaunch mid-visit keeps the twist live")
    }

    func testMammaLieTakesAndGivesNothing() {
        // No ★ Joker held → the con folds to a Toll.
        let c = campaign()
        c.addCoins(5)
        XCTAssertEqual(c.applyMysteryEvent("mammaLie", nodeId: 5)?.key, "coinLoss")
        // With one: the OFFER itself takes nothing until a choice is made…
        let c2 = campaign()
        c2.addCoins(9)
        let jid = c2.mintJokerId()
        c2.ownedIds.append(jid)
        let purse = c2.getCoins()
        XCTAssertEqual(c2.applyMysteryEvent("mammaLie", nodeId: 5)?.key, "mammaLie")
        XCTAssertEqual(c2.getCoins(), purse, "the offer itself takes nothing")
        // …the coins branch drains the purse and gives NOTHING back…
        let deckBefore = c2.deckSize()
        let r = c2.resolveMammaLie(givingCoins: true)
        XCTAssertEqual(r.coinsTaken, purse)
        XCTAssertEqual(c2.getCoins(), 0)
        XCTAssertEqual(c2.deckSize(), deckBefore, "he was lying — nothing arrives")
        // …and the joker branch removes exactly one ★, nothing else.
        let r2 = c2.resolveMammaLie(givingCoins: false)
        XCTAssertTrue(r2.jokerTaken)
        XCTAssertFalse(c2.getRunDeck().contains { $0.joker })
        XCTAssertEqual(c2.deckSize(), deckBefore - 1)
    }

    func testTwoGameNeedsAChargedShieldAndOnlyALossDrainsIt() {
        // Shield empty → the game folds to a Toll.
        let c = campaign()
        c.addCoins(5)
        c.setSameCharge(false)
        XCTAssertEqual(c.applyMysteryEvent("twoGame", nodeId: 7)?.key, "coinLoss")
        // Charged: the offer rolls a hidden card and takes NOTHING itself.
        let c2 = campaign()
        c2.setSameCharge(true)
        guard let o = c2.applyMysteryEvent("twoGame", nodeId: 7) else {
            XCTFail("twoGame should produce an outcome"); return
        }
        XCTAssertEqual(o.key, "twoGame")
        let rank = o.amount ?? 0
        XCTAssertTrue((minRank...maxRank).contains(rank), "the hidden card is a real rank")
        XCTAssertEqual(o.cards.first?.currentRank, rank, "the phantom card matches the roll")
        guard let suit = o.cards.first?.suit else { return XCTFail("no hidden card") }
        // The hidden card is always one of the four standard suits — a ★
        // Joker can never sit there, so every roll has a color.
        guard let red = DeckManager.suits.first(where: { $0.symbol == suit })?.red else {
            return XCTFail("the hidden card's suit has no color: \(suit)")
        }
        XCTAssertTrue(c2.getSameCharge(), "the offer itself drains nothing")
        // A CORRECT color call wins nothing and keeps the shield…
        let rightCall = red ? "red" : "black"
        let deckBefore = c2.deckSize(), purse = c2.getCoins()
        XCTAssertTrue(c2.resolveTwoGame(suit: suit, guess: rightCall))
        XCTAssertTrue(c2.getSameCharge())
        XCTAssertEqual(c2.deckSize(), deckBefore, "you win NOTHING")
        XCTAssertEqual(c2.getCoins(), purse)
        // …and a wrong one drains it and takes nothing else.
        let wrongCall = red ? "black" : "red"
        XCTAssertFalse(c2.resolveTwoGame(suit: suit, guess: wrongCall))
        XCTAssertFalse(c2.getSameCharge())
        XCTAssertEqual(c2.deckSize(), deckBefore)
        XCTAssertEqual(c2.getCoins(), purse)
        // Determinism: the same run+node hides the same card — suit AND rank.
        let c3 = campaign()
        c3.setSameCharge(true)
        let o3 = c3.applyMysteryEvent("twoGame", nodeId: 7)
        XCTAssertEqual(o3?.amount, rank)
        XCTAssertEqual(o3?.cards.first?.suit, suit)
    }

    /// v6.65: the call is RED-or-BLACK against the hidden card's COLOR
    /// (♥♦ red, ♠♣ black) — the old higher/lower/same pivot is gone, and the
    /// `mystery.twoGame` config block with it. Every suit, both calls: the
    /// right color wins NOTHING and keeps the shield; the wrong one drains
    /// it and takes nothing else.
    func testTwoGameResolvesOnColorBothWays() {
        // The pivot knob is dead — the config block must not come back.
        XCTAssertNil(data.items.mystery.raw["twoGame"],
                     "mystery.twoGame was retired with the pivot (v6.65)")
        for s in DeckManager.suits {
            for guess in ["red", "black"] {
                let c = campaign()
                c.setSameCharge(true)
                c.addCoins(9)
                let purse = c.getCoins(), size = c.deckSize()
                let expectWin = guess == (s.red ? "red" : "black")
                XCTAssertEqual(c.resolveTwoGame(suit: s.symbol, guess: guess), expectWin,
                               "\(s.symbol) is \(s.red ? "red" : "black"); calling \(guess)")
                XCTAssertEqual(c.getSameCharge(), expectWin,
                               "a win keeps the Same shield, a loss drains it")
                XCTAssertEqual(c.getCoins(), purse, "the game never moves coins")
                XCTAssertEqual(c.deckSize(), size, "the game never moves cards")
            }
        }
    }

    // MARK: - The Old Joker's star-for-flags

    func testJokerForPillarsTakesEveryPillarAndMintsOneJoker() {
        let c = campaign()
        for (i, p) in data.items.pillars.prefix(CampaignLayout.columnSlots).enumerated() {
            c.setColumnPillar(col: i, typeId: p.id)
        }
        let pillars = c.equippedHoldings().filter { $0.kind == .pillar }
        XCTAssertFalse(pillars.isEmpty)
        let jokersBefore = c.getRunDeck().filter(\.joker).count
        let r = c.resolveOldJoker(.jokerForPillars(pillars: pillars), choice: .accept, nodeId: 5)
        XCTAssertNotNil(r)
        XCTAssertTrue(c.equippedHoldings().filter { $0.kind == .pillar }.isEmpty,
                      "every Pillar comes down")
        XCTAssertEqual(c.getRunDeck().filter(\.joker).count, jokersBefore + 1,
                       "exactly one ★ Joker joins the deck")
        // The closing modal's result container draws the star itself.
        XCTAssertEqual(r?.cards.first?.joker, true, "the minted ★ rides on the Result")
        XCTAssertEqual(r?.cards.first?.id, r?.cardId)
    }

    func testJokerForPillarsNeedsPillarsAndCapRoom() {
        let c = campaign()
        XCTAssertFalse(OldJoker.offerKeysEligible(in: c).contains("jokerForPillars"),
                       "no Pillars → not offered")
        c.setColumnPillar(col: 0, typeId: data.items.pillars[0].id)
        // Held-vs-cap, like the mystery Wild Card — NOT jokersAllowed(),
        // which a fixed-joker tier turns off wholesale.
        XCTAssertEqual(OldJoker.offerKeysEligible(in: c).contains("jokerForPillars"),
                       c.jokersHeld() < c.jokerCapFor(),
                       "offered exactly when the joker cap has room")
    }

    // MARK: - The weights surface

    func testEveryNewOutcomeHasAWeight() {
        for k in MysteryConfig.outcomeKeys {
            XCTAssertGreaterThan(data.items.mystery.weights[k] ?? 0, 0,
                                 "\(k): needs a positive mystery weight")
        }
    }
}
