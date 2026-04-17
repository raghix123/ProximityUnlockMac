import CoreBluetooth
import Foundation

/// A Bluetooth device discovered during scanning.
struct DiscoveredDevice: Identifiable, Equatable {
    let id: UUID       // CBPeripheral.identifier (stable within a session)
    let name: String
    var rssi: Int
    var lastSeen: Date
}

// MARK: - CBCentralManager Protocol (for testability)

/// Abstracts CBCentralManager so tests can inject a mock.
protocol CBCentralManagerProtocol: AnyObject {
    var state: CBManagerState { get }
    func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]?)
    func stopScan()
}

extension CBCentralManager: CBCentralManagerProtocol {}

// MARK: - High-Level BLE Central Protocol

/// Manages BLE scanning and RSSI tracking for the user-selected device.
protocol BLECentralManaging: AnyObject {
    var selectedDeviceName: String? { get set }
}

// MARK: - UnlockManager Protocol

/// Allows MockUnlockManager to be injected in tests.
protocol UnlockManaging {
    func isScreenLocked() -> Bool
    func unlockScreen()
    func lockScreen()
}

extension UnlockManager: UnlockManaging {}
