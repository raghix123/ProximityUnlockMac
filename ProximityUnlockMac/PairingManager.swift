import Foundation
import CryptoKit
import Combine
import os

/// Manages the Mac side of the pairing handshake.
///
/// Protocol:
///   1. Mac (browser) finds iPhone (advertiser) via MPC — already connected
///   2. Mac sends PairingRequest with its ephemeral + identity public keys
///   3. iPhone sends PairingResponse with its ephemeral + identity public keys
///   4. Both sides derive shared secret via ECDH, compute 6-digit code
///   5. User compares codes on both screens, confirms on both
///   6. Mac sends PairingConfirmation (ECDSA signature over shared data)
///   7. iPhone sends PairingConfirmation
///   8. Both store peer identity key + shared key → paired
@MainActor
class PairingManager: ObservableObject {

    // MARK: - Published State

    @Published var pairingState: PairingState = .unpaired
    @Published var confirmationCode: String = ""
    @Published var pairingError: String?

    // MARK: - Callbacks

    /// Called when pairing completes successfully
    var onPaired: (() -> Void)?
    /// Called when pairing fails or is cancelled
    var onPairingFailed: ((Error) -> Void)?
    /// Called to send a message to the peer via MPC
    var sendMessage: ((Data) -> Void)?

    // MARK: - Private

    private let keyManager: IdentityKeyManager
    private let keyStore = SecureKeyStore.shared
    private var ephemeralKey: P256.KeyAgreement.PrivateKey?
    private var peerEphemeralPublicKeyData: Data?
    private var peerIdentityPublicKeyData: Data?
    private var peerDisplayName: String = ""
    private var derivedSharedSecret: SharedSecret?
    private var pairingTimeout: Timer?

    private let pairingTimeoutSeconds: TimeInterval = 60

    init(keyManager: IdentityKeyManager = .shared) {
        self.keyManager = keyManager
        // Load existing pairing state
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

    /// Initiate pairing with the connected peer.
    func startPairing() {
        guard case .unpaired = pairingState else {
            Log.pairing.warning("Pairing already in progress or paired")
            return
        }

        Log.pairing.info("Starting pairing as initiator (Mac)")
        pairingState = .pairing(phase: .waitingForPeer)
        pairingError = nil

        startPairingTimeout()

        // Generate ephemeral key pair
        let (ephemeral, ephemeralPublicKeyData) = keyManager.generateEphemeralKeyPair()
        self.ephemeralKey = ephemeral

        // Send pairing request
        guard let identityPublicKey = try? keyManager.getIdentityPublicKey() else {
            failPairing(SecurityError.keyGenerationFailed)
            return
        }

        let request = PairingRequest(
            ephemeralPublicKey: ephemeralPublicKeyData,
            identityPublicKey: identityPublicKey,
            displayName: Host.current().localizedName ?? "Mac"
        )

        guard let data = try? JSONEncoder().encode(PairingMessageType.request(request)) else {
            failPairing(SecurityError.networkError("Failed to encode pairing request"))
            return
        }

        pairingState = .pairing(phase: .exchangingKeys)
        sendMessage?(data)
        Log.pairing.info("Sent pairing request")
    }

    /// Called when user confirms the 6-digit code matches.
    func confirmCode() {
        guard case .pairing(let phase) = pairingState,
              case .displayingCode = phase else { return }

        Log.pairing.info("User confirmed pairing code")
        pairingState = .pairing(phase: .confirming)
        sendConfirmation()
    }

    /// Called when user cancels pairing.
    func cancelPairing() {
        Log.pairing.info("Pairing cancelled by user")
        sendCancellation(reason: "User cancelled")
        failPairing(SecurityError.userCancelled)
    }

    /// Called when the MPC peer disconnects mid-handshake (network drop, not user action).
    /// Silently resets state so the next reconnect can start a fresh handshake without
    /// showing a confusing "cancelled by user" error.
    func handlePeerDisconnected() {
        guard case .pairing = pairingState else { return }
        Log.pairing.info("Connection lost mid-pairing — resetting for retry")
        pairingTimeout?.invalidate()
        pairingTimeout = nil
        pairingState = .unpaired
        ephemeralKey = nil
        peerEphemeralPublicKeyData = nil
        peerIdentityPublicKeyData = nil
        derivedSharedSecret = nil
        // pairingError intentionally NOT set — this is a network drop, not a failure
    }

    /// Called when user unpairing from settings.
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

    /// Handle a decoded pairing message received from the peer.
    func handlePairingMessage(_ data: Data) {
        guard let message = try? JSONDecoder().decode(PairingMessageType.self, from: data) else {
            Log.pairing.error("Failed to decode pairing message")
            return
        }

        switch message {
        case .response(let response):
            handlePairingResponse(response)
        case .confirmation(let confirmation):
            handlePairingConfirmation(confirmation)
        case .cancelled(let cancel):
            Log.pairing.info("Peer cancelled pairing: \(cancel.reason, privacy: .public)")
            failPairing(SecurityError.userCancelled)
        case .unpair:
            handleUnpairNotification()
        case .request:
            // Mac is initiator — shouldn't receive a request
            Log.pairing.warning("Mac received pairing request (unexpected)")
        }
    }

    // MARK: - Private Handlers

    private func handlePairingResponse(_ response: PairingResponse) {
        guard case .pairing(let phase) = pairingState,
              case .exchangingKeys = phase else {
            Log.pairing.warning("Received pairing response in unexpected state")
            return
        }

        Log.pairing.info("Received pairing response from \(response.displayName, privacy: .public)")
        peerDisplayName = response.displayName
        peerEphemeralPublicKeyData = response.ephemeralPublicKey
        peerIdentityPublicKeyData = response.identityPublicKey

        // Derive shared secret
        guard let ephemeral = ephemeralKey,
              let sharedSecret = try? keyManager.deriveSharedSecret(
                myEphemeral: ephemeral,
                peerEphemeralPublicKeyData: response.ephemeralPublicKey
              ) else {
            failPairing(SecurityError.sharedSecretFailed)
            return
        }
        derivedSharedSecret = sharedSecret

        // Derive 6-digit confirmation code
        guard let myIdentityKey = try? keyManager.getIdentityPublicKey() else {
            failPairing(SecurityError.keyGenerationFailed)
            return
        }

        let code = MessageSigner.deriveConfirmationCode(
            sharedSecret: sharedSecret,
            macIdentityPublicKey: myIdentityKey,
            iphoneIdentityPublicKey: response.identityPublicKey
        )

        confirmationCode = code
        pairingState = .pairing(phase: .displayingCode(code: code))
        Log.pairing.info("Derived pairing code: \(code, privacy: .public)")
    }

    private func sendConfirmation() {
        guard let myIdentityKey = try? keyManager.getIdentityPublicKey(),
              let peerIdentityKey = peerIdentityPublicKeyData,
              let sharedSecret = derivedSharedSecret else {
            failPairing(SecurityError.keyGenerationFailed)
            return
        }

        // Sign: hash of (myIdentityPublicKey + peerIdentityPublicKey + confirmation code)
        var dataToSign = Data()
        dataToSign.append(myIdentityKey)
        dataToSign.append(peerIdentityKey)
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
        Log.pairing.info("Sent pairing confirmation signature")

        // Derive and store long-term key, store peer identity key
        finalizePairing(sharedSecret: sharedSecret)
    }

    private func handlePairingConfirmation(_ confirmation: PairingConfirmation) {
        // Post-verification: finalizePairing() already transitioned to .paired and stored
        // keys. This method verifies iPhone's ECDSA signature as a security cross-check.
        // If ephemeral state was already cleared (e.g., MPC reconnected after finalize),
        // skip silently — we're already paired and operational.
        guard let peerIdentityKeyData = peerIdentityPublicKeyData,
              let myIdentityKey = try? keyManager.getIdentityPublicKey() else {
            if isPaired {
                Log.pairing.info("Received late confirmation after ephemeral state cleared — already paired")
                return
            }
            failPairing(SecurityError.unknownPeer)
            return
        }

        // Reconstruct what the iPhone should have signed
        var dataToVerify = Data()
        dataToVerify.append(myIdentityKey)        // Mac identity (peer from iPhone's perspective)
        dataToVerify.append(peerIdentityKeyData)   // iPhone identity
        dataToVerify.append(confirmationCode.data(using: .utf8)!)

        guard let peerPublicKey = try? P256.Signing.PublicKey(x963Representation: peerIdentityKeyData),
              let signature = try? P256.Signing.ECDSASignature(derRepresentation: confirmation.identitySignature),
              peerPublicKey.isValidSignature(signature, for: SHA256.hash(data: dataToVerify)) else {
            Log.pairing.error("Peer pairing confirmation signature invalid — unpairing")
            // Keys are already in Keychain from finalizePairing(), so use unpair() (not
            // failPairing()) to clean up both Keychain and in-memory state.
            unpair()
            return
        }

        Log.pairing.info("Peer confirmation signature verified")
    }

    private func finalizePairing(sharedSecret: SharedSecret) {
        guard let myIdentityKey = try? keyManager.getIdentityPublicKey(),
              let peerIdentityKey = peerIdentityPublicKeyData else { return }

        let longTermKey = MessageSigner.deriveLongTermKey(
            sharedSecret: sharedSecret,
            macIdentityPublicKey: myIdentityKey,
            iphoneIdentityPublicKey: peerIdentityKey
        )

        do {
            try keyStore.storePairedSharedKey(longTermKey)
            try keyStore.storePairedPeerPublicKey(peerIdentityKey)
            keyStore.setPairedPeerDisplayName(peerDisplayName)
            // Reset counters for new pairing
            keyStore.setSendCounter(1)
            keyStore.setReceiveCounter(0)
            // Cancel timeout so it doesn't fire failPairing() after a successful pair.
            pairingTimeout?.invalidate()
            pairingTimeout = nil
            // Transition to .paired immediately — matching iOS behavior.
            // Without this, pairingState stays .pairing(.confirming) until iPhone's
            // confirmation arrives, and any MPC disconnect during that window would
            // reset pairing via the disconnect handler, creating a stuck loop.
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
        peerEphemeralPublicKeyData = nil
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
