import SwiftUI
import PatchModel
import BaseLoader
import ApplyEngine
import AlignmentEngine
import SessionModel

// The one owner of session state (spec "Technical architecture"). The
// shell never calls an engine: everything heavy runs on `Engines`, an
// actor, and comes back as immutable values that the views render.

/// One patch as the window shows it (spec "Column").
struct PatchColumn: Identifiable, Hashable {
    let id: UUID
    /// A, B, C or D — assigned when the patch is added and kept across
    /// reordering, so a label always means the same patch.
    var label: String
    /// The patch's file name, shown beside the label everywhere
    /// (FR-4, MISSION.md §6).
    var sourceName: String
    var patch: Patch
    /// The patch as read, copied into the `.patchadam` package on save.
    var sourceText: String
    var applied: AppliedPatch?
    var isHidden = false
    var isRead = false

    var isApplying: Bool { applied == nil }

    func appliedFile(_ path: String) -> AppliedFile? {
        applied?.files.first { $0.change.path == path || $0.change.oldPath == path }
    }

    /// Status chip for one file row (FR-8).
    func chip(for path: String) -> FileChip {
        guard let change = patch.files.first(where: { $0.path == path || $0.oldPath == path }) else { return .unchanged }
        if let file = appliedFile(path), file.status.isFailure { return .failed }
        switch change.kind {
        case .added: return .added
        case .deleted: return .deleted
        default: return .changed
        }
    }
}

enum FileChip: String, Hashable {
    case changed, added, deleted, unchanged, failed

    var color: Color {
        switch self {
        case .changed: return .blue
        case .added: return .green
        case .deleted: return .red
        case .unchanged: return .secondary
        case .failed: return .orange
        }
    }
}

struct FileRow: Identifiable, Hashable {
    var id: String { path }
    var path: String
    var chips: [UUID: FileChip]
    var isTest: Bool
}

struct ScrollRequest: Hashable {
    var displayLine: Int
    var generation: Int
}

/// Engines run here, off the main actor. Results are value types.
actor Engines {
    func apply(_ patch: Patch, to base: any FileProvider) -> AppliedPatch {
        ApplyEngine.apply(patch, to: base)
    }

    /// Locate `region` of `source` in every target (FR-13). `postKeyed`
    /// marks the golden column, whose frame is its own post text.
    func locate(_ region: Range<Int>, source: [DisplayLine], sourcePostKeyed: Bool,
                targets: [(id: UUID, lines: [DisplayLine], postKeyed: Bool, hunks: [HunkPlacement])]) -> [UUID: RegionAnchor] {
        var out: [UUID: RegionAnchor] = [:]
        for target in targets {
            out[target.id] = AlignmentEngine.locate(region, in: source, sourceKey: sourcePostKeyed ? \.postLine : \.baseLine,
                                                    target: target.lines, targetKey: target.postKeyed ? \.postLine : \.baseLine,
                                                    targetHunks: target.hunks)
        }
        return out
    }
}

/// A region the reviewer selected (spec "Region"): display lines in one column.
struct SelectionRegion: Hashable {
    var columnID: UUID
    var path: String
    var lines: Range<Int>
}

/// A pinned selection (FR-17).
struct Pin: Identifiable, Hashable {
    let id: UUID
    var region: SelectionRegion
    var label: String
    var reference: String
    var snippet: String
}

struct SearchHit: Identifiable, Hashable {
    var id: String { "\(columnID)|\(displayIndex)" }
    var columnID: UUID
    var displayIndex: Int
    var text: String
    var reference: String
}

struct SearchColumnHits: Identifiable, Hashable {
    var id: UUID { columnID }
    var columnID: UUID
    var label: String
    var hits: [SearchHit]
}

struct SearchGroup: Identifiable, Hashable {
    var id: String { path }
    var path: String
    var columns: [SearchColumnHits]
    var count: Int { columns.reduce(0) { $0 + $1.hits.count } }
}

@MainActor @Observable
final class SessionController {
    var base: (any FileProvider)?
    var columns: [PatchColumn] = []
    var selectedPath: String?
    var scrollLock = true
    var requestText = ""
    var showRequestPanel = true
    var filterText = ""
    var testsOnly = false
    var showRemovedLines = true
    var focusedColumnID: UUID?
    /// Selected display-line range per column, from the text views.
    var selections: [UUID: Range<Int>] = [:]
    var scrollRequests: [UUID: ScrollRequest] = [:]
    var errorMessage: String?
    var statusMessage: String?
    /// The golden column (FR-20), or `nil` for base rendering.
    var goldenID: UUID?
    /// The region being compared and where it landed in every other column.
    var comparedRegion: SelectionRegion?
    var anchors: [UUID: RegionAnchor] = [:]
    var pins: [Pin] = []
    var searchQuery = ""
    var searchResults: [SearchGroup] = []
    var showComparison = true
    var showPins = false
    var showSearch = false
    /// Columns whose text view selection is non-empty (a drag, not a caret).
    var selectionIsEmpty: [UUID: Bool] = [:]

    // Phase 4: the review record (SessionModel). Mirrored into a
    // `Session` on save and export; see SessionController+Review.
    var sessionName = ""
    var sessionURL: URL?
    var findings: [Finding] = []
    var ranking = Ranking()
    var categories = Session.defaultCategories
    var blind = BlindMode(isOn: false, seed: 0)
    var manualAnchors: [ManualAnchor] = []
    var showFindings = true
    var findingDraft: FindingDraft?
    var findingFilter = FindingFilter()
    var sessionStart = Date()
    var isDirty = false

    /// `git --version` at launch, or `nil` when git is not installed:
    /// the Git Revision base is then disabled and the welcome view says
    /// so; directory and archive bases still work (spec risk table).
    let gitVersion: String? = Git.version()
    static let blindPromptShownKey = "blindPromptShown"
    /// The one-time blind-mode question on a new session (spec open
    /// question: off by default, with a prompt).
    var showBlindPrompt = false

    @ObservationIgnored let engines = Engines()
    @ObservationIgnored let scrollSync = ScrollSync()
    @ObservationIgnored private var scrollGeneration = 0
    @ObservationIgnored private var displayCache: [String: [DisplayLine]] = [:]
    @ObservationIgnored private var goldenCache: [String: GoldenRenderer.Rendering] = [:]
    @ObservationIgnored var locateTask: Task<Void, Never>?
    @ObservationIgnored var locateGeneration = 0

    /// Columns in display order, hidden ones left out.
    var visibleColumns: [PatchColumn] { columns.filter { !$0.isHidden } }

    var hasSession: Bool { base != nil && columns.count >= 2 }

    var baseDescription: String { base?.origin.description ?? String(localized: "no base") }

    var sessionTitle: String {
        guard base != nil || !columns.isEmpty else { return String(localized: "Patch Adam") }
        return "\(baseDescription) — \(columns.count) " + String(localized: "patches")
    }

    // MARK: - Loading (FR-1, FR-2)

    func openBase(url: URL, revision: String? = nil) {
        do {
            base = try BaseLoader.open(url, revision: revision)
            reapplyAll()
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// Rebuild a base from the patches themselves (SyntheticBase, D4):
    /// every base line any patch shows is real, the rest is filler.
    func useSyntheticBase() {
        do {
            let files = try SyntheticBase.merged(for: columns.map(\.patch))
            base = InMemoryBase(label: String(localized: "synthetic base from \(columns.count) patches"),
                                texts: Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0.text) }))
            reapplyAll()
        } catch {
            errorMessage = "\(error)"
        }
    }

    func addPatch(url: URL) {
        do {
            let text = BaseLoader.text(from: try Data(contentsOf: url))
            addPatch(text: text, name: url.lastPathComponent)
        } catch {
            errorMessage = "\(url.lastPathComponent): \(error)"
        }
    }

    func addPatch(text: String, name: String, label: String? = nil) {
        do {
            addPatch(try UnifiedDiffParser.parse(text), text: text, name: name, label: label)
        } catch {
            errorMessage = "\(name): \(error)"
        }
    }

    private func addPatch(_ patch: Patch, text: String, name: String, label wanted: String? = nil) {
        guard columns.count < 4 else {
            errorMessage = String(localized: "A session holds at most four patches.")
            return
        }
        let labels = ["A", "B", "C", "D"]
        let used = Set(columns.map(\.label))
        let label = wanted.flatMap { used.contains($0) ? nil : $0 } ?? labels.first { !used.contains($0) } ?? "?"
        let column = PatchColumn(id: UUID(), label: label, sourceName: name, patch: patch, sourceText: text)
        columns.append(column)
        apply(columnID: column.id)
        if selectedPath == nil { selectedPath = fileRows.first?.path }
    }

    func removeColumn(_ id: UUID) {
        let label = columns.first { $0.id == id }?.label
        columns.removeAll { $0.id == id }
        displayCache = [:]
        goldenCache = [:]
        if goldenID == id { goldenID = nil }
        pins.removeAll { $0.region.columnID == id }
        if let label {
            findings.removeAll { $0.label == label }
            ranking.ranks[label] = nil
        }
        anchors = [:]
        comparedRegion = nil
    }

    func newSession() {
        base = nil
        columns = []
        selectedPath = nil
        selections = [:]
        displayCache = [:]
        goldenCache = [:]
        goldenID = nil
        pins = []
        anchors = [:]
        comparedRegion = nil
        searchResults = []
        requestText = ""
        showRequestPanel = true
        sessionName = ""
        sessionURL = nil
        findings = []
        ranking = Ranking()
        categories = Session.defaultCategories
        blind = BlindMode(isOn: false, seed: 0)
        manualAnchors = []
        findingDraft = nil
        findingFilter = FindingFilter()
        sessionStart = Date()
        isDirty = false
    }

    /// Open patch files against a base rebuilt from them (debug hooks).
    func openDemoSession(fixtures: [URL], request: String = "") {
        newSession()
        for url in fixtures { addPatch(url: url) }
        useSyntheticBase()
        requestText = request
    }

    // MARK: - Apply

    func reapplyAll() {
        displayCache = [:]
        goldenCache = [:]
        for column in columns { apply(columnID: column.id) }
    }

    private func apply(columnID: UUID) {
        guard let base, let index = columns.firstIndex(where: { $0.id == columnID }) else { return }
        columns[index].applied = nil
        let patch = columns[index].patch
        Task {
            let applied = await engines.apply(patch, to: base)
            guard let i = columns.firstIndex(where: { $0.id == columnID }) else { return }
            columns[i].applied = applied
            displayCache = [:]
            goldenCache = [:]
            let report = applied.report
            if report.failed > 0 {
                statusMessage = String(localized: "\(columns[i].label) (\(columns[i].sourceName)): \(report.failed) file(s) failed to apply")
            }
        }
    }

    // MARK: - File tree (FR-8)

    var fileRows: [FileRow] {
        let filter = filterText.lowercased()
        return allRows.filter { row in
            (!testsOnly || row.isTest) && (filter.isEmpty || row.path.lowercased().contains(filter))
        }
    }

    /// Every touched file, unfiltered. In golden mode a non-golden
    /// column's chip says whether its file differs from golden (FR-22).
    var allRows: [FileRow] {
        var paths: [String: [UUID: FileChip]] = [:]
        for column in columns {
            for file in column.patch.files {
                paths[file.path, default: [:]][column.id] = column.chip(for: file.path)
            }
        }
        let golden = goldenID.flatMap { id in columns.first { $0.id == id } }
        return paths.keys.sorted().map { path in
            let change = columns.lazy.compactMap { $0.patch.files.first { $0.path == path } }.first
            var chips = paths[path]!
            for column in columns where chips[column.id] == nil { chips[column.id] = .unchanged }
            if let golden {
                for column in columns where column.id != golden.id && chips[column.id] != .failed && column.applied != nil {
                    if let rendering = goldenRendering(golden: golden, column: column, path: path) {
                        chips[column.id] = rendering.isIdentical ? .unchanged : .changed
                    }
                }
            }
            return FileRow(path: path, chips: chips, isTest: change?.isTest ?? false)
        }
    }

    // MARK: - Rendering

    /// What a column shows for the selected file: the applied file, or
    /// the untouched base file when the patch does not mention it.
    func renderedFile(column: PatchColumn, path: String) -> AppliedFile? {
        if let file = column.appliedFile(path) { return file }
        guard column.applied != nil, let base, let data = try? base.contents(of: path) else { return nil }
        let text = BaseLoader.text(from: data)
        let count = ApplyEngine.splitLines(text).count
        let change = FileChange(oldPath: path, newPath: path, kind: .modified)
        return AppliedFile(change: change, baseText: text, postText: text, status: .clean,
                           lineMap: LineMap.identity(lineCount: count), hunks: [])
    }

    static let reducedModeThreshold = 50_000

    /// Display lines for one column and file, cached per applied result.
    /// Above `reducedModeThreshold` lines only hunks and three lines of
    /// context are shown (spec "Large or odd patches").
    func displayLines(column: PatchColumn, path: String) -> [DisplayLine] {
        let golden = goldenID.flatMap { id in id == column.id ? nil : columns.first { $0.id == id } }
        let key = "\(column.id.uuidString)|\(path)|\(showRemovedLines)|\(column.applied == nil)|\(golden?.id.uuidString ?? "base")"
        if let cached = displayCache[key] { return cached }
        guard let file = renderedFile(column: column, path: path) else { return [] }
        var lines: [DisplayLine]
        if file.status.isFailure {
            lines = Self.rawHunkLines(file.change)
        } else if let golden, let rendering = goldenRendering(golden: golden, column: column, path: path, file: file) {
            lines = rendering.lines
            if lines.count > Self.reducedModeThreshold { lines = Self.reduced(lines) }
        } else {
            lines = file.displayLines(includeRemoved: showRemovedLines)
            if lines.count > Self.reducedModeThreshold { lines = Self.reduced(lines) }
        }
        displayCache[key] = lines
        return lines
    }

    /// `column` against the golden column's post text (FR-21), cached
    /// per (file, column, golden) and dropped when the golden changes.
    func goldenRendering(golden: PatchColumn, column: PatchColumn, path: String, file: AppliedFile? = nil) -> GoldenRenderer.Rendering? {
        let key = "\(golden.id.uuidString)|\(column.id.uuidString)|\(path)|\(showRemovedLines)"
        if let cached = goldenCache[key] { return cached }
        guard let goldenFile = renderedFile(column: golden, path: path), !goldenFile.status.isFailure,
              let ownFile = file ?? renderedFile(column: column, path: path), !ownFile.status.isFailure else { return nil }
        let rendering = GoldenRenderer.render(reference: goldenFile.postText ?? "", text: ownFile.postText ?? "", includeRemoved: showRemovedLines)
        goldenCache[key] = rendering
        return rendering
    }

    /// Which line number is the shared frame for `column`: its own post
    /// line when it is golden, otherwise `baseLine` (base, or golden post).
    func usesPostLineFrame(_ columnID: UUID) -> Bool { goldenID == columnID }

    func setGolden(_ id: UUID?) {
        goldenID = (goldenID == id) ? nil : id
        goldenCache = [:]
        displayCache = [:]
        comparedRegion = nil
        anchors = [:]
        if let goldenID, let column = columns.first(where: { $0.id == goldenID }) {
            statusMessage = String(localized: "Golden: \(column.label) (\(column.sourceName))")
        } else {
            statusMessage = String(localized: "Golden cleared; columns render against the base.")
        }
    }

    /// Files and lines that differ from the golden column (FR-24).
    func goldenSummary(for column: PatchColumn) -> (files: Int, lines: Int)? {
        guard let goldenID, goldenID != column.id, let golden = columns.first(where: { $0.id == goldenID }), column.applied != nil else { return nil }
        var files = 0, lines = 0
        for row in allRows {
            guard let rendering = goldenRendering(golden: golden, column: column, path: row.path) else { continue }
            if !rendering.isIdentical { files += 1; lines += rendering.insertedCount + rendering.deletedCount }
        }
        return (files, lines)
    }

    /// A failed file stays visible with its raw hunks (FR-3).
    static func rawHunkLines(_ change: FileChange) -> [DisplayLine] {
        var out: [DisplayLine] = []
        for hunk in change.hunks {
            out.append(DisplayLine(kind: .context, baseLine: nil, postLine: nil,
                                   text: "@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@ \(hunk.sectionHeading ?? "")"))
            for line in hunk.numberedLines {
                let kind: DisplayLine.Kind = line.line.kind == .added ? .added : line.line.kind == .removed ? .removed : .context
                out.append(DisplayLine(kind: kind, baseLine: line.oldNumber, postLine: line.newNumber, text: line.line.text))
            }
        }
        return out
    }

    static func reduced(_ lines: [DisplayLine], context: Int = 3) -> [DisplayLine] {
        var keep = [Bool](repeating: false, count: lines.count)
        for (i, line) in lines.enumerated() where line.kind != .context {
            for j in max(0, i - context)...min(lines.count - 1, i + context) { keep[j] = true }
        }
        var out: [DisplayLine] = []
        var skipped = 0
        for (i, line) in lines.enumerated() {
            if keep[i] {
                if skipped > 0 {
                    out.append(DisplayLine(kind: .context, baseLine: nil, postLine: nil, text: "··· \(skipped) " + String(localized: "unchanged lines") + " ···"))
                    skipped = 0
                }
                out.append(line)
            } else {
                skipped += 1
            }
        }
        if skipped > 0 {
            out.append(DisplayLine(kind: .context, baseLine: nil, postLine: nil, text: "··· \(skipped) " + String(localized: "unchanged lines") + " ···"))
        }
        return out
    }

    // MARK: - Selection and references (MISSION.md §3)

    var focusedColumn: PatchColumn? {
        columns.first { $0.id == focusedColumnID } ?? visibleColumns.first
    }

    /// The reference for the focused column's selection, or `nil`.
    func currentReference() -> LineReference? {
        guard let column = focusedColumn, let path = selectedPath,
              let range = selections[column.id] else { return nil }
        let lines = displayLines(column: column, path: path)
        guard !lines.isEmpty else { return nil }
        let clamped = max(0, range.lowerBound)..<min(lines.count, max(range.upperBound, range.lowerBound + 1))
        guard clamped.lowerBound < clamped.upperBound else { return nil }
        let fileName = (path as NSString).lastPathComponent
        return LineReference.forDisplayLines(lines[clamped], fileName: fileName)
    }

    func copyReference() {
        guard let reference = currentReference() else {
            statusMessage = String(localized: "Select lines in a column first.")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reference.description, forType: .string)
        statusMessage = String(localized: "Copied \(reference.description)")
    }

    // MARK: - Navigation

    func focusColumn(index: Int) {
        let visible = visibleColumns
        guard index < visible.count else { return }
        focusedColumnID = visible[index].id
        scrollSync.focus(visible[index].id)
    }

    /// Scroll the focused column to the next (or previous) hunk from
    /// the top of its selection or view (keyboard `]` / `[`).
    func jumpHunk(forward: Bool) {
        guard let column = focusedColumn, let path = selectedPath else { return }
        let lines = displayLines(column: column, path: path)
        let current = selections[column.id]?.lowerBound ?? scrollSync.topLine(of: column.id) ?? 0
        // Hunk starts: first changed line after a context line.
        var starts: [Int] = []
        for (i, line) in lines.enumerated() where line.kind != .context && (i == 0 || lines[i - 1].kind == .context) {
            starts.append(i)
        }
        let target = forward ? starts.first { $0 > current } : starts.last { $0 < current }
        guard let target else { return }
        bumpScroll(columnID: column.id, displayLine: target)
        selections[column.id] = target..<target + 1
    }

    func bumpScroll(columnID: UUID, displayLine: Int) {
        scrollGeneration += 1
        scrollRequests[columnID] = ScrollRequest(displayLine: displayLine, generation: scrollGeneration)
    }

    func moveColumn(_ id: UUID, by delta: Int) {
        guard let i = columns.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard j >= 0, j < columns.count else { return }
        columns.swapAt(i, j)
    }

    func toggleHidden(_ id: UUID) {
        guard let i = columns.firstIndex(where: { $0.id == id }) else { return }
        columns[i].isHidden.toggle()
    }

    func toggleRead(_ id: UUID) {
        guard let i = columns.firstIndex(where: { $0.id == id }) else { return }
        columns[i].isRead.toggle()
    }
}

extension LineMap {
    /// Every post line is its own base line: the map of an untouched file.
    static func identity(lineCount: Int) -> LineMap {
        var map = LineMap.empty
        map.postToBase = (0..<lineCount).map { $0 + 1 }
        map.baseToPost = map.postToBase
        return map
    }
}
