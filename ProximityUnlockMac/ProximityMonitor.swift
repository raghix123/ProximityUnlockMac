import Foundation
import Combine
import CoreBluetooth
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
    @Published var lockWhenFar: Bool = true {
        didSet { UserDefaults.standard.set(lockWhenFar, forKey: "lockWhenFar") }
    }
    @Published var unlockWhenNear: Bool = true {
        didSet { UserDefaults.standard.set(unlockWhenNear, forKey: "unlockWhenNear") }
    }
    @Published var isPaused: Bool = false
    @Published var nearThreshold: Int = -65 {
        didSet { debouncedSaveThresholds() }
    }
    @Published var farThreshold: Int = -80 {
        didSet { debouncedSaveThresholds() }
    }
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var bluetoothState: CBManagerState = .unknown
    @Published var selectedDeviceName: String? {
        didSet {
            guard oldValue != selectedDeviceName else { return }
            UserDefaults.standard.set(selectedDeviceName, forKey: "selectedDeviceName")
            bleManager?.selectedDeviceName = selectedDeviceName
            // Drop any lingering RSSI samples from the previous device so the smoothed
            // average isn't polluted when the new device's signal starts flowing in.
            rssiBuffer.removeAll()
            cancelPendingTimers()
            proximityState = .unknown
            if selectedDeviceName != nil { TelemetryService.deviceSelected() }
        }
    }

    // Dependencies — injectable for testing.
    private(set) var bleManager: (any BLECentralManaging)?
    private let unlockManager: any UnlockManaging

    static let defaultHysteresisSeconds: TimeInterval = 1.5

    // Hysteresis — injectable for fast tests.
    let hysteresisSeconds: TimeInterval

    private var nearTimer: Timer?
    private var farTimer: Timer?
    private var rssiBuffer: [Int] = []
    private let rssiBufferSize = 5
    private var thresholdSaveWork: DispatchWorkItem?

    private func debouncedSaveThresholds() {
        thresholdSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            UserDefaults.standard.set(self.nearThreshold, forKey: "nearThreshold")
            UserDefaults.standard.set(self.farThreshold, forKey: "farThreshold")
            TelemetryService.thresholdChanged(near: self.nearThreshold, far: self.farThreshold)
        }
        thresholdSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

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
                    self?.rssiBuffer.removeAll()
                }
            }
        )
        ble.onDiscoveredDevicesChanged = { [weak self] devices in
            Task { @MainActor [weak self] in self?.discoveredDevices = devices }
        }
        ble.onStateChange = { [weak self] state in
            Task { @MainActor [weak self] in self?.bluetoothState = state }
        }
        // Sync the persisted selection into the BLE manager (didSet doesn't fire in init).
        ble.selectedDeviceName = selectedDeviceName
        self.bleManager = ble
        // Note: we intentionally do NOT re-unlock when the screen locks while the phone
        // is already nearby. If the user manually locked (button, lid, idle timeout),
        // the Mac should stay locked until the phone goes far and comes back, which
        // triggers the normal transitionToFar → transitionToNear unlock cycle.
    }

    /// Testable designated init — all dependencies injectable.
    init(
        bleManager: (any BLECentralManaging)? = nil,
        unlockManager: any UnlockManaging,
        hysteresisSeconds: TimeInterval = ProximityMonitor.defaultHysteresisSeconds
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
        if UserDefaults.standard.object(forKey: "lockWhenFar") != nil {
            lockWhenFar = UserDefaults.standard.bool(forKey: "lockWhenFar")
        }
        if UserDefaults.standard.object(forKey: "unlockWhenNear") != nil {
            unlockWhenNear = UserDefaults.standard.bool(forKey: "unlockWhenNear")
        }

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

        Log.proximity.debug("""
            RSSI raw=\(newRSSI, privacy: .public) \
            smoothed=\(smoothedRSSI, privacy: .public) \
            near≥\(self.nearThreshold, privacy: .public) \
            far≤\(self.farThreshold, privacy: .public) \
            state=\(self.proximityState.description, privacy: .public) \
            bufferSize=\(self.rssiBuffer.count, privacy: .public)
            """)

        // Raw RSSI for near (unlock): fast response when walking toward Mac.
        if newRSSI >= nearThreshold {
            farTimer?.invalidate()
            farTimer = nil
            if proximityState != .near && nearTimer == nil {
                Log.proximity.info("▶ Near timer started (raw \(newRSSI, privacy: .public) ≥ \(self.nearThreshold, privacy: .public))")
                nearTimer = Timer.scheduledTimer(withTimeInterval: hysteresisSeconds, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.transitionToNear() }
                }
            }
        // Smoothed RSSI for far (lock): stable, won't lock from a momentary signal drop.
        } else if smoothedRSSI <= farThreshold {
            nearTimer?.invalidate()
            nearTimer = nil
            if proximityState != .far && farTimer == nil {
                Log.proximity.info("▶ Far timer started (smoothed \(smoothedRSSI, privacy: .public) ≤ \(self.farThreshold, privacy: .public))")
                farTimer = Timer.scheduledTimer(withTimeInterval: hysteresisSeconds, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.transitionToFar() }
                }
            }
        } else {
            if nearTimer != nil || farTimer != nil {
                Log.proximity.debug("Dead zone (smoothed \(smoothedRSSI, privacy: .public)) — cancelling pending timers")
            }
            cancelPendingTimers()
        }
    }

    // MARK: - State Transitions (internal for testing)

    func transitionToNear() {
        nearTimer = nil
        rssiBuffer.removeAll()
        Log.proximity.info("Transitioning to near (enabled=\(self.isEnabled, privacy: .public) paused=\(self.isPaused, privacy: .public) unlockWhenNear=\(self.unlockWhenNear, privacy: .public))")
        guard isEnabled, !isPaused else {
            Log.proximity.info("↩ Near transition blocked (disabled or paused)")
            return
        }
        proximityState = .near
        let locked = unlockManager.isScreenLocked()
        Log.proximity.info("Screen locked=\(locked, privacy: .public) unlockWhenNear=\(self.unlockWhenNear, privacy: .public)")
        if unlockWhenNear, locked {
            Log.proximity.info("🔓 Unlocking screen")
            unlockManager.unlockScreen()
            TelemetryService.proximityUnlocked()
        } else if !unlockWhenNear {
            Log.proximity.info("↩ Unlock skipped (unlockWhenNear=false)")
        }
    }

    func transitionToFar() {
        farTimer = nil
        rssiBuffer.removeAll()
        Log.proximity.info("Transitioning to far (enabled=\(self.isEnabled, privacy: .public) paused=\(self.isPaused, privacy: .public) lockWhenFar=\(self.lockWhenFar, privacy: .public))")
        guard isEnabled, !isPaused else {
            Log.proximity.info("↩ Far transition blocked (disabled or paused)")
            return
        }
        proximityState = .far
        if lockWhenFar {
            Log.proximity.info("🔒 Locking screen")
            unlockManager.lockScreen()
            TelemetryService.proximityLocked()
        } else {
            Log.proximity.info("↩ Lock skipped (lockWhenFar=false)")
        }
    }

    func handleScreensDidWake() {
        Log.proximity.info("Screens woke — resetting proximity state to allow lid-open unlock")
        if proximityState == .near {
            proximityState = .unknown
            rssiBuffer.removeAll()
        }
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
