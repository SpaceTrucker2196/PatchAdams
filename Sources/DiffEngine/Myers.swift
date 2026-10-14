/// Myers' O(ND) difference algorithm, linear-space variant: find the
/// middle snake, recurse on both halves. Produces a minimal edit
/// script — the same number of changed lines `git diff --minimal`
/// reports.
///
/// Reference: E. Myers, "An O(ND) Difference Algorithm and Its
/// Variations", Algorithmica 1986, §4b.
enum Myers {

    static func diff(_ a: [Int], _ b: [Int], into sink: inout EditSink) {
        var scratch = Scratch(capacity: a.count + b.count + 3)
        diff(a, 0..<a.count, b, 0..<b.count, into: &sink, scratch: &scratch)
    }

    /// Reusable forward/backward furthest-reaching arrays.
    struct Scratch {
        var vf: [Int]
        var vb: [Int]
        init(capacity: Int) {
            vf = Array(repeating: 0, count: 2 * capacity + 2)
            vb = Array(repeating: 0, count: 2 * capacity + 2)
        }
    }

    static func diff(_ a: [Int], _ ar: Range<Int>, _ b: [Int], _ br: Range<Int>,
                     into sink: inout EditSink, scratch: inout Scratch) {
        var alo = ar.lowerBound, ahi = ar.upperBound
        var blo = br.lowerBound, bhi = br.upperBound

        // Common prefix and suffix are equal runs; the sink fills them in.
        while alo < ahi, blo < bhi, a[alo] == b[blo] { alo += 1; blo += 1 }
        while alo < ahi, blo < bhi, a[ahi - 1] == b[bhi - 1] { ahi -= 1; bhi -= 1 }

        if alo == ahi {
            for j in blo..<bhi { sink.insert(j) }
            return
        }
        if blo == bhi {
            for i in alo..<ahi { sink.delete(i) }
            return
        }

        let (x, y, u, v) = middleSnake(a, alo..<ahi, b, blo..<bhi, scratch: &scratch)
        if x == u && y == v && (x == 0 || y == 0) && (u == ahi - alo || v == bhi - blo) {
            // Degenerate: no snake and one side consumed — can't recurse
            // without progress. One side is empty after the split; emit
            // directly.
            for i in alo..<ahi { sink.delete(i) }
            for j in blo..<bhi { sink.insert(j) }
            return
        }
        diff(a, alo..<alo + x, b, blo..<blo + y, into: &sink, scratch: &scratch)
        diff(a, alo + u..<ahi, b, blo + v..<bhi, into: &sink, scratch: &scratch)
    }

    /// The middle snake of the shortest edit script between
    /// `a[ar]` and `b[br]`, as offsets inside those ranges:
    /// start `(x, y)`, end `(u, v)`.
    static func middleSnake(_ a: [Int], _ ar: Range<Int>, _ b: [Int], _ br: Range<Int>,
                            scratch: inout Scratch) -> (Int, Int, Int, Int) {
        let n = ar.count, m = br.count
        let alo = ar.lowerBound, blo = br.lowerBound
        let delta = n - m
        let odd = delta & 1 == 1
        let max = (n + m + 1) / 2
        let offset = max + 1

        scratch.vf[offset + 1] = 0
        scratch.vb[offset + 1] = 0

        for d in 0...max {
            // Forward pass from (0,0).
            var k = -d
            while k <= d {
                var x: Int
                if k == -d || (k != d && scratch.vf[offset + k - 1] < scratch.vf[offset + k + 1]) {
                    x = scratch.vf[offset + k + 1]
                } else {
                    x = scratch.vf[offset + k - 1] + 1
                }
                var y = x - k
                let sx = x, sy = y
                while x < n, y < m, a[alo + x] == b[blo + y] { x += 1; y += 1 }
                scratch.vf[offset + k] = x
                if odd, (delta - (d - 1)) <= k, k <= (delta + (d - 1)) {
                    // Reverse path on diagonal k reaches x' from the far end.
                    if scratch.vb[offset + delta - k] + x >= n {
                        return (sx, sy, x, y)
                    }
                }
                k += 2
            }

            // Reverse pass from (n,m); x counts back from n on diagonal k
            // in the reversed problem.
            k = -d
            while k <= d {
                var x: Int
                if k == -d || (k != d && scratch.vb[offset + k - 1] < scratch.vb[offset + k + 1]) {
                    x = scratch.vb[offset + k + 1]
                } else {
                    x = scratch.vb[offset + k - 1] + 1
                }
                var y = x - k
                let sx = x, sy = y
                while x < n, y < m, a[ar.upperBound - 1 - x] == b[br.upperBound - 1 - y] { x += 1; y += 1 }
                scratch.vb[offset + k] = x
                if !odd, (delta - d) <= k, k <= (delta + d) {
                    if scratch.vf[offset + delta - k] + x >= n {
                        return (n - x, m - y, n - sx, m - sy)
                    }
                }
                k += 2
            }
        }
        // Unreachable for non-empty inputs: the paths always meet by d = max.
        return (0, 0, 0, 0)
    }
}
