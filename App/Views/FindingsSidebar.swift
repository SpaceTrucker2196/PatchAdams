import SwiftUI
import SessionModel

/// The findings sidebar (spec "Findings sidebar"): the list with its
/// filters (FR-27), the ranking block (FR-31), the export buttons
/// (FR-32, FR-33). Clicking a finding jumps every column (FR-28).
struct FindingsSidebar: View {
    @Bindable var controller: SessionController
    @State private var pendingDelete: Finding?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            // An open finding gets the whole height (issue #21): filters
            // and ranking step aside until it is closed.
            if controller.selectedFindingID == nil {
                filters
                Divider()
            }
            findingsList
            if controller.selectedFindingID == nil {
                Divider()
                RankingBlock(controller: controller)
            }
            Divider()
            exportBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text(String(localized: "Findings")).font(.ui(.headline))
            Text("\(controller.findings.count)").font(.ui(.callout)).foregroundStyle(.secondary)
            Spacer()
            if controller.selectedFindingID != nil {
                Button(String(localized: "Close Finding")) {
                    withAnimation(.easeInOut(duration: 0.25)) { controller.selectedFindingID = nil }
                }
                .controlSize(.small)
                .help(String(localized: "Show all patches, the filters and the ranking again"))
            }
            Button {
                controller.showPasteFinding = true
            } label: { Image(systemName: "plus") }
            .buttonStyle(.plain)
            .help(String(localized: "Paste a finding; its file names and L100-L110 references become the evidence"))
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
                .font(.ui(.callout)).toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .controlSize(.small)
        .padding(6)
    }

    private var findingsList: some View {
        List {
            ForEach(controller.filteredFindings) { finding in
                FindingRow(finding: finding, controller: controller, onDelete: { pendingDelete = finding })
                    .contentShape(Rectangle())
                    // No tap on the open row, so clicks reach its text fields.
                    .onTapGesture { if controller.selectedFindingID != finding.id { controller.goTo(finding: finding) } }
                    .listRowBackground(controller.selectedFindingID == finding.id ? Color(nsColor: SpacetruckerPalette.selectedFinding) : nil)
                    .contextMenu { rowMenu(finding) }
            }
            if controller.filteredFindings.isEmpty {
                Text(controller.findings.isEmpty ? String(localized: "No findings yet. Select lines and press ⌘N.") : String(localized: "Nothing matches the filters."))
                    .font(.ui(.callout)).foregroundStyle(.secondary)
            }
        }
        .listStyle(.inset)
        .frame(minHeight: UIScale.size(160))
        .confirmationDialog(String(localized: "Delete this finding?"), isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { finding in
            Button(String(localized: "Delete"), role: .destructive) { controller.deleteFinding(finding.id) }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: { finding in
            Text(finding.title)
        }
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
        Button(String(localized: "Delete…"), role: .destructive) { pendingDelete = finding }
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
    var onDelete: () -> Void = {}
    /// Finding text reads at the code's size (Settings and zoom).
    @AppStorage(CodeStyle.fontSizeKey) private var fontSize = CodeStyle.defaultFontSize

    private var textFont: Font { .system(size: CGFloat(fontSize)) }
    private var isSelected: Bool { controller.selectedFindingID == finding.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(controller.displayLabel(finding.label))
                    .font(.ui(.callout).bold()).frame(width: UIScale.size(20))
                if isSelected {
                    Picker(String(localized: "Severity"), selection: field(\.severity)) {
                        ForEach(Severity.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    Picker(String(localized: "Category"), selection: field(\.category)) {
                        ForEach(controller.categories, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                } else {
                    Text(finding.severity.rawValue)
                        .font(.ui(.caption).bold())
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: CodeStyle.severityColor(finding.severity)).opacity(0.25)))
                    Text(finding.category).font(.ui(.caption)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if finding.notFlagged {
                    Text(String(localized: "not flagged")).font(.ui(.caption)).foregroundStyle(.secondary)
                }
                // Always visible, not only in the right-click menu (issue #26).
                Button { controller.edit(finding) } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless).help(String(localized: "Edit this finding"))
                Button(action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless).foregroundStyle(.red).help(String(localized: "Delete this finding"))
            }
            if isSelected {
                // The selected finding opens up and edits in place.
                TextField(String(localized: "Title"), text: field(\.title), axis: .vertical)
                    .font(textFont.bold()).textFieldStyle(.plain)
                let checked = evidenceChecks
                let missing = !checked.contains { $0.found }
                // Grows to the whole text: a hidden copy of the text sets
                // the height, the editor fills it, so nothing scrolls.
                ZStack(alignment: .topLeading) {
                    Text(finding.description.isEmpty ? " " : finding.description + "\n")
                        .font(Font(CodeStyle.font))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .hidden()
                    TextEditor(text: field(\.description))
                        .scrollDisabled(true)
                }
                .codeEditorStyle(invalid: missing)
                .frame(minHeight: UIScale.size(80))
                if missing {
                    EvidenceHelp(found: !checked.isEmpty, patch: controller.displayLabel(finding.label))
                }
                // Each reference jumps to its lines (issue #24); one not in
                // this patch shows red.
                FlowLayout(spacing: 6) {
                    ForEach(Array(checked.enumerated()), id: \.offset) { _, item in
                        Button(item.evidence.reference) { controller.goTo(evidence: item.evidence, of: finding) }
                            .font(.system(size: CGFloat(fontSize) - 2, design: .monospaced))
                            .buttonStyle(.bordered)
                            .tint(item.found ? nil : .red)
                            .foregroundStyle(item.found ? Color.primary : Color.red)
                            .help(item.found ? String(localized: "Show these lines in patch \(controller.displayLabel(finding.label))")
                                             : String(localized: "Not in patch \(controller.displayLabel(finding.label))"))
                    }
                }
                TextField(String(localized: "Note"), text: field(\.note)).font(.ui(.callout)).textFieldStyle(.roundedBorder)
            } else {
                Text(finding.title).font(textFont).lineLimit(2)
                    .strikethrough(finding.notFlagged)
                Text(finding.reference).font(.ui(.callout).monospaced()).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    /// The references the finding cites — from its text when the text
    /// has any, else its stored reference (a ⌘N finding) — and whether
    /// each lands in the finding's patch.
    private var evidenceChecks: [(evidence: Evidence, found: Bool)] {
        let fromText = EvidenceParser.parse(finding.description)
        let all = fromText.isEmpty ? EvidenceParser.parse(finding.reference) : fromText
        guard let column = controller.columns.first(where: { $0.label == finding.label }) else { return all.map { ($0, false) } }
        return all.map { ($0, controller.resolve($0, in: controller.column(for: $0, default: column)) != nil) }
    }

    /// A binding to one field of this finding in the session.
    private func field<Value>(_ path: WritableKeyPath<Finding, Value>) -> Binding<Value> {
        Binding(get: { (controller.findings.first { $0.id == finding.id } ?? finding)[keyPath: path] },
                set: { value in controller.updateFinding(finding.id) { $0[keyPath: path] = value } })
    }
}

/// Rank 1 to 4 per patch, ties allowed, and the rationale (FR-31).
struct RankingBlock: View {
    @Bindable var controller: SessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Ranking")).font(.ui(.headline))
            ForEach(controller.columns) { column in
                HStack(spacing: 6) {
                    Text(controller.displayLabel(column)).font(.ui(.callout).bold()).frame(width: UIScale.size(20))
                    Text(controller.displayName(column)).font(.ui(.callout)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Picker(String(localized: "Rank"), selection: Binding(get: { controller.ranking.rank(of: column.label) }, set: { controller.setRank($0, for: column.label) })) {
                        Text("—").tag(Int?.none)
                        ForEach(1...max(1, controller.columns.count), id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                    }
                    .labelsHidden().frame(width: UIScale.size(56))
                }
            }
            TextEditor(text: Binding(get: { controller.ranking.rationale }, set: { controller.ranking.rationale = $0; controller.isDirty = true }))
                .font(.ui(.body))
                .frame(minHeight: UIScale.size(50), maxHeight: UIScale.size(90))
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
                // A header like a patch column's: the label badge, then the reference.
                HStack(spacing: 8) {
                    Text(controller.displayLabel(draft.finding.label))
                        .font(.system(size: UIScale.size(for: .headline), design: .rounded)).bold()
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(ColumnView.labelColor(draft.finding.label, blind: controller.blind.isOn)))
                        .foregroundStyle(.white)
                    Text(draft.isNew ? String(localized: "New Finding") : String(localized: "Edit Finding")).font(.ui(.headline))
                    Spacer()
                    Text(draft.finding.reference)
                        .font(.ui(.body).monospaced()).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: SpacetruckerPalette.gutterBackground)))
                if let template = draft.templateOf {
                    Label(String(localized: "Template from another column; the region was located as \(template). Check the lines before saving."), systemImage: "doc.on.doc")
                        .font(.ui(.callout)).foregroundStyle(.secondary)
                }
                TextField(String(localized: "Title"), text: binding.finding.title, axis: .vertical)
                    .textFieldStyle(.plain).font(Font(CodeStyle.font).bold())
                    .padding(8).codeSurface()
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
                        .textFieldStyle(.roundedBorder).frame(maxWidth: UIScale.size(220))
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
                Text(String(localized: "Description")).font(.ui(.callout)).foregroundStyle(.secondary)
                TextEditor(text: binding.finding.description)
                    .codeEditorStyle(invalid: false)
                    .frame(minHeight: UIScale.size(160), maxHeight: UIScale.size(360))
                Text(String(localized: "Correctness note (parked, not a quality label)")).font(.ui(.callout)).foregroundStyle(.secondary)
                TextField(String(localized: "Note"), text: binding.finding.note).textFieldStyle(.roundedBorder)
                Toggle(String(localized: "Not flagged — considered and passed"), isOn: binding.finding.notFlagged)
                HStack {
                    Button(String(localized: "Cancel")) { controller.findingDraft = nil }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(draft.isNew ? String(localized: "Add Finding") : String(localized: "Save")) { controller.saveDraft() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!controller.draftCanSave)
                }
            }
            .padding(16)
            .frame(width: UIScale.size(680))
            .background(Color(nsColor: SpacetruckerPalette.gutterBackground).opacity(0.5))
        }
    }
}

extension View {
    /// The patch viewer's look (issue #26): Prussian code background,
    /// the palette's text colour, a hairline edge.
    func codeSurface() -> some View {
        self.foregroundStyle(Color(nsColor: SpacetruckerPalette.plainText))
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: SpacetruckerPalette.codeBackground)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
    }

    /// A finding text editor set like the code: the code font and size,
    /// on the code background; red when its evidence cannot be found.
    func codeEditorStyle(invalid: Bool) -> some View {
        self.font(Font(CodeStyle.font))
            .scrollContentBackground(.hidden)
            .padding(6)
            .codeSurface()
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(invalid ? 0.18 : 0)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.red, lineWidth: invalid ? 2 : 0))
    }
}

/// The + popup: paste a finding, pick the patch and the slop category.
/// The evidence is read from the text as it is typed — a file name,
/// then `L100` or `L100-L110` references to it — and each reference
/// shows whether it lands in the chosen column.
struct PasteFindingForm: View {
    @Bindable var controller: SessionController
    @State private var columnID: UUID?
    @State private var category = ""
    @State private var severity = Severity.minor

    /// Picked by hand, else named in the text ("Implementation A"), else focused.
    private var text: String { controller.pasteFindingText }

    private var column: PatchColumn? {
        controller.columns.first { $0.id == columnID } ?? controller.column(namedIn: text) ?? controller.focusedColumn
    }

    var body: some View {
        let evidence = EvidenceParser.parse(text)
        let hits = column.map { column in evidence.map { controller.resolve($0, in: controller.column(for: $0, default: column)) } } ?? []
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Paste Finding")).font(.ui(.headline))
            let missing = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hits.contains { $0 != nil }
            TextEditor(text: $controller.pasteFindingText)
                .font(.ui(.body))
                .frame(minHeight: UIScale.size(140), maxHeight: UIScale.size(260))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.red, lineWidth: missing ? 2 : 0))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(String(localized: "brew_task.go L100-L110 retries the same call twice…"))
                            .foregroundStyle(.tertiary).padding(.horizontal, 5).allowsHitTesting(false)
                    }
                }
            if missing {
                EvidenceHelp(found: !evidence.isEmpty, patch: column.map { controller.displayLabel($0) } ?? "?")
            }
            HStack {
                Picker(String(localized: "Patch"), selection: Binding(get: { column?.id }, set: { columnID = $0 })) {
                    ForEach(controller.columns) { Text(controller.displayLabel($0)).tag(UUID?.some($0.id)) }
                }
                .frame(maxWidth: UIScale.size(120))
                if columnID == nil, let named = controller.column(namedIn: text) {
                    Text(String(localized: "from the text: \(controller.displayLabel(named))"))
                        .font(.ui(.callout)).foregroundStyle(.secondary).fixedSize()
                }
                Picker(String(localized: "Category"), selection: $category) {
                    ForEach(controller.categories, id: \.self) { Text($0).tag($0) }
                }
            }
            Picker(String(localized: "Severity"), selection: $severity) {
                ForEach(Severity.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(String(localized: "Evidence")).font(.ui(.callout)).foregroundStyle(.secondary)
            if evidence.isEmpty, !missing {
                Text(String(localized: "No references yet. Write a file name, then L100 or L100-L110."))
                    .font(.ui(.callout)).foregroundStyle(.secondary)
            }
            ForEach(Array(evidence.enumerated()), id: \.offset) { i, item in
                Label(item.reference, systemImage: hits[i] == nil ? "xmark.circle" : "checkmark.circle")
                    .font(.ui(.callout).monospaced())
                    .foregroundStyle(hits[i] == nil ? Color.red : Color.secondary)
                    .help(hits[i] == nil ? String(localized: "Not in this patch's version of the file") : "")
            }
            HStack {
                Button(String(localized: "Cancel")) { controller.showPasteFinding = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Add Finding")) {
                    guard let column else { return }
                    controller.addPastedFinding(text, column: column, category: category, severity: severity)
                    controller.pasteFindingText = ""
                    controller.showPasteFinding = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(category.isEmpty || !hits.contains { $0 != nil })
            }
            // Say why Add is off, so it never just looks broken.
            if !missing, !hits.contains(where: { $0 != nil }) {
                Text(String(localized: "Add turns on once the text names a file and its lines, like catalog.go L106-L110."))
                    .font(.ui(.callout)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(16)
        .frame(width: UIScale.size(560))
        .onAppear { if category.isEmpty { category = controller.categories.first ?? "other" } }
    }
}

/// Lays children out left to right and wraps to a new row when the
/// width runs out — for the reference chips of an open finding.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = ([i], size.width, size.height)
            } else {
                current = (current.indices + [i], needed, max(current.height, size.height))
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

/// Shown under finding text whose file and line evidence cannot be
/// found (issue #25): what went wrong, and how to write evidence.
struct EvidenceHelp: View {
    /// Some references were read, but none is in the patch.
    let found: Bool
    let patch: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(found ? String(localized: "These lines are not in patch \(patch)")
                        : String(localized: "No file and line numbers found"),
                  systemImage: "exclamationmark.triangle.fill")
                .font(.ui(.callout).bold()).foregroundStyle(.red)
            Text(String(localized: "Write evidence like this:")).font(.ui(.callout))
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                row("catalog.go L106-L110", String(localized: "a file, then its lines"))
                row("main.go L349", String(localized: "one line"))
                row("L699-L702  or  L699:L702", String(localized: "a range"))
                row("main.go L349, L699", String(localized: "more lines in the same file"))
                row("-L40", String(localized: "removed lines (base side)"))
                row("Implementation A", String(localized: "which patch"))
            }
            if found {
                Text(String(localized: "Check the patch letter, the file name, and that the line numbers are this patch's own numbers."))
                    .font(.ui(.callout)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.red.opacity(0.6)))
    }

    private func row(_ example: String, _ meaning: String) -> some View {
        GridRow {
            Text(example).font(.ui(.callout).monospaced())
            Text(meaning).font(.ui(.callout)).foregroundStyle(.secondary)
        }
    }
}
