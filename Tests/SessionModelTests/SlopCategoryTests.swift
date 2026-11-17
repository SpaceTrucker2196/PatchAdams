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

    func testAHeadingNamesTheCategoryAndStartsAFinding() {
        let text = """
        Unneeded Backwards Compatibility: brew.go L10-L12 keeps the old wrapper.
        No caller is left.
        unnecessary_machinery_or_repeated_work: queue.go L40 retries with no need.
        - **Too many branches**: heater.go L5-L9 nests three ifs.
        """
        XCTAssertEqual(CategoryHeadings.split(text, categories: categories), [
            PastedFinding(category: "unneeded backwards compatibility", text: "brew.go L10-L12 keeps the old wrapper.\nNo caller is left."),
            PastedFinding(category: "unnecessary machinery or repeated work", text: "queue.go L40 retries with no need."),
            PastedFinding(category: "too many branches", text: "heater.go L5-L9 nests three ifs."),
        ])
    }

    func testTextBeforeTheFirstHeadingIsAFindingWithNoCategory() {
        let text = "brew.go L1 is odd.\n\nDead or unrelated code: brew.go L2 is unused."
        XCTAssertEqual(CategoryHeadings.split(text, categories: categories), [
            PastedFinding(category: nil, text: "brew.go L1 is odd."),
            PastedFinding(category: "dead or unrelated code", text: "brew.go L2 is unused."),
        ])
    }

    func testAPasteWithNoHeadingIsOneFinding() {
        XCTAssertEqual(CategoryHeadings.split("Note: brew.go L1 retries.\nSee L2 too.", categories: categories),
                       [PastedFinding(category: nil, text: "Note: brew.go L1 retries.\nSee L2 too.")])
        XCTAssertEqual(CategoryHeadings.split("  \n", categories: categories), [])
    }

    func testOnlyTheSessionsOwnCategoriesSplit() {
        let text = "Unclear code: brew.go L1.\nMy rule: brew.go L2."
        XCTAssertEqual(CategoryHeadings.split(text, categories: ["unclear code"]),
                       [PastedFinding(category: "unclear code", text: "brew.go L1.\nMy rule: brew.go L2.")])
        XCTAssertEqual(CategoryHeadings.split(text, categories: ["my rule"]), [
            PastedFinding(category: nil, text: "Unclear code: brew.go L1."),
            PastedFinding(category: "my rule", text: "brew.go L2."),
        ])
    }
}
