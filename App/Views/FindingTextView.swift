import AppKit
import SwiftUI

/// The open finding's text (issues #31, #33): editable like a text box,
/// with every reference in it — `catalog.go L106-L110` — a link. A click
/// on one jumps to its lines, as its button does; the last one clicked
/// is washed amber. An `NSTextView`, because SwiftUI's `TextEditor`
/// cannot say where a click landed. It grows to fit the text.
struct FindingTextView: NSViewRepresentable {
    @Binding var text: String
    /// Where each reference is written, in the order of the buttons.
    var sources: [NSRange]
    var active: NSRange?
    var onClick: (Int) -> Void

    static let scheme = "patchadam-evidence"

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView()
        view.isRichText = false
        view.allowsUndo = true
        view.drawsBackground = false
        // The system's editing tools (issue #34): spelling and grammar as
        // you type, the Find bar (⌘F), and the substitutions the user has
        // turned on in System Settings. The right-click menu has the rest.
        view.isContinuousSpellCheckingEnabled = true
        view.isGrammarCheckingEnabled = true
        view.isAutomaticSpellingCorrectionEnabled = NSSpellChecker.isAutomaticSpellingCorrectionEnabled
        view.isAutomaticQuoteSubstitutionEnabled = NSSpellChecker.isAutomaticQuoteSubstitutionEnabled
        view.isAutomaticDashSubstitutionEnabled = NSSpellChecker.isAutomaticDashSubstitutionEnabled
        view.isAutomaticTextReplacementEnabled = NSSpellChecker.isAutomaticTextReplacementEnabled
        view.smartInsertDeleteEnabled = true
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.textContainerInset = NSSize(width: 0, height: 2)
        view.textContainer?.widthTracksTextView = true
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.delegate = context.coordinator
        // Links look like the code's text, underlined, so the finding still reads as prose.
        view.linkTextAttributes = [
            .foregroundColor: SpacetruckerPalette.plainText,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: SpacetruckerPalette.amber,
            .cursor: NSCursor.pointingHand,
        ]
        view.string = text
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        context.coordinator.parent = self
        if view.string != text {
            let selection = view.selectedRanges
            view.string = text
            view.selectedRanges = selection.filter { NSMaxRange($0.rangeValue) <= (text as NSString).length }
        }
        style(view)
    }

    /// Font, colour, links and the amber wash, over the whole text; the
    /// selection and the typing position are left alone.
    private func style(_ view: NSTextView) {
        guard let storage = view.textStorage else { return }
        let whole = NSRange(location: 0, length: storage.length)
        let plain: [NSAttributedString.Key: Any] = [.font: CodeStyle.font, .foregroundColor: SpacetruckerPalette.plainText]
        storage.beginEditing()
        storage.setAttributes(plain, range: whole)
        for (i, source) in sources.enumerated() where NSMaxRange(source) <= storage.length {
            storage.addAttribute(.link, value: URL(string: "\(Self.scheme)://\(i)")!, range: source)
        }
        if let active, NSMaxRange(active) <= storage.length {
            storage.addAttribute(.backgroundColor, value: SpacetruckerPalette.amber.withAlphaComponent(0.55), range: active)
        }
        storage.endEditing()
        view.typingAttributes = plain
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NSTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        guard let container = view.textContainer, let layout = view.layoutManager else { return nil }
        container.containerSize = NSSize(width: width - view.textContainerInset.width * 2, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let height = layout.usedRect(for: container).height + view.textContainerInset.height * 2
        return CGSize(width: width, height: max(height + CodeStyle.font.pointSize, UIScale.size(80)))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: FindingTextView
        init(_ parent: FindingTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL, url.scheme == FindingTextView.scheme, let index = Int(url.host ?? "") else { return false }
            parent.onClick(index)
            return true
        }
    }
}
