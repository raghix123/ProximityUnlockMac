import Foundation
import UserNotifications

/// Handles incoming unlock requests from the Mac and dispatches confirmations.
/// Supports in-app UI (via `pendingRequest`) and iOS notifications (background-safe).
/// M8+: When requiresConfirmation=false, checks biometric recency before auto-approving.
///      Falls back to manual UI if biometric check fails (cancelled, timed out, no passcode).
@MainActor
class UnlockConfirmationManager: ObservableObject {

    @Published var pendingRequest: Bool = false
    @Published var requiresConfirmation: Bool = true {
        didSet { UserDefaults.standard.set(requiresConfirmation, forKey: "requiresConfirmation") }
    }

    /// Seconds within which a previous authentication counts as "recent" (default 120s = 2 min).
    /// Stored in UserDefaults so the user's choice persists across launches.
    @Published var recencyWindowSeconds: TimeInterval = 120 {
        didSet { UserDefaults.standard.set(recencyWindowSeconds, forKey: "recencyWindowSeconds") }
    }

    private let notificationCenter: any NotificationCentering
    private let biometricChecker: any BiometricChecking

    /// Called when a confirmation is sent so the caller can forward it via MPC.
    var onConfirmationSent: ((Bool) -> Void)?
    private let confirmNotificationId = "com.raghav.ProximityUnlock.unlockRequest"
    private var requestTimeoutTimer: Timer?

    // MARK: - Init

    /// Production init — uses real notification center and biometric checker.
    convenience init() {
        self.init(
            notificationCenter: UNUserNotificationCenter.current(),
            biometricChecker: BiometricRecencyChecker()
        )
    }

    /// Testable init — accepts injectable dependencies.
    init(notificationCenter: any NotificationCentering, biometricChecker: (any BiometricChecking)? = nil) {
        let biometricChecker = biometricChecker ?? BiometricRecencyChecker()
        self.notificationCenter = notificationCenter
        self.biometricChecker = biometricChecker
        requiresConfirmation = UserDefaults.standard.object(forKey: "requiresConfirmation").map {
            _ in UserDefaults.standard.bool(forKey: "requiresConfirmation")
        } ?? true
        if let stored = UserDefaults.standard.object(forKey: "recencyWindowSeconds") as? Double {
            recencyWindowSeconds = stored
        }
    }

    // MARK: - Request Handling

    /// Handles an unlock request arriving via MPC.
    func receiveUnlockRequest() {
        Log.unlock.info("Received unlock request (requiresConfirmation=\(self.requiresConfirmation, privacy: .public))")
        if !requiresConfirmation {
            // Check biometric recency before auto-approving.
            biometricChecker.checkRecency(withinSeconds: recencyWindowSeconds) { [weak self] passed in
                guard let self else { return }
                if passed {
                    Log.unlock.info("Biometric recency passed — auto-approving")
                    self.approve()
                } else {
                    // Recency check failed (window expired, cancelled, or no passcode).
                    // Fall back to manual approve/deny UI.
                    Log.unlock.info("Biometric recency failed — showing manual confirmation UI")
                    self.pendingRequest = true
                    self.scheduleUnlockNotification()
                    self.startRequestTimeout()
                }
            }
            return
        }
        pendingRequest = true
        scheduleUnlockNotification()
        startRequestTimeout()
    }

    /// Handles a lock event arriving via MPC.
    func receiveLockEvent() {
        Log.unlock.info("Received lock event")
        requestTimeoutTimer?.invalidate()
        requestTimeoutTimer = nil
        pendingRequest = false
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [confirmNotificationId])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [confirmNotificationId])
    }

    // MARK: - Confirmation Actions

    func approve() {
        Log.unlock.info("Confirmation approved")
        requestTimeoutTimer?.invalidate()
        requestTimeoutTimer = nil
        onConfirmationSent?(true)
        pendingRequest = false
        cancelNotification()
    }

    func deny() {
        Log.unlock.info("Confirmation denied")
        requestTimeoutTimer?.invalidate()
        requestTimeoutTimer = nil
        onConfirmationSent?(false)
        pendingRequest = false
        cancelNotification()
    }

    // MARK: - Notifications

    func requestNotificationPermission() {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { granted, error in
            Log.unlock.info("Notification permission: \(granted ? "granted" : "denied", privacy: .public)")
        }
        registerNotificationActions()
    }

    private func registerNotificationActions() {
        let approveAction = UNNotificationAction(
            identifier: "APPROVE_UNLOCK",
            title: "Unlock Mac",
            options: [.authenticationRequired]
        )
        let denyAction = UNNotificationAction(
            identifier: "DENY_UNLOCK",
            title: "Deny",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: "UNLOCK_REQUEST",
            actions: [approveAction, denyAction],
            intentIdentifiers: [],
            options: []
        )
        notificationCenter.setNotificationCategories([category])
    }

    private func scheduleUnlockNotification() {
        Log.unlock.info("Scheduling unlock notification")
        let content = UNMutableNotificationContent()
        content.title = "Mac Unlock Request"
        content.body = "Your Mac is requesting to unlock the screen. Allow?"
        content.categoryIdentifier = "UNLOCK_REQUEST"
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: confirmNotificationId,
            content: content,
            trigger: nil
        )
        notificationCenter.add(request, withCompletionHandler: nil)
    }

    private func cancelNotification() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [confirmNotificationId])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [confirmNotificationId])
    }

    private func startRequestTimeout() {
        requestTimeoutTimer?.invalidate()
        requestTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                Log.unlock.info("Unlock request timed out on iOS side")
                self?.pendingRequest = false
                self?.cancelNotification()
            }
        }
    }
}
