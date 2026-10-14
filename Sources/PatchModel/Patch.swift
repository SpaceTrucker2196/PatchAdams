import Foundation

/// One unified diff: `git diff` or `git format-patch` output.
/// Also called an implementation. The label (A, B, C, D) and the
/// source file name belong to the session, not the patch.
public struct Patch: Sendable, Hashable, Codable {
    /// Mail header fields when the input was `git format-patch` output.
    public var mailHeader: MailHeader?
    public var files: [FileChange]

    public init(mailHeader: MailHeader? = nil, files: [FileChange]) {
        self.mailHeader = mailHeader
        self.files = files
    }

    /// Total added and removed lines across every file.
    public var lineCounts: (added: Int, removed: Int) {
        files.reduce(into: (0, 0)) { acc, file in
            let c = file.lineCounts
            acc.0 += c.added
            acc.1 += c.removed
        }
    }
}

/// The `From:` / `Subject:` / `Date:` block that `git format-patch`
/// puts above the first `diff --git` line.
public struct MailHeader: Sendable, Hashable, Codable {
    public var from: String?
    public var subject: String?
    public var date: String?
    /// Commit message body between the headers and the first diff.
    public var body: String

    public init(from: String? = nil, subject: String? = nil, date: String? = nil, body: String = "") {
        self.from = from
        self.subject = subject
        self.date = date
        self.body = body
    }
}

/// One file touched by a patch.
public struct FileChange: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Codable {
        case modified, added, deleted, renamed, copied
    }

    /// Path before the patch, without the `a/` prefix. `nil` when added.
    public var oldPath: String?
    /// Path after the patch, without the `b/` prefix. `nil` when deleted.
    public var newPath: String?
    public var kind: Kind
    public var oldMode: String?
    public var newMode: String?
    /// `similarity index N%` for renames and copies.
    public var similarity: Int?
    /// `Binary files ... differ` or `GIT binary patch`. Hunks are empty.
    public var isBinary: Bool
    public var hunks: [Hunk]

    public init(oldPath: String?, newPath: String?, kind: Kind,
                oldMode: String? = nil, newMode: String? = nil,
                similarity: Int? = nil, isBinary: Bool = false, hunks: [Hunk] = []) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.kind = kind
        self.oldMode = oldMode
        self.newMode = newMode
        self.similarity = similarity
        self.isBinary = isBinary
        self.hunks = hunks
    }

    /// The path the file has after the patch, or before it when deleted.
    public var path: String { newPath ?? oldPath ?? "" }

    /// The file name only, as the reference format uses it:
    /// `downloader.go L50:L62`, never the repository path.
    public var fileName: String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    /// True when the file sits in a test directory or carries a test
    /// name. Drives the file tree's tests-only filter.
    public var isTest: Bool {
        let p = path.lowercased()
        let name = fileName.lowercased()
        return p.hasPrefix("test/") || p.hasPrefix("tests/")
            || p.contains("/test/") || p.contains("/tests/")
            || p.contains("/__tests__/") || p.contains("/spec/")
            || name.hasPrefix("test_") || name.hasSuffix("_test.go")
            || name.hasSuffix("_test.py") || name.hasSuffix("tests.swift")
            || name.contains(".test.") || name.contains(".spec.")
            || name.hasSuffix("test.rs") || name.hasSuffix("_test.zig")
    }

    public var lineCounts: (added: Int, removed: Int) {
        hunks.reduce(into: (0, 0)) { acc, hunk in
            for line in hunk.lines {
                switch line.kind {
                case .added: acc.0 += 1
                case .removed: acc.1 += 1
                case .context: break
                }
            }
        }
    }
}

/// One contiguous change, as the diff format has it.
public struct Hunk: Sendable, Hashable, Codable {
    public var oldStart: Int
    public var oldCount: Int
    public var newStart: Int
    public var newCount: Int
    /// The text after the second `@@`, usually the enclosing function.
    public var sectionHeading: String?
    public var lines: [Line]

    public init(oldStart: Int, oldCount: Int, newStart: Int, newCount: Int,
                sectionHeading: String? = nil, lines: [Line] = []) {
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.sectionHeading = sectionHeading
        self.lines = lines
    }

    /// Base range of this hunk as `Lstart:Lend` (inclusive). Empty
    /// ranges (pure insertions) report `Lstart:Lstart-1`.
    public var oldRange: ClosedRange<Int>? {
        oldCount == 0 ? nil : oldStart...(oldStart + oldCount - 1)
    }

    public var newRange: ClosedRange<Int>? {
        newCount == 0 ? nil : newStart...(newStart + newCount - 1)
    }

    /// Every line with its base and post-patch line numbers filled in.
    /// Removed lines have no post number; added lines have no base number.
    public var numberedLines: [NumberedLine] {
        var old = oldStart
        var new = newStart
        var out: [NumberedLine] = []
        out.reserveCapacity(lines.count)
        for line in lines {
            switch line.kind {
            case .context:
                out.append(NumberedLine(line: line, oldNumber: old, newNumber: new))
                old += 1; new += 1
            case .removed:
                out.append(NumberedLine(line: line, oldNumber: old, newNumber: nil))
                old += 1
            case .added:
                out.append(NumberedLine(line: line, oldNumber: nil, newNumber: new))
                new += 1
            }
        }
        return out
    }
}

public struct NumberedLine: Sendable, Hashable {
    public var line: Line
    public var oldNumber: Int?
    public var newNumber: Int?
}

/// One line of a hunk.
public struct Line: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Codable {
        case context, added, removed
    }

    public var kind: Kind
    /// The line text without its leading marker and without a newline.
    public var text: String
    /// Set when the diff carried `\ No newline at end of file` after this line.
    public var noNewlineAtEnd: Bool

    public init(kind: Kind, text: String, noNewlineAtEnd: Bool = false) {
        self.kind = kind
        self.text = text
        self.noNewlineAtEnd = noNewlineAtEnd
    }
}
