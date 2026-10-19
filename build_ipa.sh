#!/bin/bash
# Build an unsigned .app and package it into an .ipa.
# Requires Xcode (not just Command Line Tools) plus an iOS SDK.
#
#   ./build_ipa.sh                 # device build, unsigned
#   TEAM_ID=ABCDE12345 ./build_ipa.sh   # signed build
#
# Install on a device with:  ios-deploy --bundle InvisibleWatermark.ipa
# Or open the .xcarchive in Xcode Organizer for TestFlight / App Store.
set -euo pipefail
cd "$(dirname "$0")"

SCHEME="InvisibleWatermark"
CONFIG="${CONFIG:-Release}"
OUT="build"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "xcodebuild not found. Install Xcode from the App Store, then:" >&2
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

if [ -n "${TEAM_ID:-}" ]; then
  SIGN_ARGS=(
    CODE_SIGN_STYLE=Automatic
    DEVELOPMENT_TEAM="$TEAM_ID"
    CODE_SIGN_IDENTITY="Apple Development"
  )
  echo "Signing with team $TEAM_ID"
else
  SIGN_ARGS=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="")
  echo "Building unsigned (install requires re-signing)"
fi

xcodebuild \
  -project InvisibleWatermark.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -sdk iphoneos \
  -derivedDataPath "$OUT/DerivedData" \
  -destination 'generic/platform=iOS' \
  "${SIGN_ARGS[@]}" \
  build

APP_PATH="$OUT/DerivedData/Build/Products/$CONFIG-iphoneos/$SCHEME.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Build product not found at $APP_PATH" >&2
  exit 1
fi

rm -rf "$OUT/Payload" "$OUT/$SCHEME.ipa"
mkdir -p "$OUT/Payload"
cp -R "$APP_PATH" "$OUT/Payload/"
(cd "$OUT" && zip -qry "$SCHEME.ipa" Payload)

echo ""
echo "IPA: $(pwd)/$OUT/$SCHEME.ipa"
echo "Note: an unsigned IPA only installs on jailbroken devices or after"
echo "      re-signing with a development / distribution certificate."
