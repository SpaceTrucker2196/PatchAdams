import XCTest
import PatchModel
@testable import SyntaxHighlight

final class SyntaxHighlightTests: XCTestCase {

    /// `[(kind, text)]` for one line, to keep assertions readable.
    func words(_ line: String, _ language: Language, state: ScanState = .normal) -> [(TokenKind, String)] {
        var s = state
        let u = Array(line.utf16)
        return SyntaxHighlighter.tokens(line, language: language, state: &s).map { t in
            (t.kind, String(utf16CodeUnits: Array(u[t.range]), count: t.range.count))
        }
    }

    func kinds(_ line: String, _ language: Language) -> [String: TokenKind] {
        Dictionary(words(line, language).map { ($0.1, $0.0) }, uniquingKeysWith: { a, _ in a })
    }

    func testLanguageByExtension() {
        XCTAssertEqual(Language.forPath("internal/service/brew_task.go"), .go)
        XCTAssertEqual(Language.forPath("crates/glowmap/src/main.rs"), .rust)
        XCTAssertEqual(Language.forPath("src/App.vue"), .javascript)
        XCTAssertEqual(Language.forPath(".github/workflows/ci.yml"), .yaml)
        XCTAssertEqual(Language.forPath("Makefile"), .shell)
        XCTAssertEqual(Language.forPath("LICENSE"), .plain)
    }

    func testGoKeywordsTypesStringsCommentsFunctions() {
        let k = kinds(#"func (s *Service) Run(ctx context.Context, n int) error { return fmt.Errorf("bad %d", n) } // why"#, .go)
        XCTAssertEqual(k["func"], .keyword)
        XCTAssertEqual(k["Run"], .function)
        XCTAssertEqual(k["int"], .type)
        XCTAssertEqual(k["error"], .type)
        XCTAssertEqual(k["return"], .keyword)
        XCTAssertEqual(k["Errorf"], .function)
        XCTAssertEqual(k[#""bad %d""#], .string)
        XCTAssertEqual(k["// why"], .comment)
        XCTAssertNil(k["Service"], "Go capital names are exported names, not types")
        XCTAssertNil(k["s"], "a receiver is not a function name")
    }

    func testGoRawStringSpansLines() {
        let lines = ["q := `select *", "from t` + x", "y := 1"]
        let tokens = SyntaxHighlighter.tokens(lines: lines, language: .go)
        XCTAssertEqual(tokens[0].last?.kind, .string)
        XCTAssertEqual(tokens[1].first?.kind, .string)
        XCTAssertEqual(tokens[1].first?.range, 0..<7, "the string ends at the closing backtick")
        XCTAssertEqual(tokens[2].map(\.kind), [.number])
    }

    func testBlockCommentSpansLines() {
        let tokens = SyntaxHighlighter.tokens(lines: ["a /* one", "two", "three */ return"], language: .javascript)
        XCTAssertEqual(tokens[1].map(\.kind), [.comment])
        XCTAssertEqual(tokens[2].map(\.kind), [.comment, .keyword])
    }

    func testRustLifetimesMacrosAttributesAndTypes() {
        let k = kinds(#"#[derive(Clone)] pub fn glow_schema<'a>(t: &'a DataType) -> Arc<Schema> { println!("x"); }"#, .rust)
        XCTAssertEqual(k["#[derive(Clone)]"], .attribute)
        XCTAssertEqual(k["fn"], .keyword)
        XCTAssertEqual(k["glow_schema"], .function)
        XCTAssertEqual(k["'a"], .type, "a lifetime is not a char literal")
        XCTAssertEqual(k["DataType"], .type)
        XCTAssertEqual(k["println!"], .function)
    }

    func testPythonDecoratorsTripleQuotesAndConstants() {
        XCTAssertEqual(kinds("@pytest.fixture", .python)["@pytest"], .attribute)
        let tokens = SyntaxHighlighter.tokens(lines: [#"doc = """first"#, #"last""" if x is None else 3"#], language: .python)
        XCTAssertEqual(tokens[0].last?.kind, .string)
        XCTAssertEqual(tokens[1].map(\.kind), [.string, .keyword, .keyword, .constant, .keyword, .number])
    }

    func testNumbersAreNotPartOfIdentifiersOrRanges() {
        XCTAssertEqual(words("x2 = 0x1F + 1.5e-3", .python).filter { $0.0 == .number }.map(\.1), ["0x1F", "1.5e-3"])
        XCTAssertEqual(words("for i in 0..<10 {", .swift).filter { $0.0 == .number }.map(\.1), ["0", "10"])
    }

    func testYamlKeysAndCommentsButNotURLs() {
        XCTAssertEqual(kinds("  runs-on: ubuntu-latest # host", .yaml)["runs-on"], .key)
        XCTAssertEqual(kinds("  runs-on: ubuntu-latest # host", .yaml)["# host"], .comment)
        XCTAssertEqual(kinds("- name: build", .yaml)["name"], .key)
        XCTAssertNil(kinds("url: http://x", .yaml)["url: http"])
    }

    func testTomlSectionsAndKeys() {
        XCTAssertEqual(kinds("[dependencies]", .toml)["[dependencies]"], .heading)
        XCTAssertEqual(kinds(#"serde = "1.0""#, .toml)["serde"], .key)
    }

    func testJSONKeysAreKeysAndValuesAreStrings() {
        let k = kinds(#"{"name": "patch", "ok": true}"#, .json)
        XCTAssertEqual(k[#""name""#], .key)
        XCTAssertEqual(k[#""patch""#], .string)
        XCTAssertEqual(k["true"], .constant)
    }

    func testMarkdownHeadingsCodeAndLinks() {
        XCTAssertEqual(words("## Install", .markdown).map(\.0), [.heading])
        XCTAssertEqual(kinds("Run `make test` then [docs](x.md).", .markdown)["`make test`"], .string)
        XCTAssertEqual(kinds("Run `make test` then [docs](x.md).", .markdown)["[docs]"], .function)
    }

    func testShellCommentsNeedAWordBoundary() {
        XCTAssertEqual(kinds("echo $# items # count", .shell)["# count"], .comment)
        XCTAssertEqual(kinds("echo ${HOME}/x", .shell)["${HOME}"], .constant)
    }

    func testCSSPropertiesColoursAndUnits() {
        let k = kinds("  color: #ff29c7; margin: 12px 50%;", .css)
        XCTAssertEqual(k["color"], .key)
        XCTAssertEqual(k["#ff29c7"], .number)
        XCTAssertEqual(k["12px"], .number)
        XCTAssertEqual(k["50%"], .number)
    }

    func testPlainTextHasNoTokens() {
        XCTAssertTrue(words("func main() {}", .plain).isEmpty)
    }

    /// Every fixture line scans; tokens stay inside their line, never
    /// overlap, and are sorted, so the renderer can trust them.
    func testEveryFixtureLineScansToSortedInBoundsTokens() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appendingPathComponent("Fixtures/patches")
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "patch" }
        XCTAssertEqual(files.count, 19)
        var scanned = 0, colored = 0
        for url in files {
            let patch = try UnifiedDiffParser.parse(contentsOf: url)
            for change in patch.files {
                let language = Language.forPath(change.path)
                let lines = change.hunks.flatMap { $0.lines.map(\.text) }
                let tokens = SyntaxHighlighter.tokens(lines: lines, language: language)
                for (line, ts) in zip(lines, tokens) {
                    scanned += 1
                    if !ts.isEmpty { colored += 1 }
                    var last = 0
                    for t in ts {
                        XCTAssertGreaterThanOrEqual(t.range.lowerBound, last, "\(url.lastPathComponent) \(change.path): \(line)")
                        XCTAssertLessThanOrEqual(t.range.upperBound, line.utf16.count, "\(url.lastPathComponent) \(change.path): \(line)")
                        XCTAssertFalse(t.range.isEmpty)
                        last = t.range.upperBound
                    }
                }
            }
        }
        XCTAssertGreaterThan(scanned, 5_000)
        XCTAssertGreaterThan(Double(colored) / Double(scanned), 0.5, "most code lines get some colour")
    }

    func testTenThousandLinesScanQuickly() {
        let lines = (0..<10_000).map { #"func stress\#($0)(x int) string { return fmt.Sprintf("%d", x * 2) } // synthetic"# }
        let start = Date()
        let tokens = SyntaxHighlighter.tokens(lines: lines, language: .go)
        XCTAssertEqual(tokens.count, 10_000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }
}
