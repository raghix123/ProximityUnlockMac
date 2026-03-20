import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var advertiser: ProximityAdvertiser

    var body: some View {
        Form {
            // MARK: Control
            Section("Advertising") {
                Toggle("Enable ProximityUnlock", isOn: $advertiser.isEnabled)
                Toggle("Require confirmation to unlock", isOn: $advertiser.requiresConfirmation)
                    .onChange(of: advertiser.requiresConfirmation) { _, new in
                        advertiser.confirmationManager.requiresConfirmation = new
                    }
            }

            // MARK: How it works
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Keep this app open (or in background) for unlocking to work.", systemImage: "info.circle")
                    Label("Your iPhone must have Bluetooth enabled.", systemImage: "info.circle")
                    Label("\"Require confirmation\" sends you a notification each time your Mac tries to unlock.", systemImage: "info.circle")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            } header: {
                Text("How It Works")
            }

            // MARK: Bluetooth status
            Section("Bluetooth") {
                LabeledContent("Status") {
                    Text(advertiser.bluetoothStatusDescription)
                        .foregroundStyle(advertiser.bluetoothState == .poweredOn ? .green : .red)
                }
                if advertiser.bluetoothState == .unauthorized {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
