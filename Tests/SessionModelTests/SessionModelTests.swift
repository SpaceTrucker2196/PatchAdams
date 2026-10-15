import XCTest
@testable import SessionModel

final class SessionModelTests: XCTestCase {

    static func sample(blind: Bool = false) -> Session {
        var session = Session(
            name: "kettle review",
            request: "Add retry to the download task.\nKeep the API stable.",
            base: .synthetic,
            columns: [
                SessionColumn(label: "A", sourceName: "kettle-1.patch", patchFile: ""),
                SessionColumn(label: "B", sourceName: "kettle-2.patch", patchFile: ""),
                SessionColumn(label: "C", sourceName: "kettle-3.patch", patchFile: ""),
                SessionColumn(label: "D", sourceName: "kettle-4.patch", patchFile: ""),
            ],
            golden: "B",
            blind: BlindMode(isOn: blind, seed: 42))
        session.findings = [
            Finding(label: "A", path: "internal/service/brew_task.go", lines: LineSpan(9..<17), reference: "brew_task.go L10:L17",
                    title: "Retry helper wraps one call", description: "A three-line loop would do.\nThe helper has one caller.",
                    category: "unnecessary helpers", severity: .material, requestAsks: .no,
                    anchors: [FindingAnchor(label: "B", status: "modified", confidence: 0.81, reference: "brew_task.go L12:L20"),
                              FindingAnchor(label: "C", status: "absent", confidence: 0, reference: nil)]),
            Finding(label: "A", path: "internal/service/brew_task.go", lines: LineSpan(40..<41), reference: "brew_task.go L41:L41",
                    title: "Nil check on a value that cannot be nil", category: "excessive defensiveness", severity: .minor),
            Finding(label: "C", path: "internal/service/heater.go", lines: LineSpan(2..<5), reference: "heater.go L3:L5",
                    title: "Unrelated import reorder", category: "dead or unrelated code", severity: .trivial, notFlagged: true,
                    note: "gofmt did this"),
            Finding(label: "B", path: "internal/service/brew_task.go", lines: LineSpan(0..<3), reference: "brew_task.go -L1:L3",
                    title: "Deleted the context cancel", category: "other", severity: .blocking, note: "possible leak — check"),
        ]
        session.ranking = Ranking(ranks: ["B": 1, "A": 2, "D": 2, "C": 4], rationale: "B is the smallest correct change.\nA and D tie.")
        // ISO 8601 keeps whole seconds; a round trip must compare equal.
        for i in session.findings.indices { session.findings[i].created = Date(timeIntervalSince1970: 1_790_000_000 + Double(i)) }
        return session
    }

    // MARK: - Round trips

    func testSessionRoundTripsThroughJSON() throws {
        let session = Self.sample()
        let data = try SessionPackage.encodeSession(session)
        let back = try SessionPackage.decoder.decode(Session.self, from: data)
        XCTAssertEqual(back.findings, session.findings)
        XCTAssertEqual(back.ranking, session.ranking)
        XCTAssertEqual(back.columns, session.columns)
        XCTAssertEqual(back.golden, "B")
        XCTAssertEqual(back.categories, Session.defaultCategories)
        XCTAssertEqual(back.blind, session.blind)
    }

    func testPackageWritesSessionAndPatchCopiesAndReadsThemBack() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SessionModelTests-\(UUID().uuidString).patchadam")
        defer { try? FileManager.default.removeItem(at: dir) }
        let texts = ["A": "diff --git a/x b/x\n", "B": "diff --git a/y b/y\n", "C": "c\n", "D": "d\n"]
        try SessionPackage.write(SessionPackage.Contents(session: Self.sample(), patchTexts: texts), to: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("session.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("patches/A-kettle-1.patch").path))
        let back = try SessionPackage.read(from: dir)
        XCTAssertEqual(back.patchTexts, texts)
        XCTAssertEqual(back.session.findings.count, 4)
        XCTAssertNotNil(back.session.saved)
        XCTAssertEqual(back.session.columns.map(\.patchFile), ["A-kettle-1.patch", "B-kettle-2.patch", "C-kettle-3.patch", "D-kettle-4.patch"])
    }

    func testPackageWithoutAPatchTextIsAnError() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SessionModelTests-\(UUID().uuidString).patchadam")
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertThrowsError(try SessionPackage.write(SessionPackage.Contents(session: Self.sample(), patchTexts: ["A": "x"]), to: dir))
    }

    func testPatchFileNamesAreSafe() {
        XCTAssertEqual(SessionPackage.safeFileName("../evil/name.patch"), ".._evil_name.patch")
        XCTAssertEqual(SessionPackage.safeFileName(""), "patch")
    }

    // MARK: - Blind mode

    func testBlindMappingIsSeededAndCoversEveryLabel() {
        let blind = BlindMode(isOn: true, seed: 42)
        let labels = ["A", "B", "C", "D"]
        let m1 = blind.mapping(for: labels)
        let m2 = BlindMode(isOn: true, seed: 42).mapping(for: labels.reversed())
        XCTAssertEqual(m1, m2, "the mapping depends on the seed, not on the order the labels arrive in")
        XCTAssertEqual(Set(m1.values), Set(1...4))
        XCTAssertNotEqual(m1, BlindMode(isOn: true, seed: 7).mapping(for: labels))
        // The seed→order relation is frozen: a session saved today must open to the same numbers.
        XCTAssertEqual(BlindMode.shuffled(labels, seed: 42), ["C", "A", "D", "B"])
    }

    func testDisplayLabelIsTheLetterUnlessBlind() {
        XCTAssertEqual(Self.sample().displayLabel("C"), "C")
        let blind = Self.sample(blind: true)
        XCTAssertTrue(["1", "2", "3", "4"].contains(blind.displayLabel("C")))
    }

    // MARK: - Ranking

    func testRankedColumnsOrderByRankWithTiesInDisplayOrderAndUnrankedLast() {
        var session = Self.sample()
        session.ranking.ranks["C"] = nil
        XCTAssertEqual(session.rankedColumns.map(\.label), ["B", "A", "D", "C"])
    }

    // MARK: - Markdown export (FR-32, D5)

    func testMarkdownExportMatchesTheWriteUpShape() {
        let md = MarkdownExport.render(Self.sample(), date: Date(timeIntervalSince1970: 1_790_000_000))
        let expected = """
        # kettle review

        _4 patches · 3 findings · 2026-09-21_

        <details><summary>Request</summary>

        Add retry to the download task.
        Keep the API stable.

        </details>

        ## Ranking

        | Rank | Patch | File |
        |---:|---|---|
        | 1 | B | `kettle-2.patch` |
        | 2 | A | `kettle-1.patch` |
        | 2 | D | `kettle-4.patch` |
        | 4 | C | `kettle-3.patch` |

        ## Findings

        ### B — `kettle-2.patch` (rank 1)

        - **blocking · other** — Deleted the context cancel `brew_task.go -L1:L3`
          Note: possible leak — check

        ### A — `kettle-1.patch` (rank 2)

        - **material · unnecessary helpers** — Retry helper wraps one call `brew_task.go L10:L17`
          A three-line loop would do. The helper has one caller.
          Request asks for this: no.
        - **minor · excessive defensiveness** — Nil check on a value that cannot be nil `brew_task.go L41:L41`

        ## Not flagged

        Considered and passed:

        - C `heater.go L3:L5` — Unrelated import reorder

        ## Rationale

        B is the smallest correct change.
        A and D tie.

        """
        XCTAssertEqual(md, expected)
    }

    func testBlindMarkdownHidesFileNamesUntilTheMappingAtTheEnd() {
        let session = Self.sample(blind: true)
        let md = MarkdownExport.render(session)
        let mappingStart = md.range(of: "## Mapping")!.lowerBound
        let body = md[..<mappingStart]
        for column in session.columns {
            XCTAssertFalse(body.contains(column.sourceName), "\(column.sourceName) leaked before the mapping")
            XCTAssertFalse(body.contains("### \(column.label) —"), "letter heading leaked")
        }
        let tail = md[mappingStart...]
        for column in session.columns {
            XCTAssertTrue(tail.contains("| \(session.displayLabel(column.label)) | \(column.label) | `\(column.sourceName)` |"))
        }
        XCTAssertTrue(md.hasSuffix("|\n"), "the mapping is the last thing in the file")
    }

    func testEveryReferenceInTheExportComesFromAFinding() {
        let session = Self.sample()
        let md = MarkdownExport.render(session)
        let pattern = try! NSRegularExpression(pattern: #"`([^`]+ -?L\d+:L\d+)`"#)
        let found = pattern.matches(in: md, range: NSRange(md.startIndex..., in: md)).map { String(md[Range($0.range(at: 1), in: md)!]) }
        XCTAssertEqual(Set(found), Set(session.findings.map(\.reference)))
    }

    // MARK: - JSON export (FR-33)

    func testJSONExportCarriesAnchorsAndConfidence() throws {
        let data = try JSONExport.render(Self.sample(blind: true))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let session = try XCTUnwrap(json["session"] as? [String: Any])
        let findings = try XCTUnwrap(session["findings"] as? [[String: Any]])
        let anchors = try XCTUnwrap(findings[0]["anchors"] as? [[String: Any]])
        XCTAssertEqual(anchors[0]["status"] as? String, "modified")
        XCTAssertEqual(anchors[0]["confidence"] as? Double, 0.81)
        let mapping = try XCTUnwrap(json["blindMapping"] as? [String: Int])
        XCTAssertEqual(Set(mapping.keys), ["A", "B", "C", "D"])
    }

    // MARK: - Findings and manual anchors

    func testFindingNeedsTitleCategoryAndReference() {
        var f = Finding(label: "A", path: "x", lines: LineSpan(0..<1), reference: "x L1:L1", title: "", category: "other", severity: .minor)
        XCTAssertFalse(f.isComplete)
        f.title = "t"
        XCTAssertTrue(f.isComplete)
        f.category = ""
        XCTAssertFalse(f.isComplete)
    }

    func testManualAnchorMatchesItsSourceRegion() {
        let m = ManualAnchor(sourceLabel: "A", path: "x", sourceLines: LineSpan(3..<9), targetLabel: "B", targetLines: LineSpan(5..<11))
        XCTAssertTrue(m.matches(sourceLabel: "A", path: "x", sourceLines: 3..<9))
        XCTAssertFalse(m.matches(sourceLabel: "A", path: "x", sourceLines: 3..<8))
        XCTAssertFalse(m.matches(sourceLabel: "B", path: "x", sourceLines: 3..<9))
    }
}
