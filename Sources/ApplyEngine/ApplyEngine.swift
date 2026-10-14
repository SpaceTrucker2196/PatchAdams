import Foundation
import PatchModel
import BaseLoader

/// Applies a `Patch` to a base in memory (spec FR-3). Nothing is
/// written anywhere and nothing is executed. Every file gets a status
/// — clean, fuzz, failed or binary — and, when it applied, its full
/// post-patch text and a line map between base and post lines.
///
/// Hunk placement follows GNU `patch`: a hunk is looked for at its
/// declared base line plus the running offset, then at increasing
/// distances in both directions. When no exact match exists, up to
/// `maxFuzz` lines of leading and trailing context are ignored and
/// the search repeats. A hunk that still does not match fails the
/// whole file; the file keeps its raw hunks and no post text.
public enum ApplyEngine {

    public static let defaultMaxFuzz = 2

    public static func apply(_ patch: Patch, to base: any FileProvider, maxFuzz: Int = defaultMaxFuzz) -> AppliedPatch {
        AppliedPatch(files: patch.files.map { apply($0, to: base, maxFuzz: maxFuzz) })
    }

    public static func apply(_ change: FileChange, to base: any FileProvider, maxFuzz: Int = defaultMaxFuzz) -> AppliedFile {
        // Read the base file, if the change says there is one.
        var baseText: String?
        if let oldPath = change.oldPath, change.kind != .added {
            do {
                if let data = try base.contents(of: oldPath) {
                    baseText = BaseLoader.text(from: data)
                } else {
                    return AppliedFile(change: change, baseText: nil, postText: nil,
                                       status: .failed("\(oldPath) is not in the base"), lineMap: .empty, hunks: [])
                }
            } catch {
                return AppliedFile(change: change, baseText: nil, postText: nil,
                                   status: .failed("\(oldPath): \(error)"), lineMap: .empty, hunks: [])
            }
        }

        if change.isBinary {
            return AppliedFile(change: change, baseText: nil, postText: nil, status: .binary, lineMap: .empty, hunks: [])
        }

        if change.kind == .added, let newPath = change.newPath, (try? base.contents(of: newPath)) != nil {
            return AppliedFile(change: change, baseText: nil, postText: nil,
                               status: .failed("\(newPath) already exists in the base"), lineMap: .empty, hunks: [])
        }

        let baseLines = ApplyEngine.splitLines(baseText ?? "")
        let baseEndsWithNewline = baseText?.hasSuffix("\n") ?? false
        var worker = Worker(base: baseLines, maxFuzz: maxFuzz)

        for (index, hunk) in change.hunks.enumerated() {
            if let failure = worker.place(hunk, index: index) {
                return AppliedFile(change: change, baseText: baseText, postText: nil,
                                   status: .failed(failure), lineMap: .empty, hunks: worker.placements)
            }
        }
        worker.flush()

        // Trailing newline: the base's, unless a hunk at EOF changed it.
        var postEndsWithNewline = change.kind == .added ? true : baseEndsWithNewline
        for hunk in change.hunks {
            let oldLines = hunk.lines.filter { $0.kind != .added }
            let newLines = hunk.lines.filter { $0.kind != .removed }
            let oldAtEOF = oldLines.last?.noNewlineAtEnd == true
            let newAtEOF = newLines.last?.noNewlineAtEnd == true
            if newAtEOF { postEndsWithNewline = false }
            else if oldAtEOF { postEndsWithNewline = true }
        }

        let postLines = worker.post
        let postText: String?
        if change.kind == .deleted {
            postText = nil
        } else if postLines.isEmpty {
            postText = ""
        } else {
            postText = postLines.joined(separator: "\n") + (postEndsWithNewline ? "\n" : "")
        }

        let maxFuzzUsed = worker.placements.map(\.fuzz).max() ?? 0
        let status: ApplyStatus = maxFuzzUsed > 0 ? .fuzz(maxFuzzUsed) : .clean
        let lineMap = LineMap(postToBase: worker.postToBase, baseToPost: worker.baseToPost)
        return AppliedFile(change: change, baseText: baseText, postText: postText,
                           status: status, lineMap: lineMap, hunks: worker.placements)
    }

    // MARK: - Placement

    /// Walks the base once, copying untouched lines and splicing each
    /// hunk in at the position it was found.
    struct Worker {
        let base: [String]
        let maxFuzz: Int
        var post: [String] = []
        var postToBase: [Int?] = []
        var baseToPost: [Int?]
        var cursor = 0          // next base index not yet copied to post
        var offset = 0          // running line offset: found - declared
        var placements: [HunkPlacement] = []

        init(base: [String], maxFuzz: Int) {
            self.base = base
            self.maxFuzz = maxFuzz
            self.baseToPost = Array(repeating: nil, count: base.count)
        }

        /// Place one hunk. Returns a failure message, or `nil` on success.
        mutating func place(_ hunk: Hunk, index: Int) -> String? {
            let old = hunk.lines.filter { $0.kind != .added }
            // Declared 0-based base index. `-N,0` means "after line N".
            let declared = hunk.oldCount == 0 ? hunk.oldStart : hunk.oldStart - 1
            let leadingContext = hunk.lines.prefix { $0.kind == .context }.count
            let trailingContext = old.isEmpty ? 0 : hunk.lines.reversed().prefix { $0.kind == .context }.count

            for fuzz in 0...maxFuzz {
                let dropLead = min(fuzz, leadingContext)
                let dropTrail = min(fuzz, trailingContext)
                // With all context gone on both sides, the hunk matches anywhere; stop there.
                if fuzz > 0, dropLead == 0, dropTrail == 0 { break }
                let needle = old.dropFirst(dropLead).dropLast(dropTrail).map(\.text)
                let expected = declared + offset + dropLead
                if let found = search(needle, around: expected) {
                    splice(hunk, at: found, dropLead: dropLead, dropTrail: dropTrail, fuzz: fuzz, index: index)
                    return nil
                }
            }
            let where_ = hunk.oldCount == 0 ? "after base line \(hunk.oldStart)" : "at base line \(hunk.oldStart)"
            return "hunk \(index + 1) (\(where_)) does not match the base"
        }

        /// Nearest position to `expected`, not before `cursor`, where
        /// `needle` occurs in the base. An empty needle matches at the
        /// expected position when it is inside the file.
        func search(_ needle: [String], around expected: Int) -> Int? {
            let limit = base.count - needle.count
            guard limit >= cursor else { return nil }
            if needle.isEmpty {
                let p = min(max(expected, cursor), base.count)
                return p
            }
            var distance = 0
            while true {
                let fwd = expected + distance, back = expected - distance
                var any = false
                if fwd >= cursor, fwd <= limit { any = true; if matches(needle, at: fwd) { return fwd } }
                if distance > 0, back >= cursor, back <= limit { any = true; if matches(needle, at: back) { return back } }
                if !any, fwd > limit, back < cursor { return nil }
                distance += 1
            }
        }

        func matches(_ needle: [String], at position: Int) -> Bool {
            for (k, line) in needle.enumerated() where base[position + k] != line { return false }
            return true
        }

        /// Copy base lines up to `position`, then emit the hunk: context
        /// and removed lines consume base lines (dropped context is copied
        /// from the base as-is), added lines are new.
        mutating func splice(_ hunk: Hunk, at position: Int, dropLead: Int, dropTrail: Int, fuzz: Int, index: Int) {
            // `position` is where the needle starts; the hunk's declared
            // first old line sits `dropLead` lines before it.
            let hunkStart = position - dropLead
            copyBase(upTo: hunkStart)
            let postStart = post.count
            let newLineCount = hunk.lines.filter { $0.kind != .removed }.count
            for (k, line) in hunk.lines.enumerated() {
                let isLead = k < dropLead
                let isTrail = (hunk.lines.count - 1 - k) < dropTrail
                switch line.kind {
                case .context:
                    // Fuzzed context (isLead / isTrail) keeps whatever the
                    // base has here; matched context is the same line anyway.
                    if !(isLead || isTrail) || cursor < base.count { copyBase(upTo: cursor + 1) }
                case .removed:
                    baseToPost[cursor] = nil
                    cursor += 1
                case .added:
                    post.append(line.text)
                    postToBase.append(nil)
                }
            }
            placements.append(HunkPlacement(index: index, declaredOldStart: hunk.oldStart,
                                            foundOldStart: hunk.oldCount == 0 ? hunkStart : hunkStart + 1,
                                            postStart: hunk.newCount == 0 ? postStart : postStart + 1,
                                            fuzz: fuzz, newLineCount: newLineCount))
            offset = hunkStart - (hunk.oldCount == 0 ? hunk.oldStart : hunk.oldStart - 1)
        }

        mutating func copyBase(upTo end: Int) {
            while cursor < end, cursor < base.count {
                baseToPost[cursor] = post.count
                postToBase.append(cursor)
                post.append(base[cursor])
                cursor += 1
            }
        }

        mutating func flush() { copyBase(upTo: base.count) }
    }
}

extension ApplyEngine {
    /// Split on `\n`; a final newline does not produce a trailing empty
    /// line. Same rule as `DiffEngine.splitLines` — duplicated, not
    /// imported, because ApplyEngine depends on PatchModel and
    /// BaseLoader only (Package.swift).
    public static func splitLines(_ text: String) -> [String] {
        if text.isEmpty { return [] }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if text.hasSuffix("\n") { lines.removeLast() }
        return lines
    }
}
