import CoreBluetooth
import Foundation

/// Manages the iOS side of the BLE connection.
/// Advertises the ProximityUnlock service UUID so the Mac can discover and connect.
/// Also handles the unlock confirmation characteristic handshake.
class BLEPeripheralManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var bluetoothState: CBManagerState = .unknown
    @Published var isAdvertising: Bool = false
    @Published var isConnected: Bool = false
    @Published var pendingUnlockRequest: Bool = false

    // MARK: - Private

    private var peripheralManager: (any CBPeripheralManagerProtocol)!
    private var requestChar: CBMutableCharacteristic!
    private var confirmChar: CBMutableCharacteristic!
    private var subscribedCentrals: [CBCentral] = []

    /// Called when the Mac sends an unlock request; iOS app should confirm/deny.
    var onUnlockRequest: (() -> Void)?
    /// Called when Mac notifies that the screen was locked.
    var onLockEvent: (() -> Void)?

    // MARK: - Init

    /// Production init — creates a real CBPeripheralManager.
    convenience override init() {
        self.init(peripheralManager: nil)
        // Phase 2: self is ready, create real manager that calls back to delegate
        let real = CBPeripheralManager(delegate: self, queue: nil)
        self.peripheralManager = real
    }

    /// Testable init — accepts an injectable CBPeripheralManagerProtocol.
    init(peripheralManager: (any CBPeripheralManagerProtocol)?) {
        super.init()
        self.peripheralManager = peripheralManager
    }

    // MARK: - Public API

    func startAdvertising() {
        Log.ble.info("Starting BLE advertising")
        guard peripheralManager?.state == .poweredOn else { return }
        buildAndAddService()
        peripheralManager?.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BLEConstants.serviceUUID],
            CBAdvertisementDataLocalNameKey: "ProximityUnlock"
        ])
    }

    func stopAdvertising() {
        Log.ble.info("Stopping BLE advertising")
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()
        subscribedCentrals.removeAll()
        isAdvertising = false
    }

    /// Send confirmation response ("approved" or "denied") back to connected Mac.
    func sendConfirmation(approved: Bool) {
        guard !subscribedCentrals.isEmpty, let char = confirmChar else { return }
        let value = approved ? "approved" : "denied"
        Log.ble.info("Sending confirmation: \(value, privacy: .public) to \(self.subscribedCentrals.count, privacy: .public) subscriber(s)")
        let data = Data(value.utf8)
        peripheralManager?.updateValue(data, for: char, onSubscribedCentrals: subscribedCentrals)
        pendingUnlockRequest = false
    }

    // MARK: - Private Helpers

    private func buildAndAddService() {
        requestChar = CBMutableCharacteristic(
            type: BLEConstants.unlockRequestCharUUID,
            properties: [.write, .notify],
            value: nil,
            permissions: [.writeable]
        )
        confirmChar = CBMutableCharacteristic(
            type: BLEConstants.unlockConfirmCharUUID,
            properties: [.write, .notify],
            value: nil,
            permissions: [.writeable]
        )
        let service = CBMutableService(type: BLEConstants.serviceUUID, primary: true)
        service.characteristics = [requestChar, confirmChar]
        peripheralManager?.add(service)
    }

    // MARK: - Test Helpers

    /// Called by tests to simulate the Mac writing a command to the request characteristic.
    func simulateIncomingCommand(_ command: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch command {
            case "unlock_request":
                self.pendingUnlockRequest = true
                self.onUnlockRequest?()
            case "lock_event":
                self.pendingUnlockRequest = false
                self.onLockEvent?()
            default:
                break
            }
        }
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BLEPeripheralManager: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        Log.ble.info("Peripheral manager state: \(String(describing: peripheral.state.rawValue), privacy: .public)")
        bluetoothState = peripheral.state
        if peripheral.state == .poweredOn {
            startAdvertising()
        } else {
            isAdvertising = false
            isConnected = false
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error {
            Log.ble.error("Failed to start advertising: \(error.localizedDescription, privacy: .public)")
        } else {
            Log.ble.info("Started advertising successfully")
        }
        isAdvertising = error == nil
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        Log.ble.info("Central subscribed: \(central.identifier.uuidString, privacy: .public)")
        if characteristic.uuid == BLEConstants.unlockConfirmCharUUID {
            if !subscribedCentrals.contains(where: { $0.identifier == central.identifier }) {
                subscribedCentrals.append(central)
            }
            isConnected = true
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        Log.ble.info("Central unsubscribed: \(central.identifier.uuidString, privacy: .public)")
        subscribedCentrals.removeAll { $0.identifier == central.identifier }
        if subscribedCentrals.isEmpty {
            isConnected = false
            pendingUnlockRequest = false
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard let data = request.value,
                  let message = String(data: data, encoding: .utf8) else {
                peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
                continue
            }

            Log.ble.info("Received write command: \(message, privacy: .public)")
            peripheral.respond(to: request, withResult: .success)

            if request.characteristic.uuid == BLEConstants.unlockRequestCharUUID {
                simulateIncomingCommand(message)
            }
        }
    }
}

