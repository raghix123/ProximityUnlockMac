import Combine
import Foundation
import MultipeerConnectivity

/// Manages the Mac side of a MultipeerConnectivity session.
///
/// MPC automatically picks the best available transport — WiFi Direct, infrastructure
/// WiFi, or Bluetooth — giving far more reliable message delivery than raw BLE GATT.
/// This manager browses for nearby iPhones advertising the "prox-unlock" service,
/// connects automatically, and provides a reliable channel for unlock commands and
/// confirmation responses alongside BLE RSSI-based proximity sensing.
class MultipeerManager: NSObject, ObservableObject {

    // MARK: - Constants

    static let serviceType = "prox-unlock"

    // MARK: - Published State

    @Published var isConnected: Bool = false

    // MARK: - Private

    private let myPeerID = MCPeerID(displayName: Host.current().localizedName ?? "Mac")
    private var session: MCSession!
    private var browser: MCNearbyServiceBrowser!

    // MARK: - Callbacks

    /// Called on the main queue when the iPhone sends "approved" or "denied".
    var onConfirmationReceived: ((Bool) -> Void)?
    /// Called on the main queue when the iPhone sends "lock_command".
    var onLockCommand: (() -> Void)?
    /// Called on the main queue when the iPhone sends "unlock_command".
    var onUnlockCommand: (() -> Void)?

    // MARK: - Init

    override init() {
        super.init()
        Log.mpc.info("Initializing MPC with peer ID: \(self.myPeerID.displayName, privacy: .public)")
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
    }

    // MARK: - Public API

    /// Sends a command string to all connected peers reliably.
    /// Returns true if at least one peer received the message.
    @discardableResult
    func sendCommand(_ command: String) -> Bool {
        guard !session.connectedPeers.isEmpty,
              let data = command.data(using: .utf8) else {
            Log.mpc.info("sendCommand(\(command, privacy: .public)) failed: no connected peers")
            return false
        }
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            Log.mpc.info("sendCommand(\(command, privacy: .public)) succeeded")
            return true
        } catch {
            Log.mpc.error("sendCommand(\(command, privacy: .public)) error: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    var hasConnectedPeer: Bool { !session.connectedPeers.isEmpty }
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
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = String(data: data, encoding: .utf8) else { return }
        Log.mpc.info("Received message: \(message, privacy: .public) from \(peerID.displayName, privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            switch message {
            case "approved":        self?.onConfirmationReceived?(true)
            case "denied":          self?.onConfirmationReceived?(false)
            case "lock_command":    self?.onLockCommand?()
            case "unlock_command":  self?.onUnlockCommand?()
            default:                break
            }
        }
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
        Log.mpc.info("Found peer: \(peerID.displayName, privacy: .public)")
        // Auto-invite every peer that advertises our service type.
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
