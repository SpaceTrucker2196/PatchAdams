import SwiftUI

/// Interface scale (issue #29): one factor for every piece of window
/// text and the fixed sizes around it — headers, sidebars, footers —
/// so the same window reads well on a 5K display and on a laptop. The
/// code itself has its own size, the content scale (`CodeStyle`, issue
/// #10). macOS text styles have fixed point sizes, so the views ask for
/// `.ui(.callout)` instead of `.callout`.
enum UIScale {
    static let key = "interfaceScale"
    static let range = 0.8...2.0
    static let step = 0.1

    static var factor: CGFloat {
        // `double(forKey:)` also reads a launch argument (`-interfaceScale 1.4`), which arrives as text.
        let defaults = UserDefaults.standard
        let value = defaults.object(forKey: key) == nil ? 1 : defaults.double(forKey: key)
        return CGFloat(min(max(value, range.lowerBound), range.upperBound))
    }

    /// A length at the current scale.
    static func size(_ points: CGFloat) -> CGFloat { (points * factor).rounded() }

    /// The point size macOS gives a text style, at the current scale.
    static func size(for style: Font.TextStyle) -> CGFloat {
        let base: CGFloat = switch style {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline, .body: 13
        case .callout: 12
        case .subheadline: 11
        default: 10   // footnote, caption, caption2
        }
        return size(base)
    }

    static func zoom(by steps: Int) {
        let current = Double(factor)
        let next = ((current + Double(steps) * step) * 10).rounded() / 10
        UserDefaults.standard.set(min(max(next, range.lowerBound), range.upperBound), forKey: key)
    }

    static func reset() { UserDefaults.standard.set(1.0, forKey: key) }
}

extension Font {
    /// A text style at the interface scale; bold for `.headline`, as macOS draws it.
    static func ui(_ style: Font.TextStyle) -> Font {
        .system(size: UIScale.size(for: style), weight: style == .headline ? .bold : .regular)
    }
}

/// Applied inside a window's top view (not around it: wrapping the
/// `WindowGroup` content kept the window from opening). Sets the scaled
/// body font and rebuilds the views when the interface scale changes,
/// so every `.ui` font and scaled frame picks up the new factor.
struct ScaledInterface: ViewModifier {
    @AppStorage(UIScale.key) private var scale = 1.0

    func body(content: Content) -> some View {
        content
            .font(.ui(.body))
            .controlSize(scale >= 1.35 ? .large : scale <= 0.85 ? .small : .regular)
            .id(scale)
    }
}

extension View {
    func scaledInterface() -> some View { modifier(ScaledInterface()) }
}

/// The − / + pairs in the status bar: interface scale and code size.
struct ScaleControls: View {
    @AppStorage(UIScale.key) private var scale = 1.0
    @AppStorage(CodeStyle.fontSizeKey) private var codeSize = CodeStyle.defaultFontSize

    var body: some View {
        HStack(spacing: 10) {
            pair(String(localized: "Interface"), value: "\(Int((scale * 100).rounded()))%",
                 minus: { UIScale.zoom(by: -1) }, plus: { UIScale.zoom(by: 1) }, reset: { UIScale.reset() },
                 help: String(localized: "Interface scale: panels, headers and footers (⌥⌘− / ⌥⌘=)"))
            pair(String(localized: "Code"), value: "\(Int(codeSize)) pt",
                 minus: { CodeStyle.zoom(by: -1) }, plus: { CodeStyle.zoom(by: 1) }, reset: { CodeStyle.resetZoom() },
                 help: String(localized: "Content scale: the code and findings text (⌘− / ⌘=)"))
        }
    }

    private func pair(_ title: String, value: String, minus: @escaping () -> Void, plus: @escaping () -> Void,
                      reset: @escaping () -> Void, help: String) -> some View {
        HStack(spacing: 3) {
            Text(title).font(.ui(.callout)).foregroundStyle(.secondary)
            Button(action: minus) { Image(systemName: "minus") }
            Button(action: reset) { Text(value).font(.ui(.callout).monospacedDigit()).frame(minWidth: UIScale.size(38)) }
                .help(String(localized: "Back to 100% / 12 pt"))
            Button(action: plus) { Image(systemName: "plus") }
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
