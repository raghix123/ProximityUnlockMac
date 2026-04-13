import SwiftUI
import AppKit

struct MacOnboardingView: View {
    let onComplete: () -> Void
    @State private var currentStep = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to ProximityUnlock")
                    .font(.title.bold())
                Text("Unlock your Mac automatically when your iPhone is nearby")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()

            // Content area - changes based on step
            VStack(alignment: .leading, spacing: 16) {
                if currentStep == 0 {
                    Step0Content()
                } else if currentStep == 1 {
                    Step1Content()
                } else if currentStep == 2 {
                    Step2Content()
                } else {
                    Step3Content()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()

            // Footer with buttons
            HStack(spacing: 12) {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                }
                Spacer()
                Button("Skip") {
                    onComplete()
                }
                .foregroundStyle(.secondary)

                if currentStep < 3 {
                    Button("Next") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Get Started") {
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 500, height: 480)
    }
}

// MARK: - Step 0: Overview

private struct Step0Content: View {
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
                    Text("Your Mac unlocks instantly when your iPhone gets close — no fumbling for passwords.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(
                    icon: "iphone.radiowaves.left.and.right",
                    color: .blue,
                    title: "Bluetooth Sensing",
                    description: "Uses low-energy Bluetooth to detect proximity"
                )
                FeatureRow(
                    icon: "faceid",
                    color: .green,
                    title: "Biometric Protection",
                    description: "Face ID or Touch ID approves each unlock"
                )
                FeatureRow(
                    icon: "wifi",
                    color: .purple,
                    title: "Secure & Private",
                    description: "Everything stays on your local network"
                )
            }
        }
    }
}

// MARK: - Step 1: Permissions

private struct Step1Content: View {
    @State private var accessibilityGranted = AXIsProcessTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Permissions Required")
                .font(.headline)
            Text("ProximityUnlock needs these permissions to work:")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                PermissionCard(
                    icon: "lock.iphone",
                    color: .blue,
                    title: "Pairing with iPhone",
                    description: "Establish a secure connection with your iPhone",
                    granted: true // Will be set up during pairing
                )

                PermissionCard(
                    icon: "checkbox.circle.fill",
                    color: accessibilityGranted ? .green : .red,
                    title: "Accessibility",
                    description: "Required to monitor lock state and unlock",
                    granted: accessibilityGranted,
                    action: {
                        if !accessibilityGranted {
                            openAccessibilitySettings()
                        }
                    }
                )
            }

            Spacer()

            Text("You can grant permissions now or skip this step and enable them later in System Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Step 2: Pairing

private struct Step2Content: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pair Your iPhone")
                .font(.headline)
            Text("Set up the secure connection between your devices:")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                StepRow(number: 1, title: "Install ProximityUnlock", description: "Download from App Store on your iPhone")
                StepRow(number: 2, title: "Bring iPhone close", description: "Hold your iPhone near your Mac")
                StepRow(number: 3, title: "Confirm codes match", description: "A 6-digit code appears on both screens")
                StepRow(number: 4, title: "Tap Confirm", description: "Complete pairing on both devices")
            }

            Spacer()

            Text("Pairing is automatic — just bring your iPhone within Bluetooth range (typically 10-20 meters).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Step 3: Ready to Go

private struct Step3Content: View {
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
                    Text("ProximityUnlock is ready to secure your Mac")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                ChecklistItem(title: "Walk away", description: "Mac locks when iPhone moves away")
                ChecklistItem(title: "Walk back", description: "iPhone prompts to unlock")
                ChecklistItem(title: "Approve", description: "Mac unlocks after Face ID")
            }

            Spacer()

            Text("Access Settings from the menu bar icon to adjust sensitivity and other options.")
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

private struct PermissionCard: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    let granted: Bool
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            VStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Spacer()
            }
            .frame(width: 36, height: 36)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if let action = action {
                Button(action: action) {
                    Text("Enable")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct StepRow: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.accentColor)
                .clipShape(Circle())

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
