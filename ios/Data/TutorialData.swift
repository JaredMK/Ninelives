import Foundation

/// One coach-bubble step.
public struct TutorialStep: Sendable, Equatable {
    public let text: String
    /// Button label; nil = the group's default.
    public let button: String?
    /// WHICH on-screen element the bubble points at; nil = centered, arrow-less.
    public let anchor: String?
}

/// The Swift twin of `TutorialData` — loads + VALIDATES tutorial.json.
///
/// Validation is deliberately SOFTER than items/difficulty (matching the web):
/// a missing FILE still throws (the loader broke), but a malformed group/step
/// only records a problem — the game must never brick on a copy typo, so the
/// tour bows out gracefully at runtime instead. `problems` carries what would
/// have been `console.error` lines.
public struct TutorialData: Sendable {
    /// The writer-owned groups and their EXACT step counts. The tour's
    /// choreography lives in code — tutorial.js may reword a bubble, never add
    /// or remove one. (v5.60: the Ace-high bubble was cut.)
    public static let stepCounts: [(key: String, count: Int)] = [("deal", 6), ("zenEnd", 1)]
    /// The Zen-first tour carries no live placeholders: any {token} is an error.
    public static let placeholders: [String] = []

    public let groups: [String: [TutorialStep]]
    public let problems: [String]

    public func steps(_ key: String) -> [TutorialStep] { groups[key] ?? [] }

    /// Iterate every writer step (the Tutorial module audits anchor keys with this).
    public func eachStep(_ body: (TutorialStep, String) -> Void) {
        for (key, _) in Self.stepCounts {
            guard let list = groups[key] else { continue }
            for (i, s) in list.enumerated() { body(s, "groups.\(key)[\(i)]") }
        }
    }

    public static func decode(_ data: Data) throws -> TutorialData {
        let root: [String: JSONValue]
        do {
            root = try JSONDecoder().decode([String: JSONValue].self, from: data)
        } catch {
            // A file that won't parse is the loader-broke case → throw.
            throw DataValidationError(file: "tutorial.js", problems: ["[tutorial.js] not valid JSON: \(error)"])
        }
        var problems: [String] = []
        var groups: [String: [TutorialStep]] = [:]

        let placeholderPattern = try! NSRegularExpression(pattern: "\\{(\\w+)\\}")

        func checkStep(_ v: JSONValue?, _ label: String) -> TutorialStep {
            func bad(_ msg: String) { problems.append("[tutorial.js] \(label): \(msg)") }
            guard let d = v?.asObject else { bad("missing step"); return TutorialStep(text: "", button: nil, anchor: nil) }
            let text = d["text"]?.asString
            if (text ?? "").isEmpty {
                bad("missing/invalid `text` (string)")
            } else if let text {
                let ns = text as NSString
                for m in placeholderPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                    let token = ns.substring(with: m.range)
                    let inner = String(token.dropFirst().dropLast())
                    if !placeholders.contains(inner) {
                        bad("unknown placeholder \(token) (the Zen-first tour supports none)")
                    }
                }
            }
            if let b = d["button"], !b.isNull, (b.asString ?? "").isEmpty {
                bad("`button` must be a non-empty string when set")
            }
            if let a = d["anchor"], !a.isNull, (a.asString ?? "").isEmpty {
                bad("`anchor` must be an anchor-key string when set")
            }
            return TutorialStep(text: text ?? "", button: d["button"]?.asString, anchor: d["anchor"]?.asString)
        }

        if let g = root["groups"]?.asObject {
            for (key, count) in stepCounts {
                guard let list = g[key]?.asArray, list.count == count else {
                    problems.append("[tutorial.js] groups.\(key): must be an array of exactly \(count) step\(count == 1 ? "" : "s")")
                    continue
                }
                groups[key] = list.enumerated().map { checkStep($1, "groups.\(key)[\($0)]") }
            }
        } else {
            problems.append("[tutorial.js] groups: missing object")
        }

        return TutorialData(groups: groups, problems: problems)
    }
}
