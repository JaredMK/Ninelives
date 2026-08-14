import Foundation

/// v6.52: the debug screen's EVENT LOG — a run-long, in-memory record of
/// everything that fires, so "did that item actually trigger?" has an answer
/// on the device. Two feeds: the ENGINE's per-deal logbook (item triggers,
/// curses, saves, RNG-driven outcomes — drained after every action) and
/// campaign-level lines (price twists, purchases, mystery outcomes) added at
/// the site that executes them. Dev tooling only — nothing in game logic
/// reads it, it is never persisted, and it caps itself.
public final class DebugEventLog {
    public static let shared = DebugEventLog()
    private init() {}

    public private(set) var lines: [String] = []
    private var consumedEngineEntries = 0
    private let cap = 600

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    public func add(_ line: String) {
        lines.append("[\(Self.stamp.string(from: Date()))] \(line)")
        if lines.count > cap { lines.removeFirst(lines.count - cap) }
    }

    /// Pull any NEW engine logbook entries (called after every engine action;
    /// the cursor makes it idempotent). `resetEngineCursor` on each new deal.
    public func drainEngine(_ run: RunState?) {
        guard let run else { return }
        while consumedEngineEntries < run.log.count {
            let e = run.log[consumedEngineEntries]
            add(e.title)
            for l in e.lines { add("   \(l)") }
            consumedEngineEntries += 1
        }
    }

    public func resetEngineCursor() { consumedEngineEntries = 0 }
    public func text() -> String { lines.joined(separator: "\n") }
    public func clear() { lines = []; consumedEngineEntries = 0 }
}
