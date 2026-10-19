import SwiftUI
import PhoneListUI

@main
struct PhoneListApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
        }
    }
}
