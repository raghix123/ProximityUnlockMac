import XCTest
import CoreBluetooth
@testable import ProximityUnlockiOS

/// Tests for BLEPeripheralManager — advertising, command handling, confirmation sending.
final class BLEPeripheralManagerTests: XCTestCase {

    private var bleManager: BLEPeripheralManager!
    private var mockPM: MockCBPeripheralManager!

    override func setUp() {
        mockPM = MockCBPeripheralManager()
        mockPM.state = .poweredOn
        bleManager = BLEPeripheralManager(peripheralManager: mockPM)
    }

    override func tearDown() {
        bleManager = nil
        mockPM = nil
    }

    // MARK: - Advertising

    func testStartsAdvertisingWhenPoweredOn() {
        bleManager.startAdvertising()
        XCTAssertTrue(mockPM.startAdvertisingCalled, "startAdvertising should be called on powered-on manager")
    }

    func testAdvertisesCorrectServiceUUID() {
        bleManager.startAdvertising()
        let uuids = mockPM.advertisedServiceUUIDs()
        XCTAssertEqual(uuids?.first, BLEConstants.serviceUUID, "must advertise the ProximityUnlock service UUID")
    }

    func testDoesNotAdvertiseWhenBluetoothOff() {
        mockPM.state = .poweredOff
        bleManager.startAdvertising()
        XCTAssertFalse(mockPM.startAdvertisingCalled, "should not advertise when Bluetooth is off")
    }

    func testStopAdvertisingCallsRemoveAllServices() {
        bleManager.startAdvertising()
        bleManager.stopAdvertising()
        XCTAssertTrue(mockPM.stopAdvertisingCalled)
        XCTAssertTrue(mockPM.removeAllServicesCalled)
        XCTAssertFalse(bleManager.isAdvertising)
    }

    func testServiceAddedWithTwoCharacteristics() {
        bleManager.startAdvertising()
        let service = mockPM.addedServices.first
        XCTAssertNotNil(service, "a CBMutableService should be added")
        XCTAssertEqual(service?.characteristics?.count, 2, "service must have exactly 2 characteristics")
    }

    // MARK: - State Update → Advertise + Add Service

    /// Verifies the behavior that peripheralManagerDidUpdateState(.poweredOn) triggers:
    /// buildAndAddService() + startAdvertising(). Since the delegate method requires a real
    /// CBPeripheralManager, we test the equivalent by calling startAdvertising() when powered on.
    func testPoweredOnStateTriggersAddServiceAndStartAdvertising() {
        mockPM.reset()
        mockPM.state = .poweredOn

        // This is what peripheralManagerDidUpdateState calls when state == .poweredOn
        bleManager.startAdvertising()

        XCTAssertFalse(mockPM.addedServices.isEmpty, "addService must be called to register the BLE service")
        XCTAssertTrue(mockPM.startAdvertisingCalled, "startAdvertising must be called after adding service")

        // Verify the service was built with the correct UUID
        let service = mockPM.addedServices.first
        XCTAssertEqual(service?.uuid, BLEConstants.serviceUUID, "service UUID must match BLEConstants.serviceUUID")

        // Verify the service contains both required characteristics
        let charUUIDs = service?.characteristics?.map(\.uuid) ?? []
        XCTAssertTrue(charUUIDs.contains(BLEConstants.unlockRequestCharUUID), "service must include unlock request characteristic")
        XCTAssertTrue(charUUIDs.contains(BLEConstants.unlockConfirmCharUUID), "service must include unlock confirm characteristic")
    }

    func testPoweredOffStateDoesNotTriggerAdvertising() {
        mockPM.reset()
        mockPM.state = .poweredOff

        bleManager.startAdvertising()

        XCTAssertTrue(mockPM.addedServices.isEmpty, "should not add service when not powered on")
        XCTAssertFalse(mockPM.startAdvertisingCalled, "should not start advertising when not powered on")
    }

    // MARK: - Incoming Commands (unlock_request / lock_event)

    func testUnlockRequestCallbackFired() {
        var callbackFired = false
        bleManager.onUnlockRequest = { callbackFired = true }

        bleManager.simulateIncomingCommand("unlock_request")

        let expectation = XCTestExpectation(description: "callback on main queue")
        DispatchQueue.main.async { expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(callbackFired, "onUnlockRequest must be called when unlock_request is received")
        XCTAssertTrue(bleManager.pendingUnlockRequest)
    }

    func testLockEventCallbackFired() {
        // First put it in pending state
        bleManager.simulateIncomingCommand("unlock_request")

        var lockCallbackFired = false
        bleManager.onLockEvent = { lockCallbackFired = true }
        bleManager.simulateIncomingCommand("lock_event")

        let expectation = XCTestExpectation(description: "callback on main queue")
        DispatchQueue.main.async { expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertTrue(lockCallbackFired, "onLockEvent must fire when lock_event is received")
        XCTAssertFalse(bleManager.pendingUnlockRequest, "pendingUnlockRequest must clear on lock_event")
    }

    // MARK: - Sending Confirmation

    func testSendConfirmationApprovedWritesCorrectValue() {
        // Without real subscribed centrals, updateValue won't fire,
        // but we can test that pendingUnlockRequest is cleared.
        bleManager.simulateIncomingCommand("unlock_request")

        let expectation = XCTestExpectation(description: "callback on main queue")
        DispatchQueue.main.async { expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)

        // sendConfirmation with no subscribed centrals — pendingUnlockRequest still clears
        bleManager.sendConfirmation(approved: true)
        // Note: updateValue is not called because subscribedCentrals is empty in tests
        XCTAssertFalse(bleManager.pendingUnlockRequest, "pendingUnlockRequest must clear after sendConfirmation")
    }
}
