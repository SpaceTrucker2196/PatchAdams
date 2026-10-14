import SwiftUI
import AppKit
import ApplyEngine

// One column's code view (FR-9): an AppKit NSTextView (TextKit 1, so
// the gutter can ask the layout manager about line fragments) inside
// an NSScrollView, with a dual line-number ruler. SwiftUI `Text`
// cannot do 10,000 lines with per-line attributes (spec "Stack").

struct CodeTextView: NSViewRepresentable {
    let columnID: UUID
    let lines: [DisplayLine]
    /// Changes whenever `lines` should be re-set on the text storage.
    let contentKey: String
    let scrollRequest: ScrollRequest?
    let controller: SessionController

    func makeCoordinator() -> Coordinator { Coordinator(columnID: columnID, controller: controller) }

    func makeNSView(context: Context) -> CodeContainerView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(containerSize: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 6
        layout.addTextContainer(container)

        let textView = FocusReportingTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300), textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFontPanel = false
        // Non-wrapping: the text view grows with its content in both
        // directions and the scroll view shows the window onto it.
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = []
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.font = CodeStyle.font
        textView.textContainerInset = NSSize(width: 0, height: 4)
        textView.delegate = context.coordinator
        textView.onFocus = { [weak controller] in controller?.focusedColumnID = context.coordinator.columnID }

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scrollView.documentView = textView
        scrollView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsetsZero
        let gutter = LineGutterView(scrollView: scrollView, textView: textView)

        context.coordinator.textView = textView
        context.coordinator.gutter = gutter
        controller.scrollSync.register(columnID, scrollView: scrollView, textView: textView, coordinator: context.coordinator)
        return CodeContainerView(gutter: gutter, scrollView: scrollView)
    }

    func updateNSView(_ container: CodeContainerView, context: Context) {
        let scrollView = container.scrollView
        let coordinator = context.coordinator
        if coordinator.contentKey != contentKey {
            coordinator.contentKey = contentKey
            coordinator.setLines(lines)
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        if let scrollRequest, scrollRequest != coordinator.lastScrollRequest {
            coordinator.lastScrollRequest = scrollRequest
            coordinator.scroll(toDisplayLine: scrollRequest.displayLine, select: true)
        }
    }

    /// Fill whatever SwiftUI offers; never report the document's size.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CodeContainerView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 400, height: proposal.height ?? 300)
    }

    static func dismantleNSView(_ nsView: CodeContainerView, coordinator: Coordinator) {
        coordinator.controller?.scrollSync.unregister(coordinator.columnID)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let columnID: UUID
        weak var controller: SessionController?
        weak var textView: NSTextView?
        weak var gutter: LineGutterView?
        var contentKey = ""
        var lastScrollRequest: ScrollRequest?
        /// Character offset where each display line starts.
        private(set) var lineStarts: [Int] = []
        private(set) var lines: [DisplayLine] = []
        private var suppressSelectionReport = false

        init(columnID: UUID, controller: SessionController) {
            self.columnID = columnID
            self.controller = controller
        }

        func setLines(_ newLines: [DisplayLine]) {
            lines = newLines
            guard let textView, let storage = textView.textStorage else { return }
            let (attributed, starts) = CodeStyle.render(newLines)
            lineStarts = starts
            storage.beginEditing()
            storage.setAttributedString(attributed)
            storage.endEditing()
            gutter?.lineStarts = starts
            gutter?.lines = newLines
        }

        /// Display line index containing character `offset`.
        func lineIndex(forCharacter offset: Int) -> Int {
            var lo = 0, hi = lineStarts.count - 1
            if hi < 0 { return 0 }
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if lineStarts[mid] <= offset { lo = mid } else { hi = mid - 1 }
            }
            return lo
        }

        func characterRange(ofLine index: Int) -> NSRange {
            guard index < lineStarts.count else { return NSRange(location: 0, length: 0) }
            let start = lineStarts[index]
            let end = index + 1 < lineStarts.count ? lineStarts[index + 1] : (textView?.string.utf16.count ?? start)
            return NSRange(location: start, length: max(0, end - start))
        }

        func scroll(toDisplayLine index: Int, select: Bool) {
            guard let textView, index < lineStarts.count else { return }
            let range = characterRange(ofLine: index)
            if select {
                suppressSelectionReport = true
                textView.setSelectedRange(range)
                suppressSelectionReport = false
            }
            guard let layout = textView.layoutManager, let container = textView.textContainer else { return }
            let glyphRange = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphRange, in: container)
            var target = rect.origin
            target.y += textView.textContainerInset.height
            target.x = 0
            // Put the line a third of the way down the view.
            if let clip = textView.enclosingScrollView?.contentView {
                target.y = max(0, target.y - clip.bounds.height / 3)
                clip.scroll(to: target)
                textView.enclosingScrollView?.reflectScrolledClipView(clip)
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !suppressSelectionReport, let textView, let controller else { return }
            let range = textView.selectedRange()
            let first = lineIndex(forCharacter: range.location)
            // A selection ending exactly at a line start does not include that line.
            let endOffset = range.length > 0 ? range.location + range.length - 1 : range.location
            let last = lineIndex(forCharacter: endOffset)
            controller.selections[columnID] = first..<(max(first, last) + 1)
            controller.focusedColumnID = columnID
        }
    }
}

/// Reports first-responder changes so ⌘-shortcuts act on the right column.
final class FocusReportingTextView: NSTextView {
    var onFocus: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { onFocus?() }
        return ok
    }

    // Keep the view read-only even for drag-and-drop text.
    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool { false }
}

enum CodeStyle {
    static var font: NSFont { NSFont.monospacedSystemFont(ofSize: 12, weight: .regular) }

    static var addedBackground: NSColor { NSColor.systemGreen.withAlphaComponent(0.18) }
    static var removedBackground: NSColor { NSColor.systemRed.withAlphaComponent(0.16) }
    static var elidedForeground: NSColor { .tertiaryLabelColor }

    /// The attributed text and each line's start offset (UTF-16).
    static func render(_ lines: [DisplayLine]) -> (NSAttributedString, [Int]) {
        let out = NSMutableAttributedString()
        var starts: [Int] = []
        starts.reserveCapacity(lines.count)
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.textColor]
        let added: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.textColor, .backgroundColor: addedBackground]
        let removed: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor, .backgroundColor: removedBackground, .strikethroughStyle: 0]
        let elided: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: elidedForeground]
        var offset = 0
        for (i, line) in lines.enumerated() {
            starts.append(offset)
            let text = line.text + (i == lines.count - 1 ? "" : "\n")
            let attrs: [NSAttributedString.Key: Any]
            switch line.kind {
            case .added: attrs = added
            case .removed: attrs = removed
            case .context: attrs = (line.baseLine == nil && line.postLine == nil) ? elided : base
            }
            out.append(NSAttributedString(string: text, attributes: attrs))
            offset += text.utf16.count
        }
        return (out, starts)
    }
}
