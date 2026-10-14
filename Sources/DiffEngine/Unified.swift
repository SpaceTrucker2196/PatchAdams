/// Render a `LineDiff` as a unified diff, for the CLI harness and for
/// comparing against `git diff --no-index`.
extension LineDiff {

    /// Hunks with `context` lines of surrounding equal text, each as
    /// the `@@` header ranges plus its marked lines. Changes whose
    /// equal gap is at most `2 * context` lines share a hunk, as in
    /// `diff -u`.
    public func unifiedHunks(a: [String], b: [String], context: Int = 3) -> [UnifiedHunk] {
        struct Rec { var kind: Edit.Kind; var ai: Int?; var bi: Int? }
        var recs: [Rec] = []
        for e in edits {
            switch e.kind {
            case .equal: for (ai, bi) in zip(e.a, e.b) { recs.append(Rec(kind: .equal, ai: ai, bi: bi)) }
            case .delete: for ai in e.a { recs.append(Rec(kind: .delete, ai: ai, bi: nil)) }
            case .insert: for bi in e.b { recs.append(Rec(kind: .insert, ai: nil, bi: bi)) }
            }
        }
        let changed = recs.indices.filter { recs[$0].kind != .equal }
        if changed.isEmpty { return [] }

        // aBefore[i] = how many `a` lines precede rec i; same for b.
        var aBefore = [Int](repeating: 0, count: recs.count + 1)
        var bBefore = [Int](repeating: 0, count: recs.count + 1)
        for (i, r) in recs.enumerated() {
            aBefore[i + 1] = aBefore[i] + (r.ai == nil ? 0 : 1)
            bBefore[i + 1] = bBefore[i] + (r.bi == nil ? 0 : 1)
        }

        var groups: [ClosedRange<Int>] = []
        var start = changed[0], end = changed[0]
        for idx in changed.dropFirst() {
            if idx - end - 1 > 2 * context { groups.append(start...end); start = idx }
            end = idx
        }
        groups.append(start...end)

        return groups.map { g in
            let lo = Swift.max(0, g.lowerBound - context)
            let hi = Swift.min(recs.count - 1, g.upperBound + context)
            let aCount = aBefore[hi + 1] - aBefore[lo]
            let bCount = bBefore[hi + 1] - bBefore[lo]
            // A non-empty range starts at its first line (1-based); an
            // empty one reports the line before it, as `diff -u` does.
            let oldStart = aCount == 0 ? aBefore[lo] : aBefore[lo] + 1
            let newStart = bCount == 0 ? bBefore[lo] : bBefore[lo] + 1
            var lines: [String] = []
            for r in recs[lo...hi] {
                switch r.kind {
                case .equal: lines.append(" " + a[r.ai!])
                case .delete: lines.append("-" + a[r.ai!])
                case .insert: lines.append("+" + b[r.bi!])
                }
            }
            return UnifiedHunk(oldStart: oldStart, oldCount: aCount, newStart: newStart, newCount: bCount, lines: lines)
        }
    }

    /// Full unified diff text with `---`/`+++` headers.
    public func unified(a: [String], b: [String], aName: String, bName: String, context: Int = 3) -> String {
        var out = "--- \(aName)\n+++ \(bName)\n"
        for h in unifiedHunks(a: a, b: b, context: context) {
            out += h.header + "\n"
            out += h.lines.joined(separator: "\n") + "\n"
        }
        return out
    }
}

public struct UnifiedHunk: Sendable, Hashable {
    public var oldStart: Int
    public var oldCount: Int
    public var newStart: Int
    public var newCount: Int
    public var lines: [String]

    public var header: String {
        func range(_ s: Int, _ c: Int) -> String { c == 1 ? "\(s)" : "\(s),\(c)" }
        return "@@ -\(range(oldStart, oldCount)) +\(range(newStart, newCount)) @@"
    }
}
