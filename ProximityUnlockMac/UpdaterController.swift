import Foundation
import Sparkle
import Combine
import os

@MainActor
final class UpdaterController: NSObject, ObservableObject {

    // Lazy so self is available to pass as the updater delegate.
    private lazy var controller: SPUStandardUpdaterController = {
        let c = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        c.updater.automaticallyChecksForUpdates = self.automaticUpdateChecks
        c.startUpdater()
        return c
    }()

    private var cancellable: AnyCancellable?

    @Published var automaticUpdateChecks: Bool {
        didSet {
            controller.updater.automaticallyChecksForUpdates = automaticUpdateChecks
            UserDefaults.standard.set(automaticUpdateChecks, forKey: "SUEnableAutomaticChecks")
        }
    }
    @Published var updateChannel: UpdateChannel {
        didSet { UserDefaults.standard.set(updateChannel.rawValue, forKey: "updateChannel") }
    }
    @Published var lastUpdateCheckDate: Date?
    @Published var canCheckForUpdates: Bool = false

    enum UpdateChannel: String, CaseIterable, Identifiable {
        case stable, beta
        var id: String { rawValue }
        var displayName: String { self == .stable ? "Stable" : "Beta" }
    }

    override init() {
        let auto = UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") as? Bool ?? true
        let raw = UserDefaults.standard.string(forKey: "updateChannel") ?? "stable"
        self.automaticUpdateChecks = auto
        self.updateChannel = UpdateChannel(rawValue: raw) ?? .stable
        super.init()

        // Trigger lazy controller init now that self is fully available.
        lastUpdateCheckDate = controller.updater.lastUpdateCheckDate
        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
    }

    func checkForUpdates() {
        TelemetryService.updateCheckTriggered(manual: true)
        controller.checkForUpdates(nil)
    }
}

extension UpdaterController: SPUUpdaterDelegate {
    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        let raw = UserDefaults.standard.string(forKey: "updateChannel") ?? "stable"
        return raw == "beta" ? ["beta"] : []
    }

    nonisolated func updater(_ updater: SPUUpdater,
                             didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
                             error: (any Error)?) {
        Task { @MainActor [weak self] in
            self?.lastUpdateCheckDate = updater.lastUpdateCheckDate
        }
    }
}
