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
            UserDefaults.standard.set(isEnabled, forKey: "isEnabled")
            isEnabled ? bleManager.startAdvertising() : bleManager.stopAdvertising()
        }
    }

    @Published var requiresConfirmation: Bool = true {
        didSet { confirmationManager.requiresConfirmation = requiresConfirmation }
    }

    // MARK: - Sub-managers

    let bleManager: BLEPeripheralManager
    let confirmationManager: UnlockConfirmationManager

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

        // Forward BLE state to published properties
        ble.$bluetoothState.assign(to: &$bluetoothState)
        ble.$isAdvertising.assign(to: &$isAdvertising)
        ble.$isConnected.assign(to: &$isConnected)
        ble.$pendingUnlockRequest.assign(to: &$pendingUnlockRequest)

        // Request notification permission on first launch
        confirmationManager.requestNotificationPermission()
    }

    // MARK: - Public API

    func approve() { confirmationManager.approve() }
    func deny()    { confirmationManager.deny() }

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
