import Foundation
import PatchModel

/// One line as a column renders it (spec FR-9): the full post-patch
/// file with removed lines interleaved where they were. Context and
/// added lines have a post line number; context and removed lines
/// have a base line number.
public struct DisplayLine: Sendable, Hashable {
    public enum Kind: Sendable, Hashable { case context, added, removed }
    public var kind: Kind
    public var baseLine: Int?
    public var postLine: Int?
    public var text: String

    public init(kind: Kind, baseLine: Int?, postLine: Int?, text: String) {
        self.kind = kind
        self.baseLine = baseLine
        self.postLine = postLine
        self.text = text
    }
}

extension AppliedFile {

    /// The column's lines in order. A removed base line sits before
    /// the post line that follows it. A failed or binary file has no
    /// display lines; the view shows the raw hunks instead.
    public func displayLines(includeRemoved: Bool = true) -> [DisplayLine] {
        guard let post = postText ?? (change.kind == .deleted ? "" : nil) else { return [] }
        let postLines = ApplyEngine.splitLines(post)
        let baseLines = ApplyEngine.splitLines(baseText ?? "")
        var out: [DisplayLine] = []
        out.reserveCapacity(postLines.count + (includeRemoved ? baseLines.count - lineMap.baseToPost.compactMap { $0 }.count : 0))

        var nextBase = 1   // next base line not yet accounted for
        func emitRemoved(before postIndex: Int?) {
            // Base lines from nextBase up to the base line that maps to
            // `postIndex` (or EOF) are removed lines.
            let stop = postIndex.flatMap { lineMap.postToBase[$0] } ?? (baseLines.count + 1)
            while nextBase < stop {
                if includeRemoved {
                    out.append(DisplayLine(kind: .removed, baseLine: nextBase, postLine: nil, text: baseLines[nextBase - 1]))
                }
                nextBase += 1
            }
        }

        for (i, text) in postLines.enumerated() {
            if let base = lineMap.postToBase[i] {
                emitRemoved(before: i)
                out.append(DisplayLine(kind: .context, baseLine: base, postLine: i + 1, text: text))
                nextBase = base + 1
            } else {
                // An added line: any removed lines that precede it at this
                // position come first only when the next mapped post line
                // says so, so flush up to the next context line now.
                if let nextMapped = (i..<postLines.count).first(where: { lineMap.postToBase[$0] != nil }) {
                    emitRemoved(before: nextMapped)
                } else {
                    emitRemoved(before: nil)
                }
                out.append(DisplayLine(kind: .added, baseLine: nil, postLine: i + 1, text: text))
            }
        }
        emitRemoved(before: nil)
        return out
    }
}

/// `filename Lstart:Lend` (spec "Line reference format"). Post-patch
/// lines, file name only; `-L` when the reference is to removed lines.
public struct LineReference: Sendable, Hashable, CustomStringConvertible {
    public var fileName: String
    public var start: Int
    public var end: Int
    public var removedSide: Bool

    public init(fileName: String, start: Int, end: Int, removedSide: Bool = false) {
        self.fileName = fileName
        self.start = start
        self.end = end
        self.removedSide = removedSide
    }

    public var description: String {
        "\(fileName) \(removedSide ? "-" : "")L\(start):L\(end)"
    }

    /// The reference for a run of display lines. Post lines win when
    /// the run has any; a run of removed lines only refers to their
    /// base lines with the `-L` prefix. `nil` for an empty run.
    public static func forDisplayLines(_ lines: ArraySlice<DisplayLine>, fileName: String) -> LineReference? {
        let post = lines.compactMap(\.postLine)
        if let first = post.first, let last = post.last {
            return LineReference(fileName: fileName, start: first, end: last)
        }
        let base = lines.compactMap(\.baseLine)
        if let first = base.first, let last = base.last {
            return LineReference(fileName: fileName, start: first, end: last, removedSide: true)
        }
        return nil
    }
}

extension LineMap {
    /// The post line at or after base line `line` — the anchor scroll
    /// lock uses (FR-10): the same base position in every column,
    /// skipping lines the column removed.
    public func post(atOrAfterBase line: Int) -> Int? {
        guard !baseToPost.isEmpty else { return postLineCount > 0 ? 1 : nil }
        var l = max(line, 1)
        while l <= baseToPost.count {
            if let p = baseToPost[l - 1] { return p }
            l += 1
        }
        return postLineCount > 0 ? postLineCount : nil
    }
}

extension Array where Element == DisplayLine {
    /// The base line a display line stands for: its own, or the nearest
    /// earlier line that has one — an added line travels with the
    /// context above it (spec alignment step 1). Scroll lock's anchor.
    public func anchorBase(at index: Int) -> Int? {
        guard !isEmpty else { return nil }
        var i = Swift.min(Swift.max(index, 0), count - 1)
        while i >= 0 {
            if let base = self[i].baseLine { return base }
            i -= 1
        }
        return first { $0.baseLine != nil }?.baseLine
    }

    /// Index of the first display line whose base line is at or after
    /// `base`, or the last line when none is. Base lines ascend where
    /// present, so this is a binary search that steps over added lines.
    public func index(atOrAfterBase base: Int) -> Int? {
        guard !isEmpty else { return nil }
        var lo = 0, hi = count - 1, answer = count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            var probe = mid
            while probe <= hi, self[probe].baseLine == nil { probe += 1 }
            if probe > hi { hi = mid - 1; continue }
            if self[probe].baseLine! >= base { answer = probe; hi = mid - 1 } else { lo = probe + 1 }
        }
        return answer
    }
}

extension Array where Element == DisplayLine {
    /// Each run of synthetic filler lines (D4) becomes one unnumbered
    /// marker line whose text `marker` makes from the run's length
    /// (issue #12). Real lines keep their numbers, so references,
    /// scroll lock and alignment are unchanged.
    public func collapsingSyntheticFiller(marker: (Int) -> String) -> [DisplayLine] {
        var out: [DisplayLine] = []
        out.reserveCapacity(count)
        var run = 0
        func flush() {
            if run > 0 { out.append(DisplayLine(kind: .context, baseLine: nil, postLine: nil, text: marker(run))); run = 0 }
        }
        for line in self {
            if SyntheticBase.isFiller(line.text) { run += 1 } else { flush(); out.append(line) }
        }
        flush()
        return out
    }
}
