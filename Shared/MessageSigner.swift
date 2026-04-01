import Foundation
import CryptoKit

/// Handles cryptographic signing and verification of messages using identity keys.
class MessageSigner {
    private let keyProvider: IdentityKeyProviding
    private let keyStore = SecureKeyStore.shared
    private var lastReceivedCounter: UInt64 = 0

    init(keyProvider: IdentityKeyProviding) {
        self.keyProvider = keyProvider
        self.lastReceivedCounter = keyStore.getReceiveCounter()
    }

    /// Reload the receive counter from persistent storage.
    /// Must be called after pairing finalizes (which resets the counter to 0)
    /// so that the in-memory value matches the new counter baseline.
    func resetReceiveCounter() {
        lastReceivedCounter = keyStore.getReceiveCounter()
    }

    // MARK: - Signing

    /// Create a SecureMessage by signing the command and metadata
    func createSecureMessage(
        command: String,
        payload: Data? = nil
    ) throws -> SecureMessage {
        let senderPublicKey = try keyProvider.getIdentityPublicKey()
        let counter = keyStore.getSendCounter()
        let timestamp = UInt64(Date().timeIntervalSince1970)

        // Increment counter for next message
        keyStore.setSendCounter(counter + 1)

        // Construct signable data
        let signableData = constructSignableData(
            command: command,
            counter: counter,
            timestamp: timestamp,
            payload: payload,
            senderPublicKey: senderPublicKey
        )

        let signature = try keyProvider.sign(signableData)

        return SecureMessage(
            command: command,
            counter: counter,
            timestamp: timestamp,
            payload: payload,
            senderPublicKey: senderPublicKey,
            signature: signature
        )
    }

    // MARK: - Verification

    /// Verify a SecureMessage using the peer's stored public key
    func verifySecureMessage(_ message: SecureMessage) throws {
        // Check the message is from our paired peer
        guard let peerPublicKeyData = keyStore.retrievePairedPeerPublicKey() else {
            throw SecurityError.unknownPeer
        }

        guard message.senderPublicKey == peerPublicKeyData else {
            throw SecurityError.unknownPeer
        }

        // Check replay attack (counter must be strictly increasing)
        guard message.counter > lastReceivedCounter else {
            throw SecurityError.replayDetected
        }

        // Check for suspiciously large gaps (possible missed messages or clock drift)
        // TODO: Log warning once Logger is moved to Shared

        // Verify the signature
        let peerPublicKey = try P256.Signing.PublicKey(x963Representation: peerPublicKeyData)
        let signableData = constructSignableData(
            command: message.command,
            counter: message.counter,
            timestamp: message.timestamp,
            payload: message.payload,
            senderPublicKey: message.senderPublicKey
        )

        let signature = try P256.Signing.ECDSASignature(derRepresentation: message.signature)
        guard peerPublicKey.isValidSignature(signature, for: signableData) else {
            throw SecurityError.invalidSignature
        }

        // Update last received counter
        lastReceivedCounter = message.counter
        keyStore.setReceiveCounter(lastReceivedCounter)
    }

    // MARK: - Pairing Code Generation

    /// Derive a 6-digit numeric comparison code from an ECDH shared secret
    static func deriveConfirmationCode(
        sharedSecret: SharedSecret,
        macIdentityPublicKey: Data,
        iphoneIdentityPublicKey: Data
    ) -> String {
        let derivedKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: "ProximityUnlock-pairing-confirmation".data(using: .utf8)!
                + macIdentityPublicKey
                + iphoneIdentityPublicKey,
            outputByteCount: 4
        )

        let rawValue = derivedKey.withUnsafeBytes { buffer in
            buffer.baseAddress!.assumingMemoryBound(to: UInt32.self).pointee
        }

        let code = String(format: "%06d", rawValue % 1_000_000)
        return code
    }

    /// Derive the long-term shared key used for password encryption and future session keys
    static func deriveLongTermKey(
        sharedSecret: SharedSecret,
        macIdentityPublicKey: Data,
        iphoneIdentityPublicKey: Data
    ) -> Data {
        let derivedKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: "ProximityUnlock-long-term-key".data(using: .utf8)!
                + macIdentityPublicKey
                + iphoneIdentityPublicKey,
            outputByteCount: 32
        )

        return derivedKey.withUnsafeBytes { Data($0) }
    }

    // MARK: - Private

    private func constructSignableData(
        command: String,
        counter: UInt64,
        timestamp: UInt64,
        payload: Data?,
        senderPublicKey: Data
    ) -> Data {
        var data = Data()
        data.append(contentsOf: [UInt8(1)]) // version
        data.append(command.data(using: .utf8)!)
        data.append(contentsOf: withUnsafeBytes(of: counter.bigEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: timestamp.bigEndian) { Data($0) })
        if let payload {
            data.append(payload)
        }
        data.append(senderPublicKey)
        return data
    }
}
