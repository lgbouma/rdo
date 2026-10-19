import Testing
import Foundation
@testable import PhoneListCore

struct ParserTests {

    let sample = """
    ==========================================
    MSOS

    * Push revision of ur PRs (or merge existing one)
    * GET ALL CAR-912 M13 THROUGH AIRFLOW (i_car912airflow)
        * Rerun d5 on ones/zeros branch
        * Run sca02
    * Sign up for IPAC mentoring program
      https://example.com/wiki/spaces/ORG/pages/611360780/Mentoring+Program+2026


    ==========================================
    CPVs

    ----------
    Science:
    * Finalize CPV target vetting
      * "multisector postage stamp collector":  for POPULATION (e.g. to see if
            the ones from B24 that looked like EBs are in fact EBs)
    ~ one idea for shortening dev loop:
      ~ dont change your container image
    \t* Use Cloudflare Tunnel
    \t\t\thostname: lcviz.lgbouma.com

    """

    @Test func roundTrip() {
        let doc = Document(text: sample)
        #expect(doc.text == sample)
    }

    @Test func realFileRoundTrip() throws {
        let url = URL(fileURLWithPath: NSString(string: "~/Dropbox/research_TODO.txt").expandingTildeInPath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let doc = Document(text: text)
        #expect(doc.text == text)
        // Every line is covered by exactly one node, in order.
        var next = 0
        for n in doc.nodes {
            #expect(n.lines.lowerBound == next)
            next = n.lines.upperBound
        }
        #expect(next == doc.lines.count)
        #expect(doc.sections.count == 15)
        #expect(doc.sections.map(\.title).first == "OVERVIEW")
    }

    @Test func sectionsAndItems() {
        let doc = Document(text: sample)
        let secs = doc.sections
        #expect(secs.map(\.title) == ["MSOS", "CPVs"])
        let msos = secs[0].nodes.compactMap(\.item)
        #expect(msos.count == 5)
        #expect(msos[0].text == "Push revision of ur PRs (or merge existing one)")
        #expect(msos[2].indentWidth == 4)
        // Continuation line absorbed.
        #expect(msos[4].text == "Sign up for IPAC mentoring program https://example.com/wiki/spaces/ORG/pages/611360780/Mentoring+Program+2026")
        let cpv = secs[1].nodes
        #expect(cpv[1].kind == .blank)
        #expect(cpv[2].kind == .divider)
        #expect(cpv[3].kind == .note("Science:"))
        let items = cpv.compactMap(\.item)
        #expect(items[1].text == "\"multisector postage stamp collector\": for POPULATION (e.g. to see if the ones from B24 that looked like EBs are in fact EBs)")
        #expect(items[2].marker == .wontDo)
        #expect(items[4].indent == "\t")
        #expect(items[4].text == "Use Cloudflare Tunnel hostname: lcviz.lgbouma.com")
    }

    @Test func legacyXMarker() {
        let doc = Document(text: "  x maybe also other TOI\n- done thing\n")
        let items = doc.nodes.compactMap(\.item)
        #expect(items[0].marker == .wontDo)
        #expect(items[0].rawMarker == "x")
        #expect(items[1].marker == .done)
    }

    @Test func toggleOnlyTouchesMarkerLine() {
        var doc = Document(text: sample)
        let node = doc.nodes.first { $0.item?.text.hasPrefix("Sign up") == true }!
        doc.toggleDone(node.id)
        #expect(doc.lines[node.lines.lowerBound].text == "- Sign up for IPAC mentoring program")
        #expect(doc.lines[node.lines.lowerBound + 1].text == "  https://example.com/wiki/spaces/ORG/pages/611360780/Mentoring+Program+2026")
        doc.toggleDone(node.id)
        #expect(doc.text == sample)
        doc.toggleWontDo(node.id)
        #expect(doc.lines[node.lines.lowerBound].text == "~ Sign up for IPAC mentoring program")
        doc.toggleWontDo(node.id)
        #expect(doc.text == sample)
    }

    @Test func indentOutdentCarriesSubtree() {
        var doc = Document(text: sample)
        let node = doc.nodes.first { $0.item?.text.hasPrefix("GET ALL") == true }!
        doc.indent(node.id)
        #expect(doc.lines[node.lines.lowerBound].text == "  * GET ALL CAR-912 M13 THROUGH AIRFLOW (i_car912airflow)")
        #expect(doc.lines[node.lines.lowerBound + 1].text == "      * Rerun d5 on ones/zeros branch")
        #expect(doc.lines[node.lines.lowerBound + 2].text == "      * Run sca02")
        #expect(doc.lines[node.lines.lowerBound + 3].text == "* Sign up for IPAC mentoring program")
        doc.outdent(node.id)
        #expect(doc.text == sample)
        // Outdent at column 0 is a no-op.
        doc.outdent(node.id)
        #expect(doc.text == sample)
    }

    @Test func outdentTab() {
        var doc = Document(text: "\t* a\n\t\t\tcont\n")
        let n = doc.nodes[0]
        doc.outdent(n.id)
        #expect(doc.text == "* a\n\t\tcont\n")
    }

    @Test func setTextUnchangedIsNoop() {
        var doc = Document(text: sample)
        let node = doc.nodes.first { $0.item?.text.hasPrefix("\"multisector") == true }!
        doc.setText(node.id, "  \"multisector postage stamp collector\":   for POPULATION (e.g. to see if the ones from B24 that looked like EBs are in fact EBs) ")
        #expect(doc.text == sample, "normalised-equal text must not rewrap")
    }

    @Test func setTextRewraps() {
        var doc = Document(text: "    * short\n* next\n")
        let n = doc.nodes[0]
        let long = Array(repeating: "word", count: 30).joined(separator: " ")
        doc.setText(n.id, long)
        let lines = doc.lineTexts
        #expect(lines[0].hasPrefix("    * word word"))
        #expect(lines.dropLast().allSatisfy { $0.count <= 80 })
        #expect(lines[1].hasPrefix("      word"))
        #expect(lines.last == "* next")
        // Identity survives.
        #expect(doc.nodes[0].id == n.id)
        #expect(doc.nodes[0].item?.text == long)
    }

    @Test func rewrapLongWord() {
        let url = "https://example.com/" + String(repeating: "a", count: 90)
        let out = Rewrap.wrap("see " + url + " ok", firstPrefix: "* ", restPrefix: "  ", width: 80)
        #expect(out == ["* see", "  " + url, "  ok"])
    }

    @Test func insertAppendDelete() {
        var doc = Document(text: sample)
        let secs = doc.sections
        let first = secs[0].nodes.compactMap { $0.item != nil ? $0 : nil }[1]
        let newID = doc.insertItem(after: first.id, text: "new thing")!
        #expect(doc.lines[first.lines.upperBound].text == "* new thing")
        doc.delete(newID)
        #expect(doc.text == sample)

        let appended = doc.appendItem(toSection: secs[0].id, text: "tail")!
        let idx = doc.index(ofLineID: appended)!
        #expect(doc.lines[idx].text == "* tail")
        #expect(doc.lines[idx - 1].text.hasPrefix("  https://"))
        #expect(doc.lines[idx + 1].text == "")
        doc.delete(appended)
        #expect(doc.text == sample)
    }

    @Test func appendUsesBaseIndent() {
        var doc = Document(text: "=====================\nS\n\n  * a\n    * b\n\n")
        let s = doc.sections[0]
        let id = doc.appendItem(toSection: s.id, text: "c")!
        #expect(doc.lines[doc.index(ofLineID: id)!].text == "  * c")
    }

    @Test func moveSubtree() {
        var doc = Document(text: sample)
        let sec = doc.sections[0]
        let items = sec.nodes.filter { $0.item != nil }
        // Move "GET ALL" (with its two children) before "Push revision".
        doc.move(items[1].id, before: items[0].id, inSection: sec.id)
        let t = doc.lineTexts
        #expect(t[3] == "* GET ALL CAR-912 M13 THROUGH AIRFLOW (i_car912airflow)")
        #expect(t[4] == "    * Rerun d5 on ones/zeros branch")
        #expect(t[5] == "    * Run sca02")
        #expect(t[6] == "* Push revision of ur PRs (or merge existing one)")
        // And back to the end of the section.
        let sec2 = doc.sections[0]
        let get = sec2.nodes.first { $0.item?.text.hasPrefix("GET ALL") == true }!
        doc.move(get.id, before: nil, inSection: sec2.id)
        let t2 = doc.lineTexts
        #expect(t2[3] == "* Push revision of ur PRs (or merge existing one)")
        #expect(t2[6] == "* GET ALL CAR-912 M13 THROUGH AIRFLOW (i_car912airflow)")
        #expect(t2[8] == "    * Run sca02")
        #expect(t2[9] == "")
    }
}

struct EmptyItemTests {
    @Test func bareMarkerIsAnItem() {
        var doc = Document(text: "* a\n")
        let id = doc.insertItem(after: doc.nodes[0].id)!
        #expect(doc.text == "* a\n*\n")
        #expect(doc.nodes[1].item?.text == "")
        doc.setText(id, "hello")
        #expect(doc.text == "* a\n* hello\n")
        doc.setText(id, "")
        #expect(doc.text == "* a\n*\n")
    }
}
