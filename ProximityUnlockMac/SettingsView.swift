import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var monitor: ProximityMonitor

    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var hasPassword: Bool = false
    @State private var showPasswordEntry: Bool = false
    @State private var passwordMismatch: Bool = false
    @State private var isAccessibilityGranted: Bool = false
    @State private var lockWhenFar: Bool = false

    private var pairingManager: PairingManager? {
        (monitor.multipeerManager as? MultipeerManager)?.pairingManager
    }

    var body: some View {
        Form {
            // MARK: Pairing
            if let pm = pairingManager {
                PairingSectionView(pairingManager: pm)
            }

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
                Toggle("Require iPhone confirmation to unlock", isOn: $monitor.requireConfirmation)
                Toggle("Lock screen when iPhone moves away", isOn: $lockWhenFar)
                    .onChange(of: lockWhenFar) { new in
                        UserDefaults.standard.set(new, forKey: "lockWhenFar")
                    }
                }

            // MARK: Confirmation status
            if monitor.awaitingConfirmation {
                Section {
                    Label("Waiting for iPhone to confirm unlock...", systemImage: "iphone.and.arrow.forward")
                        .foregroundStyle(.orange)
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

            // MARK: Password (gated on pairing)
            Section("Unlock Password") {
                if pairingManager?.isPaired == true {
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
                } else {
                    Label("Pair with iPhone first to enable secure password storage.", systemImage: "lock.iphone")
                        .foregroundStyle(.secondary)
                        .font(.caption)
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
        // Open System Settings directly to Privacy & Security > Accessibility
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        // Re-check after a short delay (user may have just granted it).
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isAccessibilityGranted = AXIsProcessTrusted()
        }
    }
}

// MARK: - Pairing Section

private struct PairingSectionView: View {
    @ObservedObject var pairingManager: PairingManager

    var body: some View {
        Section("Pairing") {
            switch pairingManager.pairingState {
            case .unpaired:
                Label("Not paired with any iPhone", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Pairing starts automatically when your iPhone (with ProximityUnlock) is nearby.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .pairing(let phase):
                PairingPhaseView(phase: phase, pairingManager: pairingManager)

            case .paired(let peerName):
                Label("Paired with \(peerName)", systemImage: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                Button("Unpair", role: .destructive) {
                    pairingManager.unpair()
                }
            }

            if let error = pairingManager.pairingError {
                Label(error, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }
}

private struct PairingPhaseView: View {
    let phase: PairingPhase
    let pairingManager: PairingManager

    var body: some View {
        switch phase {
        case .waitingForPeer, .exchangingKeys:
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.7)
                Text("Exchanging keys with iPhone…")
                    .foregroundStyle(.secondary)
            }

        case .displayingCode(let code):
            VStack(alignment: .leading, spacing: 8) {
                Label("Compare this code with your iPhone", systemImage: "lock.shield")
                    .fontWeight(.semibold)
                Text("If both devices show the same 6-digit code, tap Confirm on both to complete pairing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatCode(code))
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .padding(.vertical, 4)
                HStack(spacing: 12) {
                    Button("Confirm Pairing") {
                        pairingManager.confirmCode()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Cancel", role: .destructive) {
                        pairingManager.cancelPairing()
                    }
                }
            }

        case .confirming, .deriving:
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.7)
                Text("Confirming pairing…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func formatCode(_ code: String) -> String {
        let clean = code.filter { $0.isNumber }
        guard clean.count == 6 else { return code }
        return String(clean.prefix(3)) + " " + String(clean.suffix(3))
    }
}
