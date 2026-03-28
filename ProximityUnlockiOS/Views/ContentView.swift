import SwiftUI

struct ContentView: View {
    @EnvironmentObject var advertiser: ProximityAdvertiser

    var body: some View {
        NavigationStack {
            List {
                // MARK: Status hero
                Section {
                    StatusView()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                // MARK: Pending unlock request (inline, no modal)
                if advertiser.pendingUnlockRequest {
                    Section {
                        Button {
                            advertiser.approve()
                        } label: {
                            Label("Unlock Mac", systemImage: "lock.open.fill")
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(.white)
                                .fontWeight(.semibold)
                                .padding(.vertical, 2)
                        }
                        .listRowBackground(Color.green)

                        Button(role: .destructive) {
                            advertiser.deny()
                        } label: {
                            Label("Deny", systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 2)
                        }
                    } header: {
                        Label("Mac Unlock Request", systemImage: "iphone.and.arrow.forward")
                            .foregroundStyle(.orange)
                    }
                }

                // MARK: Manual Lock / Unlock
                if advertiser.isConnected {
                    Section("Mac Controls") {
                        Button {
                            advertiser.unlockMac()
                        } label: {
                            Label("Unlock Mac", systemImage: "lock.open.fill")
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(.white)
                                .fontWeight(.semibold)
                                .padding(.vertical, 2)
                        }
                        .listRowBackground(Color.green)

                        Button {
                            advertiser.lockMac()
                        } label: {
                            Label("Lock Mac", systemImage: "lock.fill")
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(.white)
                                .fontWeight(.semibold)
                                .padding(.vertical, 2)
                        }
                        .listRowBackground(Color.orange)
                    }
                }

                // MARK: Controls
                Section("Advertising") {
                    Toggle("Enable ProximityUnlock", isOn: $advertiser.isEnabled)
                    Toggle("Require confirmation to unlock", isOn: $advertiser.requiresConfirmation)
                        .onChange(of: advertiser.requiresConfirmation) { _, new in
                            advertiser.confirmationManager.requiresConfirmation = new
                        }
                }

                // MARK: Bluetooth
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

                // MARK: How it works
                Section("How It Works") {
                    Label("Keep this app open or running in the background.", systemImage: "1.circle.fill")
                    Label("Make sure Bluetooth is enabled on both devices.", systemImage: "2.circle.fill")
                    Label("Walk near your Mac — it detects you and unlocks.", systemImage: "3.circle.fill")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("ProximityUnlock")
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}
