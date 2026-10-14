import SwiftUI
import PatchModel

// Patch Adam — the SwiftUI shell. One window, three zones: file tree,
// 2 to 4 patch columns with a comparison panel beneath, findings
// sidebar (docs/spec.md, "User interface"). Phase 2: tree, columns,
// gutters, scroll lock, request panel. Phase 3 adds comparison and
// golden, Phase 4 findings and export.
//
// The shell never calls an engine directly: `SessionController` owns
// the session state and hands immutable results to the views (spec,
// "Technical architecture").

@main
struct PatchAdamApp: App {
    @State private var controller = SessionController()

    var body: some Scene {
        WindowGroup {
            MainView(controller: controller)
                .frame(minWidth: 1000, minHeight: 640)
        }
        .windowResizability(.contentMinSize)
        .commands { SessionCommands(controller: controller) }
    }
}

/// Menu bar and keyboard (spec "Keyboard"). Every action is reachable
/// from the menu, so VoiceOver and the keyboard see the same set.
struct SessionCommands: Commands {
    let controller: SessionController

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(String(localized: "New Session")) { controller.newSession() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button(String(localized: "Open Base…")) { SessionActions.openBase(controller) }
                .keyboardShortcut("o")
            Button(String(localized: "Add Patches…")) { SessionActions.addPatches(controller) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button(String(localized: "Paste Patch")) { SessionActions.pastePatch(controller) }
                .keyboardShortcut("v", modifiers: [.command, .option])
            Button(String(localized: "Rebuild Base from Patches")) { controller.useSyntheticBase() }
                .disabled(controller.columns.isEmpty)
        }
        CommandGroup(after: .pasteboard) {
            Button(String(localized: "Copy Reference")) { controller.copyReference() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
        }
        CommandMenu(String(localized: "Columns")) {
            ForEach(0..<4, id: \.self) { i in
                Button(String(localized: "Focus Column \(i + 1)")) { controller.focusColumn(index: i) }
                    .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: .command)
            }
            Divider()
            ForEach(0..<4, id: \.self) { i in
                Button(String(localized: "Set Column \(i + 1) Golden")) {
                    let visible = controller.visibleColumns
                    if i < visible.count { controller.setGolden(visible[i].id) }
                }
                .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: [.command, .shift])
            }
            Divider()
            Button(String(localized: "Pin Selection")) { controller.pinSelection() }
                .keyboardShortcut("p")
            Button(String(localized: "Search All Columns")) { controller.showSearch = true }
                .keyboardShortcut("f")
            Divider()
            Button(String(localized: "Next Hunk")) { controller.jumpHunk(forward: true) }
                .keyboardShortcut("]", modifiers: [])
            Button(String(localized: "Previous Hunk")) { controller.jumpHunk(forward: false) }
                .keyboardShortcut("[", modifiers: [])
            Divider()
            Button(controller.scrollLock ? String(localized: "Scroll Lock Off") : String(localized: "Scroll Lock On")) { controller.scrollLock.toggle() }
                .keyboardShortcut("l")
            Button(controller.showRemovedLines ? String(localized: "Hide Removed Lines") : String(localized: "Show Removed Lines")) { controller.showRemovedLines.toggle() }
                .keyboardShortcut("-", modifiers: [.command, .option])
            Button(controller.showRequestPanel ? String(localized: "Hide Request") : String(localized: "Show Request")) { controller.showRequestPanel.toggle() }
                .keyboardShortcut("r")
            Button(controller.testsOnly ? String(localized: "Show All Files") : String(localized: "Tests Only")) { controller.testsOnly.toggle() }
                .keyboardShortcut("t", modifiers: [.command, .option])
        }
        #if DEBUG
        CommandMenu("Debug") {
            Button("Open Demo Session (kettle × 4)") {
                let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                controller.openDemoSession(fixtures: (15...18).map { root.appendingPathComponent("Fixtures/patches/fixture-\($0).patch") },
                                           request: "Demo: the four kettle patches (kettle-1 … kettle-4) against a base rebuilt from their hunks.")
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
        }
        #endif
    }
}
