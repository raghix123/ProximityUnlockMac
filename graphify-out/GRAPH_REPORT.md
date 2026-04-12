# Graph Report - .  (2026-04-11)

## Corpus Check
- 42 files · ~18,490 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 413 nodes · 514 edges · 30 communities detected
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## God Nodes (most connected - your core abstractions)
1. `ProximityMonitorTests` - 22 edges
2. `MultipeerManager` - 21 edges
3. `UnlockConfirmationManagerTests` - 19 edges
4. `SecureKeyStore` - 19 edges
5. `PairingManager` - 17 edges
6. `ProximityMonitor` - 15 edges
7. `SecurityError` - 14 edges
8. `BLECentralManager` - 14 edges
9. `BLECentralManagerTests` - 13 edges
10. `AppDelegate` - 13 edges

## Surprising Connections (you probably didn't know these)
- `ProximityMonitorTests` --inherits--> `XCTestCase`  [EXTRACTED]
  ProximityUnlockMacTests/ProximityMonitorTests.swift →   _Bridges community 3 → community 2_
- `UnlockConfirmationManagerTests` --inherits--> `XCTestCase`  [EXTRACTED]
  ProximityUnlockiOSTests/UnlockConfirmationManagerTests.swift →   _Bridges community 2 → community 6_
- `SecureMessage` --inherits--> `Codable`  [EXTRACTED]
  Shared/CryptoTypes.swift →   _Bridges community 0 → community 13_
- `MultipeerManager` --inherits--> `ObservableObject`  [EXTRACTED]
  ProximityUnlockMac/MultipeerManager.swift →   _Bridges community 9 → community 1_
- `PairingManager` --inherits--> `ObservableObject`  [EXTRACTED]
  ProximityUnlockMac/PairingManager.swift →   _Bridges community 9 → community 11_

## Communities

### Community 0 - "Community 0"
Cohesion: 0.07
Nodes (27): IdentityKeyProviding, KeychainKey, PairingPhase, confirming, deriving, displayingCode, exchangingKeys, waitingForPeer (+19 more)

### Community 1 - "Community 1"
Cohesion: 0.09
Nodes (6): MacMultipeerManaging, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate, MCSessionDelegate, MockMultipeerManager, MultipeerManager

### Community 2 - "Community 2"
Cohesion: 0.08
Nodes (3): BLECentralManagerTests, BLEPeripheralManagerTests, XCTestCase

### Community 3 - "Community 3"
Cohesion: 0.09
Nodes (1): ProximityMonitorTests

### Community 4 - "Community 4"
Cohesion: 0.11
Nodes (9): App, AppDelegate, NSApplicationDelegate, NSMenuDelegate, NSObject, AppDelegate, ProximityUnlockiOSApp, UIApplicationDelegate (+1 more)

### Community 5 - "Community 5"
Cohesion: 0.13
Nodes (1): SecureKeyStore

### Community 6 - "Community 6"
Cohesion: 0.11
Nodes (1): UnlockConfirmationManagerTests

### Community 7 - "Community 7"
Cohesion: 0.2
Nodes (5): ProximityMonitor, ProximityState, far, near, unknown

### Community 8 - "Community 8"
Cohesion: 0.16
Nodes (12): AnyObject, CBPeripheralManager, CBPeripheralManagerProtocol, NotificationCentering, UNUserNotificationCenter, BLECentralManaging, CBCentralManager, CBCentralManagerProtocol (+4 more)

### Community 9 - "Community 9"
Cohesion: 0.12
Nodes (4): BLEPeripheralManager, CBPeripheralManagerDelegate, ObservableObject, ProximityAdvertiser

### Community 10 - "Community 10"
Cohesion: 0.17
Nodes (6): BLECentralManager, BLEConstants, BLECentralManaging, CBCentralManagerDelegate, CBPeripheralDelegate, MockBLECentralManager

### Community 11 - "Community 11"
Cohesion: 0.26
Nodes (1): PairingManager

### Community 12 - "Community 12"
Cohesion: 0.15
Nodes (8): ContentView, PairingCodeConfirmView, PairingInProgressView, PairingPhaseView, PairingSectionView, SettingsView, StatusView, View

### Community 13 - "Community 13"
Cohesion: 0.23
Nodes (12): Codable, PairingCancelled, PairingConfirmation, PairingMessageType, cancelled, confirmation, request, response (+4 more)

### Community 14 - "Community 14"
Cohesion: 0.23
Nodes (1): UnlockManager

### Community 15 - "Community 15"
Cohesion: 0.18
Nodes (12): CodingKey, CodingKeys, command, counter, payload, senderPublicKey, signature, timestamp (+4 more)

### Community 16 - "Community 16"
Cohesion: 0.24
Nodes (2): IdentityKeyManager, IdentityKeyProviding

### Community 17 - "Community 17"
Cohesion: 0.27
Nodes (1): UnlockConfirmationManager

### Community 18 - "Community 18"
Cohesion: 0.35
Nodes (1): KeychainHelper

### Community 19 - "Community 19"
Cohesion: 0.18
Nodes (2): CBPeripheralManagerProtocol, MockCBPeripheralManager

### Community 20 - "Community 20"
Cohesion: 0.22
Nodes (2): MockNotificationCenter, NotificationCentering

### Community 21 - "Community 21"
Cohesion: 0.28
Nodes (1): MessageSigner

### Community 22 - "Community 22"
Cohesion: 0.25
Nodes (2): MockUnlockManager, UnlockManaging

### Community 23 - "Community 23"
Cohesion: 0.25
Nodes (2): CBCentralManagerProtocol, MockCBCentralManager

### Community 24 - "Community 24"
Cohesion: 0.39
Nodes (1): GlobalKeyMonitor

### Community 25 - "Community 25"
Cohesion: 0.5
Nodes (2): BiometricChecking, MockBiometricChecker

### Community 26 - "Community 26"
Cohesion: 0.67
Nodes (2): BiometricChecking, BiometricRecencyChecker

### Community 27 - "Community 27"
Cohesion: 1.0
Nodes (1): Log

### Community 28 - "Community 28"
Cohesion: 1.0
Nodes (1): BLEConstants

### Community 29 - "Community 29"
Cohesion: 1.0
Nodes (0): 

## Knowledge Gaps
- **40 isolated node(s):** `keyGenerationFailed`, `invalidPublicKey`, `sharedSecretFailed`, `signatureFailed`, `verificationFailed` (+35 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Community 27`** (2 nodes): `Logger.swift`, `Log`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 28`** (2 nodes): `BLEConstants.swift`, `BLEConstants`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 29`** (1 nodes): `main.swift`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `MultipeerManager` connect `Community 1` to `Community 9`, `Community 4`?**
  _High betweenness centrality (0.048) - this node is a cross-community bridge._
- **Why does `ProximityMonitor` connect `Community 7` to `Community 9`?**
  _High betweenness centrality (0.025) - this node is a cross-community bridge._
- **Why does `BLEPeripheralManager` connect `Community 9` to `Community 4`?**
  _High betweenness centrality (0.025) - this node is a cross-community bridge._
- **What connects `keyGenerationFailed`, `invalidPublicKey`, `sharedSecretFailed` to the rest of the system?**
  _40 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.07 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.09 - nodes in this community are weakly interconnected._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.08 - nodes in this community are weakly interconnected._