import Foundation
import MultipeerConnectivity
import UIKit

/// Manages the iOS side of a MultipeerConnectivity session.
///
/// All commands require a paired, authenticated peer. Pairing messages are
/// handled by PairingManager; operational messages are signed SecureMessages.
class MultipeerManager: NSObject, ObservableObject {

    // MARK: - Constants

    static let serviceType = "prox-unlock"

    // MARK: - Published State

    @Published var isConnected: Bool = false

    // MARK: - Sub-managers

    let pairingManager: PairingManager
    private let messageSigner: MessageSigner

    // MARK: - Private

    private let myPeerID = MCPeerID(displayName: UIDevice.current.name)
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!

    // MARK: - Callbacks

    var onUnlockRequest: (() -> Void)?
    var onLockEvent: (() -> Void)?

    // MARK: - Init

    override init() {
        self.pairingManager = PairingManager()
        self.messageSigner = MessageSigner(keyProvider: IdentityKeyManager.shared)
        super.init()

        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID,
                                               discoveryInfo: ["app": "ProximityUnlock"],
                                               serviceType: Self.serviceType)
        advertiser.delegate = self

        pairingManager.sendMessage = { [weak self] data in
            self?.sendRaw(data)
        }
        pairingManager.onPaired = { [weak self] in
            Log.pairing.info("Pairing complete — operational channel active")
            // Sync the in-memory replay counter with the just-reset persistent value (0).
            self?.messageSigner.resetReceiveCounter()
        }
    }

    func startAdvertising() {
        Log.mpc.info("Starting MPC advertising")
        advertiser.startAdvertisingPeer()
    }

    func stopAdvertising() {
        Log.mpc.info("Stopping MPC advertising")
        advertiser.stopAdvertisingPeer()
    }

    // MARK: - Public API

    /// Sends a signed confirmation to all connected Mac peers.
    func sendConfirmation(approved: Bool) {
        Log.mpc.info("Sending confirmation: \(approved ? "approved" : "denied", privacy: .public)")
        sendSignedCommand(approved ? "approved" : "denied")
    }

    /// Sends a signed command (lock/unlock) to all connected Mac peers.
    func sendMessage(_ message: String) {
        sendSignedCommand(message)
    }

    var hasConnectedPeer: Bool { !session.connectedPeers.isEmpty }

    // MARK: - Private

    private func sendSignedCommand(_ command: String) {
        guard pairingManager.isPaired else {
            Log.mpc.warning("sendSignedCommand(\(command, privacy: .public)) blocked: not paired")
            return
        }
        guard !session.connectedPeers.isEmpty else {
            Log.mpc.warning("sendSignedCommand(\(command, privacy: .public)) failed: no connected peers")
            return
        }

        guard let message = try? messageSigner.createSecureMessage(command: command),
              let data = try? JSONEncoder().encode(message) else {
            Log.mpc.error("Failed to create secure message for: \(command, privacy: .public)")
            return
        }

        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            Log.mpc.info("Sent signed command: \(command, privacy: .public)")
        } catch {
            Log.mpc.error("Failed to send '\(command, privacy: .public)': \(error.localizedDescription, privacy: .public)")
        }
    }

    private func sendRaw(_ data: Data) {
        guard !session.connectedPeers.isEmpty else { return }
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            Log.mpc.error("sendRaw error: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handleOperationalMessage(_ data: Data) {
        guard let message = try? JSONDecoder().decode(SecureMessage.self, from: data) else {
            Log.security.warning("Received unparseable operational message")
            return
        }
        do {
            try messageSigner.verifySecureMessage(message)
        } catch SecurityError.unknownPeer {
            Log.security.error("Message from unknown peer — stale pairing, clearing state")
            DispatchQueue.main.async { [weak self] in
                self?.pairingManager.unpair()
                // iPhone is responder — Mac will initiate re-pairing on reconnect
            }
            return
        } catch {
            Log.security.error("Message verification failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        DispatchQueue.main.async { [weak self] in
            switch message.command {
            case "unlock_request": self?.onUnlockRequest?()
            case "lock_event":     self?.onLockEvent?()
            default:
                Log.mpc.warning("Unknown command: \(message.command, privacy: .public)")
            }
        }
    }
}

// MARK: - MCSessionDelegate

extension MultipeerManager: MCSessionDelegate {

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let stateStr: String
        switch state {
        case .notConnected: stateStr = "notConnected"
        case .connecting:   stateStr = "connecting"
        case .connected:    stateStr = "connected"
        @unknown default:   stateStr = "unknown"
        }
        Log.mpc.info("Peer \(peerID.displayName, privacy: .public) state: \(stateStr, privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isConnected = state == .connected
            // If a pairing handshake was in progress when the peer dropped,
            // cancel only early phases. Late phases may have stored keys already.
            if state == .notConnected, case .pairing(let phase) = self.pairingManager.pairingState {
                switch phase {
                case .waitingForPeer, .exchangingKeys, .displayingCode:
                    Log.pairing.info("Peer disconnected mid-handshake — resetting pairing state")
                    self.pairingManager.cancelPairing()
                case .confirming, .deriving:
                    Log.pairing.info("Peer disconnected during confirmation — not canceling")
                }
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Try pairing message first
        if (try? JSONDecoder().decode(PairingMessageType.self, from: data)) != nil {
            Log.pairing.info("Routing pairing message from \(peerID.displayName, privacy: .public)")
            Task { @MainActor [weak self] in
                self?.pairingManager.handlePairingMessage(data)
            }
            return
        }

        // Operational signed message
        handleOperationalMessage(data)
    }

    func session(_ session: MCSession, didReceive stream: InputStream,
                 withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Log.mpc.info("Received invitation from peer: \(peerID.displayName, privacy: .public)")
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didNotStartAdvertisingPeer error: Error) {
        Log.mpc.error("Failed to start advertising: \(error.localizedDescription, privacy: .public)")
    }
}
