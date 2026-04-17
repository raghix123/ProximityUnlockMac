#!/bin/bash
# One-time script to generate the EdDSA signing keypair for Sparkle.
# The private key is stored in your login keychain (never in the repo).
# Copy the printed public key into ProximityUnlockMac/Info.plist → SUPublicEDKey.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="${HOME}/Library/Developer/Xcode/DerivedData"

# Try to find generate_keys in DerivedData (Sparkle puts it there after first build)
TOOL=$(find "$DERIVED_DATA" -name "generate_keys" -path "*/Sparkle*" 2>/dev/null | head -1)

if [[ -z "$TOOL" ]]; then
    # Fallback: look in SPM cache
    TOOL=$(find "${HOME}/Library/Developer/Xcode/DerivedData" \
                "${HOME}/.swiftpm" \
                -name "generate_keys" 2>/dev/null | head -1)
fi

if [[ -z "$TOOL" ]]; then
    echo "❌  Could not locate Sparkle's generate_keys tool."
    echo "   Build the project in Xcode first (so SwiftPM resolves Sparkle),"
    echo "   then re-run this script."
    exit 1
fi

echo "✅  Found generate_keys at: $TOOL"
echo ""
echo "Running generate_keys — your private key will be stored in login Keychain."
echo "Copy the PUBLIC KEY below into ProximityUnlockMac/Info.plist → SUPublicEDKey."
echo "---"
"$TOOL"
