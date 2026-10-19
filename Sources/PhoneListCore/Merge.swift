import Foundation

/// Line-based three-way merge in the style of `patch`: the base→local diff is
/// cut into hunks with context, and each hunk is re-applied to `remote` by
/// searching for its old lines near the expected position. Returns nil when a
/// hunk cannot be located, i.e. a genuine conflict.
public enum Merge {

    struct Hunk {
        var basePos: Int
        var old: [String]
        var new: [String]
    }

    enum Op { case equal(String), remove(String), insert(String) }

    static func editScript(base: [String], local: [String]) -> [Op] {
        let diff = local.difference(from: base)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var ops: [Op] = []
        var i = 0, j = 0
        while i < base.count || j < local.count {
            if i < base.count, removed.contains(i) {
                ops.append(.remove(base[i])); i += 1
            } else if j < local.count, inserted.contains(j) {
                ops.append(.insert(local[j])); j += 1
            } else {
                ops.append(.equal(base[i])); i += 1; j += 1
            }
        }
        return ops
    }

    static func hunks(from ops: [Op], context: Int = 3) -> [Hunk] {
        // Indices of non-equal ops, grouped when separated by <= 2*context equals.
        var groups: [(start: Int, end: Int)] = []   // op index ranges (inclusive end)
        var k = 0
        while k < ops.count {
            if case .equal = ops[k] { k += 1; continue }
            var end = k
            var m = k + 1
            var run = 0
            while m < ops.count {
                if case .equal = ops[m] { run += 1; if run > 2 * context { break } }
                else { run = 0; end = m }
                m += 1
            }
            groups.append((k, end))
            k = end + 1
        }
        var result: [Hunk] = []
        var basePos = 0
        var opIndex = 0
        for g in groups {
            // Advance basePos to g.start.
            while opIndex < g.start {
                if case .insert = ops[opIndex] {} else { basePos += 1 }
                opIndex += 1
            }
            let lo = max(0, g.start - context)
            let hi = min(ops.count - 1, g.end + context)
            var old: [String] = [], new: [String] = []
            for t in lo...hi {
                switch ops[t] {
                case .equal(let s): old.append(s); new.append(s)
                case .remove(let s): old.append(s)
                case .insert(let s): new.append(s)
                }
            }
            result.append(Hunk(basePos: basePos - (g.start - lo), old: old, new: new))
        }
        return result
    }

    static func find(_ needle: [String], in hay: [String], near expected: Int, notBefore floor: Int) -> Int? {
        if needle.isEmpty { return min(max(expected, floor), hay.count) }
        let maxStart = hay.count - needle.count
        guard maxStart >= floor else { return nil }
        func matches(_ p: Int) -> Bool {
            for (q, s) in needle.enumerated() where hay[p + q] != s { return false }
            return true
        }
        let center = min(max(expected, floor), maxStart)
        var d = 0
        while true {
            let a = center + d, b = center - d
            var any = false
            if a <= maxStart { any = true; if matches(a) { return a } }
            if b >= floor && d > 0 { any = true; if matches(b) { return b } }
            if !any { return nil }
            d += 1
        }
    }

    public static func merge(base: [String], local: [String], remote: [String]) -> [String]? {
        if remote == base { return local }
        if local == base { return remote }
        if local == remote { return local }
        let hs = hunks(from: editScript(base: base, local: local))
        var out = remote
        var delta = 0
        var floor = 0
        for h in hs {
            guard let p = find(h.old, in: out, near: h.basePos + delta, notBefore: floor) else { return nil }
            out.replaceSubrange(p..<(p + h.old.count), with: h.new)
            delta += h.new.count - h.old.count
            floor = p + h.new.count
        }
        return out
    }
}
