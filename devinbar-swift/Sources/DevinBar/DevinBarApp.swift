import SwiftUI

@main
struct DevinBarApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra("Devin", systemImage: "d.circle.fill") {
            ContentView(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
