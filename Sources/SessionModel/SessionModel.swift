import Foundation
import PatchModel

// The review record (spec "SessionModel"; FR-5, FR-12, FR-18, FR-25 to
// FR-35). Plain Codable value types, no UI, no engines: the app turns
// its live state into a `Session` to save or export and back again to
// restore. Columns are addressed by label (A–D) because a label means
// the same patch for the life of a session (MISSION.md §6).

/// Quality label of a finding (FR-26). Not a correctness verdict.
public enum Severity: String, Codable, CaseIterable, Sendable, Hashable {
    case trivial, minor, material, blocking
}

/// "Does the request ask for this?" (spec "Judge relative to the request").
public enum RequestAsks: String, Codable, CaseIterable, Sendable, Hashable {
    case yes, no, unclear
}

/// Display-line range of a region in one column, stored as bounds so it
/// is Codable and readable in `session.json`.
public struct LineSpan: Codable, Sendable, Hashable {
    public var lower: Int
    public var upper: Int

    public init(_ range: Range<Int>) {
        lower = range.lowerBound
        upper = range.upperBound
    }

    public init(lower: Int, upper: Int) {
        self.lower = lower
        self.upper = upper
    }

    public var range: Range<Int> { lower..<max(lower, upper) }
}

/// Where a finding's region landed in another column, kept with the
/// finding for the JSON export (FR-33).
public struct FindingAnchor: Codable, Sendable, Hashable {
    public var label: String
    /// `exact`, `modified`, `moved` or `absent` — the engine's words.
    public var status: String
    public var confidence: Double
    public var reference: String?

    public init(label: String, status: String, confidence: Double, reference: String?) {
        self.label = label
        self.status = status
        self.confidence = confidence
        self.reference = reference
    }
}

/// One recorded finding (FR-25, FR-26, FR-30).
public struct Finding: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var label: String
    public var path: String
    public var lines: LineSpan
    /// Generated from the selection, never typed (`filename Lstart:Lend`).
    public var reference: String
    public var title: String
    public var description: String
    public var category: String
    public var severity: Severity
    public var requestAsks: RequestAsks
    /// A deliberate pass: considered and rejected (FR-30).
    public var notFlagged: Bool
    /// A parked correctness concern; not a quality label.
    public var note: String
    public var anchors: [FindingAnchor]
    public var created: Date

    public init(id: UUID = UUID(), label: String, path: String, lines: LineSpan, reference: String,
                title: String, description: String = "", category: String, severity: Severity,
                requestAsks: RequestAsks = .unclear, notFlagged: Bool = false, note: String = "",
                anchors: [FindingAnchor] = [], created: Date = Date()) {
        self.id = id
        self.label = label
        self.path = path
        self.lines = lines
        self.reference = reference
        self.title = title
        self.description = description
        self.category = category
        self.severity = severity
        self.requestAsks = requestAsks
        self.notFlagged = notFlagged
        self.note = note
        self.anchors = anchors
        self.created = created
    }

    /// Title, severity and category are required (FR-26).
    public var isComplete: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !category.isEmpty && !reference.isEmpty
    }
}

/// Rank per label, ties allowed, plus the rationale (FR-31).
public struct Ranking: Codable, Sendable, Hashable {
    public var ranks: [String: Int]
    public var rationale: String

    public init(ranks: [String: Int] = [:], rationale: String = "") {
        self.ranks = ranks
        self.rationale = rationale
    }

    public func rank(of label: String) -> Int? { ranks[label] }
}

/// A pinned selection (FR-17), by label.
public struct SessionPin: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var label: String
    public var path: String
    public var lines: LineSpan
    public var reference: String
    public var snippet: String

    public init(id: UUID = UUID(), label: String, path: String, lines: LineSpan, reference: String, snippet: String) {
        self.id = id
        self.label = label
        self.path = path
        self.lines = lines
        self.reference = reference
        self.snippet = snippet
    }
}

/// A reviewer's correction of a located region (FR-18): for a source
/// region in one column, the lines it really corresponds to in another.
/// Takes precedence over the engine on reload.
public struct ManualAnchor: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var sourceLabel: String
    public var path: String
    public var sourceLines: LineSpan
    public var targetLabel: String
    public var targetLines: LineSpan

    public init(id: UUID = UUID(), sourceLabel: String, path: String, sourceLines: LineSpan, targetLabel: String, targetLines: LineSpan) {
        self.id = id
        self.sourceLabel = sourceLabel
        self.path = path
        self.sourceLines = sourceLines
        self.targetLabel = targetLabel
        self.targetLines = targetLines
    }

    public func matches(sourceLabel: String, path: String, sourceLines: Range<Int>) -> Bool {
        self.sourceLabel == sourceLabel && self.path == path && self.sourceLines.range == sourceLines
    }
}

/// One column as saved: its label, the patch file's name, and the copy
/// of the patch kept inside the package.
public struct SessionColumn: Codable, Sendable, Hashable {
    public var label: String
    public var sourceName: String
    /// File name inside the `.patchadam` package.
    public var patchFile: String
    public var isHidden: Bool
    public var isRead: Bool

    public init(label: String, sourceName: String, patchFile: String, isHidden: Bool = false, isRead: Bool = false) {
        self.label = label
        self.sourceName = sourceName
        self.patchFile = patchFile
        self.isHidden = isHidden
        self.isRead = isRead
    }
}

/// Pointer to the base, not the base itself (spec "Persistence").
public struct BasePointer: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable { case directory, gitRevision, archive, synthetic }
    public var kind: Kind
    public var path: String?
    public var revision: String?
    public var commit: String?
    public var label: String?

    public init(kind: Kind, path: String? = nil, revision: String? = nil, commit: String? = nil, label: String? = nil) {
        self.kind = kind
        self.path = path
        self.revision = revision
        self.commit = commit
        self.label = label
    }

    public static let synthetic = BasePointer(kind: .synthetic, label: "synthetic base from the patches")
}

/// Blind mode (FR-12): labels show as numbers in a seeded, stored
/// shuffle so the same session reopens to the same picture (MISSION.md §8).
public struct BlindMode: Codable, Sendable, Hashable {
    public var isOn: Bool
    public var seed: UInt64

    public init(isOn: Bool, seed: UInt64) {
        self.isOn = isOn
        self.seed = seed
    }

    /// Label → display number, 1-based, derived from the seed alone.
    public func mapping(for labels: [String]) -> [String: Int] {
        let order = Self.shuffled(labels.sorted(), seed: seed)
        return Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset + 1) })
    }

    /// Fisher–Yates over a tiny deterministic generator (SplitMix64):
    /// `Hasher` and the system RNG are seeded per process, so neither
    /// could reproduce a stored shuffle.
    public static func shuffled(_ labels: [String], seed: UInt64) -> [String] {
        var state = seed
        func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        var out = labels
        guard out.count > 1 else { return out }
        for i in stride(from: out.count - 1, to: 0, by: -1) {
            let j = Int(next() % UInt64(i + 1))
            out.swapAt(i, j)
        }
        return out
    }
}

/// The whole review (FR-5, FR-35). `session.json` is this, pretty-printed.
public struct Session: Codable, Sendable, Hashable {
    public static let formatVersion = 1

    public var version: Int
    public var name: String
    public var request: String
    public var base: BasePointer
    /// In display order.
    public var columns: [SessionColumn]
    public var golden: String?
    public var categories: [String]
    public var findings: [Finding]
    public var ranking: Ranking
    public var pins: [SessionPin]
    public var manualAnchors: [ManualAnchor]
    public var blind: BlindMode
    public var created: Date
    public var saved: Date?

    public init(name: String, request: String = "", base: BasePointer, columns: [SessionColumn], golden: String? = nil,
                categories: [String] = Session.defaultCategories, findings: [Finding] = [], ranking: Ranking = Ranking(),
                pins: [SessionPin] = [], manualAnchors: [ManualAnchor] = [], blind: BlindMode = BlindMode(isOn: false, seed: 0),
                created: Date = Date(), saved: Date? = nil) {
        self.version = Session.formatVersion
        self.name = name
        self.request = request
        self.base = base
        self.columns = columns
        self.golden = golden
        self.categories = categories
        self.findings = findings
        self.ranking = ranking
        self.pins = pins
        self.manualAnchors = manualAnchors
        self.blind = blind
        self.created = created
        self.saved = saved
    }

    /// The slop categories (DECISIONS.md D3), editable per session.
    public static let defaultCategories: [String] = [
        "unnecessary helpers",
        "excessive defensiveness",
        "unnecessary machinery or repeated work",
        "duplicated logic or state",
        "too many branches",
        "unclear code",
        "unhelpful comments or names",
        "code in the wrong place",
        "unneeded backwards compatibility",
        "dead or unrelated code",
        "premature extensibility",
        "low-value tests",
        "other",
    ]

    public func column(labelled label: String) -> SessionColumn? { columns.first { $0.label == label } }

    /// Label → blind number when blind mode is on, else empty.
    public var blindMapping: [String: Int] {
        blind.isOn ? blind.mapping(for: columns.map(\.label)) : [:]
    }

    /// What the reviewer sees for a label: `A`, or `2` in blind mode.
    public func displayLabel(_ label: String) -> String {
        if let n = blindMapping[label] { return String(n) }
        return label
    }

    /// Columns in rank order (ties keep display order), unranked last.
    public var rankedColumns: [SessionColumn] {
        columns.enumerated().sorted { a, b in
            let ra = ranking.rank(of: a.element.label) ?? Int.max
            let rb = ranking.rank(of: b.element.label) ?? Int.max
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
    }
}
