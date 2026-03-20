import SwiftUI

struct ContentView: View {
    @EnvironmentObject var advertiser: ProximityAdvertiser

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                StatusView()
                Divider()
                SettingsView()
            }
            .navigationTitle("ProximityUnlock")
            .navigationBarTitleDisplayMode(.large)
        }
        // Foreground confirmation sheet — shown when Mac sends an unlock request
        .sheet(isPresented: .init(
            get: { advertiser.pendingUnlockRequest },
            set: { if !$0 { advertiser.deny() } }
        )) {
            ConfirmationView()
        }
    }
}
