import SwiftUI
import PhoneListCore

public struct RootView: View {
    @EnvironmentObject var store: Store
    @State private var selectedSection: UUID?
    @State private var showSettings = false
    /// The item currently being edited, if any. Drives the edit bar.
    @State private var editingID: UUID?
    /// Title of the section last viewed, so the app reopens where you left off.
    @AppStorage("lastSectionTitle") private var lastSectionTitle = ""
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    private var sections: [FileSection] { store.document.sections }
    private var current: FileSection? {
        sections.first { $0.id == selectedSection }
            ?? sections.first { $0.title == lastSectionTitle }
            ?? sections.first
    }

    public var body: some View {
        NavigationStack {
            Group {
                if let section = current {
                    SectionView(sectionID: section.id, editingID: $editingID)
                } else {
                    ContentUnavailableView("Empty file", systemImage: "doc.text")
                }
            }
            .navigationTitle(current?.title ?? "PhoneList")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .principal) { sectionMenu }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        #if os(iOS)
                        EditButton()
                        #endif
                        Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Drawn by the app rather than via the `.keyboard` toolbar
                // placement, which does not appear on some iOS 26 devices.
                if let id = editingID { editBar(id) } else { statusBar }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $store.conflict) { c in ConflictView(conflict: c) }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await store.pull() }
            case .background, .inactive: Task { await store.push() }
            @unknown default: break
            }
        }
        .task { await store.pull() }
    }

    private var sectionMenu: some View {
        Menu {
            Picker("Section", selection: Binding(get: { current?.id }, set: { id in
                selectedSection = id
                if let t = sections.first(where: { $0.id == id })?.title { lastSectionTitle = t }
            })) {
                ForEach(sections) { s in
                    Text(s.title).tag(Optional(s.id))
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(current?.title ?? "PhoneList").font(.headline).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.bold())
            }
            .foregroundStyle(.primary)
        }
    }

    private func editBar(_ id: UUID) -> some View {
        HStack(spacing: 4) {
            barButton("decrease.indent", id: "outdent") { store.edit { $0.outdent(id) } }
            barButton("increase.indent", id: "indent") { store.edit { $0.indent(id) } }
            barButton("plus", id: "newBelow") {
                let new = store.edit(returning: { $0.insertItem(after: id) })
                if let new { editingID = new }
            }
            barButton("nosign", id: "wontDo") { Haptics.warning(); store.edit { $0.toggleWontDo(id) } }
            Spacer()
            Button("Done") { editingID = nil }
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .accessibilityIdentifier("doneEditing")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func barButton(_ symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 44, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            switch store.status {
            case .syncing: ProgressView().controlSize(.small)
            case .error: Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            case .conflict: Image(systemName: "exclamationmark.2").foregroundStyle(.red)
            case .dirty: Image(systemName: "circle.fill").foregroundStyle(.secondary).font(.system(size: 7))
            case .notLinked: Image(systemName: "link.badge.plus").foregroundStyle(.secondary)
            case .idle: Image(systemName: "checkmark.icloud").foregroundStyle(.secondary)
            }
            Text(store.status.label).lineLimit(1)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
        .onTapGesture {
            if case .error = store.status { Task { await store.pull() } }
            if case .conflict = store.status, store.conflict == nil { Task { await store.pull() } }
        }
    }
}

struct ConflictView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss
    let conflict: Store.Conflict

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("The file changed on Dropbox in a way that overlaps with edits made here, and they could not be merged automatically.")
                Text("Keep the phone version to overwrite Dropbox. Use the Dropbox version to discard the edits made here.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await store.resolveConflict(keepMine: true); dismiss() }
                } label: { Text("Keep phone version").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                Button(role: .destructive) {
                    Task { await store.resolveConflict(keepMine: false); dismiss() }
                } label: { Text("Use Dropbox version").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("Sync conflict")
        }
        .interactiveDismissDisabled()
    }
}
