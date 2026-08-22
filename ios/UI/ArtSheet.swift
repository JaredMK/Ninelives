import UIKit
import GameCore

/// ART SPECIMEN SHEET (debug, `-artSheet 1`) — the ARCHETYPE BATCH v6.76 item
/// art on one evidence still: every new pillar pennant, base plaque and the
/// Rank Flood Same-Power diamond, labelled, on the felt. Same harness idiom
/// as `-curseSheet 1` (GameFlowController boots it over whatever screen the
/// other launch args staged); the EventCaptureUITests pattern drives it.
extension GameFlowController {

    /// The v6.76 batch, grouped by class (registry ids — the art keys).
    private static let artSheetPillars = [
        "zeroRanksBury", "eightStart", "royalSanctuary", "absentSuitClubBury",
        "suitMajoritySafe", "diamondDupeSize", "sameTolNear", "sameTolRoyal",
        "sameTolSum10", "sameTolSuit", "rankShield", "suitShield",
        "purgeFlatFive", "firstFree", "eightPeek", "pauperHeart",
        "pauperDiamond", "pauperSpade", "pauperClub", "curseHarvest",
        "clubThin", "purgeRank", "sizeOneDiamonds",
    ]
    private static let artSheetBases = [
        "purgeDiscount", "transmute", "sacrifice", "devilsDeal",
        "cleanseColumn", "chorus", "diamondBoost",
    ]
    private static let artSheetSamePowers = ["rankFlood"]

    func showArtSheet() {
        let data = GameData.shared
        let panel = UIScrollView()
        panel.backgroundColor = CRT.feltDeep
        panel.frame = view.bounds
        panel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let cols = 4
        let colW = view.bounds.width / CGFloat(cols)
        let cellH: CGFloat = 108
        var y: CGFloat = 56

        func sectionHeader(_ text: String) {
            let h = CRTKit.label(text, size: 16, color: CRT.phosphor, display: true)
            h.frame = CGRect(x: 16, y: y, width: view.bounds.width - 32, height: 20)
            panel.addSubview(h)
            y += 28
        }
        func cell(_ i: Int, art: UIImage, name: String) {
            let x = CGFloat(i % cols) * colW
            let row = i / cols
            let iv = UIImageView(image: art)
            iv.layer.magnificationFilter = .nearest
            iv.contentMode = .scaleAspectFit
            iv.frame = CGRect(x: x + 10, y: y + CGFloat(row) * cellH,
                              width: colW - 20, height: 72)
            panel.addSubview(iv)
            let name = CRTKit.label(name, size: 12, color: CRT.gold)
            name.textAlignment = .center
            name.frame = CGRect(x: x + 4, y: y + CGFloat(row) * cellH + 74,
                                width: colW - 8, height: 30)
            panel.addSubview(name)
        }

        let title = CRTKit.label("ARCHETYPE BATCH v6.76 — ITEM ART", size: 18,
                                 color: CRT.cardFace, display: true)
        title.frame = CGRect(x: 16, y: 26, width: view.bounds.width - 32, height: 22)
        panel.addSubview(title)

        sectionHeader("PILLARS")
        var n = 0
        for id in GameFlowController.artSheetPillars {
            guard let d = data.pillarTypes.get(id) else { continue }
            cell(n, art: ItemArt.pillar(d, width: 52, height: 66), name: d.label)
            n += 1
        }
        y += CGFloat((n + cols - 1) / cols) * cellH + 12

        sectionHeader("BASES")
        let basesTop = y
        n = 0
        for id in GameFlowController.artSheetBases {
            guard let d = data.baseTypes.get(id) else { continue }
            cell(n, art: ItemArt.base(d, width: 66, height: 44), name: d.label)
            n += 1
        }
        y += CGFloat((n + cols - 1) / cols) * cellH + 12

        sectionHeader("SAME-POWER")
        n = 0
        for id in GameFlowController.artSheetSamePowers {
            guard let d = data.samePowerTypes.get(id) else { continue }
            cell(n, art: ItemArt.samePower(d, width: 56, height: 56), name: d.label)
            n += 1
        }
        y += CGFloat((n + cols - 1) / cols) * cellH + 12

        panel.contentSize = CGSize(width: view.bounds.width, height: y)
        view.insertSubview(panel, belowSubview: crt)
        // `-artSheetPage 2` scrolls straight to the BASES section (the sheet is
        // taller than one screen; page 1 is the pillar grid).
        if UserDefaults.standard.integer(forKey: "artSheetPage") == 2 {
            panel.setContentOffset(CGPoint(x: 0, y: basesTop - 40), animated: false)
        }
    }
}
