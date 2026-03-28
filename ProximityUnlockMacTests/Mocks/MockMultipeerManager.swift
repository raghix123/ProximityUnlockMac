import Foundation
@testable import ProximityUnlockMac

/// Mock MultipeerConnectivity manager for unit tests.
/// Records all commands sent via MPC so tests can assert on them.
/// Returns true from sendCommand() to simulate a connected peer (unlike NullMultipeerManager).
/// To simulate no MPC connection (BLE fallback active), use NullMultipeerManager instead.
final class MockMultipeerManager: MacMultipeerManaging {

    // MARK: - MacMultipeerManaging Callbacks

    var onConfirmationReceived: ((Bool) -> Void)?
    var onLockCommand: (() -> Void)?
    var onUnlockCommand: (() -> Void)?

    // MARK: - Recorded Calls

    private(set) var sentCommands: [String] = []
    private(set) var startBrowsingCalled = false
    private(set) var stopBrowsingCalled = false

    // MARK: - MacMultipeerManaging

    func startBrowsing() { startBrowsingCalled = true }
    func stopBrowsing()  { stopBrowsingCalled = true }

    @discardableResult
    func sendCommand(_ command: String) -> Bool {
        sentCommands.append(command)
        return true   // simulate connected peer
    }

    // MARK: - Helpers

    /// Returns true if `command` was sent at any point.
    func didSend(_ command: String) -> Bool {
        sentCommands.contains(command)
    }

    func reset() {
        sentCommands = []
        startBrowsingCalled = false
        stopBrowsingCalled = false
    }
}
