import AppKit
import CoreGraphics
import IOKit.pwr_mgt

/// Handles waking the display and typing the password to unlock the Mac.
///
/// Unlocking via CGEvent requires Accessibility permission, which the user
/// must grant in System Settings > Privacy & Security > Accessibility.
class UnlockManager {

    // MARK: - Public API

    func isScreenLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return dict["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    func unlockScreen() {
        wakeDisplay()
        guard let password = KeychainHelper.shared.getPassword() else { return }

        // Give the login window time to appear after waking the display.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.typeStringAndSubmit(password)
        }
    }

    func lockScreen() {
        let task = Process()
        task.launchPath = "/usr/bin/pmset"
        task.arguments = ["displaysleepnow"]
        try? task.run()
    }

    // MARK: - Private

    private func wakeDisplay() {
        // IOPMAssertionDeclareUserActivity signals user activity,
        // which wakes the display from sleep/screensaver.
        var assertionID: IOPMAssertionID = 0
        IOPMAssertionDeclareUserActivity(
            "Proximity Unlock" as CFString,
            kIOPMUserActiveLocal,
            &assertionID
        )
    }

    private func typeStringAndSubmit(_ text: String) {
        guard isAccessibilityGranted() else { return }

        let source = CGEventSource(stateID: .hidSystemState)

        for scalar in text.unicodeScalars {
            guard scalar.value <= UInt16.max else { continue }
            var uniChar = UniChar(scalar.value)

            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &uniChar)
                down.post(tap: .cgAnnotatedSessionEventTap)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &uniChar)
                up.post(tap: .cgAnnotatedSessionEventTap)
            }
        }

        // Press Return to submit the password.
        let returnDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true)
        returnDown?.post(tap: .cgAnnotatedSessionEventTap)
        let returnUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)
        returnUp?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }
}
