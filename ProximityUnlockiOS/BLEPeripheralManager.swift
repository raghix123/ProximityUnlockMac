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

    private var peripheralManager: CBPeripheralManager!
    private var requestChar: CBMutableCharacteristic!
    private var confirmChar: CBMutableCharacteristic!
    private var subscribedCentrals: [CBCentral] = []

    /// Called when the Mac sends an unlock request; iOS app should confirm/deny.
    var onUnlockRequest: (() -> Void)?
    /// Called when Mac notifies that the screen was locked.
    var onLockEvent: (() -> Void)?

    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    }

    // MARK: - Public API

    func startAdvertising() {
        guard peripheralManager.state == .poweredOn else { return }
        buildAndAddService()
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BLEConstants.serviceUUID],
            CBAdvertisementDataLocalNameKey: "ProximityUnlock"
        ])
    }

    func stopAdvertising() {
        peripheralManager.stopAdvertising()
        peripheralManager.removeAllServices()
        subscribedCentrals.removeAll()
        isAdvertising = false
    }

    /// Send confirmation response ("approved" or "denied") back to connected Mac.
    func sendConfirmation(approved: Bool) {
        guard !subscribedCentrals.isEmpty else { return }
        let value = approved ? "approved" : "denied"
        let data = Data(value.utf8)
        peripheralManager.updateValue(data, for: confirmChar, onSubscribedCentrals: subscribedCentrals)
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
        peripheralManager.add(service)
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BLEPeripheralManager: CBPeripheralManagerDelegate {

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        bluetoothState = peripheral.state
        if peripheral.state == .poweredOn {
            startAdvertising()
        } else {
            isAdvertising = false
            isConnected = false
        }
    }

    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        isAdvertising = error == nil
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        if characteristic.uuid == BLEConstants.unlockConfirmCharUUID {
            if !subscribedCentrals.contains(where: { $0.identifier == central.identifier }) {
                subscribedCentrals.append(central)
            }
            isConnected = true
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
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
                peripheral.respond(to: request, withResult: .invalidAttributeLength)
                continue
            }

            peripheral.respond(to: request, withResult: .success)

            if request.characteristic.uuid == BLEConstants.unlockRequestCharUUID {
                DispatchQueue.main.async { [weak self] in
                    switch message {
                    case "unlock_request":
                        self?.pendingUnlockRequest = true
                        self?.onUnlockRequest?()
                    case "lock_event":
                        self?.pendingUnlockRequest = false
                        self?.onLockEvent?()
                    default:
                        break
                    }
                }
            }
        }
    }
}
