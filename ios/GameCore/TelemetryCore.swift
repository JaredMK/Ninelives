import Foundation

/// REMOTE TELEMETRY (v6.92) — the transport-agnostic core.
///
/// ONE instrumentation source, two sinks: the engine's recT/debug stream
/// keeps its local log exactly as before; this queue is the REMOTE sink.
/// The core owns the vocabulary (TELEMETRY.md is the contract), the shared
/// context envelope, batching, and the opt-out. The TRANSPORT (TelemetryDeck,
/// injected by the app target) never sees a signal while sharing is off,
/// and the whole layer compiles to a nil-transport no-op outside the
/// TELEMETRY build flag — the flag gates the app-side bridge, and with no
/// transport injected `flush()` drops the batch on the floor.
///
/// THREADING + COST: `record` is an O(1) guarded append (the sharing check
/// short-circuits first — OFF costs one closure call). Flushes hand the
/// drained batch to the transport and never wait on it; failures are the
/// transport's to swallow (TelemetryDeck's SDK retries internally and drops
/// silently) — the core never retries, never blocks, never throws.
public final class TelemetryCore {
    public static let shared = TelemetryCore()

    /// One outgoing signal: a name + string parameters (envelope merged in).
    public struct Signal: Equatable, Sendable {
        public let name: String
        public let params: [String: String]
        public init(name: String, params: [String: String]) {
            self.name = name
            self.params = params
        }
    }

    /// The run/mode envelope stamped onto EVERY signal. The anonymous user
    /// id and app version ride the transport's own default payload
    /// (TelemetryDeck stamps both on every signal).
    public struct Context: Sendable {
        /// A fresh UUID per climb; nil outside a run (menu, Zen-less).
        public var runId: String?
        /// "climb" | "zen" | "endless"
        public var mode: String?
        public var deck: String?
        public var tier: String?
        public var seed: String?
        public init() {}
    }

    /// Injected by the app target; receives each drained batch.
    public var transport: (([Signal]) -> Void)?
    /// The sharing switch, read live on EVERY record — false drops at the
    /// door (nothing queues, nothing leaks out later when toggled back on).
    public var sharingEnabled: () -> Bool = { false }
    /// A full queue forces a flush.
    public var flushThreshold = 20

    public var context = Context()
    private var queue: [Signal] = []
    private let lock = NSLock()

    /// The conditional-sticker vocabulary (the v6.85–v6.90 template) —
    /// `conditional_outcome` derives from the recT stream against this set.
    public static let conditionalStickers: Set<String> = [
        "tieSafe", "suitImmunity", "gainCoin", "heavy", "donate", "quickBury",
        "diamondSnob", "tell", "pillarScout", "baseScout",
        "rechargeSameShield", "activateSamePower",
    ]

    // MARK: - Recording

    public func record(_ name: String, _ params: [String: String] = [:]) {
        guard sharingEnabled() else { return }
        var p = params
        p["run_id"] = context.runId ?? "none"
        if let m = context.mode { p["game_mode"] = m }
        if let d = context.deck { p["deck"] = d }
        if let t = context.tier { p["tier"] = t }
        if let s = context.seed { p["seed"] = s }
        lock.lock()
        queue.append(Signal(name: name, params: p))
        let count = queue.count
        lock.unlock()
        if count >= flushThreshold { flush() }
    }

    /// The recT FORWARD — the engine's one instrumentation stream feeding
    /// the remote sink. Every entry becomes `item_fired`; entries for a
    /// conditional sticker additionally derive `conditional_outcome`
    /// (converted when the recT dict says so, fired otherwise).
    public func recordItemFire(klass: String, id: String, label: String,
                               values: [String: Double]) {
        guard sharingEnabled() else { return }
        var p: [String: String] = ["item_class": klass, "item_id": id]
        for (k, v) in values { p["fx_\(k)"] = trim(v) }
        record("item_fired", p)
        if klass == "base" {
            record("base_fired", ["base_id": id])
        }
        if klass == "sticker", Self.conditionalStickers.contains(id) {
            record("conditional_outcome", [
                "sticker_id": id,
                "outcome": values["converted"] != nil ? "converted" : "fired",
            ])
        }
    }

    private func trim(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }

    /// base_expired_uncharged — a deal ended with a CHARGED base never
    /// fired (the "they don't know bases exist" signal). Fed the run's
    /// bases/basesUsed pair at deal end.
    public func recordUnfiredBases(bases: [String?]?, used: [Bool]?) {
        guard let bases, let used else { return }
        for (col, id) in bases.enumerated()
        where id != nil && col < used.count && !used[col] {
            record("base_expired_uncharged",
                   ["base_id": id ?? "", "column": String(col)])
        }
    }

    // MARK: - Flushing

    /// Drain the queue into the transport (no transport = drop, by design:
    /// the build flag off means the bridge never injected one).
    public func flush() {
        lock.lock()
        let batch = queue
        queue.removeAll()
        lock.unlock()
        guard !batch.isEmpty, let transport else { return }
        transport(batch)
    }

    // MARK: - Context lifecycle

    /// A climb begins: fresh run id + the run envelope.
    public func beginRun(mode: String, deck: String, tier: String, seed: UInt32) -> String {
        let id = UUID().uuidString
        context.runId = id
        context.mode = mode
        context.deck = deck
        context.tier = tier
        context.seed = String(seed)
        return id
    }

    /// The climb ended (any way) — the envelope empties back to menu state.
    public func endRun() {
        context.runId = nil
        context.mode = nil
        context.seed = nil
    }

    // MARK: - Test access

    public var pendingCount: Int {
        lock.lock(); defer { lock.unlock() }
        return queue.count
    }
}
