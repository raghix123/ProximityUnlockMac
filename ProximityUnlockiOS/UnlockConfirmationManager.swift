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
    private let confirmNotificationId = "com.raghav.ProximityUnlock.unlockRequest"

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
        if !requiresConfirmation {
            approve()
            return
        }
        pendingRequest = true
        scheduleUnlockNotification()
    }

    /// Handles a lock event arriving via BLE or MPC.
    func receiveLockEvent() {
        pendingRequest = false
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [confirmNotificationId])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [confirmNotificationId])
    }

    private func handleUnlockRequest() { receiveUnlockRequest() }
    private func handleLockEvent()     { receiveLockEvent() }

    // MARK: - Confirmation Actions

    func approve() {
        bleManager?.sendConfirmation(approved: true)
        pendingRequest = false
        cancelNotification()
    }

    func deny() {
        bleManager?.sendConfirmation(approved: false)
        pendingRequest = false
        cancelNotification()
    }

    // MARK: - Notifications

    func requestNotificationPermission() {
        notificationCenter.requestAuthorization(options: [.alert, .sound]) { _, _ in }
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
