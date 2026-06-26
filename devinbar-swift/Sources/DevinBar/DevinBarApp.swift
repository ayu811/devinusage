import SwiftUI

@main
struct DevinBarApp: App {
    @StateObject private var store = UsageStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            ContentView(store: store)
        } label: {
            Image(nsImage: devinMenuBarIcon())
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
        .menuBarExtraStyle(.window)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = devinAppIcon(size: 128)
    }
}
