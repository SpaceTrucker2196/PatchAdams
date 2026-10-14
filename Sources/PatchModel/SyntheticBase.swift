import Foundation

/// A base file reconstructed from a patch's own hunks.
///
/// The fixture patches arrived without their base revisions
/// (issue #6). For every file a patch modifies, renames, copies or
/// deletes, its hunks already carry the base text of every context
/// and removed line at a known base line number. `SyntheticBase`
/// lays those lines out at those numbers and fills the gaps between
/// hunks with a filler line, so the result is a file every hunk
/// applies to at its declared offset — the oracle for the Phase 1
/// apply gate (ROADMAP.md M1, DECISIONS.md D4).
///
/// What the synthetic base is not: the real file. Lines outside any
/// hunk are filler, and the file ends at the last hunk's last base
/// line because nothing after it is known. Added files have no base
/// and binary files have no hunks, so neither produces a file.
public struct SyntheticBaseFile: Sendable, Hashable {
    /// Path before the patch (`FileChange.oldPath`).
    public var path: String
    /// Full base text, trailing newline included unless the patch
    /// marked the last base line `\ No newline at end of file`.
    public var text: String

    public init(path: String, text: String) {
        self.path = path
        self.text = text
    }
}

public struct SyntheticBaseError: Error, CustomStringConvertible, Sendable, Hashable {
    public var path: String
    public var message: String

    public var description: String { "\(path): \(message)" }
}

public enum SyntheticBase {

    /// The line that stands in for base line `number` when no hunk
    /// covers it. Deliberately unlike any source language, so it can
    /// never match real context by accident.
    public static func filler(line number: Int) -> String {
        "~ synthetic base line \(number) ~"
    }

    /// One synthetic base file per non-added, non-binary file in
    /// `patch`, in patch order. Throws when a file's hunks overlap or
    /// run backwards, or when two files claim the same base path —
    /// either means the patch cannot describe a single base.
    public static func files(for patch: Patch) throws -> [SyntheticBaseFile] {
        var out: [SyntheticBaseFile] = []
        var seen: Set<String> = []
        for file in patch.files {
            guard let base = try self.file(for: file) else { continue }
            guard seen.insert(base.path).inserted else {
                throw SyntheticBaseError(path: base.path, message: "two files in the patch share this base path")
            }
            out.append(base)
        }
        return out
    }

    /// The synthetic base of one file, or `nil` when the file has no
    /// base (added) or no text hunks (binary).
    public static func file(for change: FileChange) throws -> SyntheticBaseFile? {
        if change.kind == .added || change.isBinary { return nil }
        guard let path = change.oldPath, !path.isEmpty else {
            throw SyntheticBaseError(path: change.path, message: "\(change.kind.rawValue) file has no base path")
        }

        var lines: [String] = []
        var next = 1                 // the next base line number to emit
        var lastLineHasNoNewline = false

        for (index, hunk) in change.hunks.enumerated() where hunk.oldCount > 0 {
            guard hunk.oldStart >= next else {
                throw SyntheticBaseError(path: path, message: "hunk \(index + 1) starts at base line \(hunk.oldStart) but line \(next - 1) is already covered")
            }
            while next < hunk.oldStart {
                lines.append(filler(line: next))
                next += 1
            }
            for line in hunk.lines where line.kind != .added {
                lines.append(line.text)
                lastLineHasNoNewline = line.noNewlineAtEnd
            }
            next = hunk.oldStart + hunk.oldCount
        }

        if lines.isEmpty { return SyntheticBaseFile(path: path, text: "") }
        let text = lines.joined(separator: "\n") + (lastLineHasNoNewline ? "" : "\n")
        return SyntheticBaseFile(path: path, text: text)
    }
}
