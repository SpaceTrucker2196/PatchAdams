import XCTest
@testable import SessionModel

final class ReleaseVersionTests: XCTestCase {
    func testReleaseTagsParseToTheirNumbers() {
        XCTAssertEqual(ReleaseVersion(tag: "v1.1.2-Release")?.components, [1, 1, 2])
        XCTAssertEqual(ReleaseVersion(tag: "1.1.2")?.components, [1, 1, 2])
        XCTAssertEqual(ReleaseVersion(tag: " V2.0 ")?.components, [2, 0])
        XCTAssertNil(ReleaseVersion(tag: "Release"))
        XCTAssertNil(ReleaseVersion(tag: ""))
    }

    func testVersionsCompareByNumberNotByText() {
        XCTAssertLessThan(ReleaseVersion(tag: "1.1.2")!, ReleaseVersion(tag: "1.2.0")!)
        XCTAssertLessThan(ReleaseVersion(tag: "1.9.9")!, ReleaseVersion(tag: "1.10.0")!)
        XCTAssertGreaterThan(ReleaseVersion(tag: "v2")!, ReleaseVersion(tag: "v1.99.99")!)
        XCTAssertEqual(ReleaseVersion(tag: "1.1.2")!, ReleaseVersion(tag: "1.1.2.0")!)
        XCTAssertFalse(ReleaseVersion(tag: "1.1.2")! < ReleaseVersion(tag: "1.1.2")!)
        XCTAssertEqual(ReleaseVersion(tag: "v1.1.2-Release")!.description, "1.1.2")
    }
}
