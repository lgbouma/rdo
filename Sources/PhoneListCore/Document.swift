import Foundation

/// One physical line of the text file. The `id` is stable across edits so
/// that the UI can keep selection / editing state while lines shift.
public struct Line: Identifiable, Equatable, Hashable {
    public let id: UUID
    public var text: String

    public init(_ text: String, id: UUID = UUID()) {
        self.id = id
        self.text = text
    }
}

/// Marker characters used by the TODO file.
public enum Marker: Equatable, Hashable {
    case todo       // *
    case done       // -
    case wontDo     // ~  (also legacy x / X)

    public static func from(_ c: Character) -> Marker? {
        switch c {
        case "*": return .todo
        case "-": return .done
        case "~", "x", "X": return .wontDo
        default: return nil
        }
    }

    /// Character written to the file for this marker.
    public var character: Character {
        switch self {
        case .todo: return "*"
        case .done: return "-"
        case .wontDo: return "~"
        }
    }
}

/// A logical item: a marker line plus its hanging-indent continuation lines.
public struct Item: Equatable, Hashable {
    public var marker: Marker
    /// The marker character as it appears in the file (preserves x / X).
    public var rawMarker: Character
    /// Leading whitespace of the marker line, verbatim.
    public var indent: String
    /// Display width of `indent` (tabs expanded).
    public var indentWidth: Int
    /// Continuation text, whitespace-normalised and joined with single spaces.
    public var text: String
}

/// A parsed node. `lines` indexes into `Document.lines`.
public struct Node: Identifiable, Equatable {
    public enum Kind: Equatable {
        case sectionHeader(title: String)
        case divider
        case item(Item)
        case note(String)
        case blank
    }
    public let id: UUID          // id of the node's first line
    public let kind: Kind
    public let lines: Range<Int>

    public var item: Item? {
        if case .item(let it) = kind { return it }
        return nil
    }
}

/// A section: the lines from one `=====` header up to the next.
public struct FileSection: Identifiable, Equatable {
    public let id: UUID          // id of the header node, or of the first line for the preamble
    public let title: String
    public let nodes: [Node]
    public let lines: Range<Int>
}

public enum Layout {
    public static let tabStop = 4
    public static let wrapWidth = 80
    public static let indentStep = "  "
    /// A run of this many or more "=" is a section header rather than a divider.
    public static let sectionHeaderMinLength = 10

    public static func width(ofIndent s: Substring) -> Int {
        var w = 0
        for c in s {
            if c == "\t" { w += tabStop - (w % tabStop) } else { w += 1 }
        }
        return w
    }

    public static func leadingWhitespace(_ s: String) -> Substring {
        s.prefix { $0 == " " || $0 == "\t" }
    }
}

// MARK: - Parsing

public enum Parser {

    static func isDividerRun(_ trimmed: Substring) -> Character? {
        guard let first = trimmed.first, "-~=.".contains(first), trimmed.count >= 3 else { return nil }
        return trimmed.allSatisfy { $0 == first } ? first : nil
    }

    /// Classify a single line in isolation (continuation handling happens in `parse`).
    static func classify(_ text: String) -> Node.Kind {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .blank }
        if let c = isDividerRun(Substring(trimmed)) {
            if c == "=" && trimmed.count >= Layout.sectionHeaderMinLength {
                return .sectionHeader(title: "")
            }
            return .divider
        }
        let ws = Layout.leadingWhitespace(text)
        let rest = text[ws.endIndex...]
        if let first = rest.first, let marker = Marker.from(first) {
            let afterMarker = rest.dropFirst()
            if afterMarker.isEmpty || afterMarker.first == " " || afterMarker.first == "\t" {
                let body = afterMarker.trimmingCharacters(in: .whitespaces)
                return .item(Item(marker: marker,
                                  rawMarker: first,
                                  indent: String(ws),
                                  indentWidth: Layout.width(ofIndent: ws),
                                  text: body))
            }
        }
        return .note(text)
    }

    public static func parse(_ lines: [Line]) -> [Node] {
        var nodes: [Node] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let kind = classify(line.text)
            switch kind {
            case .sectionHeader:
                // Header consumes the following title line if it is plain text.
                var end = i + 1
                var title = ""
                if i + 1 < lines.count {
                    let next = lines[i + 1].text
                    if case .note(let t) = classify(next) {
                        title = t.trimmingCharacters(in: .whitespaces)
                        end = i + 2
                    }
                }
                nodes.append(Node(id: line.id, kind: .sectionHeader(title: title), lines: i..<end))
                i = end
            case .item(var item):
                // Absorb hanging-indent continuation lines.
                var end = i + 1
                var pieces = [item.text]
                while end < lines.count {
                    let t = lines[end].text
                    let ws = Layout.leadingWhitespace(t)
                    guard Layout.width(ofIndent: ws) > item.indentWidth,
                          case .note = classify(t) else { break }
                    pieces.append(t.trimmingCharacters(in: .whitespaces))
                    end += 1
                }
                item.text = Rewrap.normalise(pieces.joined(separator: " "))
                nodes.append(Node(id: line.id, kind: .item(item), lines: i..<end))
                i = end
            default:
                nodes.append(Node(id: line.id, kind: kind, lines: i..<(i + 1)))
                i += 1
            }
        }
        return nodes
    }

    public static func sections(_ nodes: [Node], lineCount: Int) -> [FileSection] {
        var result: [FileSection] = []
        var current: [Node] = []
        var currentTitle = ""
        var currentID: UUID? = nil
        var start = 0

        func flush(end: Int) {
            guard let id = currentID ?? current.first?.id else { return }
            // Skip an empty preamble (no header, no nodes).
            if currentID == nil && current.allSatisfy({ $0.kind == .blank }) { return }
            result.append(FileSection(id: id, title: currentTitle, nodes: current, lines: start..<end))
        }

        for node in nodes {
            if case .sectionHeader(let title) = node.kind {
                flush(end: node.lines.lowerBound)
                current = [node]
                currentTitle = title.isEmpty ? "(untitled)" : title
                currentID = node.id
                start = node.lines.lowerBound
            } else {
                if currentID == nil && current.isEmpty { currentTitle = "(top)"; start = node.lines.lowerBound }
                current.append(node)
            }
        }
        flush(end: lineCount)
        return result
    }
}

// MARK: - Document and edit operations

/// The file as an array of lines. All edits are expressed as line-level
/// replacements so that untouched lines round-trip byte-for-byte.
public struct Document: Equatable {
    public private(set) var lines: [Line]
    /// Whether the original text ended with a newline (preserved on render).
    public var trailingNewline: Bool

    public init(text: String) {
        var parts = text.components(separatedBy: "\n")
        trailingNewline = text.hasSuffix("\n")
        if trailingNewline { parts.removeLast() }
        // Normalise CRLF just in case; the files are LF.
        lines = parts.map { Line($0.hasSuffix("\r") ? String($0.dropLast()) : $0) }
    }

    public init(lines: [Line], trailingNewline: Bool = true) {
        self.lines = lines
        self.trailingNewline = trailingNewline
    }

    public var text: String {
        let body = lines.map(\.text).joined(separator: "\n")
        return trailingNewline ? body + "\n" : body
    }

    public var lineTexts: [String] { lines.map(\.text) }

    public var nodes: [Node] { Parser.parse(lines) }
    public var sections: [FileSection] { Parser.sections(nodes, lineCount: lines.count) }

    public func node(withID id: UUID) -> Node? {
        nodes.first { $0.id == id }
    }

    public func index(ofLineID id: UUID) -> Int? {
        lines.firstIndex { $0.id == id }
    }

    // MARK: subtree

    /// Line range of an item together with its children: following nodes that
    /// are items or notes indented more deeply, stopping at a blank line,
    /// divider, header, or shallower-or-equal item.
    public func subtreeRange(of nodeID: UUID) -> Range<Int>? {
        let all = nodes
        guard let idx = all.firstIndex(where: { $0.id == nodeID }), let item = all[idx].item else { return nil }
        var end = all[idx].lines.upperBound
        var j = idx + 1
        while j < all.count {
            let n = all[j]
            switch n.kind {
            case .item(let child) where child.indentWidth > item.indentWidth:
                end = n.lines.upperBound
            case .note(let t) where Layout.width(ofIndent: Layout.leadingWhitespace(t)) > item.indentWidth:
                end = n.lines.upperBound
            default:
                return all[idx].lines.lowerBound..<end
            }
            j += 1
        }
        return all[idx].lines.lowerBound..<end
    }

    // MARK: marker edits

    private mutating func setMarker(_ nodeID: UUID, to marker: Marker) {
        guard let node = node(withID: nodeID), node.item != nil else { return }
        let i = node.lines.lowerBound
        var t = lines[i].text
        let ws = Layout.leadingWhitespace(t)
        let markerIndex = ws.endIndex
        guard markerIndex < t.endIndex, Marker.from(t[markerIndex]) != nil else { return }
        t.replaceSubrange(markerIndex...markerIndex, with: String(marker.character))
        lines[i].text = t
    }

    /// `*` <-> `-`. Anything else becomes `*`.
    public mutating func toggleDone(_ nodeID: UUID) {
        guard let item = node(withID: nodeID)?.item else { return }
        setMarker(nodeID, to: item.marker == .todo ? .done : .todo)
    }

    /// Mark `~`; if already `~`, back to `*`.
    public mutating func toggleWontDo(_ nodeID: UUID) {
        guard let item = node(withID: nodeID)?.item else { return }
        setMarker(nodeID, to: item.marker == .wontDo ? .todo : .wontDo)
    }

    // MARK: indentation

    public mutating func indent(_ nodeID: UUID) {
        guard let range = subtreeRange(of: nodeID) else { return }
        for i in range where !lines[i].text.trimmingCharacters(in: .whitespaces).isEmpty {
            lines[i].text = Layout.indentStep + lines[i].text
        }
    }

    public mutating func outdent(_ nodeID: UUID) {
        guard let node = node(withID: nodeID), let item = node.item, item.indentWidth > 0,
              let range = subtreeRange(of: nodeID) else { return }
        for i in range {
            var t = lines[i].text
            if t.hasPrefix("\t") {
                t.removeFirst()
            } else {
                var n = 0
                while n < Layout.indentStep.count, t.hasPrefix(" ") { t.removeFirst(); n += 1 }
            }
            lines[i].text = t
        }
    }

    // MARK: text edits

    /// Replace an item's text. If the normalised text is unchanged this is a
    /// no-op, so existing wrapping is preserved. Otherwise the item is
    /// re-wrapped at `Layout.wrapWidth` with a hanging indent.
    public mutating func setText(_ nodeID: UUID, _ newText: String) {
        guard let node = node(withID: nodeID), let item = node.item else { return }
        let normalised = Rewrap.normalise(newText)
        if normalised == item.text { return }
        let firstPrefix = item.indent + String(item.rawMarker) + " "
        let restPrefix = item.indent + "  "
        let wrapped = Rewrap.wrap(normalised, firstPrefix: firstPrefix, restPrefix: restPrefix, width: Layout.wrapWidth)
        var newLines = wrapped.map { Line($0) }
        // Keep the first line's id so the node identity survives the edit.
        if !newLines.isEmpty { newLines[0] = Line(newLines[0].text, id: node.id) }
        lines.replaceSubrange(node.lines, with: newLines)
    }

    // MARK: insertion / deletion

    /// Insert a new `*` item directly after the given item (same indentation).
    /// Returns the new node's id.
    @discardableResult
    public mutating func insertItem(after nodeID: UUID, text: String = "") -> UUID? {
        guard let node = node(withID: nodeID), let item = node.item else { return nil }
        let line = Line(item.indent + Self.newItemLine(text))
        lines.insert(line, at: node.lines.upperBound)
        return line.id
    }

    /// Insert a new `*` item at the end of the section (before its trailing
    /// blank lines), using the section's base indentation. Returns the id.
    @discardableResult
    public mutating func appendItem(toSection sectionID: UUID, text: String = "") -> UUID? {
        guard let section = sections.first(where: { $0.id == sectionID }) else { return nil }
        let items = section.nodes.compactMap(\.item)
        let indent = items.min(by: { $0.indentWidth < $1.indentWidth })?.indent ?? ""
        // Last non-blank node in the section.
        let lastContent = section.nodes.last { $0.kind != .blank }
        let at: Int
        if let last = lastContent {
            at = last.lines.upperBound
        } else {
            at = section.lines.upperBound
        }
        let line = Line(indent + Self.newItemLine(text))
        lines.insert(line, at: at)
        return line.id
    }

    /// "* text", or a bare "*" with no trailing space when the text is empty.
    static func newItemLine(_ text: String) -> String {
        text.isEmpty ? "*" : "* " + text
    }

    /// Delete just the item (marker line + continuation), not its children.
    public mutating func delete(_ nodeID: UUID) {
        guard let node = node(withID: nodeID), node.item != nil else { return }
        lines.removeSubrange(node.lines)
    }

    // MARK: reordering

    /// Move an item (with its subtree) so that it sits immediately before
    /// `targetID`'s first line, or at the end of the section if `targetID`
    /// is nil. Both nodes must be in the same section.
    public mutating func move(_ nodeID: UUID, before targetID: UUID?, inSection sectionID: UUID) {
        guard let src = subtreeRange(of: nodeID),
              let section = sections.first(where: { $0.id == sectionID }) else { return }
        var dest: Int
        if let targetID, let target = section.nodes.first(where: { $0.id == targetID }) {
            dest = target.lines.lowerBound
        } else {
            dest = (section.nodes.last { $0.kind != .blank }?.lines.upperBound) ?? section.lines.upperBound
        }
        if src.contains(dest) || dest == src.upperBound { return }
        let moving = Array(lines[src])
        lines.removeSubrange(src)
        if dest > src.lowerBound { dest -= moving.count }
        lines.insert(contentsOf: moving, at: dest)
    }
}
