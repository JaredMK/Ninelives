import Foundation

/// Seeded RNG — the Swift twin of the web build's `makeRng` (mulberry32).
///
/// A run is fully determined by its seed, so this must be BYTE-IDENTICAL to the
/// JS original or every map, shuffle and store roll diverges. The JS is:
///
/// ```js
/// let a = seed >>> 0;
/// return function () {
///   a |= 0; a = (a + 0x6D2B79F5) | 0;
///   let t = Math.imul(a ^ (a >>> 15), 1 | a);
///   t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
///   return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
/// };
/// ```
///
/// Every operation there is 32-bit: `|0` and `Math.imul` keep the low 32 bits,
/// `>>>` is an unsigned shift, and the `+` inside the second line is a float sum
/// that `^` immediately truncates back to 32 bits (ToInt32 = mod 2³²). Wrapping
/// `UInt32` arithmetic reproduces all of it exactly, and the final divide by
/// 2³² is the same IEEE-754 double on both sides.
public final class RNG {
    private var a: UInt32

    /// The generator's ENTIRE state — one word. Read to snapshot a mid-deal
    /// save, write to resume the stream at the exact position it stopped.
    public var state: UInt32 {
        get { a }
        set { a = newValue }
    }

    public init(seed: UInt32) { self.a = seed }
    /// Convenience for the many call sites that hold a seed as `Int`/`Double`.
    public convenience init(seed: Int) { self.init(seed: UInt32(truncatingIfNeeded: seed)) }

    /// One draw in [0, 1).
    public func next() -> Double {
        a = a &+ 0x6D2B79F5
        var t = (a ^ (a >> 15)) &* (1 | a)
        t = ((t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t)
        return Double(t ^ (t >> 14)) / 4294967296.0
    }

    /// `Math.floor(rng() * n)` — the shape every JS index pick uses.
    public func index(_ n: Int) -> Int {
        n <= 0 ? 0 : Int(next() * Double(n))
    }

    /// `generateSeed()` — a fresh random u32.
    public static func generateSeed() -> UInt32 {
        UInt32.random(in: UInt32.min...UInt32.max)
    }
}

// MARK: - The seed-derivation helpers the generator uses

/// `Math.imul(a, b)` — the low 32 bits of a 32-bit multiply.
@inlinable
public func jsImul(_ a: UInt32, _ b: UInt32) -> UInt32 { a &* b }

/// The stage rng seed: `(seed >>> 0) ^ ((phaseIndex + 1) * 0x9e3779b1) ^ Math.imul(attempt + 1, 0x85ebca6b)`.
///
/// NOTE the asymmetry, faithfully preserved: the phase term uses a plain JS `*`
/// (a float64 product, then ToInt32 by `^`), the attempt term uses `Math.imul`.
/// Both truncate to the same low 32 bits here because `^` applies ToInt32 to the
/// float product — and (phaseIndex + 1) * 0x9e3779b1 stays under 2⁵³ for every
/// reachable phase index, so no precision is lost before the truncation.
@inlinable
public func stageSeed(seed: UInt32, phaseIndex: Int, attempt: Int) -> UInt32 {
    let phaseTerm = UInt32(truncatingIfNeeded: Int64(phaseIndex + 1) &* 0x9e3779b1)
    let attemptTerm = jsImul(UInt32(truncatingIfNeeded: attempt + 1), 0x85ebca6b)
    return seed ^ phaseTerm ^ attemptTerm
}

/// The seed-ladder derived seed: `((seed >>> 0) ^ Math.imul(rung, 0x9e3779b1)) >>> 0`.
@inlinable
public func ladderSeed(seed: UInt32, rung: Int) -> UInt32 {
    seed ^ jsImul(UInt32(truncatingIfNeeded: rung), 0x9e3779b1)
}

/// The legacy (genV < 3) cosmetic mystery-mask seed:
/// `(seed >>> 0) ^ Math.imul(n.id + 1, 0x9e3779b1) ^ 0x6d797374`.
@inlinable
public func mysteryMaskSeed(seed: UInt32, nodeId: Int) -> UInt32 {
    seed ^ jsImul(UInt32(truncatingIfNeeded: nodeId + 1), 0x9e3779b1) ^ 0x6d797374
}
