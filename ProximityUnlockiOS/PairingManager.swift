import Foundation
import CryptoKit
import UIKit

/// Manages the iPhone side of the pairing handshake (responder role).
///
/// Protocol mirror of Mac PairingManager:
///   1. Receives PairingRequest from Mac
///   2. Sends PairingResponse with its own ephemeral + identity keys
///   3. Both sides compute 6-digit code, user compares
///   4. User confirms on both devices
///   5. Mac sends PairingConfirmation first
///   6. iPhone sends PairingConfirmation back
///   7. Both store long-term keys → paired
@MainActor
class PairingManager: ObservableObject {

    // MARK: - Published State

    @Published var pairingState: PairingState = .unpaired
    @Published var confirmationCode: String = ""
    @Published var pairingError: String?

    // MARK: - Callbacks

    var onPaired: (() -> Void)?
    var onPairingFailed: ((Error) -> Void)?
    var sendMessage: ((Data) -> Void)?

    // MARK: - Private

    private let keyManager: IdentityKeyManager
    private let keyStore = SecureKeyStore.shared
    private var ephemeralKey: P256.KeyAgreement.PrivateKey?
    private var peerIdentityPublicKeyData: Data?
    private var peerDisplayName: String = ""
    private var derivedSharedSecret: SharedSecret?
    private var pairingTimeout: Timer?

    private let pairingTimeoutSeconds: TimeInterval = 60

    init(keyManager: IdentityKeyManager? = nil) {
        let keyManager = keyManager ?? IdentityKeyManager.shared
        self.keyManager = keyManager
        if let peerName = keyStore.getPairedPeerDisplayName(),
           keyStore.retrievePairedPeerPublicKey() != nil {
            pairingState = .paired(peerName: peerName)
        }
    }

    // MARK: - Public API

    var isPaired: Bool {
        if case .paired = pairingState { return true }
        return false
    }

    /// Called when user confirms the 6-digit code matches.
    func confirmCode() {
        guard case .pairing(let phase) = pairingState,
              case .displayingCode = phase else { return }

        Log.pairing.info("User confirmed pairing code")
        pairingState = .pairing(phase: .confirming)
        sendConfirmation()
    }

    func cancelPairing() {
        Log.pairing.info("Pairing cancelled by user")
        sendCancellation(reason: "User cancelled")
        failPairing(SecurityError.userCancelled)
    }

    func unpair() {
        Log.pairing.info("Unpairing")
        let notification = UnpairNotification()
        if let data = try? JSONEncoder().encode(PairingMessageType.unpair(notification)) {
            sendMessage?(data)
        }
        try? keyStore.deletePairingState()
        pairingState = .unpaired
        confirmationCode = ""
    }

    // MARK: - Message Handling

    func handlePairingMessage(_ data: Data) {
        guard let message = try? JSONDecoder().decode(PairingMessageType.self, from: data) else {
            Log.pairing.error("Failed to decode pairing message")
            return
        }

        switch message {
        case .request(let request):
            handlePairingRequest(request)
        case .confirmation(let confirmation):
            handlePairingConfirmation(confirmation)
        case .cancelled(let cancel):
            Log.pairing.info("Mac cancelled pairing: \(cancel.reason, privacy: .public)")
            failPairing(SecurityError.userCancelled)
        case .unpair:
            handleUnpairNotification()
        case .response:
            Log.pairing.warning("iPhone received pairing response (unexpected)")
        }
    }

    // MARK: - Private Handlers

    private func handlePairingRequest(_ request: PairingRequest) {
        Log.pairing.info("Received pairing request from \(request.displayName, privacy: .public)")
        // Always clear old Keychain state before starting a fresh handshake, whether we were
        // .paired or stuck mid-.pairing. This prevents stale keys from surviving a failed
        // re-pair attempt (which would leave Keychain and in-memory state out of sync).
        if case .unpaired = pairingState {
            // Already clean — nothing to delete
        } else {
            Log.pairing.info("Clearing old pairing state before fresh handshake")
            try? keyStore.deletePairingState()
        }
        pairingState = .pairing(phase: .exchangingKeys)
        pairingError = nil
        startPairingTimeout()

        peerIdentityPublicKeyData = request.identityPublicKey
        peerDisplayName = request.displayName

        // Generate our ephemeral key pair
        let (ephemeral, ephemeralPublicKeyData) = keyManager.generateEphemeralKeyPair()
        self.ephemeralKey = ephemeral

        guard let myIdentityKey = try? keyManager.getIdentityPublicKey() else {
            failPairing(SecurityError.keyGenerationFailed)
            return
        }

        // Derive shared secret
        guard let sharedSecret = try? keyManager.deriveSharedSecret(
            myEphemeral: ephemeral,
            peerEphemeralPublicKeyData: request.ephemeralPublicKey
        ) else {
            failPairing(SecurityError.sharedSecretFailed)
            return
        }
        derivedSharedSecret = sharedSecret

        // Send response
        let response = PairingResponse(
            ephemeralPublicKey: ephemeralPublicKeyData,
            identityPublicKey: myIdentityKey,
            displayName: UIDevice.current.name
        )

        guard let data = try? JSONEncoder().encode(PairingMessageType.response(response)) else {
            failPairing(SecurityError.networkError("Failed to encode pairing response"))
            return
        }
        sendMessage?(data)

        // Derive confirmation code
        // Note: Mac is "mac" in the derivation function regardless of who initiates
        let code = MessageSigner.deriveConfirmationCode(
            sharedSecret: sharedSecret,
            macIdentityPublicKey: request.identityPublicKey,   // Mac identity = first arg
            iphoneIdentityPublicKey: myIdentityKey              // iPhone identity = second arg
        )

        confirmationCode = code
        pairingState = .pairing(phase: .displayingCode(code: code))
        Log.pairing.info("Derived pairing code: \(code, privacy: .public)")
    }

    private func sendConfirmation() {
        guard let myIdentityKey = try? keyManager.getIdentityPublicKey(),
              let peerIdentityKey = peerIdentityPublicKeyData else {
            failPairing(SecurityError.keyGenerationFailed)
            return
        }

        // Sign same data the Mac signed: (macIdentityKey + iphoneIdentityKey + code)
        // From iPhone's perspective: peerIdentityKey = Mac = first arg, myIdentityKey = iPhone = second arg
        var dataToSign = Data()
        dataToSign.append(peerIdentityKey)   // Mac identity
        dataToSign.append(myIdentityKey)     // iPhone identity
        dataToSign.append(confirmationCode.data(using: .utf8)!)

        guard let signature = try? keyManager.sign(dataToSign) else {
            failPairing(SecurityError.signatureFailed)
            return
        }

        let confirmation = PairingConfirmation(identitySignature: signature)
        guard let data = try? JSONEncoder().encode(PairingMessageType.confirmation(confirmation)) else {
            failPairing(SecurityError.networkError("Failed to encode confirmation"))
            return
        }
        sendMessage?(data)

        // Finalize pairing
        guard let sharedSecret = derivedSharedSecret else {
            failPairing(SecurityError.sharedSecretFailed)
            return
        }
        finalizePairing(
            sharedSecret: sharedSecret,
            macIdentityKey: peerIdentityKey,
            iphoneIdentityKey: myIdentityKey
        )
    }

    private func handlePairingConfirmation(_ confirmation: PairingConfirmation) {
        // Mac sent their confirmation — verify
        guard let peerIdentityKeyData = peerIdentityPublicKeyData,
              let myIdentityKey = try? keyManager.getIdentityPublicKey() else {
            failPairing(SecurityError.unknownPeer)
            return
        }

        // Mac signed: (macIdentityKey + iphoneIdentityKey + code)
        var dataToVerify = Data()
        dataToVerify.append(peerIdentityKeyData)   // Mac identity
        dataToVerify.append(myIdentityKey)          // iPhone identity
        dataToVerify.append(confirmationCode.data(using: .utf8)!)

        guard let peerPublicKey = try? P256.Signing.PublicKey(x963Representation: peerIdentityKeyData),
              let signature = try? P256.Signing.ECDSASignature(derRepresentation: confirmation.identitySignature),
              peerPublicKey.isValidSignature(signature, for: SHA256.hash(data: dataToVerify)) else {
            Log.pairing.error("Mac pairing confirmation signature invalid")
            failPairing(SecurityError.invalidSignature)
            return
        }

        Log.pairing.info("Mac confirmation signature verified")
        // If pairing already finalized (we confirmed first), just update state
        if case .pairing = pairingState {
            // Finalize now if we haven't yet
            if let sharedSecret = derivedSharedSecret {
                finalizePairing(
                    sharedSecret: sharedSecret,
                    macIdentityKey: peerIdentityKeyData,
                    iphoneIdentityKey: myIdentityKey
                )
            }
        }
    }

    private func finalizePairing(
        sharedSecret: SharedSecret,
        macIdentityKey: Data,
        iphoneIdentityKey: Data
    ) {
        let longTermKey = MessageSigner.deriveLongTermKey(
            sharedSecret: sharedSecret,
            macIdentityPublicKey: macIdentityKey,
            iphoneIdentityPublicKey: iphoneIdentityKey
        )

        do {
            try keyStore.storePairedSharedKey(longTermKey)
            try keyStore.storePairedPeerPublicKey(macIdentityKey)
            keyStore.setPairedPeerDisplayName(peerDisplayName)
            keyStore.setSendCounter(1)
            keyStore.setReceiveCounter(0)
            pairingTimeout?.invalidate()
            pairingState = .paired(peerName: peerDisplayName)
            Log.pairing.info("Pairing finalized with \(self.peerDisplayName, privacy: .public)")
            onPaired?()
        } catch {
            failPairing(error)
        }
    }

    private func handleUnpairNotification() {
        Log.pairing.info("Received unpair notification from peer")
        try? keyStore.deletePairingState()
        pairingState = .unpaired
        confirmationCode = ""
    }

    private func sendCancellation(reason: String) {
        let cancel = PairingCancelled(reason: reason)
        if let data = try? JSONEncoder().encode(PairingMessageType.cancelled(cancel)) {
            sendMessage?(data)
        }
    }

    private func failPairing(_ error: Error) {
        pairingTimeout?.invalidate()
        pairingError = error.localizedDescription
        pairingState = .unpaired
        ephemeralKey = nil
        peerIdentityPublicKeyData = nil
        derivedSharedSecret = nil
        onPairingFailed?(error)
    }

    private func startPairingTimeout() {
        pairingTimeout?.invalidate()
        pairingTimeout = Timer.scheduledTimer(withTimeInterval: pairingTimeoutSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if case .pairing = self.pairingState {
                    Log.pairing.warning("Pairing timed out")
                    self.failPairing(SecurityError.timeout)
                }
            }
        }
    }
}
