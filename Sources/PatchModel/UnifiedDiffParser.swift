import Foundation

/// Why a patch could not be parsed. Carries the 1-based line number
/// of the input so the UI can show it next to the raw text.
public struct PatchParseError: Error, Sendable, Hashable, CustomStringConvertible {
    public var line: Int
    public var message: String

    public init(line: Int, message: String) {
        self.line = line
        self.message = message
    }

    public var description: String { "line \(line): \(message)" }
}

/// Parses `git diff` and `git format-patch` output.
///
/// Strict about hunk line counts: a hunk whose body does not match its
/// `@@` header is an error, not a guess. A parser that silently accepts
/// a truncated patch would hide a change from the reviewer
/// (docs/spec.md, risk "Reviewer trusts the app's diff over the raw patch").
public enum UnifiedDiffParser {

    public static func parse(_ text: String) throws -> Patch {
        var parser = Parser(lines: text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
        return try parser.run()
    }

    public static func parse(contentsOf url: URL) throws -> Patch {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw PatchParseError(line: 0, message: "file is not text")
        }
        return try parse(text)
    }

    // MARK: - Implementation

    private struct Parser {
        let lines: [String]
        var index = 0

        init(lines: [String]) {
            // A trailing newline yields one empty trailing element; drop it
            // so "end of input" means end of input.
            if lines.last == "" {
                self.lines = Array(lines.dropLast())
            } else {
                self.lines = lines
            }
        }

        var atEnd: Bool { index >= lines.count }
        var current: String { lines[index] }
        var lineNumber: Int { index + 1 }

        mutating func run() throws -> Patch {
            let mailHeader = parseMailHeader()
            var files: [FileChange] = []
            while !atEnd {
                if current.hasPrefix("diff --git ") {
                    files.append(try parseFile())
                } else if current.hasPrefix("--- ") && lines.indices.contains(index + 1)
                            && lines[index + 1].hasPrefix("+++ ") {
                    // Plain `diff -u` output without a `diff --git` line.
                    files.append(try parseFile())
                } else if current == "-- " || current.hasPrefix("-- \n") {
                    // format-patch signature; everything after is the git version.
                    break
                } else {
                    // Prose between files (format-patch stat block, etc.).
                    index += 1
                }
            }
            if files.isEmpty {
                throw PatchParseError(line: 1, message: "no `diff --git` or `---`/`+++` header found")
            }
            return Patch(mailHeader: mailHeader, files: files)
        }

        /// `git format-patch` output starts with `From <sha> Mon Sep 17 00:00:00 2001`.
        mutating func parseMailHeader() -> MailHeader? {
            guard !atEnd, current.hasPrefix("From "), current.count > 45,
                  current.dropFirst(5).prefix(40).allSatisfy(\.isHexDigit) else {
                return nil
            }
            index += 1
            var header = MailHeader()
            // RFC 822 headers until a blank line. Continuation lines start with whitespace.
            var lastKey: String?
            while !atEnd, !current.isEmpty {
                if let first = current.first, first == " " || first == "\t", let key = lastKey {
                    let more = current.trimmingCharacters(in: .whitespaces)
                    switch key {
                    case "subject": header.subject = (header.subject ?? "") + " " + more
                    case "from": header.from = (header.from ?? "") + " " + more
                    default: break
                    }
                } else if let colon = current.firstIndex(of: ":") {
                    let key = current[..<colon].lowercased()
                    let value = current[current.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    lastKey = key
                    switch key {
                    case "from": header.from = value
                    case "subject": header.subject = value
                    case "date": header.date = value
                    default: break
                    }
                }
                index += 1
            }
            // Body until the first diff header or the `---` separator that
            // format-patch puts before the diffstat.
            var body: [String] = []
            while !atEnd, !current.hasPrefix("diff --git "), current != "---" {
                body.append(current)
                index += 1
            }
            if !atEnd, current == "---" { index += 1 }
            header.body = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return header
        }

        mutating func parseFile() throws -> FileChange {
            var oldPath: String?
            var newPath: String?
            var kind = FileChange.Kind.modified
            var oldMode: String?
            var newMode: String?
            var similarity: Int?
            var isBinary = false
            var sawPathLines = false

            if current.hasPrefix("diff --git ") {
                let (a, b) = Self.splitGitPaths(String(current.dropFirst("diff --git ".count)))
                oldPath = a
                newPath = b
                index += 1
            }

            // Extended headers.
            headers: while !atEnd {
                let line = current
                if line.hasPrefix("old mode ") {
                    oldMode = String(line.dropFirst("old mode ".count))
                } else if line.hasPrefix("new mode ") {
                    newMode = String(line.dropFirst("new mode ".count))
                } else if line.hasPrefix("deleted file mode ") {
                    kind = .deleted
                    oldMode = String(line.dropFirst("deleted file mode ".count))
                } else if line.hasPrefix("new file mode ") {
                    kind = .added
                    newMode = String(line.dropFirst("new file mode ".count))
                } else if line.hasPrefix("rename from ") {
                    kind = .renamed
                    oldPath = String(line.dropFirst("rename from ".count))
                } else if line.hasPrefix("rename to ") {
                    kind = .renamed
                    newPath = String(line.dropFirst("rename to ".count))
                } else if line.hasPrefix("copy from ") {
                    kind = .copied
                    oldPath = String(line.dropFirst("copy from ".count))
                } else if line.hasPrefix("copy to ") {
                    kind = .copied
                    newPath = String(line.dropFirst("copy to ".count))
                } else if line.hasPrefix("similarity index ") || line.hasPrefix("dissimilarity index ") {
                    let digits = line.split(separator: " ").last?.filter(\.isNumber) ?? ""
                    similarity = Int(digits)
                } else if line.hasPrefix("index ") {
                    // index <old>..<new>[ <mode>]
                    if let mode = line.split(separator: " ").dropFirst(2).first { oldMode = oldMode ?? String(mode); newMode = newMode ?? String(mode) }
                } else if line.hasPrefix("Binary files ") || line == "GIT binary patch" {
                    isBinary = true
                    index += 1
                    // Skip the binary payload up to the next file.
                    while !atEnd, !current.hasPrefix("diff --git ") { index += 1 }
                    break headers
                } else if line.hasPrefix("--- ") {
                    oldPath = Self.stripPrefix(Self.pathPart(of: line)) ?? oldPath
                    if Self.pathPart(of: line) == "/dev/null" { oldPath = nil; if kind == .modified { kind = .added } }
                    index += 1
                    guard !atEnd, current.hasPrefix("+++ ") else {
                        throw PatchParseError(line: lineNumber, message: "expected `+++` after `---`")
                    }
                    newPath = Self.stripPrefix(Self.pathPart(of: current)) ?? newPath
                    if Self.pathPart(of: current) == "/dev/null" { newPath = nil; if kind == .modified { kind = .deleted } }
                    sawPathLines = true
                    index += 1
                    break headers
                } else if line.hasPrefix("diff --git ") || line.hasPrefix("@@ ") || line == "-- " {
                    break headers
                }
                // Unknown header lines (e.g. `mode change`) are skipped.
                index += 1
            }

            var hunks: [Hunk] = []
            if sawPathLines {
                while !atEnd, current.hasPrefix("@@ ") {
                    hunks.append(try parseHunk())
                }
            }
            if kind == .added { oldPath = nil }
            if kind == .deleted { newPath = nil }
            return FileChange(oldPath: oldPath, newPath: newPath, kind: kind,
                              oldMode: oldMode, newMode: newMode,
                              similarity: similarity, isBinary: isBinary, hunks: hunks)
        }

        mutating func parseHunk() throws -> Hunk {
            let headerLineNumber = lineNumber
            let header = current
            // @@ -a[,b] +c[,d] @@[ heading]
            guard header.hasPrefix("@@ "),
                  let close = header.range(of: " @@", range: header.index(header.startIndex, offsetBy: 3)..<header.endIndex) else {
                throw PatchParseError(line: headerLineNumber, message: "malformed hunk header: \(header)")
            }
            let ranges = header[header.index(header.startIndex, offsetBy: 3)..<close.lowerBound]
                .split(separator: " ")
            guard ranges.count == 2,
                  let old = Self.parseRange(ranges[0], sign: "-"),
                  let new = Self.parseRange(ranges[1], sign: "+") else {
                throw PatchParseError(line: headerLineNumber, message: "malformed hunk ranges: \(header)")
            }
            let headingText = header[close.upperBound...].trimmingCharacters(in: .whitespaces)
            let heading = headingText.isEmpty ? nil : headingText
            index += 1

            var lines: [Line] = []
            var oldLeft = old.count
            var newLeft = new.count
            while (oldLeft > 0 || newLeft > 0) {
                guard !atEnd else {
                    throw PatchParseError(line: lineNumber, message: "hunk at line \(headerLineNumber) ends early: \(oldLeft) old / \(newLeft) new lines missing")
                }
                let raw = current
                if raw.hasPrefix("\\") {
                    // "\ No newline at end of file" applies to the previous line.
                    if !lines.isEmpty { lines[lines.count - 1].noNewlineAtEnd = true }
                    index += 1
                    continue
                }
                let marker = raw.first
                let text = raw.isEmpty ? "" : String(raw.dropFirst())
                switch marker {
                case " ":
                    lines.append(Line(kind: .context, text: text)); oldLeft -= 1; newLeft -= 1
                case nil:
                    // An empty context line whose leading space was stripped by a mailer.
                    lines.append(Line(kind: .context, text: "")); oldLeft -= 1; newLeft -= 1
                case "+":
                    lines.append(Line(kind: .added, text: text)); newLeft -= 1
                case "-":
                    lines.append(Line(kind: .removed, text: text)); oldLeft -= 1
                default:
                    throw PatchParseError(line: lineNumber, message: "unexpected line in hunk: \(raw.prefix(40))")
                }
                if oldLeft < 0 || newLeft < 0 {
                    throw PatchParseError(line: lineNumber, message: "hunk at line \(headerLineNumber) has more lines than its header declares")
                }
                index += 1
            }
            // A trailing "\ No newline" after the last counted line.
            if !atEnd, current.hasPrefix("\\") {
                if !lines.isEmpty { lines[lines.count - 1].noNewlineAtEnd = true }
                index += 1
            }
            return Hunk(oldStart: old.start, oldCount: old.count,
                        newStart: new.start, newCount: new.count,
                        sectionHeading: heading, lines: lines)
        }

        // MARK: helpers

        static func parseRange(_ s: Substring, sign: Character) -> (start: Int, count: Int)? {
            guard s.first == sign else { return nil }
            let body = s.dropFirst()
            let parts = body.split(separator: ",", maxSplits: 1)
            guard let start = Int(parts[0]) else { return nil }
            let count = parts.count == 2 ? Int(parts[1]) : 1
            guard let c = count else { return nil }
            return (start, c)
        }

        /// The path on a `---` / `+++` line, before any tab-separated timestamp.
        static func pathPart(of line: String) -> String {
            let rest = line.dropFirst(4)
            if let tab = rest.firstIndex(of: "\t") { return String(rest[..<tab]) }
            return String(rest)
        }

        static func stripPrefix(_ path: String) -> String? {
            if path == "/dev/null" { return nil }
            var p = path
            if p.hasPrefix("\"") && p.hasSuffix("\"") && p.count >= 2 { p = String(p.dropFirst().dropLast()) }
            if p.hasPrefix("a/") || p.hasPrefix("b/") { return String(p.dropFirst(2)) }
            return p
        }

        /// Split the `a/X b/Y` tail of a `diff --git` line. Quoted paths are
        /// unambiguous; unquoted ones are split where the halves agree, or at
        /// the first ` b/` when they cannot (renames with spaces — the
        /// `rename from/to` headers that follow set the real paths).
        static func splitGitPaths(_ tail: String) -> (String?, String?) {
            if tail.hasPrefix("\"") {
                var parts: [String] = []
                var cur = ""
                var inQuote = false
                var escape = false
                for ch in tail {
                    if escape { cur.append(ch); escape = false; continue }
                    if ch == "\\" && inQuote { escape = true; continue }
                    if ch == "\"" { inQuote.toggle(); continue }
                    if ch == " " && !inQuote { if !cur.isEmpty { parts.append(cur); cur = "" }; continue }
                    cur.append(ch)
                }
                if !cur.isEmpty { parts.append(cur) }
                guard parts.count == 2 else { return (nil, nil) }
                return (stripPrefix(parts[0]), stripPrefix(parts[1]))
            }
            // Try the symmetric split: "a/P b/P".
            let n = tail.count
            if n % 2 == 1 {
                let mid = tail.index(tail.startIndex, offsetBy: n / 2)
                if tail[mid] == " " {
                    let a = String(tail[..<mid]), b = String(tail[tail.index(after: mid)...])
                    if a.hasPrefix("a/") && b.hasPrefix("b/") && a.dropFirst(2) == b.dropFirst(2) {
                        return (stripPrefix(a), stripPrefix(b))
                    }
                }
            }
            if let r = tail.range(of: " b/") {
                return (stripPrefix(String(tail[..<r.lowerBound])), stripPrefix(String(tail[r.upperBound...].dropFirst(0)).withBPrefix))
            }
            return (nil, nil)
        }
    }
}

private extension String {
    var withBPrefix: String { "b/" + self }
}
