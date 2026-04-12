import SwiftUI

// MARK: - Root

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            WelcomePage(onNext: { withAnimation { page = 1 } })
                .tag(0)
            PermissionsPage(onNext: { withAnimation { page = 2 } })
                .tag(1)
            PairPage(onDone: { hasCompletedOnboarding = true })
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .background(Color(.systemBackground).ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button("Skip") { hasCompletedOnboarding = true }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 56)  // clears Dynamic Island on all iPhones
                .padding(.trailing, 24)
        }
    }
}

// MARK: - Page 1: Welcome

private struct WelcomePage: View {
    let onNext: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 60)

                OnboardingHeroIcon(systemName: "lock.iphone", color: .blue)
                    .padding(.bottom, 32)

                VStack(spacing: 12) {
                    Text("ProximityUnlock")
                        .font(.largeTitle.bold())
                    Text("Unlock your Mac the moment you walk up to it — automatically and securely.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)

                VStack(alignment: .leading, spacing: 28) {
                    OnboardingFeatureRow(
                        icon: "iphone.radiowaves.left.and.right",
                        color: .blue,
                        title: "Bluetooth Detection",
                        description: "Your iPhone broadcasts a signal your Mac uses to sense when you're near."
                    )
                    OnboardingFeatureRow(
                        icon: "faceid",
                        color: .green,
                        title: "Face ID Protected",
                        description: "Every unlock is confirmed with biometrics before it happens."
                    )
                    OnboardingFeatureRow(
                        icon: "wifi",
                        color: .purple,
                        title: "No Internet Needed",
                        description: "Commands travel directly over peer-to-peer Wi-Fi — nothing leaves your network."
                    )
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 100)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Divider()
                Button("Get Started", action: onNext)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 20)
                    .background(Color(.systemBackground))
            }
        }
    }
}

// MARK: - Page 2: Permissions

private struct PermissionsPage: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            OnboardingHeroIcon(systemName: "checkmark.shield.fill", color: .blue)
                .padding(.bottom, 32)

            VStack(spacing: 12) {
                Text("Two Permissions")
                    .font(.largeTitle.bold())
                Text("ProximityUnlock needs these to keep your Mac secure.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)

            VStack(spacing: 12) {
                PermissionCard(
                    icon: "antenna.radiowaves.left.and.right",
                    color: .blue,
                    title: "Bluetooth",
                    description: "Broadcasts your iPhone's presence so your Mac can detect proximity."
                )
                PermissionCard(
                    icon: "faceid",
                    color: .green,
                    title: "Face ID",
                    description: "Verifies your identity before approving each Mac unlock request."
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            Button("Continue", action: onNext)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
        }
    }
}

// MARK: - Page 3: Pair

private struct PairPage: View {
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            OnboardingHeroIcon(systemName: "laptopcomputer.and.iphone", color: .green)
                .padding(.bottom, 32)

            VStack(spacing: 12) {
                Text("Connect to Your Mac")
                    .font(.largeTitle.bold())
                Text("Open the Mac app to complete setup. It only takes a moment.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)

            VStack(alignment: .leading, spacing: 20) {
                OnboardingStepRow(number: 1, text: "Open ProximityUnlockMac on your Mac.")
                OnboardingStepRow(number: 2, text: "Bring your iPhone near — a 6-digit code appears on both screens.")
                OnboardingStepRow(number: 3, text: "Confirm the codes match on both devices.")
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 24)

            Spacer()

            Button("Get Started", action: onDone)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
        }
    }
}

// MARK: - Shared Components

private struct OnboardingHeroIcon: View {
    let systemName: String
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.12))
                .frame(width: 140, height: 140)
            Image(systemName: systemName)
                .font(.system(size: 60))
                .foregroundStyle(color)
        }
    }
}

private struct OnboardingFeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.subheadline)
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

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct OnboardingStepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.accentColor)
                .clipShape(Circle())
            Text(text)
                .font(.subheadline)
        }
    }
}
