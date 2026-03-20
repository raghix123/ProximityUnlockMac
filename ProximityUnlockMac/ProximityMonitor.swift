import Foundation
import Combine

enum ProximityState {
    case near, far, unknown
}

/// Coordinates BLE scanning, proximity state, and lock/unlock actions.
@MainActor
class ProximityMonitor: ObservableObject {
    @Published var proximityState: ProximityState = .unknown
    @Published var rssi: Int = -100
    @Published var isPhoneDetected: Bool = false
    @Published var isEnabled: Bool = true {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "isEnabled") }
    }

    // RSSI thresholds (dBm). More negative = farther away.
    @Published var nearThreshold: Int = -70 {
        didSet { UserDefaults.standard.set(nearThreshold, forKey: "nearThreshold") }
    }
    @Published var farThreshold: Int = -85 {
        didSet { UserDefaults.standard.set(farThreshold, forKey: "farThreshold") }
    }

    private let unlockManager = UnlockManager()
    private var bleManager: BLECentralManager!

    // Hysteresis: RSSI must be consistently near/far for this many seconds before acting.
    private let hysteresisSeconds: TimeInterval = 5.0
    private var nearTimer: Timer?
    private var farTimer: Timer?

    var statusDescription: String {
        if !isEnabled { return "ProximityUnlock: Disabled" }
        if !isPhoneDetected { return "Scanning for iPhone..." }
        switch proximityState {
        case .near:    return "iPhone nearby"
        case .far:     return "iPhone away"
        case .unknown: return "iPhone found, measuring..."
        }
    }

    init() {
        // Restore persisted settings
        if UserDefaults.standard.object(forKey: "isEnabled") != nil {
            isEnabled = UserDefaults.standard.bool(forKey: "isEnabled")
        }
        if UserDefaults.standard.object(forKey: "nearThreshold") != nil {
            nearThreshold = UserDefaults.standard.integer(forKey: "nearThreshold")
        }
        if UserDefaults.standard.object(forKey: "farThreshold") != nil {
            farThreshold = UserDefaults.standard.integer(forKey: "farThreshold")
        }

        bleManager = BLECentralManager(
            onRSSIUpdate: { [weak self] rssi in
                Task { @MainActor [weak self] in self?.handleRSSI(rssi) }
            },
            onDeviceFound: { [weak self] in
                Task { @MainActor [weak self] in self?.isPhoneDetected = true }
            },
            onDeviceLost: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.isPhoneDetected = false
                    self?.proximityState = .unknown
                    self?.cancelPendingTimers()
                }
            }
        )
    }

    private func handleRSSI(_ newRSSI: Int) {
        rssi = newRSSI

        if newRSSI >= nearThreshold {
            // Signal is strong enough to be "near"
            farTimer?.invalidate()
            farTimer = nil
            if proximityState != .near && nearTimer == nil {
                nearTimer = Timer.scheduledTimer(withTimeInterval: hysteresisSeconds, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.transitionToNear() }
                }
            }
        } else if newRSSI <= farThreshold {
            // Signal is weak enough to be "far"
            nearTimer?.invalidate()
            nearTimer = nil
            if proximityState != .far && farTimer == nil {
                farTimer = Timer.scheduledTimer(withTimeInterval: hysteresisSeconds, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.transitionToFar() }
                }
            }
        } else {
            // In the dead zone between thresholds — cancel any pending transitions.
            cancelPendingTimers()
        }
    }

    private func transitionToNear() {
        nearTimer = nil
        guard isEnabled else { return }
        proximityState = .near
        if unlockManager.isScreenLocked() {
            unlockManager.unlockScreen()
        }
    }

    private func transitionToFar() {
        farTimer = nil
        guard isEnabled else { return }
        proximityState = .far
        // Screen locking when the phone moves away is opt-in (see SettingsView).
        if UserDefaults.standard.bool(forKey: "lockWhenFar") {
            unlockManager.lockScreen()
        }
    }

    private func cancelPendingTimers() {
        nearTimer?.invalidate()
        nearTimer = nil
        farTimer?.invalidate()
        farTimer = nil
    }
}
