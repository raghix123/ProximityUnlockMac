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

/// M7+: BLE is RSSI-only. No command writing. The manager handles scanning, connection
/// for RSSI polling, device found/lost events, and RSSI updates.
protocol BLECentralManaging: AnyObject {}

// MARK: - UnlockManager Protocol

/// Allows MockUnlockManager to be injected in tests.
protocol UnlockManaging {
    func isScreenLocked() -> Bool
    func unlockScreen()
    func lockScreen()
}

extension UnlockManager: UnlockManaging {}
