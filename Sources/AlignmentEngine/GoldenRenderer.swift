import Foundation
import ApplyEngine
import DiffEngine

/// Golden rendering (spec "Golden rendering", FR-21): a column shown
/// as a diff against the golden column's post text instead of the
/// base. The result is ordinary display lines whose `baseLine` is the
/// golden column's post line, so scroll lock and alignment keep
/// working with `\.baseLine` as the shared frame.
public enum GoldenRenderer {

    public struct Rendering: Sendable, Hashable {
        public var lines: [DisplayLine]
        /// Lines in `text` not in `reference` / lines in `reference` not in `text`.
        public var insertedCount: Int
        public var deletedCount: Int
        public var isIdentical: Bool { insertedCount == 0 && deletedCount == 0 }
    }

    /// `text` against `reference`, both full texts. `includeRemoved`
    /// keeps the reference-only lines inline.
    public static func render(reference: String, text: String, includeRemoved: Bool = true, algorithm: DiffEngine.Algorithm = .patience) -> Rendering {
        let a = DiffEngine.splitLines(reference)
        let b = DiffEngine.splitLines(text)
        let diff = DiffEngine.lines(a, b, algorithm: algorithm)
        var out: [DisplayLine] = []
        out.reserveCapacity(b.count + (includeRemoved ? diff.deletedCount : 0))
        for edit in diff.edits {
            switch edit.kind {
            case .equal:
                for (ai, bi) in zip(edit.a, edit.b) {
                    out.append(DisplayLine(kind: .context, baseLine: ai + 1, postLine: bi + 1, text: b[bi]))
                }
            case .delete:
                if includeRemoved {
                    for ai in edit.a { out.append(DisplayLine(kind: .removed, baseLine: ai + 1, postLine: nil, text: a[ai])) }
                }
            case .insert:
                for bi in edit.b { out.append(DisplayLine(kind: .added, baseLine: nil, postLine: bi + 1, text: b[bi])) }
            }
        }
        return Rendering(lines: out, insertedCount: diff.insertedCount, deletedCount: diff.deletedCount)
    }
}
