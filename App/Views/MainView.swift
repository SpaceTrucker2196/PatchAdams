import SwiftUI

/// The window: file tree left, columns middle, request panel on top
/// (spec "User interface"). Phase 3 adds the comparison panel, Phase 4
/// the findings sidebar.
struct MainView: View {
    @Bindable var controller: SessionController

    var body: some View {
        Group {
            if controller.hasSession {
                session
            } else {
                WelcomeView(controller: controller)
            }
        }
        .navigationTitle(controller.sessionTitle)
        .onAppear {
            #if DEBUG
            DebugHooks.run(controller)
            #endif
        }
        .toolbar { toolbar }
        .onChange(of: controller.scrollLock, initial: true) { _, on in controller.scrollSync.isEnabled = { on } }
        .alert(String(localized: "Problem"), isPresented: Binding(get: { controller.errorMessage != nil && controller.hasSession }, set: { if !$0 { controller.errorMessage = nil } })) {
            Button(String(localized: "OK")) { controller.errorMessage = nil }
        } message: {
            Text(controller.errorMessage ?? "")
        }
    }

    private var session: some View {
        VStack(spacing: 0) {
            if controller.showRequestPanel {
                RequestPanel(controller: controller)
                Divider()
            }
            HSplitView {
                FileTreeView(controller: controller)
                    .frame(minWidth: 180, idealWidth: 240, maxWidth: 400)
                VStack(spacing: 0) {
                    columns
                    if controller.showSearch {
                        Divider()
                        SearchPanel(controller: controller)
                    } else if controller.showComparison {
                        Divider()
                        ComparisonPanel(controller: controller)
                    }
                }
                .frame(minWidth: 400, maxWidth: .infinity)
                if controller.showPins {
                    PinsSidebar(controller: controller)
                        .frame(minWidth: 180, idealWidth: 220, maxWidth: 320)
                }
            }
            Divider()
            statusBar
        }
    }

    private var columns: some View {
        HStack(spacing: 2) {
            ForEach(controller.visibleColumns) { column in
                ColumnView(column: column, controller: controller)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if controller.visibleColumns.isEmpty {
                ContentUnavailableView(String(localized: "All columns hidden"), systemImage: "eye.slash")
            }
        }
        .padding(2)
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if let path = controller.selectedPath {
                Text(path).font(.caption).lineLimit(1).truncationMode(.middle)
            }
            if controller.goldenID != nil {
                ForEach(controller.visibleColumns) { column in
                    if let summary = controller.goldenSummary(for: column) {
                        Text(String(localized: "\(column.label): \(summary.files) files, \(summary.lines) lines differ"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if let message = controller.statusMessage {
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            ForEach(controller.columns) { column in
                if column.isHidden {
                    Button("\(column.label) " + String(localized: "hidden")) { controller.toggleHidden(column.id) }
                        .buttonStyle(.link).font(.caption)
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .principal) {
            if controller.hasSession {
                Picker(String(localized: "Golden"), selection: Binding(get: { controller.goldenID }, set: { controller.setGolden($0) })) {
                    Text(String(localized: "None")).tag(UUID?.none)
                    ForEach(controller.columns) { column in
                        Text("★ \(column.label)").tag(UUID?.some(column.id))
                    }
                }
                .pickerStyle(.segmented)
                .help(String(localized: "Golden patch: every other column renders against it (⇧⌘1–4)"))
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: $controller.showSearch) {
                Label(String(localized: "Search"), systemImage: "magnifyingglass")
            }
            .help(String(localized: "Search all columns (⌘F)"))
            Toggle(isOn: $controller.showComparison) {
                Label(String(localized: "Comparison"), systemImage: "rectangle.split.2x1")
            }
            .help(String(localized: "Show the comparison panel"))
            Toggle(isOn: $controller.showPins) {
                Label(String(localized: "Pins"), systemImage: "pin")
            }
            .help(String(localized: "Pinned selections (⌘P pins)"))
            Toggle(isOn: $controller.showRequestPanel) {
                Label(String(localized: "Request"), systemImage: "text.quote")
            }
            .help(String(localized: "Show the request text (⌘R)"))
            Toggle(isOn: $controller.scrollLock) {
                Label(String(localized: "Scroll Lock"), systemImage: controller.scrollLock ? "lock" : "lock.open")
            }
            .help(String(localized: "Scroll every column to the same place (⌘L)"))
            Toggle(isOn: $controller.showRemovedLines) {
                Label(String(localized: "Removed Lines"), systemImage: "minus.square")
            }
            .help(String(localized: "Show removed lines inline"))
            Button {
                controller.copyReference()
            } label: {
                Label(String(localized: "Copy Reference"), systemImage: "number")
            }
            .help(String(localized: "Copy `filename Lstart:Lend` for the selection (⇧⌘C)"))
            .disabled(!controller.hasSession)
            Button {
                SessionActions.addPatches(controller)
            } label: {
                Label(String(localized: "Add Patch"), systemImage: "plus")
            }
            .disabled(controller.columns.count >= 4)
        }
    }
}

/// The request text (FR-6): open on a new session until the reviewer
/// closes it, so scope stays in view.
struct RequestPanel: View {
    @Bindable var controller: SessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(localized: "Request")).font(.headline)
                Spacer()
                Button {
                    controller.showRequestPanel = false
                } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.plain)
            }
            TextEditor(text: $controller.requestText)
                .font(.body)
                .frame(minHeight: 40, maxHeight: 80)
                .overlay(alignment: .topLeading) {
                    if controller.requestText.isEmpty {
                        Text(String(localized: "Paste the task prompt here. Findings are judged against it."))
                            .foregroundStyle(.tertiary).padding(.horizontal, 5).padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
