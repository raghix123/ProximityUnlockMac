import SwiftUI
import UserNotifications

@main
struct ProximityUnlockiOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var advertiser = ProximityAdvertiser()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(advertiser)
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
                .onAppear {
                    appDelegate.advertiser = advertiser
                }
                .fullScreenCover(isPresented: Binding(
                    get: { !hasCompletedOnboarding },
                    set: { if !$0 { hasCompletedOnboarding = true } }
                )) {
                    OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                }
        }
    }
}

/// Handles notification action callbacks and sets the window background
/// synchronously before SwiftUI's first render to prevent black bars.
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    var advertiser: ProximityAdvertiser?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if DEBUG
        SecureKeyStore.shared.deleteAllData()
        #endif
        UNUserNotificationCenter.current().delegate = self

        // Set window background before first render so the status bar and
        // home indicator regions never flash black. UIWindow.didBecomeKeyNotification
        // fires as the window becomes key — earlier than SwiftUI's .onAppear.
        NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            (notification.object as? UIWindow)?.backgroundColor = UIColor.systemGroupedBackground
        }

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
