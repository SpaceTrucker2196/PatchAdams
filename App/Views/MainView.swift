import SwiftUI
import SessionModel

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
        .scaledInterface()
        .navigationTitle(controller.sessionTitle)
        .onAppear {
            #if DEBUG
            DebugHooks.run(controller)
            #endif
        }
        .toolbar { toolbar }
        .sheet(item: $controller.findingDraft) { _ in FindingForm(controller: controller) }
        .sheet(isPresented: $controller.showPasteFinding) { PasteFindingForm(controller: controller) }
        .onChange(of: controller.scrollLock, initial: true) { _, on in controller.scrollSync.isEnabled = { on } }
        .onChange(of: controller.hasSession) { _, has in
            // One-time question on a new session (spec: blind off by default, with a prompt).
            if has, controller.sessionURL == nil, !UserDefaults.standard.bool(forKey: SessionController.blindPromptShownKey) {
                controller.showBlindPrompt = true
            }
        }
        .alert(String(localized: "Review blind?"), isPresented: $controller.showBlindPrompt) {
            Button(String(localized: "Blind")) { UserDefaults.standard.set(true, forKey: SessionController.blindPromptShownKey); controller.toggleBlind() }
            Button(String(localized: "Not Now")) { UserDefaults.standard.set(true, forKey: SessionController.blindPromptShownKey) }
        } message: {
            Text(String(localized: "Blind mode shows the patches as shuffled numbers and hides their file names until you export, to reduce order bias. You can switch it at any time with ⌘⌥B. This question is asked once; Settings can bring it back."))
        }
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
            } else {
                // Collapsed, the task title still heads the window.
                HStack {
                    Text(controller.sessionName.isEmpty ? String(localized: "Untitled task") : controller.sessionName)
                        .font(.ui(.title3).bold()).lineLimit(1)
                    Spacer()
                    Button { controller.showRequestPanel = true } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.plain).help(String(localized: "Show the task details"))
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color(nsColor: .windowBackgroundColor))
            }
            Divider()
            // The findings sidebar takes a quarter of the window (issue #26 follow-up).
            GeometryReader { geometry in
            let quarter = max(280, geometry.size.width / 4)
            HSplitView {
                FileTreeView(controller: controller)
                    .frame(minWidth: UIScale.size(170), idealWidth: UIScale.size(230), maxWidth: UIScale.size(300))
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
                .frame(minWidth: UIScale.size(400), maxWidth: .infinity)
                if controller.showPins {
                    PinsSidebar(controller: controller)
                        .frame(minWidth: UIScale.size(200), idealWidth: UIScale.size(260), maxWidth: UIScale.size(380))
                }
                if controller.showFindings {
                    FindingsSidebar(controller: controller)
                        .frame(width: quarter)
                }
            }
            }
            Divider()
            statusBar
        }
    }

    private var columns: some View {
        HStack(spacing: 2) {
            // With a finding selected, its patch takes the width and the
            // others fold to strips (issue #23).
            let focus = controller.selectedFinding?.label
            ForEach(controller.visibleColumns) { column in
                if focus != nil, !controller.openFindingLabels.contains(column.label) {
                    CollapsedColumnView(column: column, controller: controller)
                        .frame(width: UIScale.size(40))
                        .frame(maxHeight: .infinity)
                        .transition(.opacity)
                } else {
                    ColumnView(column: column, controller: controller)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if controller.visibleColumns.isEmpty {
                ContentUnavailableView(String(localized: "All columns hidden"), systemImage: "eye.slash")
            }
            if controller.columns.count < 4, focus == nil {
                // The add slot (issue #7): a thin column, just the icon.
                PatchSlot(role: .add, controller: controller)
                    .padding(UIScale.size(3))
                    .frame(width: UIScale.size(40))
                    .frame(maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .padding(2)
        .animation(.easeInOut(duration: 0.25), value: controller.selectedFindingID)
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            if let path = controller.selectedPath {
                Text(path).font(.ui(.callout)).lineLimit(1).truncationMode(.middle)
            }
            if controller.goldenID != nil {
                ForEach(controller.visibleColumns) { column in
                    if let summary = controller.goldenSummary(for: column) {
                        Text(String(localized: "\(controller.displayLabel(column)): \(summary.files) files, \(summary.lines) lines differ"))
                            .font(.ui(.callout)).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if controller.blind.isOn {
                Label(String(localized: "Blind"), systemImage: "eye.slash").font(.ui(.callout)).foregroundStyle(.secondary)
                    .help(String(localized: "Blind mode: labels are shuffled numbers (⌘⌥B)"))
            }
            SessionTimer(start: controller.sessionStart)
            if let message = controller.statusMessage {
                Text(message).font(.ui(.callout)).foregroundStyle(.secondary).lineLimit(1)
            }
            ForEach(controller.columns) { column in
                if column.isHidden {
                    Button("\(controller.displayLabel(column)) " + String(localized: "hidden")) { controller.toggleHidden(column.id) }
                        .buttonStyle(.link).font(.ui(.callout))
                }
            }
            Divider().frame(height: UIScale.size(14))
            ScaleControls()
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .principal) {
            if controller.hasSession {
                Picker(String(localized: "Golden"), selection: Binding(get: { controller.goldenID }, set: { controller.setGolden($0) })) {
                    Text(String(localized: "None")).tag(UUID?.none)
                    ForEach(controller.columns) { column in
                        Text("★ \(controller.displayLabel(column))").tag(UUID?.some(column.id))
                    }
                }
                .pickerStyle(.segmented)
                .help(String(localized: "Golden patch: every other column renders against it (⇧⌘1–4)"))
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle(isOn: Binding(get: { controller.blind.isOn }, set: { _ in controller.toggleBlind() })) {
                Label(String(localized: "Blind"), systemImage: "eye.slash")
            }
            .help(String(localized: "Blind mode: shuffled numbers instead of labels (⌘⌥B)"))
            .disabled(!controller.hasSession)
            Toggle(isOn: $controller.showFindings) {
                Label(String(localized: "Findings"), systemImage: "list.bullet.rectangle")
            }
            .help(String(localized: "Findings sidebar"))
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

/// Elapsed review time in the status bar (spec "Avoid reviewer fatigue").
struct SessionTimer: View {
    let start: Date

    var body: some View {
        TimelineView(.periodic(from: start, by: 60)) { context in
            let minutes = Int(context.date.timeIntervalSince(start) / 60)
            Text(String(localized: "\(minutes / 60)h \(minutes % 60)m"))
                .font(.ui(.callout).monospacedDigit()).foregroundStyle(.secondary)
                .help(String(localized: "Time in this session"))
        }
    }
}

/// The request text (FR-6): open on a new session until the reviewer
/// closes it, so scope stays in view.
/// The task header (issue #27): the task's title, then three free
/// fields — the request the patches answer, more about the task, and
/// the reviewer's instructions. Findings are judged against the request.
struct RequestPanel: View {
    @Bindable var controller: SessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField(String(localized: "Task title, e.g. Implementation comparison 103"), text: $controller.sessionName)
                    .textFieldStyle(.plain)
                    .font(.ui(.title2).bold())
                Button {
                    controller.showRequestPanel = false
                } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.plain)
                .help(String(localized: "Hide the task details"))
            }
            HStack(alignment: .top, spacing: 8) {
                field(String(localized: "Request"), text: $controller.requestText,
                      placeholder: String(localized: "Paste the task prompt here. Findings are judged against it."))
                field(String(localized: "Task info"), text: $controller.taskInfo,
                      placeholder: String(localized: "Anything else about the task: links, ids, context."))
                field(String(localized: "Instructions"), text: $controller.taskInstructions,
                      placeholder: String(localized: "How to review: what to rank, what to look for."))
            }
        }
        .padding(8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.ui(.headline))
            TextEditor(text: text)
                .font(.ui(.body))
                .frame(minHeight: UIScale.size(50), maxHeight: UIScale.size(90))
                .overlay(alignment: .topLeading) {
                    if text.wrappedValue.isEmpty {
                        Text(placeholder)
                            .foregroundStyle(.tertiary).padding(.horizontal, 5).padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: text.wrappedValue) { controller.isDirty = true }
        }
        .frame(maxWidth: .infinity)
    }
}
