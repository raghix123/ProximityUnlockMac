import CoreBluetooth
import Foundation

/// Manages the iOS BLE peripheral.
///
/// M7+: BLE is RSSI-only. The iPhone advertises its service UUID so the Mac can
/// discover it and read signal strength for proximity detection. All commands
/// (unlock_request, lock_event, confirmations) travel over MultipeerConnectivity.
/// There are no GATT characteristics — this peripheral is advertisement-only.
class BLEPeripheralManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var bluetoothState: CBManagerState = .unknown
    @Published var isAdvertising: Bool = false

    // MARK: - Private

    private var peripheralManager: (any CBPeripheralManagerProtocol)!

    // MARK: - Init

    /// Production init — creates a real CBPeripheralManager with state restoration.
    convenience override init() {
        self.init(peripheralManager: nil)
        let real = CBPeripheralManager(
            delegate: self,
            queue: nil,
            options: [CBPeripheralManagerOptionRestoreIdentifierKey: "com.raghav.ProximityUnlock.peripheral"]
        )
        self.peripheralManager = real
    }

    /// Testable init — accepts an injectable CBPeripheralManagerProtocol.
    init(peripheralManager: (any CBPeripheralManagerProtocol)?) {
        super.init()
        self.peripheralManager = peripheralManager
    }

    // MARK: - Public API

    func startAdvertising() {
        Log.ble.info("Starting BLE advertising (RSSI beacon)")
        guard peripheralManager?.state == .poweredOn else { return }
        guard !isAdvertising else { return }
        // No characteristics — advertisement-only service for RSSI proximity sensing
        let service = CBMutableService(type: BLEConstants.serviceUUID, primary: true)
        peripheralManager?.add(service)
        peripheralManager?.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BLEConstants.serviceUUID],
            CBAdvertisementDataLocalNameKey: "ProximityUnlock"
        ])
    }

    func stopAdvertising() {
        Log.ble.info("Stopping BLE advertising")
        peripheralManager?.stopAdvertising()
        peripheralManager?.removeAllServices()
        isAdvertising = false
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BLEPeripheralManager: CBPeripheralManagerDelegate {

    func peripheralManager(_ peripheral: CBPeripheralManager, willRestoreState dict: [String: Any]) {
        Log.ble.info("Restoring peripheral manager state after background termination")
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        Log.ble.info("Peripheral manager state: \(String(describing: peripheral.state.rawValue), privacy: .public)")
        bluetoothState = peripheral.state
        if peripheral.state == .poweredOn {
            startAdvertising()
        } else {
            isAdvertising = false
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
}
