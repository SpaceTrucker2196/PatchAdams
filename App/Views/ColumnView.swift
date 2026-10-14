import SwiftUI
import ApplyEngine

/// One patch column: header with label *and* patch file name (FR-4),
/// then the code view for the selected file.
struct ColumnView: View {
    let column: PatchColumn
    @Bindable var controller: SessionController

    private var path: String? { controller.selectedPath }
    private var file: AppliedFile? { path.flatMap { controller.renderedFile(column: column, path: $0) } }
    private var isFocused: Bool { controller.focusedColumnID == column.id }

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
            Text(column.label)
                .font(.system(.headline, design: .rounded)).bold()
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(labelColor))
                .foregroundStyle(.white)
                .fixedSize()
            Text(column.sourceName)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 60, alignment: .leading)
                .layoutPriority(1)
                .help(column.sourceName)
            Spacer(minLength: 4)
            ViewThatFits(in: .horizontal) {
                statusChip
                statusDot
            }
            Menu {
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

    private var labelColor: Color {
        switch column.label {
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
                CodeTextView(columnID: column.id, lines: lines,
                             contentKey: "\(column.id)|\(path)|\(controller.showRemovedLines)|\(lines.count)|\(file?.status.label ?? "")",
                             scrollRequest: controller.scrollRequests[column.id],
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
