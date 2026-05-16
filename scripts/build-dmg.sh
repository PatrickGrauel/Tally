#!/usr/bin/env bash
#
# Build a distributable Tally.dmg. Uses only built-in macOS tooling
# (hdiutil) so no extra Homebrew packages are required.
#
# Usage:
#   ./scripts/build-dmg.sh                    # builds dist/Tally-1.0.0.dmg
#   ./scripts/build-dmg.sh --output ~/Desktop # writes to ~/Desktop instead
#
# What this DOES:
#   • xcodebuild Release archive of Tally.app
#   • Stage Tally.app + a symlink to /Applications in a temp directory
#   • Pack into a compressed read-only .dmg with the version in the name
#
# What this does NOT do (yet):
#   • Code-sign with a Developer ID certificate (the build uses ad-hoc
#     signing; recipients will need to right-click → Open the first time
#     or strip the quarantine attribute manually)
#   • Notarize with Apple
#   • Apply a custom background image / window layout
#
# For public distribution outside the Mac App Store, you'll also want:
#   • A Developer ID Application certificate from your Apple Developer
#     account, and CODE_SIGN_IDENTITY="Developer ID Application: …"
#   • `xcrun notarytool submit dist/Tally-X.Y.Z.dmg --apple-id … --wait`
#   • `xcrun stapler staple dist/Tally-X.Y.Z.dmg`
# See: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution

set -euo pipefail

# ── Args ──────────────────────────────────────────────────────────
OUTPUT_DIR=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            OUTPUT_DIR="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)
            echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

# ── Paths ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_DIR/dist}"
mkdir -p "$OUTPUT_DIR"

# Read the marketing version from project.yml so the DMG filename
# tracks the version we ship without a second source of truth.
VERSION="$(awk -F'"' '/^[[:space:]]*MARKETING_VERSION:/ { print $2; exit }' "$REPO_DIR/project.yml")"
if [[ -z "$VERSION" ]]; then
    echo "Could not read MARKETING_VERSION from project.yml" >&2
    exit 1
fi
DMG_NAME="Tally-$VERSION.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

echo "==> Building Tally $VERSION"

# ── 1. Build the .app ─────────────────────────────────────────────
cd "$REPO_DIR"

# Regenerate Xcode project if xcodegen is installed and project.yml is
# newer than the .xcodeproj. Skipped silently otherwise so contributors
# without xcodegen can still drive the script.
if command -v xcodegen >/dev/null 2>&1; then
    if [[ ! -d "Tally.xcodeproj" ]] || [[ "project.yml" -nt "Tally.xcodeproj" ]]; then
        echo "==> Regenerating Tally.xcodeproj"
        xcodegen generate
    fi
fi

BUILD_DIR="$REPO_DIR/build"
rm -rf "$BUILD_DIR"
echo "==> xcodebuild Release"
xcodebuild \
    -project Tally.xcodeproj \
    -scheme Tally \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGN_IDENTITY="-" \
    build \
    | grep -E "^(\*\* |error:|warning:)" || true

APP_SRC="$BUILD_DIR/Build/Products/Release/Tally.app"
if [[ ! -d "$APP_SRC" ]]; then
    echo "Build did not produce Tally.app at $APP_SRC" >&2
    exit 1
fi

# ── 2. Stage the DMG contents ─────────────────────────────────────
# A scratch directory with Tally.app and a symlink to /Applications,
# so a user dragging Tally onto the Applications shortcut installs it.
STAGE_DIR="$(mktemp -d /tmp/tally-dmg.XXXXXX)"
trap 'rm -rf "$STAGE_DIR"' EXIT

echo "==> Staging $STAGE_DIR"
cp -R "$APP_SRC" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

# ── 3. Build the DMG ──────────────────────────────────────────────
# Use UDZO (compressed read-only) for the smallest possible final
# image. `-ov` overwrites any existing DMG with the same name so the
# script is idempotent.
rm -f "$DMG_PATH"
echo "==> Creating $DMG_NAME"
hdiutil create \
    -volname "Tally $VERSION" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" \
    >/dev/null

# ── 4. Report ─────────────────────────────────────────────────────
SIZE="$(du -h "$DMG_PATH" | awk '{ print $1 }')"
echo
echo "✓ Built $DMG_PATH ($SIZE)"
echo
echo "Recipients can:"
echo "  1. Open the .dmg"
echo "  2. Drag Tally.app onto the Applications shortcut"
echo "  3. First launch: right-click → Open, or run:"
echo "       xattr -dr com.apple.quarantine /Applications/Tally.app"
echo
echo "For a Developer-ID-signed + notarized DMG, see the comments at"
echo "the top of this script."
