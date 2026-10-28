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

# Generate Info.plist if missing
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
    <string>1.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "==> Terminating running instance if any..."
pkill -f "/Applications/DynamicIsland.app/Contents/MacOS/DynamicIsland" 2>/dev/null || true

echo "==> Installing into /Applications/DynamicIsland.app..."
rm -rf /Applications/DynamicIsland.app
cp -R DynamicIsland.app /Applications/

echo "==> Launching DynamicIsland..."
open /Applications/DynamicIsland.app

echo "==> Installation complete. DynamicIsland is active."
