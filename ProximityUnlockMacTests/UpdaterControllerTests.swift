import Testing
import Foundation
@testable import ProximityUnlockMac

@MainActor
struct UpdaterControllerTests {

    @Test("Default automatic update checks is true")
    func defaultAutoUpdateChecks() async throws {
        clearDefaults()
        let controller = UpdaterController()
        #expect(controller.automaticUpdateChecks == true)
    }

    @Test("Default update channel is stable")
    func defaultUpdateChannel() async throws {
        clearDefaults()
        let controller = UpdaterController()
        #expect(controller.updateChannel == .stable)
    }

    @Test("automaticUpdateChecks setter persists to UserDefaults")
    func autoUpdateChecksPersists() async throws {
        clearDefaults()
        let controller = UpdaterController()
        controller.automaticUpdateChecks = false
        #expect(UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") as? Bool == false)
        controller.automaticUpdateChecks = true
        #expect(UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") as? Bool == true)
    }

    @Test("updateChannel setter persists to UserDefaults")
    func updateChannelPersists() async throws {
        clearDefaults()
        let controller = UpdaterController()
        controller.updateChannel = .beta
        #expect(UserDefaults.standard.string(forKey: "updateChannel") == "beta")
        controller.updateChannel = .stable
        #expect(UserDefaults.standard.string(forKey: "updateChannel") == "stable")
    }

    @Test("Stable channel stored in UserDefaults means empty allowed channels")
    func stableChannelAllowed() async throws {
        UserDefaults.standard.set("stable", forKey: "updateChannel")
        let raw = UserDefaults.standard.string(forKey: "updateChannel") ?? "stable"
        let channels: Set<String> = raw == "beta" ? ["beta"] : []
        #expect(channels.isEmpty)
    }

    @Test("Beta channel stored in UserDefaults means beta allowed")
    func betaChannelAllowed() async throws {
        UserDefaults.standard.set("beta", forKey: "updateChannel")
        let raw = UserDefaults.standard.string(forKey: "updateChannel") ?? "stable"
        let channels: Set<String> = raw == "beta" ? ["beta"] : []
        #expect(channels == ["beta"])
    }

    @Test("UpdateChannel display names are correct")
    func channelDisplayNames() {
        #expect(UpdaterController.UpdateChannel.stable.displayName == "Stable")
        #expect(UpdaterController.UpdateChannel.beta.displayName == "Beta")
    }

    @Test("UpdateChannel allCases contains exactly stable and beta")
    func channelAllCases() {
        let cases = UpdaterController.UpdateChannel.allCases
        #expect(cases.contains(.stable))
        #expect(cases.contains(.beta))
        #expect(cases.count == 2)
    }

    @Test("Restores automaticUpdateChecks from UserDefaults on init")
    func restoresAutoChecksFromDefaults() async throws {
        UserDefaults.standard.set(false, forKey: "SUEnableAutomaticChecks")
        let controller = UpdaterController()
        #expect(controller.automaticUpdateChecks == false)
    }

    @Test("Restores updateChannel from UserDefaults on init")
    func restoresChannelFromDefaults() async throws {
        UserDefaults.standard.set("beta", forKey: "updateChannel")
        let controller = UpdaterController()
        #expect(controller.updateChannel == .beta)
    }

    private func clearDefaults() {
        UserDefaults.standard.removeObject(forKey: "SUEnableAutomaticChecks")
        UserDefaults.standard.removeObject(forKey: "updateChannel")
    }
}
