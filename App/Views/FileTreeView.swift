import SwiftUI

/// The shared file tree (FR-8): every file any patch touches, one chip
/// per patch, a filter box and a tests-only switch. Selecting a row
/// opens the file in every column at once.
struct FileTreeView: View {
    @Bindable var controller: SessionController

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField(String(localized: "Filter files"), text: $controller.filterText)
                    .textFieldStyle(.roundedBorder)
                Toggle(isOn: $controller.testsOnly) {
                    Image(systemName: "testtube.2")
                }
                .toggleStyle(.button)
                .help(String(localized: "Show only test files"))
            }
            .padding(8)
            List(controller.fileRows, selection: $controller.selectedPath) { row in
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text((row.path as NSString).lastPathComponent)
                            .lineLimit(1)
                        Text((row.path as NSString).deletingLastPathComponent)
                            .font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.head)
                    }
                    Spacer(minLength: 2)
                    ForEach(controller.columns) { column in
                        chip(column.label, row.chips[column.id] ?? .unchanged)
                    }
                }
                .tag(row.path)
                .help(row.path)
            }
            .listStyle(.sidebar)
            Divider()
            legend
        }
    }

    private func chip(_ label: String, _ chip: FileChip) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .frame(width: 16, height: 16)
            .background(RoundedRectangle(cornerRadius: 3).fill(chip.color.opacity(chip == .unchanged ? 0.15 : 0.85)))
            .foregroundStyle(chip == .unchanged ? Color.secondary : .white)
            .help(chip.rawValue)
            .accessibilityLabel("\(label) \(chip.rawValue)")
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach([FileChip.changed, .added, .deleted, .failed, .unchanged], id: \.self) { chip in
                HStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 2).fill(chip.color.opacity(chip == .unchanged ? 0.3 : 0.85)).frame(width: 8, height: 8)
                    Text(chip.rawValue).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(6)
    }
}
