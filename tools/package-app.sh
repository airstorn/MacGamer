#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${DIST:-$ROOT/dist}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
APP_NAME="MacGamer"
APP="$DIST/$APP_NAME.app"

cd "$ROOT"
swift build -c release --product MacGamerApp
BIN="$(swift build -c release --product MacGamerApp --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/MacGamerApp" "$APP/Contents/MacOS/MacGamer"
chmod +x "$APP/Contents/MacOS/MacGamer"

shopt -s nullglob
for bundle in "$BIN"/*.bundle; do
  cp -R "$bundle" "$APP/Contents/Resources/"
done
shopt -u nullglob

cp "$ROOT/packaging/Info.plist" "$APP/Contents/Info.plist"

ICONSET="$(mktemp -d /tmp/macgamer-iconset.XXXXXX)"
cleanup() { rm -rf "$ICONSET"; }
trap cleanup EXIT
mkdir -p "$ICONSET/AppIcon.iconset"
swift "$ROOT/tools/make-app-icon.swift" "$ICONSET/master.png"
for spec in "icon_16x16 16" "icon_16x16@2x 32" "icon_32x32 32" "icon_32x32@2x 64" \
            "icon_128x128 128" "icon_128x128@2x 256" "icon_256x256 256" "icon_256x256@2x 512" \
            "icon_512x512 512" "icon_512x512@2x 1024"; do
  set -- $spec
  sips -z "$2" "$2" "$ICONSET/master.png" --out "$ICONSET/AppIcon.iconset/$1.png" >/dev/null
done
iconutil -c icns "$ICONSET/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - --timestamp=none "$APP" >/dev/null

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$APP" "$INSTALL_DIR/$APP_NAME.app"
echo "$INSTALL_DIR/$APP_NAME.app"
