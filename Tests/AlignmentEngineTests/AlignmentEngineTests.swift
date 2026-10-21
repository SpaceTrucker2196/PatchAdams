import XCTest
import PatchModel
import BaseLoader
import ApplyEngine
import DiffEngine
@testable import AlignmentEngine

final class AlignmentEngineTests: XCTestCase {

    // MARK: - Helpers

    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Apply `patchText` to `base`; display lines of the first file.
    private func lines(_ patchText: String, base: String, path: String = "f.txt") throws -> (AppliedFile, [DisplayLine]) {
        let patch = try UnifiedDiffParser.parse(patchText)
        let file = ApplyEngine.apply(patch, to: InMemoryBase(texts: [path: base])).files[0]
        return (file, file.displayLines())
    }

    private func patch(_ hunks: String, path: String = "f.txt") -> String {
        "diff --git a/\(path) b/\(path)\n--- a/\(path)\n+++ b/\(path)\n" + hunks
    }

    static let base = (1...30).map { "line \($0);" }.joined(separator: "\n") + "\n"

    // MARK: - Statuses

    func testSameChangeInBothColumnsIsExact() throws {
        let hunk = "@@ -10,3 +10,3 @@\n line 10;\n-line 11;\n+LINE 11;\n line 12;\n"
        let (_, x) = try lines(patch(hunk), base: Self.base)
        let (yFile, y) = try lines(patch(hunk), base: Self.base)
        let region = x.firstIndex { $0.text == "LINE 11;" }!
        let anchor = AlignmentEngine.locate(region..<region + 1, in: x, target: y, targetHunks: yFile.hunks)
        XCTAssertEqual(anchor.status, .exact)
        XCTAssertEqual(anchor.confidence, 1)
        XCTAssertEqual(y[anchor.lines].map(\.text), ["LINE 11;"])
    }

    func testDifferentTextAtTheSamePlaceIsModified() throws {
        let (_, x) = try lines(patch("@@ -10,3 +10,3 @@\n line 10;\n-line 11;\n+line 11; // changed in X\n line 12;\n"), base: Self.base)
        let (_, y) = try lines(patch("@@ -10,3 +10,3 @@\n line 10;\n-line 11;\n+line 11; // changed in Y\n line 12;\n"), base: Self.base)
        let region = x.firstIndex { $0.kind == .added }!
        let anchor = AlignmentEngine.locate(region..<region + 1, in: x, target: y)
        XCTAssertEqual(anchor.status, .modified)
        XCTAssertGreaterThanOrEqual(anchor.confidence, 0.6)
        XCTAssertLessThan(anchor.confidence, 1)
        XCTAssertEqual(y[anchor.lines].map(\.text), ["line 11; // changed in Y"])
        XCTAssertNotNil(anchor.tokenDiff)
    }

    func testRegionCoveringContextMapsThroughBaseLines() throws {
        // X adds nothing in 20…22; Y inserts a line there. Selecting
        // 20…22 in X lands on 20…22 plus Y's insertion: modified.
        let (_, x) = try lines(patch("@@ -1,1 +1,1 @@\n-line 1;\n+LINE 1;\n"), base: Self.base)
        let (_, y) = try lines(patch("@@ -20,3 +20,4 @@\n line 20;\n line 21;\n+inserted;\n line 22;\n"), base: Self.base)
        let from = x.firstIndex { $0.baseLine == 20 }!
        let anchor = AlignmentEngine.locate(from..<from + 3, in: x, target: y)
        XCTAssertEqual(anchor.status, .modified)
        XCTAssertEqual(y[anchor.lines].map(\.text), ["line 20;", "line 21;", "inserted;", "line 22;"])
    }

    func testSameTextElsewhereIsMoved() throws {
        let block = "+fn helper() {\n+    do_the_thing();\n+    and_more();\n+}\n"
        let (_, x) = try lines(patch("@@ -5,1 +5,5 @@\n line 5;\n" + block), base: Self.base)
        let (_, y) = try lines(patch("@@ -25,1 +25,5 @@\n line 25;\n" + block), base: Self.base)
        let from = x.firstIndex { $0.text == "fn helper() {" }!
        let anchor = AlignmentEngine.locate(from..<from + 4, in: x, target: y)
        // The declared identifier `helper` is found first (step 5) and the text is identical.
        XCTAssertEqual(anchor.status, .exact)
        XCTAssertEqual(anchor.viaIdentifier, "helper")
        XCTAssertEqual(y[anchor.lines].first?.text, "fn helper() {")

        // Without a declaration, the same block is `moved` by similarity.
        let plain = "+    do_the_thing();\n+    and_more();\n+    third();\n"
        let (_, x2) = try lines(patch("@@ -5,1 +5,4 @@\n line 5;\n" + plain), base: Self.base)
        let (_, y2) = try lines(patch("@@ -25,1 +25,4 @@\n line 25;\n" + plain), base: Self.base)
        let from2 = x2.firstIndex { $0.kind == .added }!
        let anchor2 = AlignmentEngine.locate(from2..<from2 + 3, in: x2, target: y2)
        XCTAssertEqual(anchor2.status, .moved)
        XCTAssertEqual(anchor2.confidence, 1, accuracy: 0.0001)
        XCTAssertEqual(y2[anchor2.lines].map(\.text), ["    do_the_thing();", "    and_more();", "    third();"])
    }

    func testChangeTheOtherPatchDoesNotHaveIsAbsentWithNearestHunk() throws {
        let (_, x) = try lines(patch("@@ -10,1 +10,4 @@\n line 10;\n+if let Some(s) = case.strip_prefix(\"glow-\") {\n+    case = format!(\"glow_{s}\");\n+}\n"), base: Self.base)
        let (yFile, y) = try lines(patch("@@ -25,1 +25,2 @@\n line 25;\n+something_unrelated();\n"), base: Self.base)
        let from = x.firstIndex { $0.kind == .added }!
        let anchor = AlignmentEngine.locate(from..<from + 3, in: x, target: y, targetHunks: yFile.hunks)
        XCTAssertEqual(anchor.status, .absent)
        XCTAssertEqual(anchor.confidence, 0)
        XCTAssertTrue(anchor.lines.isEmpty)
        XCTAssertEqual(y[anchor.lines.lowerBound].baseLine, 11, "the notice sits where the region would fall: right after base line 10")
        XCTAssertEqual(anchor.nearestHunk?.declaredOldStart, 25)
    }

    func testAddedOnlyRegionDoesNotMatchTheContextLineItHangsOff() throws {
        // Y did not touch line 10 at all; the region (added after 10) must not be "modified" against line 10 itself.
        let (_, x) = try lines(patch("@@ -10,1 +10,2 @@\n line 10;\n+brand_new_call();\n"), base: Self.base)
        let (_, y) = try lines(patch("@@ -1,1 +1,1 @@\n-line 1;\n+LINE 1;\n"), base: Self.base)
        let from = x.firstIndex { $0.kind == .added }!
        let anchor = AlignmentEngine.locate(from..<from + 1, in: x, target: y)
        XCTAssertEqual(anchor.status, .absent)
    }

    func testRemovedLinesInTheOtherColumnStillAnchor() throws {
        // X rewrites the signature; Y deletes the function. The region
        // lands on Y's removed lines as `modified`, never `absent`.
        let (_, x) = try lines(patch("@@ -10,2 +10,2 @@\n-fn glow_schema() -> Arc<Schema> {\n+fn glow_schema(level_type: DataType) -> Arc<Schema> {\n line 11;\n"), base: Self.base.replacingOccurrences(of: "line 10;", with: "fn glow_schema() -> Arc<Schema> {"))
        let (_, y) = try lines(patch("@@ -10,2 +10,1 @@\n-fn glow_schema() -> Arc<Schema> {\n line 11;\n"), base: Self.base.replacingOccurrences(of: "line 10;", with: "fn glow_schema() -> Arc<Schema> {"))
        let from = x.firstIndex { $0.kind == .added }!
        let anchor = AlignmentEngine.locate(from..<from + 1, in: x, target: y)
        XCTAssertEqual(anchor.status, .modified)
        XCTAssertEqual(anchor.viaIdentifier, "glow_schema")
        XCTAssertEqual(y[anchor.lines].first?.kind, .removed)
    }

    func testDeclarationsAcrossLanguages() {
        func d(_ s: String) -> [String] { AlignmentEngine.declarations(in: [DisplayLine(kind: .context, baseLine: 1, postLine: 1, text: s)]) }
        XCTAssertEqual(d("fn glow_schema() -> Arc<Schema> {"), ["glow_schema"])
        XCTAssertEqual(d("pub fn generate_ree(path: &Path) {"), ["generate_ree"])
        XCTAssertEqual(d("pub(crate) struct Thing {"), ["Thing"])
        XCTAssertEqual(d("func (s *Server) tempFor(k *Kettle) {"), ["tempFor"])
        XCTAssertEqual(d("func NewServer() *Server {"), ["NewServer"])
        XCTAssertEqual(d("def test_ledger(self):"), ["test_ledger"])
        XCTAssertEqual(d("export const basemap = () => {"), ["basemap"])
        XCTAssertEqual(d("    return glow_schema(level_type);"), [], "a call is not a declaration")
        XCTAssertEqual(d("type Foo struct {"), ["Foo"])
    }

    func testEmptyRegionOrTargetIsAbsent() throws {
        let (_, x) = try lines(patch("@@ -1,1 +1,1 @@\n-line 1;\n+LINE 1;\n"), base: Self.base)
        XCTAssertEqual(AlignmentEngine.locate(0..<0, in: x, target: x).status, .absent)
        XCTAssertEqual(AlignmentEngine.locate(0..<1, in: x, target: []).status, .absent)
        XCTAssertEqual(AlignmentEngine.locate(0..<1, in: x, target: x).status, .exact)
    }

    // MARK: - Golden rendering

    func testGoldenRenderingDiffsAgainstTheGoldenText() {
        let golden = "a\nb\nc\nd\n"
        let other = "a\nB\nc\nd\ne\n"
        let r = GoldenRenderer.render(reference: golden, text: other)
        XCTAssertEqual(r.lines.map(\.kind), [.context, .removed, .added, .context, .context, .added])
        XCTAssertEqual(r.lines.map(\.baseLine), [1, 2, nil, 3, 4, nil])
        XCTAssertEqual(r.lines.map(\.postLine), [1, nil, 2, 3, 4, 5])
        XCTAssertEqual(r.insertedCount, 2)
        XCTAssertEqual(r.deletedCount, 1)
        XCTAssertFalse(r.isIdentical)
        XCTAssertTrue(GoldenRenderer.render(reference: golden, text: golden).isIdentical)
        XCTAssertEqual(GoldenRenderer.render(reference: golden, text: other, includeRemoved: false).lines.count, 5)
    }

    // MARK: - M3 gates on the lantern fixtures (lantern-1, -2, -3)

    struct LanternSession {
        var files: [String: AppliedFile]      // fixture name → main.rs
        var lines: [String: [DisplayLine]]
    }

    static func lantern() throws -> LanternSession {
        let names = ["lantern-1.patch", "lantern-2.patch", "lantern-3.patch"]
        let patches = try names.map { try UnifiedDiffParser.parse(contentsOf: repoRoot.appendingPathComponent("Fixtures/patches/\($0)")) }
        let merged = try SyntheticBase.merged(for: patches)
        let base = InMemoryBase(label: "lantern", texts: Dictionary(uniqueKeysWithValues: merged.map { ($0.path, $0.text) }))
        var session = LanternSession(files: [:], lines: [:])
        for (name, patch) in zip(names, patches) {
            let applied = ApplyEngine.apply(patch, to: base)
            let file = try XCTUnwrap(applied.file(at: "crates/glowmap/src/main.rs"), name)
            XCTAssertEqual(file.status, .clean, name)
            session.files[name] = file
            session.lines[name] = file.displayLines()
        }
        return session
    }

    func testStripPrefixBlockIsAbsentInTheOtherTwoLanternColumnsWithANearestHunk() throws {
        let s = try Self.lantern()
        let c = s.lines["lantern-3.patch"]!
        let start = try XCTUnwrap(c.firstIndex { $0.text.contains("strip_prefix(\"glow-\")") })
        XCTAssertEqual(c[start].kind, .added)
        let region = start..<start + 3   // if let … { / case = format!(…); / }
        for other in ["lantern-1.patch", "lantern-2.patch"] {
            let anchor = AlignmentEngine.locate(region, in: c, target: s.lines[other]!, targetHunks: s.files[other]!.hunks)
            XCTAssertEqual(anchor.status, .absent, "\(other): \(anchor)")
            XCTAssertNotNil(anchor.nearestHunk, "\(other): nearest hunk")
            XCTAssertLessThan(abs((anchor.nearestHunk?.foundOldStart ?? 0) - (c.anchorBase(at: start) ?? 0)), 400, "\(other): nearest hunk should be near")
        }
    }

    func testGlowSchemaIsLocatedAsModifiedOrExactInTheOtherLanternColumns() throws {
        let s = try Self.lantern()
        for source in s.lines.keys.sorted() {
            let x = s.lines[source]!
            let start = try XCTUnwrap(x.firstIndex { $0.text.hasPrefix("fn glow_schema") && $0.kind != .removed } ?? x.firstIndex { $0.text.hasPrefix("fn glow_schema") }, source)
            let region = start..<min(x.count, start + 8)
            for target in s.lines.keys.sorted() where target != source {
                let anchor = AlignmentEngine.locate(region, in: x, target: s.lines[target]!, targetHunks: s.files[target]!.hunks)
                XCTAssertTrue(anchor.status == .modified || anchor.status == .exact, "\(source) → \(target): \(anchor.status) \(anchor.confidence)")
                XCTAssertTrue(s.lines[target]![anchor.lines].contains { $0.text.contains("fn glow_schema") }, "\(source) → \(target): located lines should hold the declaration")
            }
        }
    }

    func testGoldenSwitchOverTheFourGoPatchesIsFast() throws {
        let names = (1...4).map { "kettle-\($0).patch" }
        let patches = try names.map { try UnifiedDiffParser.parse(contentsOf: Self.repoRoot.appendingPathComponent("Fixtures/patches/\($0)")) }
        let merged = try SyntheticBase.merged(for: patches)
        let base = InMemoryBase(label: "kettle", texts: Dictionary(uniqueKeysWithValues: merged.map { ($0.path, $0.text) }))
        let applied = patches.map { ApplyEngine.apply($0, to: base) }
        let paths = Set(applied.flatMap { $0.files.map(\.path) })
        // Set each column golden in turn and re-render every other column's every file.
        var worst: TimeInterval = 0
        for golden in applied {
            let start = Date()
            var renders = 0
            for other in applied where other != golden {
                for path in paths {
                    let g = golden.file(at: path)?.postText ?? (try? base.contents(of: path)).flatMap { $0 }.map(BaseLoader.text(from:)) ?? ""
                    let o = other.file(at: path)?.postText ?? (try? base.contents(of: path)).flatMap { $0 }.map(BaseLoader.text(from:)) ?? ""
                    _ = GoldenRenderer.render(reference: g, text: o)
                    renders += 1
                }
            }
            worst = max(worst, Date().timeIntervalSince(start))
            XCTAssertGreaterThan(renders, 30)
        }
        XCTAssertLessThan(worst, 1.0, "a golden switch must render in under 1 s (spec); worst \(worst)s")
    }
    func testSearchingTempForAcrossTheGoPatchesFindsSixtyOrMoreHitsGroupedByFile() throws {
        // FR-19: the app's search walks every column's display lines per
        // file. The same walk, engine-side, over four Go patches.
        let names = (1...4).map { "kettle-\($0).patch" }
        let patches = try names.map { try UnifiedDiffParser.parse(contentsOf: Self.repoRoot.appendingPathComponent("Fixtures/patches/\($0)")) }
        let merged = try SyntheticBase.merged(for: patches)
        let base = InMemoryBase(label: "go", texts: Dictionary(uniqueKeysWithValues: merged.map { ($0.path, $0.text) }))
        let query = "tempFor(k)"
        var hitsPerPatch: [String: Int] = [:]
        var filesWithHits: Set<String> = []
        for (name, patch) in zip(names, patches) {
            let applied = ApplyEngine.apply(patch, to: base)
            for file in applied.files {
                let hits = file.displayLines().filter { $0.text.localizedCaseInsensitiveContains(query) }.count
                if hits > 0 { filesWithHits.insert(file.path) }
                hitsPerPatch[name, default: 0] += hits
            }
        }
        XCTAssertGreaterThanOrEqual(hitsPerPatch["kettle-2.patch"] ?? 0, 60, "\(hitsPerPatch)")
        XCTAssertEqual(hitsPerPatch.filter { $0.value > 0 }.count, 1, "only one patch has the identifier: \(hitsPerPatch)")
        XCTAssertFalse(filesWithHits.isEmpty, "hits group by file")
    }
}
