import SwiftUI
import UniformTypeIdentifiers

/// Shown until the session has a base and at least two patches
/// (FR-1, FR-2). Patches arrive by picker, drag-and-drop, or paste.
struct WelcomeView: View {
    @Bindable var controller: SessionController
    @State private var isTargeted = false
    @State private var showGitSheet = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "rectangle.split.3x1")
                .font(.system(size: 44)).foregroundStyle(.secondary)
            Text(String(localized: "Patch Adam")).font(.largeTitle).bold()
            Text(String(localized: "Two to four patches against one base, side by side."))
                .foregroundStyle(.secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent(String(localized: "Base")) {
                        HStack {
                            Text(controller.baseDescription).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button(String(localized: "Directory or Archive…")) { SessionActions.openBase(controller) }
                            Button(String(localized: "Git Revision…")) { showGitSheet = true }
                        }
                    }
                    LabeledContent(String(localized: "Patches")) {
                        HStack {
                            Text(controller.columns.map { "\($0.label) \($0.sourceName)" }.joined(separator: ", "))
                                .lineLimit(2)
                            Spacer()
                            Button(String(localized: "Add Patches…")) { SessionActions.addPatches(controller) }
                            Button(String(localized: "Paste")) { SessionActions.pastePatch(controller) }
                        }
                    }
                    if controller.base == nil, !controller.columns.isEmpty {
                        Button(String(localized: "No base at hand? Rebuild one from the patches")) { controller.useSyntheticBase() }
                            .help(String(localized: "Every base line any patch shows is used; lines no patch touches are filler."))
                    }
                }
                .padding(6)
            }
            .frame(maxWidth: 640)

            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
                .frame(maxWidth: 640, minHeight: 90)
                .overlay(Text(String(localized: "Drop .patch / .diff files, a base directory, or an archive here")).foregroundStyle(.secondary))
                .dropDestination(for: URL.self) { urls, _ in
                    SessionActions.handleDropped(urls, controller)
                    return true
                } isTargeted: { isTargeted = $0 }

            if let message = controller.errorMessage {
                Text(message).foregroundStyle(.red).font(.callout).textSelection(.enabled)
            }
            if controller.columns.count >= 2, controller.base != nil {
                Text(String(localized: "Ready.")).foregroundStyle(.secondary)
            } else {
                Text(String(localized: "Need a base and at least two patches.")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showGitSheet) { GitRevisionSheet(controller: controller) }
    }
}

struct GitRevisionSheet: View {
    @Bindable var controller: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var repository = ""
    @State private var revision = "HEAD"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Open a git revision as the base")).font(.headline)
            HStack {
                TextField(String(localized: "Repository path"), text: $repository)
                Button(String(localized: "Choose…")) {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    if panel.runModal() == .OK, let url = panel.url { repository = url.path }
                }
            }
            TextField(String(localized: "Revision (branch, tag, or commit)"), text: $revision)
            HStack {
                Spacer()
                Button(String(localized: "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(String(localized: "Open")) {
                    controller.openBase(url: URL(fileURLWithPath: repository), revision: revision)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(repository.isEmpty || revision.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

/// Panels and pasteboard reads shared by the welcome view and the menu.
@MainActor
enum SessionActions {
    static func openBase(_ controller: SessionController) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.directory, .folder, .zip, .gzip, UTType(filenameExtension: "tar") ?? .archive, UTType(filenameExtension: "tgz") ?? .archive]
        panel.message = String(localized: "Choose the base: a directory, or a .tar / .tar.gz / .zip archive")
        if panel.runModal() == .OK, let url = panel.url { controller.openBase(url: url) }
    }

    static func addPatches(_ controller: SessionController) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType(filenameExtension: "patch") ?? .plainText, UTType(filenameExtension: "diff") ?? .plainText, .plainText]
        panel.message = String(localized: "Choose two to four unified diff files")
        if panel.runModal() == .OK {
            for url in panel.urls { controller.addPatch(url: url) }
        }
    }

    static func pastePatch(_ controller: SessionController) {
        guard let text = NSPasteboard.general.string(forType: .string), text.contains("@@") else {
            controller.errorMessage = String(localized: "The clipboard does not hold a unified diff.")
            return
        }
        controller.addPatch(text: text, name: String(localized: "Pasted patch \(controller.columns.count + 1)"))
    }

    static func handleDropped(_ urls: [URL], _ controller: SessionController) {
        for url in urls {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            let ext = url.pathExtension.lowercased()
            if isDirectory.boolValue || ["tar", "zip", "tgz", "gz"].contains(ext) {
                controller.openBase(url: url)
            } else {
                controller.addPatch(url: url)
            }
        }
    }
}
