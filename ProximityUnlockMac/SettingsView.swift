import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var monitor: ProximityMonitor
    @EnvironmentObject var updater: UpdaterController

    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var hasPassword: Bool = false
    @State private var showPasswordEntry: Bool = false
    @State private var passwordMismatch: Bool = false
    @State private var isAccessibilityGranted: Bool = false
    @State private var showResetConfirm = false

    var body: some View {
        Form {
            // MARK: Device Selection
            Section("Your iPhone") {
                if monitor.discoveredDevices.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text("Scanning for Bluetooth devices…")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Picker("Track device", selection: Binding(
                        get: { monitor.selectedDeviceName },
                        set: { monitor.selectedDeviceName = $0 }
                    )) {
                        Text("Not selected").tag(String?.none)
                        ForEach(monitor.discoveredDevices) { device in
                            Text("\(device.name)  (\(device.rssi) dBm)")
                                .tag(Optional(device.name))
                        }
                    }
                }
                Text("Select your iPhone from nearby Bluetooth devices. The Mac will lock when it moves away and unlock when it comes back.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: Status
            Section("Status") {
                LabeledContent("Device") {
                    if let name = monitor.selectedDeviceName {
                        Text(monitor.isPhoneDetected ? name : "Searching…")
                            .foregroundStyle(monitor.isPhoneDetected ? .green : .secondary)
                    } else {
                        Text("No device selected")
                            .foregroundStyle(.secondary)
                    }
                }
                if monitor.isPhoneDetected {
                    LabeledContent("Signal strength", value: RSSIDistance.label(rssi: monitor.rssi))
                    LabeledContent("Proximity") {
                        Text(proximityLabel)
                            .foregroundStyle(proximityColor)
                    }
                }
            }

            // MARK: General
            Section("General") {
                Toggle("Enable Proximity Unlock", isOn: $monitor.isEnabled)
                Toggle("Lock when iPhone leaves", isOn: $monitor.lockWhenFar)
                Toggle("Unlock when iPhone returns", isOn: $monitor.unlockWhenNear)
            }

            // MARK: Sensitivity
            Section("Sensitivity") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unlock when closer than \(RSSIDistance.label(rssi: monitor.nearThreshold))")
                    Slider(
                        value: Binding(
                            get: { Double(monitor.nearThreshold) },
                            set: { monitor.nearThreshold = Int($0) }
                        ),
                        in: -100...(-50),
                        step: 1
                    )
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Lock when farther than \(RSSIDistance.label(rssi: monitor.farThreshold))")
                    Slider(
                        value: Binding(
                            get: { Double(monitor.farThreshold) },
                            set: { monitor.farThreshold = Int($0) }
                        ),
                        in: -100...(-50),
                        step: 1
                    )
                }
                Text("-50 dBm ≈ very close (< 1 m)   ·   -100 dBm ≈ far (> 8 m)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: Password
            Section("Unlock Password") {
                if hasPassword {
                    Label("Password saved (encrypted)", systemImage: "checkmark.seal.fill")
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
                        HStack(spacing: 8) {
                            Button(action: { requestAccessibility() }) {
                                Text("Grant Access")
                            }
                            Button(action: { isAccessibilityGranted = AXIsProcessTrusted() }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text("Accessibility is required for automatic password entry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // MARK: Updates
            Section("Updates") {
                Toggle("Automatically check for updates", isOn: $updater.automaticUpdateChecks)

                Picker("Update channel", selection: $updater.updateChannel) {
                    ForEach(UpdaterController.UpdateChannel.allCases) { ch in
                        Text(ch.displayName).tag(ch)
                    }
                }

                HStack {
                    Button("Check for Updates Now") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                    Spacer()
                    if let d = updater.lastUpdateCheckDate {
                        Text("Last checked: \(d.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Link("View all releases on GitHub",
                     destination: URL(string: "https://github.com/raghix123/ProximityUnlockMac/releases")!)
                    .font(.caption)
            }

            Section {
                Button("Reset All Data & Quit", role: .destructive) {
                    showResetConfirm = true
                }
            } footer: {
                Text("Deletes all settings, your saved password, and device selection. The app will quit and treat the next launch as a fresh install.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Made by") {
                    Link("Raghav Bodicherla", destination: URL(string: "https://github.com/raghix123")!)
                }
                LabeledContent("Project") {
                    Link("github.com/raghix123/ProximityUnlockMac",
                         destination: URL(string: "https://github.com/raghix123/ProximityUnlockMac")!)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("This app is open source. The code can be modified and used however you please — just give me credit.")
                    Text("Icon made by Freepik from www.flaticon.com")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .alert("Reset ProximityUnlock?", isPresented: $showResetConfirm) {
            Button("Reset & Quit", role: .destructive) { resetAndQuit() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all settings and your saved password. The app will quit.")
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 940)
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

    private func resetAndQuit() {
        KeychainHelper.shared.deletePassword()
        if let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
        }
        NSApp.terminate(nil)
    }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isAccessibilityGranted = AXIsProcessTrusted()
        }
    }
}
