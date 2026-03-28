import Foundation
import MultipeerConnectivity
import UIKit

/// Manages the iOS side of a MultipeerConnectivity session.
///
/// MPC automatically picks the best available transport — WiFi Direct, infrastructure
/// WiFi, or Bluetooth — giving far more reliable message delivery than raw BLE GATT.
/// This manager advertises the "prox-unlock" service so the Mac can find and connect,
/// accepts all incoming invitations from the Mac, and provides a reliable channel for
/// receiving unlock commands and sending confirmations back.
class MultipeerManager: NSObject, ObservableObject {

    // MARK: - Constants

    static let serviceType = "prox-unlock"

    // MARK: - Published State

    @Published var isConnected: Bool = false

    // MARK: - Private

    private let myPeerID = MCPeerID(displayName: UIDevice.current.name)
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!

    // MARK: - Callbacks

    /// Called on the main queue when the Mac sends "unlock_request".
    var onUnlockRequest: (() -> Void)?
    /// Called on the main queue when the Mac sends "lock_event".
    var onLockEvent: (() -> Void)?

    // MARK: - Init

    override init() {
        super.init()
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil,
                                               serviceType: Self.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
    }

    // MARK: - Public API

    /// Sends an approval or denial back to all connected Mac peers reliably.
    func sendConfirmation(approved: Bool) {
        sendMessage(approved ? "approved" : "denied")
    }

    /// Sends a command to all connected Mac peers reliably.
    func sendMessage(_ message: String) {
        guard !session.connectedPeers.isEmpty,
              let data = message.data(using: .utf8) else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    var hasConnectedPeer: Bool { !session.connectedPeers.isEmpty }
}

// MARK: - MCSessionDelegate

extension MultipeerManager: MCSessionDelegate {

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = state == .connected
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async { [weak self] in
            switch message {
            case "unlock_request": self?.onUnlockRequest?()
            case "lock_event":     self?.onLockEvent?()
            default:               break
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

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerManager: MCNearbyServiceAdvertiserDelegate {

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Accept all invitations from any Mac running ProximityUnlock.
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didNotStartAdvertisingPeer error: Error) {}
}
