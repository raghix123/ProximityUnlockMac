import CoreBluetooth
import Foundation
import AppKit
import os

/// Scans all nearby Bluetooth devices continuously.
/// Reports RSSI only for the user-selected device.
/// Uses advertisement RSSI directly — no BLE connection required.
class BLECentralManager: NSObject, BLECentralManaging {

    private static let staleDeviceTimeout: TimeInterval = 15
    private static let pruneInterval: TimeInterval = 5

    private var central: CBCentralManagerProtocol!
    private var pruneTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    // MARK: - Device list

    private var devicesByName: [String: DiscoveredDevice] = [:]
    private var isSelectedDeviceActive = false

    /// Called whenever the set of discovered devices changes (new device or stale removed).
    var onDiscoveredDevicesChanged: (([DiscoveredDevice]) -> Void)?

    /// Called when the underlying CBManager state changes (on/off/unauthorized/etc.)
    /// so the UI can tell the user to enable Bluetooth or grant permission.
    var onStateChange: ((CBManagerState) -> Void)?

    // MARK: - Selection (in-memory; ProximityMonitor owns UserDefaults persistence)

    private var _selectedDeviceName: String?

    var selectedDeviceName: String? {
        get { _selectedDeviceName }
        set {
            _selectedDeviceName = newValue
            updateSelectedDeviceState()
        }
    }

    // MARK: - Callbacks

    let onRSSIUpdate:  (Int) -> Void
    let onDeviceFound: () -> Void
    let onDeviceLost:  () -> Void

    // MARK: - Init

    convenience init(
        onRSSIUpdate:  @escaping (Int) -> Void,
        onDeviceFound: @escaping () -> Void,
        onDeviceLost:  @escaping () -> Void
    ) {
        self.init(
            centralManager: nil,
            onRSSIUpdate: onRSSIUpdate,
            onDeviceFound: onDeviceFound,
            onDeviceLost: onDeviceLost
        )
    }

    init(
        centralManager: CBCentralManagerProtocol?,
        onRSSIUpdate:  @escaping (Int) -> Void,
        onDeviceFound: @escaping () -> Void,
        onDeviceLost:  @escaping () -> Void
    ) {
        self.onRSSIUpdate  = onRSSIUpdate
        self.onDeviceFound = onDeviceFound
        self.onDeviceLost  = onDeviceLost
        super.init()

        if let existing = centralManager {
            self.central = existing
        } else {
            self.central = CBCentralManager(delegate: self, queue: nil)
        }

        pruneTimer = Timer.scheduledTimer(withTimeInterval: Self.pruneInterval, repeats: true) { [weak self] _ in
            self?.pruneStaleDevices()
        }

        // NSWorkspace notifications only post to NSWorkspace.shared.notificationCenter,
        // not the default center.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.startScanning()
        }
    }

    deinit {
        pruneTimer?.invalidate()
        if let obs = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }

    // MARK: - Internal

    private func startScanning() {
        guard central.state == .poweredOn else { return }
        // nil = discover all devices. allowDuplicates gives continuous RSSI updates.
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    private func updateSelectedDeviceState() {
        guard let name = _selectedDeviceName else {
            if isSelectedDeviceActive {
                isSelectedDeviceActive = false
                onDeviceLost()
            }
            return
        }
        if let device = devicesByName[name] {
            if !isSelectedDeviceActive {
                isSelectedDeviceActive = true
                onDeviceFound()
            }
            onRSSIUpdate(device.rssi)
        } else {
            if isSelectedDeviceActive {
                isSelectedDeviceActive = false
                onDeviceLost()
            }
        }
    }

    private func pruneStaleDevices() {
        let cutoff = Date().addingTimeInterval(-Self.staleDeviceTimeout)
        let staleNames = devicesByName.filter { $0.value.lastSeen < cutoff }.map { $0.key }
        guard !staleNames.isEmpty else { return }
        for name in staleNames { devicesByName.removeValue(forKey: name) }
        let sorted = Array(devicesByName.values).sorted { $0.name < $1.name }
        onDiscoveredDevicesChanged?(sorted)

        if let selected = _selectedDeviceName, staleNames.contains(selected), isSelectedDeviceActive {
            isSelectedDeviceActive = false
            onDeviceLost()
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLECentralManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Log.ble.info("Central manager state: \(String(describing: central.state.rawValue), privacy: .public)")
        onStateChange?(central.state)
        if central.state == .poweredOn {
            startScanning()
        } else {
            // Radio off / unauthorized / resetting — discovered devices are no longer valid.
            // Clear the list and tell ProximityMonitor the selected device is gone, otherwise
            // the status bar UI would falsely report "nearby" until the 15-second prune.
            if !devicesByName.isEmpty {
                devicesByName.removeAll()
                onDiscoveredDevicesChanged?([])
            }
            if isSelectedDeviceActive {
                isSelectedDeviceActive = false
                onDeviceLost()
            }
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let rssiValue = RSSI.intValue
        guard rssiValue < 0 else { return }
        guard let name = peripheral.name, !name.isEmpty else { return }

        let isNew = devicesByName[name] == nil
        var device = devicesByName[name] ?? DiscoveredDevice(
            id: peripheral.identifier,
            name: name,
            rssi: rssiValue,
            lastSeen: Date()
        )
        device.rssi = rssiValue
        device.lastSeen = Date()
        devicesByName[name] = device

        if isNew {
            let sorted = Array(devicesByName.values).sorted { $0.name < $1.name }
            onDiscoveredDevicesChanged?(sorted)
            Log.ble.info("Discovered new device: \(name, privacy: .public) RSSI=\(rssiValue, privacy: .public)")
        }

        guard name == _selectedDeviceName else { return }

        if !isSelectedDeviceActive {
            Log.ble.info("Selected device found: \(name, privacy: .public) RSSI=\(rssiValue, privacy: .public)")
            isSelectedDeviceActive = true
            onDeviceFound()
        }
        onRSSIUpdate(rssiValue)
    }
}
