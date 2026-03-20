import SwiftUI

@main
struct ProximityUnlockMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.proximityMonitor)
        }
    }
}
