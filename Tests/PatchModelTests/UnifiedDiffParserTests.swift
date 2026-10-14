import XCTest
@testable import PatchModel

final class UnifiedDiffParserTests: XCTestCase {

    func testMinimalModification() throws {
        let text = """
        diff --git a/src/downloader.go b/src/downloader.go
        index 1111111..2222222 100644
        --- a/src/downloader.go
        +++ b/src/downloader.go
        @@ -50,3 +50,4 @@ func tempFor(k *Kettle) {
         keep
        -old
        +new
        +added
         tail

        """
        let patch = try UnifiedDiffParser.parse(text)
        XCTAssertNil(patch.mailHeader)
        XCTAssertEqual(patch.files.count, 1)
        let file = patch.files[0]
        XCTAssertEqual(file.kind, .modified)
        XCTAssertEqual(file.path, "src/downloader.go")
        XCTAssertEqual(file.fileName, "downloader.go")
        XCTAssertEqual(file.oldMode, "100644")
        XCTAssertEqual(file.hunks.count, 1)
        let hunk = file.hunks[0]
        XCTAssertEqual(hunk.sectionHeading, "func tempFor(k *Kettle) {")
        XCTAssertEqual(hunk.oldRange, 50...52)
        XCTAssertEqual(hunk.newRange, 50...53)
        XCTAssertEqual(hunk.lines.map(\.kind), [.context, .removed, .added, .added, .context])
        XCTAssertEqual(file.lineCounts.added, 2)
        XCTAssertEqual(file.lineCounts.removed, 1)
        let numbered = hunk.numberedLines
        XCTAssertEqual(numbered.map(\.oldNumber), [50, 51, nil, nil, 52])
        XCTAssertEqual(numbered.map(\.newNumber), [50, nil, 51, 52, 53])
    }

    func testSingleLineRangeWithoutComma() throws {
        let text = """
        --- a/x.txt
        +++ b/x.txt
        @@ -1 +1 @@
        -a
        +b
        """
        let patch = try UnifiedDiffParser.parse(text)
        let hunk = patch.files[0].hunks[0]
        XCTAssertEqual(hunk.oldCount, 1)
        XCTAssertEqual(hunk.newCount, 1)
        XCTAssertEqual(patch.files[0].path, "x.txt")
    }

    func testDeletedFile() throws {
        let text = """
        diff --git a/gone.rs b/gone.rs
        deleted file mode 100644
        index 3333333..0000000
        --- a/gone.rs
        +++ /dev/null
        @@ -1,2 +0,0 @@
        -fn main() {}
        -// end
        """
        let file = try UnifiedDiffParser.parse(text).files[0]
        XCTAssertEqual(file.kind, .deleted)
        XCTAssertEqual(file.oldPath, "gone.rs")
        XCTAssertNil(file.newPath)
        XCTAssertEqual(file.path, "gone.rs")
        XCTAssertNil(file.hunks[0].newRange)
        XCTAssertEqual(file.hunks[0].oldRange, 1...2)
    }

    func testBinaryStub() throws {
        let text = """
        diff --git a/icon.png b/icon.png
        new file mode 100644
        index 0000000..abcdef0
        Binary files /dev/null and b/icon.png differ
        diff --git a/a.txt b/a.txt
        --- a/a.txt
        +++ b/a.txt
        @@ -1 +1 @@
        -x
        +y
        """
        let patch = try UnifiedDiffParser.parse(text)
        XCTAssertEqual(patch.files.count, 2)
        XCTAssertTrue(patch.files[0].isBinary)
        XCTAssertEqual(patch.files[0].kind, .added)
        XCTAssertEqual(patch.files[0].path, "icon.png")
        XCTAssertTrue(patch.files[0].hunks.isEmpty)
        XCTAssertFalse(patch.files[1].isBinary)
    }

    func testGitBinaryPatchIsSkipped() throws {
        let text = """
        diff --git a/blob.bin b/blob.bin
        index 1111111..2222222 100644
        GIT binary patch
        literal 4
        LcmZQz0000
        
        literal 0
        HcmV?d00001
        
        diff --git a/a.txt b/a.txt
        --- a/a.txt
        +++ b/a.txt
        @@ -1 +1 @@
        -x
        +y
        """
        let patch = try UnifiedDiffParser.parse(text)
        XCTAssertEqual(patch.files.count, 2)
        XCTAssertTrue(patch.files[0].isBinary)
        XCTAssertEqual(patch.files[1].path, "a.txt")
    }

    func testPureRenameWithoutHunks() throws {
        let text = """
        diff --git a/old name.txt b/new name.txt
        similarity index 100%
        rename from old name.txt
        rename to new name.txt
        """
        let file = try UnifiedDiffParser.parse(text).files[0]
        XCTAssertEqual(file.kind, .renamed)
        XCTAssertEqual(file.oldPath, "old name.txt")
        XCTAssertEqual(file.newPath, "new name.txt")
        XCTAssertEqual(file.similarity, 100)
        XCTAssertTrue(file.hunks.isEmpty)
    }

    func testModeChangeOnly() throws {
        let text = """
        diff --git a/run.sh b/run.sh
        old mode 100644
        new mode 100755
        """
        let file = try UnifiedDiffParser.parse(text).files[0]
        XCTAssertEqual(file.oldMode, "100644")
        XCTAssertEqual(file.newMode, "100755")
        XCTAssertEqual(file.kind, .modified)
        XCTAssertEqual(file.path, "run.sh")
    }

    func testQuotedPathsWithSpaces() throws {
        let text = """
        diff --git "a/dir/my file.txt" "b/dir/my file.txt"
        --- "a/dir/my file.txt"
        +++ "b/dir/my file.txt"
        @@ -1 +1 @@
        -a
        +b
        """
        let file = try UnifiedDiffParser.parse(text).files[0]
        XCTAssertEqual(file.path, "dir/my file.txt")
        XCTAssertEqual(file.fileName, "my file.txt")
    }

    func testNoNewlineMarker() throws {
        let text = """
        --- a/f
        +++ b/f
        @@ -1 +1 @@
        -a
        \\ No newline at end of file
        +b
        \\ No newline at end of file
        """
        let hunk = try UnifiedDiffParser.parse(text).files[0].hunks[0]
        XCTAssertEqual(hunk.lines.count, 2)
        XCTAssertTrue(hunk.lines[0].noNewlineAtEnd)
        XCTAssertTrue(hunk.lines[1].noNewlineAtEnd)
    }

    func testFormatPatchMailHeaderAndSignature() throws {
        let text = """
        From 0123456789abcdef0123456789abcdef01234567 Mon Sep 17 00:00:00 2001
        From: Jane Doe <jane@example.com>
        Date: Tue, 14 Oct 2026 10:00:00 +0000
        Subject: [PATCH] Add tempFor cache
         and keep it warm

        Explains why.

        Second paragraph.
        ---
         a.go | 2 +-
         1 file changed, 1 insertion(+), 1 deletion(-)

        diff --git a/a.go b/a.go
        --- a/a.go
        +++ b/a.go
        @@ -1 +1 @@
        -x
        +y
        -- 
        2.46.0

        """
        let patch = try UnifiedDiffParser.parse(text)
        let header = try XCTUnwrap(patch.mailHeader)
        XCTAssertEqual(header.from, "Jane Doe <jane@example.com>")
        XCTAssertEqual(header.subject, "[PATCH] Add tempFor cache and keep it warm")
        XCTAssertEqual(header.date, "Tue, 14 Oct 2026 10:00:00 +0000")
        XCTAssertEqual(header.body, "Explains why.\n\nSecond paragraph.")
        XCTAssertEqual(patch.files.count, 1)
        XCTAssertEqual(patch.files[0].hunks[0].lines.count, 2)
    }

    func testTruncatedHunkIsAnError() {
        let text = """
        --- a/f
        +++ b/f
        @@ -1,3 +1,3 @@
         a
        -b
        +c
        """
        XCTAssertThrowsError(try UnifiedDiffParser.parse(text)) { error in
            let e = error as? PatchParseError
            XCTAssertNotNil(e)
            XCTAssertTrue(e?.message.contains("ends early") ?? false, "\(String(describing: e))")
        }
    }

    func testGarbageIsAnError() {
        XCTAssertThrowsError(try UnifiedDiffParser.parse("hello\nworld\n"))
    }

    func testEmptyContextLineStrippedByMailer() throws {
        // Some mailers strip the single space from an empty context line.
        let text = "--- a/f\n+++ b/f\n@@ -1,3 +1,3 @@\n a\n\n-b\n+c\n"
        let hunk = try UnifiedDiffParser.parse(text).files[0].hunks[0]
        XCTAssertEqual(hunk.lines.map(\.kind), [.context, .context, .removed, .added])
        XCTAssertEqual(hunk.lines[1].text, "")
    }

    func testIsTestHeuristic() {
        func fc(_ p: String) -> FileChange { FileChange(oldPath: p, newPath: p, kind: .modified) }
        XCTAssertTrue(fc("tests/test_ledger.py").isTest)
        XCTAssertTrue(fc("internal/api/handler/task_test.go").isTest)
        XCTAssertTrue(fc("Tests/PatchModelTests/FixtureTests.swift").isTest)
        XCTAssertTrue(fc("src/foo.test.ts").isTest)
        XCTAssertFalse(fc("cmd/server/main.go").isTest)
        XCTAssertFalse(fc("crates/glowmap-core/src/lib.rs").isTest)
    }

    func testCodableRoundTrip() throws {
        let text = "--- a/f.go\n+++ b/f.go\n@@ -1,2 +1,2 @@ fn\n a\n-b\n+c\n"
        let patch = try UnifiedDiffParser.parse(text)
        let data = try JSONEncoder().encode(patch)
        let back = try JSONDecoder().decode(Patch.self, from: data)
        XCTAssertEqual(back, patch)
    }
}
