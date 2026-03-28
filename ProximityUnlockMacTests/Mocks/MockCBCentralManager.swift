import CoreBluetooth
import Foundation
@testable import ProximityUnlockMac

/// Mock CBCentralManager for unit tests.
/// Implements CBCentralManagerProtocol so it can be injected into BLECentralManager.
/// Records all scan/connect/disconnect calls and allows controllable Bluetooth state.
class MockCBCentralManager: CBCentralManagerProtocol {

    // MARK: - Controllable State

    var state: CBManagerState = .poweredOff

    // MARK: - Recording

    private(set) var scanForPeripheralsCalled = false
    private(set) var scanServiceUUIDs: [CBUUID]?
    private(set) var scanOptions: [String: Any]?

    private(set) var stopScanCalled = false

    private(set) var connectCalled = false
    private(set) var connectedPeripheral: CBPeripheral?

    private(set) var cancelPeripheralConnectionCalled = false
    private(set) var cancelledPeripheral: CBPeripheral?

    // MARK: - CBCentralManagerProtocol

    func scanForPeripherals(withServices serviceUUIDs: [CBUUID]?, options: [String: Any]?) {
        scanForPeripheralsCalled = true
        scanServiceUUIDs = serviceUUIDs
        scanOptions = options
    }

    func stopScan() {
        stopScanCalled = true
    }

    func connect(_ peripheral: CBPeripheral, options: [String: Any]?) {
        connectCalled = true
        connectedPeripheral = peripheral
    }

    func cancelPeripheralConnection(_ peripheral: CBPeripheral) {
        cancelPeripheralConnectionCalled = true
        cancelledPeripheral = peripheral
    }

    // MARK: - Helpers

    func reset() {
        scanForPeripheralsCalled = false
        scanServiceUUIDs = nil
        scanOptions = nil
        stopScanCalled = false
        connectCalled = false
        connectedPeripheral = nil
        cancelPeripheralConnectionCalled = false
        cancelledPeripheral = nil
    }
}
