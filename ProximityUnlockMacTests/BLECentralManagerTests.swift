import XCTest
import CoreBluetooth
@testable import ProximityUnlockMac

/// Tests for BLECentralManager (RSSI-only, M7+).
/// BLE no longer handles commands — only scanning, connection for RSSI polling,
/// and device found/lost events. All commands flow over MPC.
final class BLECentralManagerTests: XCTestCase {

    private var mockCentral: MockCBCentralManager!
    private var bleManager: BLECentralManager!

    // Callback recording
    private var rssiUpdates: [Int] = []
    private var deviceFoundCount = 0
    private var deviceLostCount = 0

    override func setUp() {
        mockCentral = MockCBCentralManager()
        mockCentral.state = .poweredOn

        bleManager = BLECentralManager(
            centralManager: mockCentral,
            onRSSIUpdate: { [unowned self] rssi in
                self.rssiUpdates.append(rssi)
            },
            onDeviceFound: { [unowned self] in
                self.deviceFoundCount += 1
            },
            onDeviceLost: { [unowned self] in
                self.deviceLostCount += 1
            }
        )
    }

    override func tearDown() {
        bleManager = nil
        mockCentral = nil
        rssiUpdates.removeAll()
        deviceFoundCount = 0
        deviceLostCount = 0
    }

    // MARK: - Init & Wiring

    func testInitAcceptsInjectedMockCentral() {
        XCTAssertNotNil(bleManager)
    }

    func testCallbackClosuresAreStored() {
        bleManager.onRSSIUpdate(-65)
        XCTAssertEqual(rssiUpdates, [-65])

        bleManager.onDeviceFound()
        XCTAssertEqual(deviceFoundCount, 1)

        bleManager.onDeviceLost()
        XCTAssertEqual(deviceLostCount, 1)
    }

    func testMultipleRSSIUpdates() {
        bleManager.onRSSIUpdate(-50)
        bleManager.onRSSIUpdate(-60)
        bleManager.onRSSIUpdate(-70)
        XCTAssertEqual(rssiUpdates, [-50, -60, -70])
    }

    // MARK: - Mock Central State

    func testMockCentralTracksState() {
        mockCentral.state = .poweredOff
        XCTAssertEqual(mockCentral.state, .poweredOff)

        mockCentral.state = .poweredOn
        XCTAssertEqual(mockCentral.state, .poweredOn)
    }

    func testMockCentralRecordsScanCalls() {
        mockCentral.reset()
        // Scan with nil — discovers all devices (no service UUID filter).
        mockCentral.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        XCTAssertTrue(mockCentral.scanForPeripheralsCalled)
        XCTAssertNil(mockCentral.scanServiceUUIDs)
    }

    func testMockCentralRecordsStopScan() {
        mockCentral.reset()
        mockCentral.stopScan()
        XCTAssertTrue(mockCentral.stopScanCalled)
    }

    func testMockCentralReset() {
        mockCentral.scanForPeripherals(withServices: nil, options: nil)
        mockCentral.stopScan()
        XCTAssertTrue(mockCentral.scanForPeripheralsCalled)
        XCTAssertTrue(mockCentral.stopScanCalled)

        mockCentral.reset()
        XCTAssertFalse(mockCentral.scanForPeripheralsCalled)
        XCTAssertFalse(mockCentral.stopScanCalled)
        XCTAssertFalse(mockCentral.connectCalled)
        XCTAssertFalse(mockCentral.cancelPeripheralConnectionCalled)
    }

    // MARK: - Disconnect Handling

    func testNoDeviceLostBeforeDisconnect() {
        XCTAssertEqual(deviceLostCount, 0)
    }

    func testNoRSSIBeforeDiscovery() {
        XCTAssertTrue(rssiUpdates.isEmpty)
    }
}
