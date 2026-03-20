import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var monitor: ProximityMonitor

    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var hasPassword: Bool = false
    @State private var showPasswordEntry: Bool = false
    @State private var passwordMismatch: Bool = false
    @State private var isAccessibilityGranted: Bool = false
    @State private var lockWhenFar: Bool = false

    var body: some View {
        Form {
            // MARK: Status
            Section("Status") {
                LabeledContent("iPhone") {
                    Text(monitor.isPhoneDetected ? "Connected" : "Searching...")
                        .foregroundStyle(monitor.isPhoneDetected ? .green : .secondary)
                }
                if monitor.isPhoneDetected {
                    LabeledContent("Signal strength", value: "\(monitor.rssi) dBm")
                    LabeledContent("Proximity") {
                        Text(proximityLabel)
                            .foregroundStyle(proximityColor)
                    }
                }
            }

            // MARK: General
            Section("General") {
                Toggle("Enable Proximity Unlock", isOn: $monitor.isEnabled)
                Toggle("Lock screen when iPhone moves away", isOn: $lockWhenFar)
                    .onChange(of: lockWhenFar) { _, new in
                        UserDefaults.standard.set(new, forKey: "lockWhenFar")
                    }
            }

            // MARK: Sensitivity
            Section("Sensitivity") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unlock when closer than \(monitor.nearThreshold) dBm")
                    Slider(
                        value: Binding(
                            get: { Double(monitor.nearThreshold) },
                            set: { monitor.nearThreshold = Int($0) }
                        ),
                        in: -90...(-50),
                        step: 1
                    )
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lock when farther than \(monitor.farThreshold) dBm")
                    Slider(
                        value: Binding(
                            get: { Double(monitor.farThreshold) },
                            set: { monitor.farThreshold = Int($0) }
                        ),
                        in: -100...(-60),
                        step: 1
                    )
                }
                Text("-50 dBm ≈ very close (< 1 m)   ·   -90 dBm ≈ far (> 8 m)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: Password
            Section("Unlock Password") {
                if hasPassword {
                    Label("Password saved in Keychain", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    HStack {
                        Button("Change Password") { showPasswordEntry = true }
                        Button("Remove", role: .destructive) {
                            KeychainHelper.shared.deletePassword()
                            hasPassword = false
                        }
                    }
                } else {
                    Text("Save your Mac login password so the app can type it automatically when your iPhone is nearby.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Set Password") { showPasswordEntry = true }
                }

                if showPasswordEntry {
                    SecureField("Password", text: $password)
                    SecureField("Confirm Password", text: $confirmPassword)
                    if passwordMismatch {
                        Label("Passwords do not match", systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    HStack {
                        Button("Save") { savePassword() }
                            .disabled(password.isEmpty)
                        Button("Cancel") {
                            password = ""
                            confirmPassword = ""
                            passwordMismatch = false
                            showPasswordEntry = false
                        }
                    }
                }
            }

            // MARK: Permissions
            Section("Permissions") {
                HStack {
                    Label(
                        isAccessibilityGranted ? "Accessibility: Granted" : "Accessibility: Not Granted",
                        systemImage: isAccessibilityGranted ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(isAccessibilityGranted ? .green : .red)
                    Spacer()
                    if !isAccessibilityGranted {
                        Button("Grant Access") { requestAccessibility() }
                    }
                }
                Text("Accessibility is required for automatic password entry. Grant it in System Settings > Privacy & Security > Accessibility.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 560)
        .onAppear { refresh() }
    }

    // MARK: - Helpers

    private var proximityLabel: String {
        switch monitor.proximityState {
        case .near:    return "Near"
        case .far:     return "Away"
        case .unknown: return "Measuring..."
        }
    }

    private var proximityColor: Color {
        switch monitor.proximityState {
        case .near:    return .green
        case .far:     return .orange
        case .unknown: return .secondary
        }
    }

    private func refresh() {
        hasPassword = KeychainHelper.shared.hasPassword()
        isAccessibilityGranted = AXIsProcessTrusted()
        lockWhenFar = UserDefaults.standard.bool(forKey: "lockWhenFar")
    }

    private func savePassword() {
        guard password == confirmPassword else {
            passwordMismatch = true
            return
        }
        KeychainHelper.shared.savePassword(password)
        hasPassword = true
        password = ""
        confirmPassword = ""
        passwordMismatch = false
        showPasswordEntry = false
    }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
        // Re-check after a short delay (user may have just granted it).
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isAccessibilityGranted = AXIsProcessTrusted()
        }
    }
}
