import SwiftUI
import AuthenticationServices
import PhoneListCore

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Dropbox") {
                    if !Store.hasAppKey {
                        Label("No Dropbox app key. Set DROPBOX_APP_KEY in Config.xcconfig (see README).",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    if store.isLinked {
                        Button("Unlink Dropbox", role: .destructive) { store.unlink() }
                    } else {
                        Button("Link Dropbox…") { store.link(presentationAnchor: anchor) }
                            .disabled(!Store.hasAppKey)
                    }
                    TextField("Path in Dropbox", text: $store.path)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                }
                Section("Sync") {
                    LabeledContent("Status", value: store.status.label)
                    Button("Download now") { Task { await store.pull() } }.disabled(!store.isLinked)
                    Button("Upload now") { Task { await store.push() } }.disabled(!store.isLinked || !store.isDirty)
                }
                Section("About") {
                    Text("Edits only the lines you touch. Completed items stay in place until you sweep them into done.txt on a laptop.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var anchor: ASPresentationAnchor? {
        #if os(iOS)
        return UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        #else
        return nil
        #endif
    }
}
