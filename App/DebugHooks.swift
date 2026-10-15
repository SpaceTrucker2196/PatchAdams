#if DEBUG
import AppKit
import SwiftUI
import ApplyEngine
import SessionModel

/// Launch arguments for driving the real window from a shell, used by
/// the factory to check the M2 gates and take screenshots:
///
///   --demo                 open the four Go fixtures on a merged synthetic base
///   --patches a.patch,b.patch   open these patches on a merged synthetic base
///   --file <path>          select this file in the tree
///   --select A:12-20       select display lines 12…20 (1-based) in column A, copy the reference
///   --scroll B:1200        scroll column B so display line 1200 is at the top (scroll lock follows)
///   --golden B             set column B golden (logs the time to re-render every column)
///   --search "text"        search all columns, log hits per file and column
///   --pin                  pin the current selection
///   --open <pkg>           open a .patchadam session instead of --demo / --patches
///   --blind                turn blind mode on before anything else
///   --finding "A:10-20|title|category|severity[|notflagged]"   add a finding from that region (repeatable)
///   --rank "A=1,B=2"       set ranks; --rationale "text" sets the rationale
///   --save <pkg>           save the session package; --export-md <file> writes the Markdown
///   --state                log column order, golden, findings, pins, blind mapping
///   --stress               time rendering a 10,000-line synthetic file
///   --shot <png>           after everything else, render the window to this PNG
///
/// Every step logs to stderr as `hook: …`. Debug builds only.
@MainActor
enum DebugHooks {
    static func run(_ controller: SessionController) {
        let args = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        guard args.contains("--demo") || args.contains("--stress") || value(after: "--shot") != nil || value(after: "--patches") != nil || value(after: "--open") != nil else { return }

        if let pkg = value(after: "--open") { controller.open(sessionURL: URL(fileURLWithPath: pkg)) }

        if args.contains("--demo") {
            let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            controller.openDemoSession(fixtures: (15...18).map { root.appendingPathComponent("Fixtures/patches/fixture-\($0).patch") },
                                       request: "Demo: the four kettle patches (kettle-1 … kettle-4) against a base rebuilt from their hunks.")
        }
        if let list = value(after: "--patches") {
            controller.openDemoSession(fixtures: list.split(separator: ",").map { URL(fileURLWithPath: String($0)) })
        }
        if let path = value(after: "--file") { controller.selectedPath = path }

        // A review-sized window on the active display, so a capture sees it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if let window = NSApp.windows.first(where: { $0.frame.width > 900 }), let screen = NSScreen.main {
                let v = screen.visibleFrame
                window.setFrame(NSRect(x: v.minX + 40, y: v.minY + 40, width: min(1680, v.width - 80), height: min(1000, v.height - 80)), display: true)
                window.makeKeyAndOrderFront(nil)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if args.contains("--blind"), !controller.blind.isOn {
                controller.toggleBlind()
                log("blind on: seed \(controller.blind.seed) order \(controller.columns.map { "\($0.label)→\(controller.displayLabel($0))" }.joined(separator: " "))")
            }
            // Findings straight from regions (FR-25): the reference is generated, never typed.
            var i = 0
            while i + 1 < args.count {
                if args[i] == "--finding" {
                    let parts = args[i + 1].split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                    if parts.count >= 4, let (id, from, to) = parse(parts[0], controller), let path = controller.selectedPath {
                        controller.focusedColumnID = id
                        controller.selections[id] = (from - 1)..<to
                        controller.selectionIsEmpty[id] = false
                        controller.locate(SelectionRegion(columnID: id, path: path, lines: (from - 1)..<to))
                        controller.newFindingFromSelection()
                        controller.findingDraft?.finding.title = parts[1]
                        controller.findingDraft?.finding.category = parts[2]
                        controller.findingDraft?.finding.severity = Severity(rawValue: parts[3]) ?? .minor
                        controller.findingDraft?.finding.notFlagged = parts.count > 4 && parts[4] == "notflagged"
                        controller.saveDraft()
                        log("finding \(parts[0]) → \(controller.findings.last?.reference ?? "none") \(controller.findings.last?.title ?? "")")
                    } else {
                        log("finding \(args[i + 1]) → could not parse")
                    }
                    i += 2
                } else {
                    i += 1
                }
            }
            if let ranks = value(after: "--rank") {
                for pair in ranks.split(separator: ",") {
                    let kv = pair.split(separator: "=")
                    if kv.count == 2, let n = Int(kv[1]) { controller.setRank(n, for: String(kv[0])) }
                }
                log("ranks \(controller.ranking.ranks.sorted { $0.key < $1.key })")
            }
            if let text = value(after: "--rationale") { controller.ranking.rationale = text }
            if let label = value(after: "--golden"), let column = controller.columns.first(where: { $0.label == label }) {
                let start = Date()
                controller.setGolden(column.id)
                var rendered = 0
                for other in controller.visibleColumns {
                    for row in controller.allRows { _ = controller.displayLines(column: other, path: row.path); rendered += 1 }
                    _ = controller.goldenSummary(for: other)
                }
                log("golden \(label) → \(rendered) column-files rendered in \(Int(Date().timeIntervalSince(start) * 1000)) ms; summaries: " +
                    controller.visibleColumns.compactMap { c in controller.goldenSummary(for: c).map { "\(c.label)=\($0.files)f/\($0.lines)l" } }.joined(separator: " "))
            }
            if let query = value(after: "--search") {
                controller.searchQuery = query
                controller.runSearch()
                let total = controller.searchResults.reduce(0) { $0 + $1.count }
                log("search \"\(query)\" → \(total) hits in \(controller.searchResults.count) files; per column: " +
                    Dictionary(grouping: controller.searchResults.flatMap(\.columns), by: \.label).map { "\($0.key)=\($0.value.reduce(0) { $0 + $1.hits.count })" }.sorted().joined(separator: " "))
                for group in controller.searchResults.prefix(3) {
                    log("  \(group.path): " + group.columns.map { c in "\(c.label) " + c.hits.prefix(3).map { "L\($0.displayIndex + 1)" }.joined(separator: ",") }.joined(separator: " | "))
                }
            }
        }
        // Stage 2 (+5 s): the selection, once a golden switch has re-laid the text views.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if let spec = value(after: "--select"), let (id, from, to) = parse(spec, controller) {
                controller.scrollSync.select(id, lines: (from - 1)..<to)
                controller.focusedColumnID = id
                controller.copyReference()
                log("select \(spec) → selection \(controller.selections[id].map { "\($0)" } ?? "none") reference \(controller.currentReference()?.description ?? "none") pasteboard \(NSPasteboard.general.string(forType: .string) ?? "")")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    for column in controller.visibleColumns where column.id != id {
                        if let anchor = controller.anchor(for: column.id) {
                            let lines = controller.displayLines(column: column, path: controller.selectedPath ?? "")
                            let first = anchor.lines.lowerBound < lines.count ? lines[anchor.lines.lowerBound].text.trimmingCharacters(in: .whitespaces).prefix(50) : ""
                            log("anchor in \(column.label): \(anchor.status) \(String(format: "%.2f", anchor.confidence)) lines \(anchor.lines.lowerBound + 1)..<\(anchor.lines.upperBound + 1) via \(anchor.viaIdentifier ?? "position") nearest \(controller.nearestHunkReference(anchor, path: controller.selectedPath ?? "") ?? "-") : \(first)")
                        } else {
                            log("anchor in \(column.label): none")
                        }
                    }
                    if args.contains("--pin") { controller.pinSelection(); log("pins: \(controller.pins.map(\.reference))") }
                }
            }
            if let spec = value(after: "--scroll"), let (id, line, _) = parse(spec, controller) {
                controller.scrollSync.scroll(id, toTopLine: line - 1)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    for column in controller.visibleColumns {
                        let top = controller.scrollSync.topLine(of: column.id) ?? -1
                        let lines = controller.displayLines(column: column, path: controller.selectedPath ?? "")
                        let anchor = top >= 0 && top < lines.count ? lines.anchorBase(at: top) : nil
                        let text = top >= 0 && top < lines.count ? lines[top].text : ""
                        log("scroll \(spec) → column \(column.label) top display line \(top + 1) base \(anchor.map(String.init) ?? "-") post \(top >= 0 && top < lines.count ? (lines[top].postLine.map(String.init) ?? "-") : "-") : \(text.prefix(60))")
                    }
                }
            }
        }
        // Stage 3 (+8 s): persist and report, after the selection settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            if let pkg = value(after: "--save") {
                controller.sessionName = URL(fileURLWithPath: pkg).deletingPathExtension().lastPathComponent
                controller.save(to: URL(fileURLWithPath: pkg))
                log("saved \(pkg): \(controller.statusMessage ?? "")")
            }
            if let file = value(after: "--export-md") {
                let md = controller.markdownExport()
                try? Data(md.utf8).write(to: URL(fileURLWithPath: file))
                log("export-md \(file): \(md.count) chars, \(md.split(separator: "\n").count) lines")
            }
            if args.contains("--state") {
                log("state: columns \(controller.columns.map { "\($0.label)(\($0.sourceName))\($0.isHidden ? " hidden" : "")" }.joined(separator: " ")) golden \(controller.goldenID.flatMap { id in controller.columns.first { $0.id == id }?.label } ?? "none") blind \(controller.blind.isOn) seed \(controller.blind.seed) mapping \(controller.blindMapping.sorted { $0.key < $1.key })")
                log("state: \(controller.findings.count) findings \(controller.findings.map { "\($0.label) \($0.reference) [\($0.severity.rawValue)] \($0.title)" }) pins \(controller.pins.map(\.reference)) ranks \(controller.ranking.ranks.sorted { $0.key < $1.key }) rationale \"\(controller.ranking.rationale)\" request \(controller.requestText.count) chars")
            }
            if args.contains("--stress") {
                let lines = (1...10_000).map { DisplayLine(kind: $0 % 50 == 0 ? .added : .context, baseLine: $0, postLine: $0, text: "func stress\($0)() { return \($0) * 2 } // synthetic") }
                let start = Date()
                let (attributed, starts) = CodeStyle.render(lines)
                let storage = NSTextStorage(attributedString: attributed)
                let layout = NSLayoutManager()
                storage.addLayoutManager(layout)
                let container = NSTextContainer(containerSize: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
                layout.addTextContainer(container)
                _ = layout.glyphRange(for: container)   // force full layout
                log("stress: 10,000 lines rendered and laid out in \(Int(Date().timeIntervalSince(start) * 1000)) ms (\(starts.count) line starts)")
            }
        }

        if let shot = value(after: "--shot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 11) {
                if let view = NSApp.windows.first(where: { $0.frame.width > 900 })?.contentView,
                   let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    if let png = rep.representation(using: .png, properties: [:]) {
                        try? png.write(to: URL(fileURLWithPath: shot))
                        log("shot written to \(shot)")
                    }
                }
            }
        }
    }

    /// `A:12-20` → (column id, 12, 20); `B:1200` → (id, 1200, 1200).
    private static func parse(_ spec: String, _ controller: SessionController) -> (UUID, Int, Int)? {
        let parts = spec.split(separator: ":")
        guard parts.count == 2, let column = controller.columns.first(where: { $0.label == parts[0] }) else { return nil }
        let numbers = parts[1].split(separator: "-").compactMap { Int($0) }
        guard let from = numbers.first else { return nil }
        return (column.id, from, numbers.count > 1 ? numbers[1] : from)
    }

    private static func log(_ message: String) {
        FileHandle.standardError.write(Data("hook: \(message)\n".utf8))
    }
}
#endif
