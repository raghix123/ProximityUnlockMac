import Foundation
@testable import ProximityUnlockMac

/// Mock BLE central manager for unit tests.
/// Satisfies BLECentralManaging so ProximityMonitor can be tested without real BLE.
class MockBLECentralManager: BLECentralManaging {
    var selectedDeviceName: String?
}
