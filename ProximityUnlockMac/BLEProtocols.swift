import CoreBluetooth
import Foundation

// MARK: - CBCentralManager Protocol (for testability)

/// Abstracts CBCentralManager so tests can inject a mock.
protocol CBCentralManagerProtocol: AnyObject {
    var state: CBManagerState { get }
    func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]?)
    func stopScan()
    func connect(_ peripheral: CBPeripheral, options: [String: Any]?)
    func cancelPeripheralConnection(_ peripheral: CBPeripheral)
}

extension CBCentralManager: CBCentralManagerProtocol {}

// MARK: - High-Level BLE Central Protocol

/// Consumed by ProximityMonitor. Only exposes the write-command direction;
/// the reverse direction (RSSI, found, lost, confirmation) is wired via closures
/// stored in BLECentralManager and callable by tests directly on ProximityMonitor.
protocol BLECentralManaging: AnyObject {
    func writeCommand(_ command: String)
}

// MARK: - UnlockManager Protocol

/// Allows MockUnlockManager to be injected in tests.
protocol UnlockManaging {
    func isScreenLocked() -> Bool
    func unlockScreen()
    func lockScreen()
}

extension UnlockManager: UnlockManaging {}
