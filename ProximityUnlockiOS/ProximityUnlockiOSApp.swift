import SwiftUI
import UserNotifications

@main
struct ProximityUnlockiOSApp: App {
    @StateObject private var advertiser = ProximityAdvertiser()

    // Handle notification action responses (Approve/Deny from background notification)
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(advertiser)
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
                .onAppear {
                    // Pass advertiser to AppDelegate so notification responses can call confirm/deny
                    appDelegate.advertiser = advertiser
                    // Make the window background match the grouped list background so the
                    // status-bar and home-indicator regions don't show as black bars.
                    UIApplication.shared.connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .flatMap { $0.windows }
                        .forEach { $0.backgroundColor = UIColor.systemGroupedBackground }
                }
        }
    }
}

/// Handles notification action callbacks (user taps "Unlock Mac" or "Deny" in notification).
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    var advertiser: ProximityAdvertiser?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Called when user interacts with a notification action.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            Log.ui.info("Notification action: \(response.actionIdentifier, privacy: .public)")
            switch response.actionIdentifier {
            case "APPROVE_UNLOCK":
                advertiser?.approve()
            case "DENY_UNLOCK":
                advertiser?.deny()
            case UNNotificationDefaultActionIdentifier:
                // User tapped the notification itself — show app with confirmation UI
                advertiser?.confirmationManager.pendingRequest = true
            default:
                advertiser?.deny()
            }
            completionHandler()
        }
    }

    /// Show notification even when app is in foreground (display as banner + play sound).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // When app is in foreground, show the in-app ConfirmationView instead of banner
        completionHandler([])
    }
}
