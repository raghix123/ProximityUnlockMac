import SwiftUI
import CoreBluetooth

struct StatusView: View {
    @EnvironmentObject var advertiser: ProximityAdvertiser
    @State private var pulsing = false

    var body: some View {
        VStack(spacing: 24) {
            // Animated status indicator
            ZStack {
                Circle()
                    .fill(indicatorColor.opacity(0.15))
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulsing ? 1.3 : 1.0)
                    .animation(
                        advertiser.isAdvertising
                            ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                            : .default,
                        value: pulsing
                    )

                Image(systemName: indicatorIcon)
                    .font(.system(size: 48))
                    .foregroundStyle(indicatorColor)
            }
            .onAppear { pulsing = advertiser.isAdvertising }
            .onChange(of: advertiser.isAdvertising) { _, advertising in
                pulsing = advertising
            }

            // Status text
            VStack(spacing: 6) {
                Text(advertiser.bluetoothStatusDescription)
                    .font(.title3.weight(.semibold))
                if advertiser.isConnected {
                    Label("Mac detected your iPhone", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(.background)
    }

    private var indicatorColor: Color {
        switch advertiser.bluetoothState {
        case .poweredOn:
            return advertiser.isConnected ? .green : .blue
        case .poweredOff, .unauthorized:
            return .red
        default:
            return .secondary
        }
    }

    private var indicatorIcon: String {
        switch advertiser.bluetoothState {
        case .poweredOn:
            if advertiser.isConnected { return "iphone.and.arrow.forward" }
            return "iphone.radiowaves.left.and.right"
        case .poweredOff:
            return "iphone.slash"
        case .unauthorized:
            return "lock.iphone"
        default:
            return "iphone"
        }
    }
}
