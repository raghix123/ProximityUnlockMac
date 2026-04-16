import XCTest
import Combine
@testable import ProximityUnlockMac

/// Tests for ProximityMonitor — the core state machine.
/// Lock/unlock is now purely local: no MPC, no confirmation flow.
@MainActor
final class ProximityMonitorTests: XCTestCase {

    private var monitor: ProximityMonitor!
    private var mockBLE: MockBLECentralManager!
    private var mockUnlock: MockUnlockManager!

    private let hysteresis: TimeInterval = 0.1

    override func setUp() async throws {
        mockBLE    = MockBLECentralManager()
        mockUnlock = MockUnlockManager()
        monitor = ProximityMonitor(
            bleManager: mockBLE,
            unlockManager: mockUnlock,
            hysteresisSeconds: hysteresis
        )
        monitor.isEnabled     = true
        monitor.nearThreshold = -70
        monitor.farThreshold  = -85
    }

    override func tearDown() {
        monitor    = nil
        mockBLE    = nil
        mockUnlock = nil
    }

    // MARK: - Near Transition

    func testNearTransitionUnlocksScreen() async throws {
        mockUnlock.screenLocked = true

        monitor.handleRSSI(-60)   // above nearThreshold (-70)
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 1.5 * 1_000_000_000))

        XCTAssertEqual(monitor.proximityState, .near)
        XCTAssertTrue(mockUnlock.didUnlock, "should unlock immediately when near and screen is locked")
    }

    func testNearTransitionDoesNotUnlockIfScreenAlreadyUnlocked() async throws {
        mockUnlock.screenLocked = false

        monitor.handleRSSI(-60)
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 1.5 * 1_000_000_000))

        XCTAssertEqual(monitor.proximityState, .near)
        XCTAssertFalse(mockUnlock.didUnlock, "should not call unlockScreen if already unlocked")
    }

    // MARK: - Far Transition

    func testFarTransitionLocksScreen() async throws {
        monitor.handleRSSI(-90)   // below farThreshold (-85)
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 1.5 * 1_000_000_000))

        XCTAssertEqual(monitor.proximityState, .far)
        XCTAssertTrue(mockUnlock.didLock, "should always lock screen on far transition")
    }

    // MARK: - Hysteresis

    func testHysteresisPreventsPrematureUnlock() async throws {
        mockUnlock.screenLocked = true

        monitor.handleRSSI(-60)
        // Wait only HALF the hysteresis period
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 0.4 * 1_000_000_000))

        XCTAssertNotEqual(monitor.proximityState, .near)
        XCTAssertFalse(mockUnlock.didUnlock, "should not unlock before hysteresis period elapses")
    }

    func testHysteresisResetsOnSignalDrop() async throws {
        mockUnlock.screenLocked = true

        monitor.handleRSSI(-60)   // starts near timer
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 0.4 * 1_000_000_000))

        // Signal drops into dead zone — should cancel near timer
        monitor.handleRSSI(-78)
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 1.5 * 1_000_000_000))

        XCTAssertFalse(mockUnlock.didUnlock, "near timer should be cancelled when signal drops")
    }

    // MARK: - Disabled State

    func testDisabledPreventsUnlock() async throws {
        monitor.isEnabled = false
        mockUnlock.screenLocked = true

        monitor.handleRSSI(-60)
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 1.5 * 1_000_000_000))

        XCTAssertFalse(mockUnlock.didUnlock, "should not unlock when disabled")
    }

    func testDisabledPreventsFarLock() async throws {
        monitor.isEnabled = false

        monitor.handleRSSI(-90)
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 1.5 * 1_000_000_000))

        XCTAssertFalse(mockUnlock.didLock, "should not lock when disabled")
    }

    // MARK: - Direct Transition Methods

    func testTransitionToNearDoesNothingWhenDisabled() {
        monitor.isEnabled = false
        mockUnlock.screenLocked = true

        monitor.transitionToNear()

        XCTAssertFalse(mockUnlock.didUnlock, "transitionToNear must not unlock when isEnabled is false")
        XCTAssertNotEqual(monitor.proximityState, .near)
    }

    func testTransitionToFarDoesNothingWhenDisabled() {
        monitor.isEnabled = false

        monitor.transitionToFar()

        XCTAssertFalse(mockUnlock.didLock, "transitionToFar must not lock when isEnabled is false")
        XCTAssertNotEqual(monitor.proximityState, .far)
    }

    // MARK: - End-to-End

    func testFullProximityFlow() async throws {
        mockUnlock.screenLocked = true

        // Walk toward Mac — RSSI crosses near threshold
        monitor.handleRSSI(-65)
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 1.5 * 1_000_000_000))

        XCTAssertEqual(monitor.proximityState, .near)
        XCTAssertTrue(mockUnlock.didUnlock, "Mac should unlock when iPhone is near and screen is locked")

        // Walk away — RSSI crosses far threshold (need 5 smoothed samples)
        for _ in 0..<5 { monitor.handleRSSI(-90) }
        try await Task.sleep(nanoseconds: UInt64(hysteresis * 1.5 * 1_000_000_000))

        XCTAssertEqual(monitor.proximityState, .far)
        XCTAssertTrue(mockUnlock.didLock, "Mac should lock when iPhone moves away")
    }
}
