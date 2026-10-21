import XCTest
@testable import PatchModel

/// Every fixture patch in Fixtures/patches parses, and the file count
/// matches what `grep -c '^diff --git'` reports. This is the first
/// Phase 1 gate (ROADMAP.md).
final class FixtureTests: XCTestCase {

    static let fixturesDir: URL = {
        // Tests/PatchModelTests/FixtureTests.swift → repo root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/patches")
    }()

    /// file name → `diff --git` header count, measured with grep.
    static let expectedFileCounts: [String: Int] = [
        "kettle-1.patch": 12,
        "kettle-2.patch": 11,
        "kettle-3.patch": 12,
        "kettle-4.patch": 13,
        "lantern-1.patch": 9,
        "lantern-2.patch": 7,
        "lantern-3.patch": 9,
        "scaffold.patch": 7,
        "rename.patch": 4,
        "mail.patch": 6,
    ]

    func testEveryFixtureParses() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.fixturesDir.path)
            .filter { $0.hasSuffix(".patch") }
            .sorted()
        XCTAssertEqual(names.count, Self.expectedFileCounts.count, "fixture table is out of date: \(names)")
        for name in names {
            let url = Self.fixturesDir.appendingPathComponent(name)
            let patch = try UnifiedDiffParser.parse(contentsOf: url)
            XCTAssertEqual(patch.files.count, Self.expectedFileCounts[name], name)
            for file in patch.files {
                XCTAssertFalse(file.path.isEmpty, "\(name): file with no path")
                for hunk in file.hunks {
                    XCTAssertEqual(hunk.lines.filter { $0.kind != .added }.count, hunk.oldCount, "\(name) \(file.path) old count")
                    XCTAssertEqual(hunk.lines.filter { $0.kind != .removed }.count, hunk.newCount, "\(name) \(file.path) new count")
                }
            }
        }
    }

    func testRenameWithSimilarityIndex() throws {
        let patch = try UnifiedDiffParser.parse(contentsOf: Self.fixturesDir.appendingPathComponent("rename.patch"))
        let rename = try XCTUnwrap(patch.files.first { $0.kind == .renamed })
        XCTAssertEqual(rename.oldPath, "tests/billing/test_ledger.py")
        XCTAssertEqual(rename.newPath, "tests/test_ledger.py")
        XCTAssertEqual(rename.similarity, 95)
        XCTAssertEqual(rename.fileName, "test_ledger.py")
        XCTAssertTrue(rename.isTest)
    }

    func testNewFileIsAdded() throws {
        let patch = try UnifiedDiffParser.parse(contentsOf: Self.fixturesDir.appendingPathComponent("scaffold.patch"))
        let agents = try XCTUnwrap(patch.files.first { $0.path == "AGENTS.md" })
        XCTAssertEqual(agents.kind, .added)
        XCTAssertNil(agents.oldPath)
        XCTAssertEqual(agents.newMode, "100644")
        XCTAssertTrue(agents.hunks.allSatisfy { $0.lines.allSatisfy { $0.kind == .added } })
    }

    func testLineNumbersRoundTrip() throws {
        // For every context line, old and new numbers advance together and
        // land exactly on the header's declared end.
        for name in Self.expectedFileCounts.keys.sorted() {
            let patch = try UnifiedDiffParser.parse(contentsOf: Self.fixturesDir.appendingPathComponent(name))
            for file in patch.files {
                for hunk in file.hunks {
                    let numbered = hunk.numberedLines
                    let lastOld = numbered.compactMap(\.oldNumber).last
                    let lastNew = numbered.compactMap(\.newNumber).last
                    if hunk.oldCount > 0 { XCTAssertEqual(lastOld, hunk.oldStart + hunk.oldCount - 1, "\(name) \(file.path)") }
                    if hunk.newCount > 0 { XCTAssertEqual(lastNew, hunk.newStart + hunk.newCount - 1, "\(name) \(file.path)") }
                }
            }
        }
    }
}
