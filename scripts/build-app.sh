#!/usr/bin/env bash
# Moor.app 번들을 dist/ 아래에 생성한다. (Dock 아이콘 없는 메뉴바 앱, ad-hoc 서명)
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Moor"
BUNDLE_ID="com.hwansu.Moor"
APP_DIR="dist/${APP_NAME}.app"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

plutil -lint "$APP_DIR/Contents/Info.plist"
codesign --force --sign - "$APP_DIR"
codesign --verify --verbose "$APP_DIR"

echo "생성 완료: $APP_DIR"
