#!/bin/zsh
# Builds Retouch.app. Usage: scripts/build-app.sh [install]
#   install: also copies it to /Applications and registers it with Finder's "Open With".
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

swift build -c release --product Retouch

APP=build/Retouch.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Retouch "$APP/Contents/MacOS/Retouch"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [[ ! -f build/AppIcon.icns || scripts/make-icon.swift -nt build/AppIcon.icns ]]; then
  rm -rf build/AppIcon.iconset
  swift scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - --timestamp=none "$APP"
echo "built $APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x Retouch 2>/dev/null || true
  rm -rf /Applications/Retouch.app
  cp -R "$APP" /Applications/Retouch.app
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Retouch.app
  echo "installed /Applications/Retouch.app"
fi
