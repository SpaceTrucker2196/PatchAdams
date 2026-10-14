/// Patience diff: lines that occur exactly once on both sides are
/// matched by longest increasing subsequence and become anchors; the
/// gaps between anchors are diffed recursively, falling back to Myers
/// where no unique line remains.
///
/// Reference: Bram Cohen's description (2006); the same heuristic
/// `git diff --patience` uses.
enum Patience {

    static func diff(_ a: [Int], _ b: [Int], into sink: inout EditSink) {
        var scratch = Myers.Scratch(capacity: a.count + b.count + 3)
        diff(a, 0..<a.count, b, 0..<b.count, into: &sink, scratch: &scratch)
    }

    static func diff(_ a: [Int], _ ar: Range<Int>, _ b: [Int], _ br: Range<Int>,
                     into sink: inout EditSink, scratch: inout Myers.Scratch) {
        var alo = ar.lowerBound, ahi = ar.upperBound
        var blo = br.lowerBound, bhi = br.upperBound

        while alo < ahi, blo < bhi, a[alo] == b[blo] { alo += 1; blo += 1 }
        while alo < ahi, blo < bhi, a[ahi - 1] == b[bhi - 1] { ahi -= 1; bhi -= 1 }

        if alo == ahi || blo == bhi {
            Myers.diff(a, alo..<ahi, b, blo..<bhi, into: &sink, scratch: &scratch)
            return
        }

        let anchors = uniqueMatches(a, alo..<ahi, b, blo..<bhi)
        if anchors.isEmpty {
            Myers.diff(a, alo..<ahi, b, blo..<bhi, into: &sink, scratch: &scratch)
            return
        }

        var pa = alo, pb = blo
        for (ia, ib) in anchors {
            diff(a, pa..<ia, b, pb..<ib, into: &sink, scratch: &scratch)
            // The anchor itself is an equal line; the sink fills it in.
            pa = ia + 1
            pb = ib + 1
        }
        diff(a, pa..<ahi, b, pb..<bhi, into: &sink, scratch: &scratch)
    }

    /// Pairs `(aIndex, bIndex)` of lines unique on both sides, as the
    /// longest increasing subsequence by `bIndex` when ordered by
    /// `aIndex`.
    static func uniqueMatches(_ a: [Int], _ ar: Range<Int>, _ b: [Int], _ br: Range<Int>) -> [(Int, Int)] {
        var countA: [Int: Int] = [:], firstA: [Int: Int] = [:]
        for i in ar { countA[a[i], default: 0] += 1; if firstA[a[i]] == nil { firstA[a[i]] = i } }
        var countB: [Int: Int] = [:], firstB: [Int: Int] = [:]
        for j in br { countB[b[j], default: 0] += 1; if firstB[b[j]] == nil { firstB[b[j]] = j } }

        var pairs: [(Int, Int)] = []
        for i in ar {
            let sym = a[i]
            if countA[sym] == 1, countB[sym] == 1, let j = firstB[sym] { pairs.append((i, j)) }
        }
        if pairs.isEmpty { return [] }

        // Patience sorting: longest increasing subsequence on bIndex.
        var piles: [Int] = []            // top bIndex of each pile
        var pileOf: [Int] = []           // pile index per pair
        var prev: [Int?] = []            // back-pointer per pair (index into pairs)
        var pileTopPair: [Int] = []      // pair index on top of each pile
        for (p, pair) in pairs.enumerated() {
            // Binary search the first pile whose top is > pair.1.
            var lo = 0, hi = piles.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if piles[mid] < pair.1 { lo = mid + 1 } else { hi = mid }
            }
            if lo == piles.count { piles.append(pair.1); pileTopPair.append(p) } else { piles[lo] = pair.1; pileTopPair[lo] = p }
            pileOf.append(lo)
            prev.append(lo > 0 ? pileTopPair[lo - 1] : nil)
        }
        var out: [(Int, Int)] = []
        var cursor: Int? = pileTopPair.last
        while let c = cursor {
            out.append(pairs[c])
            cursor = prev[c]
        }
        return out.reversed()
    }
}
