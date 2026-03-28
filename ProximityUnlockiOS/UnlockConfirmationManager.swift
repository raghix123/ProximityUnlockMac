import Foundation
import UserNotifications

/// Handles incoming unlock requests from the Mac and dispatches confirmations.
/// Supports in-app UI (via `pendingRequest`) and iOS notifications (background-safe).
@MainActor
class UnlockConfirmationManager: ObservableObject {

    @Published var pendingRequest: Bool = false
    @Published var requiresConfirmation: Bool = true {
        didSet { UserDefaults.standard.set(requiresConfirmation, forKey: "requiresConfirmation") }
    }

    private weak var bleManager: BLEPeripheralManager?
    private let notificationCenter: any NotificationCentering

    /// Called after BLE confirmation is sent so the caller can also send via MPC.
    var onConfirmationSent: ((Bool) -> Void)?
    private let confirmNotificationId = "com.raghav.ProximityUnlock.unlockRequest"
    private var requestTimeoutTimer: Timer?

    // MARK: - Init

    /// Production init — uses real UNUserNotificationCenter.
    convenience init(bleManager: BLEPeripheralManager) {
        self.init(bleManager: bleManager, notificationCenter: UNUserNotificationCenter.current())
    }

    /// Testable init — accepts injectable notification center.
    init(bleManager: BLEPeripheralManager, notificationCenter: any NotificationCentering) {
        self.bleManager = bleManager
        self.notificationCenter = notificationCenter
        requiresConfirmation = UserDefaults.standard.object(forKey: "requiresConfirmation").map {
            _ in UserDefaults.standard.bool(forKey: "requiresConfirmation")
        } ?? true

        bleManager.onUnlockRequest = { [weak self] in
            Task { @MainActor [weak self] in self?.handleUnlockRequest() }
        }
        bleManager.onLockEvent = { [weak self] in
            Task { @MainActor [weak self] in self?.handleLockEvent() }
        }
    }

    // MARK: - Request Handling

    /// Handles an unlock request arriving via BLE or MPC.
    func receiveUnlockRequest() {
        Log.unlock.info("Received unlock request (requiresConfirmation=\(self.requiresConfirmation, privacy: .public))")
        if !requiresConfirmation {
            approve()
            return
        }
        pendingRequest = true
        scheduleUnlockNotification()

        requestTimeoutTimer?.invalidate()
        requestTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                Log.unlock.info("Unlock request timed out on iOS side")
                self?.pendingRequest = false
                self?.cancelNotification()
            }
        }
    }

    /// Handles a lock event arriving via BLE or MPC.
    func receiveLockEvent() {
        Log.unlock.info("Received lock event")
        requestTimeoutTimer?.invalidate()
        requestTimeoutTimer = nil
        pendingRequest = false
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [confirmNotificationId])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [confirmNotificationId])
    }

    private func handleUnlockRequest() { receiveUnlockRequest() }
    private func handleLockEvent()     { receiveLockEvent() }

    // MARK: - Confirmation Actions

    func approve() {
        Log.unlock.info("Confirmation approved")
        requestTimeoutTimer?.invalidate()
        requestTimeoutTimer = nil
        bleManager?.sendConfirmation(approved: true)
        onConfirmationSent?(true)
        pendingRequest = false
        cancelNotification()
    }

    func deny() {
        Log.unlock.info("Confirmation denied")
        requestTimeoutTimer?.invalidate()
        requestTimeoutTimer = nil
        bleManager?.sendConfirmation(approved: false)
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
}
