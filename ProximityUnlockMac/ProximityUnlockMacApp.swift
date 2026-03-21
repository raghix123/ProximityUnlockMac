import SwiftUI

@main
struct ProximityUnlockMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Settings window is managed directly by AppDelegate using NSHostingView
    // to avoid the deprecated showSettingsWindow: action on macOS 26+.
    var body: some Scene {
        Settings { EmptyView() }
    }
}
