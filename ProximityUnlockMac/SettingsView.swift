import SwiftUI
import AppKit
import CoreBluetooth

struct SettingsView: View {
    @EnvironmentObject var monitor: ProximityMonitor
    @EnvironmentObject var updater: UpdaterController

    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var hasPassword: Bool = false
    @State private var showPasswordEntry: Bool = false
    @State private var passwordMismatch: Bool = false
    @State private var passwordJustSaved: Bool = false
    @State private var isAccessibilityGranted: Bool = false
    @State private var showResetConfirm = false
    @State private var launchAtLogin: Bool = LoginItemManager.isEnabled

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            securityTab
                .tabItem { Label("Security", systemImage: "lock.fill") }
            updatesTab
                .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .alert("Reset ProximityUnlock?", isPresented: $showResetConfirm) {
            Button("Reset & Quit", role: .destructive) { resetAndQuit() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all settings and your saved password. The app will quit.")
        }
        .frame(width: 460, height: 520)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isAccessibilityGranted = AXIsProcessTrusted()
            launchAtLogin = LoginItemManager.isEnabled
        }
    }

    // MARK: - Tabs

    @ViewBuilder private var generalTab: some View {
        Form {
            Section("Your iPhone") {
                if let issue = bluetoothIssueMessage {
                    Label(issue, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else if monitor.discoveredDevices.isEmpty {
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

            Section("General") {
                Toggle("Enable Proximity Unlock", isOn: $monitor.isEnabled)
                Toggle("Lock when iPhone leaves", isOn: $monitor.lockWhenFar)
                Toggle("Unlock when iPhone returns", isOn: $monitor.unlockWhenNear)
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        launchAtLogin = newValue
                        LoginItemManager.isEnabled = newValue
                        TelemetryService.settingToggled("launch_at_login", value: newValue)
                    }
                ))
            }

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

            Section("Telemetry") {
                Toggle("Share anonymous usage data", isOn: Binding(
                    get: { TelemetryService.isEnabled },
                    set: { TelemetryService.setEnabled($0) }
                ))
                Text("Sends anonymous events (app launches, lock/unlock counts) to help improve the app. No device names, passwords, or personal information are ever collected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var securityTab: some View {
        Form {
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

                if passwordJustSaved {
                    Label("Password saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                        .transition(.opacity)
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

            Section {
                Button("Reset All Data & Quit", role: .destructive) {
                    showResetConfirm = true
                }
            } footer: {
                Text("Deletes all settings, your saved password, and device selection. The app will quit and treat the next launch as a fresh install.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var updatesTab: some View {
        Form {
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
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var aboutTab: some View {
        Form {
            Section("About") {
                LabeledContent("Made by") {
                    Link("Raghav Bodicherla", destination: URL(string: "https://github.com/raghix123")!)
                }
                LabeledContent("Project") {
                    Link("github.com/raghix123/ProximityUnlockMac",
                         destination: URL(string: "https://github.com/raghix123/ProximityUnlockMac")!)
                }
                Text("This app is open source. The code can be modified and used however you please — just give me credit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Helpers

    private var bluetoothIssueMessage: String? {
        switch monitor.bluetoothState {
        case .poweredOn, .unknown, .resetting: return nil
        case .poweredOff:   return "Bluetooth is off. Turn it on in Control Center."
        case .unauthorized: return "Bluetooth permission denied. Grant access in System Settings → Privacy & Security → Bluetooth."
        case .unsupported:  return "This Mac does not support Bluetooth Low Energy."
        @unknown default:   return nil
        }
    }

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
        withAnimation { passwordJustSaved = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            withAnimation { passwordJustSaved = false }
        }
    }

    private func resetAndQuit() {
        KeychainHelper.shared.deletePassword()
        // Unregister from launch-at-login so the reset leaves nothing behind in the
        // system's Login Items list. UserDefaults wipe alone doesn't revert SMAppService.
        if LoginItemManager.isEnabled { LoginItemManager.isEnabled = false }
        if let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
        }
        NSApp.terminate(nil)
    }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        // Fallback in case the user returns to the app via a path that skips didBecomeActive.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isAccessibilityGranted = AXIsProcessTrusted()
        }
    }
}
