#!/bin/bash
# Release script: builds, signs with EdDSA, uploads to GitHub, regenerates appcast.
#
# Usage:
#   ./scripts/release.sh <version> "<release notes>" [--beta]
#
# Example:
#   ./scripts/release.sh 1.0.1 "Fix lock delay on wake"
#   ./scripts/release.sh 1.1.0-beta1 "New sensitivity presets" --beta
#
# Prerequisites:
#   - gh CLI installed and authenticated (brew install gh)
#   - Sparkle's generate_appcast tool available (built automatically after first Xcode build)
#   - EdDSA private key in login Keychain (run scripts/generate_keys.sh once)
#   - Xcode command-line tools installed

set -euo pipefail

VERSION="${1:-}"
NOTES="${2:-}"
BETA="${3:-}"

if [[ -z "$VERSION" || -z "$NOTES" ]]; then
    echo "Usage: $0 <version> \"<release notes>\" [--beta]"
    exit 1
fi

IS_BETA=""
CHANNEL_FLAG=""
if [[ "$BETA" == "--beta" ]]; then
    IS_BETA="yes"
    CHANNEL_FLAG="--channel beta"
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="ProximityUnlockMac"
ARCHIVE_PATH="$REPO_ROOT/build/ProximityUnlock.xcarchive"
EXPORT_PATH="$REPO_ROOT/build/export"
APP_PATH="$EXPORT_PATH/ProximityUnlock.app"
UPDATES_DIR="$REPO_ROOT/updates"
ZIP_NAME="ProximityUnlock-${VERSION}.zip"
ZIP_PATH="$UPDATES_DIR/$ZIP_NAME"
DMG_NAME="ProximityUnlock-${VERSION}.dmg"
DMG_PATH="$REPO_ROOT/build/$DMG_NAME"
TAG="v${VERSION}"
DOWNLOAD_URL="https://github.com/raghix123/ProximityUnlock/releases/download/${TAG}/${ZIP_NAME}"

mkdir -p "$UPDATES_DIR" "$REPO_ROOT/build"

echo "▶ Bumping version to $VERSION..."
/usr/bin/sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = ${VERSION}/" \
    "$REPO_ROOT/ProximityUnlockMac.xcodeproj/project.pbxproj"

BUILD_NUMBER=$(( $(git -C "$REPO_ROOT" rev-list --count HEAD) + 1 ))
/usr/bin/sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*/CURRENT_PROJECT_VERSION = ${BUILD_NUMBER}/" \
    "$REPO_ROOT/ProximityUnlockMac.xcodeproj/project.pbxproj"

echo "▶ Archiving..."
xcodebuild archive \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "platform=macOS" \
    CODE_SIGN_STYLE=Automatic \
    | xcpretty 2>/dev/null || true

echo "▶ Exporting..."
cat > "$REPO_ROOT/build/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$REPO_ROOT/build/ExportOptions.plist" \
    -exportPath "$EXPORT_PATH" \
    | xcpretty 2>/dev/null || true

echo "▶ Zipping for notarization..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

# Notarize + staple so Gatekeeper doesn't warn users on first launch.
# Requires a one-time: xcrun notarytool store-credentials AC_NOTARY \
#     --apple-id <you@icloud.com> --team-id <TEAMID> --password <app-specific-pw>
# Set SKIP_NOTARIZE=1 in the env if you want to ship without notarization (not recommended).
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"
if [[ -z "${SKIP_NOTARIZE:-}" ]]; then
    echo "▶ Submitting to Apple notary service (profile: $NOTARY_PROFILE)..."
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "▶ Stapling ticket onto app..."
    xcrun stapler staple "$APP_PATH"
    echo "▶ Re-zipping with stapled ticket..."
    rm -f "$ZIP_PATH"
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
else
    echo "⚠  SKIP_NOTARIZE=1 — shipping un-notarized build. Gatekeeper will warn users."
fi

echo "▶ Building DMG..."
DMG_STAGING="$REPO_ROOT/build/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
rm -f "$DMG_PATH"
hdiutil create \
    -volname "ProximityUnlock" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"
rm -rf "$DMG_STAGING"

if [[ -z "${SKIP_NOTARIZE:-}" ]]; then
    echo "▶ Notarizing DMG..."
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
fi

echo "▶ Signing with EdDSA + regenerating appcast..."
DERIVED_DATA="${HOME}/Library/Developer/Xcode/DerivedData"
GENERATE_APPCAST=$(find "$DERIVED_DATA" -name "generate_appcast" -path "*/Sparkle*" 2>/dev/null | head -1)
if [[ -z "$GENERATE_APPCAST" ]]; then
    echo "❌  Could not find Sparkle's generate_appcast tool. Build the project first."
    exit 1
fi

if [[ -n "$IS_BETA" ]]; then
    "$GENERATE_APPCAST" "$UPDATES_DIR" \
        --download-url-prefix "https://github.com/raghix123/ProximityUnlock/releases/download/${TAG}/" \
        --channel beta \
        -o "$UPDATES_DIR/appcast-beta.xml"
    cp "$UPDATES_DIR/appcast-beta.xml" "$REPO_ROOT/docs/appcast-beta.xml"
else
    "$GENERATE_APPCAST" "$UPDATES_DIR" \
        --download-url-prefix "https://github.com/raghix123/ProximityUnlock/releases/download/${TAG}/" \
        -o "$UPDATES_DIR/appcast.xml"
    cp "$UPDATES_DIR/appcast.xml" "$REPO_ROOT/docs/appcast.xml"
fi

echo "▶ Committing appcast + version bump..."
git -C "$REPO_ROOT" add docs/ ProximityUnlockMac.xcodeproj/project.pbxproj
git -C "$REPO_ROOT" commit -m "Release $TAG"
git -C "$REPO_ROOT" tag "$TAG"
git -C "$REPO_ROOT" push origin main --tags

echo "▶ Creating GitHub release..."
RELEASE_FLAGS=""
if [[ -n "$IS_BETA" ]]; then
    RELEASE_FLAGS="--prerelease"
fi

gh release create "$TAG" "$ZIP_PATH" "$DMG_PATH" \
    --title "$TAG" \
    --notes "$NOTES" \
    $RELEASE_FLAGS

echo ""
echo "✅  Released $TAG"
echo "   Appcast: https://raghix123.github.io/ProximityUnlockMac/appcast.xml"
echo "   Release: https://github.com/raghix123/ProximityUnlock/releases/tag/${TAG}"
