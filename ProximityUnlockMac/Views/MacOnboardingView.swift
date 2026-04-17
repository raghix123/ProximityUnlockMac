import SwiftUI
import AppKit

struct MacOnboardingView: View {
    @ObservedObject var monitor: ProximityMonitor
    let onComplete: () -> Void
    @State private var currentStep = 0
    @State private var hasReadDisclaimer = false
    private let totalSteps = 6

    var body: some View {
        VStack(spacing: 0) {
            // Content area — full height, centered
            ZStack {
                switch currentStep {
                case 0: Step0Welcome()
                case 1: Step1SecurityWarning(hasReachedBottom: $hasReadDisclaimer)
                case 2: Step2DeviceSelect(monitor: monitor)
                case 3: Step3Accessibility()
                case 4: Step4Password()
                default: Step5Done()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.25), value: currentStep)

            // Footer
            VStack(spacing: 16) {
                // Page dots
                HStack(spacing: 8) {
                    ForEach(0..<totalSteps, id: \.self) { i in
                        Circle()
                            .fill(i == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: i == currentStep ? 8 : 6, height: i == currentStep ? 8 : 6)
                            .animation(.spring(response: 0.3), value: currentStep)
                    }
                }

                HStack(spacing: 12) {
                    if currentStep > 0 {
                        Button("Back") { withAnimation { currentStep -= 1 } }
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if currentStep < totalSteps - 1 {
                        VStack(spacing: 6) {
                            Button("Next") { withAnimation { currentStep += 1 } }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .disabled(currentStep == 1 && !hasReadDisclaimer)
                            if currentStep == 1 && !hasReadDisclaimer {
                                Text("Scroll down to continue")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .transition(.opacity.animation(.easeOut(duration: 0.25)))
                            }
                        }
                    } else {
                        Button("Get Started") { onComplete() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 28)
            .padding(.top, 12)
        }
        .frame(width: 560, height: 600)
    }
}

// MARK: - Step 0: Welcome

private struct Step0Welcome: View {
    var body: some View {
        VStack(spacing: 28) {
            HeroIcon(systemName: "lock.iphone", color: .blue)

            VStack(spacing: 8) {
                Text("Welcome to ProximityUnlock")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text("Your Mac locks and unlocks based on\nhow close your iPhone is.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                FeaturePill(icon: "iphone.radiowaves.left.and.right", color: .blue,
                            title: "Bluetooth Sensing",
                            description: "Low-energy Bluetooth tracks your iPhone's distance")
                FeaturePill(icon: "lock.fill", color: .orange,
                            title: "Auto Lock",
                            description: "Mac locks when you walk away with your iPhone")
                FeaturePill(icon: "lock.open.fill", color: .green,
                            title: "Auto Unlock",
                            description: "Mac unlocks when you return — no typing needed")
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 40)
        .padding(.top, 36)
    }
}

// MARK: - Step 1: Security Warning

private struct Step1SecurityWarning: View {
    @Binding var hasReachedBottom: Bool
    @State private var showDeleteConfirm = false
    @State private var showScrollHint = true
    @State private var bouncing = false

    var body: some View {
        ZStack(alignment: .bottom) {
        ScrollView {
            VStack(spacing: 24) {
                HeroIcon(systemName: "exclamationmark.triangle.fill", color: .orange)

                VStack(spacing: 6) {
                    Text("Security Disclaimer")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text("Read before continuing.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 10) {
                    WarningRow(
                        icon: "antenna.radiowaves.left.and.right.slash",
                        color: .red,
                        title: "Bluetooth is spoofable",
                        description: "A nearby attacker with the right hardware can broadcast a fake Bluetooth signal that matches your iPhone's name, potentially unlocking your Mac without your knowledge."
                    )
                    WarningRow(
                        icon: "person.fill.questionmark",
                        color: .orange,
                        title: "No identity verification",
                        description: "ProximityUnlock detects signal strength and device name only — it does not verify that the device is actually your iPhone. There is no cryptographic handshake."
                    )
                    WarningRow(
                        icon: "building.2.fill",
                        color: .red,
                        title: "Not for professional or enterprise use",
                        description: "Do not use this app in corporate, healthcare, legal, government, or any regulated environment. It does not meet security compliance requirements such as SOC 2, HIPAA, or FedRAMP."
                    )
                    WarningRow(
                        icon: "lock.open.trianglebadge.exclamationmark",
                        color: .orange,
                        title: "Auto-unlock is a trade-off",
                        description: "Convenience and security are at odds. Automatic unlocking reduces friction, but also lowers the barrier for unauthorized access if your iPhone is lost, stolen, or cloned."
                    )
                }

                VStack(spacing: 6) {
                    Text("Proceed at your own risk.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("This app is best suited for home or personal use where the physical environment is trusted. You accept full responsibility for any security outcomes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(14)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Quit App & Prepare for Deletion", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .alert("Remove ProximityUnlock?", isPresented: $showDeleteConfirm) {
                    Button("Delete Data & Quit", role: .destructive) {
                        if let id = Bundle.main.bundleIdentifier {
                            UserDefaults.standard.removePersistentDomain(forName: id)
                        }
                        KeychainHelper.shared.deletePassword()
                        NSApp.terminate(nil)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("""
                        Since setup isn't complete, no data may have been saved yet — that's fine, just skip any steps below that don't apply.

                        To fully remove ProximityUnlock:
                        1. Move ProximityUnlock.app from your Applications folder to Trash, then empty Trash.
                        2. System Settings › General › Login Items & Extensions — remove ProximityUnlock if listed.
                        3. System Settings › Privacy & Security › Accessibility — remove ProximityUnlock if listed.
                        4. System Settings › Privacy & Security › Bluetooth — remove ProximityUnlock if listed.
                        """)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 28)
            .padding(.bottom, 16)
            .background(
                ScrollBottomDetector(
                    onNeedsScrolling: { needs in
                        withAnimation(.easeOut(duration: 0.3)) {
                            showScrollHint = needs && !hasReachedBottom
                        }
                    },
                    onReachedBottom: {
                        withAnimation(.easeOut(duration: 0.3)) { showScrollHint = false }
                        hasReachedBottom = true
                    }
                )
            )
        }

        if showScrollHint {
            Image(systemName: "chevron.down")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.secondary.opacity(0.55), in: Circle())
                .offset(y: bouncing ? 5 : -3)
                .animation(
                    .easeInOut(duration: 0.55).repeatForever(autoreverses: true),
                    value: bouncing
                )
                .padding(.bottom, 12)
                .allowsHitTesting(false)
                .onAppear { bouncing = true }
                .transition(.opacity.animation(.easeOut(duration: 0.3)))
        }
        } // ZStack
    }
}

private struct WarningRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Step 2: Select Your iPhone

private struct Step2DeviceSelect: View {
    @ObservedObject var monitor: ProximityMonitor

    var body: some View {
        VStack(spacing: 24) {
            HeroIcon(systemName: "iphone.gen3", color: .indigo)

            VStack(spacing: 6) {
                Text("Select Your iPhone")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("Choose your iPhone from nearby Bluetooth devices.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let selected = monitor.selectedDeviceName {
                Label("Selected: \(selected)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline.weight(.semibold))
            }

            if monitor.discoveredDevices.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Scanning for devices…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Make sure Bluetooth is on and your iPhone is unlocked.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ScrollView {
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
                .frame(maxHeight: 240)
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 36)
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
                    Text(RSSIDistance.label(rssi: device.rssi))
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white.opacity(0.75) : .secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.white)
                        .font(.caption.weight(.bold))
                }
            }
            .padding(12)
            .background(isSelected ? Color.accentColor : Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 3: Accessibility Permissions

private struct Step3Accessibility: View {
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var checkTimer: Timer?

    var body: some View {
        VStack(spacing: 24) {
            HeroIcon(
                systemName: accessibilityGranted ? "checkmark.shield.fill" : "lock.shield.fill",
                color: accessibilityGranted ? .green : .purple
            )

            VStack(spacing: 6) {
                Text("Accessibility Permission")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("Required for automatic password entry\nwhen unlocking your Mac.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(accessibilityGranted ? .green : .secondary)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility")
                            .font(.subheadline.weight(.semibold))
                        Text(accessibilityGranted ? "Granted — you're all set" : "Tap Enable, then approve with Touch ID")
                            .font(.caption)
                            .foregroundStyle(accessibilityGranted ? .green : .secondary)
                    }

                    Spacer()

                    if !accessibilityGranted {
                        Button("Enable", action: requestAccessibility)
                            .buttonStyle(.bordered)
                    }
                }
                .padding(14)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Text("macOS will show a dialog with the app pre-selected. Approve it with Touch ID or your password.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 36)
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
        // Lower floating windows so System Settings can appear in front.
        let floatingWindows = NSApp.windows.filter { $0.level == .floating }
        floatingWindows.forEach { $0.level = .normal }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        // One-shot: restore floating level when the user returns to the app.
        // prefix(1) ends the sequence after the first notification — no manual removal needed.
        Task { @MainActor in
            for await _ in NotificationCenter.default
                .notifications(named: NSApplication.didBecomeActiveNotification)
                .prefix(1) {
                floatingWindows.forEach { $0.level = .floating }
            }
        }
    }
}

// MARK: - Step 4: Password

private struct Step4Password: View {
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var passwordMismatch = false
    @State private var showPasswordEntry = false
    @State private var saved = false

    var body: some View {
        VStack(spacing: 24) {
            HeroIcon(systemName: saved ? "key.fill" : "key", color: .yellow)

            VStack(spacing: 6) {
                Text("Save Login Password")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("Store your Mac password for seamless unlock.\nStored securely in the system Keychain.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if saved {
                Label("Password saved in Keychain", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline.weight(.semibold))
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if showPasswordEntry {
                VStack(spacing: 10) {
                    SecureField("Mac login password", text: $password)
                        .textFieldStyle(.roundedBorder)
                    SecureField("Confirm password", text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)

                    if passwordMismatch {
                        Label("Passwords do not match", systemImage: "xmark.circle")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }

                    HStack(spacing: 10) {
                        Button("Cancel") {
                            password = ""
                            confirmPassword = ""
                            passwordMismatch = false
                            showPasswordEntry = false
                        }
                        .foregroundStyle(.secondary)
                        Spacer()
                        Button("Save") { savePassword() }
                            .buttonStyle(.borderedProminent)
                            .disabled(password.isEmpty)
                    }
                }
                .padding(14)
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Button(action: { showPasswordEntry = true }) {
                    Label("Enter Password", systemImage: "lock.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Text("Optional — you can add or change this later in Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .padding(.top, 36)
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

// MARK: - Step 5: Done

private struct Step5Done: View {
    var body: some View {
        VStack(spacing: 28) {
            HeroIcon(systemName: "checkmark.circle.fill", color: .green)

            VStack(spacing: 8) {
                Text("You're All Set!")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text("ProximityUnlock is ready to go.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                SummaryRow(icon: "figure.walk.departure", color: .orange,
                           title: "Walk away",
                           description: "Mac locks when your iPhone moves beyond range")
                SummaryRow(icon: "figure.walk.arrival", color: .green,
                           title: "Walk back",
                           description: "Mac unlocks automatically when you return")
                SummaryRow(icon: "hand.raised.fill", color: .blue,
                           title: "Manual lock respected",
                           description: "Pressing the lock button keeps your Mac locked until you come and go")
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 40)
        .padding(.top, 36)
    }
}

// MARK: - Shared Components

private struct ScrollBottomDetector: NSViewRepresentable {
    let onNeedsScrolling: (Bool) -> Void
    let onReachedBottom: () -> Void

    func makeNSView(context: Context) -> ScrollDetectorNSView {
        let v = ScrollDetectorNSView()
        v.onNeedsScrolling = onNeedsScrolling
        v.onReachedBottom = onReachedBottom
        return v
    }
    func updateNSView(_ nsView: ScrollDetectorNSView, context: Context) {}
}

private class ScrollDetectorNSView: NSView {
    var onNeedsScrolling: ((Bool) -> Void)?
    var onReachedBottom: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { self.setup() }
    }

    private func setup() {
        guard let sv = enclosingScrollView else { return }
        NotificationCenter.default.addObserver(
            self, selector: #selector(didScroll(_:)),
            name: NSScrollView.didLiveScrollNotification, object: sv)
        check(sv)
    }

    @objc private func didScroll(_ note: Notification) {
        guard let sv = note.object as? NSScrollView else { return }
        check(sv)
    }

    private func check(_ sv: NSScrollView) {
        guard let doc = sv.documentView else { return }
        let contentH = doc.frame.height
        let visH = sv.contentSize.height
        let needsScroll = contentH > visH + 10
        DispatchQueue.main.async { self.onNeedsScrolling?(needsScroll) }
        let atBottom = !needsScroll || sv.documentVisibleRect.maxY >= contentH - 30
        if atBottom { DispatchQueue.main.async { self.onReachedBottom?() } }
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}

private struct HeroIcon: View {
    let systemName: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(color.opacity(0.15))
                .frame(width: 88, height: 88)
            Image(systemName: systemName)
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(color)
        }
    }
}

private struct FeaturePill: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct SummaryRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
