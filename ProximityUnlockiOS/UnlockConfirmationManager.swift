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
    private let notificationCenter = UNUserNotificationCenter.current()
    private let confirmNotificationId = "com.raghav.ProximityUnlock.unlockRequest"

    init(bleManager: BLEPeripheralManager) {
        self.bleManager = bleManager
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

    private func handleUnlockRequest() {
        if !requiresConfirmation {
            // Auto-approve without user confirmation
            approve()
            return
        }

        pendingRequest = true

        // Show notification so the user can respond while app is in background
        scheduleUnlockNotification()
    }

    private func handleLockEvent() {
        pendingRequest = false
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [confirmNotificationId])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [confirmNotificationId])
    }

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
            options: [.authenticationRequired]  // requires Face ID / passcode to execute
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
        content.body = "Your Mac is requesting to unlock. Allow?"
        content.categoryIdentifier = "UNLOCK_REQUEST"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: confirmNotificationId,
            content: content,
            trigger: nil  // deliver immediately
        )
        notificationCenter.add(request)
    }

    private func cancelNotification() {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [confirmNotificationId])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [confirmNotificationId])
    }
}
