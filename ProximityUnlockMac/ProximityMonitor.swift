import Foundation
import Combine
import os

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
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "isEnabled")
            if isEnabled {
                multipeerManager.startBrowsing()
            } else {
                multipeerManager.stopBrowsing()
            }
        }
    }
    @Published var requireConfirmation: Bool = false {
        didSet { UserDefaults.standard.set(requireConfirmation, forKey: "requireConfirmation") }
    }
    @Published var awaitingConfirmation: Bool = false
    @Published var isPaused: Bool = false
    @Published var nearThreshold: Int = -75 {
        didSet { UserDefaults.standard.set(nearThreshold, forKey: "nearThreshold") }
    }
    @Published var farThreshold: Int = -90 {
        didSet { UserDefaults.standard.set(farThreshold, forKey: "farThreshold") }
    }

    // Dependencies — injectable for testing.
    private(set) var bleManager: (any BLECentralManaging)!
    private let unlockManager: any UnlockManaging

    /// MultipeerConnectivity channel — injectable for testing via designated init.
    /// Production code uses the real MultipeerManager; tests use NullMultipeerManager by default
    /// or a MockMultipeerManager for assertions on sent commands.
    private(set) var multipeerManager: any MacMultipeerManaging

    // Hysteresis and confirmation timeout — injectable for fast tests.
    let hysteresisSeconds: TimeInterval
    let confirmationTimeout: TimeInterval

    private var nearTimer: Timer?
    private var farTimer: Timer?
    private var confirmationTimer: Timer?

    var statusDescription: String {
        if !isEnabled { return "ProximityUnlock: Disabled" }
        if !isPhoneDetected { return "Scanning for iPhone..." }
        if awaitingConfirmation && requireConfirmation { return "Waiting for iPhone confirmation..." }
        switch proximityState {
        case .near:    return "iPhone nearby"
        case .far:     return "iPhone away"
        case .unknown: return "iPhone found, measuring..."
        }
    }

    // MARK: - Init

    /// Production init — creates real BLE (RSSI-only) and Unlock managers.
    convenience init() {
        let mpc = MultipeerManager()
        self.init(unlockManager: UnlockManager(), multipeerManager: mpc)
        // Phase 2: self is now fully initialized; we can safely capture it in closures.
        // BLE is RSSI-only — no confirmation callback needed.
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
            }
        )
        // Wire MPC confirmations (sole channel for approvals — no BLE fallback).
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
        // Re-trigger unlock request when screen locks while phone is already near
        // (e.g., idle auto-lock or remote lock command while proximity was already .near).
        // Without this, transitionToNear never re-fires because proximityState stays .near.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled, !self.isPaused, self.isPhoneDetected else { return }
                guard self.proximityState == .near, !self.awaitingConfirmation else { return }
                Log.proximity.info("Screen locked while phone was near — requesting unlock confirmation")
                self.requestUnlockConfirmation()
            }
        }

        if isEnabled { multipeerManager.startBrowsing() }
    }

    /// Testable designated init — all dependencies injectable.
    /// Tests inject MockBLECentralManager and MockMultipeerManager; call handleRSSI/handleConfirmationResponse directly.
    /// Pass nil for multipeerManager to get NullMultipeerManager (no-op — commands are silently dropped).
    init(
        bleManager: (any BLECentralManaging)? = nil,
        unlockManager: any UnlockManaging,
        multipeerManager: (any MacMultipeerManaging)? = nil,
        hysteresisSeconds: TimeInterval = 1.5,
        confirmationTimeout: TimeInterval = 15.0
    ) {
        self.unlockManager       = unlockManager
        self.hysteresisSeconds   = hysteresisSeconds
        self.confirmationTimeout = confirmationTimeout
        self.bleManager = bleManager
        // nil → NullMultipeerManager (sendCommand always returns false — commands are dropped)
        self.multipeerManager = multipeerManager ?? NullMultipeerManager()

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
        Log.proximity.info("Confirmation response received: \(approved ? "approved" : "denied", privacy: .public)")
        // Capture before clearing — the guard must verify a request was actually pending.
        let wasAwaiting = awaitingConfirmation
        confirmationTimer?.invalidate()
        confirmationTimer = nil
        awaitingConfirmation = false

        guard approved else {
            Log.proximity.info("Confirmation denied — no action")
            return
        }
        guard wasAwaiting else {
            Log.proximity.warning("Received approval but was not awaiting confirmation (timed out?)")
            return
        }
        guard isEnabled else {
            Log.proximity.warning("Received approval but monitoring is disabled")
            return
        }
        guard unlockManager.isScreenLocked() else {
            Log.proximity.info("Received approval but screen is no longer locked — skipping unlock")
            return
        }
        unlockManager.unlockScreen()
    }

    // MARK: - State Transitions (internal for testing)

    func transitionToNear() {
        nearTimer = nil
        Log.proximity.info("Transitioning to near (isEnabled=\(self.isEnabled, privacy: .public), isScreenLocked=\(self.unlockManager.isScreenLocked(), privacy: .public))")
        guard isEnabled else { return }
        guard !isPaused else { return }
        proximityState = .near

        if unlockManager.isScreenLocked() {
            // Screen-unlock flow: send request to iPhone for confirmation.
            requestUnlockConfirmation()
        }
    }

    func transitionToFar() {
        farTimer = nil
        Log.proximity.info("Transitioning to far")
        cancelConfirmationWait()
        guard isEnabled else { return }
        guard !isPaused else { return }
        proximityState = .far
        sendCommand("lock_event")
        if UserDefaults.standard.bool(forKey: "lockWhenFar") {
            unlockManager.lockScreen()
        }
    }

    // MARK: - Confirmation Flow

    func requestUnlockConfirmation(retryCount: Int = 0) {
        guard !awaitingConfirmation else { return }
        Log.proximity.info("Requesting unlock confirmation from iPhone (attempt \(retryCount + 1, privacy: .public))")
        awaitingConfirmation = true
        sendCommand("unlock_request")

        confirmationTimer = Timer.scheduledTimer(
            withTimeInterval: confirmationTimeout,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.awaitingConfirmation = false
                // One automatic retry if still near, still locked, and this was the first attempt.
                guard retryCount == 0,
                      self.isEnabled, !self.isPaused,
                      self.proximityState == .near,
                      self.isPhoneDetected,
                      self.unlockManager.isScreenLocked() else { return }
                Log.proximity.info("Confirmation timed out — retrying unlock request")
                self.requestUnlockConfirmation(retryCount: 1)
            }
        }
    }

    func pause() {
        Log.proximity.info("Monitoring paused")
        isPaused = true
        cancelPendingTimers()
        cancelConfirmationWait()
    }

    func resume() {
        Log.proximity.info("Monitoring resumed")
        isPaused = false
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

    // MARK: - Command Sending (MPC-only, M7+)

    /// Sends a command via MPC only. BLE is RSSI-only and carries no commands.
    private func sendCommand(_ command: String) {
        let sent = multipeerManager.sendCommand(command)
        if sent {
            Log.proximity.info("Sent command via MPC: \(command, privacy: .public)")
        } else {
            Log.proximity.warning("Command not sent — MPC unavailable or not paired: \(command, privacy: .public)")
        }
    }
}
