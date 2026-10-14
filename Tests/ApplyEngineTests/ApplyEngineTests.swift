import XCTest
import PatchModel
import BaseLoader
@testable import ApplyEngine

/// A base held in memory, for rule tests that need a few lines of
/// base text and nothing on disk.
struct InMemoryBase: FileProvider {
    var files: [String: String]
    var origin: BaseOrigin { .directory(URL(fileURLWithPath: "/memory")) }
    func contents(of path: String) throws -> Data? { files[path].map { Data($0.utf8) } }
    func allPaths() throws -> [String] { files.keys.sorted() }
}

final class ApplyEngineTests: XCTestCase {

    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let patchesDir = repoRoot.appendingPathComponent("Fixtures/patches")
    static let basesDir = repoRoot.appendingPathComponent("Fixtures/bases")

    static func fixtureNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: patchesDir.path).filter { $0.hasSuffix(".patch") }.sorted()
    }

    static func apply(fixture name: String) throws -> (Patch, AppliedPatch) {
        let patch = try UnifiedDiffParser.parse(contentsOf: patchesDir.appendingPathComponent(name))
        let base = DirectoryBase(root: basesDir.appendingPathComponent(String(name.dropLast(".patch".count))))
        return (patch, ApplyEngine.apply(patch, to: base))
    }

    private func parse(_ text: String) throws -> Patch { try UnifiedDiffParser.parse(text) }

    // MARK: - M1 gate: every fixture applies against its base

    func testEveryFixtureAppliesCleanAgainstItsSyntheticBase() throws {
        for name in try Self.fixtureNames() {
            let (patch, applied) = try Self.apply(fixture: name)
            XCTAssertEqual(applied.files.count, patch.files.count, name)
            for file in applied.files {
                XCTAssertEqual(file.status, file.change.isBinary ? .binary : .clean, "\(name) \(file.path): \(file.status.label)")
                if file.change.kind != .deleted, !file.change.isBinary {
                    XCTAssertNotNil(file.postText, "\(name) \(file.path): no post text")
                }
            }
            XCTAssertTrue(applied.report.isClean, "\(name): \(applied.report.summary)")
        }
    }

    /// Every hunk's post-side lines sit in the post text exactly where
    /// the placement says, and every file's hunk count matches.
    func testEveryFixtureHunkLandsWhereItsPlacementSays() throws {
        for name in try Self.fixtureNames() {
            let (_, applied) = try Self.apply(fixture: name)
            for file in applied.files where !file.change.isBinary {
                XCTAssertEqual(file.hunks.count, file.change.hunks.count, "\(name) \(file.path)")
                guard let post = file.postText else { continue }
                let lines = ApplyEngine.splitLines(post)
                for (hunk, placement) in zip(file.change.hunks, file.hunks) {
                    XCTAssertEqual(placement.offset, 0, "\(name) \(file.path) hunk \(placement.index + 1) moved")
                    XCTAssertEqual(placement.fuzz, 0, "\(name) \(file.path) hunk \(placement.index + 1) fuzzed")
                    let expected = hunk.lines.filter { $0.kind != .removed }.map(\.text)
                    guard !expected.isEmpty else { continue }
                    let start = placement.postStart - 1
                    XCTAssertEqual(Array(lines[start..<start + expected.count]), expected, "\(name) \(file.path) @ post L\(placement.postStart)")
                    XCTAssertEqual(placement.postStart, hunk.newStart, "\(name) \(file.path): a clean apply keeps the declared post start")
                }
            }
        }
    }

    // MARK: - M1 gate: line maps round-trip

    func testLineMapsRoundTripForEveryUnchangedLine() throws {
        var checked = 0
        for name in try Self.fixtureNames() {
            let (_, applied) = try Self.apply(fixture: name)
            for file in applied.files where file.postText != nil {
                let map = file.lineMap
                XCTAssertEqual(map.postLineCount, ApplyEngine.splitLines(file.postText!).count, "\(name) \(file.path)")
                XCTAssertEqual(map.baseLineCount, ApplyEngine.splitLines(file.baseText ?? "").count, "\(name) \(file.path)")
                for post in 1...max(map.postLineCount, 1) {
                    guard let base = map.base(forPost: post) else { continue }
                    XCTAssertEqual(map.post(forBase: base), post, "\(name) \(file.path) post L\(post) → base L\(base) → ?")
                    checked += 1
                }
                for base in 1...max(map.baseLineCount, 1) {
                    guard let post = map.post(forBase: base) else { continue }
                    XCTAssertEqual(map.base(forPost: post), base, "\(name) \(file.path) base L\(base) → post L\(post) → ?")
                }
                // Mapped lines carry identical text on both sides.
                let baseLines = ApplyEngine.splitLines(file.baseText ?? "")
                let postLines = ApplyEngine.splitLines(file.postText!)
                for (i, b) in map.postToBase.enumerated() {
                    if let b { XCTAssertEqual(postLines[i], baseLines[b - 1], "\(name) \(file.path) post L\(i + 1)") }
                }
            }
        }
        XCTAssertGreaterThan(checked, 10_000, "the fixture set should exercise thousands of unchanged lines")
    }

    func testLineMapCountsMatchHunkArithmetic() throws {
        for name in try Self.fixtureNames() {
            let (_, applied) = try Self.apply(fixture: name)
            for file in applied.files where file.postText != nil {
                let counts = file.change.lineCounts
                let added = file.lineMap.postToBase.filter { $0 == nil }.count
                let removed = file.lineMap.baseToPost.filter { $0 == nil }.count
                XCTAssertEqual(added, counts.added, "\(name) \(file.path) added")
                XCTAssertEqual(removed, counts.removed, "\(name) \(file.path) removed")
            }
        }
    }

    // MARK: - Placement rules

    static let threeLinePatch = """
    diff --git a/f.txt b/f.txt
    --- a/f.txt
    +++ b/f.txt
    @@ -2,3 +2,3 @@
     two
    -three
    +THREE
     four

    """

    func testHunkAppliesAtAnOffsetAndStaysClean() throws {
        let base = InMemoryBase(files: ["f.txt": "x\ny\nz\none\ntwo\nthree\nfour\nfive\n"])
        let file = ApplyEngine.apply(try parse(Self.threeLinePatch), to: base).files[0]
        XCTAssertEqual(file.status, .clean)
        XCTAssertEqual(file.postText, "x\ny\nz\none\ntwo\nTHREE\nfour\nfive\n")
        XCTAssertEqual(file.hunks[0].offset, 3)
        XCTAssertEqual(file.hunks[0].foundOldStart, 5)
        XCTAssertEqual(file.hunks[0].postStart, 5)
        XCTAssertNil(file.lineMap.base(forPost: 6), "THREE is an added line")
        XCTAssertNil(file.lineMap.post(forBase: 6), "three was removed")
        XCTAssertEqual(file.lineMap.base(forPost: 7), 7, "four is unchanged")
    }

    func testFuzzOneWhenOneContextLineDiffers() throws {
        let base = InMemoryBase(files: ["f.txt": "one\nTWO-changed\nthree\nfour\nfive\n"])
        let file = ApplyEngine.apply(try parse(Self.threeLinePatch), to: base).files[0]
        XCTAssertEqual(file.status, .fuzz(1))
        XCTAssertEqual(file.postText, "one\nTWO-changed\nTHREE\nfour\nfive\n", "fuzzed context keeps the base's line")
        XCTAssertEqual(file.hunks[0].fuzz, 1)
    }

    func testFuzzTwoWhenBothContextSidesDiffer() throws {
        let base = InMemoryBase(files: ["f.txt": "one\nTWO\nthree\nFOUR\nfive\n"])
        let file = ApplyEngine.apply(try parse(Self.threeLinePatch), to: base).files[0]
        XCTAssertEqual(file.status, .fuzz(1), "one line each side is fuzz 1")
        XCTAssertEqual(file.postText, "one\nTWO\nTHREE\nFOUR\nfive\n")
    }

    func testFailedFileKeepsRawHunksAndHasNoPostText() throws {
        let base = InMemoryBase(files: ["f.txt": "one\ntwo\nTHREE-already\nfour\nfive\n"])
        let file = ApplyEngine.apply(try parse(Self.threeLinePatch), to: base).files[0]
        guard case .failed(let reason) = file.status else { return XCTFail("expected failed, got \(file.status)") }
        XCTAssertTrue(reason.contains("hunk 1"), reason)
        XCTAssertNil(file.postText)
        XCTAssertEqual(file.baseText, "one\ntwo\nTHREE-already\nfour\nfive\n", "the base stays visible")
        XCTAssertEqual(file.change.hunks.count, 1, "raw hunks survive on the change")
        XCTAssertTrue(file.hunks.isEmpty)
    }

    func testRemovedLineMatchingButWrongContextWithZeroFuzzFails() throws {
        let base = InMemoryBase(files: ["f.txt": "A\nthree\nB\n"])
        let file = ApplyEngine.apply(try parse(Self.threeLinePatch), to: base, maxFuzz: 0).files[0]
        XCTAssertTrue(file.status.isFailure)
    }

    func testSecondHunkFailureReportsItsNumber() throws {
        let patch = try parse("""
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        @@ -1,1 +1,1 @@
        -one
        +ONE
        @@ -9,1 +9,1 @@
        -nine
        +NINE

        """)
        let base = InMemoryBase(files: ["f.txt": "one\ntwo\n"])
        let file = ApplyEngine.apply(patch, to: base).files[0]
        guard case .failed(let reason) = file.status else { return XCTFail() }
        XCTAssertTrue(reason.contains("hunk 2"), reason)
        XCTAssertEqual(file.hunks.count, 1, "the first hunk's placement is kept")
    }

    func testMissingBaseFileFails() throws {
        let file = ApplyEngine.apply(try parse(Self.threeLinePatch), to: InMemoryBase(files: [:])).files[0]
        guard case .failed(let reason) = file.status else { return XCTFail() }
        XCTAssertTrue(reason.contains("not in the base"), reason)
    }

    func testPureInsertionAfterLineN() throws {
        let patch = try parse("""
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        @@ -2,0 +3,2 @@
        +ins1
        +ins2

        """)
        let base = InMemoryBase(files: ["f.txt": "one\ntwo\nthree\n"])
        let file = ApplyEngine.apply(patch, to: base).files[0]
        XCTAssertEqual(file.status, .clean)
        XCTAssertEqual(file.postText, "one\ntwo\nins1\nins2\nthree\n")
        XCTAssertEqual(file.lineMap.postToBase, [1, 2, nil, nil, 3])
        XCTAssertEqual(file.lineMap.baseToPost, [1, 2, 5])
    }

    func testAddedFile() throws {
        let patch = try parse("""
        diff --git a/new.txt b/new.txt
        new file mode 100644
        --- /dev/null
        +++ b/new.txt
        @@ -0,0 +1,2 @@
        +a
        +b

        """)
        let file = ApplyEngine.apply(patch, to: InMemoryBase(files: [:])).files[0]
        XCTAssertEqual(file.status, .clean)
        XCTAssertNil(file.baseText)
        XCTAssertEqual(file.postText, "a\nb\n")
        XCTAssertEqual(file.lineMap.postToBase, [nil, nil])
        XCTAssertEqual(file.lineMap.baseLineCount, 0)
    }

    func testAddedFileThatAlreadyExistsFails() throws {
        let patch = try parse("""
        diff --git a/new.txt b/new.txt
        new file mode 100644
        --- /dev/null
        +++ b/new.txt
        @@ -0,0 +1,1 @@
        +a

        """)
        let file = ApplyEngine.apply(patch, to: InMemoryBase(files: ["new.txt": "x\n"])).files[0]
        XCTAssertTrue(file.status.isFailure)
    }

    func testDeletedFile() throws {
        let patch = try parse("""
        diff --git a/gone.txt b/gone.txt
        deleted file mode 100644
        --- a/gone.txt
        +++ /dev/null
        @@ -1,2 +0,0 @@
        -a
        -b

        """)
        let file = ApplyEngine.apply(patch, to: InMemoryBase(files: ["gone.txt": "a\nb\n"])).files[0]
        XCTAssertEqual(file.status, .clean)
        XCTAssertEqual(file.baseText, "a\nb\n")
        XCTAssertNil(file.postText)
        XCTAssertEqual(file.lineMap.baseToPost, [nil, nil])
    }

    func testRenamedFileReadsOldPathAndReportsNewPath() throws {
        let patch = try parse("""
        diff --git a/old.py b/new.py
        similarity index 80%
        rename from old.py
        rename to new.py
        --- a/old.py
        +++ b/new.py
        @@ -1,1 +1,1 @@
        -x = 1
        +x = 2

        """)
        let file = ApplyEngine.apply(patch, to: InMemoryBase(files: ["old.py": "x = 1\n"])).files[0]
        XCTAssertEqual(file.status, .clean)
        XCTAssertEqual(file.path, "new.py")
        XCTAssertEqual(file.postText, "x = 2\n")
    }

    func testModeOnlyChangeKeepsTextClean() throws {
        let patch = try parse("""
        diff --git a/run.sh b/run.sh
        old mode 100644
        new mode 100755

        """)
        let file = ApplyEngine.apply(patch, to: InMemoryBase(files: ["run.sh": "echo\n"])).files[0]
        XCTAssertEqual(file.status, .clean)
        XCTAssertEqual(file.postText, "echo\n")
        XCTAssertEqual(file.lineMap.postToBase, [1])
    }

    func testBinaryFileIsReportedNotApplied() throws {
        let patch = try parse("""
        diff --git a/img.png b/img.png
        Binary files a/img.png and b/img.png differ

        """)
        let applied = ApplyEngine.apply(patch, to: InMemoryBase(files: ["img.png": "bytes"]))
        XCTAssertEqual(applied.files[0].status, .binary)
        XCTAssertEqual(applied.report.binary, 1)
        XCTAssertTrue(applied.report.isClean)
    }

    func testNoNewlineAtEndIsAddedAndRemovedCorrectly() throws {
        let addsNewline = try parse("""
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        @@ -1,1 +1,1 @@
        -end
        \\ No newline at end of file
        +end

        """)
        let file1 = ApplyEngine.apply(addsNewline, to: InMemoryBase(files: ["f.txt": "end"])).files[0]
        XCTAssertEqual(file1.postText, "end\n")

        let dropsNewline = try parse("""
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        @@ -1,1 +1,1 @@
        -end
        +end
        \\ No newline at end of file

        """)
        let file2 = ApplyEngine.apply(dropsNewline, to: InMemoryBase(files: ["f.txt": "end\n"])).files[0]
        XCTAssertEqual(file2.postText, "end")
    }

    func testReportCountsEveryStatus() throws {
        let patch = try parse("""
        diff --git a/a.txt b/a.txt
        --- a/a.txt
        +++ b/a.txt
        @@ -1,1 +1,1 @@
        -a
        +A
        diff --git a/b.txt b/b.txt
        --- a/b.txt
        +++ b/b.txt
        @@ -1,1 +1,1 @@
        -b
        +B
        diff --git a/c.png b/c.png
        Binary files a/c.png and b/c.png differ

        """)
        let applied = ApplyEngine.apply(patch, to: InMemoryBase(files: ["a.txt": "a\n", "b.txt": "nope\n", "c.png": ""]))
        let report = applied.report
        XCTAssertEqual(report.clean, 1)
        XCTAssertEqual(report.failed, 1)
        XCTAssertEqual(report.binary, 1)
        XCTAssertEqual(report.total, 3)
        XCTAssertEqual(report.summary, "1 clean, 1 failed, 1 binary")
    }

    func testNearestBaseForAddedLineIsPrecedingContext() throws {
        let patch = try parse("""
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        @@ -1,2 +1,4 @@
         one
        +new-a
        +new-b
         two

        """)
        let file = ApplyEngine.apply(patch, to: InMemoryBase(files: ["f.txt": "one\ntwo\n"])).files[0]
        XCTAssertNil(file.lineMap.base(forPost: 2))
        XCTAssertEqual(file.lineMap.nearestBase(forPost: 2), 1)
        XCTAssertEqual(file.lineMap.nearestBase(forPost: 3), 1)
        XCTAssertEqual(file.lineMap.nearestBase(forPost: 4), 2)
    }
}
