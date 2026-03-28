import XCTest
@testable import ProximityUnlockiOS

/// Tests for UnlockConfirmationManager — the confirmation handshake and notification logic.
@MainActor
final class UnlockConfirmationManagerTests: XCTestCase {

    private var bleManager: BLEPeripheralManager!
    private var confirmManager: UnlockConfirmationManager!
    private var mockNC: MockNotificationCenter!
    private var mockPM: MockCBPeripheralManager!

    override func setUp() async throws {
        mockPM = MockCBPeripheralManager()
        mockPM.state = .poweredOn
        bleManager = BLEPeripheralManager(peripheralManager: mockPM)
        mockNC = MockNotificationCenter()
        confirmManager = UnlockConfirmationManager(bleManager: bleManager, notificationCenter: mockNC)
        confirmManager.requiresConfirmation = true
    }

    override func tearDown() {
        bleManager = nil
        confirmManager = nil
        mockNC = nil
        mockPM = nil
    }

    // MARK: - Auto-Approve (No Confirmation Required)

    func testAutoApproveWhenConfirmationDisabled() async throws {
        confirmManager.requiresConfirmation = false

        bleManager.simulateIncomingCommand("unlock_request")
        try await Task.sleep(nanoseconds: 100_000_000)  // 0.1s for main queue dispatch

        XCTAssertFalse(confirmManager.pendingRequest, "pendingRequest must not be set when auto-approving")
        XCTAssertFalse(mockNC.notificationFired, "no notification should be fired when auto-approving")
        // sendConfirmation called with approved=true; no subscribers so no updateValue, but state is consistent
    }

    /// Tests receiveUnlockRequest() directly (not via BLE simulation) with confirmation disabled.
    func testDirectReceiveUnlockRequestAutoApprovesWhenConfirmationDisabled() {
        confirmManager.requiresConfirmation = false

        confirmManager.receiveUnlockRequest()

        XCTAssertFalse(confirmManager.pendingRequest, "pendingRequest must not be set when auto-approving")
        XCTAssertFalse(mockNC.notificationFired, "no notification should be fired when auto-approving")
    }

    /// Tests receiveUnlockRequest() directly with confirmation enabled — should show notification.
    func testDirectReceiveUnlockRequestShowsNotificationWhenConfirmationEnabled() {
        confirmManager.requiresConfirmation = true

        confirmManager.receiveUnlockRequest()

        XCTAssertTrue(confirmManager.pendingRequest, "pendingRequest must be set when confirmation is required")
        XCTAssertTrue(mockNC.notificationFired, "notification must be fired when confirmation is required")
    }

    // MARK: - Notification Firing

    func testNotificationFiredWhenConfirmationRequired() async throws {
        confirmManager.requiresConfirmation = true

        bleManager.simulateIncomingCommand("unlock_request")
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(mockNC.notificationFired, "a notification should be scheduled for user to approve/deny")
        XCTAssertTrue(confirmManager.pendingRequest)
        XCTAssertEqual(mockNC.lastRequest?.identifier, "com.raghav.ProximityUnlock.unlockRequest")
    }

    // MARK: - Approve / Deny

    func testApproveClears() async throws {
        bleManager.simulateIncomingCommand("unlock_request")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(confirmManager.pendingRequest)

        confirmManager.approve()
        XCTAssertFalse(confirmManager.pendingRequest, "pendingRequest must be false after approve()")
    }

    func testDenyClears() async throws {
        bleManager.simulateIncomingCommand("unlock_request")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(confirmManager.pendingRequest)

        confirmManager.deny()
        XCTAssertFalse(confirmManager.pendingRequest, "pendingRequest must be false after deny()")
    }

    func testApproveCancelsNotification() async throws {
        bleManager.simulateIncomingCommand("unlock_request")
        try await Task.sleep(nanoseconds: 100_000_000)

        confirmManager.approve()
        XCTAssertTrue(
            mockNC.removedPendingIdentifiers.contains("com.raghav.ProximityUnlock.unlockRequest"),
            "notification must be cancelled on approve"
        )
    }

    func testDenyCancelsNotification() async throws {
        bleManager.simulateIncomingCommand("unlock_request")
        try await Task.sleep(nanoseconds: 100_000_000)

        confirmManager.deny()
        XCTAssertTrue(
            mockNC.removedPendingIdentifiers.contains("com.raghav.ProximityUnlock.unlockRequest"),
            "notification must be cancelled on deny"
        )
    }

    // MARK: - Lock Event Clears Pending Request

    func testLockEventClearsPendingRequest() async throws {
        bleManager.simulateIncomingCommand("unlock_request")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(confirmManager.pendingRequest)

        bleManager.simulateIncomingCommand("lock_event")
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertFalse(confirmManager.pendingRequest, "lock_event must clear any pending unlock request")
    }

    func testLockEventCancelsNotification() async throws {
        bleManager.simulateIncomingCommand("unlock_request")
        try await Task.sleep(nanoseconds: 100_000_000)

        bleManager.simulateIncomingCommand("lock_event")
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(
            mockNC.removedPendingIdentifiers.contains("com.raghav.ProximityUnlock.unlockRequest"),
            "lock_event must cancel the pending notification"
        )
    }

    // MARK: - Notification Permission

    func testRequestNotificationPermission() {
        confirmManager.requestNotificationPermission()
        XCTAssertTrue(mockNC.authorizationRequested)
        XCTAssertFalse(mockNC.categoriesSet.isEmpty, "notification categories must be registered")
    }
}
