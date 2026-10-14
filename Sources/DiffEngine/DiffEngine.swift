import Foundation

/// Line and token diffs between two texts. No dependencies (D1).
///
/// Line diffs drive base-vs-patch and golden-vs-patch rendering
/// (spec FR-9, FR-21); token diffs drive the comparison panel (FR-16).
/// The engine is Myers' O(ND) algorithm in its linear-space form, with
/// the patience heuristic layered on top for line diffs: lines unique
/// to both sides anchor the diff, and Myers fills the gaps.
public enum DiffEngine {

    public enum Algorithm: String, Sendable, Codable, CaseIterable {
        /// Minimal edit script. Matches `git diff --minimal` in the
        /// number of changed lines.
        case myers
        /// Unique-line anchors first, Myers between them. Not always
        /// minimal, usually more readable on moved blocks.
        case patience
    }

    /// Diff two line arrays. Lines are compared exactly.
    public static func lines(_ a: [String], _ b: [String], algorithm: Algorithm = .patience) -> LineDiff {
        let table = SymbolTable(a, b)
        var sink = EditSink()
        switch algorithm {
        case .myers:
            Myers.diff(table.a, table.b, into: &sink)
        case .patience:
            Patience.diff(table.a, table.b, into: &sink)
        }
        return LineDiff(edits: sink.finish(aCount: a.count, bCount: b.count))
    }

    /// Diff two texts line by line. A trailing newline does not count
    /// as an extra empty line.
    public static func lines(_ a: String, _ b: String, algorithm: Algorithm = .patience) -> LineDiff {
        lines(splitLines(a), splitLines(b), algorithm: algorithm)
    }

    /// Diff two texts token by token: identifier runs, whitespace runs
    /// and single punctuation characters. Always Myers — token streams
    /// are short and repetition makes unique anchors rare.
    public static func tokens(_ a: String, _ b: String) -> TokenDiff {
        let ta = Tokenizer.tokens(a)
        let tb = Tokenizer.tokens(b)
        let table = SymbolTable(ta, tb)
        var sink = EditSink()
        Myers.diff(table.a, table.b, into: &sink)
        return TokenDiff(a: ta, b: tb, edits: sink.finish(aCount: ta.count, bCount: tb.count))
    }

    /// Split on `\n`; a final newline does not produce a trailing
    /// empty element.
    public static func splitLines(_ text: String) -> [String] {
        if text.isEmpty { return [] }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if text.hasSuffix("\n") { lines.removeLast() }
        return lines
    }
}

/// One run of a diff: a range of `a` and a range of `b`. For `.equal`
/// both ranges have the same length; `.delete` has an empty `b` range;
/// `.insert` has an empty `a` range.
public struct Edit: Sendable, Hashable {
    public enum Kind: Sendable, Hashable { case equal, delete, insert }
    public var kind: Kind
    public var a: Range<Int>
    public var b: Range<Int>

    public init(kind: Kind, a: Range<Int>, b: Range<Int>) {
        self.kind = kind
        self.a = a
        self.b = b
    }
}

/// A line diff: runs of equal, deleted and inserted lines covering all
/// of `a` and all of `b`, in order, with adjacent runs of one kind
/// merged.
public struct LineDiff: Sendable, Hashable {
    public var edits: [Edit]

    public init(edits: [Edit]) { self.edits = edits }

    public var deletedCount: Int { edits.filter { $0.kind == .delete }.reduce(0) { $0 + $1.a.count } }
    public var insertedCount: Int { edits.filter { $0.kind == .insert }.reduce(0) { $0 + $1.b.count } }
    public var isIdentical: Bool { edits.allSatisfy { $0.kind == .equal } }

    /// Rebuild `b` from `a` by replaying the edits. The diff is valid
    /// exactly when this returns `b`.
    public func apply(to a: [String], inserting b: [String]) -> [String] {
        var out: [String] = []
        for edit in edits {
            switch edit.kind {
            case .equal, .insert: out.append(contentsOf: b[edit.b])
            case .delete: break
            }
        }
        return out
    }
}

/// A token diff plus the token arrays it refers to, so a panel can
/// render both sides with per-token highlighting.
public struct TokenDiff: Sendable, Hashable {
    public var a: [String]
    public var b: [String]
    public var edits: [Edit]

    public init(a: [String], b: [String], edits: [Edit]) {
        self.a = a
        self.b = b
        self.edits = edits
    }

    /// Fraction of tokens shared between the two sides, in 0...1.
    /// Whitespace tokens are ignored. Used by alignment as its
    /// similarity score (spec algorithm step 4).
    public var similarity: Double {
        func counts(_ tokens: [String], _ range: Range<Int>) -> Int {
            tokens[range].filter { !$0.allSatisfy(\.isWhitespace) }.count
        }
        let total = counts(a, 0..<a.count) + counts(b, 0..<b.count)
        if total == 0 { return 1 }
        let shared = edits.filter { $0.kind == .equal }.reduce(0) { $0 + counts(a, $1.a) + counts(b, $1.b) }
        return Double(shared) / Double(total)
    }
}

// MARK: - Internals shared by the algorithms

/// Maps each distinct string to an integer so the algorithms compare
/// `Int`s, not `String`s.
struct SymbolTable {
    let a: [Int]
    let b: [Int]

    init(_ a: [String], _ b: [String]) {
        var ids: [String: Int] = [:]
        func id(_ s: String) -> Int {
            if let i = ids[s] { return i }
            let i = ids.count
            ids[s] = i
            return i
        }
        self.a = a.map(id)
        self.b = b.map(id)
    }
}

/// Collects edits in order and merges neighbours of the same kind.
/// Algorithms report deletes and inserts in absolute index space;
/// `finish` fills every gap with an `.equal` run.
struct EditSink {
    private var deletes: [Int] = []   // indices into a
    private var inserts: [Int] = []   // indices into b

    mutating func delete(_ aIndex: Int) { deletes.append(aIndex) }
    mutating func insert(_ bIndex: Int) { inserts.append(bIndex) }

    func finish(aCount: Int, bCount: Int) -> [Edit] {
        let deleted = Set(deletes)
        let inserted = Set(inserts)
        var edits: [Edit] = []
        var i = 0, j = 0

        func push(_ kind: Edit.Kind, a: Range<Int>, b: Range<Int>) {
            if let last = edits.last, last.kind == kind, last.a.upperBound == a.lowerBound, last.b.upperBound == b.lowerBound {
                edits[edits.count - 1].a = last.a.lowerBound..<a.upperBound
                edits[edits.count - 1].b = last.b.lowerBound..<b.upperBound
            } else {
                edits.append(Edit(kind: kind, a: a, b: b))
            }
        }

        while i < aCount || j < bCount {
            if i < aCount, deleted.contains(i) {
                push(.delete, a: i..<i + 1, b: j..<j); i += 1
            } else if j < bCount, inserted.contains(j) {
                push(.insert, a: i..<i, b: j..<j + 1); j += 1
            } else {
                precondition(i < aCount && j < bCount, "diff does not cover both sequences")
                push(.equal, a: i..<i + 1, b: j..<j + 1); i += 1; j += 1
            }
        }
        return edits
    }
}
