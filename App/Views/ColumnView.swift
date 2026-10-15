import SwiftUI
import ApplyEngine
import AlignmentEngine
import SessionModel

/// One patch column: header with label *and* patch file name (FR-4),
/// then the code view for the selected file.
struct ColumnView: View {
    let column: PatchColumn
    @Bindable var controller: SessionController

    private var path: String? { controller.selectedPath }
    private var file: AppliedFile? { path.flatMap { controller.renderedFile(column: column, path: $0) } }
    private var isFocused: Bool { controller.focusedColumnID == column.id }
    private var isGolden: Bool { controller.goldenID == column.id }
    private var anchor: RegionAnchor? { controller.anchor(for: column.id) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(isFocused ? Color.accentColor : Color.clear, lineWidth: 2)
                .padding(1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(controller.displayLabel(column) + (isGolden ? " ★" : ""))
                .font(.system(.headline, design: .rounded)).bold()
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(labelColor))
                .foregroundStyle(.white)
                .fixedSize()
                .help(isGolden ? String(localized: "Golden: other columns render against this one") : "")
            if let anchor {
                anchorBadge(anchor)
            }
            Text(controller.displayName(column))
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 60, alignment: .leading)
                .layoutPriority(1)
                .help(controller.displayName(column))
            Spacer(minLength: 4)
            ViewThatFits(in: .horizontal) {
                statusChip
                statusDot
            }
            Menu {
                Button(isGolden ? String(localized: "Clear Golden") : String(localized: "Set Golden")) { controller.setGolden(column.id) }
                Button(String(localized: "New Finding from Selection")) { controller.focusedColumnID = column.id; controller.newFindingFromSelection() }
                    .disabled(controller.selectionIsEmpty[column.id] != false)
                Divider()
                Button(column.isHidden ? String(localized: "Show") : String(localized: "Hide")) { controller.toggleHidden(column.id) }
                Button(String(localized: "Move Left")) { controller.moveColumn(column.id, by: -1) }
                Button(String(localized: "Move Right")) { controller.moveColumn(column.id, by: 1) }
                Divider()
                Toggle(String(localized: "Read"), isOn: Binding(get: { column.isRead }, set: { _ in controller.toggleRead(column.id) }))
                Divider()
                Button(String(localized: "Remove Patch"), role: .destructive) { controller.removeColumn(column.id) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Status badge of the located region (FR-14): colour and word.
    private func anchorBadge(_ anchor: RegionAnchor) -> some View {
        let text = anchor.status == .absent ? anchor.status.rawValue : "\(anchor.status.rawValue) \(Int((anchor.confidence * 100).rounded()))%"
        return Text(text)
            .font(.caption.bold())
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: CodeStyle.anchorColor(anchor.status))))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(style: StrokeStyle(lineWidth: anchor.status == .absent ? 1.5 : 0, dash: [3])).foregroundStyle(.red))
            .help(anchor.viaIdentifier.map { String(localized: "Matched by identifier \($0)") } ?? String(localized: "Matched by position"))
            .onTapGesture { controller.makeAnchorTheSelection(columnID: column.id) }
            .accessibilityLabel(text)
    }

    private var labelColor: Color {
        switch column.label {
        case _ where controller.blind.isOn: return .gray   // one colour for all in blind mode
        case "A": return .blue
        case "B": return .purple
        case "C": return .teal
        case "D": return .orange
        default: return .gray
        }
    }

    @ViewBuilder private var statusChip: some View {
        if column.isApplying {
            ProgressView().controlSize(.small)
        } else if let path, let change = column.patch.files.first(where: { $0.path == path || $0.oldPath == path }) {
            let status = file?.status.label ?? "—"
            let text = change.isBinary ? String(localized: "binary") : "\(change.kind.rawValue) · \(status)"
            Text(text)
                .font(.caption)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(chipColor(file?.status).opacity(0.18)))
                .foregroundStyle(chipColor(file?.status))
                .help(text)
        } else if path != nil {
            Text(String(localized: "not in this patch"))
                .font(.caption).lineLimit(1).fixedSize().foregroundStyle(.secondary)
        }
    }

    /// The chip, reduced to a dot when the column is narrow.
    @ViewBuilder private var statusDot: some View {
        if let path, column.patch.files.contains(where: { $0.path == path || $0.oldPath == path }) {
            Circle().fill(chipColor(file?.status)).frame(width: 8, height: 8)
                .help(file?.status.label ?? "")
        } else {
            Circle().stroke(Color.secondary).frame(width: 8, height: 8)
                .help(String(localized: "not in this patch"))
        }
    }

    /// "No matching change in B. Nearest hunk: main.rs L94:L101." (FR-15)
    private func absentNotice(_ anchor: RegionAnchor, path: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "xmark.rectangle").foregroundStyle(.red)
            Text(String(localized: "No matching change in \(controller.displayLabel(column))."))
            if let reference = controller.nearestHunkReference(anchor, path: path) {
                Button {
                    controller.jumpToNearestHunk(columnID: column.id)
                } label: {
                    Text(String(localized: "Nearest hunk: \(reference)"))
                }
                .buttonStyle(.link)
            }
            Spacer()
        }
        .font(.caption)
        .padding(6)
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(.red))
        .padding(4)
    }

    private func highlights(path: String) -> [LineHighlight] {
        var out: [LineHighlight] = []
        if let anchor {
            out.append(LineHighlight(lines: anchor.lines, kind: anchor.status == .absent ? .absentMarker : .anchor(anchor.status)))
        }
        for pin in controller.pins(in: column.id, path: path) {
            out.append(LineHighlight(lines: pin.region.lines, kind: .pin))
        }
        for finding in controller.findings(in: column.id, path: path) where !finding.notFlagged {
            out.append(LineHighlight(lines: finding.lines.range, kind: .finding(finding.severity)))
        }
        return out
    }

    private func chipColor(_ status: ApplyStatus?) -> Color {
        switch status {
        case .clean?: return .green
        case .fuzz?: return .yellow
        case .failed?: return .orange
        case .binary?: return .gray
        case nil: return .secondary
        }
    }

    @ViewBuilder private var content: some View {
        if let path, column.applied != nil {
            let lines = controller.displayLines(column: column, path: path)
            VStack(spacing: 0) {
                if let file, case .failed(let reason) = file.status {
                    Label(String(localized: "Did not apply: \(reason). Showing the raw hunks."), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.2))
                } else if let file, case .fuzz(let n) = file.status {
                    Label(String(localized: "Applied with fuzz \(n)."), systemImage: "exclamationmark.circle")
                        .font(.caption).padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.yellow.opacity(0.2))
                } else if let file, file.change.isBinary {
                    Text(String(localized: "Binary file; nothing to show."))
                        .foregroundStyle(.secondary).padding()
                }
                if lines.count > SessionController.reducedModeThreshold {
                    Text(String(localized: "Reduced mode: hunks only (\(lines.count) lines)."))
                        .font(.caption).foregroundStyle(.secondary).padding(4)
                }
                if let anchor, anchor.status == .absent {
                    absentNotice(anchor, path: path)
                }
                CodeTextView(columnID: column.id, lines: lines,
                             contentKey: "\(column.id)|\(path)|\(controller.showRemovedLines)|\(lines.count)|\(file?.status.label ?? "")|\(controller.goldenID?.uuidString ?? "")",
                             scrollRequest: controller.scrollRequests[column.id],
                             highlights: highlights(path: path),
                             controller: controller)
            }
        } else if path == nil {
            ContentUnavailableView(String(localized: "Select a file"), systemImage: "doc.text", description: Text(String(localized: "Pick a file in the tree to open it in every column.")))
        } else {
            ProgressView(String(localized: "Applying…"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
