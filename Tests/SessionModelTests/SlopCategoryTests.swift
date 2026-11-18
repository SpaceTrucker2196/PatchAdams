import XCTest
@testable import SessionModel

final class SlopCategoryTests: XCTestCase {
    let categories = Session.defaultCategories

    func testDefaultCategoriesKeepTheNamesOlderSessionsStore() {
        XCTAssertEqual(categories, [
            "unnecessary helpers", "excessive defensiveness", "unnecessary machinery or repeated work",
            "duplicated logic or state", "too many branches", "unclear code", "unhelpful comments or names",
            "code in the wrong place", "unneeded backwards compatibility", "dead or unrelated code",
            "premature extensibility", "low-value tests", "other",
        ])
    }

    func testEveryCategoryHasASlugAndASummary() {
        for category in SlopCategory.all {
            XCTAssertFalse(category.slug.isEmpty, category.name)
            XCTAssertFalse(category.summary.isEmpty, category.name)
            XCTAssertEqual(SlopCategory.summary(of: category.slug), category.summary)
            XCTAssertEqual(SlopCategory.summary(of: category.name.capitalized), category.summary)
        }
        XCTAssertNil(SlopCategory.summary(of: "my own category"))
    }

    private func pieces(_ text: String) -> [(String?, String)] {
        let ns = text as NSString
        return CategoryHeadings.sections(text, categories: categories).map { ($0.category, ns.substring(with: $0.range)) }
    }

    func testAHeadingNamesTheCategoryOfTheTextUnderIt() {
        let text = "Unneeded Backwards Compatibility: brew.go L10-L12 keeps the old wrapper.\nNo caller is left.\n"
            + "unnecessary_machinery_or_repeated_work: queue.go L40 retries with no need.\n"
            + "- **Too many branches**: heater.go L5-L9 nests three ifs."
        let found = pieces(text)
        XCTAssertEqual(found.map(\.0), ["unneeded backwards compatibility", "unnecessary machinery or repeated work", "too many branches"])
        XCTAssertEqual(found.map(\.1), ["brew.go L10-L12 keeps the old wrapper.\nNo caller is left.\n", "queue.go L40 retries with no need.\n", "heater.go L5-L9 nests three ifs."])
    }

    func testTextBeforeTheFirstHeadingHasNoCategory() {
        let found = pieces("intro\nUnclear code: a.go L1\nmore\nOther: b.go L2")
        XCTAssertEqual(found.map(\.0), [nil, "unclear code", "other"])
        XCTAssertEqual(found.map(\.1), ["intro\n", "a.go L1\nmore\n", "b.go L2"])
    }

    func testTextWithNoHeadingIsOneUnlabelledRun() {
        let found = pieces("brew.go L1 retries.\nSee L2 too.")
        XCTAssertEqual(found.map(\.0), [nil])
        XCTAssertEqual(found.map(\.1), ["brew.go L1 retries.\nSee L2 too."])
    }

    func testAnyShortLabelWithAColonIsAHeading() {
        let found = pieces("Bad Tests: a.go L1 asserts nothing.\nBad Tests:\na.go L2 too.\n**Unclear code**: a.go L3.")
        XCTAssertEqual(found.map(\.0), ["bad tests", "bad tests", "unclear code"])
        XCTAssertEqual(found.map(\.1), ["a.go L1 asserts nothing.\n", "a.go L2 too.\n", "a.go L3."])
    }

    func testReferencesURLsPatchNamesAndSentencesAreNotHeadings() {
        let text = ["Implementation A: brew.go L1 is odd.",
                    "See https://example.com/x for the spec.",
                    "brew.go L10: the loop.",
                    "The retry loop in this file is wrong because: it never stops."].joined(separator: "\n")
        XCTAssertEqual(pieces(text).map(\.0), [nil])
    }
}
