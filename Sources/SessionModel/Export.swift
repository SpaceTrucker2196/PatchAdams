import Foundation

/// Markdown export (FR-32): the review write-up, ready to paste. Shape
/// (DECISIONS.md D5): title, the request collapsed, a mapping table of
/// label / patch file / rank, findings grouped by patch in rank order
/// with generated references, the not-flagged passes under their own
/// heading, the rationale. In blind mode the body uses the blind
/// numbers and the true mapping is the last section (FR-12).
public enum MarkdownExport {
    public static func render(_ session: Session, date: Date = Date()) -> String {
        let blind = session.blind.isOn
        var out: [String] = []
        let name = session.name.isEmpty ? "Patch review" : session.name
        out.append("# \(name)")
        out.append("")
        out.append("_\(session.columns.count) patches · \(session.findings.filter { !$0.notFlagged }.count) findings · \(Self.dateFormatter.string(from: date))_")
        out.append("")

        if !session.request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            out.append("<details><summary>Request</summary>")
            out.append("")
            out.append(session.request.trimmingCharacters(in: .whitespacesAndNewlines))
            out.append("")
            out.append("</details>")
            out.append("")
        }

        out.append("## Ranking")
        out.append("")
        if blind {
            out.append("| Rank | Patch |")
            out.append("|---:|---|")
        } else {
            out.append("| Rank | Patch | File |")
            out.append("|---:|---|---|")
        }
        for column in session.rankedColumns {
            let rank = session.ranking.rank(of: column.label).map(String.init) ?? "—"
            if blind {
                out.append("| \(rank) | \(session.displayLabel(column.label)) |")
            } else {
                out.append("| \(rank) | \(column.label) | `\(column.sourceName)` |")
            }
        }
        out.append("")

        out.append("## Findings")
        out.append("")
        let flagged = session.findings.filter { !$0.notFlagged }
        if flagged.isEmpty { out.append("_None._"); out.append("") }
        for column in session.rankedColumns {
            let mine = flagged.filter { $0.label == column.label }
            guard !mine.isEmpty else { continue }
            out.append("### \(heading(column, session))")
            out.append("")
            for finding in sorted(mine) { out.append(contentsOf: bullet(finding)) }
            out.append("")
        }

        let passes = session.findings.filter(\.notFlagged)
        if !passes.isEmpty {
            out.append("## Not flagged")
            out.append("")
            out.append("Considered and passed:")
            out.append("")
            for finding in sorted(passes) {
                var line = "- \(session.displayLabel(finding.label)) `\(finding.reference)` — \(finding.title)"
                if !finding.description.isEmpty { line += ": \(oneLine(finding.description))" }
                out.append(line)
            }
            out.append("")
        }

        out.append("## Rationale")
        out.append("")
        let rationale = session.ranking.rationale.trimmingCharacters(in: .whitespacesAndNewlines)
        out.append(rationale.isEmpty ? "_Not written._" : rationale)
        out.append("")

        if blind {
            out.append("## Mapping")
            out.append("")
            out.append("Blind review; the labels above map to:")
            out.append("")
            out.append("| Label | Column | File |")
            out.append("|---|---|---|")
            for column in session.columns.sorted(by: { session.blindMapping[$0.label] ?? 0 < session.blindMapping[$1.label] ?? 0 }) {
                out.append("| \(session.displayLabel(column.label)) | \(column.label) | `\(column.sourceName)` |")
            }
            out.append("")
        }
        return out.joined(separator: "\n")
    }

    /// A single finding in the export's form, for the clipboard (FR-34).
    public static func bulletText(_ finding: Finding) -> String { bullet(finding).joined(separator: "\n") }

    /// One finding as a list item: `- **severity · category** — title \`ref\``,
    /// then the description, the request answer when it is not "unclear",
    /// and the note, each indented under the bullet.
    static func bullet(_ finding: Finding) -> [String] {
        var lines = ["- **\(finding.severity.rawValue) · \(finding.category)** — \(finding.title) `\(finding.reference)`"]
        if !finding.description.isEmpty { lines.append("  \(oneLine(finding.description))") }
        if finding.requestAsks != .unclear { lines.append("  Request asks for this: \(finding.requestAsks.rawValue).") }
        if !finding.note.isEmpty { lines.append("  Note: \(oneLine(finding.note))") }
        return lines
    }

    static func heading(_ column: SessionColumn, _ session: Session) -> String {
        let rank = session.ranking.rank(of: column.label).map { " (rank \($0))" } ?? ""
        if session.blind.isOn { return "Patch \(session.displayLabel(column.label))\(rank)" }
        return "\(column.label) — `\(column.sourceName)`\(rank)"
    }

    /// Blocking first, then by file and line.
    static func sorted(_ findings: [Finding]) -> [Finding] {
        let order: [Severity] = [.blocking, .material, .minor, .trivial]
        return findings.sorted { a, b in
            let sa = order.firstIndex(of: a.severity) ?? 0, sb = order.firstIndex(of: b.severity) ?? 0
            if sa != sb { return sa < sb }
            if a.path != b.path { return a.path < b.path }
            return a.lines.lower < b.lines.lower
        }
    }

    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// JSON export (FR-33): the session record itself, with anchors and
/// confidence on every finding and the blind mapping spelled out, for
/// tooling. The same encoder as `session.json`, so the two agree.
public enum JSONExport {
    public struct Document: Codable, Sendable {
        public var session: Session
        public var blindMapping: [String: Int]
        public var exported: Date
    }

    public static func render(_ session: Session, date: Date = Date()) throws -> Data {
        try SessionPackage.encoder.encode(Document(session: session, blindMapping: session.blindMapping, exported: date))
    }
}
