import SwiftUI

/// Shown as a modal sheet when the Mac sends an unlock request and the app is in foreground.
struct ConfirmationView: View {
    @EnvironmentObject var advertiser: ProximityAdvertiser
    @State private var pulsing = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Animated lock icon
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 140, height: 140)
                    .scaleEffect(pulsing ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulsing)
                Image(systemName: "lock.open.iphone")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)
            }
            .onAppear { pulsing = true }

            VStack(spacing: 8) {
                Text("Mac Unlock Request")
                    .font(.title2.weight(.bold))
                Text("Your Mac is requesting to unlock the screen.\nAllow?")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            // Action buttons
            VStack(spacing: 12) {
                Button(action: { advertiser.approve() }) {
                    Label("Unlock Mac", systemImage: "lock.open.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button(role: .destructive, action: { advertiser.deny() }) {
                    Label("Deny", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundStyle(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
