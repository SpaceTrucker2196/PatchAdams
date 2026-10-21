import AppKit
import SyntaxHighlight

/// The Spacetrucker Galactic palette (issue #9), from
/// StatusGalactic-iOS `GalacticPalette.swift`: neon magenta, hot pink,
/// cyan, phosphor green, peach and sunset orange over deep Prussian
/// blue. Dark mode uses the palette as it is, on Prussian blue; light
/// mode uses the same hues darkened until each reaches 4.5:1 against
/// white (WCAG AA). Every colour here was checked at that ratio.
enum SpacetruckerPalette {
    static func rgb(_ r: Double, _ g: Double, _ b: Double) -> NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }

    static func dynamic(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    // The palette, by its Galactic names.
    static let neonMagenta = rgb(1.00, 0.16, 0.78)
    static let hotPink = rgb(1.00, 0.40, 0.80)
    static let neonCyan = rgb(0.00, 0.94, 1.00)
    static let electricBlue = rgb(0.30, 0.36, 1.00)
    static let phosphorGreen = rgb(0.25, 1.00, 0.78)
    static let sunsetOrange = rgb(1.00, 0.42, 0.21)
    static let peach = rgb(1.00, 0.73, 0.59)
    static let mint = rgb(0.60, 0.97, 0.78)
    static let dustyRose = rgb(0.20, 0.40, 0.55)   // steel blue
    static let moon = rgb(0.92, 0.85, 1.00)
    static let deepPrussian = rgb(0.00, 0.10, 0.20)
    static let cosmicBlack = rgb(0.01, 0.02, 0.06)

    /// The code area: deep Prussian blue in dark mode.
    static let codeBackground = dynamic(dark: deepPrussian, light: .textBackgroundColor)
    static let gutterBackground = dynamic(dark: rgb(0.00, 0.07, 0.15), light: .windowBackgroundColor)
    static let plainText = dynamic(dark: moon, light: .textColor)

    static func color(_ kind: TokenKind) -> NSColor { colors[kind] ?? plainText }

    private static let colors: [TokenKind: NSColor] = [
        .keyword: dynamic(dark: neonMagenta, light: rgb(0.80, 0.13, 0.62)),
        .type: dynamic(dark: neonCyan, light: rgb(0.00, 0.47, 0.50)),
        .string: dynamic(dark: peach, light: rgb(0.55, 0.40, 0.32)),
        .number: dynamic(dark: sunsetOrange, light: rgb(0.75, 0.32, 0.16)),
        .comment: dynamic(dark: rgb(0.40, 0.55, 0.66), light: dustyRose),
        .function: dynamic(dark: phosphorGreen, light: rgb(0.12, 0.50, 0.39)),
        .attribute: dynamic(dark: hotPink, light: rgb(0.70, 0.28, 0.56)),
        .constant: dynamic(dark: mint, light: rgb(0.30, 0.48, 0.39)),
        .key: dynamic(dark: rgb(0.41, 0.46, 1.00), light: electricBlue),
        .heading: dynamic(dark: hotPink, light: rgb(0.70, 0.28, 0.56)),
    ]
}
