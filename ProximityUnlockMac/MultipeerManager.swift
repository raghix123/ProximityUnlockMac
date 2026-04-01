import Combine
import Foundation
import MultipeerConnectivity
import os

/// Manages the Mac side of a MultipeerConnectivity session.
///
/// All operational commands (unlock_request, lock_event) require a paired, authenticated peer.
/// Pairing messages are handled by PairingManager before any operational traffic is permitted.
class MultipeerManager: NSObject, ObservableObject, MacMultipeerManaging {

    // MARK: - Constants

    static let serviceType = "prox-unlock"

    // MARK: - Published State

    @Published var isConnected: Bool = false

    // MARK: - Sub-managers

    let pairingManager: PairingManager
    private let messageSigner: MessageSigner

    // MARK: - Private

    private let myPeerID = MCPeerID(displayName: Host.current().localizedName ?? "Mac")
    private var session: MCSession!
    private var browser: MCNearbyServiceBrowser!

    // MARK: - Callbacks

    var onConfirmationReceived: ((Bool) -> Void)?
    var onLockCommand: (() -> Void)?
    var onUnlockCommand: (() -> Void)?

    // MARK: - Init

    override init() {
        self.pairingManager = PairingManager()
        self.messageSigner = MessageSigner(keyProvider: IdentityKeyManager.shared)
        super.init()

        Log.mpc.info("Initializing MPC with peer ID: \(self.myPeerID.displayName, privacy: .public)")
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        browser.delegate = self

        // Wire pairing manager to send messages via MPC
        pairingManager.sendMessage = { [weak self] data in
            self?.sendRaw(data)
        }
        pairingManager.onPaired = { [weak self] in
            Log.pairing.info("Pairing complete — operational channel active")
            // Sync the in-memory replay counter with the just-reset persistent value (0).
            // Without this, messages from iPhone are rejected as replays after re-pairing.
            self?.messageSigner.resetReceiveCounter()
            self?.objectWillChange.send()
        }
        // If pairing times out or fails while the MPC peer is still connected,
        // retry after a brief delay so the user doesn't have to disconnect/reconnect.
        pairingManager.onPairingFailed = { [weak self] _ in
            guard let self, !self.session.connectedPeers.isEmpty else { return }
            Log.pairing.info("Pairing failed with peer still connected — retrying in 2s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, !self.session.connectedPeers.isEmpty else { return }
                // Guard against double-fire: only retry if we're actually unpaired,
                // not if a new pairing handshake already started from a reconnect event.
                guard !self.pairingManager.isPaired else { return }
                guard case .unpaired = self.pairingManager.pairingState else { return }
                self.pairingManager.startPairing()
            }
        }
    }

    func startBrowsing() {
        Log.mpc.info("Starting MPC browsing")
        browser.startBrowsingForPeers()
    }

    func stopBrowsing() {
        Log.mpc.info("Stopping MPC browsing")
        browser.stopBrowsingForPeers()
    }

    // MARK: - Public API

    /// Sends a signed command to paired peers.
    /// Returns true if at least one peer is connected and paired.
    @discardableResult
    func sendCommand(_ command: String) -> Bool {
        guard pairingManager.isPaired else {
            Log.mpc.warning("sendCommand(\(command, privacy: .public)) blocked: not paired")
            return false
        }
        guard !session.connectedPeers.isEmpty else {
            Log.mpc.info("sendCommand(\(command, privacy: .public)) failed: no connected peers")
            return false
        }

        guard let message = try? messageSigner.createSecureMessage(command: command),
              let data = try? JSONEncoder().encode(message) else {
            Log.mpc.error("Failed to create secure message for command: \(command, privacy: .public)")
            return false
        }

        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            Log.mpc.info("sendCommand(\(command, privacy: .public)) succeeded (signed)")
            return true
        } catch {
            Log.mpc.error("sendCommand(\(command, privacy: .public)) error: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    var hasConnectedPeer: Bool { !session.connectedPeers.isEmpty }

    // MARK: - Private

    private func sendRaw(_ data: Data) {
        guard !session.connectedPeers.isEmpty else {
            Log.mpc.warning("sendRaw: no connected peers")
            return
        }
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
            Log.security.error("Message from unknown peer — stale pairing, forcing re-pair")
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pairingManager.unpair()
                if !self.session.connectedPeers.isEmpty {
                    self.pairingManager.startPairing()
                }
            }
            return
        } catch {
            Log.security.error("Message verification failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        DispatchQueue.main.async { [weak self] in
            switch message.command {
            case "approved":        self?.onConfirmationReceived?(true)
            case "denied":          self?.onConfirmationReceived?(false)
            case "lock_command":    self?.onLockCommand?()
            case "unlock_command":  self?.onUnlockCommand?()
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
            self?.isConnected = state == .connected
            guard let self else { return }
            if state == .notConnected {
                // If a pairing handshake was in progress when the peer dropped,
                // cancel only early phases so startPairing() isn't blocked on reconnect.
                // Late phases (.confirming/.deriving) may already have stored keys via
                // finalizePairing(), so don't wipe them — let the timeout handle cleanup.
                if case .pairing(let phase) = self.pairingManager.pairingState {
                    switch phase {
                    case .waitingForPeer, .exchangingKeys, .displayingCode:
                        Log.pairing.info("Peer disconnected mid-handshake — resetting pairing state")
                        self.pairingManager.cancelPairing()
                    case .confirming, .deriving:
                        Log.pairing.info("Peer disconnected during confirmation — not canceling")
                    }
                }
            } else if state == .connected, !self.pairingManager.isPaired {
                Log.pairing.info("New peer connected, starting pairing handshake")
                self.pairingManager.startPairing()
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

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerManager: MCNearbyServiceBrowserDelegate {

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                 withDiscoveryInfo info: [String: String]?) {
        guard info?["app"] == "ProximityUnlock" else {
            Log.mpc.info("Ignoring peer \(peerID.displayName, privacy: .public) — not a ProximityUnlock device")
            return
        }
        Log.mpc.info("Found peer: \(peerID.displayName, privacy: .public)")
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 30)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Log.mpc.info("Lost peer: \(peerID.displayName, privacy: .public)")
    }

    func browser(_ browser: MCNearbyServiceBrowser,
                 didNotStartBrowsingForPeers error: Error) {
        Log.mpc.error("Failed to start browsing: \(error.localizedDescription, privacy: .public)")
    }
}
