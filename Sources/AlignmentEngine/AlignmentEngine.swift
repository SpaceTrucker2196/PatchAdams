import Foundation
import ApplyEngine
import DiffEngine

/// Locates a region of one column in another column (spec "Alignment
/// algorithm", FR-13 to FR-15). Works on display lines — the lines a
/// column shows, removed lines included — so a region can land on
/// text the other patch deleted, which is exactly what a reviewer
/// wants to see.
///
/// Reference lines: every display line carries a number in a frame
/// both columns share. Against the base that is `baseLine` (added
/// lines borrow the nearest context line above, spec step 1). In
/// golden mode the golden column's frame is its own post text, so the
/// caller passes `\.postLine` for that column and `\.baseLine` for
/// the others, where `baseLine` then means "golden post line".
public enum AlignmentEngine {

    /// Below this token similarity a located region is `absent`
    /// (spec default 0.6; D5).
    public static let defaultThreshold = 0.6

    public static func locate(_ region: Range<Int>,
                              in source: [DisplayLine], sourceKey: KeyPath<DisplayLine, Int?> = \.baseLine,
                              target: [DisplayLine], targetKey: KeyPath<DisplayLine, Int?> = \.baseLine,
                              targetHunks: [HunkPlacement] = [],
                              threshold: Double = defaultThreshold) -> RegionAnchor {
        let clamped = max(0, region.lowerBound)..<min(source.count, region.upperBound)
        guard clamped.lowerBound < clamped.upperBound, !target.isEmpty else {
            return RegionAnchor(status: .absent, confidence: 0, lines: 0..<0, nearestHunk: nil, tokenDiff: nil, viaIdentifier: nil)
        }
        let regionLines = Array(source[clamped])
        let regionText = normalized(regionLines)

        // Step 1: the region's reference lines, and the anchors of its added lines.
        var keys: Set<Int> = []
        var addedAnchors: Set<Int> = []
        for i in clamped {
            if let k = source[i][keyPath: sourceKey] { keys.insert(k) }
            else if let a = source.anchorReference(at: i, key: sourceKey) { addedAnchors.insert(a) }
        }
        let firstKey = keys.min() ?? addedAnchors.min()
        // Added lines in the target count as part of the same place only
        // when they hang off a line *inside* the region, or off the same
        // line the region's own added lines hang off. An insertion after
        // the region's last line is the next thing, not this one.
        var interior = keys
        if let last = keys.max() { interior.remove(last) }
        let addedKeys = interior.union(addedAnchors)

        // Step 5 first: an identifier the region declares outranks position.
        if let identifier = declarations(in: regionLines).first,
           let hit = declarationIndex(of: identifier, in: target, excluding: nil) {
            let window = hit..<min(target.count, hit + regionLines.count)
            if let verdict = compare(regionText, regionLines, Array(target[window])) {
                return RegionAnchor(status: verdict.exact ? .exact : .modified, confidence: verdict.similarity,
                              lines: window, nearestHunk: nil, tokenDiff: verdict.tokenDiff, viaIdentifier: identifier)
            }
        }

        // Step 2: the same reference span in the target.
        var candidate: [Int] = []
        for (i, line) in target.enumerated() {
            if let k = line[keyPath: targetKey] {
                if keys.contains(k) { candidate.append(i) }
            } else if let a = target.anchorReference(at: i, key: targetKey), addedKeys.contains(a) {
                candidate.append(i)
            }
        }
        // Step 3: compare at that place.
        if let lo = candidate.first, let hi = candidate.last {
            let window = lo..<(hi + 1)
            if let verdict = compare(regionText, regionLines, Array(target[window])) {
                return RegionAnchor(status: verdict.exact ? .exact : .modified, confidence: verdict.similarity,
                              lines: window, nearestHunk: nil, tokenDiff: verdict.tokenDiff, viaIdentifier: nil)
            }
        }

        // Step 4: the best window anywhere in the file.
        if let (window, similarity, tokenDiff) = bestWindow(for: regionLines, regionText: regionText, in: target), similarity >= threshold {
            return RegionAnchor(status: .moved, confidence: similarity, lines: window, nearestHunk: nil, tokenDiff: tokenDiff, viaIdentifier: nil)
        }

        // Step 6: absent, at the place the region would fall, with the nearest hunk.
        var position = firstKey.flatMap { target.index(atOrAfterReference: $0, key: targetKey) } ?? 0
        if keys.isEmpty, position < target.count, target[position][keyPath: targetKey] == firstKey {
            position += 1   // an added-only region falls *after* the line it hangs off
        }
        let nearest = firstKey.flatMap { key in targetHunks.min { abs($0.foundOldStart - key) < abs($1.foundOldStart - key) } }
        return RegionAnchor(status: .absent, confidence: 0, lines: position..<position, nearestHunk: nearest, tokenDiff: nil, viaIdentifier: nil)
    }

    // MARK: - Comparison

    struct Verdict {
        var exact: Bool
        var similarity: Double
        var tokenDiff: TokenDiff
    }

    /// `nil` when the texts are too different to be the same place.
    static func compare(_ regionText: String, _ region: [DisplayLine], _ candidate: [DisplayLine], threshold: Double = defaultThreshold) -> Verdict? {
        guard !candidate.isEmpty else { return nil }
        let candidateText = normalized(candidate)
        let diff = DiffEngine.tokens(region.map(\.text).joined(separator: "\n"), candidate.map(\.text).joined(separator: "\n"))
        if regionText == candidateText { return Verdict(exact: true, similarity: 1, tokenDiff: diff) }
        let similarity = diff.similarity
        return similarity >= threshold ? Verdict(exact: false, similarity: similarity, tokenDiff: diff) : nil
    }

    /// Lines joined with whitespace runs collapsed and edges trimmed.
    static func normalized(_ lines: [DisplayLine]) -> String {
        lines.map { line in
            line.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }.joined(separator: "\n")
    }

    /// Candidate windows ranked by shared normalized lines first (cheap),
    /// then the top few scored by token similarity (dear).
    static func bestWindow(for region: [DisplayLine], regionText: String, in target: [DisplayLine], topK: Int = 6) -> (Range<Int>, Double, TokenDiff)? {
        let n = region.count
        guard n > 0, target.count >= 1 else { return nil }
        let regionSet = Set(region.map { normalizedLine($0.text) }.filter { !$0.isEmpty })
        let targetNorm = target.map { normalizedLine($0.text) }
        let width = min(n, target.count)
        var scored: [(Int, Int)] = []   // (start, shared count)
        var shared = 0
        for i in 0..<width where regionSet.contains(targetNorm[i]) { shared += 1 }
        scored.append((0, shared))
        if width < target.count {
            for start in 1...(target.count - width) {
                if regionSet.contains(targetNorm[start - 1]) { shared -= 1 }
                if regionSet.contains(targetNorm[start + width - 1]) { shared += 1 }
                scored.append((start, shared))
            }
        }
        let best = scored.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(topK)
        var result: (Range<Int>, Double, TokenDiff)?
        for (start, _) in best {
            let window = start..<(start + width)
            let diff = DiffEngine.tokens(region.map(\.text).joined(separator: "\n"), target[window].map(\.text).joined(separator: "\n"))
            let s = diff.similarity
            if result == nil || s > result!.1 { result = (window, s, diff) }
        }
        return result
    }

    static func normalizedLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: - Declarations (step 5)

    /// Declaration keywords across the fixture languages: Rust, Go, Zig,
    /// Python, TypeScript/JavaScript, Swift. The identifier after the
    /// keyword (or after a Go receiver) is what the search is for.
    private static let declarationPattern: NSRegularExpression = {
        let keywords = "fn|func|def|class|struct|enum|type|interface|impl|trait|protocol|extension|const|static|let|var|function|export|pub"
        let pattern = #"^\s*(?:(?:pub(?:\([^)]*\))?|export|static|async|private|public|internal|final|default|unsafe|extern)\s+)*(?:"# + keywords + #")\s+(?:\([^)]*\)\s*)?([A-Za-z_][A-Za-z0-9_]*)"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    /// Identifiers the region declares, in order of appearance.
    public static func declarations(in lines: [DisplayLine]) -> [String] {
        var out: [String] = []
        for line in lines {
            let text = line.text
            if let m = declarationPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let r = Range(m.range(at: 1), in: text) {
                let name = String(text[r])
                // `let x = …` and `const x` declare variables; keep them only when they look like a definition.
                if !out.contains(name) { out.append(name) }
            }
        }
        return out
    }

    /// Index of the line that declares `identifier` in `lines`, preferring
    /// a declaration that is not a removed line.
    static func declarationIndex(of identifier: String, in lines: [DisplayLine], excluding: Range<Int>?) -> Int? {
        var fallback: Int?
        for (i, line) in lines.enumerated() {
            if let excluding, excluding.contains(i) { continue }
            let text = line.text
            guard text.contains(identifier),
                  let m = declarationPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let r = Range(m.range(at: 1), in: text), text[r] == identifier else { continue }
            if line.kind != .removed { return i }
            if fallback == nil { fallback = i }
        }
        return fallback
    }
}

public enum AnchorStatus: String, Sendable, Codable, Hashable {
    case exact, modified, moved, absent
}

/// Where a region landed in another column (the spec's "Anchor"; renamed so it cannot clash with SwiftUI.Anchor).
public struct RegionAnchor: Sendable, Hashable {
    public var status: AnchorStatus
    /// 1 for `exact`, the token similarity for `modified` and `moved`,
    /// 0 for `absent`.
    public var confidence: Double
    /// Display-line range in the target column. Empty for `absent`: its
    /// lower bound is where the region would fall.
    public var lines: Range<Int>
    /// For `absent`, the target's hunk nearest by reference line
    /// (spec step 6), so the UI can offer a jump.
    public var nearestHunk: HunkPlacement?
    /// Token diff of the region against the located lines, for the
    /// comparison panel (FR-16).
    public var tokenDiff: TokenDiff?
    /// The declared identifier that matched, when step 5 decided.
    public var viaIdentifier: String?

    public init(status: AnchorStatus, confidence: Double, lines: Range<Int>, nearestHunk: HunkPlacement?, tokenDiff: TokenDiff?, viaIdentifier: String?) {
        self.status = status
        self.confidence = confidence
        self.lines = lines
        self.nearestHunk = nearestHunk
        self.tokenDiff = tokenDiff
        self.viaIdentifier = viaIdentifier
    }
}

extension Array where Element == DisplayLine {
    /// `anchorBase` for any reference frame.
    public func anchorReference(at index: Int, key: KeyPath<DisplayLine, Int?>) -> Int? {
        guard !isEmpty else { return nil }
        var i = Swift.min(Swift.max(index, 0), count - 1)
        while i >= 0 {
            if let v = self[i][keyPath: key] { return v }
            i -= 1
        }
        return first { $0[keyPath: key] != nil }?[keyPath: key]
    }

    /// `index(atOrAfterBase:)` for any reference frame.
    public func index(atOrAfterReference reference: Int, key: KeyPath<DisplayLine, Int?>) -> Int? {
        guard !isEmpty else { return nil }
        var lo = 0, hi = count - 1, answer = count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            var probe = mid
            while probe <= hi, self[probe][keyPath: key] == nil { probe += 1 }
            if probe > hi { hi = mid - 1; continue }
            if self[probe][keyPath: key]! >= reference { answer = probe; hi = mid - 1 } else { lo = probe + 1 }
        }
        return answer
    }
}
