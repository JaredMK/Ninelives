import Foundation

/// A loss-free mirror of any JSON value.
///
/// The web build reads item tunables generically — `itemNum(def, key, fallback)`
/// pulls ANY numeric field off an item definition, and items.js is explicitly a
/// hand-editable file where "any other numeric field is an effect knob". So the
/// Swift item structs keep the whole decoded entry alongside the typed fields;
/// `ItemDef.num(_:_:)` reads knobs out of it exactly like `itemNum` does.
public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        // Bool BEFORE number: JSONDecoder happily reads `true` as 1.0 otherwise.
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON value")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v):   try c.encode(v)
        case .array(let v):  try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null:          try c.encodeNil()
        }
    }

    // MARK: - JS-shaped accessors

    /// `typeof v === "number" && isFinite(v)` — a bool is NOT a number in JS.
    public var asNumber: Double? {
        if case .number(let d) = self, d.isFinite { return d }
        return nil
    }
    public var asString: String? { if case .string(let s) = self { return s }; return nil }
    public var asBool: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var asArray: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    public var asObject: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    public var isNull: Bool { if case .null = self { return true }; return false }

    /// Key lookup on an object value (nil for any non-object).
    public subscript(_ key: String) -> JSONValue? { asObject?[key] }
    /// Index lookup on an array value (nil for any non-array / out of range).
    public subscript(_ i: Int) -> JSONValue? {
        guard let a = asArray, i >= 0, i < a.count else { return nil }
        return a[i]
    }
    /// `Int(v)` when the value is a finite number.
    public var asInt: Int? { asNumber.map { Int($0) } }

    /// Mirrors `JSON.stringify(x)` closely enough for validation messages
    /// (the web validators interpolate the offending value with it).
    public var jsDescription: String {
        switch self {
        case .string(let s): return "\"\(s)\""
        case .number(let d): return d == d.rounded() && abs(d) < 1e15
            ? String(Int64(d)) : String(d)
        case .bool(let b):   return b ? "true" : "false"
        case .array(let a):  return "[" + a.map(\.jsDescription).joined(separator: ",") + "]"
        case .object(let o): return "{" + o.keys.sorted().map { "\"\($0)\":\(o[$0]!.jsDescription)" }.joined(separator: ",") + "}"
        case .null:          return "null"
        }
    }
}
