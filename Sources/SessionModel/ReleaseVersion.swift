import Foundation

/// A release tag as a comparable version: `v1.1.2-Release`, `1.1.2`,
/// `V2.0` → 1.1.2, 1.1.2, 2.0. Used by the app's release check (issue
/// #35, DECISIONS.md D12); it lives in this package so `swift test`
/// covers it, as the app has no test target.
public struct ReleaseVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    public var components: [Int]

    public init(components: [Int]) { self.components = components }

    /// nil when the tag has no leading number after an optional `v`.
    public init?(tag: String) {
        var text = Substring(tag.trimmingCharacters(in: .whitespaces))
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let numbers = text.prefix { $0.isNumber || $0 == "." }.split(separator: ".").compactMap { Int($0) }
        guard !numbers.isEmpty else { return nil }
        components = numbers
    }

    public static func < (a: ReleaseVersion, b: ReleaseVersion) -> Bool {
        let count = max(a.components.count, b.components.count)
        for i in 0..<count {
            let x = i < a.components.count ? a.components[i] : 0
            let y = i < b.components.count ? b.components[i] : 0
            if x != y { return x < y }
        }
        return false
    }

    /// 1.1.2 == 1.1.2.0, so a padded tag is not "newer".
    public static func == (a: ReleaseVersion, b: ReleaseVersion) -> Bool { !(a < b) && !(b < a) }

    public func hash(into hasher: inout Hasher) {
        var trimmed = components
        while trimmed.last == 0 { trimmed.removeLast() }
        hasher.combine(trimmed)
    }

    public var description: String { components.map(String.init).joined(separator: ".") }
}
