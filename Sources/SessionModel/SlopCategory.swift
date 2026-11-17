import Foundation

/// One slop category (DECISIONS.md D3, issue #38): the name the session
/// stores, the slug a review tool writes, and a one-line summary for
/// the picker. `name` is the string older session files carry.
public struct SlopCategory: Sendable, Hashable {
    public var name: String
    public var slug: String
    public var summary: String

    public init(name: String, slug: String, summary: String) {
        self.name = name
        self.slug = slug
        self.summary = summary
    }

    public static let all: [SlopCategory] = [
        SlopCategory(name: "unnecessary helpers", slug: "unnecessary_helpers",
                     summary: "Extra functions that only pass through to other functions or add a step without improving understanding or reuse."),
        SlopCategory(name: "excessive defensiveness", slug: "excessive_defensiveness",
                     summary: "Checks, fallbacks, or error handling for cases already ruled out or handled elsewhere, including hiding errors callers need to see."),
        SlopCategory(name: "unnecessary machinery or repeated work", slug: "unnecessary_machinery_or_repeated_work",
                     summary: "Retries, locks, caches, background workers, or repeated calculations without a concrete need."),
        SlopCategory(name: "duplicated logic or state", slug: "duplicated_logic_or_state",
                     summary: "Reimplementing existing behavior, keeping multiple copies of the same information, or storing directly derivable values."),
        SlopCategory(name: "too many branches", slug: "too_many_branches",
                     summary: "Repeated checks, unnecessary nesting, or special cases that can be simplified while preserving behavior."),
        SlopCategory(name: "unclear code", slug: "unclear_code",
                     summary: "Code that is needlessly hard to follow: dense expressions, deeply nested logic, unexplained numbers or positions, or hand-written code packed into strings. Use unhelpful comments or names when names or comments are the whole issue."),
        SlopCategory(name: "unhelpful comments or names", slug: "unhelpful_comments_or_names",
                     summary: "Comments that restate obvious code, or names that are vague, overly complicated, or obscure what the code does."),
        SlopCategory(name: "code in the wrong place", slug: "code_in_wrong_place",
                     summary: "Putting a rule in the wrong component, or making callers repeat work that belongs in the underlying component."),
        SlopCategory(name: "unneeded backwards compatibility", slug: "unneeded_backwards_compatibility",
                     summary: "Old paths, wrappers, or feature flags that no actual requirement or supported caller needs."),
        SlopCategory(name: "dead or unrelated code", slug: "dead_or_unrelated_code",
                     summary: "Unused code or state, or edits outside what the task requires."),
        SlopCategory(name: "premature extensibility", slug: "premature_extensibility",
                     summary: "Frameworks, plugins, options, or extra modes for hypothetical future needs when there is only one real use case."),
        SlopCategory(name: "low-value tests", slug: "low_value_tests",
                     summary: "Tests that add little useful coverage or break after harmless implementation changes: weak assertions, excessive mocking, checks tied to internal details, repeated tests for the same behavior."),
        SlopCategory(name: "other", slug: "other",
                     summary: "Only when no listed category fits. Propose a category name and explain the gap."),
    ]

    /// The summary of the category called `name` (by name or slug), or nil
    /// for one the reviewer added to the session.
    public static func summary(of name: String) -> String? {
        let key = key(name)
        return all.first { self.key($0.name) == key || self.key($0.slug) == key }?.summary
    }

    /// How a name, a slug and a heading compare: lower case, `_` and `-`
    /// as spaces, one space between words.
    static func key(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "[_\\-]", with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// One finding read out of a paste: its category when a heading named
/// one, else nil for the picker's.
public struct PastedFinding: Sendable, Hashable {
    public var category: String?
    public var text: String

    public init(category: String?, text: String) {
        self.category = category
        self.text = text
    }
}

/// One run of a paste under a category heading, or before the first
/// one (`category` nil); `range` is UTF-16 in the original text, the
/// heading itself left out.
public struct CategorySection: Sendable, Hashable {
    public var category: String?
    public var range: NSRange

    public init(category: String?, range: NSRange) {
        self.category = category
        self.range = range
    }
}

/// A line that opens with a short label and a colon — "Unneeded
/// Backwards Compatibility: …", "unneeded_backwards_compatibility: …",
/// "- **Too many branches**: …", "Bad Tests: …" — names a category and
/// starts a finding (issues #38, #42). A label that is a known category,
/// by name or slug, gives that category; any other label of up to five
/// words is a category of its own. Not labels: file references, URLs,
/// and patch names ("Implementation A:"). Text before the first heading
/// is a finding of its own with no category; a paste with no heading is
/// one finding.
public enum CategoryHeadings {
    private static let heading = try! NSRegularExpression(pattern:
        #"^\s*(?:[-*+#>]+\s*)?[*_]{0,2}\s*(?<name>[A-Za-z][A-Za-z _\-]*?)\s*[*_]{0,2}\s*:(?:\s+(?<rest>.*)|(?<empty>))$"#)
    private static let patchName = try! NSRegularExpression(pattern:
        #"^(?:implementation|patch|column|version|solution|response|candidate)\b"#, options: [.caseInsensitive])

    /// The category a heading label names: a known one, else the label
    /// itself in the list's lower-case style; nil when the label is not a
    /// heading (too long, or a patch name).
    static func category(for label: String, known: [String: String], slugs: [String: String]) -> String? {
        let key = SlopCategory.key(label)
        if let name = known[key] ?? slugs[key].flatMap({ known[SlopCategory.key($0)] }) { return name }
        let words = key.split(separator: " ")
        guard (1...5).contains(words.count), key.count <= 48,
              patchName.firstMatch(in: key, range: NSRange(location: 0, length: (key as NSString).length)) == nil else { return nil }
        return label.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// The text cut at its headings, each piece with where it is.
    public static func sections(_ text: String, categories: [String]) -> [CategorySection] {
        let known = Dictionary(categories.map { (SlopCategory.key($0), $0) }, uniquingKeysWith: { first, _ in first })
        let slugs = Dictionary(SlopCategory.all.map { (SlopCategory.key($0.slug), $0.name) }, uniquingKeysWith: { first, _ in first })
        let ns = text as NSString
        var out: [CategorySection] = []
        var current = CategorySection(category: nil, range: NSRange(location: 0, length: 0))
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { line, lineRange, enclosing, _ in
            if let line, let match = heading.firstMatch(in: line, range: NSRange(location: 0, length: lineRange.length)),
               let name = category(for: (line as NSString).substring(with: match.range(withName: "name")), known: known, slugs: slugs) {
                if current.category != nil || current.range.length > 0 { out.append(current) }
                let rest = match.range(withName: "rest")
                let start = rest.location == NSNotFound ? NSMaxRange(lineRange) : lineRange.location + rest.location
                current = CategorySection(category: name, range: NSRange(location: start, length: NSMaxRange(enclosing) - start))
                return
            }
            current.range.length = NSMaxRange(enclosing) - current.range.location
        }
        if current.category != nil || current.range.length > 0 { out.append(current) }
        return out
    }

    public static func split(_ text: String, categories: [String]) -> [PastedFinding] {
        let ns = text as NSString
        return sections(text, categories: categories).compactMap { section in
            let body = ns.substring(with: section.range).trimmingCharacters(in: .whitespacesAndNewlines)
            return body.isEmpty ? nil : PastedFinding(category: section.category, text: body)
        }
    }
}
