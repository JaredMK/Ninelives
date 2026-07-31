import XCTest
@testable import GameCore

/// Loads `Fixtures/seed-fixtures.json` — the ground truth captured from the REAL
/// web engine by `ios/Tools/export-fixtures.mjs`.
enum Fixtures {
    static let root: [String: JSONValue] = {
        let bundle = Bundle(for: FixtureAnchor.self)
        guard let url = bundle.url(forResource: "seed-fixtures", withExtension: "json") else {
            fatalError("seed-fixtures.json is not in the test bundle — run `node ios/Tools/export-fixtures.mjs`")
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([String: JSONValue].self, from: data)
        } catch {
            fatalError("seed-fixtures.json failed to load: \(error)")
        }
    }()

    static func array(_ key: String) -> [JSONValue] { root[key]?.asArray ?? [] }
    static func object(_ key: String) -> [String: JSONValue] { root[key]?.asObject ?? [:] }
}

private final class FixtureAnchor {}

extension JSONValue {
    var int: Int? { asInt }
    var intArray: [Int] { asArray?.compactMap(\.asInt) ?? [] }
    var doubleArray: [Double] { asArray?.compactMap(\.asNumber) ?? [] }
    var stringArray: [String] { asArray?.compactMap(\.asString) ?? [] }
}

/// A canonical, comparable rendering of one generated node — the exact shape
/// `canonicalNode()` writes on the JS side, so a mismatch prints as a readable
/// diff instead of "objects differ".
struct CanonicalNode: Equatable, CustomStringConvertible {
    var id: Int
    var row: Int
    var type: String
    var lane: Int?
    var localRow: Int?
    var phase: Int?
    var piles: Int?
    var packCount: Int?
    var add: Int?
    var suit: String?
    var mystery: Bool
    var jokerNode: Bool
    var next: [Int]

    init(_ n: MapNode) {
        id = n.id; row = n.row; type = n.type
        lane = n.lane; localRow = n.localRow; phase = n.phase
        piles = n.piles; packCount = n.packCount; add = n.add; suit = n.suit
        mystery = n.mystery; jokerNode = n.jokerNode; next = n.next
    }

    init(fixture v: JSONValue) {
        id = v["id"]?.int ?? -1
        row = v["row"]?.int ?? -1
        type = v["type"]?.asString ?? ""
        lane = v["lane"]?.int
        localRow = v["localRow"]?.int
        phase = v["phase"]?.int
        piles = v["piles"]?.int
        packCount = v["packCount"]?.int
        add = v["add"]?.int
        suit = v["suit"]?.asString
        mystery = v["mystery"]?.asBool ?? false
        jokerNode = v["jokerNode"]?.asBool ?? false
        next = v["next"]?.intArray ?? []
    }

    var description: String {
        var s = "#\(id) r\(row) \(type)"
        if let lane { s += " lane\(lane)" }
        if let piles { s += " \(piles)p" }
        if let packCount { s += " pack+\(packCount)" }
        if let add { s += " add\(add)" }
        if let suit { s += " \(suit)" }
        if mystery { s += " ?" }
        if jokerNode { s += " ★node" }
        s += " → \(next)"
        return s
    }
}
