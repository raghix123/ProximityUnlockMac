import Foundation
import os
import Security

/// Manages all Keychain storage and retrieval for pairing keys, identity keys, and password encryption.
/// All items stored with accessibility: .whenUnlockedThisDeviceOnly
class SecureKeyStore {
    static let shared = SecureKeyStore()

    private let service = "com.raghav.ProximityUnlock"

    // MARK: - Identity Key Storage

    /// Store the device's identity signing key material (not the key itself, which is non-exportable on SE)
    func storeIdentityKeyMaterial(_ material: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: material
        ]

        // Delete if exists
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecurityError.keychainError("Failed to store identity key material: \(status)")
        }
    }

    /// Retrieve the device's identity key material
    func retrieveIdentityKeyMaterial(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return data
    }

    // MARK: - Paired Peer Information

    /// Store paired peer's identity public key (65 bytes, x963)
    func storePairedPeerPublicKey(_ publicKey: Data) throws {
        try storeData(publicKey, account: KeychainKey.pairedPeerIdentityPublicKey)
    }

    /// Retrieve paired peer's identity public key
    func retrievePairedPeerPublicKey() -> Data? {
        retrieveData(account: KeychainKey.pairedPeerIdentityPublicKey)
    }

    /// Store the long-term shared key derived during pairing (32 bytes).
    /// Uses .afterFirstUnlock so it can be read while the screen is locked (needed to derive the password decryption key).
    func storePairedSharedKey(_ key: Data) throws {
        try storeData(key, account: KeychainKey.pairedSharedKey, accessible: kSecAttrAccessibleAfterFirstUnlock)
    }

    /// Retrieve the long-term shared key
    func retrievePairedSharedKey() -> Data? {
        retrieveData(account: KeychainKey.pairedSharedKey)
    }

    /// Store encrypted login password (AES-GCM combined representation).
    /// Uses .afterFirstUnlock so it can be read while the screen is locked (the unlock flow reads it while locked).
    func storeEncryptedPassword(_ ciphertext: Data) throws {
        try storeData(ciphertext, account: KeychainKey.macLoginPasswordEncrypted, accessible: kSecAttrAccessibleAfterFirstUnlock)
    }

    /// Retrieve encrypted login password
    func retrieveEncryptedPassword() -> Data? {
        retrieveData(account: KeychainKey.macLoginPasswordEncrypted)
    }

    // MARK: - Unpair (Delete All Pairing Material)

    /// Delete all pairing state and encrypted password (called when user unpairing)
    func deletePairingState() throws {
        let accounts = [
            KeychainKey.pairedPeerIdentityPublicKey,
            KeychainKey.pairedSharedKey,
            KeychainKey.macLoginPasswordEncrypted
        ]

        for account in accounts {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            SecItemDelete(query as CFDictionary)
        }

        // Also clear counters
        UserDefaults.standard.removeObject(forKey: "sendCounter")
        UserDefaults.standard.removeObject(forKey: "receiveCounter")
        UserDefaults.standard.removeObject(forKey: "pairedPeerDisplayName")
    }

    // MARK: - Counter Management (UserDefaults)

    func getSendCounter() -> UInt64 {
        let value = UserDefaults.standard.integer(forKey: "sendCounter")
        return value > 0 ? UInt64(value) : 1
    }

    func setSendCounter(_ counter: UInt64) {
        UserDefaults.standard.set(Int(counter), forKey: "sendCounter")
    }

    func getReceiveCounter() -> UInt64 {
        let value = UserDefaults.standard.integer(forKey: "receiveCounter")
        return UInt64(value)
    }

    func setReceiveCounter(_ counter: UInt64) {
        UserDefaults.standard.set(Int(counter), forKey: "receiveCounter")
    }

    // MARK: - Paired Peer Display Name (UserDefaults)

    func getPairedPeerDisplayName() -> String? {
        UserDefaults.standard.string(forKey: "pairedPeerDisplayName")
    }

    func setPairedPeerDisplayName(_ name: String) {
        UserDefaults.standard.set(name, forKey: "pairedPeerDisplayName")
    }

    // MARK: - Full Reset (Debug)

    /// Delete ALL stored data — identity keys, pairing state, counters, password.
    /// Used to ensure a clean slate on debug builds.
    func deleteAllData() {
        // Delete every Keychain item under our service
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)

        // Clear UserDefaults keys
        for key in ["sendCounter", "receiveCounter", "pairedPeerDisplayName"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        Log.security.info("Deleted all stored data (debug reset)")
    }

    // MARK: - Private Helpers

    private func storeData(_ data: Data, account: String, accessible: CFString = kSecAttrAccessibleWhenUnlockedThisDeviceOnly) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: accessible,
            kSecValueData as String: data
        ]

        // Delete if exists
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecurityError.keychainError("Failed to store data: \(status)")
        }
    }

    private func retrieveData(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return data
    }
}
