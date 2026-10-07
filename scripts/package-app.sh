#!/usr/bin/env bash
# Builds a universal (Apple Silicon + Intel) "Tanks of Doom.app" and zips it for distribution.
#
#   scripts/package-app.sh [version]     # e.g. scripts/package-app.sh 1.0.0
#
# Output: dist/Tanks of Doom.app and dist/TanksOfDoom-<version>-macOS.zip
# The app is ad-hoc signed only (no Developer ID), so Gatekeeper asks players to allow it once.
set -euo pipefail

VERSION="${1:-0.0.0-dev}"
VERSION="${VERSION#v}"
APP_NAME="Tanks of Doom"
EXECUTABLE="TanksOfDoom"
BUNDLE_ID="io.github.dpalmqvist.tanksofdoom"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
ZIP="$DIST/$EXECUTABLE-$VERSION-macOS.zip"

cd "$ROOT"

echo "==> Building $EXECUTABLE $VERSION (arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64 --product "$EXECUTABLE"
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

echo "==> Assembling $APP_NAME.app"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"

# App icon from the cover art.
ICONSET="$DIST/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" docs/images/cover.jpg -s format png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" docs/images/cover.jpg -s format png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.action-games</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP"
codesign --verify --strict "$APP"

echo "==> Zipping"
ditto -c -k --keepParent "$APP" "$ZIP"

lipo -info "$APP/Contents/MacOS/$EXECUTABLE"
echo "==> Done: $ZIP"
