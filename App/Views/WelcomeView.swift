import SwiftUI
import SessionModel
import UniformTypeIdentifiers

/// Shown until the reviewer has a base, two to four patches, and has
/// confirmed their order (FR-1, FR-2; issue #22). Patches fill the
/// slots in order — the first is A, then B, C, D — and can be moved
/// before the order is confirmed; after that a label means the same
/// patch for the whole session (MISSION.md §6).
struct WelcomeView: View {
    @Bindable var controller: SessionController
    @State private var isTargeted = false
    @State private var showGitSheet = false

    private static let labels = ["A", "B", "C", "D"]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // The app icon (issue #11), not a generic symbol.
                Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: UIScale.size(96), height: UIScale.size(96))
                    .accessibilityHidden(true)
                Text(String(localized: "Patch Adams")).font(.ui(.largeTitle)).bold()
                Text(String(localized: "Two to four patches against one base, side by side."))
                    .foregroundStyle(.secondary)

                step(1, String(localized: "Choose the base — or build it from the patches"), done: controller.base != nil) { baseStep }
                step(2, String(localized: "Add patches in order: A, B, C, D"), done: controller.columns.count >= 2) { patchSlots }
                step(3, String(localized: "Confirm the patch order"), done: false) { confirmStep }

                if let message = controller.errorMessage {
                    Text(message).foregroundStyle(.red).font(.ui(.body)).textSelection(.enabled)
                }
                Button(String(localized: "How does this work?")) { controller.showOnboarding = true }
                    .buttonStyle(.link)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .dropDestination(for: URL.self) { urls, _ in
            SessionActions.handleDropped(urls, controller)
            return true
        } isTargeted: { isTargeted = $0 }
        .overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [10]))
                    .padding(8).allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $showGitSheet) { GitRevisionSheet(controller: controller) }
        .sheet(isPresented: $controller.showOnboarding) { OnboardingView(controller: controller) }
        .onAppear {
            if !UserDefaults.standard.bool(forKey: SessionController.onboardingShownKey) { controller.showOnboarding = true }
        }
    }

    private func step<Content: View>(_ number: Int, _ title: String, done: Bool, @ViewBuilder content: () -> Content) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle")
                        .font(.ui(.title2)).foregroundStyle(done ? Color.green : Color.secondary)
                    Text(title).font(.ui(.headline))
                    Spacer()
                }
                content()
            }
            .padding(8)
        }
        .frame(maxWidth: UIScale.size(680))
    }

    /// Two plain choices (issue #22): real code, or a base built from
    /// the patches — the second is easy to miss when it hides until
    /// patches are loaded, so it is always shown.
    private var baseStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "The code every patch was written against. Pick one:"))
                .font(.ui(.callout)).foregroundStyle(.secondary)
            if controller.base != nil {
                Label(controller.baseDescription, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).lineLimit(1).truncationMode(.middle)
            }
            HStack(alignment: .top, spacing: 10) {
                choice(String(localized: "I have the code"),
                       detail: String(localized: "A project folder, a .zip / .tar.gz archive, or a git revision."), icon: "folder") {
                    HStack {
                        Button(String(localized: "Folder or Archive…")) { SessionActions.openBase(controller) }
                        Button(String(localized: "Git Revision…")) { showGitSheet = true }
                            .disabled(controller.gitVersion == nil)
                            .help(controller.gitVersion == nil ? String(localized: "git was not found on this Mac") : controller.gitVersion ?? "")
                    }
                }
                choice(String(localized: "I only have the patches"),
                       detail: String(localized: "Build the base from the patches themselves. Lines no patch shows are left out."), icon: "square.stack.3d.up") {
                    Button(String(localized: "Build Base from Patches")) { controller.useSyntheticBase() }
                        .buttonStyle(.borderedProminent)
                        .disabled(controller.columns.isEmpty)
                        .help(String(localized: "Every base line any patch shows is used; lines no patch touches are filler."))
                    if controller.columns.isEmpty {
                        Text(String(localized: "Add the patches in step 2 first, or just press Confirm in step 3 — it builds this for you."))
                            .font(.ui(.callout)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if controller.gitVersion == nil {
                Label(String(localized: "git not found: folder and archive bases still work; the Git Revision base is off."), systemImage: "exclamationmark.triangle")
                    .font(.ui(.callout)).foregroundStyle(.secondary)
            }
        }
    }

    private func choice<Content: View>(_ title: String, detail: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.ui(.headline))
            Text(detail).font(.ui(.callout)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }

    /// Four slots, always shown, so the order is plain before anything
    /// is loaded: the next patch goes into the first empty slot.
    private var patchSlots: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Up to four. The first patch you add is A, the next B, then C and D. Use the arrows to change the order."))
                .font(.ui(.callout)).foregroundStyle(.secondary)
            ForEach(0..<4, id: \.self) { i in
                slotRow(i)
            }
            HStack {
                Button(String(localized: "Add Patches…")) { SessionActions.addPatches(controller) }
                    .disabled(controller.columns.count >= 4)
                Button(String(localized: "Paste")) { SessionActions.pastePatch(controller) }
                    .disabled(controller.columns.count >= 4)
                Spacer()
                Text(String(localized: "or drop .patch / .diff files anywhere in this window")).font(.ui(.callout)).foregroundStyle(.secondary)
            }
        }
    }

    private func slotRow(_ i: Int) -> some View {
        let column = i < controller.columns.count ? controller.columns[i] : nil
        let isNext = i == controller.columns.count
        return HStack(spacing: 10) {
            Text(Self.labels[i])
                .font(.system(size: UIScale.size(for: .title3), design: .rounded)).bold()
                .frame(width: UIScale.size(30), height: UIScale.size(30))
                .background(Circle().fill(column == nil ? Color.secondary.opacity(0.2) : Color.accentColor))
                .foregroundStyle(column == nil ? Color.secondary : Color.white)
            if let column {
                Text(column.sourceName).lineLimit(1).truncationMode(.middle)
                Text(String(localized: "\(column.patch.files.count) files")).font(.ui(.callout)).foregroundStyle(.secondary)
                Spacer()
                Button { controller.moveColumn(column.id, by: -1) } label: { Image(systemName: "arrow.up") }
                    .disabled(i == 0).help(String(localized: "Move up: an earlier letter"))
                Button { controller.moveColumn(column.id, by: 1) } label: { Image(systemName: "arrow.down") }
                    .disabled(i == controller.columns.count - 1).help(String(localized: "Move down: a later letter"))
                Button { controller.removeColumn(column.id) } label: { Image(systemName: "xmark") }
                    .help(String(localized: "Remove this patch"))
            } else {
                Text(isNext ? String(localized: "Next patch goes here") : String(localized: "Empty"))
                    .foregroundStyle(isNext ? .primary : .tertiary)
                Spacer()
                if isNext {
                    Button(String(localized: "Choose…")) {
                        if let url = SessionActions.chooseOnePatch() { controller.addPatch(url: url) }
                    }
                }
            }
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 4).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(column == nil ? Color.clear : Color.accentColor.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(column == nil ? 0.35 : 0.15),
                                                                style: StrokeStyle(lineWidth: 1, dash: column == nil ? [4] : [])))
    }

    private var confirmStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            if controller.columns.count >= 2 {
                Text(String(localized: "These letters stay with these patches for the whole review, in findings, ranks and the export."))
                    .font(.ui(.callout)).foregroundStyle(.secondary)
                Text(controller.columns.enumerated().map { "\(Self.labels[$0.offset]) = \($0.element.sourceName)" }.joined(separator: "   "))
                    .font(.ui(.callout).monospaced())
                if controller.base == nil {
                    // Say it before it happens: no base chosen means one is built (issue #22).
                    Label(String(localized: "No base chosen: Confirm builds one from these patches."), systemImage: "square.stack.3d.up")
                        .font(.ui(.callout)).foregroundStyle(.orange)
                }
                Button(controller.base == nil ? String(localized: "Build Base, Confirm Order and Start Review")
                                              : String(localized: "Confirm Order and Start Review")) {
                    if controller.base == nil { controller.useSyntheticBase() }
                    controller.confirmPatchOrder()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            } else {
                Text(String(localized: "Add at least two patches."))
                    .font(.ui(.callout)).foregroundStyle(.secondary)
            }
        }
    }
}

/// First-run guide (issue #22): what to load, in what order, and what
/// to do once the columns are up. Shown once; "How does this work?"
/// on the opening screen brings it back.
struct OnboardingView: View {
    @Bindable var controller: SessionController
    @State private var page = 0

    private var pages: [(icon: String, title: String, text: String)] {[
        ("hand.wave", String(localized: "Welcome to Patch Adams"),
         String(localized: "Compare two to four patches that each try to solve the same task, side by side, and write down what is wrong with each one.")),
        ("folder", String(localized: "1. Choose the base"),
         String(localized: "The base is the code before any patch: a project folder, a .zip or .tar.gz archive, or a git revision. Only have the patches? That is fine: press Build Base from Patches, or just Confirm — it builds one for you.")),
        ("square.stack.3d.up", String(localized: "2. Add patches in order"),
         String(localized: "Add up to four .patch or .diff files. They fill the slots in order: the first is A, the next B, then C and D. Drop several at once, or use Add Patches.")),
        ("checkmark.seal", String(localized: "3. Confirm the order"),
         String(localized: "Check which patch is A, B, C and D. Use the arrows to fix the order, then press Confirm. The letters then stay fixed for the whole review.")),
        ("text.magnifyingglass", String(localized: "4. Review"),
         String(localized: "Pick a file on the left. Select lines to find the same code in the other columns. Press + in Findings to paste a finding: \"Implementation A … (main.go L100-L110)\" marks those lines in patch A.")),
    ]}

    var body: some View {
        let current = pages[page]
        VStack(spacing: 18) {
            Image(systemName: current.icon).font(.system(size: UIScale.size(44))).foregroundStyle(Color.accentColor).frame(height: UIScale.size(56))
            Text(current.title).font(.ui(.title2)).bold()
            Text(current.text).font(.ui(.body)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: UIScale.size(440))
            if page == 2 {
                HStack(spacing: 10) {
                    ForEach(["A", "B", "C", "D"], id: \.self) { label in
                        Text(label).font(.system(size: UIScale.size(for: .title3), design: .rounded)).bold()
                            .frame(width: UIScale.size(34), height: UIScale.size(34)).background(Circle().fill(Color.accentColor)).foregroundStyle(.white)
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { i in
                    Circle().fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: UIScale.size(7), height: UIScale.size(7))
                }
            }
            HStack {
                Button(String(localized: "Skip")) { finish() }.keyboardShortcut(.cancelAction)
                Spacer()
                if page > 0 { Button(String(localized: "Back")) { page -= 1 } }
                Button(page == pages.count - 1 ? String(localized: "Get Started") : String(localized: "Next")) {
                    if page == pages.count - 1 { finish() } else { page += 1 }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: UIScale.size(540))
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: SessionController.onboardingShownKey)
        controller.showOnboarding = false
    }
}

struct GitRevisionSheet: View {
    @Bindable var controller: SessionController
    @Environment(\.dismiss) private var dismiss
    @State private var repository = ""
    @State private var revision = "HEAD"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Open a git revision as the base")).font(.ui(.headline))
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
        .frame(width: UIScale.size(480))
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

    static let patchExtensions: Set<String> = ["patch", "diff", "txt"]

    static func isPatchFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
            && (patchExtensions.contains(url.pathExtension.lowercased()) || url.pathExtension.isEmpty)
    }

    /// One patch file from a picker, for a column's slot (issue #7).
    static func chooseOnePatch() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "patch") ?? .plainText, UTType(filenameExtension: "diff") ?? .plainText, .plainText]
        panel.message = String(localized: "Choose a unified diff file")
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func pastePatch(_ controller: SessionController) {
        guard let text = NSPasteboard.general.string(forType: .string), text.contains("@@") else {
            controller.errorMessage = String(localized: "The clipboard does not hold a unified diff.")
            return
        }
        controller.addPatch(text: text, name: String(localized: "Pasted patch \(controller.columns.count + 1)"))
    }

    /// One file since D11; a folder package from before still opens.
    static let sessionType = UTType(exportedAs: "io.river.patchadam.session", conformingTo: .data)

    static func openSession(_ controller: SessionController) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [sessionType, .package, .folder]
        panel.treatsFilePackagesAsDirectories = false
        panel.message = String(localized: "Choose a .patchadam session")
        if panel.runModal() == .OK, let url = panel.url { controller.open(sessionURL: url) }
    }

    /// ⌘S saves in place; ⇧⌘S or a new session asks where.
    static func saveSession(_ controller: SessionController, as askWhere: Bool) {
        if !askWhere, let url = controller.sessionURL { controller.save(to: url); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [sessionType]
        panel.nameFieldStringValue = (controller.sessionName.isEmpty ? String(localized: "Review") : controller.sessionName) + ".patchadam"
        panel.message = String(localized: "Save the session, with every patch, as one .patchadam file")
        if panel.runModal() == .OK, let url = panel.url { controller.save(to: url) }
    }

    static func exportMarkdown(_ controller: SessionController) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = (controller.sessionName.isEmpty ? String(localized: "review") : controller.sessionName) + ".md"
        if panel.runModal() == .OK, let url = panel.url { controller.write(export: Data(controller.markdownExport().utf8), to: url) }
    }

    static func exportJSON(_ controller: SessionController) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = (controller.sessionName.isEmpty ? String(localized: "review") : controller.sessionName) + ".json"
        if panel.runModal() == .OK, let url = panel.url {
            do { controller.write(export: try controller.jsonExport(), to: url) } catch { controller.errorMessage = "\(error)" }
        }
    }

    static func handleDropped(_ urls: [URL], _ controller: SessionController) {
        for url in urls {
            if url.pathExtension.lowercased() == SessionPackage.fileExtension { controller.open(sessionURL: url); continue }
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
