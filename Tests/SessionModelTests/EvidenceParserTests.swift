import XCTest
@testable import SessionModel

final class EvidenceParserTests: XCTestCase {

    func testSingleLineAndRangeReferToTheFileBeforeThem() {
        let found = EvidenceParser.parse("brew_task.go L100 retries twice, and L100-L110 duplicates the loop.")
        XCTAssertEqual(found, [
            Evidence(fileName: "brew_task.go", start: 100, end: 100),
            Evidence(fileName: "brew_task.go", start: 100, end: 110),
        ])
    }

    func testANewFileNameTakesOverTheReferencesAfterIt() {
        let found = EvidenceParser.parse("""
            internal/service/brew_task.go L12-L20 wraps the error twice.
            Same in kettle.swift L5, L7-L9.
            """)
        XCTAssertEqual(found, [
            Evidence(fileName: "internal/service/brew_task.go", start: 12, end: 20),
            Evidence(fileName: "kettle.swift", start: 5, end: 5),
            Evidence(fileName: "kettle.swift", start: 7, end: 9),
        ])
    }

    func testReferenceFormatWithColonAndBareEndParses() {
        XCTAssertEqual(EvidenceParser.parse("a.py L3:L4 and L8-9 and L10 – L12"), [
            Evidence(fileName: "a.py", start: 3, end: 4),
            Evidence(fileName: "a.py", start: 8, end: 9),
            Evidence(fileName: "a.py", start: 10, end: 12),
        ])
    }

    func testParenthesisedReferenceParses() {
        XCTAssertEqual(EvidenceParser.parse("The lookup is repeated (catalog.go L106-L110) and again (store.go L3)."), [
            Evidence(fileName: "catalog.go", start: 106, end: 110),
            Evidence(fileName: "store.go", start: 3, end: 3),
        ])
    }

    func testSpaceAfterLParses() {
        XCTAssertEqual(EvidenceParser.parse("(main.go L 759:L 793), L 450"), [
            Evidence(fileName: "main.go", start: 759, end: 793),
            Evidence(fileName: "main.go", start: 450, end: 450),
        ])
    }

    func testPatchLetterBeforeAFileNamesThePatch() {
        XCTAssertEqual(EvidenceParser.parse("A repeats it (A main.go L699-L702, L710) where B does not (B main.go L640) and catalog.go L5."), [
            Evidence(fileName: "main.go", start: 699, end: 702, label: "A"),
            Evidence(fileName: "main.go", start: 710, end: 710, label: "A"),
            Evidence(fileName: "main.go", start: 640, end: 640, label: "B"),
            Evidence(fileName: "catalog.go", start: 5, end: 5),
        ])
    }

    func testPatchLetterRoundTripsThroughTheReference() {
        let evidence = Evidence(fileName: "internal/main.go", start: 699, end: 702, label: "B")
        XCTAssertEqual(evidence.reference, "B main.go L699:L702")
        XCTAssertEqual(EvidenceParser.parse(evidence.reference), [Evidence(fileName: "main.go", start: 699, end: 702, label: "B")])
    }

    func testEachReferenceKnowsWhereItIsWritten() {
        let text = "Repeats it (B main.go L699-L702, L710) and util.go L5."
        let sources = EvidenceParser.parseWithSources(text).map { (text as NSString).substring(with: $0.source) }
        XCTAssertEqual(sources, ["B main.go L699-L702", "L710", "util.go L5"])
    }

    func testLeadingMinusIsTheRemovedSide() {
        XCTAssertEqual(EvidenceParser.parse("main.rs -L40:L42 was deleted"),
                       [Evidence(fileName: "main.rs", start: 40, end: 42, removedSide: true)])
    }

    func testReferenceBeforeAnyFileNameIsDropped() {
        XCTAssertEqual(EvidenceParser.parse("L5 is odd; see util.go L9"), [Evidence(fileName: "util.go", start: 9, end: 9)])
    }

    func testProseWithDotsIsNotAFileName() {
        XCTAssertEqual(EvidenceParser.parse("util.go L1, e.g. version 1.2 L3 and LOL L4x"), [
            Evidence(fileName: "util.go", start: 1, end: 1),
            Evidence(fileName: "util.go", start: 3, end: 3),
        ])
    }

    func testReversedRangeIsOrdered() {
        XCTAssertEqual(EvidenceParser.parse("x.ts L20-L10"), [Evidence(fileName: "x.ts", start: 10, end: 20)])
    }

    func testReferenceUsesTheFileNameOnly() {
        XCTAssertEqual(Evidence(fileName: "internal/a.go", start: 1, end: 3, removedSide: true).reference, "a.go -L1:L3")
    }
}

final class EvidenceParserReviewTextTests: XCTestCase {
    // An invented finding in the shape reviewers write (issue #17): a
    // bare `(L1044)`, a call glued to a file name, a typo in
    // "Implementation". No real review text (DECISIONS.md D10).
    static let review = """
        Implementation A has the most slop of all three. It adds an optional brewTimerProvider interface and finds it using a type assertion (main.go L349, L699-L702) thus ignoring existing behavior in kettleRegistration (catalog.go L106-L110) this is speculative flexibility beyond the request.

        A adds the empty, duplicate and overlap tests for steep in (main.go L1041-L1047) using one message for all three faults (L1044) which is a strike against maintenance. A copies each field manually in the notifier (dispatchers.go L133-L139), which repeats what copyReading(alerts.go (L124-L131) already does.
        Implmentation A has tests with little value. In (runtime_test.go L1068) and (runtime_test.go L1075).  the same conditions are checked twice. (runtime_test.go L1234) has a confusing "status" message which could mislead a reviewer .
        """

    func testEveryReferenceInAReviewParagraphIsFound() {
        XCTAssertEqual(EvidenceParser.parse(Self.review).map(\.reference), [
            "main.go L349:L349", "main.go L699:L702", "catalog.go L106:L110",
            "main.go L1041:L1047", "main.go L1044:L1044", "dispatchers.go L133:L139",
            "alerts.go L124:L131", "runtime_test.go L1068:L1068", "runtime_test.go L1075:L1075",
            "runtime_test.go L1234:L1234",
        ])
    }

    func testImplementationLetterNamesThePatch() {
        XCTAssertEqual(EvidenceParser.patchLabel(in: Self.review), "A")
        XCTAssertEqual(EvidenceParser.patchLabel(in: "In patch C the loop repeats."), "C")
        XCTAssertEqual(EvidenceParser.patchLabel(in: "Column 2 is cleaner."), "2")
    }

    func testLowercaseLetterIsNotAPatch() {
        XCTAssertNil(EvidenceParser.patchLabel(in: "we patch a file and move on"))
    }
}
