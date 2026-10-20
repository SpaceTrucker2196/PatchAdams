import SwiftUI
import UniformTypeIdentifiers

/// The slot above a column (issue #7, FR-2): drop a patch file on it or
/// click it to choose one. On a filled column it replaces that column's
/// patch and keeps its label; the add slot puts a new patch in the next
/// free label.
struct PatchSlot: View {
    enum Role: Equatable {
        case replace(UUID)
        case add
    }

    let role: Role
    @Bindable var controller: SessionController
    @State private var isTargeted = false
    @State private var pendingURL: URL?

    private var column: PatchColumn? {
        if case .replace(let id) = role { return controller.columns.first { $0.id == id } }
        return nil
    }

    private var findingCount: Int {
        guard let column else { return 0 }
        return controller.findings.filter { $0.label == column.label }.count
    }

    private var title: String {
        if let column { return String(localized: "Drop a patch to replace \(controller.displayLabel(column))") }
        return String(localized: "Add a patch")
    }

    var body: some View {
        Button {
            if let url = SessionActions.chooseOnePatch() { take(url) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: role == .add ? "plus.rectangle.on.rectangle" : "arrow.down.doc")
                Text(title).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                Text(String(localized: "or click")).foregroundStyle(.tertiary)
            }
            .font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 5).fill(isTargeted ? Color.accentColor.opacity(0.2) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 5)
                .strokeBorder(style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: [4]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.6)))
        }
        .buttonStyle(.plain)
        .help(column.map { String(localized: "Replace \(controller.displayName($0)) with another patch file. Click to choose one, or drop it here.") }
              ?? String(localized: "Add a patch file. Click to choose one, or drop it here."))
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: SessionActions.isPatchFile) else { return false }
            take(url)
            return true
        } isTargeted: { isTargeted = $0 }
        .confirmationDialog(String(localized: "Replace this patch?"), isPresented: Binding(get: { pendingURL != nil }, set: { if !$0 { pendingURL = nil } })) {
            Button(String(localized: "Replace"), role: .destructive) {
                if let url = pendingURL, let column { controller.replacePatch(columnID: column.id, url: url) }
                pendingURL = nil
            }
            Button(String(localized: "Cancel"), role: .cancel) { pendingURL = nil }
        } message: {
            Text(String(localized: "\(findingCount) finding(s) point at lines of the patch in this column. Replacing it removes them, with its pins and its rank."))
        }
        .accessibilityLabel(title)
    }

    private func take(_ url: URL) {
        switch role {
        case .add:
            controller.addPatch(url: url)
        case .replace(let id):
            if findingCount > 0 { pendingURL = url } else { controller.replacePatch(columnID: id, url: url) }
        }
    }
}
