import os

enum Log {
    static let ble       = Logger(subsystem: "com.raghav.ProximityUnlock", category: "BLE")
    static let proximity = Logger(subsystem: "com.raghav.ProximityUnlock", category: "Proximity")
    static let unlock    = Logger(subsystem: "com.raghav.ProximityUnlock", category: "Unlock")
    static let mpc       = Logger(subsystem: "com.raghav.ProximityUnlock", category: "MPC")
    static let ui        = Logger(subsystem: "com.raghav.ProximityUnlock", category: "UI")
}
