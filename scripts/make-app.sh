#!/bin/bash
# Wrap the swift-built binary in a proper macOS .app bundle so UNUserNotificationCenter
# is available (notifications require Bundle.main.bundleIdentifier).
# Usage: scripts/make-app.sh [debug|release]   (default: release)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
BINARY="$ROOT/.build/arm64-apple-macosx/$CONFIG/ClaudeMon"
APP="$ROOT/.build/ClaudeMon.app"

if [ ! -x "$BINARY" ]; then
  echo "Binary not found at $BINARY." >&2
  echo "Run: swift build -c $CONFIG" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BINARY" "$APP/Contents/MacOS/ClaudeMon"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.andyspamer.claude-mon</string>
    <key>CFBundleName</key>
    <string>claude-mon</string>
    <key>CFBundleDisplayName</key>
    <string>claude-mon</string>
    <key>CFBundleExecutable</key>
    <string>ClaudeMon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc sign — enough for local notifications on macOS 14+. Distribution needs a
# Developer ID; that's a later problem.
codesign --force --sign - "$APP" 2>/dev/null || true

echo "Built: $APP"
echo "Launch:  open '$APP'"
echo "Or run direct to see stderr: '$APP/Contents/MacOS/ClaudeMon'"
