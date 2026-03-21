import CoreBluetooth
import SwiftUI

struct StatusView: View {
    @EnvironmentObject var advertiser: ProximityAdvertiser
    @State private var pulsing = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(indicatorColor.opacity(0.15))
                    .frame(width: 110, height: 110)
                    .scaleEffect(pulsing ? 1.25 : 1.0)
                    .animation(
                        advertiser.isAdvertising
                            ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                            : .default,
                        value: pulsing
                    )

                Image(systemName: indicatorIcon)
                    .font(.system(size: 44))
                    .foregroundStyle(indicatorColor)
            }
            .onAppear { pulsing = advertiser.isAdvertising }
            .onChange(of: advertiser.isAdvertising) { advertising in
                pulsing = advertising
            }

            VStack(spacing: 4) {
                Text(advertiser.bluetoothStatusDescription)
                    .font(.title3.weight(.semibold))
                if advertiser.isConnected {
                    Label("Mac connected", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
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
            return advertiser.isConnected ? "iphone.and.arrow.forward" : "iphone.radiowaves.left.and.right"
        case .poweredOff:
            return "iphone.slash"
        case .unauthorized:
            return "lock.iphone"
        default:
            return "iphone"
        }
    }
}
