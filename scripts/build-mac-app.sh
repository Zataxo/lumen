#!/usr/bin/env bash
#
# Builds the NATIVE macOS Lumen app (the real Mac interface, not the iPad app on Mac).
#
# By default the app is signed "to run locally" (ad-hoc): no Apple Developer account
# needed, runs on this Mac. To share it with other Macs, sign with your team (--team) or
# notarize it; ad-hoc apps from elsewhere are blocked by Gatekeeper until the user allows them.
#
# Usage:
#   scripts/build-mac-app.sh [--debug] [--dmg] [--team <TEAM_ID>] [--output <dir>] [--clean] [--open]
#
#   --debug          Build the Debug configuration (default: Release)
#   --dmg            Also create a .dmg (drag-to-Applications) next to the .zip
#   --team <ID>      Sign with your Apple Development certificate for this team instead of ad-hoc
#   --output <dir>   Where to put the results (default: <project>/build)
#   --clean          Remove previous build products first
#   --open           Launch the built app when done
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT="$PROJECT_DIR/llm.app.xcodeproj"
SCHEME="llm.app"
APP_NAME="Lumen"

CONFIGURATION="Release"
OUTPUT_DIR="$PROJECT_DIR/build"
MAKE_DMG=0
TEAM=""
CLEAN=0
OPEN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) CONFIGURATION="Debug"; shift ;;
    --dmg) MAKE_DMG=1; shift ;;
    --team) TEAM="$2"; shift 2 ;;
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    --clean) CLEAN=1; shift ;;
    --open) OPEN=1; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 64 ;;
  esac
done

DERIVED_DATA="$OUTPUT_DIR/DerivedData-mac"
LOG="$OUTPUT_DIR/build-mac.log"

command -v xcodebuild >/dev/null || { echo "xcodebuild not found. Install Xcode and run: sudo xcode-select -s /Applications/Xcode.app" >&2; exit 1; }

mkdir -p "$OUTPUT_DIR"
[[ $CLEAN -eq 1 ]] && { echo "→ Cleaning previous build products"; rm -rf "$DERIVED_DATA"; }

if [[ -n "$TEAM" ]]; then
  SIGNING=(DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates)
  SIGN_DESC="team $TEAM"
else
  # Ad-hoc ("Sign to Run Locally"): keeps the sandbox entitlements so the app behaves like
  # the real thing, but needs no certificate.
  SIGNING=(CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="")
  SIGN_DESC="ad-hoc (run locally)"
fi

echo "→ Building $APP_NAME for macOS ($CONFIGURATION, signed $SIGN_DESC)…"
echo "  Log: $LOG"
if ! xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA" \
    "${SIGNING[@]}" \
    build > "$LOG" 2>&1; then
  echo "✗ Build failed. Last errors:" >&2
  grep -E "error:" "$LOG" | tail -20 >&2 || tail -40 "$LOG" >&2
  exit 1
fi

BUILT_APP="$(find "$DERIVED_DATA/Build/Products/$CONFIGURATION" -maxdepth 1 -name "*.app" -type d | head -1)"
[[ -n "$BUILT_APP" ]] || { echo "✗ Built .app not found" >&2; exit 1; }

INFO_PLIST="$BUILT_APP/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$INFO_PLIST" 2>/dev/null || echo 1.0)"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$INFO_PLIST" 2>/dev/null || echo 1)"
SUFFIX=""
[[ "$CONFIGURATION" == "Debug" ]] && SUFFIX="-debug"
BASENAME="$APP_NAME-$VERSION($BUILD_NUMBER)$SUFFIX-macOS"

# Ship it as "Lumen.app" (the bundle folder name is what Finder and the Dock show).
APP_PATH="$OUTPUT_DIR/$APP_NAME.app"
rm -rf "$APP_PATH"
ditto "$BUILT_APP" "$APP_PATH"

echo "→ Verifying signature"
codesign --verify --deep --strict "$APP_PATH" || { echo "✗ Signature verification failed" >&2; exit 1; }

ZIP_PATH="$OUTPUT_DIR/$BASENAME.zip"
rm -f "$ZIP_PATH"
echo "→ Packaging $(basename "$ZIP_PATH")"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

if [[ $MAKE_DMG -eq 1 ]]; then
  DMG_PATH="$OUTPUT_DIR/$BASENAME.dmg"
  STAGING="$(mktemp -d)"
  ditto "$APP_PATH" "$STAGING/$APP_NAME.app"
  ln -s /Applications "$STAGING/Applications"
  rm -f "$DMG_PATH"
  echo "→ Creating $(basename "$DMG_PATH")"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null
  rm -rf "$STAGING"
fi

echo "✓ Done:"
echo "  App: $APP_PATH"
echo "  Zip: $ZIP_PATH ($(du -h "$ZIP_PATH" | cut -f1 | xargs))"
[[ $MAKE_DMG -eq 1 ]] && echo "  DMG: $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1 | xargs))"
if [[ -z "$TEAM" ]]; then
  echo "  Ad-hoc signed: runs on this Mac. On another Mac, right-click → Open the first time."
fi

[[ $OPEN -eq 1 ]] && open "$APP_PATH"
exit 0
