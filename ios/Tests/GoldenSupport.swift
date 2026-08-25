import XCTest
@testable import GameCore

/// THE GOLDEN BASELINE (v6.79). `Fixtures/*.json` is the committed regression
/// record of what GameCore ITSELF produces — captured by `GoldenRecorder`
/// running the real engine, and replayed by the fixture suites on every run.
/// The web engine is out of the loop: `index.html` is a frozen reference and
/// nothing here is ever regenerated from it again.
///
/// Regenerating (ONLY after an intentional engine change, in the same commit
/// that makes it):
///
///     cd ios && make golden      # re-records Fixtures/*.json from GameCore
///     make test                  # must be green against the new baseline
///
/// `make golden` drops a `.golden-record` flag file next to the fixtures and
/// runs the `GoldenRecorder` test, which writes straight into the repo's
/// `Fixtures/` directory (the simulator shares the host filesystem). Without
/// the flag the recorder skips, so a normal test run can never overwrite the
/// baseline by accident.
enum Golden {
    /// The repo's `ios/Fixtures` directory, derived from this source file's
    /// compile-time path — the recorder writes here; the replay suites read
    /// the same content out of the test bundle.
    static var fixturesDir: URL {
        URL(fileURLWithPath: #filePath)          // …/ios/Tests/GoldenSupport.swift
            .deletingLastPathComponent()         // …/ios/Tests
            .deletingLastPathComponent()         // …/ios
            .appendingPathComponent("Fixtures")
    }

    /// The record-mode flag `make golden` creates and removes.
    static var recordFlag: URL { fixturesDir.appendingPathComponent(".golden-record") }
    static var isRecording: Bool { FileManager.default.fileExists(atPath: recordFlag.path) }

    /// Deterministic JSON write: sorted keys, compact — the same content
    /// always produces the same bytes, so a re-record with no behavior
    /// change is a no-op diff.
    static func write(_ root: [String: JSONValue], to name: String) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(JSONValue.object(root))
        try data.write(to: fixturesDir.appendingPathComponent(name), options: .atomic)
    }

    /// Read a fixture straight from the repo (record mode reads inputs from
    /// the committed baseline it is about to rewrite).
    static func readRepo(_ name: String) throws -> [String: JSONValue] {
        let data = try Data(contentsOf: fixturesDir.appendingPathComponent(name))
        return try JSONDecoder().decode([String: JSONValue].self, from: data)
    }
}

// MARK: - JSONValue construction sugar (recorder-side)

extension JSONValue {
    static func num(_ v: Int) -> JSONValue { .number(Double(v)) }
    static func num(_ v: Double) -> JSONValue { .number(v) }
    static func maybeString(_ s: String?) -> JSONValue { s.map { .string($0) } ?? .null }
    static func maybeNum(_ v: Int?) -> JSONValue { v.map { .number(Double($0)) } ?? .null }
    static func ints(_ a: [Int]) -> JSONValue { .array(a.map { .number(Double($0)) }) }
    static func strings(_ a: [String]) -> JSONValue { .array(a.map { .string($0) }) }
    static func maybeInts(_ a: [Int]?) -> JSONValue { a.map { ints($0) } ?? .null }
    static func maybeBools(_ a: [Bool]?) -> JSONValue { a.map { .array($0.map { .bool($0) }) } ?? .null }
}
