import SwiftUI
import AppKit

struct MacOnboardingView: View {
    @ObservedObject var monitor: ProximityMonitor
    let onComplete: () -> Void
    @State private var currentStep = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to ProximityUnlock")
                    .font(.title.bold())
                Text("Set up proximity-based Mac unlock")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()

            // Content area
            VStack(alignment: .leading, spacing: 16) {
                switch currentStep {
                case 0: Step0Welcome()
                case 1: Step1DeviceSelect(monitor: monitor)
                case 2: Step2Accessibility()
                case 3: Step3Password()
                default: Step4Done()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()

            // Footer
            HStack(spacing: 12) {
                if currentStep > 0 {
                    Button("Back") { withAnimation { currentStep -= 1 } }
                }
                Spacer()
                if currentStep < 4 {
                    Button("Skip") { onComplete() }
                        .foregroundStyle(.secondary)
                    Button("Next") { withAnimation { currentStep += 1 } }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") { onComplete() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 500, height: 520)
    }
}

// MARK: - Step 0: Welcome

private struct Step0Welcome: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "lock.iphone")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                    .frame(width: 48, height: 48)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Smart Proximity Detection")
                        .font(.headline)
                    Text("Your Mac locks and unlocks based on iPhone proximity — no app required on iPhone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(
                    icon: "iphone.radiowaves.left.and.right",
                    color: .blue,
                    title: "Bluetooth Sensing",
                    description: "Low-energy Bluetooth detects your iPhone's proximity"
                )
                FeatureRow(
                    icon: "lock.fill",
                    color: .orange,
                    title: "Auto Lock",
                    description: "Mac locks when you walk away with your iPhone"
                )
                FeatureRow(
                    icon: "lock.open.fill",
                    color: .green,
                    title: "Auto Unlock",
                    description: "Mac unlocks automatically when you return"
                )
            }
        }
    }
}

// MARK: - Step 1: Select Your iPhone

private struct Step1DeviceSelect: View {
    @ObservedObject var monitor: ProximityMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Select Your iPhone")
                .font(.headline)
            Text("Choose your iPhone from the list of nearby Bluetooth devices:")
                .font(.caption)
                .foregroundStyle(.secondary)

            if monitor.discoveredDevices.isEmpty {
                HStack(spacing: 12) {
                    ProgressView().scaleEffect(0.8)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Scanning for devices…")
                            .font(.subheadline.weight(.semibold))
                        Text("Make sure Bluetooth is on and your iPhone is nearby.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 6) {
                    ForEach(monitor.discoveredDevices) { device in
                        DeviceRow(
                            device: device,
                            isSelected: monitor.selectedDeviceName == device.name
                        ) {
                            monitor.selectedDeviceName = device.name
                        }
                    }
                }
            }

            if let selected = monitor.selectedDeviceName {
                Label("Selected: \(selected)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption.weight(.semibold))
            }

            Spacer()

            Text("Can't see your iPhone? Make sure Bluetooth is enabled on both devices.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DeviceRow: View {
    let device: DiscoveredDevice
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "iphone")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .white : .blue)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? .white : .primary)
                    Text("\(device.rssi) dBm")
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.white)
                        .font(.caption.weight(.bold))
                }
            }
            .padding(10)
            .background(isSelected ? Color.blue : Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 2: Accessibility Permissions

private struct Step2Accessibility: View {
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var checkTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Grant Accessibility Permission")
                .font(.headline)
            Text("Required for automatic password entry when unlocking:")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                VStack {
                    if accessibilityGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "lock.shield.fill")
                            .font(.title3)
                            .foregroundStyle(.blue)
                    }
                    Spacer()
                }
                .frame(width: 36, height: 36)
                .background(accessibilityGranted ? Color.green.opacity(0.1) : Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Accessibility")
                        .font(.subheadline.weight(.semibold))
                    if accessibilityGranted {
                        Text("Granted")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text("Required for automatic unlock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if !accessibilityGranted {
                    Button(action: requestAccessibility) {
                        Text("Enable")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(12)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()

            Text("macOS will show an authentication dialog with the app pre-selected. Tap OK or use Touch ID to grant access.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task {
            checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                accessibilityGranted = AXIsProcessTrusted()
            }
        }
        .onDisappear {
            checkTimer?.invalidate()
        }
    }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}

// MARK: - Step 3: Password

private struct Step3Password: View {
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var passwordMismatch = false
    @State private var showPasswordEntry = false
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Login Password (Optional)")
                .font(.headline)
            Text("Save your Mac login password for automatic unlock:")
                .font(.caption)
                .foregroundStyle(.secondary)

            if saved {
                Label("Password saved securely in Keychain", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .padding(12)
                    .background(Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if showPasswordEntry {
                VStack(spacing: 12) {
                    SecureField("Mac password", text: $password)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Confirm password", text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)

                    if passwordMismatch {
                        Label("Passwords do not match", systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }

                    HStack(spacing: 12) {
                        Button("Save") { savePassword() }
                            .buttonStyle(.borderedProminent)
                            .disabled(password.isEmpty)
                        Button("Cancel") {
                            password = ""
                            confirmPassword = ""
                            passwordMismatch = false
                            showPasswordEntry = false
                        }
                    }
                }
                .padding(12)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Button(action: { showPasswordEntry = true }) {
                    HStack {
                        Image(systemName: "lock.fill")
                        Text("Save Password")
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Text("Your password is stored securely in the system Keychain and never transmitted.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func savePassword() {
        guard password == confirmPassword else {
            passwordMismatch = true
            return
        }
        KeychainHelper.shared.savePassword(password)
        password = ""
        confirmPassword = ""
        passwordMismatch = false
        showPasswordEntry = false
        saved = true
    }
}

// MARK: - Step 4: Done

private struct Step4Done: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.green)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text("You're all set!")
                        .font(.headline)
                    Text("ProximityUnlock is ready — no iPhone app required.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ChecklistItem(title: "Walk away", description: "Mac locks when your iPhone moves away")
                ChecklistItem(title: "Walk back", description: "Mac unlocks automatically when you return")
                ChecklistItem(title: "Always local", description: "Everything happens on your Mac via Bluetooth")
            }

            Spacer()

            Text("Adjust sensitivity and device selection from the menu bar icon anytime.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Shared Components

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ChecklistItem: View {
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
