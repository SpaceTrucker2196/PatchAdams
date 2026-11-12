import Foundation

/// One line reference found in pasted finding text: `L100` is line
/// 100, `L100-L110` the range 100…110, a leading `-L` the removed
/// (base) side — the same words the reference format writes.
public struct Evidence: Sendable, Hashable {
    /// The file name as written in the text, path parts included.
    public var fileName: String
    public var start: Int
    public var end: Int
    public var removedSide: Bool
    /// The patch the evidence is in, when the text names one before the
    /// file — `(B main.go L5)` — to compare with another implementation
    /// (issue #28). `nil` means the finding's own patch.
    public var label: String?

    public init(fileName: String, start: Int, end: Int, removedSide: Bool = false, label: String? = nil) {
        self.fileName = fileName
        self.start = start
        self.end = end
        self.removedSide = removedSide
        self.label = label
    }

    /// `name L100:L110`, the reference format the app generates, with
    /// the patch letter first when the evidence names one.
    public var reference: String {
        "\(label.map { "\($0) " } ?? "")\((fileName as NSString).lastPathComponent) \(removedSide ? "-" : "")L\(start):L\(end)"
    }
}

/// Reads the evidence out of a pasted finding. A file name is a word
/// with a source extension; every line reference after it refers to
/// that file until the next file name. A reference before any file
/// name has nothing to refer to and is dropped.
public enum EvidenceParser {
    /// Extensions that make a word a file name. Fixed, so "e.g." or a
    /// version number like "1.2" in prose never starts a new file.
    public static let sourceExtensions: Set<String> = [
        "go", "rs", "py", "pyi", "swift", "zig", "js", "mjs", "cjs", "jsx", "ts", "tsx", "vue",
        "java", "kt", "kts", "scala", "dart", "cs", "c", "h", "cc", "cpp", "cxx", "hpp", "hh",
        "m", "mm", "sh", "bash", "zsh", "fish", "mk", "yml", "yaml", "toml", "ini", "cfg",
        "json", "jsonc", "md", "markdown", "css", "scss", "less", "html", "sql", "proto",
        "rb", "php", "lua", "ex", "exs", "erl", "hs", "ml", "clj", "r", "pl", "txt", "xml", "mod", "sum",
    ]

    // A file name — after an optional patch letter, `(B main.go …)` —
    // or a line reference: optional `-` (removed side,
    // only when not glued to a word), `L` and a number (`L 759` too),
    // then an optional `-`, `–` or `:` and the end, with or without its `L`.
    private static let pattern = try! NSRegularExpression(pattern:
        #"(?:(?<![\w-])(?<label>[A-D1-4])[ \t]+)?(?<file>(?<![\w./-])[\w./-]*\w\.(?<ext>[A-Za-z][A-Za-z0-9]{0,9})(?![\w]))"#
        + #"|(?<ref>(?<![\w-])(?<minus>-)?L ?(?<start>\d+)(?:\s*[-–:]\s*(?:L ?)?(?<end>\d+))?(?!\w))"#)

    // "Implementation A", "Patch B", "Column 2": which patch the text is about.
    private static let labelPattern = try! NSRegularExpression(pattern:
        #"\b(?:implementation|patch|column|version|solution|response|candidate)\s+([A-D1-4])\b"#, options: [.caseInsensitive])

    /// The patch label the text names first ("Implementation A" → `A`,
    /// "Patch 2" → `2`), or `nil`. The letter must be a capital, so
    /// "patch a file" is not read as patch A.
    public static func patchLabel(in text: String) -> String? {
        let ns = text as NSString
        for match in labelPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let label = ns.substring(with: match.range(at: 1))
            if label == label.uppercased() { return label }
        }
        return nil
    }

    public static func parse(_ text: String) -> [Evidence] { parseWithSources(text).map(\.evidence) }

    /// Each piece of evidence with where it is written in `text` (UTF-16,
    /// as `NSRange`): the line reference, reaching back over its file
    /// name when it is the first reference after that name (issue #31).
    public static func parseWithSources(_ text: String) -> [(evidence: Evidence, source: NSRange)] {
        let ns = text as NSString
        var file: String?
        var fileRange: NSRange?   // the file name not yet claimed by a reference
        var label: String?   // the patch letter written with the current file, if any
        var out: [(evidence: Evidence, source: NSRange)] = []
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            func group(_ name: String) -> String? {
                let r = match.range(withName: name)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            if let name = group("file"), let ext = group("ext") {
                if sourceExtensions.contains(ext.lowercased()) { file = name; label = group("label"); fileRange = match.range }
            } else if let file, let start = group("start").flatMap({ Int($0) }) {
                let end = group("end").flatMap { Int($0) } ?? start
                let reference = match.range(withName: "ref")
                let source = fileRange.map { NSUnionRange($0, reference) } ?? reference
                fileRange = nil
                out.append((Evidence(fileName: file, start: min(start, end), end: max(start, end), removedSide: group("minus") != nil, label: label), source))
            }
        }
        return out
    }
}
