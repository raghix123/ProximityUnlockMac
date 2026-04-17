# ProximityUnlock

A macOS menu-bar app that locks your Mac when you walk away with your iPhone and unlocks it when you come back — no typing, no tapping.

Works entirely on-device over Bluetooth Low Energy. No iOS app required; no cloud, no account, no network calls.

## How it works

Your iPhone already broadcasts a BLE advertisement that's unique and stable when paired over classic Bluetooth. ProximityUnlock listens for that advertisement, reads its RSSI (signal strength), and smooths the stream to decide when you're near or far. When you cross the "far" threshold, it runs Apple's private lock API. When you cross the "near" threshold, it wakes the display and types your saved login password via the Accessibility API.

## Requirements

- macOS 26.2 or later
- A Mac with Bluetooth Low Energy
- An iPhone that has been paired with this Mac at least once (so it's a known Bluetooth device)
- Accessibility permission (needed for typing the password at the login screen)

## Install

Download the latest signed build from the [Releases page](https://github.com/raghix123/ProximityUnlockMac/releases) and drag `ProximityUnlock.app` to `/Applications`. Sparkle handles updates from there.

## Build from source

```bash
git clone https://github.com/raghix123/ProximityUnlockMac
cd ProximityUnlockMac
xcodebuild -scheme ProximityUnlockMac -destination 'platform=macOS' build
```

Open `ProximityUnlockMac.xcodeproj` in Xcode to run and debug.

## Permissions & privacy

- **Bluetooth** — macOS prompts on first launch. Used only to scan for advertisements; the app never connects to your iPhone.
- **Accessibility** — granted manually in System Settings → Privacy & Security → Accessibility. Required so the app can type your password at the login window.
- **Keychain** — your Mac login password is stored encrypted in the login keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Never leaves the device.
- **No analytics PII** — the opt-in TelemetryDeck signals only report bucketed threshold values and event counts. No device names, no passwords, no identifiers. Toggle it off under Settings → General → Telemetry.

## Troubleshooting

**My iPhone doesn't appear in the device picker.** Open Control Center → Bluetooth on the iPhone to make sure it's advertising. Then pair it with the Mac once in System Settings → Bluetooth — after that it will show up in ProximityUnlock's list.

**It detects my iPhone but never unlocks.** Make sure Accessibility is granted in System Settings → Privacy & Security → Accessibility, and that you've saved your login password in Settings → Security.

**Unlock/lock triggers too eagerly or too reluctantly.** Adjust the sliders in Settings → Sensitivity. `-65 dBm` is typical for "at your desk"; `-85 dBm` is typical for "one room away." The dead zone between the two thresholds is deliberate — it prevents flicker.

**Mac locked while I was still at my desk.** RSSI is noisy; drop the far threshold a few dBm until it matches your room layout.

## Credits

- Update framework: [Sparkle](https://sparkle-project.org)
- Anonymous analytics: [TelemetryDeck](https://telemetrydeck.com)

## License

Open source. Modify and use freely — please credit.
