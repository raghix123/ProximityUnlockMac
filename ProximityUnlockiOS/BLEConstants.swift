import CoreBluetooth

/// BLE UUIDs shared between the iOS and Mac apps.
/// Both sides MUST use these exact values.
enum BLEConstants {
    /// Primary service UUID the iPhone advertises and the Mac scans for.
    static let serviceUUID = CBUUID(string: "5F0A4A6E-9DC4-4C57-9A8C-D8BF0B1B0FDE")

    /// Mac writes "unlock_request" or "lock_event" here; iPhone is notified.
    static let unlockRequestCharUUID = CBUUID(string: "A3F1E2D4-5B6C-7A8E-9F0D-1B2C3E4F5A6B")

    /// iPhone writes "approved" or "denied" here; Mac is notified.
    static let unlockConfirmCharUUID = CBUUID(string: "B4E2F3C5-6D7E-8B9F-0A1C-2D3E4F5B6C7A")
}
