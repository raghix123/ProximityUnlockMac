import Foundation
import Combine

enum ProximityState {
    case near, far, unknown
}

/// Coordinates BLE scanning, proximity state, unlock confirmation, and lock/unlock actions.
@MainActor
class ProximityMonitor: ObservableObject {
    @Published var proximityState: ProximityState = .unknown
    @Published var rssi: Int = -100
    @Published var isPhoneDetected: Bool = false
    @Published var isEnabled: Bool = true {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "isEnabled") }
    }
    /// When true, Mac sends an unlock_request to the iPhone and waits for approval.
    @Published var requireConfirmation: Bool = true {
        didSet { UserDefaults.standard.set(requireConfirmation, forKey: "requireConfirmation") }
    }
    /// True while we're waiting for the iPhone to approve/deny an unlock.
    @Published var awaitingConfirmation: Bool = false

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

    // Timeout for waiting on iPhone confirmation (seconds).
    private let confirmationTimeout: TimeInterval = 15.0
    private var confirmationTimer: Timer?

    var statusDescription: String {
        if !isEnabled { return "ProximityUnlock: Disabled" }
        if !isPhoneDetected { return "Scanning for iPhone..." }
        if awaitingConfirmation { return "Waiting for iPhone confirmation..." }
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
        if UserDefaults.standard.object(forKey: "requireConfirmation") != nil {
            requireConfirmation = UserDefaults.standard.bool(forKey: "requireConfirmation")
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
                    self?.cancelConfirmationWait()
                }
            },
            onConfirmationReceived: { [weak self] approved in
                Task { @MainActor [weak self] in self?.handleConfirmationResponse(approved) }
            }
        )
    }

    // MARK: - RSSI Handling

    private func handleRSSI(_ newRSSI: Int) {
        rssi = newRSSI

        if newRSSI >= nearThreshold {
            farTimer?.invalidate()
            farTimer = nil
            if proximityState != .near && nearTimer == nil {
                nearTimer = Timer.scheduledTimer(withTimeInterval: hysteresisSeconds, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.transitionToNear() }
                }
            }
        } else if newRSSI <= farThreshold {
            nearTimer?.invalidate()
            nearTimer = nil
            if proximityState != .far && farTimer == nil {
                farTimer = Timer.scheduledTimer(withTimeInterval: hysteresisSeconds, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.transitionToFar() }
                }
            }
        } else {
            cancelPendingTimers()
        }
    }

    // MARK: - State Transitions

    private func transitionToNear() {
        nearTimer = nil
        guard isEnabled else { return }
        proximityState = .near
        guard unlockManager.isScreenLocked() else { return }

        if requireConfirmation {
            requestUnlockConfirmation()
        } else {
            unlockManager.unlockScreen()
        }
    }

    private func transitionToFar() {
        farTimer = nil
        cancelConfirmationWait()
        guard isEnabled else { return }
        proximityState = .far

        // Notify iPhone of the lock event (so it can clear pending request UI)
        bleManager.writeCommand("lock_event")

        if UserDefaults.standard.bool(forKey: "lockWhenFar") {
            unlockManager.lockScreen()
        }
    }

    // MARK: - Confirmation Flow

    private func requestUnlockConfirmation() {
        guard !awaitingConfirmation else { return }
        awaitingConfirmation = true

        // Send request to iPhone
        bleManager.writeCommand("unlock_request")

        // Start timeout — if iPhone doesn't respond in time, abort unlock
        confirmationTimer = Timer.scheduledTimer(
            withTimeInterval: confirmationTimeout,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.awaitingConfirmation = false
            }
        }
    }

    private func handleConfirmationResponse(_ approved: Bool) {
        confirmationTimer?.invalidate()
        confirmationTimer = nil
        awaitingConfirmation = false

        guard approved, isEnabled, unlockManager.isScreenLocked() else { return }
        unlockManager.unlockScreen()
    }

    private func cancelConfirmationWait() {
        confirmationTimer?.invalidate()
        confirmationTimer = nil
        awaitingConfirmation = false
    }

    private func cancelPendingTimers() {
        nearTimer?.invalidate()
        nearTimer = nil
        farTimer?.invalidate()
        farTimer = nil
    }
}
