import AppKit
import ApplyEngine
import AlignmentEngine

/// Scroll lock (FR-10): when one column scrolls, the others follow to
/// the aligned position — by anchor, not raw line number. In Phase 2
/// the anchor is the base line: the top visible line maps to its base
/// line through the column's line map, and every other column scrolls
/// to the post line at or after that base line. Phase 3 replaces the
/// mapping with the alignment engine's anchors.
@MainActor
final class ScrollSync {
    private struct Entry {
        weak var scrollView: NSScrollView?
        weak var textView: NSTextView?
        weak var coordinator: CodeTextView.Coordinator?
    }

    private var entries: [UUID: Entry] = [:]
    private var observers: [UUID: any NSObjectProtocol] = [:]
    private var syncing = false
    /// `isEnabled` is set by the controller; the sync reads it on every scroll.
    var isEnabled: () -> Bool = { true }
    /// Which number is the shared frame for a column: `postLine` for the
    /// golden column, `baseLine` for the rest. Set by the controller.
    var usesPostLineFrame: (UUID) -> Bool = { _ in false }

    func register(_ id: UUID, scrollView: NSScrollView, textView: NSTextView, coordinator: CodeTextView.Coordinator) {
        entries[id] = Entry(scrollView: scrollView, textView: textView, coordinator: coordinator)
        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        observers[id] = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didScroll(id) }
        }
    }

    func unregister(_ id: UUID) {
        if let observer = observers.removeValue(forKey: id) { NotificationCenter.default.removeObserver(observer) }
        entries[id] = nil
    }

    func focus(_ id: UUID) {
        guard let textView = entries[id]?.textView else { return }
        textView.window?.makeFirstResponder(textView)
    }

    /// Select display lines `range` in a column, as a user drag would.
    func select(_ id: UUID, lines range: Range<Int>) {
        guard let entry = entries[id], let textView = entry.textView, let coordinator = entry.coordinator else { return }
        let start = coordinator.characterRange(ofLine: range.lowerBound).location
        let endRange = coordinator.characterRange(ofLine: max(range.lowerBound, range.upperBound - 1))
        textView.setSelectedRange(NSRange(location: start, length: NSMaxRange(endRange) - start))
    }

    /// Scroll a column so display line `line` is at the top, as a wheel would.
    func scroll(_ id: UUID, toTopLine line: Int) {
        guard let entry = entries[id], let scrollView = entry.scrollView, let rect = lineRect(entry, line: line) else { return }
        let clip = scrollView.contentView
        clip.scroll(to: NSPoint(x: 0, y: rect.minY))
        scrollView.reflectScrolledClipView(clip)
    }

    /// Index of the display line at the top of the column's view.
    func topLine(of id: UUID) -> Int? {
        guard let entry = entries[id], let textView = entry.textView, let coordinator = entry.coordinator,
              let layout = textView.layoutManager, let container = textView.textContainer else { return nil }
        var point = textView.visibleRect.origin
        point.y -= textView.textContainerInset.height
        point.y = max(0, point.y)
        let glyph = layout.glyphIndex(for: point, in: container)
        let char = layout.characterIndexForGlyph(at: glyph)
        return coordinator.lineIndex(forCharacter: char)
    }

    private func didScroll(_ source: UUID) {
        guard !syncing, isEnabled(), entries.count > 1 else { return }
        guard let top = topLine(of: source), let sourceLines = entries[source]?.coordinator?.lines, top < sourceLines.count else { return }
        guard let anchor = sourceLines.anchorReference(at: top, key: usesPostLineFrame(source) ? \.postLine : \.baseLine) else { return }
        guard let sourceTextView = entries[source]?.textView else { return }
        // Keep the fractional offset inside the top line so following is smooth.
        let sourceLineRect = lineRect(entries[source]!, line: top)
        let fraction = sourceTextView.visibleRect.origin.y - (sourceLineRect?.minY ?? 0)

        syncing = true
        defer { syncing = false }
        for (id, entry) in entries where id != source {
            guard let coordinator = entry.coordinator, let scrollView = entry.scrollView else { continue }
            guard let target = coordinator.lines.index(atOrAfterReference: anchor, key: usesPostLineFrame(id) ? \.postLine : \.baseLine) else { continue }
            guard let rect = lineRect(entry, line: target) else { continue }
            let clip = scrollView.contentView
            let maxY = max(0, (scrollView.documentView?.frame.height ?? 0) - clip.bounds.height)
            let y = min(maxY, max(0, rect.minY + fraction))
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
            scrollView.reflectScrolledClipView(clip)
        }
    }

    private func lineRect(_ entry: Entry, line: Int) -> NSRect? {
        guard let textView = entry.textView, let coordinator = entry.coordinator,
              let layout = textView.layoutManager, let container = textView.textContainer else { return nil }
        let range = coordinator.characterRange(ofLine: line)
        let glyphRange = layout.glyphRange(forCharacterRange: NSRange(location: range.location, length: 0), actualCharacterRange: nil)
        var rect = layout.lineFragmentRect(forGlyphAt: min(glyphRange.location, max(0, layout.numberOfGlyphs - 1)), effectiveRange: nil)
        if layout.numberOfGlyphs == 0 { rect = .zero }
        rect.origin.y += textView.textContainerInset.height
        _ = container
        return rect
    }
}
