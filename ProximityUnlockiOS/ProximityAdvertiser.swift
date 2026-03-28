import Foundation
import CoreBluetooth
import UIKit

/// Top-level state coordinator for the iOS app.
/// Owns the BLE peripheral manager and confirmation manager, and exposes
/// a unified interface to SwiftUI views.
@MainActor
class ProximityAdvertiser: ObservableObject {

    // MARK: - Published State (proxied from sub-managers)

    @Published var bluetoothState: CBManagerState = .unknown
    @Published var isAdvertising: Bool = false
    @Published var isConnected: Bool = false
    @Published var pendingUnlockRequest: Bool = false

    @Published var isEnabled: Bool = true {
        didSet {
            Log.ui.info("isEnabled changed to \(self.isEnabled, privacy: .public)")
            UserDefaults.standard.set(isEnabled, forKey: "isEnabled")
            isEnabled ? bleManager.startAdvertising() : bleManager.stopAdvertising()
            isEnabled ? multipeerManager.startAdvertising() : multipeerManager.stopAdvertising()
        }
    }

    @Published var requiresConfirmation: Bool = true {
        didSet { confirmationManager.requiresConfirmation = requiresConfirmation }
    }

    // MARK: - Sub-managers

    let bleManager: BLEPeripheralManager
    let confirmationManager: UnlockConfirmationManager

    /// MultipeerConnectivity channel — uses WiFi Direct / WiFi / Bluetooth automatically,
    /// giving much more reliable message delivery than raw BLE GATT.
    let multipeerManager = MultipeerManager()

    // MARK: - Init

    init() {
        let ble = BLEPeripheralManager()
        bleManager = ble
        confirmationManager = UnlockConfirmationManager(bleManager: ble)

        // Restore persisted settings
        if UserDefaults.standard.object(forKey: "isEnabled") != nil {
            isEnabled = UserDefaults.standard.bool(forKey: "isEnabled")
        }
        requiresConfirmation = confirmationManager.requiresConfirmation
        Log.ui.info("Init: isEnabled=\(self.isEnabled, privacy: .public), requiresConfirmation=\(self.requiresConfirmation, privacy: .public)")

        // Forward BLE state to published properties
        ble.$bluetoothState.assign(to: &$bluetoothState)
        ble.$isAdvertising.assign(to: &$isAdvertising)
        ble.$isConnected.assign(to: &$isConnected)
        ble.$pendingUnlockRequest.assign(to: &$pendingUnlockRequest)

        // Request notification permission on first launch
        confirmationManager.requestNotificationPermission()

        // Wire MPC commands to the same handlers as BLE — whichever channel wins first.
        multipeerManager.onUnlockRequest = { [weak self] in
            Task { @MainActor [weak self] in self?.confirmationManager.receiveUnlockRequest() }
        }
        multipeerManager.onLockEvent = { [weak self] in
            Task { @MainActor [weak self] in self?.confirmationManager.receiveLockEvent() }
        }

        // When a confirmation is sent (user taps or auto-approve), also send via MPC
        // so the Mac receives it over WiFi, not just BLE GATT.
        confirmationManager.onConfirmationSent = { [weak self] approved in
            self?.multipeerManager.sendConfirmation(approved: approved)
        }

        if isEnabled { multipeerManager.startAdvertising() }
    }

    // MARK: - Public API

    func approve() {
        Log.proximity.info("User approved unlock")
        // confirmationManager.approve() sends via BLE and fires onConfirmationSent → MPC
        confirmationManager.approve()
    }

    func deny() {
        Log.proximity.info("User denied unlock")
        // confirmationManager.deny() sends via BLE and fires onConfirmationSent → MPC
        confirmationManager.deny()
    }

    func lockMac() {
        Log.proximity.info("Sending lock command")
        multipeerManager.sendMessage("lock_command")
    }

    func unlockMac() {
        Log.proximity.info("Sending unlock command")
        multipeerManager.sendMessage("unlock_command")
    }

    var bluetoothStatusDescription: String {
        switch bluetoothState {
        case .poweredOn:     return isAdvertising ? (isConnected ? "Connected to Mac" : "Advertising...") : "Stopped"
        case .poweredOff:    return "Bluetooth Off"
        case .unauthorized:  return "Permission Denied"
        case .unsupported:   return "BLE Not Supported"
        case .resetting:     return "Resetting..."
        case .unknown:       return "Initializing..."
        @unknown default:    return "Unknown"
        }
    }
}
