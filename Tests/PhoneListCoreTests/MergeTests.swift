import Testing
import Foundation
@testable import PhoneListCore

struct MergeTests {

    let base = """
    ====
    A

    * one
    * two
    * three

    ====
    B

    * four
    * five
    * six
    """.components(separatedBy: "\n")

    @Test func trivial() {
        #expect(Merge.merge(base: base, local: base, remote: base) == base)
        var local = base; local[4] = "- two"
        #expect(Merge.merge(base: base, local: local, remote: base) == local)
        var remote = base; remote[11] = "- five"
        #expect(Merge.merge(base: base, local: base, remote: remote) == remote)
    }

    @Test func laptopSweepShiftsPhoneEdit() {
        // Phone marks "five" done; laptop sweeps "one" and "two" out of section A.
        var local = base; local[11] = "- five"
        var remote = base; remote.removeSubrange(3...4)
        let merged = Merge.merge(base: base, local: local, remote: remote)
        var expected = remote; expected[9] = "- five"
        #expect(merged == expected)
    }

    @Test func bothEditDifferentPlaces() {
        var local = base; local.insert("* one-b", at: 4)
        var remote = base; remote[12] = "~ six"
        let merged = Merge.merge(base: base, local: local, remote: remote)!
        #expect(merged.contains("* one-b"))
        #expect(merged.contains("~ six"))
        #expect(merged.count == base.count + 1)
    }

    @Test func sameLineConflict() {
        var local = base; local[4] = "- two"
        var remote = base; remote[4] = "~ two"
        #expect(Merge.merge(base: base, local: local, remote: remote) == nil)
    }

    @Test func identicalEditsAgree() {
        var local = base; local[4] = "- two"
        #expect(Merge.merge(base: base, local: local, remote: local) == local)
    }

    @Test func appendAtEnd() {
        var local = base; local.append("* seven")
        var remote = base; remote[0] = "========"
        let merged = Merge.merge(base: base, local: local, remote: remote)!
        #expect(merged.last == "* seven")
        #expect(merged.first == "========")
    }
}
