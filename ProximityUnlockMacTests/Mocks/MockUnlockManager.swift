import Foundation
@testable import ProximityUnlockMac

/// Mock unlock manager for unit tests.
/// Records lock/unlock calls and provides controllable isScreenLocked state.
class MockUnlockManager: UnlockManaging {

    // MARK: - Controllable State

    var screenLocked: Bool = true

    // MARK: - Recording

    private(set) var unlockCallCount: Int = 0
    private(set) var lockCallCount: Int = 0

    // MARK: - UnlockManaging

    func isScreenLocked() -> Bool {
        screenLocked
    }

    func unlockScreen() {
        unlockCallCount += 1
        screenLocked = false
    }

    func lockScreen() {
        lockCallCount += 1
        screenLocked = true
    }

    // MARK: - Helpers

    var didUnlock: Bool { unlockCallCount > 0 }
    var didLock: Bool { lockCallCount > 0 }

    func reset() {
        unlockCallCount = 0
        lockCallCount = 0
        screenLocked = true
    }
}
