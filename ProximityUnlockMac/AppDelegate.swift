import AppKit
import Combine
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    var proximityMonitor: ProximityMonitor!
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        proximityMonitor = ProximityMonitor()
        setupStatusBar()

        cancellable = proximityMonitor.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateStatusBarIcon() }
        }
    }

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusBarIcon()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func updateStatusBarIcon() {
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
        updateStatusBarIcon()
    }

    @objc private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
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
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit ProximityUnlock",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
    }
}
