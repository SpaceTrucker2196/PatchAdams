import AppKit
import ApplyEngine

/// The dual line-number gutter (FR-9): base line number on the left,
/// post-patch line number on the right, a colour bar for added and
/// removed lines. A plain view beside the scroll view — not an
/// `NSRulerView`, whose content layer on macOS 26+ is pane-sized and
/// unclipped, so a background fill there paints over the neighbours.
/// Draws only the visible line fragments, and only inside its bounds.
final class LineGutterView: NSView {
    weak var textView: NSTextView?
    weak var scrollView: NSScrollView?
    var lines: [DisplayLine] = [] { didSet { numberFont = Self.matchingCodeFont(); updateWidth(); needsDisplay = true } }
    var lineStarts: [Int] = []

    /// Same point size as the code (Settings and zoom), so a number
    /// reads at the size of the line beside it. A font change re-sets
    /// `lines` through the column's content key, which refreshes this.
    private var numberFont = matchingCodeFont()
    private static func matchingCodeFont() -> NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: CodeStyle.font.pointSize, weight: .regular)
    }
    private let padding: CGFloat = 6
    private var widthConstraint: NSLayoutConstraint?

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        self.scrollView = scrollView
        super.init(frame: .zero)
        clipsToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        widthConstraint = widthAnchor.constraint(equalToConstant: 60)
        widthConstraint?.isActive = true
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        // Selector observers are removed automatically on dealloc.
        NotificationCenter.default.addObserver(self, selector: #selector(clipDidScroll(_:)), name: NSView.boundsDidChangeNotification, object: clip)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func clipDidScroll(_ note: Notification) { needsDisplay = true }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }

    private var charWidth: CGFloat { ("0" as NSString).size(withAttributes: [.font: numberFont]).width }

    private var digits: Int {
        let maxBase = lines.lazy.compactMap(\.baseLine).max() ?? 0
        let maxPost = lines.lazy.compactMap(\.postLine).max() ?? 0
        return max(2, String(max(maxBase, maxPost)).count)
    }

    func updateWidth() {
        widthConstraint?.constant = ceil(charWidth * CGFloat(digits * 2) + padding * 3 + 4)
    }

    override func draw(_ dirtyRect: NSRect) {
        SpacetruckerPalette.gutterBackground.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()

        guard let textView, let layout = textView.layoutManager, let container = textView.textContainer, !lines.isEmpty else { return }
        let visible = textView.visibleRect
        let glyphRange = layout.glyphRange(forBoundingRect: visible, in: container)
        guard glyphRange.length > 0 else { return }

        let columnWidth = charWidth * CGFloat(digits)
        let baseRight = padding + 4 + columnWidth
        let postRight = baseRight + padding + columnWidth
        let numberAttrs: [NSAttributedString.Key: Any] = [.font: numberFont, .foregroundColor: NSColor.secondaryLabelColor]
        let inset = textView.textContainerInset.height

        var glyph = glyphRange.location
        let end = NSMaxRange(glyphRange)
        while glyph < end {
            var fragmentRange = NSRange()
            let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &fragmentRange)
            let charIndex = layout.characterIndexForGlyph(at: glyph)
            let index = CodeStyle.lineIndex(forCharacter: charIndex, in: lineStarts)
            // Document y → gutter y: the gutter's top is the clip view's top.
            let y = fragment.minY + inset - visible.minY
            if index < lines.count, y + fragment.height >= 0, y <= bounds.height {
                let line = lines[index]
                if index % 2 == 1 {
                    SpacetruckerPalette.zebraStripe.setFill()
                    NSRect(x: 0, y: y, width: bounds.width - 1, height: fragment.height).fill()
                }
                switch line.kind {
                case .added: NSColor.systemGreen.withAlphaComponent(0.6).setFill(); NSRect(x: 0, y: y, width: 3, height: fragment.height).fill()
                case .removed: NSColor.systemRed.withAlphaComponent(0.6).setFill(); NSRect(x: 0, y: y, width: 3, height: fragment.height).fill()
                case .context: break
                }
                let baseline = y + (fragment.height - numberFont.ascender + numberFont.descender) / 2
                if let base = line.baseLine {
                    let s = NSAttributedString(string: String(base), attributes: numberAttrs)
                    s.draw(at: NSPoint(x: baseRight - s.size().width, y: baseline))
                }
                if let post = line.postLine {
                    let s = NSAttributedString(string: String(post), attributes: numberAttrs)
                    s.draw(at: NSPoint(x: postRight - s.size().width, y: baseline))
                }
            }
            if fragmentRange.length == 0 { break }
            glyph = NSMaxRange(fragmentRange)
        }
    }
}

/// Gutter on the left, scroll view on the right, as one AppKit view
/// for the representable to hand to SwiftUI.
final class CodeContainerView: NSView {
    let gutter: LineGutterView
    let scrollView: NSScrollView

    init(gutter: LineGutterView, scrollView: NSScrollView) {
        self.gutter = gutter
        self.scrollView = scrollView
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        clipsToBounds = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(gutter)
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            gutter.leadingAnchor.constraint(equalTo: leadingAnchor),
            gutter.topAnchor.constraint(equalTo: topAnchor),
            gutter.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: gutter.trailingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }
}
