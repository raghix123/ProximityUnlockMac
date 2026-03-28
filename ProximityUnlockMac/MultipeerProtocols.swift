import Foundation

/// Protocol abstracting the Mac-side MultipeerConnectivity manager.
/// Enables injection of mocks in tests without depending on real MPC infrastructure.
protocol MacMultipeerManaging: AnyObject {
    var onConfirmationReceived: ((Bool) -> Void)? { get set }
    var onLockCommand: (() -> Void)? { get set }
    var onUnlockCommand: (() -> Void)? { get set }

    func startBrowsing()
    func stopBrowsing()

    /// Sends a command to all connected peers. Returns true if at least one peer received it.
    @discardableResult
    func sendCommand(_ command: String) -> Bool
}

/// No-op implementation used as default when no mock is injected in the test init.
/// Behaves as if MPC is always disconnected — sendCommand always returns false,
/// causing ProximityMonitor to fall through to the BLE fallback (preserving test behavior).
final class NullMultipeerManager: MacMultipeerManaging {
    var onConfirmationReceived: ((Bool) -> Void)?
    var onLockCommand: (() -> Void)?
    var onUnlockCommand: (() -> Void)?
    func startBrowsing() {}
    func stopBrowsing() {}
    @discardableResult func sendCommand(_ command: String) -> Bool { return false }
}
