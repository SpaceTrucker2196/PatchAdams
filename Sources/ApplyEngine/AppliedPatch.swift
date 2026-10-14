import Foundation
import PatchModel

/// One patch applied to the base: every file with its status, text
/// and line map, plus the per-patch report (spec FR-3).
public struct AppliedPatch: Sendable, Hashable {
    public var files: [AppliedFile]

    public init(files: [AppliedFile]) { self.files = files }

    public var report: ApplyReport { ApplyReport(files: files) }

    public func file(at path: String) -> AppliedFile? {
        files.first { $0.change.path == path }
    }
}

public enum ApplyStatus: Sendable, Hashable {
    /// Every hunk matched at its declared place or at an offset.
    case clean
    /// At least one hunk needed context ignored; the payload is the
    /// largest fuzz used.
    case fuzz(Int)
    /// A hunk did not match; no post text. The file keeps its raw hunks.
    case failed(String)
    /// Binary change: nothing to apply, nothing to show but a stub.
    case binary

    public var label: String {
        switch self {
        case .clean: return "clean"
        case .fuzz(let n): return "fuzz \(n)"
        case .failed: return "failed"
        case .binary: return "binary"
        }
    }

    public var isFailure: Bool { if case .failed = self { return true } else { return false } }
}

/// One file after apply. `baseText` and `postText` are the full texts
/// the columns render; they are shared by value and never copied per
/// view (AGENTS.md).
public struct AppliedFile: Sendable, Hashable {
    public var change: FileChange
    /// Full base text; `nil` for added files, binaries, and files the
    /// base does not have.
    public var baseText: String?
    /// Full post-patch text; `nil` when deleted, failed, or binary.
    public var postText: String?
    public var status: ApplyStatus
    public var lineMap: LineMap
    /// Where each hunk landed, in hunk order; stops at the failing
    /// hunk when the file failed.
    public var hunks: [HunkPlacement]

    public init(change: FileChange, baseText: String?, postText: String?,
                status: ApplyStatus, lineMap: LineMap, hunks: [HunkPlacement]) {
        self.change = change
        self.baseText = baseText
        self.postText = postText
        self.status = status
        self.lineMap = lineMap
        self.hunks = hunks
    }

    public var path: String { change.path }
}

/// Where a hunk was applied. Line numbers are 1-based; `foundOldStart`
/// and `postStart` are `oldStart`-style: the first line of the range,
/// or the line before an empty range.
public struct HunkPlacement: Sendable, Hashable {
    public var index: Int
    public var declaredOldStart: Int
    public var foundOldStart: Int
    public var postStart: Int
    public var fuzz: Int
    public var newLineCount: Int

    public var offset: Int { foundOldStart - declaredOldStart }
}

/// Counts per status for one patch, the "per patch, which files
/// applied cleanly, with fuzz, or failed" of FR-3.
public struct ApplyReport: Sendable, Hashable {
    public var clean = 0
    public var fuzz = 0
    public var failed = 0
    public var binary = 0

    public init(files: [AppliedFile]) {
        for file in files {
            switch file.status {
            case .clean: clean += 1
            case .fuzz: fuzz += 1
            case .failed: failed += 1
            case .binary: binary += 1
            }
        }
    }

    public var total: Int { clean + fuzz + failed + binary }
    public var isClean: Bool { fuzz == 0 && failed == 0 }

    public var summary: String {
        var parts = ["\(clean) clean"]
        if fuzz > 0 { parts.append("\(fuzz) fuzz") }
        if failed > 0 { parts.append("\(failed) failed") }
        if binary > 0 { parts.append("\(binary) binary") }
        return parts.joined(separator: ", ")
    }
}

/// Post line ↔ base line, both 1-based. Added lines have no base line;
/// removed lines have no post line. Built once per applied file and
/// shared by value.
public struct LineMap: Sendable, Hashable {
    /// Index `post - 1` → base line, or `nil` for an added line.
    public var postToBase: [Int?]
    /// Index `base - 1` → post line, or `nil` for a removed line.
    public var baseToPost: [Int?]

    public static let empty = LineMap(postToBase: [], baseToPost: [])

    /// From 0-based worker arrays.
    init(postToBase: [Int?], baseToPost: [Int?]) {
        self.postToBase = postToBase.map { $0.map { $0 + 1 } }
        self.baseToPost = baseToPost.map { $0.map { $0 + 1 } }
    }

    public var postLineCount: Int { postToBase.count }
    public var baseLineCount: Int { baseToPost.count }

    public func base(forPost line: Int) -> Int? {
        guard line >= 1, line <= postToBase.count else { return nil }
        return postToBase[line - 1]
    }

    public func post(forBase line: Int) -> Int? {
        guard line >= 1, line <= baseToPost.count else { return nil }
        return baseToPost[line - 1]
    }

    /// The base line of `post`, or of the nearest earlier post line that
    /// has one (spec alignment step 1: added lines carry the base line
    /// of their nearest context line).
    public func nearestBase(forPost line: Int) -> Int? {
        var l = min(max(line, 1), postToBase.count)
        while l >= 1 {
            if let b = postToBase[l - 1] { return b }
            l -= 1
        }
        return postToBase.compactMap { $0 }.first
    }
}
