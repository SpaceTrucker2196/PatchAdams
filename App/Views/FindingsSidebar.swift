import SwiftUI
import SessionModel

/// The findings sidebar (spec "Findings sidebar"): the list with its
/// filters (FR-27), the ranking block (FR-31), the export buttons
/// (FR-32, FR-33). Clicking a finding jumps every column (FR-28).
struct FindingsSidebar: View {
    @Bindable var controller: SessionController

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            filters
            Divider()
            findingsList
            Divider()
            RankingBlock(controller: controller)
            Divider()
            exportBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text(String(localized: "Findings")).font(.headline)
            Text("\(controller.findings.count)").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button {
                controller.newFindingFromSelection()
            } label: { Image(systemName: "plus") }
            .buttonStyle(.plain)
            .help(String(localized: "New finding from the selection (⌘N)"))
            Button {
                controller.showFindings = false
            } label: { Image(systemName: "xmark") }
            .buttonStyle(.plain)
        }
        .padding(8)
    }

    private var filters: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Picker(String(localized: "Patch"), selection: $controller.findingFilter.label) {
                    Text(String(localized: "Any patch")).tag(String?.none)
                    ForEach(controller.columns) { column in
                        Text(controller.displayLabel(column)).tag(String?.some(column.label))
                    }
                }
                .labelsHidden()
                Picker(String(localized: "Severity"), selection: $controller.findingFilter.severity) {
                    Text(String(localized: "Any severity")).tag(Severity?.none)
                    ForEach(Severity.allCases, id: \.self) { Text($0.rawValue).tag(Severity?.some($0)) }
                }
                .labelsHidden()
            }
            HStack(spacing: 4) {
                Picker(String(localized: "File"), selection: $controller.findingFilter.path) {
                    Text(String(localized: "Any file")).tag(String?.none)
                    ForEach(Array(Set(controller.findings.map(\.path))).sorted(), id: \.self) { path in
                        Text((path as NSString).lastPathComponent).tag(String?.some(path))
                    }
                }
                .labelsHidden()
                Picker(String(localized: "Category"), selection: $controller.findingFilter.category) {
                    Text(String(localized: "Any category")).tag(String?.none)
                    ForEach(controller.categories, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .labelsHidden()
            }
            Toggle(String(localized: "Show not-flagged"), isOn: $controller.findingFilter.includeNotFlagged)
                .font(.caption).toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .controlSize(.small)
        .padding(6)
    }

    private var findingsList: some View {
        List {
            ForEach(controller.filteredFindings) { finding in
                FindingRow(finding: finding, controller: controller)
                    .contentShape(Rectangle())
                    .onTapGesture { controller.goTo(finding: finding) }
                    .contextMenu { rowMenu(finding) }
            }
            if controller.filteredFindings.isEmpty {
                Text(controller.findings.isEmpty ? String(localized: "No findings yet. Select lines and press ⌘N.") : String(localized: "Nothing matches the filters."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .listStyle(.inset)
        .frame(minHeight: 160)
    }

    @ViewBuilder private func rowMenu(_ finding: Finding) -> some View {
        Button(String(localized: "Edit…")) { controller.edit(finding) }
        Button(String(localized: "Copy Finding")) { controller.copyFinding(finding) }
        Button(finding.notFlagged ? String(localized: "Mark as Flagged") : String(localized: "Mark as Not Flagged")) { controller.toggleNotFlagged(finding.id) }
        Menu(String(localized: "Same Issue In")) {
            ForEach(controller.columns.filter { $0.label != finding.label }) { column in
                Button("\(controller.displayLabel(column))…") { controller.copyFindingAsTemplate(finding, to: column.id) }
            }
        }
        Divider()
        Button(String(localized: "Delete"), role: .destructive) { controller.deleteFinding(finding.id) }
    }

    private var exportBar: some View {
        HStack(spacing: 6) {
            Button(String(localized: "Copy Markdown")) { controller.copyMarkdown() }
                .help(String(localized: "The write-up, ready to paste into the review form"))
            Button(String(localized: "Export…")) { SessionActions.exportMarkdown(controller) }
                .help(String(localized: "Save the write-up as Markdown (⌘E)"))
            Menu {
                Button(String(localized: "Export JSON…")) { SessionActions.exportJSON(controller) }
                Button(String(localized: "Save Session…")) { SessionActions.saveSession(controller, as: controller.sessionURL == nil) }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).fixedSize()
        }
        .controlSize(.small)
        .padding(6)
    }
}

struct FindingRow: View {
    let finding: Finding
    let controller: SessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(controller.displayLabel(finding.label))
                    .font(.caption.bold()).frame(width: 16)
                Text(finding.severity.rawValue)
                    .font(.caption2.bold())
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: CodeStyle.severityColor(finding.severity)).opacity(0.25)))
                Text(finding.category).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if finding.notFlagged {
                    Text(String(localized: "not flagged")).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(finding.title).font(.callout).lineLimit(2)
                .strikethrough(finding.notFlagged)
            Text(finding.reference).font(.caption.monospaced()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// Rank 1 to 4 per patch, ties allowed, and the rationale (FR-31).
struct RankingBlock: View {
    @Bindable var controller: SessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Ranking")).font(.headline)
            ForEach(controller.columns) { column in
                HStack(spacing: 6) {
                    Text(controller.displayLabel(column)).font(.caption.bold()).frame(width: 16)
                    Text(controller.displayName(column)).font(.caption).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Picker(String(localized: "Rank"), selection: Binding(get: { controller.ranking.rank(of: column.label) }, set: { controller.setRank($0, for: column.label) })) {
                        Text("—").tag(Int?.none)
                        ForEach(1...max(1, controller.columns.count), id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                    }
                    .labelsHidden().frame(width: 56)
                }
            }
            TextEditor(text: Binding(get: { controller.ranking.rationale }, set: { controller.ranking.rationale = $0; controller.isDirty = true }))
                .font(.callout)
                .frame(minHeight: 50, maxHeight: 90)
                .overlay(alignment: .topLeading) {
                    if controller.ranking.rationale.isEmpty {
                        Text(String(localized: "Rationale: why this order?"))
                            .foregroundStyle(.tertiary).padding(.horizontal, 5).padding(.vertical, 8).allowsHitTesting(false)
                    }
                }
        }
        .controlSize(.small)
        .padding(8)
    }
}

/// The finding sheet (FR-25, FR-26): reference prefilled and read-only;
/// title, category and severity required; "Does the request ask for
/// this?"; a parked correctness note; the not-flagged tag (FR-30).
struct FindingForm: View {
    @Bindable var controller: SessionController
    @State private var newCategory = ""

    var body: some View {
        if let draft = controller.findingDraft {
            let binding = Binding(get: { controller.findingDraft ?? draft }, set: { controller.findingDraft = $0 })
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(draft.isNew ? String(localized: "New Finding") : String(localized: "Edit Finding")).font(.headline)
                    Spacer()
                    Text("\(controller.displayLabel(draft.finding.label))  \(draft.finding.reference)")
                        .font(.callout.monospaced()).foregroundStyle(.secondary)
                }
                if let template = draft.templateOf {
                    Label(String(localized: "Template from another column; the region was located as \(template). Check the lines before saving."), systemImage: "doc.on.doc")
                        .font(.caption).foregroundStyle(.secondary)
                }
                TextField(String(localized: "Title"), text: binding.finding.title)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Picker(String(localized: "Category"), selection: binding.finding.category) {
                        ForEach(controller.categories, id: \.self) { Text($0).tag($0) }
                    }
                    Picker(String(localized: "Severity"), selection: binding.finding.severity) {
                        ForEach(Severity.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                HStack {
                    TextField(String(localized: "Add a category…"), text: $newCategory)
                        .textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                    Button(String(localized: "Add")) {
                        let name = newCategory.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty, !controller.categories.contains(name) else { return }
                        controller.categories.append(name)
                        controller.findingDraft?.finding.category = name
                        newCategory = ""
                    }
                    .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
                    Spacer()
                }
                .controlSize(.small)
                Picker(String(localized: "Does the request ask for this?"), selection: binding.finding.requestAsks) {
                    ForEach(RequestAsks.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(String(localized: "Description")).font(.caption).foregroundStyle(.secondary)
                TextEditor(text: binding.finding.description).font(.body).frame(minHeight: 70, maxHeight: 140)
                Text(String(localized: "Correctness note (parked, not a quality label)")).font(.caption).foregroundStyle(.secondary)
                TextField(String(localized: "Note"), text: binding.finding.note).textFieldStyle(.roundedBorder)
                Toggle(String(localized: "Not flagged — considered and passed"), isOn: binding.finding.notFlagged)
                HStack {
                    Button(String(localized: "Cancel")) { controller.findingDraft = nil }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(draft.isNew ? String(localized: "Add Finding") : String(localized: "Save")) { controller.saveDraft() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!draft.finding.isComplete)
                }
            }
            .padding(16)
            .frame(width: 560)
        }
    }
}
