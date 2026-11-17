import AppKit
import SwiftUI

/// Prose the reviewer types outside a finding's description — titles,
/// the correctness note, the rationale, the task fields, the paste box —
/// in an `NSTextView`, so the system's spelling and grammar check it
/// (issue #36). SwiftUI's `TextField` and `TextEditor` give neither on
/// macOS. `scrolls` puts it in a scroll view for a fixed frame; otherwise
/// it grows to fit its text, as `FindingTextView` does. `singleLine`
/// sends Return and Tab on to the next field.
struct ProseTextView: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var textColor: NSColor = .textColor
    var scrolls = false
    var singleLine = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSView {
        let view: NSTextView
        let container: NSView
        if scrolls {
            let scroll = NSTextView.scrollableTextView()
            scroll.drawsBackground = true
            scroll.backgroundColor = .textBackgroundColor
            scroll.borderType = .noBorder
            scroll.autohidesScrollers = true
            view = scroll.documentView as! NSTextView
            container = scroll
        } else {
            view = NSTextView()
            view.textContainer?.widthTracksTextView = true
            view.isVerticallyResizable = false
            view.isHorizontallyResizable = false
            container = view
        }
        view.drawsBackground = false
        view.isRichText = false
        view.allowsUndo = true
        view.useSystemEditing()
        view.textContainerInset = NSSize(width: 0, height: scrolls ? 6 : 2)
        view.delegate = context.coordinator
        view.string = text
        return container
    }

    private func textView(in container: NSView) -> NSTextView? {
        (container as? NSScrollView)?.documentView as? NSTextView ?? container as? NSTextView
    }

    func updateNSView(_ container: NSView, context: Context) {
        context.coordinator.parent = self
        guard let view = textView(in: container) else { return }
        if view.string != text {
            // Text set by code (a loaded session, a hook) lands after this
            // update, not inside it: a text view re-laid inside a SwiftUI
            // update asks the window to re-measure while the update is
            // still running, and that crashed in Observation every time.
            // Typing never comes here: the binding already holds it.
            DispatchQueue.main.async { [weak view] in
                guard let view, let current = context.coordinator.parent.text as String?, view.string != current else { return }
                let selection = view.selectedRanges
                view.string = current
                // AppKit refuses an empty selection list; the view then keeps its own.
                let kept = selection.filter { NSMaxRange($0.rangeValue) <= (current as NSString).length }
                if !kept.isEmpty { view.selectedRanges = kept }
                view.checkTextInDocument(nil)
            }
        }
        // Font and colour over the whole text, as `FindingTextView` does;
        // the selection and the typing position are left alone.
        guard let storage = view.textStorage else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        storage.beginEditing()
        storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        storage.endEditing()
        view.typingAttributes = attributes
        view.insertionPointColor = textColor
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView container: NSView, context: Context) -> CGSize? {
        guard !scrolls, let view = textView(in: container),
              let textContainer = view.textContainer, let layout = view.layoutManager else { return nil }
        let width = proposal.width ?? 300
        textContainer.containerSize = NSSize(width: width - view.textContainerInset.width * 2, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: textContainer)
        let height = layout.usedRect(for: textContainer).height + view.textContainerInset.height * 2
        return CGSize(width: width, height: max(height, font.pointSize * 1.4 + view.textContainerInset.height * 2))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ProseTextView
        init(_ parent: ProseTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }

        func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard parent.singleLine else { return false }
            switch selector {
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                view.window?.selectNextKeyView(nil)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                view.window?.selectPreviousKeyView(nil)
                return true
            default:
                return false
            }
        }
    }
}

extension NSTextView {
    /// The system's editing tools (issues #34, #36): spelling and grammar
    /// as you type, the Find bar (⌘F), and the substitutions the user has
    /// turned on in System Settings. The right-click menu has the rest.
    func useSystemEditing() {
        isContinuousSpellCheckingEnabled = true
        isGrammarCheckingEnabled = true
        isAutomaticSpellingCorrectionEnabled = NSSpellChecker.isAutomaticSpellingCorrectionEnabled
        isAutomaticQuoteSubstitutionEnabled = NSSpellChecker.isAutomaticQuoteSubstitutionEnabled
        isAutomaticDashSubstitutionEnabled = NSSpellChecker.isAutomaticDashSubstitutionEnabled
        isAutomaticTextReplacementEnabled = NSSpellChecker.isAutomaticTextReplacementEnabled
        smartInsertDeleteEnabled = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
    }
}

extension NSFont {
    /// A text style at the interface scale, the AppKit twin of `Font.ui`.
    static func ui(_ style: Font.TextStyle, weight: NSFont.Weight? = nil) -> NSFont {
        .systemFont(ofSize: UIScale.size(for: style), weight: weight ?? (style == .headline ? .bold : .regular))
    }
}

extension View {
    /// Grey hint text over an empty prose field, where the first line goes.
    func prosePlaceholder(_ hint: String, shown: Bool, inset: CGFloat = 2) -> some View {
        overlay(alignment: .topLeading) {
            if shown {
                Text(hint).foregroundStyle(.tertiary)
                    .padding(.horizontal, 5).padding(.vertical, inset).allowsHitTesting(false)
            }
        }
    }

    /// A one-line prose field drawn like a bordered text field.
    func proseField() -> some View {
        self.padding(.horizontal, 4).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(nsColor: .separatorColor)))
    }
}
