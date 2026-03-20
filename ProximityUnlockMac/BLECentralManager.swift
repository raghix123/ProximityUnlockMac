import CoreBluetooth
import Foundation

/// The service UUID that the iPhone app will advertise.
/// Both the Mac and iPhone apps must use this exact UUID.
enum BLEConstants {
    static let serviceUUID            = CBUUID(string: "5F0A4A6E-9DC4-4C57-9A8C-D8BF0B1B0FDE")
    /// Mac writes "unlock_request" / "lock_event" to this; iPhone is notified.
    static let unlockRequestCharUUID  = CBUUID(string: "A3F1E2D4-5B6C-7A8E-9F0D-1B2C3E4F5A6B")
    /// iPhone writes "approved" / "denied" to this; Mac is notified.
    static let unlockConfirmCharUUID  = CBUUID(string: "B4E2F3C5-6D7E-8B9F-0A1C-2D3E4F5B6C7A")
}

/// Manages CoreBluetooth scanning, RSSI polling, and the unlock-confirmation handshake.
class BLECentralManager: NSObject {
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rssiTimer: Timer?
    private var lostTimer: Timer?

    /// Characteristic used to send unlock/lock commands to the iPhone.
    private var requestChar: CBCharacteristic?
    /// Characteristic used to receive confirm/deny responses from the iPhone.
    private var confirmChar: CBCharacteristic?

    // MARK: - Callbacks

    let onRSSIUpdate:          (Int) -> Void
    let onDeviceFound:         () -> Void
    let onDeviceLost:          () -> Void
    /// Called when the iPhone responds with "approved" or "denied".
    let onConfirmationReceived: (Bool) -> Void

    // MARK: - Init

    init(
        onRSSIUpdate:           @escaping (Int) -> Void,
        onDeviceFound:          @escaping () -> Void,
        onDeviceLost:           @escaping () -> Void,
        onConfirmationReceived: @escaping (Bool) -> Void
    ) {
        self.onRSSIUpdate           = onRSSIUpdate
        self.onDeviceFound          = onDeviceFound
        self.onDeviceLost           = onDeviceLost
        self.onConfirmationReceived = onConfirmationReceived
        super.init()
        // nil queue → uses the main queue, keeping delegate calls on main thread.
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Scanning / RSSI

    private func startScanning() {
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(
            withServices: [BLEConstants.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func startRSSIPolling() {
        rssiTimer?.invalidate()
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.peripheral?.readRSSI()
        }
        peripheral?.readRSSI()
    }

    private func stopRSSIPolling() {
        rssiTimer?.invalidate()
        rssiTimer = nil
        lostTimer?.invalidate()
        lostTimer = nil
    }

    private func resetLostTimer() {
        lostTimer?.invalidate()
        lostTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            guard let self, let p = self.peripheral else { return }
            self.central.cancelPeripheralConnection(p)
        }
    }

    // MARK: - Characteristics

    /// Send a command string to the iPhone via the unlock-request characteristic.
    func writeCommand(_ command: String) {
        guard let peripheral, let char = requestChar else { return }
        let data = Data(command.utf8)
        peripheral.writeValue(data, for: char, type: .withResponse)
    }

    /// Subscribe to confirmation notifications from the iPhone.
    private func subscribeToConfirmations() {
        guard let peripheral, let char = confirmChar else { return }
        peripheral.setNotifyValue(true, for: char)
    }
}

// MARK: - CBCentralManagerDelegate

extension BLECentralManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard self.peripheral == nil else { return }
        self.peripheral = peripheral
        self.peripheral?.delegate = self
        central.stopScan()
        central.connect(peripheral, options: nil)
        onDeviceFound()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Discover our service to find the confirmation characteristics.
        peripheral.discoverServices([BLEConstants.serviceUUID])
        startRSSIPolling()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        stopRSSIPolling()
        requestChar = nil
        confirmChar = nil
        self.peripheral = nil
        onDeviceLost()
        startScanning()
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        self.peripheral = nil
        startScanning()
    }
}

// MARK: - CBPeripheralDelegate

extension BLECentralManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else { return }
        resetLostTimer()
        onRSSIUpdate(RSSI.intValue)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == BLEConstants.serviceUUID })
        else { return }
        peripheral.discoverCharacteristics(
            [BLEConstants.unlockRequestCharUUID, BLEConstants.unlockConfirmCharUUID],
            for: service
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil else { return }
        for char in service.characteristics ?? [] {
            switch char.uuid {
            case BLEConstants.unlockRequestCharUUID:
                requestChar = char
            case BLEConstants.unlockConfirmCharUUID:
                confirmChar = char
                subscribeToConfirmations()
            default:
                break
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == BLEConstants.unlockConfirmCharUUID,
              error == nil,
              let data = characteristic.value,
              let message = String(data: data, encoding: .utf8)
        else { return }

        let approved = (message == "approved")
        onConfirmationReceived(approved)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        // Subscription to confirmChar established — ready to receive responses.
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        // Optionally handle write acknowledgements here.
    }
}
