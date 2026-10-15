import SwiftUI
import PatchModel
import BaseLoader
import ApplyEngine
import AlignmentEngine
import SessionModel

// Phase 4: findings, ranking, export, session save and load, blind
// mode, manual anchors (FR-5, FR-12, FR-18, FR-25 to FR-35).

/// A finding being written or edited in the sheet (FR-25).
struct FindingDraft: Identifiable, Hashable {
    var id: UUID { finding.id }
    var finding: Finding
    var isNew: Bool
    /// Set when the draft is a template copied from another column (FR-29).
    var templateOf: String?
}

/// The findings list filters (FR-27). `nil` means "any".
struct FindingFilter: Hashable {
    var label: String?
    var path: String?
    var category: String?
    var severity: Severity?
    var includeNotFlagged = true

    var isActive: Bool { label != nil || path != nil || category != nil || severity != nil || !includeNotFlagged }

    func admits(_ finding: Finding) -> Bool {
        (label == nil || finding.label == label) && (path == nil || finding.path == path)
            && (category == nil || finding.category == category) && (severity == nil || finding.severity == severity)
            && (includeNotFlagged || !finding.notFlagged)
    }
}

extension SessionController {

    // MARK: - Labels (FR-12)

    /// Label → blind number when blind mode is on.
    var blindMapping: [String: Int] { blind.isOn ? blind.mapping(for: columns.map(\.label)) : [:] }

    /// What the window shows for a column: `A`, or `2` in blind mode.
    func displayLabel(_ column: PatchColumn) -> String { displayLabel(column.label) }

    func displayLabel(_ label: String) -> String {
        if let n = blindMapping[label] { return String(n) }
        return label
    }

    /// The patch file name, or a neutral name in blind mode so the file
    /// name cannot give the patch away.
    func displayName(_ column: PatchColumn) -> String {
        blind.isOn ? String(localized: "Patch \(displayLabel(column))") : column.sourceName
    }

    /// Turn blind mode on (seeding it the first time and putting the
    /// columns in the shuffled order) or off. The seed is kept so the
    /// session reopens to the same numbers (MISSION.md §8).
    func toggleBlind() {
        if blind.isOn {
            blind.isOn = false
            statusMessage = String(localized: "Blind mode off: labels show as letters again.")
        } else {
            if blind.seed == 0 { blind.seed = UInt64.random(in: 1...UInt64.max) }
            blind.isOn = true
            let mapping = blind.mapping(for: columns.map(\.label))
            columns.sort { (mapping[$0.label] ?? 0) < (mapping[$1.label] ?? 0) }
            statusMessage = String(localized: "Blind mode: columns are numbered in a shuffled order; the export reveals the mapping.")
        }
        isDirty = true
    }

    // MARK: - Findings (FR-25 to FR-30)

    var filteredFindings: [Finding] { findings.filter { findingFilter.admits($0) } }

    func findings(in columnID: UUID, path: String) -> [Finding] {
        guard let label = columns.first(where: { $0.id == columnID })?.label else { return [] }
        return findings.filter { $0.label == label && $0.path == path }
    }

    /// ⌘N: a draft prefilled from the focused selection — label, file,
    /// reference, and the anchors the comparison already computed.
    func newFindingFromSelection() {
        guard let column = focusedColumn, let path = selectedPath, let range = selections[column.id],
              selectionIsEmpty[column.id] != true else {
            statusMessage = String(localized: "Select lines in a column first.")
            return
        }
        let lines = displayLines(column: column, path: path)
        let clamped = max(0, range.lowerBound)..<min(lines.count, range.upperBound)
        guard !clamped.isEmpty, let reference = LineReference.forDisplayLines(lines[clamped], fileName: (path as NSString).lastPathComponent) else { return }
        var finding = Finding(label: column.label, path: path, lines: LineSpan(clamped), reference: reference.description,
                              title: "", category: categories.first ?? "other", severity: .minor)
        if comparedRegion == SelectionRegion(columnID: column.id, path: path, lines: clamped) {
            finding.anchors = findingAnchors(path: path)
        }
        findingDraft = FindingDraft(finding: finding, isNew: true, templateOf: nil)
    }

    /// The current anchors as the finding will record them (FR-33).
    func findingAnchors(path: String) -> [FindingAnchor] {
        visibleColumns.compactMap { column in
            guard let anchor = anchors[column.id] else { return nil }
            let lines = displayLines(column: column, path: path)
            let reference = anchor.lines.isEmpty ? nil
                : LineReference.forDisplayLines(lines[anchor.lines.clamped(to: 0..<lines.count)], fileName: (path as NSString).lastPathComponent)?.description
            return FindingAnchor(label: column.label, status: anchor.status.rawValue, confidence: anchor.confidence, reference: reference)
        }
    }

    func edit(_ finding: Finding) {
        findingDraft = FindingDraft(finding: finding, isNew: false, templateOf: nil)
    }

    /// "Same issue in C?" (FR-29): the finding's region located in
    /// `columnID`, as a draft the reviewer confirms.
    func copyFindingAsTemplate(_ finding: Finding, to columnID: UUID) {
        guard let source = columns.first(where: { $0.label == finding.label }), let target = columns.first(where: { $0.id == columnID }) else { return }
        let sourceLines = displayLines(column: source, path: finding.path)
        let targetLines = displayLines(column: target, path: finding.path)
        let hunks = renderedFile(column: target, path: finding.path)?.hunks ?? []
        let sourcePostKeyed = usesPostLineFrame(source.id), targetPostKeyed = usesPostLineFrame(target.id)
        Task {
            let located = await engines.locate(finding.lines.range, source: sourceLines, sourcePostKeyed: sourcePostKeyed,
                                               targets: [(target.id, targetLines, targetPostKeyed, hunks)])
            guard let anchor = located[target.id] else { return }
            let lines = anchor.lines.isEmpty ? anchor.lines.lowerBound..<min(targetLines.count, anchor.lines.lowerBound + 1) : anchor.lines
            let reference = lines.isEmpty ? "" : LineReference.forDisplayLines(targetLines[lines.clamped(to: 0..<targetLines.count)], fileName: (finding.path as NSString).lastPathComponent)?.description ?? ""
            var copy = finding
            copy.id = UUID()
            copy.label = target.label
            copy.lines = LineSpan(lines)
            copy.reference = reference
            copy.anchors = []
            copy.created = Date()
            findingDraft = FindingDraft(finding: copy, isNew: true, templateOf: "\(anchor.status.rawValue) \(Int((anchor.confidence * 100).rounded()))%")
            selectedPath = finding.path
            selections[target.id] = lines
            selectionIsEmpty[target.id] = lines.isEmpty
            scrollTo(columnID: target.id, displayLine: lines.lowerBound)
        }
    }

    func saveDraft() {
        guard let draft = findingDraft, draft.finding.isComplete else { return }
        if let i = findings.firstIndex(where: { $0.id == draft.finding.id }) {
            findings[i] = draft.finding
        } else {
            findings.append(draft.finding)
        }
        findingDraft = nil
        isDirty = true
        statusMessage = String(localized: "Finding \(draft.isNew ? "added" : "updated"): \(draft.finding.reference)")
    }

    func deleteFinding(_ id: UUID) {
        findings.removeAll { $0.id == id }
        isDirty = true
    }

    func toggleNotFlagged(_ id: UUID) {
        guard let i = findings.firstIndex(where: { $0.id == id }) else { return }
        findings[i].notFlagged.toggle()
        isDirty = true
    }

    /// Clicking a finding scrolls its column there and locates the
    /// region in the others (FR-28).
    func goTo(finding: Finding) {
        guard let column = columns.first(where: { $0.label == finding.label }) else { return }
        selectedPath = finding.path
        selections[column.id] = finding.lines.range
        selectionIsEmpty[column.id] = false
        if column.isHidden { toggleHidden(column.id) }
        scrollTo(columnID: column.id, displayLine: finding.lines.lower)
        locate(SelectionRegion(columnID: column.id, path: finding.path, lines: finding.lines.range))
    }

    /// `}` and `{`: the next or previous finding in the focused column.
    func jumpFinding(forward: Bool) {
        guard let column = focusedColumn, let path = selectedPath else { return }
        let mine = findings(in: column.id, path: path).sorted { $0.lines.lower < $1.lines.lower }
        guard !mine.isEmpty else { statusMessage = String(localized: "No findings in \(displayLabel(column)) for this file."); return }
        let current = selections[column.id]?.lowerBound ?? -1
        let target = forward ? (mine.first { $0.lines.lower > current } ?? mine.first) : (mine.last { $0.lines.lower < current } ?? mine.last)
        if let target { goTo(finding: target) }
    }

    /// One finding in the export's bullet form (FR-34).
    func copyFinding(_ finding: Finding) {
        let text = "\(displayLabel(finding.label)) " + MarkdownExport.bulletText(finding)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusMessage = String(localized: "Copied finding \(finding.reference)")
    }

    // MARK: - Ranking (FR-31)

    func setRank(_ rank: Int?, for label: String) {
        ranking.ranks[label] = rank
        isDirty = true
    }

    // MARK: - Manual anchors (FR-18)

    /// Replace the engine's anchor in `columnID` for the compared region
    /// with the reviewer's own selection there. Remembered for the session
    /// and saved with it; wins over the engine on reload.
    func useSelectionAsAnchor(columnID: UUID) {
        guard let region = comparedRegion, let source = columns.first(where: { $0.id == region.columnID }),
              let target = columns.first(where: { $0.id == columnID }), let lines = selections[columnID], !lines.isEmpty else {
            statusMessage = String(localized: "Select the matching lines in that column first.")
            return
        }
        manualAnchors.removeAll { $0.matches(sourceLabel: source.label, path: region.path, sourceLines: region.lines) && $0.targetLabel == target.label }
        manualAnchors.append(ManualAnchor(sourceLabel: source.label, path: region.path, sourceLines: LineSpan(region.lines),
                                          targetLabel: target.label, targetLines: LineSpan(lines)))
        isDirty = true
        locate(region)
        statusMessage = String(localized: "Anchor in \(displayLabel(target)) set by hand.")
    }

    func clearManualAnchor(columnID: UUID) {
        guard let region = comparedRegion, let source = columns.first(where: { $0.id == region.columnID }),
              let target = columns.first(where: { $0.id == columnID }) else { return }
        manualAnchors.removeAll { $0.matches(sourceLabel: source.label, path: region.path, sourceLines: region.lines) && $0.targetLabel == target.label }
        isDirty = true
        locate(region)
    }

    /// The reviewer's override for `region` in `columnID`, as the engine
    /// would report it, or `nil`.
    func manualAnchor(for region: SelectionRegion, in columnID: UUID) -> RegionAnchor? {
        guard let source = columns.first(where: { $0.id == region.columnID }), let target = columns.first(where: { $0.id == columnID }),
              let manual = manualAnchors.first(where: { $0.matches(sourceLabel: source.label, path: region.path, sourceLines: region.lines) && $0.targetLabel == target.label }) else { return nil }
        let sourceText = displayLines(column: source, path: region.path)[region.lines.clamped(to: 0..<displayLines(column: source, path: region.path).count)].map(\.text)
        let targetLines = displayLines(column: target, path: region.path)
        let targetText = targetLines[manual.targetLines.range.clamped(to: 0..<targetLines.count)].map(\.text)
        let same = sourceText.map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") } == targetText.map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        return RegionAnchor(status: same ? .exact : .modified, confidence: 1, lines: manual.targetLines.range, nearestHunk: nil, tokenDiff: nil, viaIdentifier: "manual")
    }

    func hasManualAnchor(columnID: UUID) -> Bool {
        guard let region = comparedRegion else { return false }
        return manualAnchor(for: region, in: columnID) != nil
    }

    // MARK: - Session record (FR-5, FR-35)

    var basePointer: BasePointer {
        switch base?.origin {
        case .directory(let url)?: return BasePointer(kind: .directory, path: url.path)
        case .archive(let url)?: return BasePointer(kind: .archive, path: url.path)
        case .gitRevision(let repository, let revision, let commit)?: return BasePointer(kind: .gitRevision, path: repository.path, revision: revision, commit: commit)
        case .inMemory(let label)?: return BasePointer(kind: .synthetic, label: label)
        case nil: return .synthetic
        }
    }

    func makeSession() -> Session {
        Session(name: sessionName, request: requestText, base: basePointer,
                columns: columns.map { SessionColumn(label: $0.label, sourceName: $0.sourceName, patchFile: "", isHidden: $0.isHidden, isRead: $0.isRead) },
                golden: goldenID.flatMap { id in columns.first { $0.id == id }?.label },
                categories: categories, findings: findings, ranking: ranking,
                pins: pins.compactMap { pin in
                    columns.first { $0.id == pin.region.columnID }.map {
                        SessionPin(id: pin.id, label: $0.label, path: pin.region.path, lines: LineSpan(pin.region.lines), reference: pin.reference, snippet: pin.snippet)
                    }
                },
                manualAnchors: manualAnchors, blind: blind, created: sessionStart)
    }

    func packageContents() -> SessionPackage.Contents {
        SessionPackage.Contents(session: makeSession(), patchTexts: Dictionary(uniqueKeysWithValues: columns.map { ($0.label, $0.sourceText) }))
    }

    /// Write the `.patchadam` package. The one place the app writes files.
    func save(to url: URL) {
        do {
            if sessionName.isEmpty { sessionName = url.deletingPathExtension().lastPathComponent }
            try SessionPackage.write(packageContents(), to: url)
            sessionURL = url
            isDirty = false
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
            statusMessage = String(localized: "Saved \(url.lastPathComponent)")
        } catch {
            errorMessage = "\(error)"
        }
    }

    /// Restore a saved session: patches in their saved order and labels,
    /// the base from its pointer (synthetic when the pointer is gone),
    /// then everything the reviewer wrote.
    func open(sessionURL url: URL) {
        let contents: SessionPackage.Contents
        do { contents = try SessionPackage.read(from: url) } catch { errorMessage = "\(error)"; return }
        let session = contents.session
        newSession()
        for column in session.columns {
            guard let text = contents.patchTexts[column.label] else { continue }
            addPatch(text: text, name: column.sourceName, label: column.label)
            if let i = columns.firstIndex(where: { $0.label == column.label }) {
                columns[i].isHidden = column.isHidden
                columns[i].isRead = column.isRead
            }
        }
        switch session.base.kind {
        case .synthetic:
            useSyntheticBase()
        case .directory, .archive, .gitRevision:
            if let path = session.base.path, FileManager.default.fileExists(atPath: path) {
                openBase(url: URL(fileURLWithPath: path), revision: session.base.commit ?? session.base.revision)
            } else {
                useSyntheticBase()
                statusMessage = String(localized: "The base at \(session.base.path ?? "?") is gone; showing a base rebuilt from the patches.")
            }
        }
        sessionName = session.name
        sessionURL = url
        requestText = session.request
        showRequestPanel = false
        categories = session.categories
        findings = session.findings
        ranking = session.ranking
        manualAnchors = session.manualAnchors
        blind = session.blind
        goldenID = session.golden.flatMap { label in columns.first { $0.label == label }?.id }
        pins = session.pins.compactMap { pin in
            columns.first { $0.label == pin.label }.map {
                Pin(id: pin.id, region: SelectionRegion(columnID: $0.id, path: pin.path, lines: pin.lines.range), label: $0.label, reference: pin.reference, snippet: pin.snippet)
            }
        }
        sessionStart = session.created
        isDirty = false
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        statusMessage = String(localized: "Opened \(url.lastPathComponent): \(findings.count) findings")
    }

    // MARK: - Export (FR-32, FR-33)

    func markdownExport() -> String { MarkdownExport.render(makeSession()) }

    func jsonExport() throws -> Data { try JSONExport.render(makeSession()) }

    func copyMarkdown() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdownExport(), forType: .string)
        statusMessage = String(localized: "Copied the Markdown write-up (\(findings.count) findings).")
    }

    func write(export data: Data, to url: URL) {
        do {
            try data.write(to: url, options: .atomic)
            statusMessage = String(localized: "Exported \(url.lastPathComponent)")
        } catch {
            errorMessage = "\(error)"
        }
    }
}

extension Range where Bound == Int {
    func clamped(to limits: Range<Int>) -> Range<Int> {
        let lo = Swift.min(Swift.max(lowerBound, limits.lowerBound), limits.upperBound)
        let hi = Swift.min(Swift.max(upperBound, lo), limits.upperBound)
        return lo..<hi
    }
}
