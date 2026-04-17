import Foundation
import TelemetryClient

/// Thin wrapper around TelemetryDeck. All signals are anonymous — no device names,
/// no passwords, no hardware identifiers. Users can opt out in Settings → About.
@MainActor
enum TelemetryService {

    private static let appID = "14838AA9-45A6-4C7D-8EF0-FA51897AACDE"
    private static var didStart = false

    /// Telemetry is enabled by default (opt-out model).
    /// Users can disable telemetry in Settings → About.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "telemetryEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "telemetryEnabled") }
    }

    static func start() {
        guard !didStart else { return }
        configure(enabled: isEnabled)
    }

    static func signal(_ name: String, parameters: [String: String] = [:]) {
        guard isEnabled else { return }
        start()  // Lazy init: signals from object initializers can fire before AppDelegate.
        TelemetryManager.send(name, with: parameters)
    }

    private static func configure(enabled: Bool) {
        var config = TelemetryManagerConfiguration(appID: appID)
        config.analyticsDisabled = !enabled
        TelemetryManager.initialize(with: config)
        didStart = true
    }

    // MARK: - Named events

    static func appLaunched(nearThreshold: Int, farThreshold: Int) {
        let bucket = { (v: Int) in String(Int((Double(v) / 5.0).rounded() * 5)) }
        signal("app.launched", parameters: [
            "near_dbm": bucket(nearThreshold),
            "far_dbm":  bucket(farThreshold)
        ])
    }

    static func proximityLocked() {
        signal("proximity.locked")
    }

    static func proximityUnlocked() {
        signal("proximity.unlocked")
    }

    static func deviceSelected() {
        signal("device.selected")
    }

    static func settingToggled(_ key: String, value: Bool) {
        signal("setting.toggled", parameters: ["key": key, "value": value ? "true" : "false"])
    }

    static func updateCheckTriggered(manual: Bool) {
        signal("update.check", parameters: ["manual": manual ? "true" : "false"])
    }

    /// Called when the user finishes adjusting a threshold slider.
    /// Values are bucketed to 5 dBm to avoid over-precision.
    static func thresholdChanged(near nearThreshold: Int, far farThreshold: Int) {
        let bucket = { (v: Int) in String(Int((Double(v) / 5.0).rounded() * 5)) }
        signal("threshold.changed", parameters: [
            "near_dbm": bucket(nearThreshold),
            "far_dbm":  bucket(farThreshold)
        ])
    }

    static func onboardingCompleted() {
        signal("onboarding.completed")
    }

    static func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        // Re-initialize so TelemetryDeck picks up the new analyticsDisabled flag.
        configure(enabled: enabled)
    }
}
