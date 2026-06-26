import SwiftUI

@main
struct DevinBarApp: App {
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView(store: store)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "d.circle.fill")
                Text(store.todayCost, format: .currency(code: "USD").precision(.fractionLength(0)))
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
