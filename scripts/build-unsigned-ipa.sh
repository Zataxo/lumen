#!/usr/bin/env bash
#
# Builds an UNSIGNED Lumen .ipa for iPhone/iPad.
#
# The result is not installable as-is: sign it afterwards (e.g. AltStore, Sideloadly,
# `codesign` + a provisioning profile, or your distribution tool of choice).
#
# Usage:
#   scripts/build-unsigned-ipa.sh [--debug] [--output <dir>] [--clean]
#
#   --debug         Build the Debug configuration (default: Release)
#   --output <dir>  Where to put the .ipa (default: <project>/build)
#   --clean         Remove previous build products first
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$PROJECT_DIR/llm.app.xcodeproj"
SCHEME="llm.app"
APP_NAME="Lumen"

CONFIGURATION="Release"
OUTPUT_DIR="$PROJECT_DIR/build"
CLEAN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) CONFIGURATION="Debug"; shift ;;
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    --clean) CLEAN=1; shift ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 64 ;;
  esac
done

DERIVED_DATA="$OUTPUT_DIR/DerivedData"
STAGING="$OUTPUT_DIR/ipa-staging"
LOG="$OUTPUT_DIR/build.log"

command -v xcodebuild >/dev/null || { echo "xcodebuild not found. Install Xcode and run: sudo xcode-select -s /Applications/Xcode.app" >&2; exit 1; }

mkdir -p "$OUTPUT_DIR"
if [[ $CLEAN -eq 1 ]]; then
  echo "→ Cleaning previous build products"
  rm -rf "$DERIVED_DATA" "$STAGING"
fi

echo "→ Building $APP_NAME ($CONFIGURATION, iOS device, unsigned)…"
echo "  Log: $LOG"
if ! xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -sdk iphoneos \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGN_ENTITLEMENTS="" \
    DEVELOPMENT_TEAM="" \
    build > "$LOG" 2>&1; then
  echo "✗ Build failed. Last errors:" >&2
  grep -E "error:" "$LOG" | tail -20 >&2 || tail -40 "$LOG" >&2
  exit 1
fi

APP_PATH="$(find "$DERIVED_DATA/Build/Products/$CONFIGURATION-iphoneos" -maxdepth 1 -name "*.app" -type d | head -1)"
if [[ -z "$APP_PATH" ]]; then
  echo "✗ Built .app not found in $DERIVED_DATA/Build/Products/$CONFIGURATION-iphoneos" >&2
  exit 1
fi

INFO_PLIST="$APP_PATH/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$INFO_PLIST" 2>/dev/null || echo 1.0)"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$INFO_PLIST" 2>/dev/null || echo 1)"
SUFFIX=""
[[ "$CONFIGURATION" == "Debug" ]] && SUFFIX="-debug"
IPA_PATH="$OUTPUT_DIR/$APP_NAME-$VERSION($BUILD_NUMBER)$SUFFIX-unsigned.ipa"

echo "→ Packaging $(basename "$APP_PATH") → $(basename "$IPA_PATH")"
rm -rf "$STAGING"
mkdir -p "$STAGING/Payload"
# ditto keeps symlinks, permissions and extended attributes intact.
ditto "$APP_PATH" "$STAGING/Payload/$(basename "$APP_PATH")"
# Make sure no stale signature from an earlier signed build sneaks in.
rm -rf "$STAGING/Payload/$(basename "$APP_PATH")/_CodeSignature" \
       "$STAGING/Payload/$(basename "$APP_PATH")/embedded.mobileprovision"

rm -f "$IPA_PATH"
(cd "$STAGING" && /usr/bin/zip -qry "$IPA_PATH" Payload)
rm -rf "$STAGING"

SIZE="$(du -h "$IPA_PATH" | cut -f1 | xargs)"
echo "✓ Done: $IPA_PATH ($SIZE)"
echo "  Unsigned — sign it before installing on a device."
