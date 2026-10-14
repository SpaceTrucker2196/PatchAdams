import SwiftUI
import ApplyEngine
import AlignmentEngine

// Phase 3: selection alignment, pins, search (FR-13 to FR-19).
extension SessionController {

    // MARK: - Selection → anchors

    /// Called by a column's text view whenever its selection changes.
    func setSelection(_ columnID: UUID, lines: Range<Int>, isEmpty: Bool) {
        selections[columnID] = lines
        selectionIsEmpty[columnID] = isEmpty
        focusedColumnID = columnID
        if isEmpty {
            if comparedRegion?.columnID == columnID { comparedRegion = nil; anchors = [:] }
            return
        }
        guard let path = selectedPath else { return }
        locate(SelectionRegion(columnID: columnID, path: path, lines: lines))
    }

    /// Locate a region in every other visible column, off the main actor.
    func locate(_ region: SelectionRegion) {
        guard let source = columns.first(where: { $0.id == region.columnID }) else { return }
        comparedRegion = region
        let sourceLines = displayLines(column: source, path: region.path)
        let targets: [(id: UUID, lines: [DisplayLine], postKeyed: Bool, hunks: [HunkPlacement])] = visibleColumns
            .filter { $0.id != region.columnID }
            .map { ($0.id, displayLines(column: $0, path: region.path), usesPostLineFrame($0.id), renderedFile(column: $0, path: region.path)?.hunks ?? []) }
        let sourcePostKeyed = usesPostLineFrame(region.columnID)
        locateGeneration += 1
        let generation = locateGeneration
        locateTask?.cancel()
        locateTask = Task {
            let result = await engines.locate(region.lines, source: sourceLines, sourcePostKeyed: sourcePostKeyed, targets: targets)
            guard !Task.isCancelled, generation == locateGeneration else { return }
            anchors = result
        }
    }

    func anchor(for columnID: UUID) -> RegionAnchor? {
        guard comparedRegion != nil, comparedRegion?.path == selectedPath else { return nil }
        return anchors[columnID]
    }

    /// `main.rs L94:L101` for an absent anchor's nearest hunk (FR-15).
    func nearestHunkReference(_ anchor: RegionAnchor, path: String) -> String? {
        guard let hunk = anchor.nearestHunk else { return nil }
        let name = (path as NSString).lastPathComponent
        let end = max(hunk.postStart, hunk.postStart + hunk.newLineCount - 1)
        return "\(name) L\(hunk.postStart):L\(end)"
    }

    /// Scroll a column to its nearest hunk for an absent region.
    func jumpToNearestHunk(columnID: UUID) {
        guard let anchor = anchor(for: columnID), let hunk = anchor.nearestHunk,
              let column = columns.first(where: { $0.id == columnID }), let path = selectedPath else { return }
        let lines = displayLines(column: column, path: path)
        let index = lines.firstIndex { $0.postLine == hunk.postStart } ?? anchor.lines.lowerBound
        scrollTo(columnID: columnID, displayLine: min(index, max(0, lines.count - 1)))
    }

    func scrollTo(columnID: UUID, displayLine: Int) {
        focusedColumnID = columnID
        bumpScroll(columnID: columnID, displayLine: displayLine)
    }

    /// Compare the located region in `columnID` back the other way, so
    /// the reviewer can walk anchor to anchor.
    func makeAnchorTheSelection(columnID: UUID) {
        guard let anchor = anchor(for: columnID), !anchor.lines.isEmpty, let path = selectedPath else { return }
        selections[columnID] = anchor.lines
        selectionIsEmpty[columnID] = false
        scrollTo(columnID: columnID, displayLine: anchor.lines.lowerBound)
        locate(SelectionRegion(columnID: columnID, path: path, lines: anchor.lines))
    }

    // MARK: - Pins (FR-17)

    func pinSelection() {
        guard let column = focusedColumn, let path = selectedPath, let range = selections[column.id],
              selectionIsEmpty[column.id] != true else {
            statusMessage = String(localized: "Select lines in a column first.")
            return
        }
        let lines = displayLines(column: column, path: path)
        let clamped = max(0, range.lowerBound)..<min(lines.count, range.upperBound)
        guard !clamped.isEmpty else { return }
        let reference = LineReference.forDisplayLines(lines[clamped], fileName: (path as NSString).lastPathComponent)?.description ?? ""
        let snippet = lines[clamped].first?.text.trimmingCharacters(in: .whitespaces) ?? ""
        let pin = Pin(id: UUID(), region: SelectionRegion(columnID: column.id, path: path, lines: clamped),
                      label: column.label, reference: reference, snippet: snippet)
        pins.append(pin)
        showPins = true
        statusMessage = String(localized: "Pinned \(pin.label) \(pin.reference)")
    }

    func removePin(_ id: UUID) { pins.removeAll { $0.id == id } }

    func goTo(pin: Pin) {
        selectedPath = pin.region.path
        selections[pin.region.columnID] = pin.region.lines
        selectionIsEmpty[pin.region.columnID] = false
        scrollTo(columnID: pin.region.columnID, displayLine: pin.region.lines.lowerBound)
        locate(pin.region)
    }

    func pins(in columnID: UUID, path: String) -> [Pin] {
        pins.filter { $0.region.columnID == columnID && $0.region.path == path }
    }

    // MARK: - Search (FR-19)

    /// Search every file of every visible column; results group by file,
    /// then column, with references.
    func runSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { searchResults = []; return }
        var groups: [SearchGroup] = []
        for row in allRows {
            var columnsHits: [SearchColumnHits] = []
            for column in visibleColumns where column.applied != nil {
                let lines = displayLines(column: column, path: row.path)
                let name = (row.path as NSString).lastPathComponent
                var hits: [SearchHit] = []
                for (i, line) in lines.enumerated() where line.text.localizedCaseInsensitiveContains(query) {
                    let reference = LineReference.forDisplayLines(lines[i..<i + 1], fileName: name)?.description ?? name
                    hits.append(SearchHit(columnID: column.id, displayIndex: i, text: line.text.trimmingCharacters(in: .whitespaces), reference: reference))
                }
                if !hits.isEmpty { columnsHits.append(SearchColumnHits(columnID: column.id, label: column.label, hits: hits)) }
            }
            if !columnsHits.isEmpty { groups.append(SearchGroup(path: row.path, columns: columnsHits)) }
        }
        searchResults = groups
        showSearch = true
        let total = groups.reduce(0) { $0 + $1.count }
        statusMessage = String(localized: "\(total) hits for “\(query)” in \(groups.count) files")
    }

    func goTo(hit: SearchHit, path: String) {
        selectedPath = path
        selections[hit.columnID] = hit.displayIndex..<hit.displayIndex + 1
        selectionIsEmpty[hit.columnID] = false
        scrollTo(columnID: hit.columnID, displayLine: hit.displayIndex)
    }
}
