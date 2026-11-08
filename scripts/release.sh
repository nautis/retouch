#!/bin/zsh
# Builds a universal (Apple silicon + Intel) Retouch.app and zips it for a GitHub release.
#
#   scripts/release.sh <version>
#       Ad-hoc signed. Gatekeeper blocks the first launch on other Macs until the user
#       clicks Open Anyway in System Settings > Privacy & Security.
#
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=<keychain profile> scripts/release.sh <version>
#       Signed with the hardened runtime, notarized and stapled: opens without a warning.
#       The keychain profile comes from `xcrun notarytool store-credentials`.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
VERSION=${1:?usage: scripts/release.sh <version>}

swift build -c release --arch arm64 --arch x86_64 --product Retouch
BIN=.build/out/Products/Release/Retouch          # SwiftPM's multi-arch output (Swift 6.2)
[[ -f "$BIN" ]] || BIN=.build/apple/Products/Release/Retouch   # older toolchains

OUT=build/release
APP=$OUT/Retouch.app
rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Retouch"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"

if [[ ! -f build/AppIcon.icns || scripts/make-icon.swift -nt build/AppIcon.icns ]]; then
  rm -rf build/AppIcon.iconset
  swift scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$APP"
else
  codesign --force --sign - --timestamp=none "$APP"
  echo "ad-hoc signed (set SIGN_IDENTITY and NOTARY_PROFILE for a notarized build)"
fi

ZIP=$OUT/Retouch-$VERSION.zip
ditto -c -k --keepParent "$APP" "$ZIP"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
fi

codesign --verify --deep --strict "$APP"
lipo -info "$APP/Contents/MacOS/Retouch"
shasum -a 256 "$ZIP"
