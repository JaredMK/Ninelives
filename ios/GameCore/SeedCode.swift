import Foundation

/// SeedCode (SEED1) — the shareable 7-char form of a 32-bit run seed.
///
/// Crockford-ish unambiguous alphabet (no 0/O/1/I/L — 31 symbols; 31⁷ > 2³²), so
/// every u32 encodes bijectively and `decode` rejects codes that would overflow
/// 32 bits. Pure. The deck / tier context travels in the SHARE string
/// ("PINKY-REGULAR-XK4T9QD"), never in the code itself.
public enum SeedCode {
    public static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    public static let base = 31
    public static let length = 7

    /// u32 → 7-char code (fixed width, most-significant char first).
    public static func encode(_ u32: UInt32) -> String {
        var v = UInt64(u32)
        var out = ""
        for _ in 0..<length {
            out = String(alphabet[Int(v % UInt64(base))]) + out
            v /= UInt64(base)
        }
        return out
    }

    /// 7-char code → u32, or nil (trim/case tolerant; rejects bad chars, wrong
    /// length, and values past 0xFFFFFFFF — the 7-char space is wider than u32).
    public static func decode(_ str: String?) -> UInt32? {
        guard let str else { return nil }
        let s = str.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard s.count == length else { return nil }
        var v: UInt64 = 0
        for ch in s {
            guard let idx = alphabet.firstIndex(of: ch) else { return nil }
            v = v * UInt64(base) + UInt64(idx)
        }
        guard v <= 0xFFFF_FFFF else { return nil }
        return UInt32(v)
    }
}
