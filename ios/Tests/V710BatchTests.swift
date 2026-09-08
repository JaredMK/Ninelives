import XCTest
@testable import GameCore

/// v7.10 — small, fully revealed packs are the DEFAULT: a fresh install (no
/// pref written) generates +3-capped, face-up packs; the debug toggle turns
/// it off by writing "0".
final class V710BatchTests: XCTestCase {

    func testSmallRevealedPacksAreOnForAFreshInstall() {
        // A fresh store has NO pref — that must read as ON.
        let c = CampaignState(store: MemoryStore())
        XCTAssertNil(c.saveStore.pref("debugSmallRevealedPacks"), "setup: nothing written")
        XCTAssertTrue(c.debugSmallRevealedPacksOn(), "unset reads as ON (the fresh-install default)")
        c.setDeck("pink"); c.setTier("regular"); c.setSeedOverride(4242); c.reset()
        let packs = c.runMap!.nodes.filter { $0.type == "pack" }
        XCTAssertFalse(packs.isEmpty)
        for n in packs {
            XCTAssertLessThanOrEqual(n.addOf, 3, "node \(n.id): a fresh climb caps packs at +3")
            XCTAssertEqual(c.packNodeCards(n).count, n.addOf, "node \(n.id): …and every pack is face-up")
        }
        // The debug toggle still turns it OFF — explicitly, by writing "0".
        c.setDebugSmallRevealedPacks(false)
        XCTAssertEqual(c.saveStore.pref("debugSmallRevealedPacks"), "0")
        XCTAssertFalse(c.debugSmallRevealedPacksOn())
        c.setDebugSmallRevealedPacks(true)
        XCTAssertTrue(c.debugSmallRevealedPacksOn())
    }

    func testTheRunCapturesItsPackConfigSoRestoreRegeneratesTheSameMap() {
        // Generated under the default (small packs ON).
        let c = CampaignState(store: MemoryStore())
        c.setDeck("pink"); c.setTier("regular"); c.setSeedOverride(11); c.reset()
        XCTAssertTrue(c.smallPacksRun, "the run captured the flag it was generated with")
        let ids = c.runMap!.nodes.map(\.id)
        let sizes = c.runMap!.nodes.filter { $0.type == "pack" }.map(\.addOf)
        // A restore into a store whose LIVE pref says OFF must still rebuild
        // the identical map — the captured flag wins, never the pref.
        let store = MemoryStore()
        let twin = CampaignState(store: store)
        twin.setDebugSmallRevealedPacks(false)
        XCTAssertTrue(twin.restore(c.serialize()))
        XCTAssertTrue(twin.smallPacksRun, "the captured flag rides the save")
        XCTAssertEqual(twin.runMap!.nodes.map(\.id), ids, "restore regenerates the SAME map")
        XCTAssertEqual(twin.runMap!.nodes.filter { $0.type == "pack" }.map(\.addOf), sizes, "…same pack sizes")
        // …and its packs still resolve face-up off the captured flag, not the pref.
        if let p = twin.runMap!.nodes.first(where: { $0.type == "pack" }) {
            XCTAssertEqual(twin.packNodeCards(p).count, p.addOf, "the run's packs stay committed")
        }
        // A mid-climb toggle changes NOTHING for this run — only the next climb.
        c.setDebugSmallRevealedPacks(false)
        XCTAssertTrue(c.smallPacksRun)
        c.setSeedOverride(12); c.reset()
        XCTAssertFalse(c.smallPacksRun, "the next climb reads the toggle")
        XCTAssertTrue(c.runMap!.nodes.contains { $0.type == "pack" && $0.addOf > 3 || ($0.type == "pack" && c.packNodeCards($0).isEmpty) },
                      "flag off: big or sealed packs come back")
    }
}
