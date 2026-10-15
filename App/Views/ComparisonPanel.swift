import SwiftUI
import DiffEngine
import AlignmentEngine

/// One pane per other column: the selected region against the located
/// region as a word-level diff (FR-16). Collapsible. The pane header
/// carries the status badge and, for `absent`, the nearest-hunk link.
struct ComparisonPanel: View {
    @Bindable var controller: SessionController

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Comparison")).font(.headline)
                if let region = controller.comparedRegion, let source = controller.columns.first(where: { $0.id == region.columnID }) {
                    Text(String(localized: "\(controller.displayLabel(source)) · \((region.path as NSString).lastPathComponent) · \(region.lines.count) lines"))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(String(localized: "Select lines in a column to compare them with the other columns."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { controller.showComparison = false } label: { Image(systemName: "chevron.down") }.buttonStyle(.plain)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            if let region = controller.comparedRegion {
                HStack(alignment: .top, spacing: 2) {
                    ForEach(controller.visibleColumns.filter { $0.id != region.columnID }) { column in
                        pane(column: column, path: region.path)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(height: 170)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func pane(column: PatchColumn, path: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(controller.displayLabel(column)).font(.caption.bold())
                Text(controller.displayName(column)).font(.caption).lineLimit(1).truncationMode(.middle)
                Spacer()
                // FR-18: the reviewer's own selection in this column replaces the engine's anchor.
                if controller.hasManualAnchor(columnID: column.id) {
                    Button(String(localized: "Clear manual anchor")) { controller.clearManualAnchor(columnID: column.id) }
                        .buttonStyle(.link).font(.caption)
                } else if controller.selectionIsEmpty[column.id] == false, controller.selections[column.id] != nil {
                    Button(String(localized: "Use selection as anchor")) { controller.useSelectionAsAnchor(columnID: column.id) }
                        .buttonStyle(.link).font(.caption)
                        .help(String(localized: "Remember the selected lines here as the match for the compared region (FR-18)"))
                }
                if let anchor = controller.anchor(for: column.id) {
                    Text(anchor.status == .absent ? anchor.status.rawValue : "\(anchor.status.rawValue) \(Int((anchor.confidence * 100).rounded()))%")
                        .font(.caption.bold())
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: CodeStyle.anchorColor(anchor.status))))
                } else {
                    ProgressView().controlSize(.mini)
                }
            }
            if let anchor = controller.anchor(for: column.id) {
                if anchor.status == .absent {
                    if let reference = controller.nearestHunkReference(anchor, path: path) {
                        Button(String(localized: "No matching change. Nearest hunk: \(reference)")) { controller.jumpToNearestHunk(columnID: column.id) }
                            .buttonStyle(.link).font(.caption)
                    } else {
                        Text(String(localized: "No matching change, and no hunk in this file.")).font(.caption).foregroundStyle(.secondary)
                    }
                } else if let diff = anchor.tokenDiff {
                    ScrollView {
                        Text(Self.render(diff))
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(6)
        .background(Color(nsColor: .textBackgroundColor))
    }

    /// Inline token diff: deleted tokens red and struck, inserted green.
    static func render(_ diff: TokenDiff) -> AttributedString {
        var out = AttributedString()
        for edit in diff.edits {
            switch edit.kind {
            case .equal:
                out += AttributedString(diff.a[edit.a].joined())
            case .delete:
                var run = AttributedString(diff.a[edit.a].joined())
                run.backgroundColor = Color.red.opacity(0.3)
                run.strikethroughStyle = .single
                out += run
            case .insert:
                var run = AttributedString(diff.b[edit.b].joined())
                run.backgroundColor = Color.green.opacity(0.3)
                out += run
            }
        }
        return out
    }
}

/// Pinned selections (FR-17): stay highlighted, listed for return.
struct PinsSidebar: View {
    @Bindable var controller: SessionController

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Pins")).font(.headline)
                Spacer()
                Button { controller.showPins = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
            .padding(8)
            if controller.pins.isEmpty {
                Text(String(localized: "⌘P pins the current selection.")).font(.caption).foregroundStyle(.secondary).padding()
                Spacer()
            } else {
                List {
                    ForEach(controller.pins) { pin in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(controller.displayLabel(pin.label)).font(.caption.bold())
                                Text(pin.reference).font(.caption)
                                Spacer()
                                Button { controller.removePin(pin.id) } label: { Image(systemName: "pin.slash") }.buttonStyle(.plain)
                            }
                            Text(pin.snippet).font(.system(size: 10, design: .monospaced)).lineLimit(1).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { controller.goTo(pin: pin) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Cross-column search (FR-19): grouped by file, then column.
struct SearchPanel: View {
    @Bindable var controller: SessionController
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField(String(localized: "Search all columns"), text: $controller.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit { controller.runSearch() }
                Button(String(localized: "Search")) { controller.runSearch() }.keyboardShortcut(.defaultAction)
                Text(String(localized: "\(controller.searchResults.reduce(0) { $0 + $1.count }) hits in \(controller.searchResults.count) files"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { controller.showSearch = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
            .padding(8)
            List {
                ForEach(controller.searchResults) { group in
                    Section(header: Text("\(group.path)  (\(group.count))").font(.caption.bold())) {
                        ForEach(group.columns) { columnHits in
                            ForEach(columnHits.hits) { hit in
                                HStack(spacing: 6) {
                                    Text(controller.displayLabel(columnHits.label)).font(.caption.bold()).frame(width: 16)
                                    Text(hit.reference).font(.caption).frame(width: 190, alignment: .leading)
                                    Text(hit.text).font(.system(size: 10, design: .monospaced)).lineLimit(1)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { controller.goTo(hit: hit, path: group.path) }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .frame(height: 220)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { fieldFocused = true }
    }
}
