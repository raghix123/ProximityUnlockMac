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
    @Published var requireConfirmation: Bool = false {
        didSet { UserDefaults.standard.set(requireConfirmation, forKey: "requireConfirmation") }
    }
    @Published var awaitingConfirmation: Bool = false

    @Published var nearThreshold: Int = -75 {
        didSet { UserDefaults.standard.set(nearThreshold, forKey: "nearThreshold") }
    }
    @Published var farThreshold: Int = -90 {
        didSet { UserDefaults.standard.set(farThreshold, forKey: "farThreshold") }
    }

    // Dependencies — injectable for testing.
    private(set) var bleManager: (any BLECentralManaging)!
    private let unlockManager: any UnlockManaging

    /// MultipeerConnectivity channel — uses WiFi Direct / WiFi / Bluetooth automatically,
    /// giving much more reliable message delivery than raw BLE GATT writes.
    let multipeerManager = MultipeerManager()

    // Hysteresis and confirmation timeout — injectable for fast tests.
    let hysteresisSeconds: TimeInterval
    let confirmationTimeout: TimeInterval

    private var nearTimer: Timer?
    private var farTimer: Timer?
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

    // MARK: - Init

    /// Production init — creates real BLE and Unlock managers.
    convenience init() {
        self.init(unlockManager: UnlockManager())
        // Phase 2: self is now fully initialized; we can safely capture it in closures.
        self.bleManager = BLECentralManager(
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
        // Wire MPC confirmations — same handler, deduplication is handled by isScreenLocked().
        multipeerManager.onConfirmationReceived = { [weak self] approved in
            Task { @MainActor [weak self] in self?.handleConfirmationResponse(approved) }
        }
        // Wire iPhone-initiated lock/unlock commands.
        multipeerManager.onLockCommand = { [weak self] in
            Task { @MainActor [weak self] in
                Log.proximity.info("Received remote lock command")
                self?.unlockManager.lockScreen()
            }
        }
        multipeerManager.onUnlockCommand = { [weak self] in
            Task { @MainActor [weak self] in
                Log.proximity.info("Received remote unlock command")
                self?.unlockManager.unlockScreen()
            }
        }
    }

    /// Testable designated init — all dependencies injectable.
    /// Tests inject a MockBLECentralManager and call handleRSSI/handleConfirmationResponse directly.
    init(
        bleManager: (any BLECentralManaging)? = nil,
        unlockManager: any UnlockManaging,
        hysteresisSeconds: TimeInterval = 1.5,
        confirmationTimeout: TimeInterval = 15.0
    ) {
        self.unlockManager      = unlockManager
        self.hysteresisSeconds  = hysteresisSeconds
        self.confirmationTimeout = confirmationTimeout
        // bleManager is set to nil here; convenience init overwrites it; tests supply their own.
        self.bleManager = bleManager

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
    }

    // MARK: - RSSI Handling (internal so tests can call directly)

    func handleRSSI(_ newRSSI: Int) {
        rssi = newRSSI

        if newRSSI >= nearThreshold {
            farTimer?.invalidate()
            farTimer = nil
            if proximityState != .near && nearTimer == nil {
                Log.proximity.debug("RSSI \(newRSSI, privacy: .public) crossed near threshold \(self.nearThreshold, privacy: .public)")
                nearTimer = Timer.scheduledTimer(withTimeInterval: hysteresisSeconds, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.transitionToNear() }
                }
            }
        } else if newRSSI <= farThreshold {
            nearTimer?.invalidate()
            nearTimer = nil
            if proximityState != .far && farTimer == nil {
                Log.proximity.debug("RSSI \(newRSSI, privacy: .public) crossed far threshold \(self.farThreshold, privacy: .public)")
                farTimer = Timer.scheduledTimer(withTimeInterval: hysteresisSeconds, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.transitionToFar() }
                }
            }
        } else {
            cancelPendingTimers()
        }
    }

    // MARK: - Confirmation Response (internal so tests can call directly)

    func handleConfirmationResponse(_ approved: Bool) {
        Log.proximity.info("Confirmation response: \(approved ? "approved" : "denied", privacy: .public)")
        confirmationTimer?.invalidate()
        confirmationTimer = nil
        awaitingConfirmation = false

        guard approved, isEnabled, unlockManager.isScreenLocked() else { return }
        unlockManager.unlockScreen()
    }

    // MARK: - State Transitions (internal for testing)

    func transitionToNear() {
        nearTimer = nil
        Log.proximity.info("Transitioning to near (isEnabled=\(self.isEnabled, privacy: .public), isScreenLocked=\(self.unlockManager.isScreenLocked(), privacy: .public))")
        guard isEnabled else { return }
        proximityState = .near
        guard unlockManager.isScreenLocked() else { return }

        if requireConfirmation {
            requestUnlockConfirmation()
        } else {
            unlockManager.unlockScreen()
        }
    }

    func transitionToFar() {
        farTimer = nil
        Log.proximity.info("Transitioning to far")
        cancelConfirmationWait()
        guard isEnabled else { return }
        proximityState = .far
        sendCommand("lock_event")
        if UserDefaults.standard.bool(forKey: "lockWhenFar") {
            unlockManager.lockScreen()
        }
    }

    // MARK: - Confirmation Flow

    private func requestUnlockConfirmation() {
        guard !awaitingConfirmation else { return }
        Log.proximity.info("Requesting unlock confirmation from iPhone")
        awaitingConfirmation = true
        sendCommand("unlock_request")

        confirmationTimer = Timer.scheduledTimer(
            withTimeInterval: confirmationTimeout,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.awaitingConfirmation = false
            }
        }
    }

    func cancelConfirmationWait() {
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

    // MARK: - Dual-Channel Command Sending

    /// Sends a command via MPC when connected (more reliable), falling back to BLE GATT.
    /// Both channels are tried when both are available so the message gets through either way.
    private func sendCommand(_ command: String) {
        let sentViaMPC = multipeerManager.sendCommand(command)
        if sentViaMPC {
            Log.proximity.info("Sent command via MPC: \(command, privacy: .public)")
        } else {
            Log.proximity.info("MPC unavailable, falling back to BLE for command: \(command, privacy: .public)")
            bleManager?.writeCommand(command)
        }
    }
}
