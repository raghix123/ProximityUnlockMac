import AppKit
import CoreGraphics
import IOKit.pwr_mgt
import os

/// Handles waking the display and typing the password to unlock the Mac.
///
/// Unlocking via CGEvent requires Accessibility permission, which the user
/// must grant in System Settings > Privacy & Security > Accessibility.
/// The app must NOT be sandboxed — CGEvent posting and pmset require it.
///
/// Lock state tracking: macOS 26 removed CGSSessionScreenIsLocked from
/// CGSessionCopyCurrentDictionary, so we track state via distributed notifications
/// (com.apple.screenIsLocked / com.apple.screenIsUnlocked) instead.
class UnlockManager {

    // MARK: - Lock State (notification-tracked)

    private var _isScreenLocked: Bool = false
    private var lockObserver: NSObjectProtocol?
    private var unlockObserver: NSObjectProtocol?

    init() {
        // Seed initial state from CGSession (works on older macOS; falls back to false on macOS 26+)
        if let dict = CGSessionCopyCurrentDictionary() as? [String: Any] {
            _isScreenLocked = dict["CGSSessionScreenIsLocked"] as? Bool ?? false
        }

        let nc = DistributedNotificationCenter.default()
        lockObserver = nc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Log.unlock.info("Screen lock notification received")
            self?._isScreenLocked = true
        }
        unlockObserver = nc.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Log.unlock.info("Screen unlock notification received")
            self?._isScreenLocked = false
        }
    }

    deinit {
        if let obs = lockObserver   { DistributedNotificationCenter.default().removeObserver(obs) }
        if let obs = unlockObserver { DistributedNotificationCenter.default().removeObserver(obs) }
    }

    // MARK: - Public API

    func isScreenLocked() -> Bool {
        Log.unlock.debug("isScreenLocked: \(self._isScreenLocked, privacy: .public)")
        return _isScreenLocked
    }

    func unlockScreen() {
        Log.unlock.info("Unlocking screen")
        wakeDisplay()
        guard let password = KeychainHelper.shared.getPassword() else {
            Log.unlock.warning("No password stored — cannot unlock")
            return
        }

        // Poll until the login window is ready (up to 5 seconds), then type.
        waitForLoginWindow(timeout: 5.0) {
            self.clickPasswordField()
            // Small delay to let the click register before typing.
            usleep(200_000) // 200ms
            self.typeStringAndSubmit(password)
            // Optimistically mark as unlocked — the distributed notification will
            // confirm once the system actually unlocks.
            self._isScreenLocked = false
        }
    }

    func lockScreen() {
        Log.unlock.info("Locking screen")
        // SACLockScreenImmediate (private ScreenSaver framework) is the correct
        // programmatic lock on macOS 13+. CGSession -suspend was removed in macOS 26.
        let frameworkPath = "/System/Library/PrivateFrameworks/ScreenSaver.framework/ScreenSaver"
        if let handle = dlopen(frameworkPath, RTLD_LAZY),
           let sym = dlsym(handle, "SACLockScreenImmediate") {
            typealias SACFunc = @convention(c) () -> Void
            let lockFn = unsafeBitCast(sym, to: SACFunc.self)
            lockFn()
            // Set immediately — the distributed notification may not fire for programmatic
            // locks on macOS 26, so we can't rely on it alone for state tracking.
            _isScreenLocked = true
        } else {
            Log.unlock.warning("SACLockScreenImmediate unavailable, falling back to pmset")
            let task = Process()
            task.launchPath = "/usr/bin/pmset"
            task.arguments = ["displaysleepnow"]
            try? task.run()
            _isScreenLocked = true
        }
    }

    // MARK: - Private

    private func wakeDisplay() {
        Log.unlock.info("Waking display")
        var assertionID: IOPMAssertionID = 0
        IOPMAssertionDeclareUserActivity(
            "Proximity Unlock" as CFString,
            kIOPMUserActiveLocal,
            &assertionID
        )
    }

    /// Polls `_isScreenLocked` (notification-tracked) until the lock screen is up,
    /// then fires the completion on a background thread.
    private func waitForLoginWindow(timeout: TimeInterval, completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if self._isScreenLocked {
                    Log.unlock.info("Login window detected")
                    // Extra settle time for the login window UI.
                    usleep(500_000) // 500ms
                    completion()
                    return
                }
                usleep(250_000) // poll every 250ms
            }
            // Timeout — try anyway as a best-effort.
            Log.unlock.warning("Login window detection timed out, proceeding anyway")
            completion()
        }
    }

    /// Click the center of the main screen to focus the password field.
    private func clickPasswordField() {
        Log.unlock.info("Clicking password field")
        let source = CGEventSource(stateID: .hidSystemState)
        let screen = NSScreen.main ?? NSScreen.screens.first
        let center = CGPoint(
            x: (screen?.frame.width ?? 1920) / 2,
            y: (screen?.frame.height ?? 1080) / 2
        )
        let mouseDown = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                                mouseCursorPosition: center, mouseButton: .left)
        let mouseUp = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                              mouseCursorPosition: center, mouseButton: .left)
        mouseDown?.post(tap: .cghidEventTap)
        mouseUp?.post(tap: .cghidEventTap)
    }

    private func typeStringAndSubmit(_ text: String) {
        Log.unlock.info("Typing password and submitting")
        guard isAccessibilityGranted() else { return }

        let source = CGEventSource(stateID: .hidSystemState)

        for scalar in text.unicodeScalars {
            guard scalar.value <= UInt16.max else { continue }
            var uniChar = UniChar(scalar.value)

            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &uniChar)
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &uniChar)
                up.post(tap: .cghidEventTap)
            }
            // Small delay between keystrokes so events aren't dropped.
            usleep(20_000) // 20ms
        }

        // Press Return to submit the password.
        let returnDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true)
        returnDown?.post(tap: .cghidEventTap)
        let returnUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)
        returnUp?.post(tap: .cghidEventTap)
    }

    private func isAccessibilityGranted() -> Bool {
        let granted = AXIsProcessTrusted()
        if !granted {
            Log.unlock.warning("Accessibility permission not granted")
        }
        return granted
    }
}
