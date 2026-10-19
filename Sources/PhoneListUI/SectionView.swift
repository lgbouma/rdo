import SwiftUI
import PhoneListCore
#if canImport(UIKit)
import UIKit
#endif

struct SectionView: View {
    @EnvironmentObject var store: Store
    let sectionID: UUID
    /// Which item shows a text field. Owned by RootView so the edit bar above
    /// the keyboard can act on it. Focus follows this (see ItemRow.onAppear);
    /// setting FocusState directly to a not-yet-rendered field is dropped.
    @Binding var editingID: UUID?
    @FocusState private var focused: UUID?

    private var section: FileSection? { store.document.sections.first { $0.id == sectionID } }

    var body: some View {
        List {
            if let section {
                ForEach(section.nodes) { node in
                    row(node)
                        .moveDisabled(node.item == nil)
                        .deleteDisabled(node.item == nil)
                }
                .onMove { source, dest in move(section, source, dest) }
                .onDelete { offsets in
                    guard let i = offsets.first, let node = section.nodes[safe: i], node.item != nil else { return }
                    store.edit { $0.delete(node.id) }
                }
                addRow(section)
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 1)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await store.pull() }
        .onChange(of: focused) { old, new in
            if let new {
                editingID = new
            } else if old == editingID {
                // Keyboard dismissed (Done, scroll) while that row was editing.
                // A nil caused by a row being replaced (return key inserts a
                // sibling) leaves editingID pointing at the new row.
                editingID = nil
            }
        }
    }

    @ViewBuilder
    private func row(_ node: Node) -> some View {
        switch node.kind {
        case .sectionHeader:
            EmptyView()
        case .divider:
            Rectangle().fill(.separator).frame(height: 1)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
        case .blank:
            Color.clear.frame(height: 10)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
        case .note(let text):
            Text(text.trimmingCharacters(in: .whitespaces))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.leading, indentPad(Layout.width(ofIndent: Layout.leadingWhitespace(text))))
                .listRowInsets(rowInsets)
                .listRowSeparator(.hidden)
        case .item(let item):
            ItemRow(node: node, item: item, editing: $editingID, focused: $focused,
                    commit: { text in store.edit { $0.setText(node.id, text) } },
                    newBelow: { text in newBelow(node, draft: text) })
                .listRowInsets(rowInsets)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button { Haptics.warning(); store.edit { $0.toggleWontDo(node.id) } } label: {
                        Label("Won't do", systemImage: "nosign")
                    }.tint(.orange)
                    Button(role: .destructive) { store.edit { $0.delete(node.id) } } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu { itemMenu(node) }
        }
    }

    private func addRow(_ section: FileSection) -> some View {
        Button {
            let id = store.edit(returning: { $0.appendItem(toSection: section.id) })
            if let id { editingID = id }
        } label: {
            Label("New item", systemImage: "plus.circle").foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("newItem")
        .buttonStyle(.plain)
        .listRowInsets(rowInsets)
        .listRowSeparator(.hidden)
        .padding(.vertical, 6)
    }

    private var rowInsets: EdgeInsets { EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16) }

    @ViewBuilder
    private func itemMenu(_ node: Node) -> some View {
        Button { store.edit { $0.indent(node.id) } } label: { Label("Indent", systemImage: "increase.indent") }
        Button { store.edit { $0.outdent(node.id) } } label: { Label("Outdent", systemImage: "decrease.indent") }
        Button { newBelow(node, draft: nil) } label: { Label("New item below", systemImage: "plus") }
        Button { store.edit { $0.toggleWontDo(node.id) } } label: { Label("Won't do (~)", systemImage: "nosign") }
        Divider()
        Button(role: .destructive) { store.edit { $0.delete(node.id) } } label: { Label("Delete", systemImage: "trash") }
    }

    /// Commit the current draft (if any) and insert a sibling below, focusing it.
    private func newBelow(_ node: Node, draft: String?) {
        if let draft { store.edit { $0.setText(node.id, draft) } }
        let id = store.edit(returning: { $0.insertItem(after: node.id) })
        if let id { editingID = id }
    }

    private func move(_ section: FileSection, _ source: IndexSet, _ dest: Int) {
        guard let s = source.first, let moving = section.nodes[safe: s], moving.item != nil else { return }
        let target: UUID? = dest < section.nodes.count ? section.nodes[dest].id : nil
        if target == moving.id { return }
        Haptics.tap()
        store.edit { $0.move(moving.id, before: target, inSection: section.id) }
    }

    static func indentPad(_ width: Int) -> CGFloat { CGFloat(width) * 7 }
    private func indentPad(_ width: Int) -> CGFloat { Self.indentPad(width) }
}

struct ItemRow: View {
    let node: Node
    let item: Item
    @Binding var editing: UUID?
    var focused: FocusState<UUID?>.Binding
    let commit: (String) -> Void
    let newBelow: (String) -> Void

    @EnvironmentObject var store: Store
    @State private var draft = ""

    private var isEditing: Bool { editing == node.id }

    var body: some View {
        // Top-aligned with the circle sized to one body line: an empty text
        // field has no usable baseline, so baseline alignment drifts.
        HStack(alignment: .top, spacing: 10) {
            Button {
                Haptics.tap()
                store.edit { $0.toggleDone(node.id) }
            } label: {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(item.marker == .todo ? Color.accentColor : Color.secondary)
                    .frame(width: 24, height: Self.bodyLineHeight)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("checkbox")

            if isEditing {
                TextField("", text: $draft, prompt: Text("New item"), axis: .vertical)
                    .accessibilityIdentifier("itemEditor")
                    .focused(focused, equals: node.id)
                    .onAppear {
                        // Claim focus once the field exists in the hierarchy.
                        DispatchQueue.main.async { focused.wrappedValue = node.id }
                    }
                    .onChange(of: draft) { _, new in
                        if new.contains("\n") {
                            let cleaned = new.replacingOccurrences(of: "\n", with: " ")
                            draft = cleaned
                            newBelow(cleaned)
                        }
                    }
            } else {
                Text(item.text.isEmpty ? " " : item.text)
                    .strikethrough(item.marker == .done)
                    .foregroundStyle(item.marker == .todo ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("itemText")
                    .onTapGesture {
                        draft = item.text
                        editing = node.id
                    }
            }
        }
        .padding(.leading, SectionView.indentPad(item.indentWidth))
        .padding(.vertical, 2)
        .onChange(of: isEditing) { was, now in
            if was && !now { commit(draft) }
            if now && !was { draft = item.text }
        }
        .onAppear { if isEditing { draft = item.text } }
    }

    static var bodyLineHeight: CGFloat {
        #if canImport(UIKit)
        return UIFont.preferredFont(forTextStyle: .body).lineHeight
        #else
        return 22
        #endif
    }

    private var symbol: String {
        switch item.marker {
        case .todo: return "circle"
        case .done: return "checkmark.circle.fill"
        case .wontDo: return "xmark.circle"
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
