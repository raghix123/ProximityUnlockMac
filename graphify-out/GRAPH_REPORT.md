# Graph Report - .  (2026-04-17)

## Corpus Check
- 21 files · ~49,555 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 226 nodes · 314 edges · 20 communities detected
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## God Nodes (most connected - your core abstractions)
1. `ProximityMonitorTests` - 36 edges
2. `AppDelegate` - 18 edges
3. `BLECentralManagerTests` - 14 edges
4. `TelemetryService` - 13 edges
5. `UpdaterControllerTests` - 12 edges
6. `UnlockManager` - 12 edges
7. `ProximityMonitor` - 11 edges
8. `BLECentralManager` - 11 edges
9. `UpdaterController` - 8 edges
10. `ScrollDetectorNSView` - 8 edges

## Surprising Connections (you probably didn't know these)
- `ProximityMonitorTests` --inherits--> `XCTestCase`  [EXTRACTED]
  ProximityUnlockMacTests/ProximityMonitorTests.swift →   _Bridges community 0 → community 4_
- `UpdateChannel` --inherits--> `Identifiable`  [EXTRACTED]
  ProximityUnlockMac/UpdaterController.swift →   _Bridges community 11 → community 9_
- `UpdaterController` --inherits--> `NSObject`  [EXTRACTED]
  ProximityUnlockMac/UpdaterController.swift →   _Bridges community 9 → community 6_
- `AppDelegate` --inherits--> `NSObject`  [EXTRACTED]
  ProximityUnlockMac/AppDelegate.swift →   _Bridges community 6 → community 2_
- `ProximityMonitor` --inherits--> `ObservableObject`  [EXTRACTED]
  ProximityUnlockMac/ProximityMonitor.swift →   _Bridges community 9 → community 3_

## Communities

### Community 0 - "Community 0"
Cohesion: 0.12
Nodes (1): ProximityMonitorTests

### Community 1 - "Community 1"
Cohesion: 0.14
Nodes (14): DeviceRow, FeaturePill, HeroIcon, MacOnboardingView, Step0Welcome, Step1SecurityWarning, Step2DeviceSelect, Step3Accessibility (+6 more)

### Community 2 - "Community 2"
Cohesion: 0.17
Nodes (3): AppDelegate, NSApplicationDelegate, NSMenuDelegate

### Community 3 - "Community 3"
Cohesion: 0.17
Nodes (6): CustomStringConvertible, ProximityMonitor, ProximityState, far, near, unknown

### Community 4 - "Community 4"
Cohesion: 0.13
Nodes (2): BLECentralManagerTests, XCTestCase

### Community 5 - "Community 5"
Cohesion: 0.26
Nodes (1): TelemetryService

### Community 6 - "Community 6"
Cohesion: 0.18
Nodes (5): BLECentralManager, BLECentralManaging, CBCentralManagerDelegate, MockBLECentralManager, NSObject

### Community 7 - "Community 7"
Cohesion: 0.21
Nodes (1): UpdaterControllerTests

### Community 8 - "Community 8"
Cohesion: 0.23
Nodes (1): UnlockManager

### Community 9 - "Community 9"
Cohesion: 0.19
Nodes (8): CaseIterable, ObservableObject, SPUUpdaterDelegate, String, UpdateChannel, beta, stable, UpdaterController

### Community 10 - "Community 10"
Cohesion: 0.25
Nodes (4): ScrollBottomDetector, ScrollDetectorNSView, NSView, NSViewRepresentable

### Community 11 - "Community 11"
Cohesion: 0.27
Nodes (9): AnyObject, BLECentralManaging, CBCentralManager, CBCentralManagerProtocol, DiscoveredDevice, UnlockManager, UnlockManaging, Equatable (+1 more)

### Community 12 - "Community 12"
Cohesion: 0.29
Nodes (2): MockUnlockManager, UnlockManaging

### Community 13 - "Community 13"
Cohesion: 0.33
Nodes (1): KeychainHelper

### Community 14 - "Community 14"
Cohesion: 0.33
Nodes (2): CBCentralManagerProtocol, MockCBCentralManager

### Community 15 - "Community 15"
Cohesion: 0.67
Nodes (1): RSSIDistance

### Community 16 - "Community 16"
Cohesion: 1.0
Nodes (1): Log

### Community 17 - "Community 17"
Cohesion: 1.0
Nodes (1): LoginItemManager

### Community 18 - "Community 18"
Cohesion: 1.0
Nodes (0): 

### Community 19 - "Community 19"
Cohesion: 1.0
Nodes (0): 

## Knowledge Gaps
- **7 isolated node(s):** `Log`, `stable`, `beta`, `near`, `far` (+2 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `Community 16`** (2 nodes): `Logger.swift`, `Log`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 17`** (2 nodes): `LoginItemManager.swift`, `LoginItemManager`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 18`** (2 nodes): `generate_icon.swift`, `roundedRect()`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.
- **Thin community `Community 19`** (1 nodes): `main.swift`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `UpdaterController` connect `Community 9` to `Community 6`?**
  _High betweenness centrality (0.065) - this node is a cross-community bridge._
- **Why does `AppDelegate` connect `Community 2` to `Community 6`?**
  _High betweenness centrality (0.041) - this node is a cross-community bridge._
- **Why does `ProximityMonitorTests` connect `Community 0` to `Community 4`?**
  _High betweenness centrality (0.036) - this node is a cross-community bridge._
- **What connects `Log`, `stable`, `beta` to the rest of the system?**
  _7 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.12 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.14 - nodes in this community are weakly interconnected._
- **Should `Community 4` be split into smaller, more focused modules?**
  _Cohesion score 0.13 - nodes in this community are weakly interconnected._