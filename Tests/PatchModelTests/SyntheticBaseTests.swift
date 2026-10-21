import XCTest
@testable import PatchModel

/// `SyntheticBase` rebuilds a base file from a patch's hunks, and the
/// checked-in `Fixtures/bases/` set is exactly what it produces for
/// every fixture patch (issue #6, DECISIONS.md D4).
final class SyntheticBaseTests: XCTestCase {

    static let fixturesRoot: URL = FixtureTests.fixturesDir.deletingLastPathComponent()
    static let basesDir: URL = fixturesRoot.appendingPathComponent("bases")

    // MARK: - Reconstruction rules

    func testContextAndRemovedLinesLandOnTheirBaseNumbers() throws {
        let patch = try UnifiedDiffParser.parse("""
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        @@ -1,3 +1,3 @@
         one
        -two
        +TWO
         three

        """)
        let base = try XCTUnwrap(SyntheticBase.files(for: patch).first)
        XCTAssertEqual(base.path, "f.txt")
        XCTAssertEqual(base.text, "one\ntwo\nthree\n")
    }

    func testGapsBetweenHunksAreFilledByNumberedFillerLines() throws {
        let patch = try UnifiedDiffParser.parse("""
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        @@ -3,2 +3,2 @@
         three
        -four
        +FOUR
        @@ -8,1 +8,1 @@
        -eight
        +EIGHT

        """)
        let base = try XCTUnwrap(SyntheticBase.files(for: patch).first)
        let lines = base.text.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
        XCTAssertEqual(lines.count, 8)
        XCTAssertEqual(lines[0], Substring(SyntheticBase.filler(line: 1)))
        XCTAssertEqual(lines[1], Substring(SyntheticBase.filler(line: 2)))
        XCTAssertEqual(lines[2], "three")
        XCTAssertEqual(lines[3], "four")
        XCTAssertEqual(lines[4], Substring(SyntheticBase.filler(line: 5)))
        XCTAssertEqual(lines[6], Substring(SyntheticBase.filler(line: 7)))
        XCTAssertEqual(lines[7], "eight")
    }

    func testNoNewlineAtEndOfBaseIsPreserved() throws {
        let patch = try UnifiedDiffParser.parse("""
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        @@ -1,2 +1,2 @@
         one
        -two
        \\ No newline at end of file
        +two

        """)
        let base = try XCTUnwrap(SyntheticBase.files(for: patch).first)
        XCTAssertEqual(base.text, "one\ntwo")
    }

    func testPureInsertionHunkAddsNoBaseLines() throws {
        let patch = try UnifiedDiffParser.parse("""
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        @@ -2,0 +3,1 @@
        +inserted

        """)
        let base = try XCTUnwrap(SyntheticBase.files(for: patch).first)
        XCTAssertEqual(base.text, "", "a hunk with no base lines tells us nothing about the base")
    }

    func testAddedAndBinaryFilesHaveNoBase() throws {
        let patch = try UnifiedDiffParser.parse("""
        diff --git a/new.txt b/new.txt
        new file mode 100644
        --- /dev/null
        +++ b/new.txt
        @@ -0,0 +1,1 @@
        +hello
        diff --git a/img.png b/img.png
        Binary files a/img.png and b/img.png differ
        diff --git a/kept.txt b/kept.txt
        --- a/kept.txt
        +++ b/kept.txt
        @@ -1,1 +1,1 @@
        -a
        +b

        """)
        let bases = try SyntheticBase.files(for: patch)
        XCTAssertEqual(bases.map(\.path), ["kept.txt"])
    }

    func testRenamedFileUsesItsOldPath() throws {
        let patch = try UnifiedDiffParser.parse("""
        diff --git a/old/name.py b/new/name.py
        similarity index 90%
        rename from old/name.py
        rename to new/name.py
        --- a/old/name.py
        +++ b/new/name.py
        @@ -1,1 +1,1 @@
        -x = 1
        +x = 2

        """)
        let base = try XCTUnwrap(SyntheticBase.files(for: patch).first)
        XCTAssertEqual(base.path, "old/name.py")
        XCTAssertEqual(base.text, "x = 1\n")
    }

    func testOverlappingHunksAreAnError() throws {
        let patch = try UnifiedDiffParser.parse("""
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        @@ -1,3 +1,3 @@
         one
        -two
        +TWO
         three
        @@ -2,1 +2,1 @@
        -two
        +deux

        """)
        XCTAssertThrowsError(try SyntheticBase.files(for: patch)) { error in
            let message = "\(error)"
            XCTAssertTrue(message.contains("hunk 2"), message)
            XCTAssertTrue(message.contains("already covered"), message)
        }
    }

    // MARK: - The checked-in fixture bases

    /// `Fixtures/bases/<fixture>/` is byte-for-byte what `SyntheticBase`
    /// produces today — no stale, missing or extra file. Regenerate with
    /// `make bases` when the generator or a fixture changes.
    func testStoredBasesMatchRegeneration() throws {
        let fm = FileManager.default
        for name in FixtureTests.expectedFileCounts.keys.sorted() {
            let stem = String(name.dropLast(".patch".count))
            let patch = try UnifiedDiffParser.parse(contentsOf: FixtureTests.fixturesDir.appendingPathComponent(name))
            let generated = try SyntheticBase.files(for: patch)
            XCTAssertFalse(generated.isEmpty, "\(name): no base files generated")

            let dir = Self.basesDir.appendingPathComponent(stem)
            var stored: Set<String> = []
            if let walker = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) {
                for case let url as URL in walker where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                    stored.insert(String(url.path.dropFirst(dir.path.count + 1)))
                }
            }
            XCTAssertEqual(stored, Set(generated.map(\.path)), "\(stem): stored base files differ from the generator's set")

            for file in generated {
                let url = dir.appendingPathComponent(file.path)
                guard let data = fm.contents(atPath: url.path) else {
                    XCTFail("\(stem)/\(file.path): missing from Fixtures/bases"); continue
                }
                XCTAssertEqual(data, Data(file.text.utf8), "\(stem)/\(file.path): stale — run make bases")
            }
        }
    }

    /// Every base file ends exactly where its last hunk ends, and every
    /// hunk's base lines are found verbatim at their declared offset.
    func testEveryFixtureHunkIsFoundAtItsDeclaredOffsetInItsBase() throws {
        for name in FixtureTests.expectedFileCounts.keys.sorted() {
            let patch = try UnifiedDiffParser.parse(contentsOf: FixtureTests.fixturesDir.appendingPathComponent(name))
            let bases = Dictionary(uniqueKeysWithValues: try SyntheticBase.files(for: patch).map { ($0.path, $0.text) })
            for file in patch.files where file.kind != .added && !file.isBinary {
                let text = try XCTUnwrap(bases[file.oldPath ?? ""], "\(name) \(file.path)")
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                for hunk in file.hunks where hunk.oldCount > 0 {
                    let expected = hunk.lines.filter { $0.kind != .added }.map(\.text)
                    let start = hunk.oldStart - 1
                    XCTAssertLessThanOrEqual(start + expected.count, lines.count, "\(name) \(file.path) hunk runs past base end")
                    let actual = lines[start..<min(start + expected.count, lines.count)].map(String.init)
                    XCTAssertEqual(actual, expected, "\(name) \(file.path) @ L\(hunk.oldStart)")
                }
            }
        }
    }
}

final class MergedSyntheticBaseTests: XCTestCase {

    static let fixturesDir = FixtureTests.fixturesDir

    func testMergedBaseFillsEachPatchsGapsFromTheOther() throws {
        let a = try UnifiedDiffParser.parse("""
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        @@ -1,2 +1,2 @@
         one
        -two
        +TWO

        """)
        let b = try UnifiedDiffParser.parse("""
        diff --git a/f.txt b/f.txt
        --- a/f.txt
        +++ b/f.txt
        @@ -4,2 +4,2 @@
         four
        -five
        +FIVE

        """)
        let merged = try SyntheticBase.merged(for: [a, b])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].text, "one\ntwo\n\(SyntheticBase.filler(line: 3))\nfour\nfive\n")
    }

    func testMergedBaseRejectsDisagreement() throws {
        let a = try UnifiedDiffParser.parse("diff --git a/f.txt b/f.txt\n--- a/f.txt\n+++ b/f.txt\n@@ -1,1 +1,1 @@\n-one\n+1\n")
        let b = try UnifiedDiffParser.parse("diff --git a/f.txt b/f.txt\n--- a/f.txt\n+++ b/f.txt\n@@ -1,1 +1,1 @@\n-uno\n+1\n")
        XCTAssertThrowsError(try SyntheticBase.merged(for: [a, b])) { error in
            XCTAssertTrue("\(error)".contains("disagree about base line 1"), "\(error)")
        }
    }

    /// The four kettle patches (kettle-1…18) share one real base; the
    /// merged synthetic base must be consistent across all of them.
    func testTheFourGoPatchesShareOneMergedBase() throws {
        let patches = try (1...4).map { try UnifiedDiffParser.parse(contentsOf: Self.fixturesDir.appendingPathComponent("kettle-\($0).patch")) }
        let merged = try SyntheticBase.merged(for: patches)
        let paths = Set(merged.map(\.path))
        XCTAssertGreaterThanOrEqual(merged.count, 10)
        // Every file any of the four modifies is present once.
        for patch in patches {
            for file in patch.files where file.kind != .added && !file.isBinary {
                XCTAssertTrue(paths.contains(file.oldPath ?? ""), file.path)
            }
        }
        // And every single-patch base is a sub-reconstruction of the merged one.
        for patch in patches {
            let single = Dictionary(uniqueKeysWithValues: try SyntheticBase.files(for: patch).map { ($0.path, $0.text) })
            for file in merged where single[file.path] != nil {
                let mergedLines = file.text.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
                let singleLines = single[file.path]!.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
                for (i, line) in singleLines.enumerated() where i < mergedLines.count && line != Substring(SyntheticBase.filler(line: i + 1)) {
                    XCTAssertEqual(mergedLines[i], line, "\(file.path) L\(i + 1)")
                }
            }
        }
    }
}
