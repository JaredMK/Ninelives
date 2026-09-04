import Foundation

/// IN-DEAL EVENT FEED (v7.01, debug-toggleable) — the recT stream's third
/// sink: short, scannable one-liners for the help-band area ("Pile saved by
/// Rank Shield", "Tell became a curse"). The MAPPING and the per-deal
/// scrollback live here in GameCore so the tests exercise the real thing;
/// the UI only renders. No new emit points: everything derives from the
/// same recT entries telemetry and the debug log already consume.
public enum EventFeed {

    /// One feed line for a recT entry, or nil when the entry isn't
    /// feed-worthy (pure misses, bookkeeping-only fires). Priority order:
    /// the most player-meaningful key wins — an entry never yields two lines.
    public static func message(klass: String, id: String, label: String,
                               values: [String: Double]) -> String? {
        func n(_ key: String) -> Int { Int(values[key] ?? 0) }
        // Conversions outrank everything — the bet failed, the curse is news.
        if values["converted"] != nil { return "\(label) became a curse" }
        if values["saves"] != nil {
            return values["revived"] != nil ? "Pile revived by \(label)"
                                            : "Pile saved by \(label)"
        }
        if values["warded"] != nil { return "Conversion blocked by \(label)" }
        if let c = values["cleansed"] ?? values["peeled"], c > 0 {
            return "Curse\(c > 1 ? "s" : "") removed by \(label)"
        }
        // The Same-charge family names its charge, not a generic fire.
        if id == "rechargeSameShield" || id == "rechargeSame" {
            return "Same Shield charged by \(label)"
        }
        if id == "activateSamePower" || id == "activateSame" {
            return "Same-Power fired by \(label)"
        }
        if let b = values["buried"], b > 0 { return "Buried \(n("buried")) by \(label)" }
        if let c = values["coins"], c > 0 { return "+\(n("coins"))◉ from \(label)" }
        if values["coinsLost"] != nil { return "−\(n("coinsLost"))◉ from \(label)" }
        if values["peeks"] != nil { return "Peek from \(label)" }
        if values["tells"] != nil || values["hints"] != nil { return "Tell from \(label)" }
        if let a = values["applied"], a > 0 { return "Sticker added by \(label)" }
        if values["purged"] != nil { return "Card purged by \(label)" }
        if values["kills"] != nil || values["killed"] != nil || values["destroyed"] != nil {
            return "Pile destroyed by \(label)"
        }
        if values["revived"] != nil { return "Pile revived by \(label)" }
        if let s = values["shuffled"], s > 0 { return "Shuffled by \(label)" }
        if let m = values["moved"], m > 0 { return "Cards moved by \(label)" }
        if let s = values["size"], s > 0 { return "+\(n("size")) pile size from \(label)" }
        if values["cards"] != nil { return "Cards returned by \(label)" }
        if values["copies"] != nil { return "Card copied by \(label)" }
        if values["charge"] != nil { return "Same Shield charged by \(label)" }
        // A bare {fires:1} with none of the above is bookkeeping — but a
        // named fire is still worth one quiet line.
        if values["fires"] != nil { return "\(label) fired" }
        return nil
    }
}

/// The per-deal scrollback + the display queue's source. `enabled` is the
/// debug toggle — disabled, nothing records at all (the toggle test's pin).
public final class EventFeedLog {
    public static let shared = EventFeedLog()
    public init() {}

    /// The debug-menu switch (UI reads/writes the pref; this is the gate).
    public var enabled = false

    /// The current deal's lines, oldest first, capped.
    public private(set) var lines: [String] = []
    /// Lines not yet shown by the UI — drained per display beat, which is
    /// what coalesces one landing's burst into one card.
    private var pending: [String] = []
    private let cap = 60
    private let lock = NSLock()

    /// Map + record one recT entry. No-op while disabled.
    public func post(klass: String, id: String, label: String,
                     values: [String: Double]) {
        guard enabled,
              let line = EventFeed.message(klass: klass, id: id, label: label,
                                           values: values) else { return }
        lock.lock()
        lines.append(line)
        if lines.count > cap { lines.removeFirst(lines.count - cap) }
        pending.append(line)
        lock.unlock()
    }

    /// Everything posted since the last drain — the UI shows one batch per
    /// beat, so a single landing's burst reads as one card.
    public func drainPending() -> [String] {
        lock.lock(); defer { lock.unlock() }
        let out = pending
        pending.removeAll()
        return out
    }

    /// A new deal starts its scrollback fresh.
    public func reset() {
        lock.lock()
        lines.removeAll()
        pending.removeAll()
        lock.unlock()
    }
}
