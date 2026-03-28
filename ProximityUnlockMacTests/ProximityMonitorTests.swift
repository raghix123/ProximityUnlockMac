import XCTest
import Combine
@testable import ProximityUnlockMac

/// Tests for ProximityMonitor — the core state machine.
/// All BLE and unlock operations are mocked; timers run at 0.1s for speed.
@MainActor
final class ProximityMonitorTests: XCTestCase {

    private var monitor: ProximityMonitor!
    private var mockBLE: MockBLECentralManager!
    private var mockUnlock: MockUnlockManager!

    // Use fast hysteresis/timeout so tests finish quickly.
    private let hysteresis: TimeInterval = 0.1
    private let confirmTimeout: TimeInterval = 0.3

    override func setUp() async throws {
        mockBLE    = MockBLECentralManager()
        mockUnlock = MockUnlockManager()
        monitor = ProximityMonitor(
            bleManager: mockBLE,
            unlockManager: mockUnlock,
            hysteresisSeconds: hysteresis,
            confirmationTimeout: confirmTimeout
        )
        // Deterministic settings — override anything in UserDefaults
        monitor.isEnabled          = true
        monitor.requireConfirmation = false   // default to no-confirmation for most tests
        monitor.nearThreshold      = -70
        monitor.farThreshold       = -85
        UserDefaults.standard.set(false, forKey: "lockWhenFar")
    }

    override func tearDown() {
        monitor = nil
        mockBLE = nil
        mockUnlock = nil
    }

    // MARK: - Near Transition

    func testNearTransitionUnlocksScreen() async throws {
        mockUnlock.screenLocked = true
        monitor.requireConfirmation = false

        monitor.handleRSSI(-60)   // above nearThreshold (-70)
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 1.5 * 1_000_000_000))

        // RSSI crossed — Mac sends unlock_request via MPC and waits for approval.
        // Even with requireConfirmation=false the round-trip goes over WiFi.
        XCTAssertEqual(monitor.proximityState, .near)
        XCTAssertTrue(monitor.awaitingConfirmation, "should be awaiting MPC approval even with requireConfirmation=false")
        XCTAssertTrue(mockBLE.didWrite("unlock_request"), "unlock_request must be sent via MPC channel")
        XCTAssertFalse(mockUnlock.didUnlock, "must not unlock until iPhone approval arrives over MPC")

        // iPhone auto-approves via MPC → Mac unlocks
        monitor.handleConfirmationResponse(true)
        XCTAssertTrue(mockUnlock.didUnlock, "unlockScreen should be called after MPC approval")
        XCTAssertFalse(monitor.awaitingConfirmation)
    }

    func testNearTransitionDoesNotUnlockIfScreenAlreadyUnlocked() async throws {
        mockUnlock.screenLocked = false
        monitor.requireConfirmation = false

        monitor.handleRSSI(-60)
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 1.5 * 1_000_000_000))

        XCTAssertEqual(monitor.proximityState, .near)
        XCTAssertFalse(mockUnlock.didUnlock, "should not call unlockScreen if already unlocked")
    }

    // MARK: - Hysteresis

    func testHysteresisPreventsPrematureUnlock() async throws {
        mockUnlock.screenLocked = true
        monitor.requireConfirmation = false

        monitor.handleRSSI(-60)
        // Wait only HALF the hysteresis period
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 0.4 * 1_000_000_000))

        XCTAssertNotEqual(monitor.proximityState, .near)
        XCTAssertFalse(mockUnlock.didUnlock, "should not unlock before hysteresis period elapses")
    }

    func testHysteresisResetsOnSignalDrop() async throws {
        mockUnlock.screenLocked = true
        monitor.requireConfirmation = false

        monitor.handleRSSI(-60)   // starts near timer
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 0.4 * 1_000_000_000))

        // Signal drops into dead zone — should cancel near timer
        monitor.handleRSSI(-78)
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 1.5 * 1_000_000_000))

        XCTAssertFalse(mockUnlock.didUnlock, "near timer should be cancelled when signal drops")
    }

    // MARK: - Far Transition

    func testFarTransitionLocksWhenEnabled() async throws {
        UserDefaults.standard.set(true, forKey: "lockWhenFar")
        monitor.handleRSSI(-90)   // below farThreshold (-85)
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 1.5 * 1_000_000_000))

        XCTAssertEqual(monitor.proximityState, .far)
        XCTAssertTrue(mockUnlock.didLock)
    }

    func testFarTransitionDoesNotLockWhenSettingDisabled() async throws {
        UserDefaults.standard.set(false, forKey: "lockWhenFar")
        monitor.handleRSSI(-90)
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 1.5 * 1_000_000_000))

        XCTAssertEqual(monitor.proximityState, .far)
        XCTAssertFalse(mockUnlock.didLock, "should not lock when lockWhenFar is false")
    }

    func testFarTransitionSendsLockEventToiPhone() async throws {
        monitor.handleRSSI(-90)
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 1.5 * 1_000_000_000))

        XCTAssertTrue(mockBLE.didWrite("lock_event"), "should write lock_event to iPhone on far transition")
    }

    // MARK: - Disabled State

    func testDisabledPreventsUnlock() async throws {
        monitor.isEnabled = false
        monitor.handleRSSI(-60)
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 1.5 * 1_000_000_000))

        XCTAssertFalse(mockUnlock.didUnlock, "should not unlock when disabled")
    }

    func testDisabledPreventsFarLock() async throws {
        monitor.isEnabled = false
        UserDefaults.standard.set(true, forKey: "lockWhenFar")
        monitor.handleRSSI(-90)
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 1.5 * 1_000_000_000))

        XCTAssertFalse(mockUnlock.didLock, "should not lock when disabled")
    }

    // MARK: - Confirmation Flow

    func testConfirmationRequiredSendsRequest() async throws {
        monitor.requireConfirmation = true
        mockUnlock.screenLocked = true

        monitor.handleRSSI(-60)
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 1.5 * 1_000_000_000))

        XCTAssertTrue(mockBLE.didWrite("unlock_request"), "should write unlock_request when requireConfirmation is on")
        XCTAssertTrue(monitor.awaitingConfirmation)
        XCTAssertFalse(mockUnlock.didUnlock, "should NOT unlock immediately — must wait for iPhone approval")
    }

    func testUnlockAfterApproval() async throws {
        monitor.requireConfirmation = true
        mockUnlock.screenLocked = true

        monitor.handleRSSI(-60)
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 1.5 * 1_000_000_000))
        XCTAssertTrue(monitor.awaitingConfirmation)

        // iPhone approves
        monitor.handleConfirmationResponse(true)
        XCTAssertTrue(mockUnlock.didUnlock)
        XCTAssertFalse(monitor.awaitingConfirmation)
    }

    func testUnlockBlockedAfterDenial() async throws {
        monitor.requireConfirmation = true
        mockUnlock.screenLocked = true

        monitor.handleRSSI(-60)
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 1.5 * 1_000_000_000))

        // iPhone denies
        monitor.handleConfirmationResponse(false)
        XCTAssertFalse(mockUnlock.didUnlock, "denied confirmation must not unlock screen")
        XCTAssertFalse(monitor.awaitingConfirmation)
    }

    func testConfirmationTimesOut() async throws {
        monitor.requireConfirmation = true
        mockUnlock.screenLocked = true

        monitor.handleRSSI(-60)
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 1.5 * 1_000_000_000))
        XCTAssertTrue(monitor.awaitingConfirmation)

        // Wait for confirmation timeout
        try await Task.sleep(nanoseconds: UInt64(confirmTimeout * 1.5 * 1_000_000_000))
        XCTAssertFalse(monitor.awaitingConfirmation, "awaitingConfirmation should clear after timeout")
        XCTAssertFalse(mockUnlock.didUnlock, "screen must not unlock after timeout with no response")
    }

    func testDeviceLostCancelsConfirmationWait() async throws {
        monitor.requireConfirmation = true
        mockUnlock.screenLocked = true

        monitor.handleRSSI(-60)
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 1.5 * 1_000_000_000))
        XCTAssertTrue(monitor.awaitingConfirmation)

        // Simulate device lost
        monitor.isPhoneDetected = false
        monitor.proximityState = .unknown
        monitor.cancelConfirmationWait()

        XCTAssertFalse(monitor.awaitingConfirmation, "pending confirmation must be cleared when device is lost")
        XCTAssertFalse(mockUnlock.didUnlock)
    }

    // MARK: - End-to-End Simulation

    /// Complete simulation: phone approaches → unlock request sent → iPhone approves → screen unlocks.
    func testFullUnlockHandshake() async throws {
        monitor.requireConfirmation = true
        mockUnlock.screenLocked = true
        monitor.isPhoneDetected = true

        // Step 1: RSSI crosses near threshold (simulating phone getting close)
        monitor.handleRSSI(-65)
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 1.5 * 1_000_000_000))

        // Step 2: Mac should have sent unlock_request to iPhone
        XCTAssertTrue(mockBLE.didWrite("unlock_request"), "Mac must request confirmation from iPhone")
        XCTAssertTrue(monitor.awaitingConfirmation)
        XCTAssertFalse(mockUnlock.didUnlock, "must not unlock before iPhone confirms")

        // Step 3: User taps "Unlock Mac" on iPhone → iPhone sends "approved"
        monitor.handleConfirmationResponse(true)

        // Step 4: Mac should now unlock
        XCTAssertTrue(mockUnlock.didUnlock, "screen must unlock after iPhone approves")
        XCTAssertEqual(monitor.proximityState, .near)
        XCTAssertFalse(monitor.awaitingConfirmation)
    }

    /// Denial flow: phone approaches → request sent → user denies on iPhone → no unlock.
    func testFullDenialHandshake() async throws {
        monitor.requireConfirmation = true
        mockUnlock.screenLocked = true

        monitor.handleRSSI(-65)
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 1.5 * 1_000_000_000))

        monitor.handleConfirmationResponse(false)
        XCTAssertFalse(mockUnlock.didUnlock)
        XCTAssertEqual(mockBLE.writtenCommands.filter { $0 == "unlock_request" }.count, 1)
    }

    // MARK: - Direct Transition Methods When Disabled

    func testTransitionToNearDoesNothingWhenDisabled() async throws {
        monitor.isEnabled = false
        mockUnlock.screenLocked = true

        // Call transitionToNear directly — it should bail out because isEnabled is false.
        monitor.transitionToNear()

        XCTAssertFalse(mockUnlock.didUnlock, "transitionToNear must not unlock when isEnabled is false")
        // proximityState should NOT be set to .near when disabled
        XCTAssertNotEqual(monitor.proximityState, .near, "proximityState must not change to .near when disabled")
    }

    func testTransitionToFarDoesNothingWhenDisabled() async throws {
        monitor.isEnabled = false
        UserDefaults.standard.set(true, forKey: "lockWhenFar")

        // Call transitionToFar directly — it should bail out because isEnabled is false.
        monitor.transitionToFar()

        XCTAssertFalse(mockUnlock.didLock, "transitionToFar must not lock when isEnabled is false")
        // proximityState should NOT be set to .far when disabled
        XCTAssertNotEqual(monitor.proximityState, .far, "proximityState must not change to .far when disabled")
        XCTAssertFalse(mockBLE.didWrite("lock_event"), "should not send lock_event when disabled")
    }

    func testConfirmationApprovalDoesNothingWhenScreenNotLocked() async throws {
        mockUnlock.screenLocked = false
        monitor.requireConfirmation = true
        monitor.awaitingConfirmation = true

        // Simulate approval when screen is already unlocked — deduplication guard.
        monitor.handleConfirmationResponse(true)

        XCTAssertFalse(mockUnlock.didUnlock, "should not call unlockScreen when screen is already unlocked")
        XCTAssertFalse(monitor.awaitingConfirmation, "awaitingConfirmation should still be cleared")
    }
}
