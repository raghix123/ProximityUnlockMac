import CoreBluetooth
import Foundation

/// The service UUID that the iPhone app will advertise.
/// Both the Mac and iPhone apps must use this exact UUID.
enum BLEConstants {
    static let serviceUUID = CBUUID(string: "5F0A4A6E-9DC4-4C57-9A8C-D8BF0B1B0FDE")
}

/// Manages CoreBluetooth scanning and RSSI polling for the paired iPhone.
class BLECentralManager: NSObject {
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rssiTimer: Timer?
    private var lostTimer: Timer?

    // Callbacks arrive on the queue passed to CBCentralManager (default queue).
    // ProximityMonitor wraps them in Task { @MainActor } before mutating state.
    let onRSSIUpdate: (Int) -> Void
    let onDeviceFound: () -> Void
    let onDeviceLost: () -> Void

    init(
        onRSSIUpdate: @escaping (Int) -> Void,
        onDeviceFound: @escaping () -> Void,
        onDeviceLost: @escaping () -> Void
    ) {
        self.onRSSIUpdate = onRSSIUpdate
        self.onDeviceFound = onDeviceFound
        self.onDeviceLost = onDeviceLost
        super.init()
        // nil queue → uses the main queue, keeping delegate calls on main thread.
        central = CBCentralManager(delegate: self, queue: nil)
    }

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
        // If no RSSI update arrives for 10 seconds, treat the device as lost.
        lostTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            guard let self, let p = self.peripheral else { return }
            self.central.cancelPeripheralConnection(p)
        }
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
        startRSSIPolling()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        stopRSSIPolling()
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
}
