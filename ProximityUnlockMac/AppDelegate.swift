import AppKit
import Combine
import os
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    var proximityMonitor: ProximityMonitor
    private var cancellable: AnyCancellable?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var hasCompletedOnboarding: Bool
    let updaterController = UpdaterController()

    override init() {
        self.proximityMonitor = ProximityMonitor()
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedMacOnboarding")
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.ui.info("App launched")
        TelemetryService.start()
        TelemetryService.appLaunched(nearThreshold: proximityMonitor.nearThreshold, farThreshold: proximityMonitor.farThreshold)

        // Show onboarding on first launch
        if !hasCompletedOnboarding {
            // Stay .regular so the onboarding window can come to the front
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showOnboarding()
            }
        } else {
            setupStatusBar()
        }

        cancellable = proximityMonitor.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateStatusBarIcon() }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(sessionDidResignActive),
            name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(sessionDidBecomeActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(screensDidWake),
            name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    @objc private func sessionDidResignActive(_ notification: Notification) {
        Log.ui.info("Session resigned active (Fast User Switch)")
        proximityMonitor.pause()
    }

    @objc private func sessionDidBecomeActive(_ notification: Notification) {
        Log.ui.info("Session became active")
        proximityMonitor.resume()
    }

    @objc private func screensDidWake(_ notification: Notification) {
        Log.ui.info("Screens woke")
        proximityMonitor.handleScreensDidWake()
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusBarIcon()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func updateStatusBarIcon() {
        guard statusItem != nil else { return }  // Status bar not yet created (e.g., during onboarding)

        let symbolName: String
        if !proximityMonitor.isEnabled {
            symbolName = "iphone.slash"
        } else {
            switch proximityMonitor.proximityState {
            case .near:    symbolName = "lock.open.iphone"
            case .far:     symbolName = "lock.iphone"
            case .unknown: symbolName = "iphone"
            }
        }
        statusItem.button?.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "Proximity Unlock"
        )
        statusItem.button?.toolTip = proximityMonitor.statusDescription
    }

    @objc private func toggleEnabled() {
        proximityMonitor.isEnabled.toggle()
        Log.ui.info("Toggled enabled: \(self.proximityMonitor.isEnabled, privacy: .public)")
        updateStatusBarIcon()
    }

    @objc private func openSettings() {
        Log.ui.info("Opening settings")
        if settingsWindow == nil {
            let view = SettingsView()
                .environmentObject(proximityMonitor)
                .environmentObject(updaterController)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "ProximityUnlock Settings"
            window.contentView = NSHostingView(rootView: view)
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func checkForUpdates() { updaterController.checkForUpdates() }

    @objc func showOnboardingFromMenu() {
        Log.ui.info("Showing onboarding from menu")
        onboardingWindow = nil  // force fresh window so new size is applied
        showOnboarding()
    }

    private func showOnboarding() {
        Log.ui.info("Showing onboarding")
        if onboardingWindow == nil {
            let view = MacOnboardingView(monitor: proximityMonitor) { [weak self] in
                self?.completeOnboarding()
            }
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Welcome to ProximityUnlock"
            window.contentView = NSHostingView(rootView: view)
            window.center()
            window.level = .floating
            window.isReleasedWhenClosed = false
            onboardingWindow = window
        }
        onboardingWindow?.makeKeyAndOrderFront(nil)
        onboardingWindow?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func completeOnboarding() {
        Log.ui.info("Onboarding completed")
        UserDefaults.standard.set(true, forKey: "hasCompletedMacOnboarding")
        hasCompletedOnboarding = true
        onboardingWindow?.close()
        onboardingWindow = nil
        setupStatusBar()
        // Auto-open settings after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.openSettings()
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let statusTitle = proximityMonitor.statusDescription
        let statusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)

        if proximityMonitor.isPhoneDetected {
            let rssiItem = NSMenuItem(title: "Signal: \(proximityMonitor.rssi) dBm", action: nil, keyEquivalent: "")
            rssiItem.isEnabled = false
            menu.addItem(rssiItem)
        }

        menu.addItem(.separator())

        let toggleTitle = proximityMonitor.isEnabled ? "Disable" : "Enable"
        menu.addItem(NSMenuItem(title: toggleTitle, action: #selector(toggleEnabled), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Setup Guide...", action: #selector(showOnboardingFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit ProximityUnlock",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
    }
}
