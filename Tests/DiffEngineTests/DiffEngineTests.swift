import XCTest
import PatchModel
import BaseLoader
import ApplyEngine
@testable import DiffEngine

final class DiffEngineTests: XCTestCase {

    private func lines(_ s: String) -> [String] { s.map { String($0) } }

    // MARK: - Shape of the edit list

    func testIdenticalInputsAreOneEqualRun() {
        for algorithm in DiffEngine.Algorithm.allCases {
            let d = DiffEngine.lines(lines("abc"), lines("abc"), algorithm: algorithm)
            XCTAssertEqual(d.edits, [Edit(kind: .equal, a: 0..<3, b: 0..<3)], "\(algorithm)")
            XCTAssertTrue(d.isIdentical)
        }
    }

    func testEmptyInputs() {
        for algorithm in DiffEngine.Algorithm.allCases {
            XCTAssertEqual(DiffEngine.lines([String](), [], algorithm: algorithm).edits, [])
            XCTAssertEqual(DiffEngine.lines([], ["a"], algorithm: algorithm).edits, [Edit(kind: .insert, a: 0..<0, b: 0..<1)])
            XCTAssertEqual(DiffEngine.lines(["a"], [], algorithm: algorithm).edits, [Edit(kind: .delete, a: 0..<1, b: 0..<0)])
        }
    }

    func testInsertInTheMiddle() {
        let d = DiffEngine.lines(lines("ac"), lines("abc"), algorithm: .myers)
        XCTAssertEqual(d.edits, [
            Edit(kind: .equal, a: 0..<1, b: 0..<1),
            Edit(kind: .insert, a: 1..<1, b: 1..<2),
            Edit(kind: .equal, a: 1..<2, b: 2..<3),
        ])
    }

    func testMyersIsMinimalOnTheClassicExample() {
        // Myers 1986, figure 1: ABCABBA → CBABAC has a shortest edit script of length 5.
        let d = DiffEngine.lines(lines("ABCABBA"), lines("CBABAC"), algorithm: .myers)
        XCTAssertEqual(d.deletedCount + d.insertedCount, 5)
        XCTAssertEqual(d.apply(to: lines("ABCABBA"), inserting: lines("CBABAC")), lines("CBABAC"))
    }

    func testPatienceAnchorsOnUniqueLinesAcrossAMovedBlock() {
        let a = ["#include <x>", "", "int a() {", "  return 1;", "}", "", "int b() {", "  return 2;", "}"]
        let b = ["#include <x>", "", "int b() {", "  return 2;", "}", "", "int a() {", "  return 1;", "}"]
        let d = DiffEngine.lines(a, b, algorithm: .patience)
        XCTAssertEqual(d.apply(to: a, inserting: b), b)
        // Unique lines `int a() {` / `int b() {` / `return 1` / `return 2`
        // anchor one function in place; the other moves as one deleted
        // block and one inserted block, never interleaved line by line.
        XCTAssertEqual(d.edits.filter { $0.kind == .delete }.count, 1, "\(d.edits)")
        XCTAssertEqual(d.edits.filter { $0.kind == .insert }.count, 1, "\(d.edits)")
        XCTAssertEqual(d.deletedCount, 4)
        XCTAssertEqual(d.insertedCount, 4)
        let anchored = d.edits.first { $0.kind == .equal && a[$0.a].contains("int b() {") }
        XCTAssertEqual(anchored?.a.count, 2, "the anchored function body stays one equal run")
    }

    func testEveryEditListReplaysForPseudoRandomInputs() {
        // Deterministic LCG so a failure reproduces.
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(bound))
        }
        for trial in 0..<200 {
            let n = next(30), m = next(30)
            let alphabet = 1 + next(5)
            let a = (0..<n).map { _ in String(next(alphabet)) }
            let b = (0..<m).map { _ in String(next(alphabet)) }
            for algorithm in DiffEngine.Algorithm.allCases {
                let d = DiffEngine.lines(a, b, algorithm: algorithm)
                XCTAssertEqual(d.apply(to: a, inserting: b), b, "trial \(trial) \(algorithm): \(a) → \(b)")
                // Every run is inside bounds and runs are contiguous.
                var ai = 0, bi = 0
                for e in d.edits {
                    XCTAssertEqual(e.a.lowerBound, ai, "trial \(trial) \(algorithm)")
                    XCTAssertEqual(e.b.lowerBound, bi, "trial \(trial) \(algorithm)")
                    ai = e.a.upperBound; bi = e.b.upperBound
                }
                XCTAssertEqual(ai, n); XCTAssertEqual(bi, m)
            }
            // Myers is minimal: never more changes than patience.
            let myers = DiffEngine.lines(a, b, algorithm: .myers)
            let patience = DiffEngine.lines(a, b, algorithm: .patience)
            XCTAssertLessThanOrEqual(myers.deletedCount + myers.insertedCount,
                                     patience.deletedCount + patience.insertedCount, "trial \(trial)")
        }
    }

    func testSplitLinesIgnoresTheFinalNewline() {
        XCTAssertEqual(DiffEngine.splitLines(""), [])
        XCTAssertEqual(DiffEngine.splitLines("a"), ["a"])
        XCTAssertEqual(DiffEngine.splitLines("a\n"), ["a"])
        XCTAssertEqual(DiffEngine.splitLines("a\n\n"), ["a", ""])
        XCTAssertEqual(DiffEngine.splitLines("\n"), [""])
    }

    // MARK: - Tokens

    func testTokenizerRoundTripsAndSplitsWordsSpacesAndPunctuation() {
        let text = "let x_1 = foo(a, b) // hi\n"
        let tokens = Tokenizer.tokens(text)
        XCTAssertEqual(tokens.joined(), text)
        XCTAssertEqual(tokens.prefix(7).map { $0 }, ["let", " ", "x_1", " ", "=", " ", "foo"])
        XCTAssertTrue(tokens.contains("("))
        XCTAssertTrue(tokens.contains(","))
    }

    func testTokenDiffMarksOnlyTheChangedWord() {
        let d = DiffEngine.tokens("return a + b;", "return a - b;")
        let deleted = d.edits.filter { $0.kind == .delete }.flatMap { d.a[$0.a] }
        let inserted = d.edits.filter { $0.kind == .insert }.flatMap { d.b[$0.b] }
        XCTAssertEqual(deleted, ["+"])
        XCTAssertEqual(inserted, ["-"])
    }

    func testSimilarityIgnoresWhitespaceAndRangesZeroToOne() {
        XCTAssertEqual(DiffEngine.tokens("a b c", "a  b   c").similarity, 1, accuracy: 0.0001)
        XCTAssertEqual(DiffEngine.tokens("", "").similarity, 1)
        XCTAssertEqual(DiffEngine.tokens("abc", "xyz").similarity, 0)
        let half = DiffEngine.tokens("keep gone", "keep new").similarity
        XCTAssertEqual(half, 0.5, accuracy: 0.0001)
    }

    // MARK: - Unified rendering

    func testUnifiedHunksUseDiffUHeaderConventions() {
        let a = (1...10).map { "line \($0)" }
        var b = a
        b[4] = "LINE 5"
        let hunks = DiffEngine.lines(a, b, algorithm: .myers).unifiedHunks(a: a, b: b)
        XCTAssertEqual(hunks.count, 1)
        XCTAssertEqual(hunks[0].header, "@@ -2,7 +2,7 @@")
        XCTAssertEqual(hunks[0].lines, [" line 2", " line 3", " line 4", "-line 5", "+LINE 5", " line 6", " line 7", " line 8"])

        let insertAtTop = DiffEngine.lines([String](), ["x"], algorithm: .myers).unifiedHunks(a: [], b: ["x"])
        XCTAssertEqual(insertAtTop[0].header, "@@ -0,0 +1 @@")

        let deleteAll = DiffEngine.lines(["x"], [], algorithm: .myers).unifiedHunks(a: ["x"], b: [])
        XCTAssertEqual(deleteAll[0].header, "@@ -1 +0,0 @@")
    }

    func testFarApartChangesMakeSeparateHunks() {
        let a = (1...30).map { "l\($0)" }
        var b = a
        b[1] = "X"; b[28] = "Y"
        let hunks = DiffEngine.lines(a, b, algorithm: .myers).unifiedHunks(a: a, b: b)
        XCTAssertEqual(hunks.count, 2)
        XCTAssertEqual(hunks[0].header, "@@ -1,5 +1,5 @@")
        XCTAssertEqual(hunks[1].header, "@@ -26,5 +26,5 @@")
    }

    // MARK: - M1 gate: matches `git diff --no-index` on 20 fixture file pairs

    /// Base and post-patch text of the first 20 changed fixture files,
    /// diffed by us and by `git diff --no-index --minimal`. Myers is a
    /// minimal edit script, so the changed-line counts must agree
    /// exactly, and our unified hunks must apply back to the post text.
    /// Hunk *count* is not compared: equally minimal scripts can slide
    /// a change up or down a repeated line, and git picks its own.
    /// Texts are given a final newline on both sides, because git
    /// counts a changed end-of-file newline as a changed line while
    /// `LineDiff` keeps that as a property of the text.
    /// The one `Process` call outside `BaseLoader` lives in this test,
    /// as the oracle the gate names.
    func testLineDiffMatchesGitDiffForTwentySampledFilePairs() throws {
        guard Git.version() != nil else { throw XCTSkip("git is not installed; the gate needs it as the oracle") }
        let pairs = try Self.sampledPairs(count: 20)
        XCTAssertEqual(pairs.count, 20)

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("patchadam-diff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        for (label, rawBase, rawPost) in pairs {
            let baseText = rawBase.hasSuffix("\n") ? rawBase : rawBase + "\n"
            let postText = rawPost.hasSuffix("\n") ? rawPost : rawPost + "\n"
            let aURL = tmp.appendingPathComponent("a.txt"), bURL = tmp.appendingPathComponent("b.txt")
            try Data(baseText.utf8).write(to: aURL)
            try Data(postText.utf8).write(to: bURL)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["git", "diff", "--no-index", "--minimal", "--no-indent-heuristic", "-U3", "--no-color", aURL.path, bURL.path]
            let out = Pipe()
            process.standardOutput = out
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let gitOutput = String(decoding: data, as: UTF8.self)
            let gitDeleted = gitOutput.split(separator: "\n").filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count
            let gitInserted = gitOutput.split(separator: "\n").filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count
            XCTAssertFalse(gitOutput.isEmpty, "\(label): git produced no diff")

            let a = DiffEngine.splitLines(baseText), b = DiffEngine.splitLines(postText)
            let ours = DiffEngine.lines(a, b, algorithm: .myers)
            XCTAssertEqual(ours.deletedCount, gitDeleted, "\(label): deleted lines")
            XCTAssertEqual(ours.insertedCount, gitInserted, "\(label): inserted lines")
            XCTAssertEqual(ours.apply(to: a, inserting: b), b, "\(label): edit list does not replay")

            // Our unified rendering is a patch PatchModel parses and ApplyEngine applies back to b.
            let unified = "diff --git a/f b/f\n" + ours.unified(a: a, b: b, aName: "a/f", bName: "b/f")
            let patch = try UnifiedDiffParser.parse(unified)
            XCTAssertFalse(patch.files[0].hunks.isEmpty, "\(label): no hunks rendered")
            let applied = ApplyEngine.apply(patch, to: InMemoryBase(files: ["f": baseText]))
            XCTAssertEqual(applied.files[0].status, .clean, "\(label): our own diff must apply clean")
            XCTAssertEqual(applied.files[0].postText.map(DiffEngine.splitLines), b, "\(label): round trip through unified")
        }
    }

    /// `(label, base, post)` for the first `count` modified text files
    /// across the fixtures, in fixture order.
    static func sampledPairs(count: Int) throws -> [(String, String, String)] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let patches = root.appendingPathComponent("Fixtures/patches")
        let names = try FileManager.default.contentsOfDirectory(atPath: patches.path).filter { $0.hasSuffix(".patch") }.sorted()
        var out: [(String, String, String)] = []
        for name in names {
            let patch = try UnifiedDiffParser.parse(contentsOf: patches.appendingPathComponent(name))
            let base = DirectoryBase(root: root.appendingPathComponent("Fixtures/bases/\(name.dropLast(6))"))
            for file in ApplyEngine.apply(patch, to: base).files {
                guard let b = file.baseText, let p = file.postText, b != p else { continue }
                out.append(("\(name) \(file.path)", b, p))
                if out.count == count { return out }
            }
        }
        return out
    }
}

struct InMemoryBase: FileProvider {
    var files: [String: String]
    var origin: BaseOrigin { .directory(URL(fileURLWithPath: "/memory")) }
    func contents(of path: String) throws -> Data? { files[path].map { Data($0.utf8) } }
    func allPaths() throws -> [String] { files.keys.sorted() }
}
