import Foundation
import Combine
import os

enum ProximityState: CustomStringConvertible {
    case near, far, unknown

    var description: String {
        switch self {
        case .near: return "near"
        case .far: return "far"
        case .unknown: return "unknown"
        }
    }
}

/// Coordinates BLE scanning, proximity state, and direct lock/unlock actions.
/// No iPhone app or MPC required — lock/unlock is entirely local.
@MainActor
class ProximityMonitor: ObservableObject {
    @Published var proximityState: ProximityState = .unknown
    @Published var rssi: Int = -100
    @Published var isPhoneDetected: Bool = false
    @Published var isEnabled: Bool = true {
        didSet { UserDefaults.standard.set(isEnabled, forKey: "isEnabled") }
    }
    @Published var isPaused: Bool = false
    @Published var nearThreshold: Int = -75 {
        didSet { UserDefaults.standard.set(nearThreshold, forKey: "nearThreshold") }
    }
    @Published var farThreshold: Int = -90 {
        didSet { UserDefaults.standard.set(farThreshold, forKey: "farThreshold") }
    }
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var selectedDeviceName: String? {
        didSet {
            UserDefaults.standard.set(selectedDeviceName, forKey: "selectedDeviceName")
            bleManager?.selectedDeviceName = selectedDeviceName
        }
    }

    // Dependencies — injectable for testing.
    private(set) var bleManager: (any BLECentralManaging)?
    private let unlockManager: any UnlockManaging

    // Hysteresis — injectable for fast tests.
    let hysteresisSeconds: TimeInterval

    private var nearTimer: Timer?
    private var farTimer: Timer?
    private var rssiBuffer: [Int] = []
    private let rssiBufferSize = 5

    var statusDescription: String {
        if !isEnabled { return "ProximityUnlock: Disabled" }
        guard let name = selectedDeviceName else { return "No device selected" }
        if !isPhoneDetected { return "Scanning for \(name)..." }
        switch proximityState {
        case .near:    return "iPhone nearby"
        case .far:     return "iPhone away"
        case .unknown: return "iPhone found, measuring..."
        }
    }

    // MARK: - Init

    /// Production init — creates real BLE manager.
    convenience init() {
        self.init(unlockManager: UnlockManager())
        let ble = BLECentralManager(
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
        ble.onDiscoveredDevicesChanged = { [weak self] devices in
            Task { @MainActor [weak self] in self?.discoveredDevices = devices }
        }
        // Sync the persisted selection into the BLE manager (didSet doesn't fire in init).
        ble.selectedDeviceName = selectedDeviceName
        self.bleManager = ble

        // Re-unlock when screen locks while phone is already nearby
        // (e.g., idle auto-lock while user is sitting at desk with iPhone in pocket).
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isEnabled, !self.isPaused, self.isPhoneDetected else { return }
                guard self.proximityState == .near else { return }
                Log.proximity.info("Screen locked while phone was near — re-unlocking")
                self.unlockManager.unlockScreen()
            }
        }
    }

    /// Testable designated init — all dependencies injectable.
    init(
        bleManager: (any BLECentralManaging)? = nil,
        unlockManager: any UnlockManaging,
        hysteresisSeconds: TimeInterval = 1.5
    ) {
        self.unlockManager     = unlockManager
        self.hysteresisSeconds = hysteresisSeconds
        self.bleManager        = bleManager

        // Restore persisted settings.
        if UserDefaults.standard.object(forKey: "isEnabled") != nil {
            isEnabled = UserDefaults.standard.bool(forKey: "isEnabled")
        }
        if UserDefaults.standard.object(forKey: "nearThreshold") != nil {
            nearThreshold = UserDefaults.standard.integer(forKey: "nearThreshold")
        }
        if UserDefaults.standard.object(forKey: "farThreshold") != nil {
            farThreshold = UserDefaults.standard.integer(forKey: "farThreshold")
        }
        selectedDeviceName = UserDefaults.standard.string(forKey: "selectedDeviceName")

        // Validate threshold sanity: near must be a stronger signal (less negative) than far.
        if nearThreshold <= farThreshold {
            nearThreshold = -65
            farThreshold = -80
            UserDefaults.standard.set(nearThreshold, forKey: "nearThreshold")
            UserDefaults.standard.set(farThreshold, forKey: "farThreshold")
            Log.proximity.warning("Stored RSSI thresholds were inverted — reset to near=-65, far=-80")
        }
    }

    // MARK: - RSSI Handling (internal so tests can call directly)

    func handleRSSI(_ newRSSI: Int) {
        rssi = newRSSI

        rssiBuffer.append(newRSSI)
        if rssiBuffer.count > rssiBufferSize { rssiBuffer.removeFirst() }
        let smoothedRSSI = rssiBuffer.reduce(0, +) / rssiBuffer.count

        // Raw RSSI for near (unlock): fast response when walking toward Mac.
        if newRSSI >= nearThreshold {
            farTimer?.invalidate()
            farTimer = nil
            if proximityState != .near && nearTimer == nil {
                Log.proximity.debug("Raw RSSI \(newRSSI, privacy: .public) crossed near threshold \(self.nearThreshold, privacy: .public)")
                nearTimer = Timer.scheduledTimer(withTimeInterval: hysteresisSeconds, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.transitionToNear() }
                }
            }
        // Smoothed RSSI for far (lock): stable, won't lock from a momentary signal drop.
        } else if smoothedRSSI <= farThreshold {
            nearTimer?.invalidate()
            nearTimer = nil
            if proximityState != .far && farTimer == nil {
                Log.proximity.debug("Smoothed RSSI \(smoothedRSSI, privacy: .public) crossed far threshold \(self.farThreshold, privacy: .public)")
                farTimer = Timer.scheduledTimer(withTimeInterval: hysteresisSeconds, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.transitionToFar() }
                }
            }
        } else {
            cancelPendingTimers()
        }
    }

    // MARK: - State Transitions (internal for testing)

    func transitionToNear() {
        nearTimer = nil
        rssiBuffer.removeAll()
        Log.proximity.info("Transitioning to near")
        guard isEnabled, !isPaused else { return }
        proximityState = .near
        if unlockManager.isScreenLocked() {
            unlockManager.unlockScreen()
        }
    }

    func transitionToFar() {
        farTimer = nil
        rssiBuffer.removeAll()
        Log.proximity.info("Transitioning to far")
        guard isEnabled, !isPaused else { return }
        proximityState = .far
        unlockManager.lockScreen()
    }

    func pause() {
        Log.proximity.info("Monitoring paused")
        isPaused = true
        cancelPendingTimers()
    }

    func resume() {
        Log.proximity.info("Monitoring resumed")
        isPaused = false
    }

    private func cancelPendingTimers() {
        nearTimer?.invalidate()
        nearTimer = nil
        farTimer?.invalidate()
        farTimer = nil
    }
}
