#!/usr/bin/env bash
set -euo pipefail

echo "==> Building DynamicIsland (Release mode)..."
swift build -c release

echo "==> Packaging DynamicIsland.app bundle..."
mkdir -p DynamicIsland.app/Contents/MacOS
mkdir -p DynamicIsland.app/Contents/Resources

cp .build/release/DynamicIsland DynamicIsland.app/Contents/MacOS/
if [ -d "Resources" ]; then
    cp Resources/*.caf DynamicIsland.app/Contents/Resources/ 2>/dev/null || true
fi
if [ -d ".build/release/DynamicIsland_DynamicIsland.bundle" ]; then
    cp -R .build/release/DynamicIsland_DynamicIsland.bundle DynamicIsland.app/Contents/Resources/
fi

cat << 'EOF' > DynamicIsland.app/Contents/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>DynamicIsland</string>
    <key>CFBundleIdentifier</key>
    <string>com.alexey.dynamicisland</string>
    <key>CFBundleName</key>
    <string>DynamicIsland</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.1.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Dynamic Island needs permission to display and control active media playback from Spotify and Apple Music.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "==> Signing DynamicIsland.app bundle..."
codesign --force --deep --sign - --identifier com.alexey.dynamicisland DynamicIsland.app

echo "==> Terminating running instance if any..."
pkill -f "/Applications/DynamicIsland.app/Contents/MacOS/DynamicIsland" 2>/dev/null || true

echo "==> Installing into /Applications/DynamicIsland.app..."
rm -rf /Applications/DynamicIsland.app
cp -R DynamicIsland.app /Applications/

echo "==> Launching DynamicIsland..."
open /Applications/DynamicIsland.app

echo "==> Installation complete. DynamicIsland is active."
